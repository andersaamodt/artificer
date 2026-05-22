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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-actuation-orchestrate.XXXXXX")
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

run_appctl_expect_fail() {
  if run_appctl "$@" >/dev/null 2>&1; then
    fail "expected command to fail but it succeeded: $*"
  fi
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
workspace_id=$(json_query "$projects_json" '(data.get("workspaces") or [{}])[0].get("id", "")')
[ -n "$workspace_id" ] || fail "missing workspace id after project add"

preview_json=$(run_appctl self-actuation preview \
  --operation rename_workspace \
  --workspace-id "$workspace_id" \
  --name "Renamed Via Orchestrate" \
  --json)
preview_mode=$(json_query "$preview_json" 'data.get("mode", "")')
[ "$preview_mode" = "preview" ] || fail "expected preview mode"
confirm_token=$(json_query "$preview_json" 'data.get("confirm_token", "")')
[ -n "$confirm_token" ] || fail "preview did not return confirm_token"

policy_block_json=$(run_appctl self-actuation policy-set \
  --workspace-id "$workspace_id" \
  --action rename_workspace \
  --enabled 0 \
  --json)
policy_block_enabled=$(json_query "$policy_block_json" 'data.get("enabled", "")')
[ "$policy_block_enabled" = "0" ] || fail "policy-set did not disable operation"

run_appctl_expect_fail self-actuation apply \
  --operation rename_workspace \
  --workspace-id "$workspace_id" \
  --name "Renamed Via Orchestrate" \
  --confirm-token "$confirm_token" \
  --json

policy_allow_json=$(run_appctl self-actuation policy-set \
  --workspace-id "$workspace_id" \
  --action rename_workspace \
  --enabled 1 \
  --json)
policy_allow_enabled=$(json_query "$policy_allow_json" 'data.get("enabled", "")')
[ "$policy_allow_enabled" = "1" ] || fail "policy-set did not re-enable operation"

run_appctl_expect_fail self-actuation apply \
  --operation rename_workspace \
  --workspace-id "$workspace_id" \
  --name "Renamed Via Orchestrate" \
  --confirm-token "wrong-token" \
  --json

idem_key="rename-${workspace_id}"
apply_json=$(run_appctl self-actuation apply \
  --operation rename_workspace \
  --workspace-id "$workspace_id" \
  --name "Renamed Via Orchestrate" \
  --confirm-token "$confirm_token" \
  --idempotency-key "$idem_key" \
  --json)
apply_success=$(json_query "$apply_json" 'data.get("success", False)')
[ "$apply_success" = "true" ] || fail "apply did not succeed after policy allow"
apply_hit=$(json_query "$apply_json" 'data.get("idempotent_hit", "")')
[ "$apply_hit" = "0" ] || fail "first apply should not be idempotent replay"

apply_replay_json=$(run_appctl self-actuation apply \
  --operation rename_workspace \
  --workspace-id "$workspace_id" \
  --name "Renamed Via Orchestrate" \
  --confirm-token "$confirm_token" \
  --idempotency-key "$idem_key" \
  --json)
apply_replay_hit=$(json_query "$apply_replay_json" 'data.get("idempotent_hit", "")')
[ "$apply_replay_hit" = "1" ] || fail "second apply with same idempotency key should replay cached result"

projects_after_json=$(run_appctl project list --json)
workspace_name=$(json_query "$projects_after_json" '(data.get("workspaces") or [{}])[0].get("name", "")')
[ "$workspace_name" = "Renamed Via Orchestrate" ] || fail "rename_workspace apply did not persist workspace name"

policy_get_json=$(run_appctl self-actuation policy-get \
  --workspace-id "$workspace_id" \
  --action rename_workspace \
  --json)
policy_get_enabled=$(json_query "$policy_get_json" 'data.get("enabled", "")')
[ "$policy_get_enabled" = "1" ] || fail "policy-get returned unexpected enabled value"

audit_json=$(run_appctl self-actuation audit --limit 200 --json)
audit_count=$(json_query "$audit_json" 'len(data.get("entries") or [])')
[ "$audit_count" -ge 1 ] || fail "audit should include at least one event"
has_policy_set=$(json_query "$audit_json" 'any((entry.get("event") == "policy-set") for entry in (data.get("entries") or []))')
[ "$has_policy_set" = "true" ] || fail "audit missing policy-set entries"
has_orchestrate=$(json_query "$audit_json" 'any((entry.get("event") == "orchestrate" and entry.get("action") == "rename_workspace") for entry in (data.get("entries") or []))')
[ "$has_orchestrate" = "true" ] || fail "audit missing orchestrate rename_workspace entries"

run_appctl project delete --workspace-id "$workspace_id" >/dev/null

printf '%s\n' "ok self-actuation orchestration/policy/audit: preview+confirm, policy guardrails, idempotent apply replay, and audit trail are validated"
