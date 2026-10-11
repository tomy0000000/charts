{{- define "plausible.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "plausible.fullname" -}}
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

{{- define "plausible.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "plausible.labels" -}}
helm.sh/chart: {{ include "plausible.chart" . }}
{{ include "plausible.selectorLabels" . }}
app.kubernetes.io/version: {{ include "plausible.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "plausible.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plausible.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "plausible.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "plausible.image" -}}
{{- printf "%s:%s" .Values.image.repository (include "plausible.imageTag" .) }}
{{- end }}

{{/*
Environment shared by the migration init container and the server.
*/}}
{{- define "plausible.env" -}}
env:
  - name: BASE_URL
    value: {{ .Values.baseURL | quote }}
  # Where the release writes its temporary files, an emptyDir as the image has no writable path.
  - name: TMPDIR
    value: /var/lib/plausible/tmp
  {{- range $name, $value := .Values.env }}
  - name: {{ $name }}
    value: {{ $value | quote }}
  {{- end }}
envFrom:
  - secretRef:
      name: {{ required "existingSecret is required" .Values.existingSecret | quote }}
{{- end }}
