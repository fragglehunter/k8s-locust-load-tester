ARG PYTHON_VERSION=3.13-slim

FROM python:${PYTHON_VERSION}

ARG LOCUST_VERSION=2.46.4

# Build metadata. CI passes real values (docker/metadata-action); the defaults keep
# a plain `docker build .` honest rather than pretending to be a release.
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED=1970-01-01T00:00:00Z

# image.source is what links the GHCR package to the repo: it makes the package
# inherit the repo's public visibility and its Apache-2.0 license.
LABEL org.opencontainers.image.source="https://github.com/fragglehunter/k8s-locust-load-tester" \
      org.opencontainers.image.title="k8s-locust-load-tester" \
      org.opencontainers.image.description="Locust load generator for Kubernetes, configured entirely through environment variables." \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"

# Unbuffered so `kubectl logs` streams live; no bytecode because /config is a
# read-only ConfigMap mount and the rootfs is read-only in the chart.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd --gid 1000 locust \
    && useradd --uid 1000 --gid 1000 --no-log-init --create-home --shell /usr/sbin/nologin locust \
    && mkdir -p /config \
    && chown 1000:1000 /config

# locust, pyzmq and faker all publish manylinux wheels for amd64 and arm64, so no
# compiler toolchain (and no apt at all) is needed. pyzmq is what makes
# master/worker mode work; faker is here because the bundled example locustfiles
# import it.
# hadolint ignore=DL3013
RUN pip install --no-cache-dir "locust==${LOCUST_VERSION}" pyzmq faker

COPY runLocust.sh /usr/local/bin/runLocust.sh

RUN chmod 0755 /usr/local/bin/runLocust.sh

# 8089 = web UI, 5557 = master/worker comms (Locust 2.x uses a single port).
EXPOSE 8089 5557

USER 1000:1000
WORKDIR /config

ENTRYPOINT ["/usr/local/bin/runLocust.sh"]
