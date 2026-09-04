# k8s-locust-load-tester

[![CI](https://github.com/fragglehunter/k8s-locust-load-tester/actions/workflows/ci.yaml/badge.svg)](https://github.com/fragglehunter/k8s-locust-load-tester/actions/workflows/ci.yaml)
[![Image](https://img.shields.io/badge/ghcr.io-k8s--locust--load--tester-2496ed?logo=docker&logoColor=white)](https://github.com/fragglehunter/k8s-locust-load-tester/pkgs/container/k8s-locust-load-tester)
[![Chart](https://img.shields.io/badge/helm-oci%20chart-0f1689?logo=helm&logoColor=white)](https://github.com/fragglehunter/k8s-locust-load-tester/pkgs/container/charts%2Flocust-load-tester)
[![Locust](https://img.shields.io/badge/locust-2.46.4-31a05d?logo=python&logoColor=white)](https://docs.locust.io/)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Load and integration tests that simulate real end-user traffic against an application
running in Kubernetes. Use them to validate that everything still works end to end, or
to put sustained, measurable load on the system. The tests are written with
[locust.io](https://locust.io).

The container is deliberately **generic**: no test is baked into the image. You hand it
a locustfile and a target, and it builds the `locust` command line for you. That is what
makes one image useful for every service you own instead of one image per test.

Two artifacts are published from this repo — the chart in two places, because both
distribution styles are free and people expect different ones:

| Artifact | Where |
| --- | --- |
| Container image | `ghcr.io/fragglehunter/k8s-locust-load-tester` |
| Helm chart (OCI) | `oci://ghcr.io/fragglehunter/charts/locust-load-tester` |
| Helm chart (repo) | `https://fragglehunter.github.io/k8s-locust-load-tester` |

The chart runs the test as a Deployment, a Job, a CronJob, or a distributed
master/worker cluster, and every knob is a value — see
[`charts/locust-load-tester/README.md`](charts/locust-load-tester/README.md) for the
full reference.

---

## Quick start

Two required values: where to send the traffic, and the locustfile to send it with.

### From the OCI registry (Helm 3.8+)

```bash
helm install dotnet-loadtest oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://dotnet-8-app:5000 \
  --set-file locustfile.content=./locustfile-dotnet-app.py
```

No `helm repo add` needed — OCI charts are pulled straight from GHCR.

### From the chart repository (gh-pages)

```bash
helm repo add locust-load-tester https://fragglehunter.github.io/k8s-locust-load-tester
helm repo update

helm install dotnet-loadtest locust-load-tester/locust-load-tester \
  --set locust.targetHost=http://dotnet-8-app:5000 \
  --set-file locustfile.content=./locustfile-dotnet-app.py
```

### Watch it run

```bash
kubectl logs -f -l app.kubernetes.io/instance=dotnet-loadtest --tail=100
```

### Tear it down

```bash
helm uninstall dotnet-loadtest
```

`--set-file locustfile.content=./your-test.py` is the ergonomic win over the old
`kubectl create configmap --from-file=...` dance: the file goes in as a chart value, so
the ConfigMap, the mount, the env vars and a `checksum/config` pod annotation are all
derived from it. Edit the file, `helm upgrade`, and the pods roll on their own.

There are ready-made values files in [`examples/`](examples/) for the locustfiles that
ship with this repo:

```bash
helm install dotnet-loadtest oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  -f examples/dotnet-app-values.yaml
```

---

## Supplying the locustfile

Three ways in, pick one.

### 1. Inline from a file on disk — `--set-file` (recommended)

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set-file locustfile.content=./locustfile.py
```

Helm reads the file verbatim, so Python indentation survives. Extra files land next to it
in `/config`, which is handy for a `LoadTestShape`, a data fixture or a shared module:

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set-file locustfile.content=./locustfile.py \
  --set-file 'locustfile.extraFiles.shape\.py=./shape.py'
```

The `\.` is not a typo — Helm splits `--set` keys on `.`, so the dot in a filename has
to be escaped. A values file (below) avoids the whole problem.

### 2. In a values file

Better once the test outgrows a one-liner, because the values file is reviewable and
version controlled:

```yaml
locust:
  targetHost: http://my-service:8080

locustfile:
  name: locustfile.py
  content: |-
    from locust import HttpUser, between, task


    class Web(HttpUser):
        wait_time = between(0.5, 1)

        @task
        def index(self):
            self.client.get("/")

  extraFiles:
    paths.txt: |-
      /
      /health
```

```bash
helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester -f my-values.yaml
```

### 3. A ConfigMap you already manage

If the locustfile is produced by something else — a GitOps pipeline, another chart, a
`kubectl create configmap` you are not ready to retire — point the chart at it:

```bash
kubectl create configmap my-locustfile --from-file=locustfile.py=./locustfile.py

helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set locustfile.existingConfigMap=my-locustfile
```

The whole ConfigMap is mounted at `/config`, and `locustfile.name` (default
`locustfile.py`) selects the key to run. The chart renders no ConfigMap of its own in
this mode, and no `checksum/config` annotation either — the contents are not the
chart's to hash, so **editing the ConfigMap will not restart the pods**. Roll them
yourself with `kubectl rollout restart`.

Installing with neither `locustfile.content` nor `locustfile.existingConfigMap` fails at
render time rather than producing a pod that crash-loops on a missing file.

---

## Common recipes

### Headless timed run

The default shape: no web UI, run for a fixed time, print the summary, stop.

```bash
helm install soak oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set locust.users=200 \
  --set locust.spawnRate=20 \
  --set locust.runTime=15m \
  --set locust.onlySummary=true \
  --set-file locustfile.content=./locustfile.py
```

A Deployment has no notion of "done": when `runTime` elapses Locust exits, the container
exits with it, and the kubelet restarts it — so the run repeats, with a backoff between
attempts. That is right for a soak you intend to leave running and wrong for a one-shot;
use the Job recipe below when you want the run to stop. Leave `locust.runTime` empty to
run until you uninstall.

If you *do* want it to repeat, `locust.loop=true` is the better way: the entrypoint
restarts Locust itself after each clean finish, so the container stays up and the restart
counter does not climb. It requires a `runTime` and a Deployment, and it is the modern
replacement for the `while true; do locust ...; done` wrapper the old manifests used.

### Web UI plus port-forward

Drive the test from the browser instead of the command line.

```bash
helm install ui oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set locust.targetHost=http://my-service:8080 \
  --set locust.headless=false \
  --set service.enabled=true \
  --set-file locustfile.content=./locustfile.py

kubectl port-forward svc/ui-locust-load-tester 8089:8089
# then open http://127.0.0.1:8089
```

`service.enabled=true` without `locust.headless=false` gives you a Service in front of a
process that is not listening — the chart prints a warning for exactly that combination.

Add `--set locust.autostart=true` to serve the UI *and* start the run immediately, which
is the right choice for a dashboard you want populated when you open it. Use
`ingress.enabled=true` (which requires `service.enabled=true`) to expose it properly
instead of port-forwarding.

### Run once as a Job

```bash
helm install release-gate oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set workload.kind=Job \
  --set locust.targetHost=http://my-service:8080 \
  --set locust.runTime=2m \
  --set locust.waitForHost.enabled=true \
  --set workload.ttlSecondsAfterFinished=3600 \
  --set-file locustfile.content=./locustfile.py \
  --wait
```

`--wait` blocks until the Job completes, so this works as a pipeline step: Locust exits
non-zero when the run recorded failures, and the Job — with `backoffLimit: 0` and
`restartPolicy: Never` by default — fails with it. `locust.waitForHost.enabled=true`
polls the target first so a deployment that is still rolling out does not show up as a
wall of connection errors.

If you want the run graded on "did it run" rather than "was the target healthy", pass
`--set 'locust.extraArgs={--exit-code-on-error,0}'`.

By default Locust exits `1` if **any** request failed, so a single 404 sends the Job to
`Failed` (and, with `workload.kind: Deployment`, sends the pod to `CrashLoopBackOff`).
That is what you want for a smoke test gating a pipeline. For a soak test against a
target you already know errors under load, turn it off:

```bash
  --set locust.exitCodeOnError=0
```

### On a schedule as a CronJob

```bash
helm install nightly oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set workload.kind=CronJob \
  --set workload.schedule='0 2 * * *' \
  --set locust.targetHost=http://my-service:8080 \
  --set locust.runTime=10m \
  --set-file locustfile.content=./locustfile.py
```

`workload.concurrencyPolicy` defaults to `Forbid`, so a run that overruns its window
does not get a second copy piled on top of it. Pause without uninstalling using
`--set workload.suspend=true`.

### Distributed master and workers

When one pod can no longer saturate the target, spread it out. One master coordinates,
`worker.replicaCount` workers generate the traffic, and a headless Service on port 5557
is how the workers find the master.

```bash
helm install big oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set mode=distributed \
  --set worker.replicaCount=6 \
  --set locust.targetHost=http://my-service:8080 \
  --set locust.users=5000 \
  --set locust.spawnRate=200 \
  --set locust.runTime=20m \
  --set-file locustfile.content=./locustfile.py
```

Notes that matter:

* `locust.users` and `locust.spawnRate` are **cluster totals**, split across the workers
  by the master. They are not per-worker numbers.
* The master waits for `locust.expectWorkers` workers before starting; left empty it
  defaults to `worker.replicaCount`, which is what you want almost always.
* Workers can be scaled while a test is running — they attach to the live master:
  `kubectl scale deployment/big-locust-load-tester-worker --replicas=10`.
* `mode: distributed` requires `workload.kind: Deployment`. A Job or CronJob has no
  master to coordinate.
* Give the workers their own resources with `worker.resources`; they fall back to the
  top-level `resources` when unset.

See [`examples/distributed-values.yaml`](examples/distributed-values.yaml) for the
values-file version.

---

## Recipe: the Faces demo app

[Faces](https://github.com/BuoyantIO/faces-demo) installs into the `faces` namespace,
so the load test goes there too and can use short service names.

Point it at the **`face`** service, not `faces-gui`. `face` is the edge service the
browser actually hammers, and it fans out to `smiley` and `color` behind it, so this
exercises the whole chain instead of just serving static HTML. The GUI renders a grid
whose small centre block requests `/center/` and whose every other cell requests
`/edge/`, which is why [`locustfile-faces.py`](locustfile-faces.py) weights them 8:1.

Smallest thing that works — a 5 minute headless run:

```bash
helm install faces-loadtest oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --namespace faces \
  --set locust.targetHost=http://face \
  --set locust.users=40 \
  --set locust.spawnRate=10 \
  --set locust.runTime=5m \
  --set-file locustfile.content=./locustfile-faces.py
```

Same thing from the bundled values file, which also turns on CSV output:

```bash
helm install faces-loadtest oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --namespace faces \
  -f examples/faces-values.yaml
```

Watch it:

```bash
kubectl logs -n faces -f -l app.kubernetes.io/instance=faces-loadtest --tail=100
```

With the web UI instead, so you can drive the ramp by hand:

```bash
helm install faces-ui oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --namespace faces \
  --set locust.targetHost=http://face \
  --set locust.headless=false \
  --set service.enabled=true \
  --set-file locustfile.content=./locustfile-faces.py

kubectl port-forward -n faces svc/faces-ui-locust-load-tester 8089:8089
# then open http://127.0.0.1:8089
```

Enough load to actually make Faces go red, distributed across 4 workers:

```bash
helm install faces-big oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --namespace faces \
  --set mode=distributed \
  --set worker.replicaCount=4 \
  --set locust.targetHost=http://face \
  --set locust.users=800 \
  --set locust.spawnRate=50 \
  --set locust.runTime=15m \
  --set-file locustfile.content=./locustfile-faces.py
```

Clean up:

```bash
helm uninstall faces-loadtest faces-ui faces-big -n faces
```

Faces injects errors and latency on purpose (its `ERROR_FRACTION` and `DELAY_BUCKETS`
settings), so a steady non-zero failure rate in the Locust summary is the demo working
as designed — not a broken test. Turn `errorFraction` down in the Faces chart itself if
you want a clean baseline to measure against.

If you are running the load test from **outside** the `faces` namespace, use the fully
qualified name instead: `--set locust.targetHost=http://face.faces.svc.cluster.local`.

---

## Using your own registry instead of GHCR

The chart's image is `image.registry` + `/` + `image.repository`, so pointing it at a
private Harbor (or ECR, or Artifactory) is two values plus a pull secret:

```bash
kubectl create secret docker-registry harbor-creds \
  --docker-server=harbor.example.com \
  --docker-username=robot\$loadtest \
  --docker-password="$HARBOR_TOKEN"

helm install my-test oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --set image.registry=harbor.example.com \
  --set image.repository=load-testing/k8s-locust-load-tester \
  --set image.tag=2.46.4 \
  --set imagePullSecrets[0].name=harbor-creds \
  --set locust.targetHost=http://my-service:8080 \
  --set-file locustfile.content=./locustfile.py
```

or in a values file:

```yaml
image:
  registry: harbor.example.com
  repository: load-testing/k8s-locust-load-tester
  tag: "2.46.4"

imagePullSecrets:
  - name: harbor-creds
```

`image.tag` falls back to the chart's `appVersion` when left empty. `image.digest`
(`sha256:...`) wins over the tag if you want the pull pinned rather than merely named.

### Getting the image into Harbor

`push.sh` builds and pushes a multi-arch image to any registry. CI already publishes to
GHCR on every push to `main` and every `v*` tag, so this script is for the cases CI does
not cover — a private registry, or a one-off local build.

```bash
docker login harbor.example.com

./push.sh harbor.example.com/load-testing k8s-locust-load-tester v1.0.0
```

```
Usage: push.sh <image-repo> <image-name> <image-tag>
```

* `PLATFORMS` — defaults to `linux/amd64,linux/arm64`. Multi-arch needs buildx and
  pushes straight from the builder, so the image will not appear in your local
  `docker images`. Set `PLATFORMS=linux/amd64` if you want it to.
* `LOCUST_VERSION` — the Locust version baked into the image; defaults to the
  Dockerfile's own default.

The chart mirrors nothing and pulls nothing on your behalf — if your cluster cannot
reach `ghcr.io`, mirror the image once and set `image.registry` for good.

---

## Building and running locally

### Build the container

```bash
docker build -t locust-load-tester:dev .
```

Multi-arch, if you need it:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t locust-load-tester:dev .
```

Override the bundled Locust with `--build-arg LOCUST_VERSION=2.45.0`. The image runs as
uid 1000, expects the locustfile in `/config`, and exposes 8089 (web UI) and 5557
(master/worker).

### Run the container

The entrypoint is `runLocust.sh` and everything is configured through environment
variables — the same contract the chart writes to:

```bash
docker run --rm \
  -v "$PWD:/config:ro" \
  -e TARGET_HOST=http://host.docker.internal:8080 \
  -e LOCUST_FILE=locustfile-dotnet-app.py \
  -e USERS=10 -e SPAWN_RATE=5 -e RUN_TIME=1m \
  locust-load-tester:dev
```

For the web UI, add `-e HEADLESS=false -p 8089:8089` and browse to
<http://127.0.0.1:8089>.

### Run the script directly

Requirements: `pip install locust`

The script looks for its locustfile in `/config` — that is where the chart mounts the
ConfigMap — so outside the container point it somewhere real:

```bash
LOCUST_CONFIG_DIR=. LOCUST_FILE=locustfile-dotnet-app.py \
  ./runLocust.sh -h http://localhost:8080 -c 10
```

#### Parameters

* `-h [host]` — hostname and port where the application is exposed. Required unless
  `TARGET_HOST` is already in the environment.
* `-c [clients]` — concurrent simulated users. Optional, default 2.
* `-d [seconds]` — delay before starting. Optional, default 0.
* `-r [requests]` — **accepted and ignored**, see below.

Anything after the flags is appended verbatim to the `locust` command line.

#### What changed in Locust since v1 of this script

Locust moved on, and two things in the old script no longer exist upstream:

* **`--no-web` became `--headless`.** The old script passed `--no-web` unless
  `WEB_UI=true`; modern Locust does not accept it. The script now uses `--headless`, and
  the switch is `HEADLESS` (default `true`). `WEB_UI` is still honoured as a deprecated
  alias — it wins over `HEADLESS` and logs a warning — so old invocations keep working.
* **`-r` is gone.** It meant "number of requests", the idea behind Locust's old `-n` /
  `--num-request`, which upstream removed years ago — a run is bounded by `--run-time`
  now. (v1 of this script never passed the value to Locust anyway; it only printed it.)
  Passing `-r` logs a warning and changes nothing. Use `RUN_TIME=5m` instead.

One more behaviour change worth knowing: v1 refused to start unless the target answered
HTTP 200. That is wrong for most services — a 302, 401 or 404 on `/` is perfectly
normal — so the readiness poll is now opt-in (`WAIT_FOR_HOST=true`), accepts any HTTP
response unless `WAIT_FOR_HOST_STATUS` pins an exact code, and only *warns* on timeout
rather than exiting. A load test that reports connection errors is more useful than a
pod that refuses to start.

Running `./runLocust.sh` with an unrecognised flag prints the usage summary, which lists
the environment variables it reads.

---

## Migrating from `create-locust-loadtest-deploy.sh`

The old script wrote a ConfigMap and a Deployment YAML for you to `kubectl apply`. It
still works and is kept for muscle memory, but the chart replaces it. Everything the
script could do is a value:

| Old flag | New chart value |
| --- | --- |
| `-n perf` | `helm install ... --namespace perf --create-namespace` |
| `-d dotnet-loadtest` | the Helm release name: `helm install dotnet-loadtest ...` |
| `-c locust-loadtest-cm` | not needed — the ConfigMap is rendered and named from the release. Use `locustfile.existingConfigMap` to bring your own |
| `-i IMAGE` | `image.registry`, `image.repository`, `image.tag` |
| `-f ./locustfile.py` | `--set-file locustfile.content=./locustfile.py` |
| `-h http://dotnet-8-app:5000` | `locust.targetHost=http://dotnet-8-app:5000` |
| `-r 5` | `locust.spawnRate=5` |
| `-t 5m` | `locust.runTime=5m` (see below) |
| *(no flag existed)* | `locust.users=10` |
| `WEB_UI=true` env var | `locust.headless=false` (plus `service.enabled=true` to reach the UI) |
| `kubectl apply -f cm.yaml -f deploy.yaml` | `helm install`, `helm upgrade`, `helm uninstall` |

### About that `-t` flag

The original script had a genuine bug worth naming, because if you copied its defaults
into a runbook you inherited it:

* `-t` was documented as `Run time (default: 5m)`, but the parser assigned it to the
  `USERS` variable, which was written to the ConfigMap's `users` key and surfaced to the
  container as `USERS`.
* `USERS` itself defaulted to the string `"5m"`.
* There was no run-time key at all — nothing in the generated manifest ever set
  `--run-time`.

So `-t 10m` set `--users 10m`, and running the script with no flags at all set
`--users 5m` and no time limit. Locust refuses the value outright —
`locust: error: argument -u/--users: invalid int value: '5m'` — which is a confusing way
to be told your run time went to the wrong flag. The chart keeps the two ideas apart and
gives each an honest default:

| Value | Meaning | Default |
| --- | --- | --- |
| `locust.users` | peak concurrent users (`--users`) | `10` |
| `locust.runTime` | how long the run lasts (`--run-time`) | `""` — run until the release is uninstalled |

`locust.spawnRate` (`--spawn-rate`, default `5`) is the third of the trio: how fast the
users ramp up to `locust.users`.

---

## Repository layout

```
Dockerfile                       the generic Locust image
runLocust.sh                     entrypoint; turns env vars into a locust command line
push.sh                          build + push to any registry (Harbor, ECR, ...)
create-locust-loadtest-deploy.sh deprecated pre-chart script, kept for compatibility
charts/locust-load-tester/       the Helm chart
  charts/locust-load-tester/ci/  install permutations exercised by CI
examples/                        installable values files for the locustfiles below
locustfile-*.py                  example tests: dotnet app, emojivoto, sock-shop, faces
```

`charts/locust-load-tester/ci/*-values.yaml` are install permutations — standalone,
distributed, Job, web UI. [chart-testing](https://github.com/helm/chart-testing)
auto-discovers any `ci/` directory inside a chart, so every PR installs all four onto a
kind cluster and runs `helm test` against each. They target CoreDNS's metrics endpoint,
which answers HTTP 200 in a bare kind cluster with nothing to install and nothing to
pull. CI separately renders a wider set of `--set` permutations through `kubeconform`.

## Releasing

Cutting a new image or chart version, the one-time GitHub setup it depends on, and how
to roll a bad release back: see [RELEASING.md](RELEASING.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE).

Made with love by Phil Henderson ([@fragglehunter](https://github.com/fragglehunter)).
