{{/*
Chart name, overridable with nameOverride.
*/}}
{{- define "locust-load-tester.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, capped at 63 chars for label/DNS limits.
*/}}
{{- define "locust-load-tester.fullname" -}}
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

{{- define "locust-load-tester.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels. Must stay immutable across upgrades — never add anything
version-dependent here.
*/}}
{{- define "locust-load-tester.selectorLabels" -}}
app.kubernetes.io/name: {{ include "locust-load-tester.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "locust-load-tester.labels" -}}
helm.sh/chart: {{ include "locust-load-tester.chart" . }}
{{ include "locust-load-tester.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: locust
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Component label for a role. Deliberately NOT part of .labels: the master and
worker Deployments need their own value, and emitting it twice yields a duplicate
YAML key that the API server rejects.
Call with a role string: standalone | master | worker.
*/}}
{{- define "locust-load-tester.componentLabel" -}}
{{- if eq . "standalone" -}}
app.kubernetes.io/component: load-generator
{{- else -}}
app.kubernetes.io/component: {{ . }}
{{- end -}}
{{- end }}

{{/*
Annotations applied to every object. Emits nothing when unset so callers can
guard with `with`.
*/}}
{{- define "locust-load-tester.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{- define "locust-load-tester.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "locust-load-tester.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Fully qualified image reference. A digest wins over a tag; tag falls back to
the chart appVersion. An empty registry yields an unprefixed (Docker Hub) ref.
*/}}
{{- define "locust-load-tester.image" -}}
{{- $registry := .Values.image.registry | default "" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $ref := $repository -}}
{{- if $registry -}}
{{- $ref = printf "%s/%s" $registry $repository -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $ref .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end }}

{{/*
ConfigMap holding the locustfile: either one the user manages or the one this
chart renders.
*/}}
{{- define "locust-load-tester.configMapName" -}}
{{- if .Values.locustfile.existingConfigMap -}}
{{- .Values.locustfile.existingConfigMap -}}
{{- else -}}
{{- include "locust-load-tester.fullname" . -}}
{{- end -}}
{{- end }}

{{- define "locust-load-tester.masterFullname" -}}
{{- printf "%s-master" (include "locust-load-tester.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "locust-load-tester.workerFullname" -}}
{{- printf "%s-worker" (include "locust-load-tester.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Headless Service workers use to find the master. Always created in distributed mode.
*/}}
{{- define "locust-load-tester.headlessServiceName" -}}
{{- printf "%s-headless" (include "locust-load-tester.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Master hostname workers dial: <headless-svc>.<namespace>.svc.cluster.local
*/}}
{{- define "locust-load-tester.masterHost" -}}
{{- printf "%s.%s.svc.cluster.local" (include "locust-load-tester.headlessServiceName" .) .Release.Namespace -}}
{{- end }}

{{/*
Fail fast on value combinations that would otherwise produce a pod that starts
and then does nothing useful.
*/}}
{{- define "locust-load-tester.validateValues" -}}
{{- if not (has .Values.mode (list "standalone" "distributed")) -}}
{{- fail (printf "mode must be \"standalone\" or \"distributed\", got %q" .Values.mode) -}}
{{- end -}}
{{- if not (has .Values.workload.kind (list "Deployment" "Job" "CronJob")) -}}
{{- fail (printf "workload.kind must be Deployment, Job, or CronJob, got %q" .Values.workload.kind) -}}
{{- end -}}
{{- if not .Values.locust.targetHost -}}
{{- fail "locust.targetHost is required, e.g. --set locust.targetHost=http://my-service:8080" -}}
{{- end -}}
{{- if and (not .Values.locustfile.existingConfigMap) (not .Values.locustfile.content) -}}
{{- fail "set locustfile.content (e.g. --set-file locustfile.content=./locustfile.py) or locustfile.existingConfigMap" -}}
{{- end -}}
{{- if and (eq .Values.mode "distributed") (ne .Values.workload.kind "Deployment") -}}
{{- fail "mode: distributed requires workload.kind: Deployment" -}}
{{- end -}}
{{- if and .Values.locust.autostart .Values.locust.headless -}}
{{- fail "locust.autostart requires locust.headless: false (autostart serves the web UI and starts the run itself)" -}}
{{- end -}}
{{- if and .Values.locust.loop (ne .Values.workload.kind "Deployment") -}}
{{- fail "locust.loop only applies to workload.kind: Deployment; use a CronJob to repeat Job runs" -}}
{{- end -}}
{{- if and .Values.locust.loop (not .Values.locust.runTime) -}}
{{- fail "locust.loop requires locust.runTime to be set, otherwise the first run never ends" -}}
{{- end -}}
{{- end }}
