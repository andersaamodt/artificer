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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-control-plane-self-actuation.XXXXXX")
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

preview_json=$(run_client self-actuation preview --action bootstrap_workspace_stack --path "$workspace_root" --title "Bootstrap Thread" --name "Nightly Review" --prompt "Inspect the workspace" --schedule-kind interval --schedule-value 900)
[ "$(json_query "$preview_json" 'data.get("mode")')" = "preview" ] || fail "self-actuation preview should stay in preview mode"
confirm_token=$(json_query "$preview_json" 'data.get("confirm_token", "")')
[ -n "$confirm_token" ] || fail "self-actuation preview missing confirm_token"
[ "$(json_query "$preview_json" 'len(data.get("planned_changes") or []) >= 2')" = "true" ] || fail "self-actuation preview should plan workspace/thread changes"

apply_json=$(run_client self-actuation apply --action bootstrap_workspace_stack --path "$workspace_root" --title "Bootstrap Thread" --name "Nightly Review" --prompt "Inspect the workspace" --schedule-kind interval --schedule-value 900 --confirm-token "$confirm_token" --idempotency-key "bootstrap-stack")
[ "$(json_query "$apply_json" 'data.get("mode")')" = "apply" ] || fail "self-actuation apply should return apply mode"
workspace_id=$(json_query "$apply_json" 'data.get("workspace_id", "")')
conversation_id=$(json_query "$apply_json" 'data.get("conversation_id", "")')
automation_id=$(json_query "$apply_json" 'data.get("automation_id", "")')
[ -n "$workspace_id" ] || fail "self-actuation apply missing workspace_id"
[ -n "$conversation_id" ] || fail "self-actuation apply missing conversation_id"
[ -n "$automation_id" ] || fail "self-actuation apply missing automation_id"

project_json=$(run_client project get --workspace-id "$workspace_id")
[ "$(json_query "$project_json" 'len((data.get("project") or {}).get("sessions") or [])')" = "1" ] || fail "self-actuation apply should create exactly one session"

automation_json=$(run_client automation get --automation-id "$automation_id")
[ "$(json_query "$automation_json" '((data.get("automation") or {}).get("name") or "")')" = "Nightly Review" ] || fail "self-actuation apply should create requested automation"

idempotent_json=$(run_client self-actuation apply --action bootstrap_workspace_stack --path "$workspace_root" --title "Bootstrap Thread" --name "Nightly Review" --prompt "Inspect the workspace" --schedule-kind interval --schedule-value 900 --confirm-token "$confirm_token" --idempotency-key "bootstrap-stack")
[ "$(json_query "$idempotent_json" 'data.get("idempotent_hit")')" = "1" ] || fail "self-actuation apply should honor idempotency keys"

printf '%s\n' "ok control-plane self-actuation runtime: preview/apply/idempotency all succeed through the headless control surface"
