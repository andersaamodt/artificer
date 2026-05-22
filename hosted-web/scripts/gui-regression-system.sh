#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

browser_choice="auto"

pass_args=""
append_arg() {
  if [ -z "$pass_args" ]; then
    pass_args=$1
  else
    pass_args=$(printf '%s\n%s' "$pass_args" "$1")
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --browser)
      browser_choice=$2
      shift 2
      ;;
    *)
      append_arg "$1"
      shift
      ;;
  esac
done

normalize_browser_choice() {
  value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    auto|safari|firefox)
      printf '%s' "$value"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

browser_choice=$(normalize_browser_choice "$browser_choice")
if [ -z "$browser_choice" ]; then
  echo "Unknown --browser value (expected auto, safari, or firefox)." >&2
  exit 1
fi

run_selected() {
  selected=$1
  script_path=""
  case "$selected" in
    safari)
      script_path="$SCRIPT_DIR/gui-regression-safari.sh"
      ;;
    firefox)
      script_path="$SCRIPT_DIR/gui-regression-firefox.sh"
      ;;
    *)
      echo "Unsupported browser selection: $selected" >&2
      return 1
      ;;
  esac

  if [ ! -x "$script_path" ]; then
    echo "Automation script missing or not executable: $script_path" >&2
    return 1
  fi

  if [ -z "$pass_args" ]; then
    exec "$script_path"
  fi

  # Preserve argument boundaries using a temporary file list.
  args_file=$(mktemp "${TMPDIR:-/tmp}/artificer-gui-args.XXXXXX")
  printf '%s\n' "$pass_args" > "$args_file"
  set --
  while IFS= read -r arg_line; do
    set -- "$@" "$arg_line"
  done < "$args_file"
  rm -f "$args_file"
  exec "$script_path" "$@"
}

if [ "$browser_choice" = "safari" ]; then
  if ! command -v osascript >/dev/null 2>&1; then
    echo "Safari automation requested but osascript is unavailable." >&2
    exit 1
  fi
  run_selected "safari"
  exit $?
fi

if [ "$browser_choice" = "firefox" ]; then
  run_selected "firefox"
  exit $?
fi

kernel_name=$(uname -s 2>/dev/null || printf '%s' "")
case "$kernel_name" in
  Darwin)
    if command -v osascript >/dev/null 2>&1; then
      run_selected "safari"
      exit $?
    fi
    run_selected "firefox"
    exit $?
    ;;
  Linux)
    run_selected "firefox"
    exit $?
    ;;
  *)
    run_selected "firefox"
    exit $?
    ;;
esac
