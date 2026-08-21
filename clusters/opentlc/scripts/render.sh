#!/usr/bin/env bash
# Render overlay manifests locally (no cluster required).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
cd "${ROOT}"

OUT="${ROOT}/clusters/opentlc/.rendered"
mkdir -p "${OUT}"

render() {
  local name="$1"
  shift
  echo "Rendering ${name}"
  helm template "$@" > "${OUT}/${name}.yaml"
}

render gateway-api gateway-api "${CHARTS}/gateway-api" \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/gateway-api/values.yaml"

render maas-postgres maas-postgres "${CHARTS}/maas-postgres" \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/maas-postgres/values.yaml"

render granite llmisvc "${CHARTS}/llmisvc" -n ai-models \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/values/llmisvc/granite-3.1-2b-instruct.yaml"

render maas-subscriptions maas-subscriptions "${CHARTS}/maas-subscriptions" -n models-as-a-service \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/values/maas-subscriptions/values.yaml"

if [[ ! -f "${CHARTS}/platform-addons/charts/install-operators-0.1.0.tgz" ]]; then
  mkdir -p "${CHARTS}/platform-addons/charts"
  helm package "${CHARTS}/install-operators" -d "${CHARTS}/platform-addons/charts" >/dev/null
fi

render platform-addons platform-addons "${CHARTS}/platform-addons" -n rhoai-model-registries \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/platform-addons/values.yaml" \
  --set install-platform-operators.enabled=false \
  --set modelRegistry.createCR=true

echo "Rendered manifests in ${OUT}"
