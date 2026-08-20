{{/*
Platform nodeSelector — infra + virtualized workers (not GPU bare metal, not masters).
*/}}
{{- define "platform-addons.platformNodeSelector" -}}
{{- toYaml .Values.scheduling.platform.nodeSelector }}
{{- end }}

{{- define "platform-addons.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "platform-addons.storageClassName" -}}
{{- .Values.storage.files.name }}
{{- end }}
