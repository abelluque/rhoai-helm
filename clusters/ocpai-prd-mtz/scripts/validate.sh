#!/usr/bin/env bash
# Post-install validation for MaaS on ocpai-prd-mtz.
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

echo "== GPU capacity =="
oc get nodes -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
total=0
gpu_nodes=0
for n in d.get("items",[]):
    g=n.get("status",{}).get("allocatable",{}).get("nvidia.com/gpu")
    if g:
        gpu_nodes += 1
        total += int(g)
        print(n["metadata"]["name"], "nvidia.com/gpu="+str(g))
print("gpu_nodes", gpu_nodes, "total_gpus", total)
sys.exit(0 if gpu_nodes >= 2 and total >= 12 else 1)
' || fail=1

echo "== Gateway =="
check "maas-default-gateway exists" oc get gateway maas-default-gateway -n openshift-ingress
oc get gateway maas-default-gateway -n openshift-ingress -o yaml | grep -E 'Programmed|Accepted|hostname' || true

echo "== DataScienceCluster / MaaS DB =="
check "DataScienceCluster exists" oc get datasciencecluster -A
check "maas-db-config secret" oc get secret maas-db-config -n redhat-ods-applications

echo "== Storage / Model Registry =="
check "StorageClass nutanix-files-dynamic" oc get storageclass nutanix-files-dynamic
check "Model Registry MySQL" oc get deploy model-registry-mysql -n rhoai-model-registries
check "ModelRegistry CR" oc get modelregistry rhoai-registry -n rhoai-model-registries
oc get pvc -n rhoai-model-registries || true

echo "== Platform placement =="
oc get nodes -l workload.rhoai.io/platform=true --no-headers || true
oc get nodes -l nvidia.com/gpu.present=true --no-headers || true

echo "== Models =="
for m in granite-3-0-8b-instruct qwen25-coder-32b deepseek-coder-33b; do
  check "LLMInferenceService ${m}" oc get llminferenceservice "${m}" -n ai-models
done
oc get llminferenceservice -n ai-models || true
oc get pods -n ai-models -o wide || true

echo "== MaaS CRs =="
check "MaaSModelRef" oc get maasmodelref -n ai-models
check "MaaSSubscription" oc get maassubscription -n models-as-a-service
check "MaaSAuthPolicy" oc get maasauthpolicy -n models-as-a-service

NAME="$(python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))["global"]["cluster"]["name"])' "${CLUSTER}/cluster.yaml")"
DOMAIN="$(python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))["global"]["cluster"]["baseDomain"])' "${CLUSTER}/cluster.yaml")"
HOST="maas.apps.${NAME}.${DOMAIN}"
echo
echo "Probe MaaS (requires an API key from the MaaS dashboard):"
echo "  curl -sk https://${HOST}/v1/models -H 'Authorization: Bearer <MAAS_API_KEY>'"
echo "  curl -sk https://${HOST}/v1/chat/completions -H 'Authorization: Bearer <MAAS_API_KEY>' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"granite-3-0-8b-instruct\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"

if [[ -n "${MAAS_API_KEY:-}" ]]; then
  echo "== Live chat completions =="
  for model in granite-3-0-8b-instruct qwen25-coder-32b deepseek-coder-33b; do
    echo "-- ${model} --"
    curl -sk "https://${HOST}/v1/chat/completions" \
      -H "Authorization: Bearer ${MAAS_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with pong\"}],\"max_tokens\":16}" \
      && echo || fail=1
  done
else
  echo "Set MAAS_API_KEY to run live inference probes."
fi

exit "${fail}"
