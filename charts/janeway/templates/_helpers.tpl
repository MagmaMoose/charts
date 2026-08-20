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

{{/*
The generated-asset mounts, kept OUT of janeway.volumeMounts on purpose.

build_assets writes the per-journal override CSS and the journal header images
into static/, then collectstatic copies the lot into collected-static/, which is
what WhiteNoise actually serves. Both are inside the image and so are read-only
under securityContext.readOnlyRootFilesystem; putting them on the volume is what
lets an editor theme a journal at all.

Only the two workloads that run build_assets need them — the web Deployment, so
an operator can run it, and the bootstrap Job, which runs it via install_janeway.
They are separate from janeway.volumeMounts so that the invariant "these
directories are mounted if and only if janeway.seedAssetsInitContainer has
populated them" holds: a pod that mounted them without the init container would
shadow the image's assets with an empty directory.
*/}}
{{- define "janeway.generatedAssetMounts" -}}
{{- if .Values.generatedAssets.enabled }}
- name: files
  mountPath: /opt/janeway/src/static
  subPath: static
- name: files
  mountPath: /opt/janeway/src/collected-static
  subPath: collected-static
{{- end }}
{{- end }}

{{/*
Init container that seeds the generated-asset volumes from the image.

The subPaths are mounted HERE at /seed rather than over their real locations on
purpose: the image's own copy has to stay visible for the copy to have a source.
The main container mounts the same two subPaths over src/static and
src/collected-static.

readOnlyRootFilesystem stays ON — the only thing this writes is the volume.
*/}}
{{- define "janeway.seedAssetsInitContainer" -}}
{{- if .Values.generatedAssets.enabled }}
- name: seed-assets
  image: {{ include "janeway.image" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command:
    - sh
    - -ec
    - |
      # Copy the CONTENTS of an image directory onto its mounted counterpart.
      #
      # Overwriting, not `cp -n`: files/ and transform/xsl hold user data and
      # must never be clobbered, but these hold build output that has to track
      # the image, or an upgrade's new CSS would sit behind the previous
      # release's copy for ever. Anything the image does not ship is untouched
      # by a copy FROM the image, which is exactly the generated overrides.
      #
      # NOT `cp -a "$1/." "$2/"`. That also applies the source directory's
      # timestamps to $2 itself, and $2 is a subPath mount root — created by
      # kubelet, owned by root, group-writable to fsGroup. The container runs as
      # a non-root user that does not own it, so the whole copy dies on:
      #
      #   cp: preserving times for '/seed/static/.': Operation not permitted
      #
      # `-T` so a re-run merges into the existing directory rather than nesting
      # another copy inside it, and `find` rather than a shell glob so a
      # top-level dotfile added upstream is not silently skipped.
      seed() {
        cd "$1" && find . -mindepth 1 -maxdepth 1 -exec cp -aT {} "$2"/{} \;
      }
      seed /opt/janeway/src/static           /seed/static
      seed /opt/janeway/src/collected-static /seed/collected-static
  securityContext:
    {{- toYaml .Values.securityContext | nindent 4 }}
  resources:
    {{- toYaml .Values.generatedAssets.resources | nindent 4 }}
  volumeMounts:
    - name: files
      mountPath: /seed/static
      subPath: static
    - name: files
      mountPath: /seed/collected-static
      subPath: collected-static
{{- end }}
{{- end }}

{{/*
Volume mounts for CronJob pods. Accepts (list $root $job).
Jobs that set mountFiles: false (DB-only tasks) skip the files PVC mounts to
avoid triggering a RWO Multi-Attach error when a CronJob pod lands on a
different node than the web pod.
*/}}
{{- define "janeway.cronJobVolumeMounts" -}}
{{- $root := index . 0 -}}
{{- $job  := index . 1 -}}
{{- if ne $job.mountFiles false }}
- name: files
  mountPath: /opt/janeway/src/files
  subPath: files
- name: files
  mountPath: /opt/janeway/src/media
  subPath: media
- name: files
  mountPath: /opt/janeway/src/transform/xsl
  subPath: xsl
{{- end }}
- name: tmp
  mountPath: /tmp
{{- end }}
