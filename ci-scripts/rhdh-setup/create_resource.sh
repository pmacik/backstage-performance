#!/bin/bash

export TMP_DIR WORKDIR

POPULATION_CONCURRENCY=${POPULATION_CONCURRENCY:-10}
COMPONENT_SHARD_SIZE=${COMPONENT_SHARD_SIZE:-50000}

TMP_DIR=${TMP_DIR:-$(readlink -m .tmp)}
mkdir -p "$TMP_DIR"
WORKDIR=$(readlink -m .)

kc_lockfile="$TMP_DIR/kc.lockfile"

keycloak_url() {
  f="$TMP_DIR/keycloak.url"
  exec 4>"$kc_lockfile"
  flock 4 || {
    echo "Failed to acquire lock"
    exit 1
  }

  if [ ! -f "$f" ]; then
    echo -n "https://$(oc get routes keycloak -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 4
  cat "$f"
  set +x
}

bs_lockfile="$TMP_DIR/bs.lockfile"

backstage_url() {
  f="$TMP_DIR/backstage.url"
  exec 5>"$bs_lockfile"
  flock 5 || {
    echo "Failed to acquire lock"
    exit 1
  }
  if [ ! -f "$f" ]; then
    echo -n "https://$(oc get routes "${RHDH_HELM_RELEASE_NAME}-developer-hub" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.host}')" >"$f"
  fi
  flock -u 5
  cat "$f"
}

create_per_grp() {
  echo "Creating entity YAML files"
  varname=$2
  obj_count=${!varname}
  if [[ -z ${!varname} ]]; then
    echo "$varname is not set: Skipping $1 "
    exit 1
  fi
  local iter_count mod
  iter_count=$(echo "(${obj_count}/${GROUP_COUNT})" | bc)
  mod=$(echo "(${obj_count}%${GROUP_COUNT})" | bc)

  if [[ ! ${mod} -eq 0 ]]; then
    iter_count=$(echo "${iter_count}+1" | bc)
  fi
  indx=0
  shard_index=0
  for _ in $(seq 1 "${iter_count}"); do
    for g in $(seq 1 "${GROUP_COUNT}"); do
      indx=$((1 + indx))
      [[ ${obj_count} -lt $indx ]] && break
      $1 "$g" "$indx" "$shard_index"
      if [ "$(echo "(${indx}%${COMPONENT_SHARD_SIZE})" | bc)" == "0" ]; then
        shard_index=$((shard_index + 1))
      fi
    done
  done
}

clone_and_upload() {
  echo "Uploading entities to GitHub"
  git_str="${GITHUB_USER}:${GITHUB_TOKEN}@github.com"
  base_name=$(basename "$GITHUB_REPO")
  git_dir=$TMP_DIR/${base_name}
  git_repo=${GITHUB_REPO//github.com/${git_str}}
  [[ -d "${git_dir}" ]] && rm -rf "${git_dir}"
  git clone "$git_repo" "$git_dir"
  cd "$git_dir" || return
  git config user.name "rhdh-performance-bot"
  git config user.email rhdh-performance-bot@redhat.com
  tmp_branch=$(mktemp -u XXXXXXXXXX)
  git checkout -b "$tmp_branch"
  mapfile -t files < <(find "$TMP_DIR" -name "$1")
  for filename in "${files[@]}"; do
    mv -vf "$filename" "$(basename "$filename")"
    git add "$(basename "$filename")"
  done
  git commit -a -m "commit objects"
  git push -f --set-upstream origin "$tmp_branch"
  cd ..
  sleep 5
  for filename in "${files[@]}"; do
    upload_url="${GITHUB_REPO%.*}/blob/${tmp_branch}/$(basename "$filename")"
    curl -k "$(backstage_url)/api/catalog/locations" -X POST -H 'Accept-Encoding: gzip, deflate, br' -H 'Content-Type: application/json' --data-raw '{"type":"url","target":"'"${upload_url}"'"}'
  done
}

# shellcheck disable=SC2016
create_api() {
  export grp_indx=$1
  export api_indx=$2
  export shard_indx=${3:-0}
  envsubst '${grp_indx} ${api_indx}' <"$WORKDIR/template/component/api.template" >>"$TMP_DIR/api-$shard_indx.yaml"
}

# shellcheck disable=SC2016
create_cmp() {
  export grp_indx=$1
  export cmp_indx=$2
  export shard_indx=${3:-0}
  envsubst '${grp_indx} ${cmp_indx}' <"$WORKDIR/template/component/component.template" >>"$TMP_DIR/component-$shard_indx.yaml"
}

create_group() {
  token=$(get_token)
  groupname="group${0}"
  curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/groups" \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '"$token" \
    --data-raw '{"name": "'"${groupname}"'"}' |& tee -a "$TMP_DIR/create_group.log"
  echo "Group $groupname created" >>"$TMP_DIR/create_group.log"
}

create_groups() {
  echo "Creating Groups in Keycloak"
  sleep 5
  seq 1 "${GROUP_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_group'
}

create_user() {
  token=$(get_token)
  grp=$(echo "${0}%${GROUP_COUNT}" | bc)
  [[ $grp -eq 0 ]] && grp=${GROUP_COUNT}
  username="test${0}"
  groupname="group${grp}"
  curl -s -k --location --request POST "$(keycloak_url)/auth/admin/realms/backstage/users" \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '"$token" \
    --data-raw '{"firstName":"'"${username}"'","lastName":"tester", "email":"'"${username}"'@test.com", "enabled":"true", "username":"'"${username}"'","groups":["/'"${groupname}"'"]}' |& tee -a "$TMP_DIR/create_user.log"
  echo "User $username ($groupname) created" >>"$TMP_DIR/create_user.log"
}

create_users() {
  echo "Creating Users in Keycloak"
  export GROUP_COUNT
  sleep 5
  seq 1 "${BACKSTAGE_USER_COUNT}" | xargs -n1 -P"${POPULATION_CONCURRENCY}" bash -c 'create_user'
}

token_lockfile="$TMP_DIR/token.lockfile"
log_token() {
  token_log="$TMP_DIR/get_token.log"
  echo "[$(date --utc -Ins)] $1" >>"$token_log"
}

get_token() {
  token_log="$TMP_DIR/get_token.log"
  token_file=$TMP_DIR/token.json
  while ! mkdir "$token_lockfile" 2>/dev/null; do
    sleep 0.5s
  done
  #shellcheck disable=SC2064
  trap "rm -rf $token_lockfile; exit" INT TERM EXIT HUP

  timeout_timestamp=$(date -d "60 seconds" "+%s")
  while [ ! -f "$token_file" ] || [ ! -s "$token_file" ] || [ "$(date +%s)" -gt "$(jq -rc '.expires_in_timestamp' "$token_file")" ]; do
    log_token "refreshing keycloak token"
    keycloak_pass=$(oc -n "${RHDH_NAMESPACE}" get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}' | base64 -d)
    curl -s -k "$(keycloak_url)/auth/realms/master/protocol/openid-connect/token" -d username=admin -d "password=${keycloak_pass}" -d 'grant_type=password' -d 'client_id=admin-cli' | jq -r ".expires_in_timestamp = $(date -d '30 seconds' +%s)" >"$token_file"
    if [ "$(date "+%s")" -gt "$timeout_timestamp" ]; then
      log_token "ERROR: Timeout getting keycloak token"
      exit 1
    else
      log_token "Re-attempting to get keycloak token"
      sleep 5s
    fi
  done

  rm -rf "$token_lockfile"
  jq -rc '.access_token' "$token_file"
}

export -f keycloak_url backstage_url backstage_url get_token create_group create_user log_token
export kc_lockfile bs_lockfile token_lockfile
