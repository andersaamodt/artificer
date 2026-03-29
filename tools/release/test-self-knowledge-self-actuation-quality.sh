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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-knowledge-quality.XXXXXX")
sites_root="$tmp_root/sites"
state_home="$tmp_root/state"
isolated_home="$tmp_root/home"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}
mkdir -p "$sites_root" "$state_home" "$isolated_home"

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

require_contains() {
  haystack=$1
  needle=$2
  label=$3
  if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "$label (missing: $needle)"
  fi
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

teach_json=$(run_appctl knowledge teach --topic self-actuation --json)
teach_topic=$(json_query "$teach_json" 'data.get("topic", "")')
[ "$teach_topic" = "self-actuation" ] || fail "knowledge teach returned unexpected topic"
learning_goals=$(json_query "$teach_json" 'data.get("learning_goals", "")')
misconceptions=$(json_query "$teach_json" 'data.get("common_misconceptions", "")')
assessment_checks=$(json_query "$teach_json" 'data.get("assessment_checks", "")')
practice_tasks=$(json_query "$teach_json" 'data.get("practice_tasks", "")')
teach_content=$(json_query "$teach_json" 'data.get("content", "")')
reference_paths_json=$(json_query "$teach_json" 'data.get("reference_paths", [])')

[ -n "$learning_goals" ] || fail "knowledge teach learning_goals is empty"
[ -n "$misconceptions" ] || fail "knowledge teach misconceptions is empty"
[ -n "$assessment_checks" ] || fail "knowledge teach assessment_checks is empty"
[ -n "$practice_tasks" ] || fail "knowledge teach practice_tasks is empty"
[ -n "$teach_content" ] || fail "knowledge teach content is empty"

require_contains "$teach_content" "self-actuation preview --operation" "teach content should explain orchestration preview"
require_contains "$teach_content" "self-actuation apply --operation" "teach content should explain orchestration apply"
require_contains "$teach_content" "policy-set" "teach content should explain policy control"
require_contains "$teach_content" "audit --limit" "teach content should explain audit review"
require_contains "$teach_content" "idempotency" "teach content should explain idempotent retries"
require_contains "$teach_content" "blocked by self-actuation policy" "teach content should explain blocked policy diagnosis"

require_contains "$learning_goals" "policy awareness" "learning goals should include policy awareness"
require_contains "$learning_goals" "idempotent retries" "learning goals should include idempotent retries"
require_contains "$assessment_checks" "confirm token" "assessment checks should cover confirm tokens"
require_contains "$assessment_checks" "blocked-policy" "assessment checks should cover policy troubleshooting"
require_contains "$practice_tasks" "ensure_workspace" "practice tasks should include orchestrated operation sequencing"
require_contains "$practice_tasks" "policy-set rollback" "practice tasks should include policy rollback"

require_contains "$reference_paths_json" "hosted-web/cgi/lib/runtime/40i-self-actuation.sh" "teach reference paths should include self-actuation runtime"
require_contains "$reference_paths_json" "hosted-web/cgi/actions/self_actuation_orchestrate.sh" "teach reference paths should include orchestrate action"

show_json=$(run_appctl knowledge show --topic self-actuation --json)
show_topic=$(json_query "$show_json" 'data.get("requested_topic", "")')
[ "$show_topic" = "self-actuation" ] || fail "knowledge show returned unexpected topic"
show_content=$(json_query "$show_json" 'data.get("selected_content", "")')
[ -n "$show_content" ] || fail "knowledge show selected_content is empty"
require_contains "$show_content" "Orchestrated operation map" "knowledge show should include operation map section"
require_contains "$show_content" "Failure diagnosis runbook" "knowledge show should include failure diagnosis runbook"

printf '%s\n' "ok self-knowledge quality: self-actuation teaching payload is complete, articulate, and includes orchestration/policy/audit guidance"
