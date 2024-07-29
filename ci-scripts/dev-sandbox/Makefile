#SHELL="/bin/bash -x"

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_DIR := $(dir $(MAKEFILE_PATH))

export RHDH_OLM_INDEX_IMAGE ?= quay.io/rhdh/iib:1.2-v4.15-x86_64
export RHDH_OPERATOR_NAMESPACE ?= rhdh-operator
export RHDH_OLM_CHANNEL ?= fast
export RHDH_OLM_OPERATOR_PACKAGE ?= rhdh

export TMP_DIR ?= $(shell readlink -m "$(MAKEFILE_DIR)/../../.tmp")
export ARTIFACT_DIR ?=

USER_WORKLOADS_TEMPLATE ?= $(MAKEFILE_DIR)/rhdh-perf-workloads.template.yaml
ITERATIONS ?= 10

.PHONY: getenv
getenv:
	echo "$(USER_WORKLOADS_TEMPLATE)"
	cat "$(USER_WORKLOADS_TEMPLATE)"
	echo "$(ITERATIONS)"

# Setup toolchain-e2e repository. Clones https://github.com/codeready-toolchain/toolchain-e2e repository locally
# and deploys the Toolchain resources using the latest images of Toolchain operators
.PHONY: setup-toolchain-e2e
setup-toolchain-e2e:
	./setup-toolchain-e2e.sh

# Deploy RHDH operator using the $RHDH_OLM_INDEX_IMAGE catalog in the $RHDH_OPERATOR_NAMESPACE namespace using
# a subscription to $RHDH_OLM_CHANNEL channel and $RHDH_OLM_OPERATOR_PACKAGE package. See the ./operator.yaml template
.PHONY: deploy
deploy:
	./deploy.sh

# Undeploy RHDH operator
.PHONY: undeploy
undeploy:
	./undeploy.sh

# Run the RHDH operator test. It uses the https://github.com/codeready-toolchain/toolchain-e2e/blob/master/setup/README.adoc
# tool. First it runs the baseline run to install all operators
# (https://github.com/codeready-toolchain/toolchain-e2e/tree/master/setup#baseline-runs-done-by-the-sandbox-team) and then
# it runs $ITERATONS number of runs with 2000 simulated users.
.PHONY: run
run:
	./run.sh "$(USER_WORKLOADS_TEMPLATE)" "$(ITERATIONS)"

# Collect results from all the runs (baseline + $ITERATIONS number of full runs) and combines it into
# a single CSV file ($ARTIFACT_DIR/summary.csv)
.PHONY: collect-results
collect-results:
	./collect-results.sh

# Cleans all toolchain-e2e resources from cluster
.PHONY: clean
clean:
	./clean.sh

# Collects current number of various resources in cluster (e.g. Secrets, ConfigMaps, etc.). It is used
# to track number of those resources before and after each of the test runs.
.PHONY: show-counts
show-counts:
	./counts.sh

# Runs all the pieces to setup the test in CI
.PHONY: ci-setup
ci-setup: setup-toolchain-e2e deploy

# Runs all the pieces to run the test in CI
.PHONY: ci-test
ci-test: run

# Runs all the pieces to collect results of the test in CI
.PHONY: ci-collect-results
ci-collect-results: collect-results

# Runs all the pieces to clean the cluster off the test resources in CI
.PHONY: ci-clean
ci-clean: undeploy clean
