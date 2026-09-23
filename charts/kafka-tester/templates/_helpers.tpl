{{/*
Name helpers — the standard Helm set.
*/}}
{{- define "kafka-tester.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka-tester.fullname" -}}
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

{{- define "kafka-tester.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kafka-tester.labels" -}}
helm.sh/chart: {{ include "kafka-tester.chart" . }}
{{ include "kafka-tester.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "kafka-tester.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka-tester.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "kafka-tester.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kafka-tester.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference. An empty image.tag falls back to .Chart.AppVersion, and a digest,
when given, pins the image whatever the tag later points at.
*/}}
{{- define "kafka-tester.image" -}}
{{- $ref := printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- if .Values.image.digest }}
{{- $ref = printf "%s@%s" $ref .Values.image.digest }}
{{- end }}
{{- $ref }}
{{- end }}

{{- define "kafka-tester.caMountPath" -}}
/etc/kafka-tester/ca
{{- end }}

{{/*
The app's settings, rendered as the environment it reads. Emits the list items only;
the caller writes the `env:` key.
*/}}
{{- define "kafka-tester.env" -}}
- name: KAFKA_TESTER_TARGETS
  value: {{ .Values.targets | toJson | quote }}
- name: KAFKA_TESTER_ALLOW_CUSTOM
  value: {{ .Values.config.allowCustom | quote }}
- name: KAFKA_TESTER_DEFAULT_TOPIC
  value: {{ .Values.config.defaultTopic | quote }}
- name: KAFKA_TESTER_TIMEOUT_MS
  {{- /* int first: a YAML number reaches the template as a float, and a large one would print in exponent form. */}}
  value: {{ int .Values.config.timeoutMs | quote }}
- name: KAFKA_TESTER_CREATE_TOPICS
  value: {{ .Values.config.createTopics | quote }}
- name: KAFKA_TESTER_IP_ECHO_URL
  value: {{ .Values.config.ipEchoUrl | quote }}
{{- if or .Values.caBundle.secretName .Values.caBundle.configMapName }}
- name: KAFKA_TESTER_SSL_CAFILE
  value: {{ include "kafka-tester.caMountPath" . }}/ca.crt
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
