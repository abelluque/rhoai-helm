#!/usr/bin/env bash
# Wave 8 models then wave 7 MaaS subscriptions (simulators are not installed).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

cd "${ROOT}"

if ! oc get secret hf-token -n ai-models >/dev/null 2>&1; then
  echo "Secret hf-token missing in ai-models. Export HF_TOKEN and re-run ./scripts/day0.sh" >&2
  exit 1
fi

echo "== Wave 8: LLMInferenceService models =="
helm upgrade --install llmisvc-granite-3-0-8b "${CHARTS}/llmisvc" -n ai-models --create-namespace \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/llmisvc/granite-3.0-8b-instruct.yaml"

helm upgrade --install llmisvc-qwen25-coder-32b "${CHARTS}/llmisvc" -n ai-models \
  --set namespace.create=false \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/llmisvc/qwen2.5-coder-32b.yaml"

helm upgrade --install llmisvc-deepseek-coder-33b "${CHARTS}/llmisvc" -n ai-models \
  --set namespace.create=false \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/llmisvc/deepseek-coder-33b.yaml"

echo "== Wave 7: MaaS subscriptions / auth policies =="
helm upgrade --install maas-subscriptions "${CHARTS}/maas-subscriptions" -n models-as-a-service --create-namespace \
  -f "${CLUSTER}/cluster.yaml" \
  -f "${CLUSTER}/values/maas-subscriptions/values.yaml"

echo "Models and subscriptions submitted. Next: ./scripts/validate.sh"
