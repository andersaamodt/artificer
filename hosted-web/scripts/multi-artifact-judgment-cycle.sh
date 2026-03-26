#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PARENT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)

SITE_ROOT=""
if [ -x "$PROJECT_ROOT/hosted-web/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT/hosted-web"
elif [ -x "$PROJECT_ROOT/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT"
elif [ -x "$PARENT_ROOT/web/artificer/cgi/artificer-api" ]; then
  SITE_ROOT="$PARENT_ROOT/web/artificer"
fi

if [ -z "$SITE_ROOT" ]; then
  echo "Could not locate artificer site root from $SCRIPT_DIR" >&2
  exit 1
fi

BROAD_CYCLE="$SCRIPT_DIR/broad-reasoning-cycle.sh"
DEFAULT_REGRESSIONS="$SITE_ROOT/tests/fixtures/artificer-multi-artifact-judgment-regressions-v1.tsv"
DEFAULT_HOLDOUT="$SITE_ROOT/tests/fixtures/artificer-multi-artifact-judgment-holdout-v1.tsv"

usage() {
  cat <<'USAGE'
Usage:
  multi-artifact-judgment-cycle.sh run [--profile regressions|holdout] [broad-reasoning-cycle run args...]
  multi-artifact-judgment-cycle.sh transfer [broad-reasoning-cycle transfer args...]

Notes:
  - This is a thin wrapper over broad-reasoning-cycle.sh with multi-artifact-judgment defaults.
  - `run` defaults to the regressions fixture unless `--profile holdout` is provided.
USAGE
}

[ -x "$BROAD_CYCLE" ] || {
  echo "broad-reasoning-cycle.sh is not executable: $BROAD_CYCLE" >&2
  exit 1
}

command_name=${1:-}
[ -n "$command_name" ] || {
  usage >&2
  exit 1
}
shift

case "$command_name" in
  run)
    profile="regressions"
    while [ $# -gt 0 ]; do
      case "$1" in
        --profile)
          profile=${2:-}
          shift 2
          ;;
        *)
          break
          ;;
      esac
    done
    case "$profile" in
      regressions)
        tasks_file=$DEFAULT_REGRESSIONS
        ;;
      holdout)
        tasks_file=$DEFAULT_HOLDOUT
        ;;
      *)
        echo "Unknown --profile value: $profile" >&2
        exit 1
        ;;
    esac
    exec sh "$BROAD_CYCLE" run --tasks-file "$tasks_file" "$@"
    ;;
  transfer)
    exec sh "$BROAD_CYCLE" transfer "$@"
    ;;
  -h|--help|--usage)
    usage
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage >&2
    exit 1
    ;;
esac
