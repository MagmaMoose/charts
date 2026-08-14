{{/*
Name helpers — the standard Helm set.
*/}}
{{- define "janeway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "janeway.fullname" -}}
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

{{- define "janeway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "janeway.labels" -}}
helm.sh/chart: {{ include "janeway.chart" . }}
{{ include "janeway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: janeway
{{- end }}

{{- define "janeway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "janeway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "janeway.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "janeway.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference. An empty image.tag falls back to .Chart.AppVersion so that the
chart and the application it deploys move together by default.
*/}}
{{- define "janeway.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{- define "janeway.pvcName" -}}
{{- default (printf "%s-files" (include "janeway.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}

{{- define "janeway.pressDomain" -}}
{{- default .Values.config.siteDomain .Values.bootstrap.pressDomain }}
{{- end }}

{{/*
Environment shared by every workload: the web Deployment, the migration hook,
the bootstrap hook and every CronJob. They all run the same image against the
same database, so drift between them is a class of bug worth designing out.

Secrets are referenced with secretKeyRef rather than interpolated, so no
credential is ever written into the release manifest.
*/}}
Emits the LIST ITEMS only — the caller writes the `env:` key. That is what lets
the bootstrap Job append its own entries to the same list instead of producing a
second `env:` key, which would be a duplicate YAML mapping key and silently
drop one of the two.
*/}}
{{- define "janeway.env" -}}
- name: JANEWAY_SETTINGS_MODULE
  value: core.production_settings
- name: DB_VENDOR
  value: postgres
- name: DB_HOST
  value: {{ .Values.database.host | quote }}
- name: DB_PORT
  value: {{ .Values.database.port | quote }}
- name: DB_NAME
  value: {{ .Values.database.name | quote }}
- name: DB_USER
  value: {{ .Values.database.user | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default (printf "%s-db" (include "janeway.fullname" .)) .Values.database.existingSecret }}
      key: {{ .Values.database.existingSecretKey }}
- name: JANEWAY_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ default (printf "%s-secret-key" (include "janeway.fullname" .)) .Values.secretKey.existingSecret }}
      key: {{ .Values.secretKey.existingSecretKey }}
{{- if .Values.email.existingSecret }}
- name: JANEWAY_EMAIL_HOST_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.email.existingSecret }}
      key: {{ .Values.email.existingSecretKey }}
{{- end }}
{{- end }}

{{/*
Non-secret configuration, shared by every workload.
*/}}
{{- define "janeway.envFrom" -}}
- configMapRef:
    name: {{ include "janeway.fullname" . }}
{{- end }}

{{/*
Volumes and mounts.

The files PVC is mounted twice by subPath rather than as two claims: Janeway
writes uploads under BASE_DIR/files and BASE_DIR/media, and one volume for both
keeps a single thing to size, snapshot and restore.

/tmp is an emptyDir because Django spills file uploads larger than
FILE_UPLOAD_MAX_MEMORY_SIZE to the system temp directory, which would otherwise
be the read-only root filesystem.
*/}}
{{- define "janeway.volumes" -}}
- name: files
  {{- if .Values.persistence.enabled }}
  persistentVolumeClaim:
    claimName: {{ include "janeway.pvcName" . }}
  {{- else }}
  emptyDir: {}
  {{- end }}
- name: tmp
  emptyDir: {}
{{- end }}

{{- define "janeway.volumeMounts" -}}
- name: files
  mountPath: /opt/janeway/src/files
  subPath: files
- name: files
  mountPath: /opt/janeway/src/media
  subPath: media
# transform/xsl ships four stylesheets and is ALSO the upload target for
# Janeway's XSLFile model, so it holds user data. Without a volume here an
# uploaded XSL is written into the pod's own filesystem and lost on restart —
# and `migrate` writes one itself, so the migration Job would fail outright
# against a read-only root filesystem. The entrypoint restores the shipped
# stylesheets onto an empty volume.
- name: files
  mountPath: /opt/janeway/src/transform/xsl
  subPath: xsl
- name: tmp
  mountPath: /tmp
{{- end }}
