#!/bin/bash
set -euo pipefail

NAMESPACE="${PERSES_NAMESPACE:?PERSES_NAMESPACE required}"
DEPLOYMENT="${PERSES_DEPLOYMENT:-perses-operator}"
CONTAINER="${PERSES_CONTAINER:-perses-operator}"
COO_SUBSCRIPTION="${COO_SUBSCRIPTION:-cluster-observability-operator}"
COO_CSV_FALLBACK="${COO_CSV:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-120}"
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

is_csv_default_resources() {
  local current="$1"
  jq -e -n --argjson current "${current}" \
    '$current.requests.memory == "128Mi" and $current.requests.cpu == "100m"' >/dev/null
}

wait_for() {
  local description="$1"
  local check_cmd="$2"
  local elapsed=0

  while ! eval "${check_cmd}" >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
      echo "Timed out after ${WAIT_TIMEOUT}s waiting for ${description}" >&2
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

resolve_container_index() {
  local idx

  idx=$(oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | \
    jq -r --arg name "${CONTAINER}" '
      (.spec.template.spec.containers | map(.name) | index($name)) as $i |
      if $i == null then empty else ($i | tostring) end')

  if [ -n "${idx}" ]; then
    echo "${idx}"
    return 0
  fi

  if [ "$(oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | jq '.spec.template.spec.containers | length')" = "1" ]; then
    echo "0"
    return 0
  fi

  echo "Error: container ${CONTAINER} not found in ${DEPLOYMENT}" >&2
  exit 1
}

resolve_coo_csv() {
  local current

  if [ -n "${COO_CSV_FALLBACK}" ]; then
    if oc get csv "${COO_CSV_FALLBACK}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      echo "${COO_CSV_FALLBACK}"
      return 0
    fi
    echo "Pinned CSV ${COO_CSV_FALLBACK} not present yet; trying subscription currentCSV..." >&2
  fi

  current=$(oc get subscription "${COO_SUBSCRIPTION}" -n "${NAMESPACE}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
  if [ -n "${current}" ] && oc get csv "${current}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "${current}"
    return 0
  fi

  current=$(oc get csv -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '/cluster-observability-operator/ && /Succeeded|Replacing|Pending/ {print $1; exit}')
  if [ -n "${current}" ]; then
    echo "${current}"
    return 0
  fi

  return 1
}

wait_for_coo_csv() {
  local elapsed=0

  while true; do
    if CSV_NAME=$(resolve_coo_csv); then
      echo "Using COO CSV ${CSV_NAME}"
      return 0
    fi
    if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
      if [ -n "${COO_CSV_FALLBACK}" ]; then
        echo "Timed out after ${WAIT_TIMEOUT}s waiting for pinned CSV ${COO_CSV_FALLBACK}" >&2
      else
        echo "Timed out after ${WAIT_TIMEOUT}s waiting for COO CSV from subscription ${COO_SUBSCRIPTION}" >&2
      fi
      exit 1
    fi
    echo "Waiting for COO CSV..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

resolve_csv_container_index() {
  oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
    jq -r --arg deploy "${DEPLOYMENT}" --arg container "${CONTAINER}" '
      .spec.install.spec.deployments
      | map(select(.name == $deploy))
      | .[0].spec.template.spec.containers
      | map(.name)
      | index($container) // empty'
}

patch_csv_resources() {
  wait_for_coo_csv

  DEPLOY_IDX=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
    jq -r --arg name "${DEPLOYMENT}" '
      (.spec.install.spec.deployments | map(.name) | index($name)) as $i |
      if $i == null then empty else ($i | tostring) end')

  if [ -z "${DEPLOY_IDX}" ]; then
    echo "Warning: ${DEPLOYMENT} not found in CSV ${CSV_NAME}; skipping CSV patch" >&2
    return 0
  fi

  CONTAINER_IDX=$(resolve_csv_container_index)
  if [ -z "${CONTAINER_IDX}" ]; then
    echo "Warning: ${CONTAINER} not found in CSV ${CSV_NAME}/${DEPLOYMENT}; skipping CSV patch" >&2
    return 0
  fi

  CSV_CURRENT=$(oc get csv "${CSV_NAME}" -n "${NAMESPACE}" -o json | \
    jq -c ".spec.install.spec.deployments[${DEPLOY_IDX}].spec.template.spec.containers[${CONTAINER_IDX}].resources // {}")

  if resources_equal "${CSV_CURRENT}"; then
    echo "CSV resources already set"
    return 0
  fi

  echo "Patching CSV ${CSV_NAME} deployment ${DEPLOYMENT} container ${CONTAINER}..."
  oc patch csv "${CSV_NAME}" -n "${NAMESPACE}" --type=json -p \
    "[{\"op\":\"replace\",\"path\":\"/spec/install/spec/deployments/${DEPLOY_IDX}/spec/template/spec/containers/${CONTAINER_IDX}/resources\",\"value\":${RESOURCES_JSON}}]"
}

deployment_resources() {
  local container_idx

  container_idx=$(resolve_container_index)
  oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | \
    jq -c ".spec.template.spec.containers[${container_idx}].resources // {}"
}

patch_deployment_resources() {
  wait_for "${DEPLOYMENT} in ${NAMESPACE}" "oc get deployment \"${DEPLOYMENT}\" -n \"${NAMESPACE}\""

  CONTAINER_IDX=$(resolve_container_index)
  CONTAINER_NAME=$(oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o json | \
    jq -r ".spec.template.spec.containers[${CONTAINER_IDX}].name")

  CURRENT=$(deployment_resources)

  if resources_equal "${CURRENT}"; then
    echo "${DEPLOYMENT}/${CONTAINER_NAME} resources already set"
    return 0
  fi

  echo "Patching ${DEPLOYMENT}/${CONTAINER_NAME} resources (request memory=${MEMORY_REQUEST}, limit memory=${MEMORY_LIMIT})..."
  oc patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --type=json -p \
    "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/${CONTAINER_IDX}/resources\",\"value\":${RESOURCES_JSON}}]"
}

verify_resources_stable() {
  local elapsed=0
  local stable_count=0
  local required_stable=3

  while [ "${elapsed}" -lt "${VERIFY_TIMEOUT}" ]; do
    CURRENT=$(deployment_resources)
    if resources_equal "${CURRENT}"; then
      stable_count=$((stable_count + 1))
      if [ "${stable_count}" -ge "${required_stable}" ]; then
        echo "${DEPLOYMENT} resources stable"
        return 0
      fi
      echo "${DEPLOYMENT} resources match (${stable_count}/${required_stable} stable checks)..."
    else
      stable_count=0
      if is_csv_default_resources "${CURRENT}"; then
        echo "Deployment reverted to CSV defaults; re-patching CSV and deployment..."
        patch_csv_resources
      fi
      echo "Waiting for ${DEPLOYMENT} resources to stabilize (current=${CURRENT})..."
      patch_deployment_resources || true
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  CURRENT=$(deployment_resources)
  echo "Error: ${DEPLOYMENT} resources not stable after ${VERIFY_TIMEOUT}s (current=${CURRENT})" >&2
  exit 1
}

# COO ships perses-operator from its CSV; patch CSV first so reconcile loops stop reverting.
patch_csv_resources
patch_deployment_resources
verify_resources_stable

echo "Perses operator resources patched"
