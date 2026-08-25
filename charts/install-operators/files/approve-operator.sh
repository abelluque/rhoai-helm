#!/bin/bash

{{- $operator := index . 0 }}
{{- $config := index . 1 }}
{{- $approveCSVs := $config.approveCSVs | default list }}
{{- $manualInstall := eq ($config.installPlanApproval | default "Automatic") "Manual" }}
{{- if $manualInstall }}
{{- $approveCSVs = append $approveCSVs $config.startingCSV }}
{{- end }}
{{- $namespace := $config.namespace | default "openshift-operators" }}

NAMESPACE="{{ $namespace }}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240}"

function approve_install_plan {
  set -x
  oc patch installplan "$1" -n "${NAMESPACE}" --patch '{"spec": {"approved": true}}' --type merge
  { set +x ; } 2>/dev/null
}

function find_install_plans {
  oc get installplan -n "${NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.clusterServiceVersionNames}{"\n"}{end}' 2>/dev/null \
    | while IFS=$'\t' read -r name csvs; do
        [ -z "${name}" ] && continue
        for csv in {{ join " " $approveCSVs }}; do
          case " ${csvs} " in
            *"${csv}"*) echo "${name}" ;;
          esac
        done
      done
}

echo "Waiting up to ${WAIT_TIMEOUT}s for InstallPlan ({{ join " " $approveCSVs }}) in ${NAMESPACE}"
elapsed=0
while true; do
  install_plans=( $(find_install_plans) )
  if [ "${#install_plans[@]}" -gt 0 ]; then
    echo
    for install_plan in "${install_plans[@]}"; do
      if [ -z "$install_plan" ]; then
        continue
      fi
      approved=$(oc get installplan "$install_plan" -n "${NAMESPACE}" -o jsonpath='{.spec.approved}')
      if [ "$approved" != "true" ]; then
        approve_install_plan "$install_plan"
      else
        echo "InstallPlan ${install_plan} already approved"
      fi
    done
    exit 0
  fi
  if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
    echo "Timed out after ${WAIT_TIMEOUT}s waiting for InstallPlan for: {{ join " " $approveCSVs }}" >&2
    echo "Pinned startingCSV is often missing from this cluster's catalog." >&2
    oc get subscription,installplan,csv -n "${NAMESPACE}" >&2 || true
    exit 1
  fi
  echo -n '.'
  sleep 5
  elapsed=$((elapsed + 5))
done
