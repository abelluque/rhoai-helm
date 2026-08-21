#!/usr/bin/env bash
# Day-0: label workers as platform. No GPU taints. Postgres is in-cluster (wave 4).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

echo "== Who am I =="
oc whoami
oc config current-context

echo "== Label worker nodes workload.rhoai.io/platform=true (skip control-plane) =="
if [[ -n "${PLATFORM_NODES:-}" ]]; then
  for n in ${PLATFORM_NODES}; do
    echo "Label platform node ${n}"
    oc label node "${n}" workload.rhoai.io/platform=true --overwrite
  done
else
  oc get nodes -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for n in d["items"]:
    labels=n["metadata"].get("labels",{})
    name=n["metadata"]["name"]
    if labels.get("node-role.kubernetes.io/master") is not None or labels.get("node-role.kubernetes.io/control-plane") is not None:
        continue
    print(name)
' | while read -r n; do
    [[ -z "${n}" ]] && continue
    oc label node "${n}" workload.rhoai.io/platform=true --overwrite
  done
fi

echo
echo "== Nodes =="
oc get nodes -o wide
echo
echo "== Instance types / roles =="
oc get nodes -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.node-role\\.kubernetes\\.io/worker,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,CPU:.status.capacity.cpu,MEM:.status.capacity.memory --no-headers || oc get nodes
echo
echo "== StorageClasses =="
oc get storageclass
echo
echo "== Global pull-secret keys =="
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin).get("auths",{}).keys())))' 2>/dev/null \
  || echo "(could not decode pull-secret)"

echo
echo "This lab has no GPUs. Do not taint nodes or install nvidia-gpu-enablement."
echo "maas-db-config is created in wave 4 (in-cluster Postgres)."
echo
echo "Day-0 checks finished. Next: ./scripts/install-waves.sh"
