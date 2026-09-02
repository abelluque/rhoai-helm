#!/bin/bash
set -euo pipefail

NAMESPACE="${KUADRANT_NAMESPACE:-kuadrant-system}"
DEPLOY="${AUTHORINO_DEPLOYMENT:-authorino}"
CERT_FILE="${SSL_CERT_FILE_PATH:-/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt}"
CA_VOLUME="${SERVICE_CA_VOLUME:-openshift-service-ca}"
CA_CONFIGMAP="${SERVICE_CA_CONFIGMAP:-openshift-service-ca.crt}"
MOUNT_PATH="$(dirname "${CERT_FILE}")"

echo "Waiting for Deployment/${DEPLOY} in ${NAMESPACE}..."
until oc get deployment "${DEPLOY}" -n "${NAMESPACE}" >/dev/null 2>&1; do
  sleep 5
done

CONTAINER="$(oc get deployment "${DEPLOY}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].name}')"

echo "Setting Authorino TLS trust env on Deployment/${DEPLOY}..."
oc set env "deployment/${DEPLOY}" -n "${NAMESPACE}" \
  "SSL_CERT_FILE=${CERT_FILE}" \
  "REQUESTS_CA_BUNDLE=${CERT_FILE}"

VOLUMES="$(oc get deployment "${DEPLOY}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.volumes[*].name}')"
if echo " ${VOLUMES} " | grep -q " ${CA_VOLUME} "; then
  echo "Volume ${CA_VOLUME} already present"
else
  echo "Mounting ${CA_CONFIGMAP} at ${MOUNT_PATH} on container ${CONTAINER}..."
  oc patch deployment "${DEPLOY}" -n "${NAMESPACE}" --type=strategic -p "{
    \"spec\": {
      \"template\": {
        \"spec\": {
          \"volumes\": [
            {
              \"name\": \"${CA_VOLUME}\",
              \"configMap\": {
                \"name\": \"${CA_CONFIGMAP}\",
                \"items\": [{\"key\": \"service-ca.crt\", \"path\": \"service-ca-bundle.crt\"}]
              }
            }
          ],
          \"containers\": [
            {
              \"name\": \"${CONTAINER}\",
              \"volumeMounts\": [
                {
                  \"name\": \"${CA_VOLUME}\",
                  \"mountPath\": \"${MOUNT_PATH}\",
                  \"readOnly\": true
                }
              ]
            }
          ]
        }
      }
    }
  }"
fi

oc wait --for=condition=Available "deployment/${DEPLOY}" -n "${NAMESPACE}" --timeout=300s
echo "Authorino CA bundle configured"
