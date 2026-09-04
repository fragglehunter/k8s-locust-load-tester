#!/usr/bin/env bash
#
# Build and push the load-tester image to any registry.
#
# CI already publishes multi-arch images to ghcr.io on every push to main and every
# v* tag (see .github/workflows/image.yaml), so this script is for the cases CI does
# not cover: pushing to a private Harbor, or cutting a one-off local build.

set -euo pipefail

log_info() {
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

usage() {
  cat >&2 <<EOF
Usage: $0 <image-repo> <image-name> <image-tag>

  <image-repo>  Registry and namespace, e.g. ghcr.io/fragglehunter or harbor.example.com/load-testing
  <image-name>  Image name, e.g. k8s-locust-load-tester
  <image-tag>   Tag, e.g. v1.0.0

Environment:
  PLATFORMS       Target platforms (default: linux/amd64,linux/arm64).
                  Multi-arch requires buildx and pushes directly from the builder;
                  the image will not appear in your local 'docker images'.
  LOCUST_VERSION  Locust version to bake in (default: the Dockerfile's own default).

Example:
  $0 ghcr.io/fragglehunter k8s-locust-load-tester v1.0.0
  PLATFORMS=linux/amd64 $0 harbor.example.com/load-testing locust-load-tester v1.0.0
EOF
  exit 1
}

if [[ $# -ne 3 ]]; then
  log_error "Invalid number of arguments"
  usage
fi

IMAGE_REPO="$1"
IMAGE_NAME="$2"
IMAGE_TAG="$3"
FULL_IMAGE="${IMAGE_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

build_args=()
if [[ -n "${LOCUST_VERSION:-}" ]]; then
  build_args+=(--build-arg "LOCUST_VERSION=${LOCUST_VERSION}")
fi
build_args+=(--build-arg "VERSION=${IMAGE_TAG}")
if revision=$(git rev-parse HEAD 2>/dev/null); then
  build_args+=(--build-arg "REVISION=${revision}")
fi

if ! docker buildx version >/dev/null 2>&1; then
  log_error "docker buildx not found. Install it, or set PLATFORMS to a single platform and use a plain 'docker build'."
  exit 1
fi

log_info "Building and pushing ${FULL_IMAGE} for ${PLATFORMS}"
if docker buildx build \
  --platform "${PLATFORMS}" \
  "${build_args[@]}" \
  --tag "${FULL_IMAGE}" \
  --push \
  .; then
  log_info "Pushed ${FULL_IMAGE}"
else
  log_error "Build/push failed. If this is an auth error, run: docker login ${IMAGE_REPO%%/*}"
  exit 1
fi
