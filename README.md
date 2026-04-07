# Backstage performance benchmarking tool

## Prerequisites

Ensure your system has all the CLI and tools as shown in the [OpenShift CI runner Containerfile](https://github.com/openshift/release/blob/master/ci-operator/config/redhat-performance/backstage-performance/redhat-performance-backstage-performance-main.yaml#L7) or compatible versions.

## How to…

Everything is driven by the [`Makefile`](./Makefile). For details on targets and options, see the Makefile comments or run `make help`.

For a full walkthrough of workflows, secrets, and every `test.env` / Makefile / `ci-scripts` variable, see **[`USERGUIDE.md`](./USERGUIDE.md)**.

## Setup the environment

The RHDH performance testing framework is optimized to run in OpenShift CI, where secrets are supplied as files under `/usr/local/ci-secrets/backstage-performance`. (See [OpenShift CI Docs](https://docs.ci.openshift.org/docs/how-tos/adding-a-new-secret-to-ci/))

The framework expects the following credential files in that directory:

| Credential file | Mapped environment variable | Description | Example |
| :--- | :--- | :--- | :--- |
| `github.accounts` | *(read from file; not a single env var)* | Comma-separated `username:token` tuples; setup/test scripts use these to record GitHub API rate limits. | `gh_user1:ghp_token1,gh_user2:ghp_token2` |
| `github.org` | `GITHUB_ORG` | GitHub organization name; used when cleaning catalog branches (for example via `ci-scripts/clean-git-repo.sh`). | `example-org` |
| `github.repo` | `GITHUB_REPO` | URL of the GitHub repository used for RHDH catalog locations. | `https://github.com/example-org/rhdh-perf-testing-repo.git` |
| `github.user` | `GITHUB_USER` | GitHub username with access to the catalog repo. | `gh_user1` |
| `github.token` | `GITHUB_TOKEN` | Personal access token (classic) with permissions such as `delete_repo`, `repo`, and `workflow` as required. | `ghp_…` |
| `quay.token` | `QUAY_TOKEN` | Pull secret for RHDH and other images (often a base64-encoded Docker config JSON). | — |

Create `/usr/local/ci-secrets/backstage-performance` on the machine where you run the framework and populate these files.

Additionally, use an OpenShift cluster where you have sufficient permissions, and set **`KUBECONFIG`** (or log in with `oc`) so the tooling can reach the cluster.

# Running the RHDH performance tests

The workflow has three phases:

* Setup
* Test
* Collect results

## Testing RHDH performance

RHDH is deployed on OpenShift together with a load generator that simulates concurrent users.

RHDH is installed with Helm or the OLM operator. **Keycloak** acts as the identity provider and OAuth2 server. RHDH and Keycloak each use PostgreSQL, all in one namespace (`rhdh-performance` by default). RHDH may include an `oauth2-proxy` sidecar to protect the API. Test users and groups are created in Keycloak; catalog entities are loaded during setup.

The load generator uses the [Locust Kubernetes operator](https://abdelrhmanhamouda.github.io/locust-k8s-operator/getting_started/), installed in the `locust-operator` namespace by default.

Central configuration lives in **`test.env`** (sourced by the Makefile and `ci-scripts`).

To install RHDH and populate the database with test users, groups, and catalog entities:

1. Create `.setenv.local` with content like:

```bash
#!/bin/bash

export GITHUB_TOKEN
export GITHUB_USER
export GITHUB_REPO
export QUAY_TOKEN

GITHUB_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/github.token)"
GITHUB_USER="$(cat /usr/local/ci-secrets/backstage-performance/github.user)"
GITHUB_REPO="$(cat /usr/local/ci-secrets/backstage-performance/github.repo)"
QUAY_TOKEN="$(cat /usr/local/ci-secrets/backstage-performance/quay.token)"
```

2. Uncomment and set at least the following variables in `test.env`:

```bash
# Test phase
export SCENARIO=mvp
export USERS=10
export WORKERS=100
export DURATION=10m
export SPAWN_RATE=20
export WAIT_FOR_SEARCH_INDEX=false

# Setup phase
export PRE_LOAD_DB=true
export BACKSTAGE_USER_COUNT=100
export GROUP_COUNT=25
export API_COUNT=250
export COMPONENT_COUNT=250
export KEYCLOAK_USER_PASS=changeme
export AUTH_PROVIDER=keycloak

export RHDH_INSTALL_METHOD=helm
export RHDH_HELM_CHART_VERSION=1.8-164-CI

export RHDH_DEPLOYMENT_REPLICAS=1
export RHDH_DB_REPLICAS=1
export RHDH_DB_STORAGE=2Gi
export RHDH_KEYCLOAK_REPLICAS=1

export ENABLE_RBAC=true
export ENABLE_ORCHESTRATOR=true

export RHDH_LOG_LEVEL=debug
```

### [Setup phase] Install RHDH and populate the DB

From the repository root:

```bash
source .setenv.local
make clean-all |& tee clean.log
./ci-scripts/setup.sh |& tee setup.log
```

Intermediate files for debugging are under the `.tmp` directory.

### [Test phase] Run a single performance test

```bash
./ci-scripts/test.sh |& tee test.log
```

### [Collect results phase] Collect results and metrics

```bash
./ci-scripts/collect-results.sh |& tee collect-results.log
```

Artifacts are written under **`ARTIFACT_DIR`** (default **`.artifacts`**).
