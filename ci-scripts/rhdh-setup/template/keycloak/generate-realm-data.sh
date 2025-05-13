#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Generating KeyCloak realm data files ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

pushd "$SCRIPT_DIR/../../../.."
read -ra bs_users_groups <<<"1:1 10:2 10:10 100:25 1000:250"
for bu_bg in "${bs_users_groups[@]}"; do
  IFS=":" read -ra tokens <<<"${bu_bg}"
  bu="${tokens[0]}"
  [[ "${#tokens[@]}" == 1 ]] && bg="" || bg="${tokens[1]}"
  echo "export SCENARIO=mvp
export DURATION=10m
export WAIT_FOR_SEARCH_INDEX=false
export PRE_LOAD_DB=true
export KEYCLOAK_USER_PASS=changeme
export AUTH_PROVIDER=keycloak
export RHDH_INSTALL_METHOD=helm
export RHDH_HELM_REPO=https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.6-72-CI/installation
export RHDH_IMAGE_REGISTRY=quay.io
export RHDH_IMAGE_REPO=rhdh/rhdh-hub-rhel9
export RHDH_IMAGE_TAG=1.6-88
export ENABLE_RBAC=true
export RHDH_LOG_LEVEL=debug
export BACKSTAGE_USER_COUNT=$bu
export GROUP_COUNT=$bg" >test.env
  make clean-all |& tee clean.log
  ./ci-scripts/setup.sh |& tee setup.log
  ./ci-scripts/rhdh-setup/template/keycloak/export-keycloak-realm.sh
done
read -ra bs_users_groups <<<"1000:500"
for bu_bg in "${bs_users_groups[@]}"; do
  IFS=":" read -ra tokens <<<"${bu_bg}"
  bu="${tokens[0]}"
  [[ "${#tokens[@]}" == 1 ]] && bg="" || bg="${tokens[1]}"
  echo "export SCENARIO=mvp
export DURATION=10m
export WAIT_FOR_SEARCH_INDEX=false
export PRE_LOAD_DB=true
export KEYCLOAK_USER_PASS=changeme
export AUTH_PROVIDER=keycloak
export RHDH_INSTALL_METHOD=helm
export RHDH_HELM_REPO=https://raw.githubusercontent.com/rhdh-bot/openshift-helm-charts/refs/heads/redhat-developer-hub-1.6-72-CI/installation
export RHDH_IMAGE_REGISTRY=quay.io
export RHDH_IMAGE_REPO=rhdh/rhdh-hub-rhel9
export RHDH_IMAGE_TAG=1.6-88
export ENABLE_RBAC=true
export RBAC_POLICY=user_in_multiple_groups
export RHDH_LOG_LEVEL=debug
export BACKSTAGE_USER_COUNT=$bu
export GROUP_COUNT=$bg" >test.env
  make clean-all |& tee clean.log
  ./ci-scripts/setup.sh |& tee setup.log
  ./ci-scripts/rhdh-setup/template/keycloak/export-keycloak-realm.sh
done
popd
