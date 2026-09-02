#!/bin/bash
set -euo pipefail

NAMESPACE="${POSTGRES_NAMESPACE:?POSTGRES_NAMESPACE required}"
LABEL_KEY="${GATEWAY_ACCESS_LABEL_KEY:-maas.opendatahub.io/gateway-access}"
LABEL_VALUE="${GATEWAY_ACCESS_LABEL_VALUE:-true}"

echo "Waiting for Namespace/${NAMESPACE}..."
until oc get namespace "${NAMESPACE}" >/dev/null 2>&1; do
  sleep 5
done

echo "Labeling ${NAMESPACE} ${LABEL_KEY}=${LABEL_VALUE}"
oc label namespace "${NAMESPACE}" "${LABEL_KEY}=${LABEL_VALUE}" --overwrite
echo "Labeled Namespace/${NAMESPACE}"
