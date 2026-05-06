#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

WATCHES=${WATCHES:-true}
FILTERS=${FILTERS:-false}
MEMORY_LIMITS=${MEMORY_LIMITS:-1Gi}
WORKLOAD_TEMPLATE_NAMES=${WORKLOADS_TEMPLATE_NAMES:-default}

IFS=" " read -ra watches <<<"${WATCHES}"
IFS=" " read -ra filters <<<"${FILTERS}"
IFS=" " read -ra memory_limits <<<"${MEMORY_LIMITS}"
IFS=" " read -ra workload_template_names <<<"${WORKLOAD_TEMPLATE_NAMES}"

export RHDH_OLM_INDEX_IMAGE=${RHDH_OLM_INDEX_IMAGE:-quay.io/rhdh/iib:1.10-v4.21-x86_64}
export RHDH_INSTALL_METHOD=olm
export NUMBER_OF_RUNS=${NUMBER_OF_RUNS:-10}
export NUMBER_OF_USERS_PER_RUN=${NUMBER_OF_USERS_PER_RUN:-2000}
export NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN=${NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN:-2000}

function log() {
    echo
    echo "/---------------------------------------------------------- "
    echo "| $1"
    echo "/---------------------------------------------------------- "
}

for t in "${workload_template_names[@]}"; do
    for w in "${watches[@]}"; do
        for cf in "${filters[@]}"; do
            for m in "${memory_limits[@]}"; do
                oc login --username "$OPENSHIFT_USERNAME" --password "$OPENSHIFT_PASSWORD" "$OPENSHIFT_API" --insecure-skip-tls-verify=true
                export ARTIFACT_DIR="$(readlink -m "$SCRIPT_DIR/../../_ARTIFACTS.dev-sandbox/.artifacts.dev-sandbox.1_10.watch_$w.filters_$cf.$m.$t.$(date +%Y%m%d-%H%M%S --utc)")"
                mkdir -p $ARTIFACT_DIR
                echo
                echo "/---------------------------------------------------------- "
                echo "| Release test parameters:"
                echo "|   watch: $w"
                echo "|   filters: $cf"
                echo "|   memory limit: $m"
                echo "|   workload template name: $t"
                echo "|   number of runs: $NUMBER_OF_RUNS"
                echo "|   number of users per run: $NUMBER_OF_USERS_PER_RUN"
                echo "|   number of users with workloads per run: $NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN"
                echo "/---------------------------------------------------------- "
                export RHDH_WORKLOADS_TEMPLATE_NAME="$t"
                export RHDH_OLM_WATCH_EXT_CONF="$w"
                export RHDH_OLM_ENABLE_CACHE_LABEL_FILTER="$cf"
                export RHDH_OLM_OPERATOR_RESOURCES_MEMORY_LIMITS="$m"
                log "Re-deploying RHDH Operator..."
                make undeploy deploy |& tee $ARTIFACT_DIR/ci-setup.log
                log "Running release test..."
                make ci-test |& tee $ARTIFACT_DIR/ci-test.log
                log "Collecting results..."
                make collect-results |& tee $ARTIFACT_DIR/collect-results.log
            done
        done
    done
done
