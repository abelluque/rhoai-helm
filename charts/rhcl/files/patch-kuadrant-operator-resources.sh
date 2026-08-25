#!/bin/bash
set -euo pipefail

NAMESPACE="${KUADRANT_NAMESPACE:?KUADRANT_NAMESPACE required}"
DEPLOYMENT="${KUADRANT_CONTROLLER_DEPLOYMENT:-kuadrant-operator-controller-manager}"
RHCL_SUBSCRIPTION="${RHCL_SUBSCRIPTION:-rhcl-operator}"
RHCL_CSV_FALLBACK="${RHCL_CSV:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"
BEST_EFFORT="${BEST_EFFORT:-true}"
MEMORY_REQUEST="${CONTROLLER_MEMORY_REQUEST:?CONTROLLER_MEMORY_REQUEST required}"
MEMORY_LIMIT="${CONTROLLER_MEMORY_LIMIT:?CONTROLLER_MEMORY_LIMIT required}"
CPU_REQUEST="${CONTROLLER_CPU_REQUEST:?CONTROLLER_CPU_REQUEST required}"
CPU_LIMIT="${CONTROLLER_CPU_LIMIT:?CONTROLLER_CPU_LIMIT required}"

RESOURCES_JSON=$(jq -cn \
  --arg mr "${MEMORY_REQUEST}" \
  --arg ml "${MEMORY_LIMIT}" \
  --arg cr "${CPU_REQUEST}" \
  --arg cl "${CPU_LIMIT}" \
  '{requests: {memory: $mr, cpu: $cr}, limits: {memory: $ml, cpu: $cl}}')

resources_equal() {
  local current="$1"
  jq -e -n --argjson current "${current}" --argjson expected "${RESOURCES_JSON}" '$current == $expected' >/dev/null
}

give_up() {
  local msg="$1"
  if [ "${BEST_EFFORT}" = "true" ]; then
    echo "WARNING: ${msg}; skipping so Helm is not blocked" >&2
    exit 0
  fi
  echo "Error: ${msg}" >&2
  exit 1
}

wait_for() {
  local description="$1"
  local check_cmd="$2"
  local elapsed=0

  while ! eval "${check_cmd}" >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
      give_up "timed out after ${WAIT_TIMEOUT}s waiting for ${description}"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

resolve_rhcl_csv() {
  local current

  if [ -n "${RHCL_CSV_FALLBACK}" ]; then
    if oc get csv "${RHCL_CSV_FALLBACK}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      echo "${RHCL_CSV_FALLBACK}"
      return 0
    fi
  fi

  current=$(oc get subscription "${RHCL_SUBSCRIPTION}" -n "${NAMESPACE}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
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

wait_for_rhcl_csv() {
  local elapsed=0

  while true; do
    if CSV_NAME=$(resolve_rhcl_csv); then
      echo "Using RHCL CSV ${CSV_NAME}"
      return 0
    fi
    if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
      oc get csv,sub,og,deploy -n "${NAMESPACE}" >&2 || true
      give_up "timed out after ${WAIT_TIMEOUT}s waiting for RHCL CSV in ${NAMESPACE}"
    fi
    echo "Waiting for RHCL CSV..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

patch_csv_resources() {
  wait_for_rhcl_csv

  DEPLOY_IDX=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
    jq -r --arg name "${DEPLOYMENT}" '
      (.spec.install.spec.deployments | map(.name) | index($name)) as $i |
      if $i == null then empty else ($i | tostring) end')

  if [ -z "${DEPLOY_IDX}" ]; then
    echo "Warning: ${DEPLOYMENT} not found in CSV ${CSV_NAME}; skipping CSV patch" >&2
    return 0
  fi

  CSV_CURRENT=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
    jq -c ".spec.install.spec.deployments[${DEPLOY_IDX}].spec.template.spec.containers[0].resources // {}")

  if resources_equal "${CSV_CURRENT}"; then
    echo "CSV resources already set"
    return 0
  fi

  echo "Patching CSV ${CSV_NAME} deployment index ${DEPLOY_IDX}..."
  oc patch csv "${CSV_NAME}" -n "${NAMESPACE}" --type=json -p \
    "[{\"op\":\"replace\",\"path\":\"/spec/install/spec/deployments/${DEPLOY_IDX}/spec/template/spec/containers/0/resources\",\"value\":${RESOURCES_JSON}}]"
}

patch_deployment_resources() {
  wait_for "${DEPLOYMENT} in ${NAMESPACE}" "oc get deployment \"${DEPLOYMENT}\" -n \"${NAMESPACE}\""

  CURRENT=$(oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | \
    jq -c '.spec.template.spec.containers[] | select(.name == "manager") | .resources // {}')

  CONTAINER_IDX=$(oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | \
    jq -r '
      (.spec.template.spec.containers | map(.name) | index("manager")) as $i |
      if $i == null then empty else ($i | tostring) end')

  if [ -z "${CONTAINER_IDX}" ]; then
    give_up "manager container not found in ${DEPLOYMENT}"
  fi

  if resources_equal "${CURRENT}"; then
    echo "${DEPLOYMENT} resources already set"
    return 0
  fi

  echo "Patching ${DEPLOYMENT} resources (request memory=${MEMORY_REQUEST}, limit memory=${MEMORY_LIMIT})..."
  oc patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --type=json -p \
    "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/${CONTAINER_IDX}/resources\",\"value\":${RESOURCES_JSON}}]"
}

patch_csv_resources
patch_deployment_resources

echo "Kuadrant controller resources patched"
