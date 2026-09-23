{{/*
Preflight checks, for values that would otherwise start a pod that crash-loops or
has nothing it is allowed to test. `fail` turns each into a readable `helm
template` error instead.

Included once from NOTES.txt so they run on template, install and upgrade.
*/}}
{{- define "kafka-tester.guards" -}}

{{- if and (not .Values.config.allowCustom) (not .Values.targets) }}
{{- fail "config.allowCustom is false and targets is empty, so the UI would offer nothing it is allowed to test. Add a target, or allow custom endpoints." }}
{{- end }}

{{- $seen := dict }}
{{- range .Values.targets }}
{{- if hasKey $seen .name }}
{{- fail (printf "targets: the name %q is used more than once. The app refuses duplicate names at startup, so the pod would crash-loop." .name) }}
{{- end }}
{{- $_ := set $seen .name true }}
{{- end }}

{{- if and .Values.caBundle.secretName .Values.caBundle.configMapName }}
{{- fail "caBundle: set secretName or configMapName, not both." }}
{{- end }}

{{- end }}
