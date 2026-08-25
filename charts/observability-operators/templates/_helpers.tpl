{{/*
Expand the name of the chart.
*/}}
{{- define "observability-operators.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "observability-operators.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "observability-operators.labels" -}}
helm.sh/chart: {{ include "observability-operators.chart" . }}
{{ include "observability-operators.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "observability-operators.selectorLabels" -}}
app.kubernetes.io/name: {{ include "observability-operators.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Perses operator resource patch settings with chart defaults.
Cluster values may omit persesOperator entirely or only override nested fields.
*/}}
{{- define "observability-operators.persesOperatorResourcesPatch" -}}
{{- $configured := (.Values.persesOperator | default dict).resourcesPatch | default dict }}
{{- $requests := $configured.requests | default dict }}
{{- $limits := $configured.limits | default dict }}
{{- $installObs := index .Values "install-observability" | default dict }}
{{- $operators := $installObs.operators | default dict }}
{{- $coo := index $operators "cluster-observability-operator" | default dict }}
{{- $csvPatch := (.Values.csvPatch | default dict) }}
enabled: {{ default true $configured.enabled }}
namespace: {{ default (default "openshift-cluster-observability-operator" $coo.namespace) $configured.namespace }}
deployment: {{ default "perses-operator" $configured.deployment }}
container: {{ default "perses-operator" $configured.container }}
csvName: {{ default (default "" $coo.startingCSV) $csvPatch.csvName }}
subscription: {{ default "cluster-observability-operator" $csvPatch.subscription }}
requests:
  memory: {{ default "3Gi" $requests.memory }}
  cpu: {{ default "200m" $requests.cpu }}
limits:
  memory: {{ default "5Gi" $limits.memory }}
  cpu: {{ default "500m" $limits.cpu }}
{{- end }}
