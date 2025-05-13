#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo -e "\n === Exporting KeyCloak realm ===\n"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR"/../../../../test.env)"

ARTIFACT_DIR=$(readlink -m "${ARTIFACT_DIR:-.artifacts}")
mkdir -p "${ARTIFACT_DIR}"

export TMP_DIR

TMP_DIR=$(readlink -m "${TMP_DIR:-.tmp}")
mkdir -p "${TMP_DIR}"

oc exec -n rhdh-performance keycloak-0 -- /bin/bash -c '/opt/eap/bin/standalone.sh -c standalone-openshift.xml -Djboss.http.port=8081 -Djboss.https.port=8444 -Djboss.ajp.port=8010 -Djboss.management.http.port=9991 -Djboss.as.management.blocking.timeout=600 -Dkeycloak.migration.action=export -Dkeycloak.migration.provider=singleFile -Dkeycloak.migration.realmName=backstage -Dkeycloak.migration.usersExportStrategy=REALM_FILE -Dkeycloak.migration.file=/tmp/backstage-realm.json' &
PID=$!
sleep 5m
kill -SIGINT $PID

oc cp rhdh-performance/keycloak-0:/tmp/backstage-realm.json "ci-scripts/rhdh-setup/template/keycloak/backstage-realm.${BACKSTAGE_USER_COUNT}u-${GROUP_COUNT}g.json"

tar -czf ci-scripts/rhdh-setup/template/keycloak/backstage-realm.${BACKSTAGE_USER_COUNT}u-${GROUP_COUNT}g.json.tar.gz -C ci-scripts/rhdh-setup/template/keycloak backstage-realm.${BACKSTAGE_USER_COUNT}u-${GROUP_COUNT}g.json

# pushd "$TMP_DIR"
# kc_tar="kc.tar.gz"
# curl -sSL -o "$kc_tar" https://github.com/keycloak/keycloak/releases/download/26.2.4/keycloak-26.2.4.tar.gz
# tar -xvf "$kc_tar"
# rm -rvf "$kc_tar"
# kc_dir=$(find -name 'keycloak-*' -type d)
# kc_adm="$kc_dir/bin/kcadm.sh"
# kc_host="$(oc get route/keycloak -n rhdh-performance -o json | jq -rc '.status.ingress[0].host')"

# keychain="$TMP_DIR/keycloak-keychain.jks"
# truststore="$TMP_DIR/keycloak-truststore.jks"
# storepass=changeme

# rm -rvf "$truststore"
# rm -rvf "$keychain"
# rm -rvf "$TMP_DIR/kc_cert-*.crt"
# openssl s_client -showcerts -connect "$kc_host:443" -servername "$kc_host" </dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >"$keychain"
# csplit -z -f "$TMP_DIR/kc_cert-" -b "%02d.crt" "$keychain" '/-----BEGIN CERTIFICATE-----/' '{*}'

# for crt in "$TMP_DIR"/kc_cert-*.crt; do
#   alias=$(basename "$crt" .crt)
#   keytool -import -noprompt -trustcacerts \
#     -alias "$alias" \
#     -file "$crt" \
#     -keystore "$truststore" \
#     -storepass "$storepass"
# done
# export KC_OPTS="-Djavax.net.ssl.trustStore=$truststore -Djavax.net.ssl.trustStorePassword=$storepass"

# $kc_adm config credentials --server "https://$kc_host/auth" --realm master --user "$(oc get secret credential-rhdh-sso -n rhdh-performance -o json | jq -rc '.data.ADMIN_USERNAME' | base64 -d)" --password "$(oc get secret credential-rhdh-sso -n rhdh-performance -o json | jq -rc '.data.ADMIN_PASSWORD' | base64 -d)"

# $kc_adm get realms/backstage >"$TMP_DIR/backstage-realm.json"
# popd
