#!/usr/bin/env bash
# Waves 1–5: operators, GPU, Connectivity Link, Gateway API, Postgres wiring, OpenShift AI / MaaS.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

cd "${ROOT}"

echo "Updating Helm chart dependencies..."
for c in cert-manager nvidia-gpu-enablement rhcl leaderworkerset openshift-ai observability-operators platform-addons; do
  (cd "${CHARTS}/${c}" && helm dependency update)
done

echo "== Wave 1: cert-manager + observability-operators + platform-addons =="
helm upgrade --install cert-manager "${CHARTS}/cert-manager" -n cert-manager-operator --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/cert-manager/values.yaml"
helm upgrade --install observability-operators "${CHARTS}/observability-operators" -n openshift-operators \
  --timeout 20m \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/observability-operators/values.yaml"
helm upgrade --install platform-addons "${CHARTS}/platform-addons" -n rhoai-model-registries --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/platform-addons/values.yaml" \
  --set modelRegistry.createCR=false
./clusters/ocpai-prd-mtz/scripts/approve-installplans.sh cert-manager-operator openshift-operators openshift-gitops-operator || true
wait_csv cert-manager-operator cert-manager-operator 600 || true
wait_csv openshift-operators 'tempo|opentelemetry|cluster-observability' 600 || true

echo "== Wave 2: NVIDIA GPU + LeaderWorkerSet + RHCL =="
helm upgrade --install nvidia-gpu-enablement "${CHARTS}/nvidia-gpu-enablement" -n openshift-nfd --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/nvidia-gpu-enablement/values.yaml"
helm upgrade --install leaderworkerset "${CHARTS}/leaderworkerset" -n openshift-lws-operator --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/leaderworkerset/values.yaml"
helm upgrade --install rhcl "${CHARTS}/rhcl" -n kuadrant-system --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/rhcl/values.yaml"
./clusters/ocpai-prd-mtz/scripts/approve-installplans.sh openshift-nfd nvidia-gpu-operator openshift-lws-operator kuadrant-system || true
wait_csv openshift-nfd nfd 900 || true
wait_csv nvidia-gpu-operator gpu-operator 900 || true
wait_csv kuadrant-system 'rhcl|kuadrant' 900 || true
wait_job openshift-nfd apply-nfd-instance 900 || true
wait_job nvidia-gpu-operator apply-gpu-cluster-policy 900 || true
wait_job openshift-lws-operator apply-leaderworkerset 900 || true
wait_job kuadrant-system apply-kuadrant 900 || true

echo "GPU allocatable:"
oc get nodes -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
total=0
for n in d.get("items",[]):
    g=n.get("status",{}).get("allocatable",{}).get("nvidia.com/gpu","0")
    print(n["metadata"]["name"], g)
    try: total += int(g)
    except: pass
print("TOTAL_GPUS", total)
'

echo "== Wave 3: Gateway API (Ingress Operator on OpenShift 4.22) =="
# charts/service-mesh-operators is legacy reference only — do not helm-install it.
# OCP 4.22 Ingress Operator vendors Gateway API CRDs. Creating GatewayClass
# openshift-default (controllerName: openshift.io/gateway-controller/v1) deploys
# a lightweight Istio control plane in openshift-ingress. A second
# servicemeshoperator3 CSV via OLM can conflict (duplicate Istio CRDs / two
# controllers). See charts/service-mesh-operators/README.md.
helm upgrade --install gateway-api "${CHARTS}/gateway-api" -n openshift-ingress \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/gateway-api/values.yaml"
oc get gatewayclass openshift-default || true
oc get gateway maas-default-gateway -n openshift-ingress || true

echo "== Wave 4: MaaS Postgres wiring (external secret only) =="
if ! oc get secret maas-db-config -n redhat-ods-applications >/dev/null 2>&1; then
  echo "Secret maas-db-config missing. Re-run ./scripts/day0.sh with MAAS_DB_CONNECTION_URL." >&2
  exit 1
fi
helm upgrade --install maas-postgres "${CHARTS}/maas-postgres" -n redhat-ods-applications --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/maas-postgres/values.yaml"

echo "== Wave 5: OpenShift AI + MaaS =="
helm upgrade --install openshift-ai "${CHARTS}/openshift-ai" -n redhat-ods-operator --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/openshift-ai/values.yaml"
./clusters/ocpai-prd-mtz/scripts/approve-installplans.sh redhat-ods-operator || true
wait_csv redhat-ods-operator rhods-operator 1200
wait_job redhat-ods-operator apply-dsci 900 || true
wait_job redhat-ods-operator apply-dsc 1200 || true

echo "== Wave 5b: ModelRegistry CR =="
helm upgrade --install platform-addons "${CHARTS}/platform-addons" -n rhoai-model-registries \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/platform-addons/values.yaml" \
  --set modelRegistry.createCR=true

echo "Waves 1–5 submitted. Next: ./scripts/install-models.sh"
echo "Check: oc get datasciencecluster,dscinitialization -A"
