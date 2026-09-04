{{/*
Shared pod definition for every workload kind. deployment.yaml, job.yaml,
cronjob.yaml, master-deployment.yaml and worker-deployment.yaml all render the
same pod through here so they cannot drift apart.

All templates in this file take a dict:
  {"ctx": $, "role": "standalone"|"master"|"worker"}
*/}}

{{/*
Checksum of the rendered ConfigMap, so editing the locustfile rolls the pods.
Renders nothing when the user brings their own ConfigMap — its contents are not
ours to hash, and a missing checksum is better than a wrong one.
Call with the root context.
*/}}
{{- define "locust-load-tester.configChecksum" -}}
{{- if not .Values.locustfile.existingConfigMap -}}
{{- include (print $.Template.BasePath "/configmap.yaml") $ | sha256sum -}}
{{- end -}}
{{- end }}

{{/*
Environment for the Locust container. The image entrypoint (runLocust.sh) builds
the locust command line from these, which is why the chart never sets command/args.
*/}}
{{- define "locust-load-tester.env" -}}
{{- $ctx := .ctx -}}
{{- $role := .role -}}
{{- $v := $ctx.Values -}}
- name: LOCUST_RUN_MODE
  value: {{ $role | quote }}
- name: TARGET_HOST
  value: {{ $v.locust.targetHost | quote }}
- name: LOCUST_CONFIG_DIR
  value: "/config"
- name: LOCUST_FILE
  value: {{ $v.locustfile.name | quote }}
- name: USERS
  value: {{ $v.locust.users | quote }}
- name: SPAWN_RATE
  value: {{ $v.locust.spawnRate | quote }}
- name: RUN_TIME
  value: {{ $v.locust.runTime | quote }}
- name: HEADLESS
  value: {{ $v.locust.headless | quote }}
{{- /* WEB_UI is deliberately not set: it is the legacy alias for HEADLESS and the
       entrypoint warns whenever it is present. */}}
- name: AUTOSTART
  value: {{ $v.locust.autostart | quote }}
- name: ONLY_SUMMARY
  value: {{ $v.locust.onlySummary | quote }}
- name: LOGLEVEL
  value: {{ $v.locust.loglevel | quote }}
- name: EXIT_CODE_ON_ERROR
  value: {{ $v.locust.exitCodeOnError | quote }}
- name: STOP_TIMEOUT
  value: {{ $v.locust.stopTimeout | quote }}
- name: TAGS
  value: {{ join " " $v.locust.tags | quote }}
- name: EXCLUDE_TAGS
  value: {{ join " " $v.locust.excludeTags | quote }}
- name: CSV_PREFIX
  value: {{ if $v.locust.csv.enabled }}{{ $v.locust.csv.prefix | quote }}{{ else }}""{{ end }}
- name: CSV_FULL_HISTORY
  value: {{ and $v.locust.csv.enabled $v.locust.csv.fullHistory | quote }}
- name: HTML_REPORT
  value: {{ $v.locust.htmlReport | quote }}
- name: WEB_PORT
  value: "8089"
- name: WEB_HOST
  value: "0.0.0.0"
{{- if ne $role "standalone" }}
- name: MASTER_PORT
  value: "5557"
{{- end }}
{{- if eq $role "master" }}
- name: EXPECT_WORKERS
  value: {{ default $v.worker.replicaCount $v.locust.expectWorkers | quote }}
{{- end }}
{{- if eq $role "worker" }}
- name: MASTER_HOST
  value: {{ include "locust-load-tester.masterHost" $ctx | quote }}
{{- end }}
- name: WAIT_FOR_HOST
  value: {{ $v.locust.waitForHost.enabled | quote }}
- name: WAIT_FOR_HOST_TIMEOUT
  value: {{ $v.locust.waitForHost.timeout | quote }}
- name: WAIT_FOR_HOST_STATUS
  value: {{ $v.locust.waitForHost.expectStatus | quote }}
- name: LOOP
  value: {{ $v.locust.loop | quote }}
- name: EXTRA_PIP_PACKAGES
  value: {{ join " " $v.locust.extraPipPackages | quote }}
- name: LOCUST_EXTRA_ARGS
  value: {{ join " " $v.locust.extraArgs | quote }}
{{- with $v.extraEnv }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
The complete pod spec, minus the `spec:` key itself.
*/}}
{{- define "locust-load-tester.podSpec" -}}
{{- $ctx := .ctx -}}
{{- $role := .role -}}
{{- $v := $ctx.Values -}}
{{- $isWorker := eq $role "worker" -}}
{{- $batch := has $v.workload.kind (list "Job" "CronJob") -}}
{{- /* The web UI only exists when locust is not headless; workers never serve it. */ -}}
{{- $webUI := and (not $v.locust.headless) (not $isWorker) -}}
{{- $resources := $v.resources -}}
{{- $nodeSelector := $v.nodeSelector -}}
{{- $tolerations := $v.tolerations -}}
{{- $affinity := $v.affinity -}}
{{- $topologySpreadConstraints := $v.topologySpreadConstraints -}}
{{- if $isWorker -}}
{{- with $v.worker.resources }}{{ $resources = . }}{{ end -}}
{{- with $v.worker.nodeSelector }}{{ $nodeSelector = . }}{{ end -}}
{{- with $v.worker.tolerations }}{{ $tolerations = . }}{{ end -}}
{{- with $v.worker.affinity }}{{ $affinity = . }}{{ end -}}
{{- with $v.worker.topologySpreadConstraints }}{{ $topologySpreadConstraints = . }}{{ end -}}
{{- end -}}
serviceAccountName: {{ include "locust-load-tester.serviceAccountName" $ctx }}
automountServiceAccountToken: {{ $v.serviceAccount.automountServiceAccountToken }}
{{- with $v.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if $batch }}
restartPolicy: {{ $v.workload.restartPolicy }}
{{- end }}
{{- if not (kindIs "invalid" $v.terminationGracePeriodSeconds) }}
terminationGracePeriodSeconds: {{ $v.terminationGracePeriodSeconds }}
{{- end }}
{{- with $v.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with $v.hostAliases }}
hostAliases:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.dnsPolicy }}
dnsPolicy: {{ . }}
{{- end }}
{{- with $v.dnsConfig }}
dnsConfig:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.initContainers }}
initContainers:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: locust
    image: {{ include "locust-load-tester.image" $ctx | quote }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    {{- with $v.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    env:
      {{- include "locust-load-tester.env" (dict "ctx" $ctx "role" $role) | nindent 6 }}
    {{- with $v.extraEnvFrom }}
    envFrom:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if not $isWorker }}
    ports:
      - name: web
        containerPort: 8089
        protocol: TCP
      {{- if eq $role "master" }}
      - name: master
        containerPort: 5557
        protocol: TCP
      {{- end }}
    {{- end }}
    {{- if and $webUI $v.livenessProbe.enabled }}
    livenessProbe:
      httpGet:
        path: /
        port: web
      {{- /* Generous delay: EXTRA_PIP_PACKAGES are installed before locust starts. */}}
      initialDelaySeconds: 30
      periodSeconds: 15
      failureThreshold: 3
    {{- end }}
    {{- if and $webUI $v.readinessProbe.enabled }}
    readinessProbe:
      httpGet:
        path: /
        port: web
      initialDelaySeconds: 10
      periodSeconds: 10
      failureThreshold: 3
    {{- end }}
    volumeMounts:
      - name: config
        mountPath: /config
        readOnly: true
      - name: tmp
        mountPath: /tmp
      {{- with $v.extraVolumeMounts }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- with $resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- with $v.sidecars }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
volumes:
  - name: config
    configMap:
      name: {{ include "locust-load-tester.configMapName" $ctx }}
  {{- /* readOnlyRootFilesystem is on by default, so locust needs a writable /tmp
         for CSV/HTML reports and pip --target installs. */}}
  - name: tmp
    {{- if $v.tmpDirSizeLimit }}
    emptyDir:
      sizeLimit: {{ $v.tmpDirSizeLimit }}
    {{- else }}
    emptyDir: {}
    {{- end }}
  {{- with $v.extraVolumes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- with $nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
The pod template (metadata + spec) shared by all five workloads. The
role-specific component label is emitted after the common labels so it overrides
the `load-generator` component set by .labels, and matches the selector the
master/worker Deployments use.
*/}}
{{- define "locust-load-tester.podTemplate" -}}
{{- $ctx := .ctx -}}
{{- $role := .role -}}
{{- $v := $ctx.Values -}}
{{- $checksum := include "locust-load-tester.configChecksum" $ctx -}}
{{- $podAnnotations := merge (deepCopy ($v.podAnnotations | default dict)) ($v.commonAnnotations | default dict) -}}
{{- $podLabels := deepCopy ($v.podLabels | default dict) -}}
{{- if eq $role "worker" -}}
{{- $podAnnotations = merge (deepCopy ($v.worker.podAnnotations | default dict)) $podAnnotations -}}
{{- $podLabels = merge (deepCopy ($v.worker.podLabels | default dict)) $podLabels -}}
{{- end -}}
metadata:
  {{- if or $checksum $podAnnotations }}
  annotations:
    {{- with $checksum }}
    checksum/config: {{ . }}
    {{- end }}
    {{- with $podAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  labels:
    {{- include "locust-load-tester.labels" $ctx | nindent 4 }}
    {{- include "locust-load-tester.componentLabel" $role | nindent 4 }}
    {{- with $podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- include "locust-load-tester.podSpec" (dict "ctx" $ctx "role" $role) | nindent 2 }}
{{- end }}
