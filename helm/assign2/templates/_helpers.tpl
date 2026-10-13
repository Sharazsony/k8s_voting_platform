{{- define "assign2.environment" -}}
{{ required "set global.environment (use -f values-<env>.yaml)" .Values.global.environment }}
{{- end -}}

{{- define "assign2.image" -}}
{{- $registry := .global.imageRegistry | default "" -}}
{{- if $registry }}{{ $registry }}/{{ end }}{{ .image.repository }}:{{ .image.tag }}
{{- end -}}

{{- define "assign2.hosts" -}}
{{- $domain := required "set global.domain (use -f values-<env>.yaml)" .Values.global.domain -}}
- {{ printf "vote.%s" $domain }}
- {{ printf "result.%s" $domain }}
{{- if .Values.global.adminerEnabled }}
- {{ printf "adminer.%s" $domain }}
{{- end }}
{{- end -}}

{{- define "assign2.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: assign2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "assign2.scopedName" -}}
{{- $name := .name -}}
{{- if and .global.sharedCluster .Values.global.environment -}}
{{ printf "%s-%s" $name .Values.global.environment }}
{{- else -}}
{{ $name }}
{{- end -}}
{{- end -}}
