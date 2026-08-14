{{/*
Preflight checks.

Every one of these describes a failure that is otherwise slow and confusing to
diagnose in a running cluster — a pod stuck ContainerCreating, a login that
returns to the login page with no error, a site that silently redirects to
example.org. `fail` turns each into an immediate, readable `helm template`
error instead.

Included once from NOTES.txt so they run on template, install and upgrade.
*/}}
{{- define "janeway.guards" -}}

{{- if not .Values.config.siteDomain }}
{{- fail "config.siteDomain is required. It is DEFAULT_HOST, the CSRF trusted origin, and the default Press domain: without it, login POSTs are rejected and unmatched requests redirect to https://www.example.org." }}
{{- end }}

{{- if not .Values.database.host }}
{{- fail "database.host is required. Janeway's settings read DB_HOST with a bare os.environ[] lookup, so an unset value is a KeyError at import rather than a connection error you could diagnose from the logs." }}
{{- end }}

{{- if and (not .Values.database.existingSecret) (not .Values.database.password) }}
{{- fail "Set database.existingSecret (preferred) or database.password. Nothing can start without a database password." }}
{{- end }}

{{- if and (not .Values.secretKey.existingSecret) (not .Values.secretKey.value) }}
{{- fail "Set secretKey.existingSecret (preferred) or secretKey.value. There is deliberately no default: upstream Janeway hardcodes a SECRET_KEY that is published in a public repository, so an install without an override would sign session cookies and password-reset tokens with a publicly known key." }}
{{- end }}

{{/*
ReadWriteOnce is per-NODE, not per-pod, so multiple replicas CAN share one RWO
volume — but only if they are all scheduled onto the same node. Without a
nodeSelector or affinity that is chance, and the failure mode is a second pod
stuck in ContainerCreating with a Multi-Attach error.
*/}}
{{- if and .Values.persistence.enabled (gt (int .Values.replicaCount) 1) }}
{{- if has "ReadWriteOnce" .Values.persistence.accessModes }}
{{- if and (not .Values.nodeSelector) (not .Values.affinity) }}
{{- fail "replicaCount > 1 with a ReadWriteOnce volume and no nodeSelector or affinity. RWO is per-node, so replicas must be pinned to one node or the second pod will fail to attach the volume. Either pin them, or use ReadWriteMany (which needs a storage class that actually supports it)." }}
{{- end }}
{{- end }}
{{- end }}

{{- if and .Values.autoscaling.enabled .Values.persistence.enabled }}
{{- if has "ReadWriteOnce" .Values.persistence.accessModes }}
{{- if and (not .Values.nodeSelector) (not .Values.affinity) }}
{{- fail "autoscaling.enabled with a ReadWriteOnce volume and no node pinning: scaled-up replicas will land on other nodes and fail to attach the volume." }}
{{- end }}
{{- end }}
{{- end }}

{{- if and (gt (int .Values.replicaCount) 1) (eq .Values.strategy.type "RollingUpdate") }}
{{- if has "ReadWriteOnce" .Values.persistence.accessModes }}
{{- if and (not .Values.nodeSelector) (not .Values.affinity) }}
{{- fail "strategy.type=RollingUpdate with a ReadWriteOnce volume and no node pinning: the new pod cannot attach the volume while the old one holds it. Use strategy.type=Recreate." }}
{{- end }}
{{- end }}
{{- end }}

{{- if and .Values.bootstrap.enabled .Values.bootstrap.superuser.email }}
{{- if and (not .Values.bootstrap.superuser.existingSecret) (not .Values.bootstrap.superuser.password) }}
{{- fail "bootstrap.superuser.email is set but no password source is. Set bootstrap.superuser.existingSecret (preferred) or bootstrap.superuser.password, or clear the email to skip superuser creation." }}
{{- end }}
{{- end }}

{{- if .Values.ingress.enabled }}
{{- if not .Values.ingress.hosts }}
{{- fail "ingress.enabled is true but ingress.hosts is empty." }}
{{- end }}
{{- end }}

{{- end }}
