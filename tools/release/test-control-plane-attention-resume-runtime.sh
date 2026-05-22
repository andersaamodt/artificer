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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-attention-resume.XXXXXX")
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

project_json=$(run_client project add --path "$workspace_root" --name "Approval Resume Demo")
[ "$(json_query "$project_json" 'data.get("success")')" = "true" ] || fail "project add failed"
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
[ -n "$workspace_id" ] || fail "missing workspace id"

session_json=$(run_client session create --workspace-id "$workspace_id" --title "Approval Resume")
[ "$(json_query "$session_json" 'data.get("success")')" = "true" ] || fail "session create failed"
conversation_id=$(json_query "$session_json" '((data.get("session") or {}).get("id") or "")')
[ -n "$conversation_id" ] || fail "missing conversation id"

message_json=$(run_client session message \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --prompt "Create hello.sh that prints Hello, world! and run it." \
  --run-mode programming \
  --compute-budget quick \
  --command-exec-mode ask-some \
  --permission-mode workspace-write)
[ "$(json_query "$message_json" 'data.get("success")')" = "true" ] || fail "session message failed"

first_run_json=$(run_client session run-next \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --stream-session "approval-step-1")
[ "$(json_query "$first_run_json" 'data.get("success")')" = "true" ] || fail "first run-next failed"
[ "$(json_query "$first_run_json" '((data.get("session") or {}).get("queue") or {}).get("last_status")')" = "awaiting_approval" ] || fail "first run-next should stop in awaiting_approval"
[ "$(json_query "$first_run_json" '"approval_required" in (((data.get("run") or {}).get("session_log") or ""))')" = "true" ] || fail "first run-next should record approval_required in session log"
[ "$(json_query "$first_run_json" '(((data.get("session") or {}).get("approval_request")) or {}).get("command", "")')" = "./hello.sh" ] || fail "approval request should preserve blocked command"

attention_json=$(run_client attention list)
[ "$(json_query "$attention_json" 'len(data.get("items") or [])')" = "1" ] || fail "attention list should expose one pending approval"
[ "$(json_query "$attention_json" '((data.get("items") or [{}])[0]).get("kind", "")')" = "approval" ] || fail "attention item kind should be approval"

approval_json=$(run_client attention approval-answer \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --decision allow \
  --scope once \
  --match-mode exact \
  --command "./hello.sh")
[ "$(json_query "$approval_json" 'data.get("success")')" = "true" ] || fail "approval answer failed"
[ "$(json_query "$approval_json" '((data.get("session") or {}).get("queue") or {}).get("pending")')" = "1" ] || fail "approval answer should queue exactly one retry item"
[ "$(json_query "$approval_json" '(((data.get("session") or {}).get("approval_request")) is None)')" = "true" ] || fail "approval answer should clear approval request"

second_run_json=$(run_client session run-next \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --stream-session "approval-step-2")
[ "$(json_query "$second_run_json" 'data.get("success")')" = "true" ] || fail "second run-next failed"
[ "$(json_query "$second_run_json" '((data.get("session") or {}).get("queue") or {}).get("last_status")')" = "done" ] || fail "second run-next should complete the resumed work"
[ "$(json_query "$second_run_json" 'len(((data.get("session") or {}).get("messages") or [])) >= 3')" = "true" ] || fail "resumed run should leave user + blocked assistant + final assistant messages"
[ "$(json_query "$second_run_json" '"Hello, world!" in ((((data.get("session") or {}).get("messages") or [{}])[-1]).get("content") or "")')" = "true" ] || fail "resumed run should report successful hello-world output"

events_json=$(run_client session events --workspace-id "$workspace_id" --conversation-id "$conversation_id")
[ "$(json_query "$events_json" 'len(((data.get("trace") or {}).get("events") or [])) >= 2')" = "true" ] || fail "events trace should preserve both blocked and resumed run events"
[ "$(json_query "$events_json" '(((data.get("trace") or {}).get("events") or [{}])[0]).get("status", "")')" = "awaiting_approval" ] || fail "first run event should preserve awaiting_approval status"
[ "$(json_query "$events_json" '(((data.get("trace") or {}).get("events") or [{}])[-1]).get("status", "")')" = "done" ] || fail "last run event should preserve done status after resume"

printf '%s\n' "ok control-plane attention resume runtime: headless approval gates can be answered and resumed to completion through run-next"
