# rhdh-setup

Shell tooling to install **Red Hat Developer Hub (RHDH)** on OpenShift with **Keycloak** or **LDAP**, provision PostgreSQL, optionally load catalog data, and configure RBAC. The entry point is **`deploy.sh`**.

For repository-wide prerequisites, phases (setup / test / collect), and the full list of **`test.env`** variables, see the root **[`README.md`](../../README.md)** and **[`USERGUIDE.md`](../../USERGUIDE.md)**.

---

## Configuration and secrets

- **`deploy.sh`** sources **`../../test.env`** (repo root) via an absolute path resolved at runtime.
- **`QUAY_TOKEN`**, **`GITHUB_TOKEN`**, **`GITHUB_USER`**, and **`GITHUB_REPO`** must be set (and non-empty) before deploy logic runs — typically from CI secret files or a local **`.setenv.local`**.
- Cluster access: **`oc`** / **`KUBECONFIG`** as usual.

Install method (**Helm** vs **OLM**) is selected by how the script is invoked: default is Helm unless **`-o`** is passed (see below). The Makefile sets this from **`RHDH_INSTALL_METHOD`**.

---

## `deploy.sh` usage

Run from this directory (`ci-scripts/rhdh-setup`) or ensure paths still resolve. **`AUTH_PROVIDER`** for **`-i`** is usually **`keycloak`** or **`ldap`**.

| Flag | Action |
| --- | --- |
| **`-i <AUTH_PROVIDER>`** | Full **install**: namespace setup, Keycloak/LDAP as needed, catalog population when **`PRE_LOAD_DB`** is true, RHDH (Helm or OLM). |
| **`-o`** | Use **OLM** install path (combine with **`-i`** for a full OLM install). Without **`-o`**, install uses **Helm**. |
| **`-r`** | **Redeploy**: delete stack, then **install** again (same as **`-d`** followed by install — useful to resync after user/group changes). |
| **`-d`** | **Delete** RHDH and related resources (not necessarily the DB; see **`-C`**). |
| **`-c`** | Create / ensure the **RHDH PostgreSQL** cluster (`setup_rhdh_db`). |
| **`-C`** | Delete the **RHDH DB** (`delete_rhdh_db`). |
| **`-k`** | Install **Keycloak** only (namespace, operator group, realm). |
| **`-l`** | Install **LDAP** only (namespace + LDAP deployment). |
| **`-p`** | **Ensure catalog population** (wait for entity counts). |
| **`-m`** | **Setup monitoring** helpers. |
| **`-w`** | **Install** Sonataflow / workflow resources (**Helm** only). |
| **`-W`** | **Uninstall** workflows (**Helm** only). |
| **`-e`** | **PostgreSQL debug** shell job. |
| **`-E`** | **Cleanup** PostgreSQL debug resources. |

Examples:

```bash
# Helm, Keycloak, full install (typical local/CI)
./deploy.sh -i keycloak

# OLM instead of Helm
./deploy.sh -o -i keycloak

# Delete RHDH (see script for DB/other resources)
./deploy.sh -d

# Redeploy: delete then install again (requires AUTH_PROVIDER, e.g. from test.env)
./deploy.sh -r

# Or explicitly:
./deploy.sh -d && ./deploy.sh -i keycloak
```

**`create_resource.sh`** is sourced by **`deploy.sh`**; it implements catalog entity creation, Git upload helpers, and RBAC CSV / YAML generation (`create_and_upload_rbac_policy_csv`, `create_rbac_policy`, etc.).

---

## `RBAC_POLICY` values

When **`ENABLE_RBAC`** is true, **`RBAC_POLICY`** selects the preset used to generate policy (GitHub CSV upload, ConfigMap, or LDAP seed). It must be one of:

| Value | Notes |
| --- | --- |
| **`all_groups_admin_inherited`** | **Default** in **`deploy.sh`**. Admin role on **`admin_parent`**; hierarchy for inherited access. |
| **`all_groups_admin`** | Admin role on every group **`g1`…`gN`** (`N` = **`GROUP_COUNT`**). |
| **`static`** | Like above but only up to **`RBAC_POLICY_SIZE`**. |
| **`user_in_multiple_groups`** | Conditional / multi-group rules for **`user_in_multiple_groups`** scenarios. |
| **`nested_groups`** | Nested **`g*`** / **`g*_1`** chain aligned with catalog population. |
| **`complex`** | Base rules plus **`complex-rbac-config.csv`** and rotating named roles; optional orchestrator CSV patches when **`ENABLE_ORCHESTRATOR`** is on. |

Anything else fails during generation. See **`USERGUIDE.md`** for full behavior.

---

## Related Makefile targets (repo root)

- **`make deploy-rhdh-helm`** / **`make deploy-rhdh-olm`** — Wrap **`deploy.sh`** with the right flags and timestamps under **`.tmp/`**.
- **`make deploy-rhdh-db`** / **`make undeploy-rhdh-db`** — **`deploy.sh -c`** / **`-C`**.
- **`make deploy-keycloak`**, **`make deploy-ldap`**, **`make install-workflows`**, **`make ensure-catalog-population`**, etc.

Run **`make help`** at the repo root for the full list.
