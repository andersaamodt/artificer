#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-cgi-action-contract.XXXXXX")
sites_root="$tmp_root/sites"
state_home="$tmp_root/state"
api_out_file="$tmp_root/cgi.out"
api_err_file="$tmp_root/cgi.err"
mkdir -p "$sites_root" "$state_home"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

wait_with_timeout() {
  target_pid=$1
  timeout_seconds=$2
  elapsed=0
  while kill -0 "$target_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      kill "$target_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$target_pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 0
}

default_extra='workspace_id=missing-workspace&conversation_id=missing-conversation&automation_id=missing-automation&item_id=missing-item&stream_session=missing-session&session_id=missing-session'

action_skip_reason() {
  case "$1" in
    pick_workspace)
      printf '%s' "opens a native folder chooser"
      return 0
      ;;
    git_choose_ssh_key)
      printf '%s' "opens a native file chooser"
      return 0
      ;;
    git_generate_ssh)
      printf '%s' "mutates user SSH key material"
      return 0
      ;;
    dictation_install|dictation_install_start|dictation_uninstall)
      printf '%s' "install/uninstall voice runtime side effects"
      return 0
      ;;
    dictate|dictate_prepare|dictate_start)
      printf '%s' "can start live microphone capture"
      return 0
      ;;
    self_improve_run)
      printf '%s' "can invoke long-running model work"
      return 0
      ;;
  esac
  return 1
}

action_extra_for() {
  action_name=$1
  case "$action_name" in
    add_workspace)
      printf '%s' "path=relative/path&name=example&$default_extra"
      ;;
    automation_daemon_set)
      printf '%s' "enabled=maybe&$default_extra"
      ;;
    model_install_start|model_uninstall|set_model)
      printf '%s' "model=invalid%20model&$default_extra"
      ;;
    *)
      printf '%s' "$default_extra"
      ;;
  esac
}

extract_json_body() {
  response_file=$1
  awk '
    BEGIN {
      in_body = 0
      last = ""
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (in_body == 0) {
        if (line == "") {
          in_body = 1
        }
        next
      }
      if (line != "") {
        last = line
      }
    }
    END {
      print last
    }
  ' "$response_file"
}

validate_action_response() {
  action_name=$1
  if [ -s "$api_err_file" ]; then
    printf '%s\n' "stderr emitted for action $action_name:" >&2
    sed -n '1,120p' "$api_err_file" >&2
    fail "action $action_name emitted stderr"
  fi

  if ! grep -q '^Status: 200 OK' "$api_out_file"; then
    printf '%s\n' "unexpected CGI status for action $action_name:" >&2
    sed -n '1,120p' "$api_out_file" >&2
    fail "action $action_name did not return Status: 200 OK"
  fi

  response_body=$(extract_json_body "$api_out_file")
  if [ -z "$response_body" ]; then
    response_body=$(tail -n 1 "$api_out_file")
  fi

  case "$response_body" in
    *'"success":true'*|*'"success":false'*)
      ;;
    *)
      printf '%s\n' "invalid JSON envelope for action $action_name:" >&2
      sed -n '1,120p' "$api_out_file" >&2
      fail "action $action_name response missing success field"
      ;;
  esac

  if ! RESPONSE_BODY="$response_body" python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("RESPONSE_BODY", "")
try:
    payload = json.loads(raw)
except Exception:
    sys.exit(1)

if not isinstance(payload, dict):
    sys.exit(2)

if "success" not in payload:
    sys.exit(3)
PY
  then
    printf '%s\n' "response was not valid top-level JSON for action $action_name:" >&2
    printf '%s\n' "$response_body" >&2
    fail "action $action_name returned malformed JSON"
  fi
}

invoke_action() {
  action_name=$1
  action_extra=$2
  query="action=$action_name"
  if [ -n "$action_extra" ]; then
    query="$query&$action_extra"
  fi

  : >"$api_out_file"
  : >"$api_err_file"
  (
    REQUEST_METHOD=GET
    QUERY_STRING=$query
    SCRIPT_NAME='/cgi/artificer-api'
    SCRIPT_FILENAME=$api_path
    GATEWAY_INTERFACE='CGI/1.1'
    SERVER_PROTOCOL='HTTP/1.1'
    HTTP_HOST='localhost:8082'
    WIZARDRY_SITE_NAME='artificer'
    WIZARDRY_SITES_DIR=$sites_root
    WEB_WIZARDRY_ROOT=$sites_root
    XDG_STATE_HOME=$state_home
    ARTIFICER_STATE_ROOT="$state_home/artificer"
    export REQUEST_METHOD QUERY_STRING SCRIPT_NAME SCRIPT_FILENAME GATEWAY_INTERFACE SERVER_PROTOCOL HTTP_HOST
    export WIZARDRY_SITE_NAME WIZARDRY_SITES_DIR WEB_WIZARDRY_ROOT XDG_STATE_HOME ARTIFICER_STATE_ROOT
    sh "$api_path"
  ) >"$api_out_file" 2>"$api_err_file" &
  action_pid=$!

  if ! wait_with_timeout "$action_pid" 15; then
    fail "action $action_name timed out after 15 seconds (query: $query)"
  fi
  action_rc=0
  wait "$action_pid" || action_rc=$?
  if [ "$action_rc" -ne 0 ]; then
    printf '%s\n' "non-zero exit for action $action_name (rc=$action_rc):" >&2
    sed -n '1,120p' "$api_err_file" >&2
    fail "action $action_name exited non-zero"
  fi

  validate_action_response "$action_name"
}

WEB_WIZARDRY_ROOT="$sites_root" \
WIZARDRY_SITES_DIR="$sites_root" \
XDG_STATE_HOME="$state_home" \
ARTIFICER_STATE_ROOT="$state_home/artificer" \
sh "$repo_root/artificer" ensure-site >/dev/null

site_root="$sites_root/artificer"
api_path="$site_root/cgi/artificer-api"
actions_dir="$site_root/cgi/actions"

[ -f "$api_path" ] || fail "missing CGI entrypoint: $api_path"
[ -d "$actions_dir" ] || fail "missing CGI actions directory: $actions_dir"

tested_count=0
skipped_count=0
total_count=0

for action_file in "$actions_dir"/*.sh; do
  [ -f "$action_file" ] || continue
  action_name=$(basename "$action_file" .sh)
  [ "$action_name" = "_default" ] && continue
  total_count=$((total_count + 1))

  if skip_reason=$(action_skip_reason "$action_name"); then
    skipped_count=$((skipped_count + 1))
    printf '%s\n' "skip action=$action_name reason=$skip_reason"
    continue
  fi

  action_extra=$(action_extra_for "$action_name")
  invoke_action "$action_name" "$action_extra"
  tested_count=$((tested_count + 1))
done

if [ "$tested_count" -lt 1 ]; then
  fail "no CGI actions were exercised"
fi

invoke_action "__unknown_action__" "$default_extra"
tested_count=$((tested_count + 1))

printf '%s\n' "ok cgi action contract: total=$total_count tested=$tested_count skipped=$skipped_count"
