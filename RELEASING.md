# Releasing

Two things ship from this repo, on two independent triggers:

| Artifact | Published to | Trigger |
| --- | --- | --- |
| Container image | `ghcr.io/fragglehunter/k8s-locust-load-tester` | push to `main`, and any `v*` tag |
| Helm chart | `oci://ghcr.io/fragglehunter/charts/locust-load-tester` **and** `https://fragglehunter.github.io/k8s-locust-load-tester` | push to `main` touching `charts/**` |

Everything runs on `GITHUB_TOKEN`. There are no secrets to configure and, on a public
repo, nothing here costs anything.

---

## One-time setup

Do these once, in order. Step 2 has to wait for the first workflow run — GHCR packages
do not exist until something is pushed to them — so the practical sequence is: do steps
3 and 4, push, then come back and do step 2.

### 1. GHCR: nothing to create

There is no "create a package" step. The first successful run of `.github/workflows/image.yaml`
creates the `k8s-locust-load-tester` package, and the first successful run of
`.github/workflows/chart-release.yaml` creates `charts/locust-load-tester`. Both are
created **private**, owned by your user account.

### 2. Make both packages public and link them to the repo

Until you do this, `docker pull` and `helm pull` fail for everyone else with a
`denied`/`unauthorized` error that looks like the image does not exist.

For **each** of the two packages — `k8s-locust-load-tester` and
`charts/locust-load-tester`:

1. Go to <https://github.com/fragglehunter?tab=packages>, or the **Packages** section in
   the repository sidebar, and open the package.
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public** →
   confirm by typing the package name.
3. On the same page, check **Manage Actions access**: the
   `fragglehunter/k8s-locust-load-tester` repository must be listed with the **Write**
   role, so later workflow runs can keep pushing to it. It is added automatically the
   first time a workflow pushes; add it manually if it is missing.

Only public packages get free storage and bandwidth. Private ones bill against your
account quota.

**Linking to the repository** happens by itself, from metadata that is already in the
repo, so there is normally nothing to click:

* The image carries `LABEL org.opencontainers.image.source="https://github.com/fragglehunter/k8s-locust-load-tester"`
  (see the `Dockerfile`). GHCR reads that label and attaches the package to the repo,
  which is also what puts the repo's README and its Apache-2.0 licence on the package
  page.
* The chart gets the same annotation from `sources[0]` in `charts/locust-load-tester/Chart.yaml`,
  which Helm converts to OCI annotations when it pushes.

If a package page still shows no repository, use **Package settings** → **Connect
repository** to link it by hand.

### 3. Create the `gh-pages` branch, then turn on GitHub Pages

`chart-releaser` publishes `index.yaml` by committing to `gh-pages`. It does **not**
create the branch, and the workflow fails if it is missing. Create it once, empty:

```bash
git switch --orphan gh-pages
git commit --allow-empty -m "Initialise chart repository branch"
git push -u origin gh-pages
git switch main
```

Then: **Settings** → **Pages** → **Build and deployment** → Source: **Deploy from a
branch** → Branch: **`gh-pages`**, folder **`/ (root)`** → **Save**.

A minute or so later `https://fragglehunter.github.io/k8s-locust-load-tester/index.yaml`
starts serving. That URL — without `/index.yaml` — is what people pass to
`helm repo add`.

This step is only needed for the `helm repo add` flow. The OCI chart at
`oci://ghcr.io/fragglehunter/charts/locust-load-tester` works without Pages at all.

### 4. Settings → Actions → General

* **Actions permissions**: Actions must be enabled, with **Allow all actions and
  reusable workflows** selected. If you prefer an allow-list, it must cover
  `actions/*`, `docker/*`, `helm/*`, `azure/setup-helm@*` and `hadolint/*`.
* **Workflow permissions**: the restricted default — *Read repository contents and
  package permissions* — is correct and should be left alone. Every workflow here
  declares its own `permissions:` block and requests exactly what it needs
  (`contents: write` for the GitHub Release and the `gh-pages` commit,
  `packages: write` for the two registry pushes, `id-token`/`attestations: write` for
  build provenance), and an explicit block grants those regardless of the default.

  If a release ever fails with `403 Resource not accessible by integration` on the
  `gh-pages` push or the `helm push`, that is the setting to look at: switching it to
  **Read and write permissions** is the fix, but check the workflow's `permissions:`
  block first, because a missing scope there is the far more likely cause.

* Optional: **Settings** → **Branches** → protect `main` and require the `lint`,
  `chart`, `chart-test` and `build` checks from the CI workflow.

---

## Cutting a release

### What to bump

| Change | Bump |
| --- | --- |
| Anything under `charts/**` | `version` in `charts/locust-load-tester/Chart.yaml` (SemVer: patch for a fix, minor for a new value, major for a breaking rename or default change) |
| A new Locust version | `ARG LOCUST_VERSION` in `Dockerfile`, `appVersion` in `Chart.yaml`, the Locust badge in `README.md` — **and** `version`, because the chart's default image changed |
| `Dockerfile` / `runLocust.sh` only | nothing is strictly required, but a chart `version` bump is polite if the env-var contract changed |

Keep a line in `annotations."artifacthub.io/changes"` in `Chart.yaml` describing the
change; Artifact Hub renders it as the changelog.

### The versioning rule that is easy to get wrong

`image.tag` defaults to the chart's `appVersion`. So for a default install to work,
**an image tagged exactly `<appVersion>` has to exist in GHCR** — and the image workflow
only produces bare version tags from `v*` git tags.

The scheme that keeps this true with no extra thought: **tag the repo `v<locust-version>`**,
e.g. `v2.46.4` when `appVersion: "2.46.4"`. If you would rather version the repo
independently of Locust, then set `image.tag` explicitly in `values.yaml` instead of
leaving it empty, and stop relying on the `appVersion` fallback.

### Steps

1. Make the change on a branch and open a PR. `.github/workflows/ci.yaml` runs on it:
   hadolint + shellcheck + actionlint + yamllint, `helm lint` and `kubeconform -strict`
   over five value permutations, `ct lint` and a real `ct install` on a kind cluster
   using an image built from that commit, and a build-and-smoke-test of the image.
2. Merge to `main`. Two workflows fire:
   * **Image** (`image.yaml`) — builds `linux/amd64` and `linux/arm64`, pushes tags
     `main` and `sha-<short>`, attaches an SBOM and a signed build-provenance
     attestation. `latest` does **not** move; only tags move `latest`.
   * **Release chart** (`chart-release.yaml`) — only if the push touched `charts/**`.
     `chart-releaser` packages the chart, creates a GitHub Release named
     `locust-load-tester-<version>` with the `.tgz` attached, and commits an updated
     `index.yaml` to `gh-pages`. Then the same package is pushed to
     `oci://ghcr.io/fragglehunter/charts`. Both halves are idempotent: an unchanged
     `version` finds the release and the OCI tag already present and skips them, so a
     README-only commit under `charts/**` is a harmless no-op.
3. Tag the release so the image gets real version tags:

   ```bash
   git switch main && git pull
   git tag -a v2.46.4 -m "Locust 2.46.4"
   git push origin v2.46.4
   ```

   The Image workflow runs again and publishes `2.46.4`, `2.46`, `2` and `latest`. (The
   bare major tag is suppressed for `v0.x` — a `0` tag would imply a stability a 0.x
   series does not have.)

Neither workflow is cancellable by a newer run: a superseded build has still produced a
digest worth keeping, and cancelling mid-push can leave a tag pointing at nothing.

---

## Verifying a release

Chart, from the OCI registry:

```bash
helm show chart oci://ghcr.io/fragglehunter/charts/locust-load-tester --version 0.1.1
helm pull oci://ghcr.io/fragglehunter/charts/locust-load-tester --version 0.1.1
```

Chart, from the Pages repository:

```bash
curl -sSf https://fragglehunter.github.io/k8s-locust-load-tester/index.yaml | head -20

helm repo add locust-load-tester https://fragglehunter.github.io/k8s-locust-load-tester
helm repo update
helm search repo locust-load-tester --versions
```

Image:

```bash
docker pull ghcr.io/fragglehunter/k8s-locust-load-tester:2.46.4
docker run --rm --entrypoint locust ghcr.io/fragglehunter/k8s-locust-load-tester:2.46.4 --version

# both architectures are really in the index
docker buildx imagetools inspect ghcr.io/fragglehunter/k8s-locust-load-tester:2.46.4

# the build provenance the workflow attested
gh attestation verify oci://ghcr.io/fragglehunter/k8s-locust-load-tester:2.46.4 \
  --repo fragglehunter/k8s-locust-load-tester
```

End to end, which is the only check that proves the chart and the image agree:

```bash
helm install verify oci://ghcr.io/fragglehunter/charts/locust-load-tester \
  --version 0.1.1 \
  --set workload.kind=Job \
  --set locust.targetHost=http://kube-dns.kube-system.svc.cluster.local:9153 \
  --set locust.runTime=20s \
  --set-file locustfile.content=./locustfile.py \
  --wait

kubectl logs -l app.kubernetes.io/instance=verify --tail=50
helm uninstall verify
```

Do it as an anonymous user too — `docker logout ghcr.io` first — or you will not notice
that the packages are still private.

---

## Rolling back a bad release

### Preferred: roll forward

Published versions are immutable and consumers may already have them cached. Fixing
forward is almost always right:

* **Chart** — bump the patch version, merge, and let the workflow publish it. `helm repo
  update` picks it up; `helm upgrade --version <good>` puts an existing release back on
  a known-good chart.
* **Image** — build the fix and cut a new tag. To point `latest` back at an older
  release without inventing a version, re-run the Image workflow on the good tag:
  **Actions** → **Image** → **Run workflow** → select the tag → run. It republishes the
  same digest and moves `latest` with it.

### Actually deleting a version

Sometimes you do have to remove one — a leaked secret, a chart that installs something
harmful. GHCR versions are deleted per package version.

List what is there:

```bash
gh api /user/packages/container/k8s-locust-load-tester/versions \
  --jq '.[] | {id, tags: .metadata.container.tags}'

# the chart package's name contains a slash, so it has to be URL-encoded
gh api /user/packages/container/charts%2Flocust-load-tester/versions \
  --jq '.[] | {id, tags: .metadata.container.tags}'
```

Delete one:

```bash
gh api --method DELETE /user/packages/container/k8s-locust-load-tester/versions/<ID>
```

or through the UI: package page → **Package settings** → **Manage versions** → the row's
**⋯** → **Delete version**.

Two GitHub rules to know before you rely on this:

* A public package version with **more than 5,000 downloads** cannot be deleted
  self-service; you have to ask GitHub Support.
* Deleting the **only** version deletes the package itself. It will be recreated,
  private again, by the next push — so redo the "make it public" step from the one-time
  setup if that happens.

### Retracting a chart version

Deleting the OCI version is only half of it — the Pages repository is a separate copy:

1. Delete the OCI package version, as above.
2. Delete the GitHub Release `locust-load-tester-<version>` and its git tag:

   ```bash
   gh release delete locust-load-tester-0.1.1 --cleanup-tag --yes
   ```

3. Remove that version's entry from `index.yaml` on the `gh-pages` branch and push. Do
   not regenerate the whole index — hand-edit the one `- apiVersion:` block under
   `entries.locust-load-tester` whose `version:` matches, and leave the rest alone so
   the `created` timestamps and digests of good versions survive.
4. Tell anyone who has already pulled it, and bump to a good version. `helm repo update`
   removes it from search results but does not touch a release that is already
   installed.

Because `chart-releaser` runs with `skip_existing: true`, re-releasing the *same*
version number after a deletion works, but do not: consumers who cached the bad `.tgz`
will never see the replacement. Bump the patch instead.
