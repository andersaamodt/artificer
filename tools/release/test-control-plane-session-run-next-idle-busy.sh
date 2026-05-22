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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-run-next-idle-busy.XXXXXX")
isolated_home="$tmp_root/home"
data_home="$tmp_root/data"
state_home="$tmp_root/state"
workspace_root="$tmp_root/workspace"
mkdir -p "$isolated_home" "$data_home" "$state_home" "$workspace_root"

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

invoke_post() {
  body=$1
  content_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
  printf '%s' "$body" | \
    ARTIFICER_API_SCRIPT="$api_path" \
    WIZARDRY_DIR="$wizardry_dir_real" \
    HOME="$isolated_home" \
    XDG_DATA_HOME="$data_home" \
    XDG_STATE_HOME="$state_home" \
    ARTIFICER_STATE_ROOT="$state_home/artificer" \
    REQUEST_METHOD=POST \
    CONTENT_TYPE='application/x-www-form-urlencoded' \
    CONTENT_LENGTH="$content_length" \
    "$api_path" | awk 'BEGIN { body = 0 } { line = $0; sub(/\r$/, "", line); if (body == 1) { print line; next } if (line == "") { body = 1 } }'
}

project_json=$(run_client project add --path "$workspace_root" --name "Run Next Idle Busy")
[ "$(json_query "$project_json" 'data.get("success")')" = "true" ] || fail "project add failed"
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
[ -n "$workspace_id" ] || fail "missing workspace id"

session_json=$(run_client session create --workspace-id "$workspace_id" --title "Idle Busy")
[ "$(json_query "$session_json" 'data.get("success")')" = "true" ] || fail "session create failed"
conversation_id=$(json_query "$session_json" '((data.get("session") or {}).get("id") or "")')
[ -n "$conversation_id" ] || fail "missing conversation id"

idle_json=$(run_client session run-next --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$idle_json" 'data.get("success")')" = "true" ] || fail "idle run-next failed"
[ "$(json_query "$idle_json" 'data.get("has_item")')" = "false" ] || fail "idle run-next should not dequeue work"
[ "$(json_query "$idle_json" 'data.get("busy")')" = "false" ] || fail "idle run-next should not report busy"
[ -z "$(json_query "$idle_json" 'data.get("stream_session")')" ] || fail "idle run-next should not fabricate a stream_session"

message_json=$(run_client session message \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --prompt "Create hello.sh that prints Hello, world! and run it." \
  --run-mode programming \
  --compute-budget quick \
  --command-exec-mode ask-some \
  --permission-mode workspace-write)
[ "$(json_query "$message_json" 'data.get("success")')" = "true" ] || fail "session message failed"

take_json=$(invoke_post "action=queue_take&workspace_id=$workspace_id&conversation_id=$conversation_id")
[ "$(json_query "$take_json" 'data.get("success")')" = "true" ] || fail "queue_take failed"
[ "$(json_query "$take_json" 'data.get("has_item")')" = "true" ] || fail "queue_take should move one item to running"
running_item_id=$(json_query "$take_json" '((data.get("item") or {}).get("id") or "")')
[ -n "$running_item_id" ] || fail "queue_take missing running item id"

conv_dir=$(find "$tmp_root" -type d -path "*/workspaces/$workspace_id/conversations/$conversation_id" | sed -n '1p')
[ -n "$conv_dir" ] || fail "unable to locate isolated conversation directory"
queue_dir="$conv_dir/queue"
printf '%s\n' "existing-headless-run" > "$queue_dir/running.stream_session"

busy_json=$(run_client session run-next --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$busy_json" 'data.get("success")')" = "true" ] || fail "busy run-next failed"
[ "$(json_query "$busy_json" 'data.get("has_item")')" = "false" ] || fail "busy run-next should not dequeue a second item"
[ "$(json_query "$busy_json" 'data.get("busy")')" = "true" ] || fail "busy run-next should report busy"
[ "$(json_query "$busy_json" 'data.get("running_item_id")')" = "$running_item_id" ] || fail "busy run-next should preserve running item id"
[ "$(json_query "$busy_json" 'data.get("stream_session")')" = "existing-headless-run" ] || fail "busy run-next should surface the actual running stream session"

printf '%s\n' "ok control-plane session run-next idle/busy: no-item runs stay streamless and busy sessions surface the actual running stream id"
