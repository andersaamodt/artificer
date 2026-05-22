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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-attention.XXXXXX")
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

project_json=$(run_client project add --path "$repo_root" --name "Artificer Repo")
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
session_json=$(run_client session create --workspace-id "$workspace_id" --title "Attention Smoke")
conversation_id=$(json_query "$session_json" '((data.get("session") or {}).get("id") or "")')
run_client session message --workspace-id "$workspace_id" --conversation-id "$conversation_id" --prompt "Inspect README.md and ask before dangerous commands." --run-mode programming >/dev/null

invoke_post "action=assay_inject_approval_request&workspace_id=$workspace_id&conversation_id=$conversation_id&command=./deploy.sh%20--env%20prod&reason=attention-test" >/dev/null
attention_json=$(run_client attention list)
[ "$(json_query "$attention_json" 'len(data.get("items") or [])')" = "1" ] || fail "attention list should expose one approval request"
[ "$(json_query "$attention_json" '((data.get("items") or [{}])[0]).get("kind", "")')" = "approval" ] || fail "attention list should expose approval kind"

approval_json=$(run_client attention approval-answer --workspace-id "$workspace_id" --conversation-id "$conversation_id" --decision allow --scope once --match-mode exact --command "./deploy.sh --env prod")
[ "$(json_query "$approval_json" 'data.get("success")')" = "true" ] || fail "approval answer failed"
[ "$(json_query "$approval_json" '(((data.get("session") or {}).get("approval_request")) is None)')" = "true" ] || fail "approval answer should clear approval request"
[ "$(json_query "$approval_json" '((data.get("session") or {}).get("queue") or {}).get("pending", 0) >= 1')" = "true" ] || fail "approval answer should queue a retry"

invoke_post "action=assay_inject_decision_request&workspace_id=$workspace_id&conversation_id=$conversation_id&question=Ship%20now?&options=Ship%20now|Wait%20for%20logs" >/dev/null
attention_json=$(run_client attention list)
[ "$(json_query "$attention_json" 'len(data.get("items") or [])')" = "1" ] || fail "attention list should expose one decision request after injection"
[ "$(json_query "$attention_json" '((data.get("items") or [{}])[0]).get("kind", "")')" = "decision" ] || fail "attention list should expose decision kind"

decision_json=$(run_client attention decision-answer --workspace-id "$workspace_id" --conversation-id "$conversation_id" --answer "Wait for logs")
[ "$(json_query "$decision_json" 'data.get("success")')" = "true" ] || fail "decision answer failed"
[ "$(json_query "$decision_json" '(((data.get("session") or {}).get("decision_request")) is None)')" = "true" ] || fail "decision answer should clear decision request"
[ "$(json_query "$decision_json" 'len(((data.get("session") or {}).get("messages") or [])) >= 2')" = "true" ] || fail "decision answer should append a decision message"

printf '%s\n' "ok control-plane attention workflow: approval and decision requests are listed, answered, and reflected back into session state"
