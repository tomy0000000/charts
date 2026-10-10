{{- define "clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "clickhouse.fullname" -}}
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

{{- define "clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "clickhouse.labels" -}}
helm.sh/chart: {{ include "clickhouse.chart" . }}
{{ include "clickhouse.selectorLabels" . }}
app.kubernetes.io/version: {{ include "clickhouse.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "clickhouse.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "clickhouse.image" -}}
{{- printf "%s:%s" .Values.image.repository (include "clickhouse.imageTag" .) }}
{{- end }}

{{/*
Whether the server needs S3 credentials: for the schedule, or for a one-time restore.
*/}}
{{- define "clickhouse.s3" -}}
{{- if or .Values.backup.enabled .Values.backup.recoverFrom }}true{{ end }}
{{- end }}

{{/*
The S3 key, in the server's environment. With use_environment_credentials on,
BACKUP and RESTORE statements name only the URL, so the key never reaches a
query log or a client's error output.
*/}}
{{- define "clickhouse.s3Env" -}}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ required "backup.existingSecret is required" .Values.backup.existingSecret | quote }}
      key: {{ .Values.backup.accessKeyIdKey | quote }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.backup.existingSecret | quote }}
      key: {{ .Values.backup.secretAccessKeyKey | quote }}
{{- end }}

{{/*
Environment the backup and restore jobs run clickhouse-client with.
*/}}
{{- define "clickhouse.backupEnv" -}}
- name: CLICKHOUSE_HOST
  value: {{ include "clickhouse.fullname" . }}
- name: BACKUP_URL
  value: {{ required "backup.url is required" .Values.backup.url | quote }}
{{- end }}
