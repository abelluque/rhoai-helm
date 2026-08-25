#!/usr/bin/env bash
# Post-install validation for the CPU-only OpenTLC lab.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

fail=0
check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "OK  ${desc}"
  else
    echo "FAIL ${desc}" >&2
    fail=1
  fi
}

echo "== Nodes (expect 0 GPUs) =="
oc get nodes -o wide
oc get nodes -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
gpu=0
for n in d.get("items",[]):
    g=n.get("status",{}).get("allocatable",{}).get("nvidia.com/gpu")
    if g:
        gpu += int(g)
        print(n["metadata"]["name"], "nvidia.com/gpu="+str(g))
print("total_gpus", gpu)
sys.exit(0 if gpu == 0 else 1)
' || fail=1

echo "== Gateway API (Ingress Operator) =="
check "GatewayClass openshift-default" oc get gatewayclass openshift-default
check "maas-default-gateway exists" oc get gateway maas-default-gateway -n openshift-ingress
oc get gatewayclass openshift-default -o yaml | grep -E 'Accepted|ControllerInstalled|CRDsReady' || true
oc get gateway maas-default-gateway -n openshift-ingress -o yaml | grep -E 'Programmed|Accepted|hostname' || true

echo "== DataScienceCluster / MaaS DB =="
check "DataScienceCluster exists" oc get datasciencecluster -A
check "maas-db-config secret" oc get secret maas-db-config -n redhat-ods-applications

echo "== Storage / Model Registry =="
check "StorageClass gp3-csi" oc get storageclass gp3-csi
check "Model Registry MySQL" oc get deploy model-registry-mysql -n rhoai-model-registries
check "ModelRegistry CR" oc get modelregistry rhoai-registry -n rhoai-model-registries
oc get pvc -n rhoai-model-registries || true

echo "== Platform placement =="
oc get nodes -l workload.rhoai.io/platform=true --no-headers || true

echo "== Lab SLM =="
check "LLMInferenceService granite-3-1-2b-instruct" oc get llminferenceservice granite-3-1-2b-instruct -n ai-models
oc get llminferenceservice -n ai-models || true
oc get pods -n ai-models -o wide || true

echo "== MaaS CRs =="
check "MaaSModelRef" oc get maasmodelref granite-3-1-2b-instruct -n ai-models
check "MaaSSubscription" oc get maassubscription -n models-as-a-service
check "MaaSAuthPolicy" oc get maasauthpolicy -n models-as-a-service

echo "== Live MaaS probe =="
if "${CLUSTER}/scripts/probe-maas.sh"; then
  echo "OK  mint API key + /v1/models + /v1/chat/completions"
else
  echo "FAIL mint API key + /v1/models + /v1/chat/completions" >&2
  fail=1
fi

exit "${fail}"
