{{/*
Expand the name of the chart.
*/}}
{{- define "install-operators.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "install-operators.fullname" -}}
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
{{- define "install-operators.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "install-operators.labels" -}}
helm.sh/chart: {{ include "install-operators.chart" . }}
{{ include "install-operators.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "install-operators.selectorLabels" -}}
app.kubernetes.io/name: {{ include "install-operators.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
True if $ns already has an OperatorGroup. lookup with an empty name can return
cluster-wide items without .metadata.namespace; only count groups whose
namespace field equals $ns. Do not use `default $ns` — an empty namespace
would look like a match and Helm would drop the OG from the release.
*/}}
{{- define "install-operators.namespaceHasOperatorGroup" -}}
{{- $ns := . -}}
{{- $found := false -}}
{{- $list := lookup "operators.coreos.com/v1" "OperatorGroup" $ns "" -}}
{{- if $list -}}
{{- if $list.items -}}
{{- range $list.items -}}
{{- if and .metadata.namespace (eq .metadata.namespace $ns) -}}
{{- $found = true -}}
{{- end -}}
{{- end -}}
{{- else if and $list.metadata $list.metadata.name $list.metadata.namespace -}}
{{- if eq $list.metadata.namespace $ns -}}
{{- $found = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $found -}}
{{- end }}

{{/*
Subscription manifest
*/}}
{{- define "install-operators.subscription" -}}
{{- $operator := .operator }}
{{- $config := .config }}
{{- $root := .root }}
{{- $installPlanApproval := $config.installPlanApproval | default "Automatic" }}
{{- if and (eq $installPlanApproval "Manual") (not $config.startingCSV) }}
{{- fail (printf "Operator %s requires startingCSV when installPlanApproval is Manual" $operator) }}
{{- end }}
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: {{ $operator }}
  namespace: {{ $config.namespace | default "openshift-operators" }}
  labels:
    {{- include "install-operators.labels" $root | nindent 4 }}
  {{- with $config.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  channel: {{ $config.channel }}
  installPlanApproval: {{ $installPlanApproval }}
  name: {{ $operator }}
  source: {{ $config.catalog | default "redhat-operators" }}
  sourceNamespace: openshift-marketplace
  {{- with $config.startingCSV }}
  startingCSV: {{ . }}
  {{- end }}
{{- end }}
