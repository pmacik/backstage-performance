# Backstage / RHDH performance testing — user guide

This document expands on [`README.md`](README.md): what the repository does, how the workflow fits together, and what each environment variable means. Use it together with `make help` for Makefile targets.

---

## What this project is

The **Backstage performance benchmarking tool** deploys **Red Hat Developer Hub (RHDH)** on OpenShift, seeds it with users, groups, and catalog data, then drives load with **Locust** (via the [Locust Kubernetes operator](https://abdelrhmanhamouda.github.io/locust-k8s-operator/getting_started/)). Typical flow:

1. **Setup** — Install RHDH (Helm or OLM), Keycloak, PostgreSQL, optional extras (RBAC, Orchestrator, workflows), populate the catalog.
2. **Test** — Run a Locust scenario (`scenarios/<SCENARIO>.py`) against the RHDH route.
3. **Collect results** — Gather logs, Prometheus metrics (via `status_data.py` / OPL), CSV summaries, and optional CPU/heap profiles.

Everything is orchestrated from the **Makefile**; CI-style wrappers live under **`ci-scripts/`**.

---

## Prerequisites (from README)

- CLIs aligned with the [OpenShift CI runner image](https://github.com/openshift/release/blob/master/ci-operator/config/redhat-performance/backstage-performance/redhat-performance-backstage-performance-main.yaml) (or compatible): `oc`/`kubectl`, `helm`, `jq`, `envsubst`, Python 3, etc.
- An OpenShift cluster and a **`KUBECONFIG`** (or active `oc login`) with sufficient permissions.
- For GitHub-backed catalog / cleanup / rate-limit relief: files under **`/usr/local/ci-secrets/backstage-performance/`** (or your own `.setenv.local` that exports the same variables — see README).

---

## Secrets and CI layout

| Credential file (under `/usr/local/ci-secrets/backstage-performance/`) | Typical env var | Purpose |
| --- | --- | --- |
| `github.accounts` | (read by scripts) | Comma-separated `user:token` pairs to poll GitHub API rate limits during setup/test. |
| `github.org` | **`GITHUB_ORG`** (used in `ci-scripts/clean-git-repo.sh`) | Organization name for API calls when pruning catalog branches. |
| `github.repo` | **`GITHUB_REPO`** | Clone/push URL for the perf test catalog Git repo. |
| `github.user` | **`GITHUB_USER`** | Git user with repo access. |
| `github.token` | **`GITHUB_TOKEN`** | PAT with permissions such as `repo`, `delete_repo`, `workflow` as needed. |
| `quay.token` | **`QUAY_TOKEN`** | Pull secret material (often base64-encoded `dockerconfigjson`) for private images. |

`ci-scripts/setup.sh` and `ci-scripts/test.sh` **overwrite** `GITHUB_*` and `QUAY_TOKEN` from these files after sourcing `test.env`, matching OpenShift CI. For local runs, use `.setenv.local` as in the README.

---

## Configuration file: `test.env`

`test.env` is **sourced** by:

- The **Makefile** (`include test.env`) — use only `export VAR=value` (not `export VAR=${VAR:-default}`; the Makefile merge does not handle that pattern well).
- **`ci-scripts/rhdh-setup/deploy.sh`** and scripts that source it.
- **`ci-scripts/setup.sh`**, **`ci-scripts/test.sh`**, **`ci-scripts/collect-results.sh`**, **`ci-scripts/scalability/test-scalability.sh`**, etc.

Uncomment and set variables you need. Defaults in code/Makefile apply when a variable is unset.

---

## Workflow commands (from README)

| Phase | Command | Notes |
| --- | --- | --- |
| Clean + setup | `source .setenv.local; make clean-all \|& tee clean.log; ./ci-scripts/setup.sh \|& tee setup.log` | `setup.sh` runs `make ci-deploy`. Debug files under **`.tmp/`**. |
| Test | `./ci-scripts/test.sh \|& tee test.log` | Sets `BASE_HOST` from the route, then `make ci-run`. |
| Collect | `./ci-scripts/collect-results.sh \|& tee collect-results.log` | Uses **`ARTIFACT_DIR`** (default `.artifacts`). |

---

## Makefile highlights

- **`make help`** — Lists targets and short descriptions.
- **`make ci-deploy`** — `namespace` + `deploy-rhdh-helm` or `deploy-rhdh-olm` depending on **`RHDH_INSTALL_METHOD`**.
- **`make ci-run`** — `setup-venv`, `deploy-locust`, **`make test`** (Locust CR + workers in **`LOCUST_NAMESPACE`**).
- **`make test-local`** — Run Locust on your machine against **`BASE_HOST`** (or auto-discovered route).
- **`make test-scalability`** — Matrix of scale dimensions; see **`SCALE_*`** variables below.
- **`make clean-all`** — Namespace cleanup, locust test resources, undeploy RHDH DB and RHDH, etc.

**`PROJ_ROOT`** is exported by the Makefile (repository root with trailing `/`). It is required by **`ci-scripts/scalability/test-scalability.sh`** when resolving paths; running **`make test-scalability`** sets it automatically.

---

## Environment variables — load test / Locust

| Variable | Default (typical) | Meaning |
| --- | --- | --- |
| **`SCENARIO`** | `mvp` (Makefile) | Locust file **`scenarios/<SCENARIO>.py`**. |
| **`BASE_HOST`** | empty → auto | Full URL (`https://…`) passed to Locust `--host`. If empty, derived from the OpenShift route (`RHDH_INSTALL_METHOD`, **`RHDH_NAMESPACE`**, **`RHDH_HELM_RELEASE_NAME`**, **`AUTH_PROVIDER`**). |
| **`USERS`** | `100` | Peak concurrent Locust users (`--users`). |
| **`WORKERS`** | `5` | Locust worker pod replicas in-cluster; if `USERS <= WORKERS`, Makefile bumps **`WORKERS`** up to **`USERS`**. |
| **`DURATION`** | `1m` | Test length (`--run-time`), e.g. `300s`, `10m`, `1h30m`. |
| **`SPAWN_RATE`** | `20` | Users spawned per second (`--spawn-rate`). |
| **`WAIT_FOR_SEARCH_INDEX`** | `true` (scalability script) / often `false` in README examples | If `true`, scalability setup waits until catalog search returns a non-null result count (indexing). If `false`, skips wait (faster but may skew early requests). |
| **`LOCUST_EXTRA_CMD`** | empty | Extra flags appended to Locust master/worker commands (e.g. `--debug=true`). Makefile strips quotes. |
| **`LOCUST_NAMESPACE`** | `locust-operator` | Namespace for Locust operator and test pods. |
| **`PAGE_N_COUNT`** | `0` | If &gt; 0, enables dynamic “page N” plugin workload; passed into Locust as `--page-n-count`. |
| **`CATALOG_TAB_N_COUNT`** | `0` | Same for catalog tab N; `--catalog-tab-n-count`. |
| **`DYNAMIC_PLUGIN_BS_VERSION`** | `1.48` | Backstage version label used when wiring dynamic plugin assets during deploy. |

Keycloak-related flags are injected automatically for **`AUTH_PROVIDER=keycloak`** from the cluster (`--keycloak-host`, `--keycloak-password` from `perf-test-secrets`).

---

## Environment variables — data population

| Variable | Default (deploy.sh) | Meaning |
| --- | --- | --- |
| **`PRE_LOAD_DB`** | `true` | If true, population path runs (users, groups, catalog entities). |
| **`BACKSTAGE_USER_COUNT`** | `1` | Number of Backstage users (Keycloak/LDAP wiring depends on **`AUTH_PROVIDER`**). |
| **`GROUP_COUNT`** | `1` | Number of groups. |
| **`API_COUNT`** | `1` | API entities in catalog. |
| **`COMPONENT_COUNT`** | `1` | Component entities in catalog. |
| **`KEYCLOAK_USER_PASS`** | `changeme` | Password for generated test users (also stored in secrets for Locust). |
| **`AUTH_PROVIDER`** | empty in deploy.sh until **`deploy.sh -i <provider>`** | **`keycloak`** or **`ldap`** (plus Helm/OLM specifics). Drives IdP templates and routes. |
| **`COMPONENT_SHARD_SIZE`** | `500` | How many entities go into each shard file (`api-N.yaml` / `component-N.yaml`) before incrementing `N` in `create_resource.sh`. |
| **`ENSURE_CATALOG_POPULATION_TIMEOUT`** | `3600` | Seconds to wait for catalog population to finish. |
| **`CATALOG_REFRESH_INTERVAL_MINUTES`** | `50` | Minutes for catalog refresh interval in app config (`CATALOG_REFRESH_INTERVAL` internal mapping). |

---

## Environment variables — RHDH install (Helm)

| Variable | Default | Meaning |
| --- | --- | --- |
| **`RHDH_INSTALL_METHOD`** | `helm` (Makefile / scripts) | **`helm`** or **`olm`**. Makefile picks `deploy-rhdh-helm` vs `deploy-rhdh-olm`. |
| **`RHDH_NAMESPACE`** | `rhdh-performance` | Namespace for RHDH stack (app, DB routes, secrets). |
| **`RHDH_HELM_REPO`** | `oci://quay.io/rhdh/chart` | Helm chart repository URL. |
| **`RHDH_HELM_CHART`** | `redhat-developer-hub` | Chart name (scalability script may override for alternate charts). |
| **`RHDH_HELM_CHART_VERSION`** | auto from **`RHDH_BASE_VERSION`** | If empty, `deploy.sh` picks latest tag matching base version via `skopeo`/`jq`. |
| **`RHDH_HELM_RELEASE_NAME`** | `rhdh` | Helm release name; label selector for routes. |
| **`RHDH_BASE_VERSION`** | `1.9` | Version family for auto chart/IIB selection. |
| **`RHDH_IMAGE_REGISTRY`**, **`RHDH_IMAGE_REPO`**, **`RHDH_IMAGE_TAG`** | empty | Optional full image override for RHDH. |
| **`RHDH_DEPLOYMENT_REPLICAS`** | `1` | RHDH backend pod count. |
| **`RHDH_DB_REPLICAS`** | `1` | Postgres cluster replica count (0 can mean single instance depending on chart). |
| **`RHDH_DB_STORAGE`** | `1Gi` | PVC size for main RHDH DB. |
| **`RHDH_KEYCLOAK_REPLICAS`** | `1` | Keycloak deployment replicas. |
| **`RHDH_RESOURCES_*`** | empty | CPU/memory requests/limits for RHDH pods (`_REQUESTS` / `_LIMITS`). |
| **`RHDH_DB_RESOURCES_*`** | empty | Same for database pods. |
| **`RHDH_NODEJS_MAX_HEAP_SIZE`** | empty | Node.js heap cap for Backstage backend when set in chart. |
| **`ENABLE_PGBOUNCER`** | `false` | Deploy PgBouncer in front of DB. |
| **`PGBOUNCER_REPLICAS`** | `0` | PgBouncer pod count when enabled. |
| **`KEYCLOAK_DB_STORAGE`** | falls back to **`RHDH_DB_STORAGE`** | Keycloak Postgres PVC size. |

### Orchestrator (Helm only)

| Variable | Default | Meaning |
| --- | --- | --- |
| **`ENABLE_ORCHESTRATOR`** | `false` | Install orchestrator infra chart alongside RHDH. |
| **`FORCE_ORCHESTRATOR_INFRA_UNINSTALL`** | `false` | Force-remove orchestrator Helm release on teardown. |
| **`RHDH_HELM_ORCHESTRATOR_REPO`** | `oci://quay.io/rhdh/orchestrator-infra-chart` | Orchestrator chart repo. |
| **`RHDH_HELM_ORCHESTRATOR_CHART`** | `redhat-developer-hub-orchestrator-infra` | Chart name. |
| **`RHDH_HELM_ORCHESTRATOR_CHART_VERSION`** | **`RHDH_HELM_CHART_VERSION`** | Chart version alignment. |

---

## Environment variables — RHDH install (OLM)

| Variable | Default | Meaning |
| --- | --- | --- |
| **`RHDH_OPERATOR_NAMESPACE`** | `rhdh-operator` | Namespace for operator subscription/catalog source. |
| **`RHDH_OLM_INDEX_IMAGE`** | `quay.io/rhdh/iib:<base>-v<OCP>-x86_64` | Index image for catalog; **`<OCP>`** is short OpenShift version from `oc version`. |
| **`RHDH_OLM_CHANNEL`** | `fast` | Subscription channel. |
| **`RHDH_OLM_OPERATOR_PACKAGE`** | `rhdh` | Operator package name (README sometimes uses `rhdh-operator`; set to match your index). |
| **`RHDH_OLM_WATCH_EXT_CONF`** | `true` | Whether the operator watches extra CRs for config. |
| **`RHDH_OLM_OPERATOR_VERSION`** | empty | Pin CSV/version; if empty, latest from catalog. |
| **`RHDH_OLM_OPERATOR_RESOURCES_*`** | empty | CPU/memory/ephemeral storage requests/limits on operator Deployment. |

**`INSTALL_METHOD`** inside `deploy.sh` is **`helm`** unless you invoke **`deploy.sh -o`**, which the Makefile does when **`RHDH_INSTALL_METHOD=olm`**.

---

## Environment variables — RBAC policy

| Variable | Default | Meaning |
| --- | --- | --- |
| **`ENABLE_RBAC`** | `false` | Apply RBAC patch to app config and related resources. |
| **`RBAC_POLICY`** | `all_groups_admin_inherited` | Which preset to use when generating the permission policy (CSV upload, inline YAML, and LDAP seed scripts). Must be one of the values in the table below; anything else fails during generation (`create_resource.sh`). |
| **`RBAC_POLICY_SIZE`** | falls back to **`GROUP_COUNT`** | Per-policy scale for policies that use a size cap (nested groups, static, `user_in_multiple_groups`). Ignored or clamped where the implementation ties groups to **`GROUP_COUNT`**. |
| **`RBAC_POLICY_UPLOAD_TO_GITHUB`** | `true` | Push generated policy CSV to **`GITHUB_REPO`** (needs **`GITHUB_USER`**, **`GITHUB_TOKEN`**). |
| **`RBAC_POLICY_FILE_URL`** | empty | If set, fetch policy from URL into PVC instead of ConfigMap. |
| **`RBAC_POLICY_PVC_STORAGE`** | `100Mi` | PVC size for downloaded policy. |

### Allowed values for `RBAC_POLICY`

These string literals are defined and handled in **`ci-scripts/rhdh-setup/create_resource.sh`** (and the LDAP **`generate-seed-ldif.sh`** helper). The generator starts from a small base CSV (default role `a`, users `guru` / `guest`), then adds policy-specific `g, …` lines.

| Value | What it generates |
| --- | --- |
| **`all_groups_admin_inherited`** *(default)* | Single admin grant: **`group:default/admin_parent`** → **`role:default/a`**. Catalog/LDAP setup creates an **`admin_parent`** hierarchy so children inherit access. Default in **`deploy.sh`** when **`RBAC_POLICY`** is unset. |
| **`all_groups_admin`** | Assigns admin role **`role:default/a`** to every catalog group **`group:default/g1` … `group:default/gN`** where **N = `GROUP_COUNT`**. |
| **`static`** | Same “every `g{i}` is admin” pattern, but **i** runs only up to **`RBAC_POLICY_SIZE`** (or **`GROUP_COUNT`** if size is unset). Useful when you want fewer admin groups than **`GROUP_COUNT`**. |
| **`user_in_multiple_groups`** | For each test user **`user:default/t{u}`**, adds admin membership; user **`t1`** is given a **conditional** grant (group must be in a fixed list of **`g1`…`g{RBAC_POLICY_SIZE}`**), other users get unconditional admin. Exercises conditional/group-list rules. |
| **`nested_groups`** | Builds a **nested group chain**: repeated admin grants on **`g1`** and on names like **`g{i-1}_1`** up to **`min(RBAC_POLICY_SIZE, GROUP_COUNT)`**, matching the nested-group layout used by catalog population for that policy. |
| **`complex`** | Appends rules from **`template/backstage/complex-rbac-config.csv`**, and maps each **`g{i}`** to a **rotating named role** (`platform_admin`, `engineering_lead`, …). With **`ENABLE_ORCHESTRATOR`** (Helm), also appends **`complex-orchestrator-rbac-patch.csv`**. Intended for the **complex-rbac** scenario. |

Any other value is **invalid** and causes **`Invalid RBAC policy`** when the policy is generated.

---

## Environment variables — logging, metrics, profiling

| Variable | Default | Meaning |
| --- | --- | --- |
| **`RHDH_LOG_LEVEL`** | `warn` | Backstage log level. |
| **`KEYCLOAK_LOG_LEVEL`** | `WARN` | Keycloak log level. |
| **`PSQL_LOG`** | `true` | Enable PostgreSQL logging configuration in cluster. |
| **`PSQL_EXPORT`** | `false` | If `true`, `collect-results.sh` also queries Postgres-focused Prometheus metrics. |
| **`RHDH_METRIC`** | `true` | Collect NodeJS-oriented metrics for populate/test windows. |
| **`ENABLE_PROFILING`** | `false` | After tests (Helm only), collect V8 CPU log and heap snapshot from backend pod. |
| **`LOG_MIN_DURATION_STATEMENT`**, **`LOG_MIN_DURATION_SAMPLE`**, **`LOG_STATEMENT_SAMPLE_RATE`** | `65`, `50`, `0.7` | Postgres slow-query logging tunables. |
| **`RHDH_STARTUP_TIMEOUT_SECONDS`** | `600 * replica_count` | Max wait for RHDH rollout during scaled startup. |

---

## Environment variables — paths and artifacts

| Variable | Default | Meaning |
| --- | --- | --- |
| **`TMP_DIR`** | `.tmp` (resolved to absolute path) | Timestamps, rendered YAML, URLs, DB log snippets, etc. |
| **`ARTIFACT_DIR`** | `.artifacts` | Logs, `benchmark.json`, metrics, `summary.csv`, profiling outputs. **`collect-results.sh`** copies many **`TMP_DIR`** files here. |

---

## Environment variables — scalability matrix (`make test-scalability`)

Used by **`ci-scripts/scalability/test-scalability.sh`**. Values are often **space-separated lists**. Tuple formats use **`:`** inside each token.

| Variable | Example / default | Meaning |
| --- | --- | --- |
| **`SCALE_WORKERS`** | `5` | Locust worker counts to iterate. |
| **`SCALE_ACTIVE_USERS_SPAWN_RATES`** | `1:1 200:40` | Pairs **`USERS`:`SPAWN_RATE`** per iteration (nested mode). |
| **`SCALE_BS_USERS_GROUPS`** | `1:1 10000:2500` | Pairs **`BACKSTAGE_USER_COUNT`:`GROUP_COUNT`**. |
| **`SCALE_CATALOG_SIZES`** | `1:1 10000:10000` | Pairs **`API_COUNT`:`COMPONENT_COUNT`**. |
| **`SCALE_RBAC_POLICY_SIZE`** | `10000` | Values for **`RBAC_POLICY_SIZE`**. |
| **`SCALE_REPLICAS`** | `1:1` | Pairs **`RHDH_DEPLOYMENT_REPLICAS`:`RHDH_DB_REPLICAS`**. |
| **`SCALE_DB_STORAGES`** | `1Gi 2Gi` | **`RHDH_DB_STORAGE`** values. |
| **`SCALE_CPU_REQUESTS_LIMITS`** | `:` | Pairs **`requests`:`limits`** for **`RHDH_RESOURCES_CPU_*`** (empty half allowed). |
| **`SCALE_MEMORY_REQUESTS_LIMITS`** | `:` | Same for memory. |
| **`SCALE_PAGE_N_CATALOG_TAB_N_COUNTS`** | `0:0` | Pairs **`PAGE_N_COUNT`:`CATALOG_TAB_N_COUNT`**. |
| **`SCALE_COMBINED`** | unset | If set, **combines** active users, spawn rate, users, groups, APIs, and components in one token: **`au:sr:bu:bg:apis:components`**, and skips inner nested loops for those dimensions. |
| **`ALWAYS_CLEANUP`** | `false` | If not `false`, runs cleanup before each iteration without full redeploy path. |

Openshift login for scalability CI: **`OPENSHIFT_API`**, **`OPENSHIFT_USERNAME`**, **`OPENSHIFT_PASSWORD`** (used in `env_setup()` in `test-scalability.sh`).

---

## Developer Sandbox (`ci-scripts/dev-sandbox/`)

Optional workflow Makefile variables (see **`ci-scripts/dev-sandbox/Makefile`**):

| Variable | Default | Meaning |
| --- | --- | --- |
| **`RHDH_WORKLOADS_TEMPLATE_NAME`** | `default` | Which workload template to apply for multi-Backstage tests. |
| **`NUMBER_OF_RUNS`** | `10` | Repeated test runs. |
| **`NUMBER_OF_USERS_PER_RUN`** | `2000` | Users per run. |
| **`NUMBER_OF_USERS_WITH_WORKLOADS_PER_RUN`** | `2000` | Users that also drive workload CRs. |

These interact with **`RHDH_OLM_*`** variables when testing on sandbox clusters.

---

## Release / CI test driver (`ci-scripts/release-tests.sh`)

This script composes **`SCALE_*`** matrices for named scenarios. Optional:

| Variable | Meaning |
| --- | --- |
| **`SCALE_MEMORY_LIMITS`** | Memory requests:limits tuple (e.g. `1Gi:2Gi`) passed into preset functions for memory-scaling runs. |

---

## Miscellaneous scripts

| Variable | Where | Meaning |
| --- | --- | --- |
| **`DRY_RUN`** | `clean-git-repo.sh`, LDAP helpers | If `true` (default in branch cleaner), only print branches that would be deleted. |
| **`GITHUB_ORG`**, **`GITHUB_TOKEN`**, **`GITHUB_REPO`** | `clean-git-repo.sh` | Normally loaded from CI secret files; used to delete non-`main` branches on the catalog repo. |

---

## Quick reference: boolean-ish values

Shell scripts compare strings literally in many places (**`true`** / **`false`**). Use lowercase **`true`** and **`false`** for:

- **`PRE_LOAD_DB`**, **`ENABLE_RBAC`**, **`ENABLE_ORCHESTRATOR`**, **`ENABLE_PROFILING`**, **`ENABLE_PGBOUNCER`**, **`WAIT_FOR_SEARCH_INDEX`**, **`PSQL_EXPORT`**, **`RHDH_METRIC`**, **`RHDH_OLM_WATCH_EXT_CONF`**, **`RBAC_POLICY_UPLOAD_TO_GITHUB`**, etc.

---

## Further reading

- [`README.md`](README.md) — Quick start, secret layout, example `test.env` snippet.
- **`make help`** — All Makefile targets.
- [`ci-scripts/rhdh-setup/README.md`](ci-scripts/rhdh-setup/README.md) — Deeper setup notes where present.
