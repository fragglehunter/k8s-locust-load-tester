#!/bin/bash
###################################################################################################################
# Purpose: Run Locust Load test
# Created on: 12.26.24
# Updated on: 04.24.25
# Made with Love by: Phil Henderson
# Version 1.11
###################################################################################################################

SCRIPT_NAME=$(basename "$0")
INITIAL_DELAY=1
# Default values will be overridden if passed via flags
: "${CLIENTS:=2}"
: "${REQUESTS:=10}"
: "${HATCH_RATE:=5}"

do_usage() {
  cat >&2 <<EOF
Usage:
  ${SCRIPT_NAME} -h hostname [OPTIONS]

Options:
  -d  Delay before starting (in seconds, default: 1)
  -h  Target host URL, e.g. http://localhost/
  -c  Number of clients (default: 2)
  -r  Number of requests (default: 10)

Environment Variables:
  WEB_UI=true     Enables Locust Web UI instead of running headlessly.

Description:
  Runs a Locust load simulation against the specified host.
EOF
  exit 1
}

do_check() {
  if [ -z "$TARGET_HOST" ]; then
    echo "[ERROR] TARGET_HOST is not set; use '-h hostname:port'"
    exit 1
  fi

  if ! command -v locust &> /dev/null; then
    echo "[ERROR] Python 'locust' package is not found!"
    exit 1
  fi

  if [ -n "${LOCUST_FILE:+1}" ]; then
    echo "[INFO] Locust file: $LOCUST_FILE"
  else
    LOCUST_FILE="locustfile.py"
    echo "[INFO] Default Locust file: $LOCUST_FILE"
  fi
}

do_exec() {
  sleep "$INITIAL_DELAY"

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_HOST}")
  if [ "$STATUS" -ne 200 ]; then
    echo "[ERROR] ${TARGET_HOST} is not accessible (HTTP $STATUS)"
    exit 1
  fi

  echo "[INFO] Running $LOCUST_FILE against $TARGET_HOST with $CLIENTS clients and $REQUESTS requests."

  LOCUST_CMD="locust --host=http://${TARGET_HOST} -f ${LOCUST_FILE} --clients=${CLIENTS} --hatch-rate=${HATCH_RATE} --num-request=${REQUESTS}"

  if [ "${WEB_UI}" != "true" ]; then
    LOCUST_CMD="$LOCUST_CMD --no-web --only-summary"
  fi

  echo "[INFO] Executing: $LOCUST_CMD"
  eval "$LOCUST_CMD"

  echo "[INFO] Done"
}

# Parse command-line options
while getopts ":d:h:c:r:" opt; do
  case "${opt}" in
    d)
      INITIAL_DELAY=${OPTARG}
      ;;
    h)
      TARGET_HOST=${OPTARG}
      ;;
    c)
      CLIENTS=${OPTARG}
      ;;
    r)
      REQUESTS=${OPTARG}
      ;;
    *)
      do_usage
      ;;
  esac
done

# Show usage if no arguments are passed
if [ "$OPTIND" -eq 1 ]; then
  do_usage
fi

do_check
do_exec
