{{/*
Expand the name of the chart.
*/}}
{{- define "email-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "email-mcp.fullname" -}}
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

{{- define "email-mcp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "email-mcp.labels" -}}
helm.sh/chart: {{ include "email-mcp.chart" . }}
{{ include "email-mcp.selectorLabels" . }}
app.kubernetes.io/version: {{ include "email-mcp.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "email-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "email-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "email-mcp.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "email-mcp.image" -}}
{{- printf "%s:%s" .Values.image.repository (include "email-mcp.imageTag" .) }}
{{- end }}

{{/*
Name of the Secret holding the shared token, and the key inside it.
*/}}
{{- define "email-mcp.secretName" -}}
{{- .Values.auth.existingSecret | default (include "email-mcp.fullname" .) }}
{{- end }}

{{- define "email-mcp.secretKey" -}}
{{- if .Values.auth.existingSecret }}{{ .Values.auth.existingSecretKey }}{{ else }}token{{ end }}
{{- end }}

{{- define "email-mcp.tlsSecretName" -}}
{{- .Values.ingress.tls.secretName | default (printf "%s-tls" (include "email-mcp.fullname" .)) }}
{{- end }}

{{/*
Server environment. The mailbox is composed from MCP_EMAIL_SERVER_* variables,
the mechanism upstream documents for containers, so nothing is written to a
catalog and the password exists only in the Secret and this process.
*/}}
{{- define "email-mcp.serverEnv" -}}
- name: HOME
  value: /data/config
- name: MCP_EMAIL_SERVER_CONFIG_PATH
  value: /data/config/config.toml
- name: MCP_EMAIL_SERVER_EMAIL_ADDRESS
  valueFrom:
    secretKeyRef:
      name: {{ required "account.existingSecret is required" .Values.account.existingSecret | quote }}
      key: {{ .Values.account.usernameKey | quote }}
- name: MCP_EMAIL_SERVER_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.account.existingSecret | quote }}
      key: {{ .Values.account.passwordKey | quote }}
- name: MCP_EMAIL_SERVER_IMAP_HOST
  value: {{ .Values.account.imap.host | quote }}
- name: MCP_EMAIL_SERVER_IMAP_PORT
  value: {{ .Values.account.imap.port | quote }}
- name: MCP_EMAIL_SERVER_IMAP_SSL
  value: {{ not .Values.account.imap.starttls | quote }}
- name: MCP_EMAIL_SERVER_IMAP_START_SSL
  value: {{ .Values.account.imap.starttls | quote }}
# Empty denies sending, forwarding and draft saves. Pinned, not left to the default.
- name: MCP_EMAIL_SERVER_ALLOWED_RECIPIENTS
  value: ""
- name: MCP_HOST
  value: "127.0.0.1"
- name: MCP_PORT
  value: {{ .Values.server.port | quote }}
- name: MCP_ALLOWED_HOSTS
  value: {{ .Values.host | quote }}
- name: MCP_ALLOWED_ORIGINS
  value: {{ prepend .Values.extraAllowedOrigins (printf "https://%s" .Values.host) | join "," | quote }}
{{- with .Values.server.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
