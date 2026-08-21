#!/usr/bin/env bash
# Wave 8: CPU SLM, then wave 7 MaaS subscriptions. No GPU models from ocpai-prd-mtz.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

cd "${ROOT}"

echo "== Wave 8: Granite 3.1 2B Instruct (CPU) =="
helm upgrade --install llmisvc-granite-3-1-2b "${CHARTS}/llmisvc" -n ai-models --create-namespace \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/llmisvc/granite-3.1-2b-instruct.yaml"

echo "== Wave 7: MaaS subscriptions / auth policies =="
helm upgrade --install maas-subscriptions "${CHARTS}/maas-subscriptions" -n models-as-a-service --create-namespace \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/maas-subscriptions/values.yaml"

echo "Model and subscriptions submitted. Next: ./scripts/validate.sh"
