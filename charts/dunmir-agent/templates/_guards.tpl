{{/*
Preflight checks. Included from NOTES.txt so they fire on helm template, install, and upgrade.
*/}}
{{- define "dunmir.guards" -}}

{{- if and (not .Values.secrets.create) (not .Values.secrets.existingSecretName) }}
{{- fail "Set secrets.existingSecretName when secrets.create=false, otherwise the pod's envFrom references a Secret that is never created and the pod will fail with CreateContainerConfigError." }}
{{- end }}

{{- end }}
