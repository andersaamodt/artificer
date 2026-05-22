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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-run-next.XXXXXX")
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

project_json=$(run_client project add --path "$workspace_root" --name "Run Next Demo")
[ "$(json_query "$project_json" 'data.get("success")')" = "true" ] || fail "project add failed"
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
[ -n "$workspace_id" ] || fail "missing workspace id"

session_json=$(run_client session create --workspace-id "$workspace_id" --title "Headless Run Next")
[ "$(json_query "$session_json" 'data.get("success")')" = "true" ] || fail "session create failed"
conversation_id=$(json_query "$session_json" '((data.get("session") or {}).get("id") or "")')
[ -n "$conversation_id" ] || fail "missing conversation id"

message_json=$(run_client session message \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --prompt "Create hello.sh that prints Hello, world! and run it." \
  --run-mode programming \
  --compute-budget quick \
  --command-exec-mode all \
  --permission-mode workspace-write)
[ "$(json_query "$message_json" 'data.get("success")')" = "true" ] || fail "session message failed"
[ "$(json_query "$message_json" '((data.get("session") or {}).get("queue") or {}).get("pending")')" = "1" ] || fail "message should queue one pending item"

run_next_json=$(run_client session run-next \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --stream-session "headless-smoke")
[ "$(json_query "$run_next_json" 'data.get("success")')" = "true" ] || fail "session run-next failed"
[ "$(json_query "$run_next_json" 'data.get("has_item")')" = "true" ] || fail "session run-next should report dequeued item"
[ "$(json_query "$run_next_json" 'data.get("stream_session")')" = "headless-smoke" ] || fail "session run-next should preserve requested stream session"
[ "$(json_query "$run_next_json" '((data.get("run") or {}).get("success"))')" = "true" ] || fail "nested run payload should succeed"
[ "$(json_query "$run_next_json" '((data.get("session") or {}).get("queue") or {}).get("pending")')" = "0" ] || fail "queue should be drained after run-next"
[ "$(json_query "$run_next_json" '((data.get("session") or {}).get("queue") or {}).get("last_status")')" = "done" ] || fail "queue last_status should be done after deterministic run"
[ "$(json_query "$run_next_json" 'len(((data.get("session") or {}).get("messages") or [])) >= 2')" = "true" ] || fail "run-next should append assistant output"
[ "$(json_query "$run_next_json" '"I created hello.sh" in ((((data.get("session") or {}).get("messages") or [{}])[-1]).get("content") or "")')" = "true" ] || fail "assistant output should summarize hello.sh execution"
[ -f "$workspace_root/hello.sh" ] || fail "run-next should create hello.sh in workspace"

events_json=$(run_client session events --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$events_json" 'len(((data.get("trace") or {}).get("events") or [])) >= 1')" = "true" ] || fail "run-next should append at least one run event"
[ "$(json_query "$events_json" '"Detected hello-world script task." in ((((data.get("trace") or {}).get("events") or [{}])[-1]).get("stream_text") or "")')" = "true" ] || fail "run event trace should retain streamed hello-world progress text"

stream_json=$(run_client session stream --workspace-id "$workspace_id" --conversation-id "$conversation_id" --stream-session "headless-smoke" --offset 0)
[ "$(json_query "$stream_json" 'data.get("success")')" = "true" ] || fail "stream poll should succeed after run-next"
[ "$(json_query "$stream_json" '"Detected hello-world script task." in ((data.get("delta") or ""))')" = "true" ] || fail "stream poll should expose hello-world progress output"
[ "$(json_query "$stream_json" '"Run finished." in ((data.get("delta") or ""))')" = "true" ] || fail "stream poll should expose final completion line"

printf '%s\n' "ok control-plane session run-next runtime: headless clients can dequeue, execute, trace, and stream a queued run through the shared backend path"
