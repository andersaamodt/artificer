#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
action_file="$repo_root/hosted-web/cgi/actions/add_workspace.sh"

[ -f "$action_file" ] || {
  printf '%s\n' "missing add_workspace action: $action_file" >&2
  exit 1
}

run_case() {
  label=$1
  raw_path=$2
  expected_suffix=$3

  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-tilde-runtime.XXXXXX")
  home_dir="$tmp_root/home"
  workspaces_dir="$tmp_root/workspaces"
  runner_script="$tmp_root/run-add-workspace.sh"
  mkdir -p "$home_dir/project" "$workspaces_dir"

  cat > "$runner_script" <<'SH'
set -eu

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

param() {
  key=${1-}
  case "$key" in
    path)
      printf '%s' "${RAW_PATH-}"
      ;;
    name)
      printf '%s' ""
      ;;
    command_exec_mode)
      printf '%s' ""
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

emit_error() {
  msg=$1
  printf '{"success":false,"error":"%s"}\n' "$msg"
}

read_file_line() {
  file_path=$1
  fallback=${2-}
  if [ -f "$file_path" ]; then
    sed -n '1p' "$file_path"
    return
  fi
  printf '%s' "$fallback"
}

new_id() {
  printf '%s' "ws-1"
}

workspace_dir_for() {
  printf '%s/%s' "$workspaces_dir" "$1"
}

normalize_command_exec_mode_value() {
  printf '%s' ""
}

set_command_policy_mode_for_workspace() {
  :
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

workspaces_dir=$WORKSPACES_DIR
. "$ACTION_FILE"
SH
  output=$(HOME="$home_dir" RAW_PATH="$raw_path" WORKSPACES_DIR="$workspaces_dir" ACTION_FILE="$action_file" sh "$runner_script")

  expected_path=$(cd "$home_dir$expected_suffix" && pwd -P)
  output_path=$(printf '%s\n' "$output" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p' | sed -n '1p')
  [ -n "$output_path" ] || {
    printf '%s\n' "runtime tilde expansion test ($label) missing path in response: $output" >&2
    rm -rf "$tmp_root"
    exit 1
  }

  if [ "$output_path" != "$expected_path" ]; then
    printf '%s\n' "runtime tilde expansion test ($label) expected path $expected_path, got $output_path" >&2
    rm -rf "$tmp_root"
    exit 1
  fi

  stored_path_file="$workspaces_dir/ws-1/path"
  [ -f "$stored_path_file" ] || {
    printf '%s\n' "runtime tilde expansion test ($label) missing persisted path file" >&2
    rm -rf "$tmp_root"
    exit 1
  }
  stored_path=$(sed -n '1p' "$stored_path_file")
  if [ "$stored_path" != "$expected_path" ]; then
    printf '%s\n' "runtime tilde expansion test ($label) persisted path mismatch: expected $expected_path got $stored_path" >&2
    rm -rf "$tmp_root"
    exit 1
  fi

  rm -rf "$tmp_root"
}

run_case "home-shortcut" "~" ""
run_case "home-child" "~/project" "/project"
run_case "encoded-home-child" "%7E/project" "/project"

printf '%s\n' "ok add_workspace runtime tilde expansion resolves ~ and %7E prefixes"
