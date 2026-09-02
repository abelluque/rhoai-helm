{{- define "gateway-api.gatewayConfig.name" -}}
{{- $gc := .Values.disconnected.gatewayConfig | default dict -}}
{{- default "maas-gateway-options" $gc.name -}}
{{- end -}}

{{- define "gateway-api.gatewayConfig.namespace" -}}
{{- $gc := .Values.disconnected.gatewayConfig | default dict -}}
{{- default "openshift-ingress" $gc.namespace -}}
{{- end -}}

{{- define "gateway-api.defaultAllowedRoutes" -}}
namespaces:
  from: Selector
  selector:
    matchLabels:
      maas.opendatahub.io/gateway-access: "true"
{{- end -}}
