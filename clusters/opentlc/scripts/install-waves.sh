#!/usr/bin/env bash
# Waves 1–5 for the CPU-only OpenTLC lab. Skips NVIDIA GPU operator.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

cd "${ROOT}"

echo "Updating Helm chart dependencies..."
for c in cert-manager rhcl leaderworkerset openshift-ai observability-operators platform-addons; do
  (cd "${CHARTS}/${c}" && helm dependency update)
done

echo "== Wave 1: cert-manager + observability-operators + platform-addons =="
# OpenTLC/RHDP often pre-creates cert-manager-operator. Do not pass
# --take-ownership: that would put the platform Namespace into the Helm
# release and helm uninstall would delete it. The chart skips existing NS/OG.
# Same for openshift-gitops-operator / openshift-gitops / openshift-pipelines.
helm upgrade --install cert-manager "${CHARTS}/cert-manager" -n cert-manager-operator --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/cert-manager/values.yaml"
helm upgrade --install observability-operators "${CHARTS}/observability-operators" -n openshift-operators \
  --timeout 20m \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/observability-operators/values.yaml"
reset_broken_helm_release platform-addons rhoai-model-registries
helm upgrade --install platform-addons "${CHARTS}/platform-addons" -n rhoai-model-registries --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/platform-addons/values.yaml" \
  --set modelRegistry.createCR=false
./clusters/opentlc/scripts/approve-installplans.sh cert-manager-operator openshift-operators openshift-gitops-operator \
  openshift-tempo-operator openshift-opentelemetry-operator openshift-cluster-observability-operator || true
wait_csv cert-manager-operator cert-manager-operator 600 || true
wait_csv openshift-tempo-operator tempo 600 || true
wait_csv openshift-opentelemetry-operator opentelemetry 600 || true
wait_csv openshift-cluster-observability-operator cluster-observability 600 || true

echo "== Wave 2: LeaderWorkerSet + RHCL (no NVIDIA) =="
wait_ns_not_terminating openshift-lws-operator 900
wait_ns_not_terminating kuadrant-system 900
reset_broken_helm_release leaderworkerset openshift-lws-operator
helm upgrade --install leaderworkerset "${CHARTS}/leaderworkerset" -n openshift-lws-operator --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/leaderworkerset/values.yaml"
helm upgrade --install rhcl "${CHARTS}/rhcl" -n kuadrant-system --create-namespace \
  --timeout 15m \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/rhcl/values.yaml"
./clusters/opentlc/scripts/approve-installplans.sh openshift-lws-operator kuadrant-system || true
wait_csv kuadrant-system 'rhcl|kuadrant' 900 || true
wait_job openshift-lws-operator apply-leaderworkerset 900 || true
wait_job kuadrant-system apply-kuadrant 900 || true

echo "== Wave 3: Gateway API (Ingress Operator) =="
# charts/service-mesh-operators is legacy reference only — do not helm-install it.
helm upgrade --install gateway-api "${CHARTS}/gateway-api" -n openshift-ingress \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/gateway-api/values.yaml"
oc get gatewayclass openshift-default || true
oc get gateway maas-default-gateway -n openshift-ingress || true

echo "== Wave 4: in-cluster MaaS Postgres =="
helm upgrade --install maas-postgres "${CHARTS}/maas-postgres" -n redhat-ods-applications --create-namespace \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/maas-postgres/values.yaml"
wait_job redhat-ods-applications create-maas-db-config 600 || true

echo "== Wave 5: OpenShift AI + MaaS =="
# Subscriptions first (--no-hooks). HardwareProfile/DSC CRDs do not exist yet;
# hooks apply those CRs after the operator CSV is Succeeded.
helm upgrade --install openshift-ai "${CHARTS}/openshift-ai" -n redhat-ods-operator --create-namespace \
  --no-hooks \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/openshift-ai/values.yaml"
./clusters/opentlc/scripts/approve-installplans.sh redhat-ods-operator || true
wait_csv redhat-ods-operator rhods-operator 1200
helm upgrade --install openshift-ai "${CHARTS}/openshift-ai" -n redhat-ods-operator \
  --timeout 20m \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/openshift-ai/values.yaml"
wait_job redhat-ods-operator apply-dsci 900 || true
wait_job redhat-ods-applications apply-dsc 1200 || true
wait_job redhat-ods-applications apply-hardwareprofiles 600 || true

echo "== Wave 5b: ModelRegistry CR =="
helm upgrade --install platform-addons "${CHARTS}/platform-addons" -n rhoai-model-registries \
  -f "${CLUSTER}/cluster.yaml" -f "${CLUSTER}/platform/values/platform-addons/values.yaml" \
  --set modelRegistry.createCR=true

echo "Waves 1–5 submitted. Next: ./scripts/install-models.sh"
echo "Check: oc get datasciencecluster,dscinitialization -A"
