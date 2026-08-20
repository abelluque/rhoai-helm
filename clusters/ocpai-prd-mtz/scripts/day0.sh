#!/usr/bin/env bash
# Day-0 checks and optional secret provisioning for ocpai-prd-mtz.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

echo "== Who am I =="
oc whoami
oc config current-context

echo "== Node placement (platform VMs vs SuperMicro GPU) =="
if [[ -n "${PLATFORM_NODES:-}" ]]; then
  for n in ${PLATFORM_NODES}; do
    echo "Label platform node ${n}"
    oc label node "${n}" workload.rhoai.io/platform=true --overwrite
  done
else
  echo "PLATFORM_NODES not set; labeling non-master nodes without nvidia.com/gpu.present"
  oc get nodes -o json | python3 -c '
import json,sys,subprocess
d=json.load(sys.stdin)
for n in d["items"]:
    labels=n["metadata"].get("labels",{})
    name=n["metadata"]["name"]
    if labels.get("node-role.kubernetes.io/master") is not None or labels.get("node-role.kubernetes.io/control-plane") is not None:
        continue
    if labels.get("nvidia.com/gpu.present") == "true":
        continue
    print(name)
' | while read -r n; do
    [[ -z "${n}" ]] && continue
    oc label node "${n}" workload.rhoai.io/platform=true --overwrite
  done
fi

if [[ -n "${GPU_NODES:-}" ]]; then
  for n in ${GPU_NODES}; do
    echo "Taint/label GPU node ${n}"
    oc label node "${n}" nvidia.com/gpu.present=true --overwrite
    oc adm taint node "${n}" nvidia.com/gpu=true:NoSchedule --overwrite || true
  done
else
  echo "GPU_NODES not set; tainting nodes already labeled nvidia.com/gpu.present=true"
  oc get nodes -l nvidia.com/gpu.present=true -o name | while read -r n; do
    oc adm taint "${n}" nvidia.com/gpu=true:NoSchedule --overwrite || true
  done
fi

echo
echo "== Nodes =="
oc get nodes -o wide
echo
echo "== GPU-present labels =="
oc get nodes -l nvidia.com/gpu.present=true -o custom-columns=NAME:.metadata.name,GPUS:.status.allocatable.nvidia\\.com/gpu --no-headers || true
echo
echo "== Taints =="
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'
echo
echo "== StorageClasses =="
oc get storageclass
echo
echo "== Global pull-secret keys =="
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin).get("auths",{}).keys())))' 2>/dev/null \
  || echo "(could not decode pull-secret)"

echo
echo "== Ensure redhat-ods-applications exists (for maas-db-config) =="
oc create namespace redhat-ods-applications --dry-run=client -o yaml | oc apply -f -

if [[ -n "${MAAS_DB_CONNECTION_URL:-}" ]]; then
  echo "Creating/updating Secret maas-db-config from MAAS_DB_CONNECTION_URL"
  oc create secret generic maas-db-config -n redhat-ods-applications \
    --from-literal=DB_CONNECTION_URL="${MAAS_DB_CONNECTION_URL}" \
    --dry-run=client -o yaml | oc apply -f -
else
  echo "MAAS_DB_CONNECTION_URL not set; expecting an existing maas-db-config Secret."
fi

if oc get secret maas-db-config -n redhat-ods-applications >/dev/null 2>&1; then
  echo "OK: maas-db-config present"
else
  echo "MISSING: Secret maas-db-config in redhat-ods-applications (required before wave 5)" >&2
  exit 1
fi

echo
echo "== Hugging Face token (optional now; required before model install) =="
oc create namespace ai-models --dry-run=client -o yaml | oc apply -f -
if [[ -n "${HF_TOKEN:-}" ]]; then
  oc create secret generic hf-token -n ai-models \
    --from-literal=HF_TOKEN="${HF_TOKEN}" \
    --dry-run=client -o yaml | oc apply -f -
  echo "OK: hf-token created/updated in ai-models"
elif oc get secret hf-token -n ai-models >/dev/null 2>&1; then
  echo "OK: hf-token already present"
else
  echo "WARNING: hf-token not found in ai-models. Create it before ./scripts/install-models.sh"
fi

echo
echo "Day-0 checks finished. Next: ./scripts/install-waves.sh"
