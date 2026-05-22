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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-actuation-e2e.XXXXXX")
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
import sys

payload = os.environ.get("JSON_PAYLOAD", "")
query = os.environ.get("JSON_QUERY", "")
data = json.loads(payload)
value = eval(query, {"__builtins__": {"len": len}}, {"data": data})
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

WEB_WIZARDRY_ROOT="$sites_root" \
WIZARDRY_SITES_DIR="$sites_root" \
XDG_STATE_HOME="$state_home" \
ARTIFICER_STATE_ROOT="$state_home/artificer" \
sh "$launcher" ensure-site >/dev/null

site_root="$sites_root/artificer"
api_path="$site_root/cgi/artificer-api"
[ -x "$api_path" ] || fail "missing staged API script: $api_path"

project_path="$projects_root/alpha"
mkdir -p "$project_path"

run_appctl project add --path "$project_path" --name "Alpha Project" >/dev/null

projects_json=$(run_appctl project list --json)
workspace_count=$(json_query "$projects_json" 'len(data.get("workspaces") or [])')
[ "$workspace_count" = "1" ] || fail "expected one workspace after project add"
workspace_id=$(json_query "$projects_json" '(data.get("workspaces") or [{}])[0].get("id", "")')
[ -n "$workspace_id" ] || fail "missing workspace id after project add"
workspace_name=$(json_query "$projects_json" '(data.get("workspaces") or [{}])[0].get("name", "")')
[ "$workspace_name" = "Alpha Project" ] || fail "unexpected workspace name after project add"

run_appctl project rename --workspace-id "$workspace_id" --name "Renamed Project" >/dev/null
projects_after_rename=$(run_appctl project list --json)
renamed_name=$(json_query "$projects_after_rename" '(data.get("workspaces") or [{}])[0].get("name", "")')
[ "$renamed_name" = "Renamed Project" ] || fail "project rename did not persist"

run_appctl thread new --workspace-id "$workspace_id" --title "Kickoff Thread" --model "mistral:latest" >/dev/null
threads_json=$(run_appctl thread list --workspace-id "$workspace_id" --json)
thread_count=$(json_query "$threads_json" 'len((data.get("workspaces") or [{}])[0].get("conversations") or [])')
[ "$thread_count" = "1" ] || fail "expected one thread after thread new"
conversation_id=$(json_query "$threads_json" '((data.get("workspaces") or [{}])[0].get("conversations") or [{}])[0].get("id", "")')
[ -n "$conversation_id" ] || fail "missing conversation id after thread new"

run_appctl automation upsert \
  --workspace-id "$workspace_id" \
  --conversation-id "$conversation_id" \
  --name "Nightly Check" \
  --prompt "summarize-status" \
  --schedule-kind "interval" \
  --schedule-value "900" \
  --enabled "1" \
  --allow-self-reschedule "1" \
  --run-mode "auto" \
  --compute-budget "quick" \
  --command-exec-mode "ask-some" \
  --permission-mode "workspace-write" \
  --programmer-review "1" \
  --programmer-review-rounds "2" >/dev/null

automations_json=$(run_appctl automation list --json)
automation_count=$(json_query "$automations_json" 'len((data.get("automations") or {}).get("items") or [])')
[ "$automation_count" = "1" ] || fail "expected one automation after upsert"
automation_id=$(json_query "$automations_json" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("id", "")')
[ -n "$automation_id" ] || fail "missing automation id after upsert"
automation_enabled=$(json_query "$automations_json" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("enabled", "")')
[ "$automation_enabled" = "1" ] || fail "automation should be enabled after create"

run_now_json=$(run_appctl automation run-now --automation-id "$automation_id")
run_now_success=$(json_query "$run_now_json" 'data.get("success", False)')
[ "$run_now_success" = "true" ] || fail "automation run-now did not return success"
run_item_id=$(json_query "$run_now_json" 'data.get("item_id", "")')
[ -n "$run_item_id" ] || fail "automation run-now missing queue item id"

run_appctl automation toggle --automation-id "$automation_id" --enabled "0" >/dev/null
automations_after_disable=$(run_appctl automation list --json)
enabled_after_disable=$(json_query "$automations_after_disable" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("enabled", "")')
[ "$enabled_after_disable" = "0" ] || fail "automation toggle off did not persist"

run_appctl automation toggle --automation-id "$automation_id" --enabled "1" >/dev/null
automations_after_enable=$(run_appctl automation list --json)
enabled_after_enable=$(json_query "$automations_after_enable" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("enabled", "")')
[ "$enabled_after_enable" = "1" ] || fail "automation toggle on did not persist"
next_run_after_enable=$(json_query "$automations_after_enable" '(((data.get("automations") or {}).get("items") or [{}])[0]).get("next_run", "0")')
case "$next_run_after_enable" in
  ''|*[!0-9]*)
    fail "automation next_run is not numeric after enable"
    ;;
esac
[ "$next_run_after_enable" -gt 0 ] || fail "automation next_run should be future epoch when enabled"

run_appctl thread archive --workspace-id "$workspace_id" --conversation-id "$conversation_id" >/dev/null
threads_after_archive=$(run_appctl thread list --workspace-id "$workspace_id" --json)
thread_count_after_archive=$(json_query "$threads_after_archive" 'len((data.get("workspaces") or [{}])[0].get("conversations") or [])')
[ "$thread_count_after_archive" = "0" ] || fail "thread archive did not remove active thread from workspace state"

run_appctl automation delete --automation-id "$automation_id" >/dev/null
automations_after_delete=$(run_appctl automation list --json)
automation_count_after_delete=$(json_query "$automations_after_delete" 'len((data.get("automations") or {}).get("items") or [])')
[ "$automation_count_after_delete" = "0" ] || fail "automation delete did not remove automation"

run_appctl project delete --workspace-id "$workspace_id" >/dev/null
projects_after_delete=$(run_appctl project list --json)
workspace_count_after_delete=$(json_query "$projects_after_delete" 'len(data.get("workspaces") or [])')
[ "$workspace_count_after_delete" = "0" ] || fail "project delete did not remove workspace"

printf '%s\n' "ok self-actuation e2e lifecycle: project/thread/automation create-list-mutate-verify-delete all succeed in isolated runtime"
