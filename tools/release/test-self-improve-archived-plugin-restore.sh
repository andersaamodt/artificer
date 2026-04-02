#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
self_improve_lib="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

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
value = eval(query, {"__builtins__": {"len": len, "sorted": sorted, "sum": sum}}, {"data": payload})
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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-archived-restore.XXXXXX")
plugins_dir="$tmp_root/plugins"
archive_dir="$plugins_dir/archive"
last_run_file="$tmp_root/last-run.json"
llm_settings_dir="$tmp_root/llm"
self_improve_model_file="$llm_settings_dir/self-improve-model.txt"
self_improve_run_options_file="$llm_settings_dir/self-improve-run-options.json"
mkdir -p "$archive_dir" "$llm_settings_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

trim() {
  printf '%s' "$1" | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); printf "%s", $0}'
}

read_file_line() {
  file_path=$1
  default_value=${2-}
  if [ -f "$file_path" ]; then
    sed -n '1p' "$file_path"
  else
    printf '%s' "$default_value"
  fi
}

json_escape() {
  JSON_ESCAPE_VALUE=${1-} python3 - <<'PY'
import json
import os
print(json.dumps(os.environ.get("JSON_ESCAPE_VALUE", ""))[1:-1])
PY
}

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
self_improve_model_file="$self_improve_model_file" \
self_improve_run_options_file="$self_improve_run_options_file" \
self_improve_llm_settings_dir="$llm_settings_dir" \
llm_settings_dir="$llm_settings_dir" \
self_improve_plugins_dir="$plugins_dir" \
self_improve_last_run_file="$last_run_file" \
. "$self_improve_lib"

cat >"$last_run_file" <<'EOF_JSON'
{
  "summary": "Restore archived plugins.",
  "generated_at": "2026-04-01T12:00:00Z",
  "model": "mistral:latest",
  "capability_benchmark": {
    "compare_count": 7
  }
}
EOF_JSON

cat >"$archive_dir/archived-planning.json" <<'EOF_JSON'
{
  "id": "2026-03-30-planning-gate",
  "name": "Planning Gate",
  "description": "Tighten architecture planning.",
  "instructions": "Require explicit architecture tradeoffs and contradiction checks.",
  "implementation_plan": "Add a planning gate before execution.",
  "rationale": "Planning is a weak family.",
  "lineage_key": "planning-gate",
  "generated_at": "2026-03-30T00:00:00Z",
  "enabled": false,
  "adoption_state": "review",
  "automatic_adoption_state": "review",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["planning_architecture"],
  "targeted_capability_gaps": ["planning_architecture"],
  "archived_at": "2026-04-01T00:00:00Z",
  "archived_via": "stale-benchmark-prune",
  "archived_from_state": "review",
  "archived_after_compare_cycles": 3,
  "archived_reason": "Automatic archive after 3 later benchmark compare cycles left this review plugin stale without operator intervention."
}
EOF_JSON

archived_payload=$(self_improve_archived_plugins_json)
[ "$(json_query "$archived_payload" 'len(data)')" = "1" ] || fail "archived plugin list should expose archive entries"
[ "$(json_query "$archived_payload" 'data[0].get("archive_entry_id")')" = "archived-planning" ] || fail "archive entry id should come from archive filename"
[ "$(json_query "$archived_payload" 'data[0].get("archived_from_state")')" = "review" ] || fail "archive list should preserve archived-from state"

restore_json=$(self_improve_archived_plugin_restore_json "archived-planning")
[ "$(json_query "$restore_json" 'data.get("success")')" = "true" ] || fail "restore action should succeed for non-conflicting lineage"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("adoption_state")')" = "review" ] || fail "restored plugin should re-enter review state"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("operator_policy")')" = "force-review" ] || fail "restored plugin should come back under forced review"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("operator_lock")')" = "true" ] || fail "restored plugin should lock the forced review state"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("enabled")')" = "false" ] || fail "restored plugin should stay disabled until manually reconsidered"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("last_benchmark_compare_count")')" = "7" ] || fail "restored plugin should reset stale age against current compare count"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("stale_compare_cycles")')" = "0" ] || fail "restored plugin should clear stale compare-cycle age"
[ "$(json_query "$restore_json" 'data.get("plugin", {}).get("restored_from_archive_entry_id")')" = "archived-planning" ] || fail "restored plugin should record archive provenance"

plugins_payload=$(self_improve_plugins_json)
inventory_payload=$(self_improve_plugin_inventory_json)
settings_payload=$(self_improve_settings_json)
[ "$(json_query "$plugins_payload" 'len(data)')" = "1" ] || fail "restored plugin should reappear in active plugins"
[ "$(json_query "$inventory_payload" 'data.get("active_count")')" = "1" ] || fail "inventory should count restored active plugin"
[ "$(json_query "$inventory_payload" 'data.get("archived_count")')" = "0" ] || fail "inventory should remove restored archive entry"
[ "$(json_query "$settings_payload" 'len(data.get("archived_plugins") or [])')" = "0" ] || fail "settings payload should show archive emptied after restore"

cat >"$archive_dir/archived-planning-again.json" <<'EOF_JSON'
{
  "id": "2026-03-31-planning-gate",
  "name": "Planning Gate Again",
  "lineage_key": "planning-gate",
  "generated_at": "2026-03-31T00:00:00Z",
  "enabled": false,
  "adoption_state": "rejected",
  "automatic_adoption_state": "rejected",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["planning_architecture"],
  "archived_at": "2026-04-01T01:00:00Z",
  "archived_via": "stale-benchmark-prune",
  "archived_from_state": "rejected",
  "archived_after_compare_cycles": 2,
  "archived_reason": "Automatic archive after 2 later benchmark compare cycles left this rejected plugin stale without operator intervention."
}
EOF_JSON

blocked_json=$(self_improve_archived_plugin_restore_json "archived-planning-again")
[ "$(json_query "$blocked_json" 'data.get("success")')" = "false" ] || fail "restore should fail when the lineage is already active"
[ "$(json_query "$blocked_json" 'data.get("error")')" = "an active plugin with this lineage already exists" ] || fail "restore failure should explain the active-lineage conflict"

cat >"$archive_dir/archived-review-pack.json" <<'EOF_JSON'
{
  "id": "2026-03-29-review-pack",
  "name": "Review Pack",
  "lineage_key": "review-pack",
  "generated_at": "2026-03-29T00:00:00Z",
  "enabled": false,
  "adoption_state": "review",
  "automatic_adoption_state": "review",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["review_document"],
  "archived_at": "2026-04-01T02:00:00Z",
  "archived_via": "stale-benchmark-prune",
  "archived_from_state": "review",
  "archived_after_compare_cycles": 3,
  "archived_reason": "Automatic archive after 3 later benchmark compare cycles left this review plugin stale without operator intervention."
}
EOF_JSON

delete_json=$(self_improve_archived_plugin_delete_json "archived-review-pack")
[ "$(json_query "$delete_json" 'data.get("success")')" = "true" ] || fail "archived delete should succeed"
[ ! -f "$archive_dir/archived-review-pack.json" ] || fail "archived delete should remove the archive file"

printf '%s\n' "ok self-improve archived plugin restore: archive list is visible, restore reintroduces a plugin in locked review with stale age reset, duplicate lineage restore is blocked, and archive delete works"
