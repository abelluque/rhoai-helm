#!/usr/bin/env bash
# Approve pending OLM InstallPlans (charts use installPlanApproval: Manual).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_oc
warn_if_wrong_cluster

NAMESPACES=(
  cert-manager-operator
  openshift-operators
  openshift-lws-operator
  kuadrant-system
  redhat-ods-operator
  openshift-gitops-operator
)

if [[ $# -gt 0 ]]; then
  NAMESPACES=("$@")
fi

approve_installplans "${NAMESPACES[@]}"
echo "InstallPlan approval pass complete."
