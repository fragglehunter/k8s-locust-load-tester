#!/usr/bin/env bash
###################################################################################################################
# Purpose: Entrypoint for the k8s-locust-load-tester image. Builds a Locust command
#          line from environment variables (the contract the Helm chart writes to)
#          and execs it. Legacy flags from v1 of this script still work.
# Made with Love by: Phil Henderson
###################################################################################################################
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

# --- Defaults ----------------------------------------------------------------
# Anything the Helm chart sets always wins; these only matter for bare
# `docker run`. USERS/SPAWN_RATE keep the v1 defaults so old local invocations
# behave the same (the chart's own defaults are 10/5).
: "${LOCUST_CONFIG_DIR:=/config}"
: "${LOCUST_FILE:=locustfile.py}"
: "${TARGET_HOST:=}"
: "${USERS:=2}"
: "${SPAWN_RATE:=5}"
: "${RUN_TIME:=}"
: "${HEADLESS:=true}"
: "${AUTOSTART:=false}"
: "${ONLY_SUMMARY:=false}"
: "${LOGLEVEL:=INFO}"
: "${EXIT_CODE_ON_ERROR:=}"
: "${STOP_TIMEOUT:=}"
: "${TAGS:=}"
: "${EXCLUDE_TAGS:=}"
: "${CSV_PREFIX:=}"
: "${CSV_FULL_HISTORY:=false}"
: "${HTML_REPORT:=}"
: "${LOCUST_RUN_MODE:=standalone}"
: "${MASTER_HOST:=}"
: "${MASTER_PORT:=5557}"
: "${EXPECT_WORKERS:=}"
: "${WEB_PORT:=8089}"
: "${WEB_HOST:=0.0.0.0}"
: "${WAIT_FOR_HOST:=false}"
: "${WAIT_FOR_HOST_TIMEOUT:=60}"
: "${WAIT_FOR_HOST_STATUS:=}"
: "${LOOP:=false}"
: "${EXTRA_PIP_PACKAGES:=}"
: "${LOCUST_EXTRA_ARGS:=}"

# Legacy: v1 accepted -d/-r and the WEB_UI env var.
: "${INITIAL_DELAY:=0}"
: "${REQUESTS:=}"
: "${WEB_UI:=}"

# Seconds between runs when LOOP=true, and between WAIT_FOR_HOST polls.
readonly LOOP_SLEEP=5
readonly POLL_INTERVAL=2
readonly PIP_TARGET_DIR=/tmp/pip-packages

CHILD_PID=""

# --- Helpers -----------------------------------------------------------------
# Everything goes to stderr: bash block-buffers stdout on a pipe, so mixing the two
# reorders our own lines in `kubectl logs`. Locust logs to stderr too, which leaves
# stdout to the stats tables alone.
log() {
  local level=$1
  shift
  printf '[%s] %s\n' "$level" "$*" >&2
}

is_true() {
  case "${1,,}" in
    true | yes | 1 | on) return 0 ;;
    *) return 1 ;;
  esac
}

do_usage() {
  cat >&2 <<EOF
Usage:
  ${SCRIPT_NAME} [-h hostname] [OPTIONS] [-- extra locust args]

Options (legacy v1 flags, kept for backwards compatibility):
  -h  Target host URL, e.g. http://localhost:8080   (env TARGET_HOST)
  -c  Number of clients                             (env USERS)
  -r  Number of requests -- ACCEPTED BUT IGNORED, see below
  -d  Delay in seconds before starting              (env INITIAL_DELAY)

Everything else is configured through environment variables; see the README for
the full list (TARGET_HOST, USERS, SPAWN_RATE, RUN_TIME, HEADLESS, AUTOSTART,
LOCUST_RUN_MODE, WAIT_FOR_HOST, LOOP, EXTRA_PIP_PACKAGES, LOCUST_EXTRA_ARGS, ...).

Any arguments left after the flags above are appended verbatim to the locust
command line.
EOF
  exit 1
}

# Terminate promptly on pod deletion instead of sitting out
# terminationGracePeriodSeconds. This script is PID 1, and PID 1 *ignores* any
# signal it has no handler for -- so without this trap a SIGTERM arriving while we
# are still installing pip packages or polling WAIT_FOR_HOST is silently dropped
# and the pod lingers until the kubelet SIGKILLs it. Installed before any waiting;
# the non-looping path then execs locust, which handles its own signals.
terminate() {
  local signal=$1
  log INFO "Received SIG${signal}; shutting down."
  if [[ -n "$CHILD_PID" ]]; then
    kill -s "$signal" "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  exit 0
}

# sleep in the background and wait on it, so a trapped signal interrupts the nap
# rather than being queued until it finishes.
nap() {
  sleep "$1" &
  CHILD_PID=$!
  wait "$CHILD_PID" 2>/dev/null || true
  CHILD_PID=""
}

# --- Startup checks ----------------------------------------------------------
resolve_locustfile() {
  if [[ "$LOCUST_FILE" == /* ]]; then
    LOCUSTFILE_PATH="$LOCUST_FILE"
  else
    LOCUSTFILE_PATH="${LOCUST_CONFIG_DIR%/}/${LOCUST_FILE}"
  fi

  if [[ ! -f "$LOCUSTFILE_PATH" ]]; then
    log ERROR "Locustfile not found: ${LOCUSTFILE_PATH}"
    if [[ -d "$LOCUST_CONFIG_DIR" ]]; then
      log ERROR "Contents of ${LOCUST_CONFIG_DIR}:"
      ls -la "$LOCUST_CONFIG_DIR" >&2 || true
    else
      log ERROR "Config directory ${LOCUST_CONFIG_DIR} does not exist. Mount your locustfile there (the chart mounts a ConfigMap)."
    fi
    exit 1
  fi
  log INFO "Locustfile: ${LOCUSTFILE_PATH}"
}

do_check() {
  if ! command -v locust > /dev/null 2>&1; then
    log ERROR "The 'locust' executable was not found on PATH."
    exit 1
  fi

  case "$LOCUST_RUN_MODE" in
    standalone | master | worker) ;;
    *)
      log ERROR "LOCUST_RUN_MODE must be standalone, master or worker; got '${LOCUST_RUN_MODE}'."
      exit 1
      ;;
  esac

  # A worker gets its host from the master, so only the other modes need one.
  if [[ -z "$TARGET_HOST" && "$LOCUST_RUN_MODE" != "worker" ]]; then
    log ERROR "TARGET_HOST is not set; use '-h http://host:port' or the TARGET_HOST env var."
    exit 1
  fi

  if [[ "$LOCUST_RUN_MODE" == "worker" && -z "$MASTER_HOST" ]]; then
    log ERROR "LOCUST_RUN_MODE=worker requires MASTER_HOST."
    exit 1
  fi

  if [[ -n "$REQUESTS" ]]; then
    # Locust removed -n/--num-request years ago (a run is bounded by --run-time
    # now), just as --no-web became --headless. Accept the old flag, do nothing.
    log WARN "-r/REQUESTS ('${REQUESTS}') is ignored: Locust removed -n/--num-request. Use RUN_TIME to bound the run."
  fi

  # Legacy alias: WEB_UI=true meant "serve the web UI", i.e. not headless.
  if [[ -n "$WEB_UI" ]]; then
    if is_true "$WEB_UI"; then
      log WARN "WEB_UI=${WEB_UI} is deprecated; treating it as HEADLESS=false."
      HEADLESS=false
    else
      log WARN "WEB_UI=${WEB_UI} is deprecated; treating it as HEADLESS=true."
      HEADLESS=true
    fi
  fi

  resolve_locustfile
}

install_extra_packages() {
  [[ -n "$EXTRA_PIP_PACKAGES" ]] || return 0

  local packages=()
  read -r -a packages <<< "$EXTRA_PIP_PACKAGES" || true
  ((${#packages[@]})) || return 0

  # --target keeps everything under /tmp (an emptyDir) so this still works with
  # readOnlyRootFilesystem: true.
  log INFO "Installing extra pip packages into ${PIP_TARGET_DIR}: ${packages[*]}"
  pip install --no-cache-dir --target "$PIP_TARGET_DIR" "${packages[@]}"
  export PYTHONPATH="${PIP_TARGET_DIR}${PYTHONPATH:+:${PYTHONPATH}}"
  log INFO "PYTHONPATH=${PYTHONPATH}"
}

# Print the HTTP status the target answered with, or fail if nothing answered.
# Redirects are deliberately not followed so WAIT_FOR_HOST_STATUS=302 is testable.
http_status() {
  python3 - "$1" <<'PY'
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


url = sys.argv[1]
opener = urllib.request.build_opener(NoRedirect)
request = urllib.request.Request(url, headers={"User-Agent": "runLocust.sh"})
try:
    with opener.open(request, timeout=5) as response:
        print(response.status)
except urllib.error.HTTPError as exc:
    # 3xx/4xx/5xx still prove something is listening and speaking HTTP.
    print(exc.code)
except Exception as exc:  # noqa: BLE001 - any failure means "not up yet"
    print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

# Opt-in readiness poll. v1 hard-failed unless the target returned 200, which is
# wrong for most services -- 302/401/404 on / are perfectly normal. Any HTTP
# response counts unless WAIT_FOR_HOST_STATUS pins an exact code, and a timeout
# only warns: a load test that reports connection errors is more useful than a
# pod that refuses to start.
wait_for_host() {
  is_true "$WAIT_FOR_HOST" || return 0

  local deadline=$((SECONDS + WAIT_FOR_HOST_TIMEOUT))
  local status=""

  if [[ -n "$WAIT_FOR_HOST_STATUS" ]]; then
    log INFO "Waiting up to ${WAIT_FOR_HOST_TIMEOUT}s for ${TARGET_HOST} to return HTTP ${WAIT_FOR_HOST_STATUS}."
  else
    log INFO "Waiting up to ${WAIT_FOR_HOST_TIMEOUT}s for ${TARGET_HOST} to answer over HTTP."
  fi

  while ((SECONDS < deadline)); do
    if status=$(http_status "$TARGET_HOST" 2>/dev/null); then
      if [[ -z "$WAIT_FOR_HOST_STATUS" || "$status" == "$WAIT_FOR_HOST_STATUS" ]]; then
        log INFO "${TARGET_HOST} answered with HTTP ${status}; starting."
        return 0
      fi
      log INFO "${TARGET_HOST} answered with HTTP ${status}, waiting for ${WAIT_FOR_HOST_STATUS}."
    fi
    nap "$POLL_INTERVAL"
  done

  log WARN "${TARGET_HOST} was not ready after ${WAIT_FOR_HOST_TIMEOUT}s; starting anyway."
}

# --- Command line assembly ---------------------------------------------------
# Built as an array and exec'd. Never eval a string: v1 did, and any value with a
# space or a quote in it (a tag, a header in LOCUST_EXTRA_ARGS) broke the run.
build_command() {
  local words=()

  LOCUST_ARGS=(locust --locustfile "$LOCUSTFILE_PATH" --loglevel "$LOGLEVEL")

  if [[ "$LOCUST_RUN_MODE" == "worker" ]]; then
    # Workers take their load profile from the master; passing --run-time or
    # --users here makes Locust complain (or exit), so send only worker flags.
    LOCUST_ARGS+=(--worker --master-host "$MASTER_HOST" --master-port "$MASTER_PORT")
  else
    LOCUST_ARGS+=(--host "$TARGET_HOST" --users "$USERS" --spawn-rate "$SPAWN_RATE")

    if [[ "$LOCUST_RUN_MODE" == "master" ]]; then
      LOCUST_ARGS+=(--master --master-bind-port "$MASTER_PORT")
      [[ -n "$EXPECT_WORKERS" ]] && LOCUST_ARGS+=(--expect-workers "$EXPECT_WORKERS")
    fi

    [[ -n "$EXIT_CODE_ON_ERROR" ]] && LOCUST_ARGS+=(--exit-code-on-error "$EXIT_CODE_ON_ERROR")
    [[ -n "$RUN_TIME" ]] && LOCUST_ARGS+=(--run-time "$RUN_TIME")
    [[ -n "$STOP_TIMEOUT" ]] && LOCUST_ARGS+=(--stop-timeout "$STOP_TIMEOUT")

    if is_true "$HEADLESS"; then
      LOCUST_ARGS+=(--headless)
    else
      LOCUST_ARGS+=(--web-host "$WEB_HOST" --web-port "$WEB_PORT")
      is_true "$AUTOSTART" && LOCUST_ARGS+=(--autostart)
    fi

    is_true "$ONLY_SUMMARY" && LOCUST_ARGS+=(--only-summary)

    if [[ -n "$CSV_PREFIX" ]]; then
      LOCUST_ARGS+=(--csv "$CSV_PREFIX")
      is_true "$CSV_FULL_HISTORY" && LOCUST_ARGS+=(--csv-full-history)
    fi

    [[ -n "$HTML_REPORT" ]] && LOCUST_ARGS+=(--html "$HTML_REPORT")
  fi

  # Tags are evaluated per process, so workers need them too.
  if [[ -n "$TAGS" ]]; then
    read -r -a words <<< "$TAGS" || true
    ((${#words[@]})) && LOCUST_ARGS+=(--tags "${words[@]}")
  fi

  if [[ -n "$EXCLUDE_TAGS" ]]; then
    read -r -a words <<< "$EXCLUDE_TAGS" || true
    ((${#words[@]})) && LOCUST_ARGS+=(--exclude-tags "${words[@]}")
  fi

  if [[ -n "$LOCUST_EXTRA_ARGS" ]]; then
    read -r -a words <<< "$LOCUST_EXTRA_ARGS" || true
    ((${#words[@]})) && LOCUST_ARGS+=("${words[@]}")
  fi

  # Anything left on our own command line, passed straight through.
  ((${#PASSTHROUGH_ARGS[@]})) && LOCUST_ARGS+=("${PASSTHROUGH_ARGS[@]}")

  return 0
}

do_exec() {
  log INFO "Run mode: ${LOCUST_RUN_MODE}"
  log INFO "Executing: $(printf '%q ' "${LOCUST_ARGS[@]}")"

  if ! is_true "$LOOP"; then
    exec "${LOCUST_ARGS[@]}"
  fi

  local rc=0
  while true; do
    rc=0
    "${LOCUST_ARGS[@]}" &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=""

    if ((rc != 0)); then
      log ERROR "Locust exited with status ${rc}; not looping."
      exit "$rc"
    fi

    log INFO "Locust finished cleanly; LOOP=true, restarting in ${LOOP_SLEEP}s."
    nap "$LOOP_SLEEP"
  done
}

# --- Main --------------------------------------------------------------------
trap 'terminate TERM' TERM
trap 'terminate INT' INT

while getopts ":d:h:c:r:" opt; do
  case "$opt" in
    d) INITIAL_DELAY=$OPTARG ;;
    h) TARGET_HOST=$OPTARG ;;
    c) USERS=$OPTARG ;;
    r) REQUESTS=$OPTARG ;;
    *) do_usage ;;
  esac
done
shift $((OPTIND - 1))
PASSTHROUGH_ARGS=("$@")

do_check
install_extra_packages

if [[ "$INITIAL_DELAY" != "0" ]]; then
  log INFO "Sleeping ${INITIAL_DELAY}s before starting."
  nap "$INITIAL_DELAY"
fi

[[ "$LOCUST_RUN_MODE" == "worker" ]] || wait_for_host

build_command
do_exec
