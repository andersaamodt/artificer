#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
api_path="$repo_root/hosted-web/cgi/artificer-api"
client="$repo_root/hosted-web/scripts/artificer-runtime-client"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

json_query() {
  payload=$1
  query=$2
  JSON_PAYLOAD=$payload JSON_QUERY=$query python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("JSON_PAYLOAD", ""))
query = os.environ.get("JSON_QUERY", "")
value = eval(query, {"__builtins__": {"len": len}}, {"data": payload})
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
elif value is None:
    print("")
else:
    print(str(value))
PY
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-runtime.XXXXXX")
isolated_home="$tmp_root/home"
data_home="$tmp_root/data"
state_home="$tmp_root/state"
mkdir -p "$isolated_home" "$data_home" "$state_home"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

run_client() {
  ARTIFICER_API_SCRIPT="$api_path" \
  WIZARDRY_DIR="$wizardry_dir_real" \
  HOME="$isolated_home" \
  XDG_DATA_HOME="$data_home" \
  XDG_STATE_HOME="$state_home" \
  ARTIFICER_STATE_ROOT="$state_home/artificer" \
  sh "$client" "$@"
}

describe_json=$(run_client describe)
[ "$(json_query "$describe_json" 'data.get("api_version")')" = "v1" ] || fail "control-plane describe should expose api_version v1"
[ "$(json_query "$describe_json" 'len(data.get("resources") or []) >= 7')" = "true" ] || fail "control-plane describe should expose resource catalog"
[ "$(json_query "$describe_json" 'len([item for item in (data.get("resources") or []) if item.get("name") == "sessions"])')" = "1" ] || fail "control-plane describe missing sessions resource"
[ "$(json_query "$describe_json" 'len([item for item in (data.get("resources") or []) if item.get("name") == "sessions" and "run-next" in (item.get("operations") or [])])')" = "1" ] || fail "control-plane describe should advertise headless session run-next"

health_json=$(run_client health)
[ "$(json_query "$health_json" 'data.get("runtime", {}).get("runtime_client_exists")')" = "1" ] || fail "control-plane health should expose runtime client availability"

project_json=$(run_client project add --path "$repo_root" --name "Artificer Repo")
[ "$(json_query "$project_json" 'data.get("success")')" = "true" ] || fail "project add failed"
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
[ -n "$workspace_id" ] || fail "project add missing workspace id"

session_json=$(run_client session create --workspace-id "$workspace_id" --title "Headless Smoke")
conversation_id=$(json_query "$session_json" '((data.get("session") or {}).get("id") or "")')
[ -n "$conversation_id" ] || fail "session create missing conversation id"
[ "$(json_query "$session_json" '((data.get("session") or {}).get("queue") or {}).get("pending")')" = "0" ] || fail "fresh session should not have queued items"

message_json=$(run_client session message --workspace-id "$workspace_id" --conversation-id "$conversation_id" --prompt "Inspect README.md and summarize it later." --run-mode programming --compute-budget quick)
[ "$(json_query "$message_json" 'data.get("success")')" = "true" ] || fail "session message failed"
[ "$(json_query "$message_json" 'len(((data.get("session") or {}).get("messages") or []))')" = "1" ] || fail "session message should persist user message immediately"
[ "$(json_query "$message_json" '((data.get("session") or {}).get("queue") or {}).get("pending")')" = "1" ] || fail "session message should queue exactly one pending item"

list_json=$(run_client session list --workspace-id "$workspace_id")
[ "$(json_query "$list_json" 'len(data.get("sessions") or [])')" = "1" ] || fail "session list should include created session"

get_json=$(run_client session get --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$get_json" '((data.get("session") or {}).get("title") or "")')" = "Headless Smoke" ] || fail "session get should preserve title"
[ "$(json_query "$get_json" 'len((((data.get("session") or {}).get("trace") or {}).get("events") or []))')" = "0" ] || fail "new queued session should not fabricate run events"
[ "$(json_query "$get_json" 'len((((data.get("session") or {}).get("trace") or {}).get("tool_hooks") or []))')" = "0" ] || fail "new queued session should expose an empty tool hook trace"

events_json=$(run_client session events --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$events_json" 'data.get("session_id")')" = "$conversation_id" ] || fail "session events should preserve session id"
[ "$(json_query "$events_json" 'len(((data.get("trace") or {}).get("events") or []))')" = "0" ] || fail "fresh queued session events should be empty"

printf '%s\n' "ok control-plane runtime api: describe/health/project/session create-message-get-list all succeed in isolated runtime"
