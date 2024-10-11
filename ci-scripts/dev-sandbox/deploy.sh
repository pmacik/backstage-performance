#!/bin/bash

export RHDH_OPERATOR_NAMESPACE=rhdh-operator

export GITHUB_TOKEN GITHUB_USER GITHUB_REPO QUAY_TOKEN KUBECONFIG PRE_LOAD_DB

GITHUB_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/github.token)
GITHUB_USER=$(cat /usr/local/ci-secrets/backstage-performance/github.user)
GITHUB_REPO=$(cat /usr/local/ci-secrets/backstage-performance/github.repo)
QUAY_TOKEN=$(cat /usr/local/ci-secrets/backstage-performance/quay.token)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1090,SC1091
source "$(readlink -m "$SCRIPT_DIR/../../test.env")"

rootdir=$(readlink -m "$SCRIPT_DIR/../..")

pushd "$rootdir"
make ci-deploy
popd
