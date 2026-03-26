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

RICH_CYCLE="$SCRIPT_DIR/rich-reasoning-cycle.sh"
DEFAULT_REGRESSIONS="$SITE_ROOT/tests/fixtures/artificer-long-context-reassessment-regressions-v1.tsv"
DEFAULT_HOLDOUT="$SITE_ROOT/tests/fixtures/artificer-long-context-reassessment-holdout-v1.tsv"

usage() {
  cat <<'USAGE'
Usage:
  long-context-reassessment-cycle.sh run [--profile regressions|holdout] [rich-reasoning-cycle run args...]
  long-context-reassessment-cycle.sh transfer [rich-reasoning-cycle transfer args...]

Notes:
  - This is a thin wrapper over rich-reasoning-cycle.sh with long-context-reassessment defaults.
  - `run` defaults to the regressions fixture unless `--profile holdout` is provided.
USAGE
}

[ -x "$RICH_CYCLE" ] || {
  echo "rich-reasoning-cycle.sh is not executable: $RICH_CYCLE" >&2
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
    exec sh "$RICH_CYCLE" run --tasks-file "$tasks_file" "$@"
    ;;
  transfer)
    exec sh "$RICH_CYCLE" transfer "$@"
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
