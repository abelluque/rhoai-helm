# RHOAI 3.4 Helm Charts

Helm-based layout for deploying RHOAI 3.4 and Models-as-a-Service (MaaS), following the pattern from [openshift-setup](https://github.com/jharmison-redhat/openshift-setup).

The existing Kustomize tree at `[rhoai-3_4/](../rhoai-3_4/)` and `[bootstrap.sh](../bootstrap.sh)` are unchanged. Use this directory for direct Helm deployments.

## Directory Layout

```bash
rhoai-3_4-helm/
├── charts/                         # Reusable Helm charts
├── clusters/                       # Per-cluster values
│   └── example.cluster.opentlc.com/
│       ├── cluster.yaml            # Global cluster name/domain/toolsImage
│       ├── platform/values/{app}/  # Platform chart overrides (waves 1–5)
│       └── values/{app}/           # Workload chart overrides (waves 6–7)
└── HELM.md
```

**Model name contract:** keys in `llmisvc` `models:` must match names in `maas-subscriptions` `modelRefs`, `subscriptions`, and `authPolicies`.

## Install Order

| Wave | Chart                     | Description                                                              |
| ---- | ------------------------- | ------------------------------------------------------------------------ |
| 1    | `cert-manager`            | cert-manager operator                                                    |
| 1    | `observability-operators` | Tempo, Cluster Observability, OpenTelemetry operators                    |
| 2    | `nvidia-gpu-enablement`   | NFD + NVIDIA GPU operator; instances via post-install Jobs               |
| 2    | `leaderworkerset`         | Leader Worker Set operator; instance via post-install Job                |
| 2    | `rhcl`                    | Red Hat Connectivity Link operator; Kuadrant via post-install Job        |
| 3    | `service-mesh-operators`  | OpenShift Service Mesh 3 operator (pinned `servicemeshoperator3.v3.3.3`) |
| 3    | `gateway-api`             | GatewayClass + maas-default-gateway                                      |
| 4    | `maas-postgres`           | Optional in-cluster Postgres + `maas-db-config` for MaaS API             |
| 5    | `openshift-ai`            | RHOAI operator; DSC/DSCI and dashboard config via post-install Jobs      |
| 6    | `llmisvc`                 | LLMInferenceService models                                               |
| 7    | `maas-subscriptions`      | MaaSModelRef, MaaSAuthPolicy, MaaSSubscription                           |

Wave 4 (`maas-postgres`) runs before wave 5 (`openshift-ai`) so the `maas-db-config` secret exists when the DataScienceCluster enables MaaS — see [Prerequisites for wave 5](#prerequisites-for-wave-5) below.

### 1. Configure your cluster

```bash
cp -r clusters/example.cluster.opentlc.com clusters/mycluster.mydomain.com
# Edit clusters/mycluster.mydomain.com/cluster.yaml:
#   global.cluster.name
#   global.cluster.baseDomain
#   global.toolsImage
```

Edit platform overrides under `clusters/mycluster.mydomain.com/platform/values/` and workload overrides under `clusters/mycluster.mydomain.com/values/`.

### 2. Update chart dependencies

```bash
for c in cert-manager nvidia-gpu-enablement rhcl leaderworkerset openshift-ai observability-operators service-mesh-operators; do
  (cd charts/$c && helm dependency update)
done
```

### 3. Install in wave order

```bash
CLUSTER=clusters/example.cluster.opentlc.com
CHARTS=charts

# Wave 1 - optional when cert-manager/Venafi is pre-installed (see Venafi integration below)
# For RHDP cluster add --take-ownership to the cert-manager install when adopting an existing operator
helm upgrade --install cert-manager $CHARTS/cert-manager -n cert-manager-operator --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/cert-manager/values.yaml
# openshift-operators is a platform namespace; do not pass --create-namespace
helm upgrade --install observability-operators $CHARTS/observability-operators -n openshift-operators \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/observability-operators/values.yaml

# Wave 2 (wait for operators to be ready)
helm upgrade --install nvidia-gpu-enablement $CHARTS/nvidia-gpu-enablement -n openshift-nfd --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/nvidia-gpu-enablement/values.yaml
helm upgrade --install leaderworkerset $CHARTS/leaderworkerset -n openshift-lws-operator --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/leaderworkerset/values.yaml
helm upgrade --install rhcl $CHARTS/rhcl -n kuadrant-system --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/rhcl/values.yaml

# Wave 3 (wait for servicemeshoperator3 CSV Succeeded before gateway-api)
helm upgrade --install service-mesh-operators $CHARTS/service-mesh-operators -n openshift-operators \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/service-mesh-operators/values.yaml
helm upgrade --install gateway-api $CHARTS/gateway-api -n openshift-ingress \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/gateway-api/values.yaml

# Wave 4
helm upgrade --install maas-postgres $CHARTS/maas-postgres -n redhat-ods-applications --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/maas-postgres/values.yaml

# Wave 5
helm upgrade --install openshift-ai $CHARTS/openshift-ai -n redhat-ods-operator --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/openshift-ai/values.yaml

# Waves 6–7 (workloads)
helm upgrade --install llmisvc $CHARTS/llmisvc -n ai-models --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/values/llmisvc/values.yaml
helm upgrade --install maas-subscriptions $CHARTS/maas-subscriptions -n models-as-a-service --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/values/maas-subscriptions/values.yaml

# Wave 8 Optional - add additional Inference Servers to the `ai-models` namespace

# Adds gpt-oss-20b
helm upgrade --install llmisvc-gpt-oss-20b $CHARTS/llmisvc \
  -n ai-models --set namespace.create=false \
  -f $CLUSTER/cluster.yaml -f $CHARTS/llmisvc/gpt-oss-20b-maas.yaml



```

Wait for each wave's operators and post-install Jobs to complete before proceeding to the next wave.

### Prerequisites for wave 5

Before wave 5 (`openshift-ai`), the `maas-db-config` secret must exist in `redhat-ods-applications`. Wave 4 (`maas-postgres`) creates it when `maas.postgres.deploy.enabled: true` (wait for the `create-maas-db-config` Job to complete). With an external database (`maas.postgres.deploy.enabled: false`), run wave 4 with `existingSecret` or `credentialsSecret` configured, or provision `maas-db-config` out of band before proceeding.

If `maas-db-config` is missing when wave 5 runs, the DataScienceCluster will report `ModelsAsServiceReady: False` with:

```bash
database Secret 'maas-db-config' not found in namespace 'redhat-ods-applications'
```

### Platform readiness checklist

Before installing workload charts (waves 6–7), confirm:

- [ ] `servicemeshoperator3.v3.3.3` CSV is `Succeeded` in `openshift-operators`
- [ ] `maas-default-gateway` is programmed in `openshift-ingress`
- [ ] DataScienceCluster and RHOAI dashboard are ready
- [ ] `maas-db-config` secret exists (from wave 4 in-cluster Postgres, external credentials, or day2 provisioning)
- [ ] GPU nodes are labeled if deploying GPU models (`nvidia.com/gpu.present=true`)

### Service Mesh 3 and OpenShift AI coexistence

Wave 3 installs the **Service Mesh 3 operator only** (`servicemeshoperator3.v3.3.3`) with a pinned CSV — independent of RHOAI's operator dependency chain. Wave 5 (`openshift-ai`) sets `serviceMesh.managementState: Removed` on the DSCInitialization so RHOAI does not auto-install or manage Service Mesh; MaaS and llm-d use Gateway API and RawDeployment instead. See [OpenShift AI + Service Mesh 3 on one cluster](https://developers.redhat.com/articles/2025/07/16/how-deploy-openshift-ai-service-mesh-3-one-cluster#testing_and_validation).

This chart does **not** deploy an `Istio` control plane or Kiali operator. Tempo and OpenTelemetry are installed in wave 1 (`observability-operators`). Deploy an `Istio` CR separately if your cluster requires an SM3 data plane beyond the operator subscription.

## Value Layering

### Platform charts

Charts merge values in this order (later overrides earlier):

1. `charts/{app}/values.yaml` — chart defaults
2. `clusters/{cluster}/cluster.yaml` — global cluster name/domain/toolsImage
3. `clusters/{cluster}/platform/values/{app}/values.yaml` — per-app overrides

The gateway hostname is templated from cluster globals:

```bash
maas.apps.{cluster.name}.{cluster.baseDomain}
```

### Workload charts

1. `charts/{app}/values.yaml` — chart defaults
2. `clusters/{cluster}/cluster.yaml` — global cluster settings
3. `clusters/{cluster}/values/{app}/values.yaml` — per-app overrides

### Disconnected clusters (optional)

For air-gapped or disconnected environments, set `disconnected.enabled: true` in `clusters/{cluster}/cluster.yaml` and update the registry/image fields for that cluster:

```yaml
disconnected:
  enabled: true
  wasmShimImage: registry.example.com/rhcl-1/wasm-shim-rhel9@sha256:...
  protectedRegistry: registry.example.com
  gatewayConfig:
    wasmInsecureRegistries: registry.example.com
    serviceType: ClusterIP  # lab only; omit on production clusters
```

This enables:

- `**rhcl**`: copies `pull-secret` to `wasm-plugin-pull-secret` and patches the operator subscription (`RELATED_IMAGE_WASMSHIM`, `PROTECTED_REGISTRY`) — bootstrap.sh step 11
- `**gateway-api**`: creates `default-gateway-config` with `WASM_INSECURE_REGISTRIES` for the gateway istio-proxy

Leave `disconnected.enabled: false` (default) on connected clusters such as OpenTLC sandboxes.

### Venafi / pre-installed cert-manager (optional)

When the cluster already has cert-manager and a Venafi `ClusterIssuer`, **skip Wave 1** (`cert-manager` chart) and enable HTTPS certificate issuance in Wave 3 (`gateway-api`).

1. Set `install-cert-manager.enabled: false` in `clusters/{cluster}/platform/values/cert-manager/values.yaml` (or omit the Wave 1 install entirely).
2. Enable certificate creation in `clusters/{cluster}/platform/values/gateway-api/values.yaml`:

```yaml
gateways:
  maas-default-gateway:
    listeners:
      https:
        certificate:
          create: true
          secretName: maas-default-gateway-venafi-tls
          duration: 17520h
          issuerRef:
            group: cert-manager.io
            kind: ClusterIssuer
            name: venafi-tpp-cluster-issuer
        tls:
          certificateRefs:
            - group: ""
              kind: Secret
              name: maas-default-gateway-venafi-tls
```

`commonName` defaults to the gateway hostname in the Certificate template. Venafi `venafi-tpp-approver-policy` requires `duration: 17520h` (2 years) — set this in cluster values when using that policy.

Chart defaults use `certificate.create: false` and reference `maas-default-gateway-venafi-tls` so clusters without Venafi are unaffected. Optional Venafi fields (`renewBefore`, `dnsNames`, `subject`, etc.) are supported under `listeners.https.certificate` — see `charts/gateway-api/values.yaml`.

**Verify after Wave 3:**

```bash
oc get clusterissuer venafi-tpp-cluster-issuer
oc get certificate maas-default-gateway-venafi-tls -n openshift-ingress
oc describe certificate maas-default-gateway-venafi-tls -n openshift-ingress
oc get certificaterequest -n openshift-ingress
oc get secret maas-default-gateway-venafi-tls -n openshift-ingress
oc get gateway maas-default-gateway -n openshift-ingress
```

If the Certificate is not `Ready`, check `oc describe certificate` for Venafi policy errors (e.g. missing `commonName` or wrong `duration`).

**Migration:** If a previous install used `cert-manager-ingress-cert`, delete the old resources before upgrading:

```bash
oc delete certificate cert-manager-ingress-cert -n openshift-ingress --ignore-not-found
oc delete secret cert-manager-ingress-cert -n openshift-ingress --ignore-not-found
```

### MaaS PostgreSQL (optional per cluster)

MaaS API key storage requires a `maas-db-config` secret with `DB_CONNECTION_URL`. Configure this per cluster in `clusters/{cluster}/cluster.yaml`:

```yaml
maas:
  postgres:
    deploy:
      enabled: true   # sandbox/POC: deploy in-cluster PostgreSQL via maas-postgres chart
    dbConfig:
      secretName: maas-db-config
```

For **production** clusters with day2-managed PostgreSQL, disable the in-cluster deployment and point MaaS at your external database:

```yaml
maas:
  postgres:
    deploy:
      enabled: false
    dbConfig:
      secretName: maas-db-config
      # Option A: secret already provisioned outside this repo (recommended)
      existingSecret: maas-db-config
      # Option B: chart creates maas-db-config from a credentials secret + endpoints
      # credentialsSecret: maas-postgres-credentials
      # host: postgres.production.example.com
      # port: 5432
      # database: maas
      # user: maas
      # passwordKey: password
      # sslmode: require
```

When `deploy.enabled` is `true`, the chart deploys a single-replica PostgreSQL instance and a Job that builds `maas-db-config` from the bundled credentials. When `deploy.enabled` is `false` and `existingSecret` is set, the chart does not deploy PostgreSQL or run the Job — day2 operations own the secret. When `deploy.enabled` is `false` and `credentialsSecret` (or host/user) is set, the Job creates `maas-db-config` from the external connection details.

## Bootstrap.sh Parity

All imperative steps from `[bootstrap.sh](../bootstrap.sh)` are encoded in the Helm charts:

| bootstrap.sh step                                           | Helm chart              | Implementation                                                                               |
| ----------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------- |
| Kuadrant CR                                                 | `rhcl`                  | Job `apply-kuadrant` (post-install; waits for operator CRD)                                  |
| RHCL CSV `ISTIO_GATEWAY_CONTROLLER_NAMES` patch             | `rhcl`                  | Job `patch-rhcl-csv`                                                                         |
| Enable `kuadrant-console-plugin`                            | `rhcl`                  | Job `enable-console-plugin`                                                                  |
| Gateway hostname patch                                      | `gateway-api`           | Templated from `cluster.yaml`                                                                |
| DSCInitialization + DataScienceCluster                      | `openshift-ai`          | Jobs `apply-dsci`, `apply-dsc` (post-install; wait for operator CRDs)                        |
| Authorino NetworkPolicy                                     | `openshift-ai`          | Template                                                                                     |
| Authorino service serving-cert annotation                   | `rhcl`                  | `service-authorino.yaml` (SSA)                                                               |
| Authorino TLS spec                                          | `rhcl`                  | `authorino.yaml`                                                                             |
| Restart kuadrant-operator-controller                        | `rhcl`                  | Job `restart-kuadrant-operator`                                                              |
| NFD instance + NVIDIA ClusterPolicy                         | `nvidia-gpu-enablement` | Jobs `apply-nfd-instance`, `apply-gpu-cluster-policy` (post-install; wait for operator CRDs) |
| LeaderWorkerSetOperator instance                            | `leaderworkerset`       | Job `apply-leaderworkerset` (post-install; waits for operator CRD)                           |
| OdhDashboardConfig (MaaS dashboard flags)                   | `openshift-ai`          | Job `apply-odh-dashboard-config` (post-install; waits for CRD after DSC)                     |
| Postgres deployment (optional)                              | `maas-postgres`         | `postgres.yaml` when `maas.postgres.deploy.enabled`                                          |
| `maas-db-config` secret + maas-api restart                  | `maas-postgres`         | Job `create-maas-db-config` (skipped when `existingSecret` is set)                           |
| Simulated LLM models                                        | `llmisvc`               | Multi-model templates                                                                        |
| MaaS subscriptions                                          | `maas-subscriptions`    | Subscription templates                                                                       |
| Observability DSCI + cluster monitoring                     | `openshift-ai`          | DSCInitialization + ConfigMap                                                                |
| `default-tenant` telemetry                                  | `maas-subscriptions`    | Job `patch-tenant-telemetry` (patches operator-created Tenant)                               |
| Restart `rhods-dashboard`                                   | `openshift-ai`          | Job `restart-rhods-dashboard`                                                                |
| WASM shim disconnected workaround                           | `rhcl`                  | Job `apply-wasm-shim-workaround` (optional via `disconnected.enabled`)                       |
| Gateway `default-gateway-config` (WASM insecure registries) | `gateway-api`           | ConfigMap `default-gateway-config` (optional via `disconnected.enabled`)                     |

Post-install Jobs use the cluster `toolsImage` (must include `oc` and `jq`) and run as Helm post-install/post-upgrade hooks.

## Chart Sources

| Chart                                                                                                                                                   | Source                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `install-operators`, `cert-manager`, `nvidia-gpu-enablement`, `leaderworkerset`, `rhcl`, `gateway-api`, `openshift-ai`, `llmisvc`, `maas-subscriptions` | Adapted from [openshift-setup](https://github.com/jharmison-redhat/openshift-setup) |
| `maas-postgres`, `observability-operators`, `service-mesh-operators`                                                                                    | Created from `[rhoai-3_4/](../rhoai-3_4/)` Kustomize manifests or repo additions    |

## Validation

Compare Helm output against Kustomize for parity:

```bash
# Gateway
helm template test charts/gateway-api \
  -f clusters/example.cluster.opentlc.com/cluster.yaml \
  -f clusters/example.cluster.opentlc.com/platform/values/gateway-api/values.yaml \
  | grep -A5 "kind: Gateway"

kustomize build ../rhoai-3_4/overlays/03-gateway | grep -A5 "kind: Gateway"

# Workload
helm template test charts/llmisvc \
  -f clusters/example.cluster.opentlc.com/cluster.yaml \
  -f clusters/example.cluster.opentlc.com/values/llmisvc/values.yaml
```

Render a chart locally without installing:

```bash
CLUSTER=clusters/example.cluster.opentlc.com

helm template test charts/gateway-api \
  -f $CLUSTER/cluster.yaml \
  -f $CLUSTER/platform/values/gateway-api/values.yaml

helm template test charts/openshift-ai \
  -f $CLUSTER/cluster.yaml \
  -f $CLUSTER/platform/values/openshift-ai/values.yaml
```
