# locust-load-tester

![Type: application](https://img.shields.io/badge/type-application-informational)
![Version: 0.1.0](https://img.shields.io/badge/version-0.1.0-informational)
![AppVersion: 2.46.4](https://img.shields.io/badge/appVersion-2.46.4-informational)
![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)

Run a [Locust](https://locust.io) load test in Kubernetes against any target service,
with the locustfile supplied as chart values or an existing ConfigMap.

The chart renders the test as a **Deployment** (long-running), a **Job** (run once), a
**CronJob** (on a schedule), or a distributed **master + workers** cluster. The image
takes no command or args: the entrypoint builds the `locust` command line from
environment variables, and every `locust.*` value below maps to one of them.

For task-shaped documentation — quick start, recipes, migrating from the old shell
script — see the [repository README](../../README.md).

## Requirements

* Kubernetes 1.21+ (the chart uses `networking.k8s.io/v1` Ingress and `batch/v1` CronJob)
* Helm 3.8+ for the OCI registry; any Helm 3 for the chart repository

## Installing

Two values are required: `locust.targetHost`, and either `locustfile.content` or
`locustfile.existingConfigMap`. The chart fails at render time without them rather than
producing a pod that crash-loops.

From the OCI registry:

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set-file locustfile.content=./locustfile.py
```

From the chart repository:

```bash
helm repo add locust-load-tester https://fragglehunter.github.io/k8s-locust-load-tester
helm repo update

helm install my-test locust-load-tester/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set-file locustfile.content=./locustfile.py
```

Pin the chart version in anything automated:

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --version 0.1.0 \
  -f my-values.yaml
```

## Upgrading

```bash
helm upgrade my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester -f my-values.yaml
```

Changing `locustfile.content` (or `locustfile.extraFiles`) changes the `checksum/config`
pod annotation, so the pods roll automatically. With `locustfile.existingConfigMap` there
is no checksum — the contents are not the chart's to hash — so edit-then-restart is
manual:

```bash
kubectl rollout restart deployment/my-test-locust-load-tester
```

## Uninstalling

```bash
helm uninstall my-test
```

That removes everything the chart created. Jobs left behind by a CronJob are owned by
the CronJob and go with it; set `workload.ttlSecondsAfterFinished` if you want finished
Jobs cleaned up sooner than that.

## Testing

With `service.enabled: true` the chart ships a `helm test` hook — a busybox pod that
`wget --spider`s the web UI through the Service:

```bash
helm test my-test
```

## Validated value combinations

The chart refuses to render, with a message naming the fix, when:

* `mode` is not `standalone` or `distributed`
* `workload.kind` is not `Deployment`, `Job` or `CronJob`
* `locust.targetHost` is empty
* neither `locustfile.content` nor `locustfile.existingConfigMap` is set
* `mode: distributed` is combined with a Job or CronJob
* `locust.autostart` is set while `locust.headless` is still `true`
* `locust.loop` is used with a Job or CronJob, or without a `locust.runTime`
* `ingress.enabled` is set without `service.enabled`

`values.schema.json` additionally enforces types and enums, so a typo like
`--set service.type=Nodeport` fails before anything is sent to the cluster.

## Values

### Topology and image

| Key | Description | Default |
| --- | --- | --- |
| `mode` | Topology. `standalone` runs one self-contained Locust process (what you want for most tests). `distributed` runs a master plus `worker.replicaCount` workers, for when a single pod can no longer saturate the target. | `"standalone"` |
| `image.registry` | Container registry. Set to your Harbor host to pull from there instead. | `"ghcr.io"` |
| `image.repository` | Image repository, without the registry prefix. | `"fragglehunter/k8s-locust-load-tester"` |
| `image.tag` | Image tag. Defaults to `Chart.AppVersion` when empty. | `""` |
| `image.digest` | Pin by digest (`sha256:...`). Takes precedence over `tag` when set. | `""` |
| `image.pullPolicy` | Image pull policy. | `"IfNotPresent"` |
| `imagePullSecrets` | Secrets for pulling from a private registry, e.g. `[{name: harbor-creds}]`. | `[]` |
| `nameOverride` | Override the chart name used in resource names and labels. | `""` |
| `fullnameOverride` | Override the full generated resource name outright. | `""` |
| `commonLabels` | Labels added to every rendered object. | `{}` |
| `commonAnnotations` | Annotations added to every rendered object. | `{}` |

### Locust run configuration

| Key | Description | Default |
| --- | --- | --- |
| `locust.targetHost` | REQUIRED. Target under test, e.g. `http://dotnet-8-app:5000`. | `""` |
| `locust.users` | Peak concurrent simulated users (`--users`). In distributed mode this is the cluster total, split across workers. | `10` |
| `locust.spawnRate` | Users started per second until `users` is reached (`--spawn-rate`). | `5` |
| `locust.runTime` | Stop after this long, e.g. `5m`, `1h30m`. Empty runs until the pod is deleted. | `""` |
| `locust.headless` | Run without the web UI (`--headless`). Set false to drive the test from the browser. | `true` |
| `locust.autostart` | Serve the web UI but start the test immediately (`--autostart`). Requires `headless: false`. | `false` |
| `locust.onlySummary` | Suppress per-interval stats and print only the final summary (`--only-summary`). | `false` |
| `locust.loglevel` | Locust log level: DEBUG, INFO, WARNING, ERROR, CRITICAL. | `"INFO"` |
| `locust.exitCodeOnError` | Exit code when any request failed (`--exit-code-on-error`). `0` makes a Job report success despite failures. | `1` |
| `locust.stopTimeout` | Seconds to wait for tasks to finish on shutdown (`--stop-timeout`). Empty omits the flag. | `""` |
| `locust.tags` | Only run tasks carrying these `@tag` names (`--tags`). | `[]` |
| `locust.excludeTags` | Skip tasks carrying these `@tag` names (`--exclude-tags`). | `[]` |
| `locust.expectWorkers` | In distributed mode, wait for this many workers before starting (`--expect-workers`). Defaults to `worker.replicaCount` when empty. | `""` |
| `locust.csv.enabled` | Write `*_stats.csv` / `*_failures.csv` (`--csv`). | `false` |
| `locust.csv.prefix` | Path prefix for the CSV files. Must be under a writable mount, e.g. `/tmp`. | `"/tmp/locust"` |
| `locust.csv.fullHistory` | Also write a full stats history row per interval (`--csv-full-history`). | `false` |
| `locust.htmlReport` | Write an HTML report to this path on completion (`--html`). Must be writable. | `""` |
| `locust.waitForHost.enabled` | Poll `locust.targetHost` before starting so the test does not report connection errors while the target is still rolling out. | `false` |
| `locust.waitForHost.timeout` | Give up (and start anyway) after this many seconds. | `60` |
| `locust.waitForHost.expectStatus` | Require this exact HTTP status. Empty accepts any HTTP response. | `""` |
| `locust.loop` | Restart the run when Locust exits successfully. Only meaningful with `workload.kind: Deployment` and a non-empty `runTime` — this is the modern equivalent of the old `while true; do locust ...; done` wrapper. | `false` |
| `locust.extraPipPackages` | pip packages installed into /tmp at container start, e.g. `[locust-plugins]`. No image rebuild needed. | `[]` |
| `locust.extraArgs` | Extra flags appended verbatim to the locust command line. | `[]` |

### The locustfile

| Key | Description | Default |
| --- | --- | --- |
| `locustfile.name` | Filename mounted into /config and passed to `locust -f`. | `"locustfile.py"` |
| `locustfile.content` | Inline locustfile contents. Ignored when `existingConfigMap` is set. Usually supplied with `--set-file locustfile.content=./locustfile.py`. | `""` |
| `locustfile.existingConfigMap` | Use a ConfigMap you manage yourself instead of rendering one from `content`. | `""` |
| `locustfile.extraFiles` | Additional files mounted next to the locustfile, e.g. a LoadTestShape or CSV fixture: `{"shape.py": "from locust import LoadTestShape\n..."}`. | `{}` |

### Workload kind

| Key | Description | Default |
| --- | --- | --- |
| `workload.kind` | Deployment (long-running), Job (run once and stop), or CronJob (run on a schedule). | `"Deployment"` |
| `workload.backoffLimit` | Job/CronJob: retries before the run is marked failed. | `0` |
| `workload.ttlSecondsAfterFinished` | Job/CronJob: delete finished Jobs after this many seconds. Empty keeps them. | `""` |
| `workload.restartPolicy` | Job/CronJob: `restartPolicy` for the pod. | `"Never"` |
| `workload.schedule` | CronJob: schedule in cron format. | `"0 * * * *"` |
| `workload.concurrencyPolicy` | CronJob: Allow, Forbid, or Replace. | `"Forbid"` |
| `workload.suspend` | CronJob: pause the schedule without deleting it. | `false` |
| `workload.successfulJobsHistoryLimit` | CronJob: completed Jobs to retain. | `3` |
| `workload.failedJobsHistoryLimit` | CronJob: failed Jobs to retain. | `1` |

### Scale

| Key | Description | Default |
| --- | --- | --- |
| `replicaCount` | Standalone/master replicas. Values above 1 run independent, uncoordinated tests in standalone mode; use `mode: distributed` to coordinate instead. | `1` |
| `worker.replicaCount` | Number of Locust workers. Only used when `mode: distributed`. | `2` |
| `worker.resources` | Per-worker resources. Falls back to the top-level `resources` when empty. | `{}` |
| `worker.nodeSelector` | Per-worker node selector. Falls back to the top-level `nodeSelector` when empty. | `{}` |
| `worker.tolerations` | Per-worker tolerations. Falls back to the top-level `tolerations` when empty. | `[]` |
| `worker.affinity` | Per-worker affinity. Falls back to the top-level `affinity` when empty. | `{}` |
| `worker.topologySpreadConstraints` | Per-worker spread constraints. Falls back to the top-level value when empty. | `[]` |
| `worker.podAnnotations` | Extra annotations on worker pods; merged over the top-level `podAnnotations`. | `{}` |
| `worker.podLabels` | Extra labels on worker pods; merged over the top-level `podLabels`. | `{}` |

### Service, Ingress and ServiceAccount

| Key | Description | Default |
| --- | --- | --- |
| `service.enabled` | Expose the Locust web UI. Leave false for headless runs. | `false` |
| `service.type` | ClusterIP, NodePort or LoadBalancer. | `"ClusterIP"` |
| `service.port` | Port the Service listens on. The container always serves on 8089. | `8089` |
| `service.nodePort` | Only used when `type: NodePort`. | `""` |
| `service.annotations` | Annotations on the Service, merged with `commonAnnotations`. | `{}` |
| `service.labels` | Extra labels on the Service. | `{}` |
| `ingress.enabled` | Create an Ingress for the web UI. Requires `service.enabled: true`. | `false` |
| `ingress.className` | `ingressClassName`. Empty leaves it to the cluster default. | `""` |
| `ingress.annotations` | Annotations on the Ingress, merged with `commonAnnotations`. | `{}` |
| `ingress.hosts` | Hosts and paths routed to the web UI. | `[{"host":"locust.local","paths":[{"path":"/","pathType":"Prefix"}]}]` |
| `ingress.tls` | TLS blocks, passed through verbatim. | `[]` |
| `serviceAccount.create` | Create a ServiceAccount for the pods. | `true` |
| `serviceAccount.automountServiceAccountToken` | Mount the API token into the pod. Off by default: a load generator has no business talking to the API server. | `false` |
| `serviceAccount.annotations` | Annotations on the ServiceAccount, e.g. an IRSA role ARN. | `{}` |
| `serviceAccount.name` | Use an existing ServiceAccount. Generated from the fullname when empty. | `""` |

### Security context

| Key | Description | Default |
| --- | --- | --- |
| `podSecurityContext.runAsNonRoot` | Pod-level security context. Hardened by default; the image runs as uid 1000. | `true` |
| `podSecurityContext.runAsUser` | UID the container runs as; matches the image's `locust` user. | `1000` |
| `podSecurityContext.runAsGroup` | GID the container runs as. | `1000` |
| `podSecurityContext.fsGroup` | Group applied to mounted volumes. | `1000` |
| `podSecurityContext.seccompProfile.type` | Seccomp profile; `RuntimeDefault` satisfies the restricted Pod Security Standard. | `"RuntimeDefault"` |
| `securityContext.allowPrivilegeEscalation` | Container-level security context. | `false` |
| `securityContext.readOnlyRootFilesystem` | Read-only root filesystem. `/tmp` is a writable emptyDir, which is where CSV/HTML reports and `extraPipPackages` go. | `true` |
| `securityContext.privileged` | Never needed by a load generator. | `false` |
| `securityContext.capabilities.drop` | Linux capabilities to drop. | `["ALL"]` |

### Resources and scheduling

| Key | Description | Default |
| --- | --- | --- |
| `resources` | Resource requests/limits. No CPU limit by default: CFS throttling on a load generator shows up as target latency that is really your own client stalling. | see below |
| `resources.requests.cpu` | CPU request. | `"100m"` |
| `resources.requests.memory` | Memory request. | `"128Mi"` |
| `resources.limits.memory` | Memory limit. | `"512Mi"` |
| `tmpDirSizeLimit` | Size of the emptyDir mounted at /tmp (scratch, CSV/HTML reports, pip packages). | `"1Gi"` |
| `livenessProbe.enabled` | HTTP liveness probe against the web UI. Only applied when the UI is being served (`locust.headless: false`) and never on workers. | `false` |
| `readinessProbe.enabled` | HTTP readiness probe against the web UI. Same conditions as the liveness probe. | `false` |
| `podAnnotations` | Extra annotations on every pod. | `{}` |
| `podLabels` | Extra labels on every pod. | `{}` |
| `nodeSelector` | Node selector for the pods. | `{}` |
| `tolerations` | Tolerations for the pods. | `[]` |
| `affinity` | Affinity rules for the pods. | `{}` |
| `topologySpreadConstraints` | Topology spread constraints for the pods. | `[]` |
| `priorityClassName` | PriorityClass for the pods. | `""` |
| `terminationGracePeriodSeconds` | Grace period on pod deletion. An explicit `0` is honoured. | `30` |
| `hostAliases` | Pin DNS or bypass service discovery for the target, e.g. `[{ip: "10.0.0.5", hostnames: ["api.internal"]}]`. | `[]` |
| `dnsPolicy` | Pod `dnsPolicy`. Empty leaves the Kubernetes default. | `""` |
| `dnsConfig` | Pod `dnsConfig`, passed through verbatim. | `{}` |

### Extension points

| Key | Description | Default |
| --- | --- | --- |
| `extraEnv` | Extra environment variables for the Locust container. | `[]` |
| `extraEnvFrom` | Extra `envFrom` sources (ConfigMaps/Secrets) for the Locust container. | `[]` |
| `extraVolumes` | Extra volumes added to the pod. | `[]` |
| `extraVolumeMounts` | Extra volume mounts added to the Locust container. | `[]` |
| `initContainers` | Init containers added to the pod. | `[]` |
| `sidecars` | Sidecar containers added to the pod. | `[]` |

`resources` as a whole defaults to:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 512Mi
```

## Objects rendered

| Object | When |
| --- | --- |
| ConfigMap | unless `locustfile.existingConfigMap` is set |
| ServiceAccount | `serviceAccount.create: true` |
| Deployment | `workload.kind: Deployment` and `mode: standalone` |
| Job | `workload.kind: Job` |
| CronJob | `workload.kind: CronJob` |
| Deployment (master) + Deployment (worker) | `mode: distributed` |
| Service (headless, port 5557) | `mode: distributed` |
| Service | `service.enabled: true` |
| Ingress | `ingress.enabled: true` |
| Test Pod (`helm test`) | `service.enabled: true` |

## Examples

Installable values files live in [`examples/`](../../examples) at the repository root:

| File | What it runs |
| --- | --- |
| `dotnet-app-values.yaml` | headless timed run against a .NET service |
| `emojivoto-values.yaml` | web UI plus Service, against the emojivoto demo app |
| `sock-shop-values.yaml` | run-once Job against the Sock Shop demo, with an HTML report |
| `distributed-values.yaml` | master plus four workers |

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  -f examples/dotnet-app-values.yaml
```

## Licence

Apache-2.0. See [LICENSE](../../LICENSE).
