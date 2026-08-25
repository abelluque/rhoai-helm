# Day-0 — OpenTLC lab (`cluster-6f7dh`)

Este overlay existe para **ensayar, corregir y validar** la instalación de RHOAI + MaaS en un cluster sin GPU, no para servir los modelos de producción.

Consola: https://console-openshift-console.apps.cluster-6f7dh.6f7dh.sandbox3519.opentlc.com/

Complete these steps **before** wave 5. Run `./scripts/day0.sh` after `oc login`. Helm **3.14+**.

## 1. Cluster login

```bash
oc login --server=https://api.cluster-6f7dh.6f7dh.sandbox3519.opentlc.com:6443
oc whoami
oc config current-context
```

Confirm the context contains `cluster-6f7dh` or `sandbox3519`. Hostname MaaS:

`maas.apps.cluster-6f7dh.6f7dh.sandbox3519.opentlc.com`

(`global.cluster.name=cluster-6f7dh`, `baseDomain=6f7dh.sandbox3519.opentlc.com` in [cluster.yaml](cluster.yaml).)

## 2. Node topology (6 nodes, no GPU)

Region **us-east-2**. Family **m6a** (AMD EPYC, AVX2 — required by `vllm-cpu-rhel9`).

| Role | Qty | Instance type | CPU | Memory | Filesystem | Schedulable | Workloads |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Control plane | 3 | m6a.2xlarge | 8 | 30.67 GiB | 99.78 GiB | **No** | Control plane |
| Worker | 3 | m6a.4xlarge | 16 | 61.46 GiB | 99.78 GiB | Yes | Platform + CPU SLM (label `workload.rhoai.io/platform=true`) |

There are **no** SuperMicro / H200 nodes. Do **not** install the NVIDIA GPU operator. Do **not** taint workers with `nvidia.com/gpu`.

```bash
export PLATFORM_NODES="ip-10-0-8-172.us-east-2.compute.internal ip-10-0-34-182.us-east-2.compute.internal ip-10-0-114-220.us-east-2.compute.internal"
./scripts/day0.sh
```

If `PLATFORM_NODES` is unset, `day0.sh` labels every non-control-plane node.

## 3. Pull secrets and entitlements

Cluster `pull-secret` in `openshift-config` should include `registry.redhat.io` (RHOAI, RHAIIS CPU image).

Operators this overlay installs:

- Red Hat OpenShift AI 3.4 (`rhods-operator` channel `stable-3.x`) including Model Registry
- OpenShift GitOps and OpenShift Pipelines (`platform-addons`)
- Red Hat Connectivity Link
- LeaderWorkerSet
- cert-manager (wave 1; set `install-cert-manager.enabled: false` if RHDP already installed it)
- Tempo / Cluster Observability / OpenTelemetry

Do **not** subscribe to NVIDIA GPU Operator or Node Feature Discovery. Do **not** install `charts/service-mesh-operators` (legacy reference only; Gateway API is owned by the Ingress Operator on OCP 4.19+). See [charts/service-mesh-operators/README.md](../../charts/service-mesh-operators/README.md).

Charts use `installPlanApproval: Manual`:

```bash
./scripts/approve-installplans.sh
```

## 4. PostgreSQL (`maas-db-config`)

This lab **deploys in-cluster Postgres** in wave 4. You do **not** need `MAAS_DB_CONNECTION_URL` on day-0. The Job `create-maas-db-config` writes Secret `maas-db-config` in `redhat-ods-applications` before wave 5.

Lab credentials (not for production): user `maas`, password `opentlc-lab`, database `maas`.

## 5. Hugging Face token

The lab SLM (`ibm-granite/granite-3.1-2b-instruct`) is public. A `hf-token` Secret is **not** required. If a download is rate-limited, create one in `ai-models` the same way as on `ocpai-prd-mtz`.

## 6. Storage

AWS **gp3-csi** (RWO). Nutanix Files is not used. Model Registry / notebook / pipeline PVCs are sized down and RWO so they bind on EBS.

```bash
oc get storageclass
```

## 7. TLS / cert-manager

Wave 1 installs the cert-manager operator into `cert-manager-operator`. OpenTLC usually **already created that namespace**; the chart skips the Namespace (and OperatorGroup) when they exist so Helm does not try to import them. MaaS is exposed with an OpenShift Route (`edge`) on `maas.apps.cluster-6f7dh.6f7dh.sandbox3519.opentlc.com`.

If the operator CSV is already `Succeeded`, set `install-cert-manager.enabled: false` instead of reinstalling.
