#!/bin/bash

#################################################################################################
# Purpose: Deploy a configurable Locust load test in Kubernetes
# Updated on: 04.24.25
# Made with Love by: Phil Henderson
# Version: 1.0
#################################################################################################

set -e

# Default values
CONFIGMAP_NAME="locust-loadtest-cm"
DEPLOYMENT_NAME="locust-loadtest"
NAMESPACE="default"
SPAWN_RATE="5"
USERS="5m"
TARGET_HOST="http://my-service:8080"
LOCUSTFILE_PATH="locustfile.py"
IMAGE="locust-load-test:v2.0"
SCRIPT_NAME=$(basename "$0")
: "${WEB_UI:=false}"

# Logging functions
log_info() {
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_error() {
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  -n NAMESPACE       Kubernetes namespace (default: default)
  -c CONFIGMAP_NAME  ConfigMap name (default: locust-loadtest-cm)
  -d DEPLOY_NAME     Deployment name (default: locust-loadtest)
  -i IMAGE           Locust Docker image (default: locustio/locust:2.25.0)
  -f LOCUSTFILE      Path to locustfile.py (default: locustfile.py)
  -h TARGET_HOST        Target host (default: http://my-service:8080)
  -r SPAWN_RATE      Spawn rate (default: 5)
  -t USERS        Run time (default: 5m)
  --help             Show this help

Example:
  $SCRIPT_NAME -n perf -f locustfile.py -h http://dotnet-8-app:5000 -d dotnet-loadtest
EOF
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAMESPACE="$2"; shift 2 ;;
    -c) CONFIGMAP_NAME="$2"; shift 2 ;;
    -d) DEPLOYMENT_NAME="$2"; shift 2 ;;
    -i) IMAGE="$2"; shift 2 ;;
    -f) LOCUSTFILE_PATH="$2"; shift 2 ;;
    -h) TARGET_HOST="$2"; shift 2 ;;
    -r) SPAWN_RATE="$2"; shift 2 ;;
    -t) USERS="$2"; shift 2 ;;
    --help) usage ;;
    *) log_error "Unknown option: $1"; usage ;;
  esac
done

# Check for required tools
if ! command -v kubectl &>/dev/null; then
  log_error "kubectl not found. Please install it first."
  exit 1
fi

# Check locustfile.py exists
if [ ! -f "$LOCUSTFILE_PATH" ]; then
  log_error "Locust file '$LOCUSTFILE_PATH' not found."
  exit 1
fi

log_info "Creating ConfigMap '$CONFIGMAP_NAME' in namespace '$NAMESPACE'..."

kubectl create configmap "$CONFIGMAP_NAME" \
  --from-file=locustfile.py="$LOCUSTFILE_PATH" \
  --from-literal=hatchrate="$SPAWN_RATE" \
  --from-literal=users="$USERS" \
  --from-literal=targethost="$TARGET_HOST" \
  -n "$NAMESPACE" --dry-run=client -o yaml > $CONFIGMAP_NAME.yaml

log_info "Deploying Locust load test as '$DEPLOYMENT_NAME'..."

cat <<EOF > $DEPLOYMENT_NAME.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: locust-loadtest
spec:
  replicas: 1
  selector:
    matchLabels:
      app: locust-loadtest
  template:
    metadata:
      labels:
        app: locust-loadtest
    spec:
      containers:
      - name: locust
        image: $IMAGE
        env:
        - name: TARGET_HOST
          valueFrom:
            configMapKeyRef:
              name: $CONFIGMAP_NAME
              key: targethost
        - name: SPAWN_RATE
          valueFrom:
            configMapKeyRef:
              name: $CONFIGMAP_NAME
              key: hatchrate
        - name: USERS
          valueFrom:
            configMapKeyRef:
              name: $CONFIGMAP_NAME
              key: users
        - name: WEB_UI
          value: "$WEB_UI"
        volumeMounts:
        - name: config-volume
          mountPath: /config
      volumes:
      - name: config-volume
        configMap:
          name: $CONFIGMAP_NAME
EOF

log_info "Locust load test deployed successfully!"
