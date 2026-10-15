{{/* <name>-<env>, e.g. vote-dev. Fails fast if no values-<env>.yaml was passed. */}}
{{- define "assign2.resourceName" -}}
{{ printf "%s-%s" .name (required "set global.environment (use -f values-<env>.yaml)" .global.environment) }}
{{- end -}}

{{- define "assign2.image" -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}

{{- define "assign2.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: assign2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}
