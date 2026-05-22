#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
appctl="$repo_root/hosted-web/scripts/artificer-appctl"
launcher="$repo_root/artificer"

[ -f "$appctl" ] || {
  printf '%s\n' "missing appctl script: $appctl" >&2
  exit 1
}
[ -f "$launcher" ] || {
  printf '%s\n' "missing launcher script: $launcher" >&2
  exit 1
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-actuation-orch-ops.XXXXXX")
sites_root="$tmp_root/sites"
state_home="$tmp_root/state"
isolated_home="$tmp_root/home"
projects_root="$tmp_root/projects"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}
mkdir -p "$sites_root" "$state_home" "$isolated_home" "$projects_root"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

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

payload = os.environ.get("JSON_PAYLOAD", "")
query = os.environ.get("JSON_QUERY", "")
data = json.loads(payload)
value = eval(query, {"__builtins__": {"len": len, "any": any}}, {"data": data})
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
else:
    print(str(value))
PY
}

run_appctl() {
  ARTIFICER_API_SCRIPT="$api_path" \
  WIZARDRY_SITE_NAME='artificer' \
  WIZARDRY_SITES_DIR="$sites_root" \
  WEB_WIZARDRY_ROOT="$sites_root" \
  WIZARDRY_DIR="$wizardry_dir_real" \
  HOME="$isolated_home" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  XDG_STATE_HOME="$state_home" \
  ARTIFICER_STATE_ROOT="$state_home/artificer" \
  sh "$appctl" "$@"
}

assert_success_json() {
  payload=$1
  label=$2
  ok=$(json_query "$payload" 'data.get("success", False)')
  [ "$ok" = "true" ] || fail "$label"
}

preview_apply_operation() {
  operation_name=$1
  shift
  preview_json=$(run_appctl self-actuation preview --operation "$operation_name" "$@" --json)
  preview_mode=$(json_query "$preview_json" 'data.get("mode", "")')
  [ "$preview_mode" = "preview" ] || fail "preview failed for operation $operation_name"
  confirm_token=$(json_query "$preview_json" 'data.get("confirm_token", "")')
  [ -n "$confirm_token" ] || fail "missing confirm_token for operation $operation_name"
  apply_json=$(run_appctl self-actuation apply --operation "$operation_name" "$@" --confirm-token "$confirm_token" --json)
  assert_success_json "$apply_json" "apply failed for operation $operation_name"
  apply_mode=$(json_query "$apply_json" 'data.get("mode", "")')
  [ "$apply_mode" = "apply" ] || fail "apply mode mismatch for operation $operation_name"
  printf '%s\n' "$apply_json"
}

WEB_WIZARDRY_ROOT="$sites_root" \
WIZARDRY_SITES_DIR="$sites_root" \
XDG_STATE_HOME="$state_home" \
ARTIFICER_STATE_ROOT="$state_home/artificer" \
sh "$launcher" ensure-site >/dev/null

site_root="$sites_root/artificer"
api_path="$site_root/cgi/artificer-api"
[ -x "$api_path" ] || fail "missing staged API script: $api_path"

primary_path="$projects_root/primary"
secondary_path="$projects_root/secondary"
mkdir -p "$primary_path" "$secondary_path"

primary_workspace_apply=$(preview_apply_operation ensure_workspace --path "$primary_path" --name "Primary Workspace")
primary_workspace_id=$(json_query "$primary_workspace_apply" 'data.get("workspace_id", "")')
[ -n "$primary_workspace_id" ] || fail "ensure_workspace did not return workspace id"

preview_apply_operation ensure_workspace --workspace-id "$primary_workspace_id" >/dev/null

preview_apply_operation rename_workspace --workspace-id "$primary_workspace_id" --name "Primary Renamed" >/dev/null
projects_after_rename=$(run_appctl project list --json)
primary_name=$(json_query "$projects_after_rename" '(data.get("workspaces") or [{}])[0].get("name", "")')
[ "$primary_name" = "Primary Renamed" ] || fail "rename_workspace did not persist new name"

primary_thread_apply=$(preview_apply_operation ensure_thread --workspace-id "$primary_workspace_id" --title "Primary Thread" --model "mistral:latest")
primary_conversation_id=$(json_query "$primary_thread_apply" 'data.get("conversation_id", "")')
[ -n "$primary_conversation_id" ] || fail "ensure_thread did not return conversation id"

primary_automation_apply=$(preview_apply_operation ensure_automation \
  --workspace-id "$primary_workspace_id" \
  --conversation-id "$primary_conversation_id" \
  --name "Primary Auto" \
  --prompt "summarize-primary" \
  --schedule-kind "interval" \
  --schedule-value "900" \
  --enabled "1" \
  --allow-self-reschedule "1")
primary_automation_id=$(json_query "$primary_automation_apply" 'data.get("automation_id", "")')
[ -n "$primary_automation_id" ] || fail "ensure_automation did not return automation id"

preview_apply_operation toggle_automation --automation-id "$primary_automation_id" --enabled "0" >/dev/null
autos_after_toggle_off=$(run_appctl automation list --json)
primary_enabled_off=$(json_query "$autos_after_toggle_off" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("enabled", "")')
[ "$primary_enabled_off" = "0" ] || fail "toggle_automation did not disable primary automation"

preview_apply_operation toggle_automation --automation-id "$primary_automation_id" --enabled "1" >/dev/null
autos_after_toggle_on=$(run_appctl automation list --json)
primary_enabled_on=$(json_query "$autos_after_toggle_on" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("enabled", "")')
[ "$primary_enabled_on" = "1" ] || fail "toggle_automation did not enable primary automation"

preview_apply_operation run_automation_now --automation-id "$primary_automation_id" >/dev/null

bootstrap_apply=$(preview_apply_operation bootstrap_workspace_stack \
  --path "$secondary_path" \
  --title "Secondary Thread" \
  --model "mistral:latest" \
  --name "Secondary Auto" \
  --prompt "summarize-secondary" \
  --schedule-kind "interval" \
  --schedule-value "600" \
  --enabled "1" \
  --allow-self-reschedule "1")
secondary_workspace_id=$(json_query "$bootstrap_apply" 'data.get("workspace_id", "")')
secondary_conversation_id=$(json_query "$bootstrap_apply" 'data.get("conversation_id", "")')
secondary_automation_id=$(json_query "$bootstrap_apply" 'data.get("automation_id", "")')
[ -n "$secondary_workspace_id" ] || fail "bootstrap_workspace_stack missing workspace id"
[ -n "$secondary_conversation_id" ] || fail "bootstrap_workspace_stack missing conversation id"
[ -n "$secondary_automation_id" ] || fail "bootstrap_workspace_stack missing automation id"

preview_apply_operation archive_thread --workspace-id "$primary_workspace_id" --conversation-id "$primary_conversation_id" >/dev/null
threads_after_archive=$(run_appctl thread list --workspace-id "$primary_workspace_id" --json)
primary_thread_count=$(json_query "$threads_after_archive" 'len((data.get("workspaces") or [{}])[0].get("conversations") or [])')
[ "$primary_thread_count" = "0" ] || fail "archive_thread did not remove primary conversation"

preview_apply_operation delete_automation --automation-id "$secondary_automation_id" >/dev/null
preview_apply_operation delete_automation --automation-id "$primary_automation_id" >/dev/null
autos_after_delete=$(run_appctl automation list --json)
auto_count_after_delete=$(json_query "$autos_after_delete" 'len((data.get("automations") or {}).get("items") or [])')
[ "$auto_count_after_delete" = "0" ] || fail "delete_automation did not clear automations"

preview_apply_operation delete_workspace --workspace-id "$secondary_workspace_id" >/dev/null
preview_apply_operation delete_workspace --workspace-id "$primary_workspace_id" >/dev/null
projects_after_delete=$(run_appctl project list --json)
workspace_count_after_delete=$(json_query "$projects_after_delete" 'len(data.get("workspaces") or [])')
[ "$workspace_count_after_delete" = "0" ] || fail "delete_workspace did not remove all workspaces"

printf '%s\n' "ok orchestrated operation coverage: preview/apply executed ensure/rename/delete workspace, ensure/archive thread, ensure/toggle/run/delete automation, and bootstrap stack"
