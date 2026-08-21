#!/usr/bin/env bash
# Shared paths for the OpenTLC lab overlay.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLUSTER="${CLUSTER:-${ROOT}/clusters/opentlc}"
CHARTS="${CHARTS:-${ROOT}/charts}"

helm_cluster_flags() {
  echo -f "${CLUSTER}/cluster.yaml"
}

require_oc() {
  command -v oc >/dev/null 2>&1 || { echo "oc is required" >&2; exit 1; }
  command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
  oc whoami >/dev/null 2>&1 || { echo "Not logged in to OpenShift. Run oc login first." >&2; exit 1; }
  local helm_major helm_minor
  helm_major="$(helm version --template '{{.Version}}' 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')"
  helm_minor="$(helm version --template '{{.Version}}' 2>/dev/null | sed -E 's/^v[0-9]+\.([0-9]+).*/\1/')"
  if [[ "${helm_major:-0}" -lt 3 ]] || [[ "${helm_major:-0}" -eq 3 && "${helm_minor:-0}" -lt 14 ]]; then
    echo "Helm 3.14+ is required (found $(helm version --short))." >&2
    exit 1
  fi
}

warn_if_wrong_cluster() {
  local ctx
  ctx="$(oc config current-context 2>/dev/null || true)"
  if [[ "${ctx}" != *cluster-6f7dh* && "${ctx}" != *sandbox3519* ]]; then
    echo "WARNING: current context '${ctx}' does not look like cluster-6f7dh / sandbox3519." >&2
    echo "Set CONFIRM_WRONG_CLUSTER=1 to continue anyway." >&2
    if [[ "${CONFIRM_WRONG_CLUSTER:-}" != "1" ]]; then
      exit 1
    fi
  fi
}

approve_installplans() {
  local ns
  for ns in "$@"; do
    oc get installplan -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.approved}{"\n"}{end}' 2>/dev/null \
      | while IFS=$'\t' read -r name approved; do
          [[ -z "${name}" ]] && continue
          if [[ "${approved}" != "true" ]]; then
            echo "Approving InstallPlan ${name} in ${ns}"
            oc patch installplan "${name}" -n "${ns}" --type merge -p '{"spec":{"approved":true}}'
          fi
        done
  done
}

wait_csv() {
  local ns="$1"
  local grep_name="$2"
  local timeout="${3:-600}"
  echo "Waiting for CSV matching '${grep_name}' in ${ns} (timeout ${timeout}s)"
  local elapsed=0
  while (( elapsed < timeout )); do
    if oc get csv -n "${ns}" --no-headers 2>/dev/null | grep -E "${grep_name}" | grep -q Succeeded; then
      echo "CSV ${grep_name} Succeeded"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "Timed out waiting for CSV ${grep_name} in ${ns}" >&2
  oc get csv -n "${ns}" || true
  return 1
}

wait_job() {
  local ns="$1"
  local name="$2"
  local timeout="${3:-900}"
  echo "Waiting for Job/${name} in ${ns}"
  oc wait --for=condition=complete "job/${name}" -n "${ns}" --timeout="${timeout}s" 2>/dev/null \
    || oc wait --for=condition=complete "job/${name}" -n "${ns}" --timeout="${timeout}s"
}
