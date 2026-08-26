{{- define "gateway-api.gatewayConfig.enabled" -}}
{{- $gc := .Values.disconnected.gatewayConfig | default dict -}}
{{- if or $gc.serviceType $gc.servingCertSecretName (and .Values.disconnected.enabled $gc.wasmInsecureRegistries) -}}
true
{{- end -}}
{{- end -}}
