#!/bin/bash
set -euo pipefail

CSV_PIN="${RHCL_CSV:-}"
NAMESPACE="${RHCL_NAMESPACE:?RHCL_NAMESPACE required}"
GATEWAY_CONTROLLERS="${ISTIO_GATEWAY_CONTROLLER_NAMES:?ISTIO_GATEWAY_CONTROLLER_NAMES required}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
SUBSCRIPTION="${RHCL_SUBSCRIPTION:-rhcl-operator}"

resolve_csv() {
  local current
  if [ -n "${CSV_PIN}" ] && oc get csv "${CSV_PIN}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "${CSV_PIN}"
    return 0
  fi
  current=$(oc get subscription "${SUBSCRIPTION}" -n "${NAMESPACE}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
  if [ -n "${current}" ] && oc get csv "${current}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "${current}"
    return 0
  fi
  current=$(oc get csv -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '/rhcl-operator/ {print $1; exit}')
  if [ -n "${current}" ]; then
    echo "${current}"
    return 0
  fi
  return 1
}

echo "Waiting up to ${WAIT_TIMEOUT}s for RHCL CSV in ${NAMESPACE}..."
elapsed=0
CSV_NAME=""
while true; do
  if CSV_NAME=$(resolve_csv); then
    echo "Using CSV ${CSV_NAME}"
    break
  fi
  if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
    echo "Timed out waiting for RHCL CSV (pin=${CSV_PIN:-none}). Need an OperatorGroup in ${NAMESPACE}." >&2
    oc get csv,sub,og -n "${NAMESPACE}" >&2 || true
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

ENV_INDEX=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
  jq -r '
    (.spec.install.spec.deployments[0].spec.template.spec.containers[0].env | map(.name) | index("ISTIO_GATEWAY_CONTROLLER_NAMES")) as $i |
    if $i == null then empty else ($i | tostring) end')

if [ -z "${ENV_INDEX}" ]; then
  echo "ISTIO_GATEWAY_CONTROLLER_NAMES not found in CSV ${CSV_NAME}" >&2
  exit 1
fi

CURRENT=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
  jq -r ".spec.install.spec.deployments[0].spec.template.spec.containers[0].env[${ENV_INDEX}].value")

if [ "${CURRENT}" = "${GATEWAY_CONTROLLERS}" ]; then
  echo "CSV already patched"
  exit 0
fi

oc patch csv "${CSV_NAME}" -n "${NAMESPACE}" --type=json -p \
  "[{\"op\":\"replace\",\"path\":\"/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/${ENV_INDEX}/value\",\"value\":\"${GATEWAY_CONTROLLERS}\"}]"

echo "Patched ISTIO_GATEWAY_CONTROLLER_NAMES on ${CSV_NAME}"
