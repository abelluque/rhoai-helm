# Day-0 prerequisites — ocpai-prd-mtz

Complete these steps **before** wave 5 (`openshift-ai`). Run `./scripts/day0.sh` after `oc login`.

## 1. Cluster login and identity

Required CLI:

- `oc` (cluster-admin)
- Helm **3.14+** (platform charts use `append`/`mergeOverwrite`; Helm 3.2 will fail to template `openshift-ai`)

```bash
oc login --server=<api.ocpai-prd-mtz...>
oc whoami
oc config current-context
```

Confirm you are cluster-admin on **ocpai-prd-mtz**, not a sandbox. Edit [cluster.yaml](cluster.yaml) `global.cluster.baseDomain` so the MaaS hostname becomes:

`maas.apps.ocpai-prd-mtz.<baseDomain>`

## 2. Node topology (11 nodes)

| Role | Qty | Hardware | Schedulable | Workloads |
| --- | --- | --- | --- | --- |
| Masters | 3 | VM, 12 vCPU / 64 Gi | **No** | Control plane |
| Infra | 3 | VM, 16 vCPU / 64 Gi | Yes | Platform (label `workload.rhoai.io/platform=true`) |
| Workers virt | 3 | VM, 12 vCPU / 32 Gi | Yes | Same platform label |
| Workers GPU | 2 | SuperMicro SYS-521GE-TNRT, 128 vCPU / 1500 Gi, 6× H200 | Yes, GPU taint | LLM inference only |

```bash
export GPU_NODES="supermicro-1 supermicro-2"
export PLATFORM_NODES="infra-1 infra-2 infra-3 worker-vm-1 worker-vm-2 worker-vm-3"
./scripts/day0.sh
```

`day0.sh` aplica:

- `oc label node <platform> workload.rhoai.io/platform=true`
- `oc adm taint node <gpu> nvidia.com/gpu=true:NoSchedule --overwrite`
- `oc label node <gpu> nvidia.com/gpu.present=true --overwrite`

Do not run inference on masters. GPU Operator DaemonSets tolerate the GPU taint; RHOAI/GitOps/Pipelines/SM/RHCL/Authorino do not, so they stay on VMs.

After wave 2, each SuperMicro must show `nvidia.com/gpu: 6` Allocatable.

## 3. Pull secrets and entitlements

Cluster `pull-secret` in `openshift-config` must include:

- `registry.redhat.io` (RHOAI, RHAIIS vLLM, RHEL AI)
- `nvcr.io` / NGC if the NVIDIA operator needs it
- Hugging Face is not a pull secret; it uses Secret `hf-token` in `ai-models`

Subscriptions / operators this overlay expects:

- Red Hat OpenShift AI 3.4 (`rhods-operator` channel `stable-3.x`) including **Model Registry**
- OpenShift GitOps and OpenShift Pipelines (wave 1 `platform-addons`)
- Red Hat Connectivity Link
- OpenShift Service Mesh 3 (`servicemeshoperator3.v3.3.3` pin)
- NVIDIA GPU Operator certified + Node Feature Discovery
- cert-manager (installed in wave 1 unless you disable it)

Charts use `installPlanApproval: Manual`. After each operator Subscription appears, approve InstallPlans:

```bash
./scripts/approve-installplans.sh
```

## 4. External PostgreSQL (`maas-db-config`)

MaaS stores API keys in PostgreSQL. In-cluster Postgres is **disabled**. Create this Secret in `redhat-ods-applications` **before wave 5**:

```bash
oc create namespace redhat-ods-applications --dry-run=client -o yaml | oc apply -f -
oc create secret generic maas-db-config -n redhat-ods-applications \
  --from-literal=DB_CONNECTION_URL='postgresql://maas:<password>@<host>:5432/maas?sslmode=require' \
  --dry-run=client -o yaml | oc apply -f -
```

See [secrets/maas-db-config.secret.yaml.example](secrets/maas-db-config.secret.yaml.example).

If this Secret is missing when the DataScienceCluster reconciles MaaS:

`database Secret 'maas-db-config' not found in namespace 'redhat-ods-applications'`

## 5. Hugging Face token

Required to pull `hf://` models (Qwen2.5-Coder FP8, DeepSeek-Coder, Granite). Create after namespace `ai-models` exists (wave 8 creates it), or create the namespace first:

```bash
oc create namespace ai-models --dry-run=client -o yaml | oc apply -f -
oc create secret generic hf-token -n ai-models \
  --from-literal=HF_TOKEN='hf_...' \
  --dry-run=client -o yaml | oc apply -f -
```

Do not commit tokens. Model values reference `huggingface.existingSecret: hf-token`.

## 6. Nutanix Files StorageClass

Set `storage.files.parameters.nfsServerName` in `platform/values/platform-addons/values.yaml` to the Prism Files server **short name**. CSI secret `ntnx-secret` must exist in `openshift-cluster-csi-drivers`.

Wave 1 (`platform-addons`) creates StorageClass `nutanix-files-dynamic` (default) and PVCs listed in [INSTALL.md](INSTALL.md).

```bash
oc get storageclass
oc get pvc -A | grep -E 'model-registry|rhods-notebooks|pipelines-artifacts'
```

## 7. TLS / cert-manager

This overlay **installs cert-manager** (wave 1) and exposes MaaS via an OpenShift **Route** (`edge` TLS with the cluster ingress certificate) on `maas.apps.ocpai-prd-mtz.<baseDomain>`.

The Gateway still declares an HTTPS listener that references Secret `maas-default-gateway-tls` in `openshift-ingress`. The Route uses listener **HTTP/80**, so MaaS works without that Secret. To program Gateway HTTPS later, create the Secret or set `listeners.https.certificate.create: true` with a ClusterIssuer.

If Venafi/cert-manager is already present:

1. Set `install-cert-manager.enabled: false` in `platform/values/cert-manager/values.yaml`
2. Point `platform/values/gateway-api/values.yaml` at your ClusterIssuer (see the example overlay)

## 8. GPU time-slicing

Left at `timeSlices: 1` (exclusive GPUs). Do not enable MIG/time-slicing for these three LLMInferenceServices.
