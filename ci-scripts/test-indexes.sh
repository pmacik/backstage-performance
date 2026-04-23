#!/bin/bash -x
set -o nounset
set -o errexit
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$SCRIPT_DIR"/../test.env)"

indexes_dir="$(readlink -m "$SCRIPT_DIR/../ci-scripts/db-indexes")"

export INDEXES_ENABLED=${INDEXES_ENABLED:-false}
export RHDH_NAMESPACE=${RHDH_NAMESPACE:-rhdh-performance}

export ARTIFACT_DIR
ARTIFACT_DIR=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${ARTIFACT_DIR:-$($SCRIPT_DIR/../_ARTIFACTS.indexes/.artifacts.indexes_${INDEXES_ENABLED}.$(date +%Y%m%d_%H%M%S))}")
make clean-all |& tee clean.log.txt

mkdir -p $ARTIFACT_DIR
mv clean.log.txt $ARTIFACT_DIR/clean.log

./ci-scripts/setup.sh |& tee $ARTIFACT_DIR/setup.log

oc port-forward -n $RHDH_NAMESPACE $(oc -n $RHDH_NAMESPACE get pods -l postgres-operator.crunchydata.com/instance-set=primary -o name) 5432:5432 &
export PG_PID=$!
trap "kill $PG_PID" EXIT

export POSTGRES_USER="$(oc -n $RHDH_NAMESPACE get secret rhdh-db-credentials -o json | jq -rc '.data.POSTGRES_USER | @base64d')"
export POSTGRES_PASSWORD="$(oc -n $RHDH_NAMESPACE get secret rhdh-db-credentials -o json | jq -rc '.data.POSTGRES_PASSWORD | @base64d')"
export POSTGRES_DATABASE_NAME=backstage_plugin_catalog
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432

pushd $indexes_dir
while ! node db-setup.js; do
    sleep 10s
    echo "Retrying database setup..."
done

if [ "${INDEXES_ENABLED}" == "true" ]; then
    while ! node db-recreate-indexes.js; do
        sleep 10s
        echo "Retrying index recreation..."
    done
fi

node db-reset.js
popd

./ci-scripts/test.sh |& tee $ARTIFACT_DIR/test.log

./ci-scripts/collect-results.sh |& tee $ARTIFACT_DIR/collect-results.log
pushd $indexes_dir
REPORT_FILE="$ARTIFACT_DIR/db-queries.html" node db-report.js
popd
