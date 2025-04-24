#!/usr/bin/env bash

set -euo pipefail

# Logging functions
log_info() {
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

# Usage help
usage() {
  echo "Usage: $0 <image-repo> <image-name> <image-tag>"
  echo "Example: $0 ghcr.io/yourorg my-app v1.0.0"
  exit 1
}

# Validate args
if [[ $# -ne 3 ]]; then
  log_error "Invalid number of arguments"
  usage
fi

IMAGE_REPO="$1"
IMAGE_NAME="$2"
IMAGE_TAG="$3"
FULL_IMAGE="${IMAGE_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

log_info "Building Docker image: ${FULL_IMAGE}"
if docker build -t "$FULL_IMAGE" .; then
  log_info "Docker image built successfully."
else
  log_error "Failed to build Docker image."
  exit 1
fi

log_info "Pushing Docker image: ${FULL_IMAGE}"
if docker push "$FULL_IMAGE"; then
  log_info "Docker image pushed successfully."
else
  log_error "Failed to push Docker image."
  exit 1
fi
