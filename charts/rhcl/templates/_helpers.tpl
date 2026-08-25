{{/*
Expand the name of the chart.
*/}}
{{- define "rhcl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rhcl.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rhcl.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rhcl.labels" -}}
helm.sh/chart: {{ include "rhcl.chart" . }}
{{ include "rhcl.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rhcl.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rhcl.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Kuadrant operator controller resource patch settings with chart defaults.
Cluster values may omit kuadrantOperator entirely or only override nested fields.
*/}}
{{- define "rhcl.kuadrantOperatorResourcesPatch" -}}
{{- $configured := (.Values.kuadrantOperator | default dict).resourcesPatch | default dict }}
{{- $requests := $configured.requests | default dict }}
{{- $limits := $configured.limits | default dict }}
{{- /* Helm `default` treats false as empty, so enabled: false would stay true. */}}
{{- if hasKey $configured "enabled" }}
enabled: {{ $configured.enabled }}
{{- else }}
enabled: true
{{- end }}
requests:
  memory: {{ default "3Gi" $requests.memory }}
  cpu: {{ default "200m" $requests.cpu }}
limits:
  memory: {{ default "5Gi" $limits.memory }}
  cpu: {{ default "500m" $limits.cpu }}
{{- end }}
