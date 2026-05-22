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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-stale-pruning.XXXXXX")
plugins_dir="$tmp_root/plugins"
last_run_file="$tmp_root/last-run.json"
llm_settings_dir="$tmp_root/llm"
self_improve_model_file="$llm_settings_dir/self-improve-model.txt"
self_improve_run_options_file="$llm_settings_dir/self-improve-run-options.json"
mkdir -p "$plugins_dir"
mkdir -p "$llm_settings_dir"

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

cat >"$plugins_dir/review-stale.json" <<'EOF_JSON'
{
  "id": "review-stale",
  "name": "Review Stale",
  "lineage_key": "review-stale",
  "generated_at": "2026-04-01T00:00:00Z",
  "enabled": false,
  "adoption_state": "review",
  "automatic_adoption_state": "review",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["review_document"],
  "last_benchmark_compare_count": 1,
  "stale_compare_cycles": 0
}
EOF_JSON

cat >"$plugins_dir/rejected-stale.json" <<'EOF_JSON'
{
  "id": "rejected-stale",
  "name": "Rejected Stale",
  "lineage_key": "rejected-stale",
  "generated_at": "2026-04-01T00:00:00Z",
  "enabled": false,
  "adoption_state": "rejected",
  "automatic_adoption_state": "rejected",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["planning_architecture"],
  "last_benchmark_compare_count": 2,
  "stale_compare_cycles": 0
}
EOF_JSON

cat >"$plugins_dir/rejected-locked.json" <<'EOF_JSON'
{
  "id": "rejected-locked",
  "name": "Rejected Locked",
  "lineage_key": "rejected-locked",
  "generated_at": "2026-04-01T00:00:00Z",
  "enabled": false,
  "adoption_state": "rejected",
  "automatic_adoption_state": "review",
  "operator_policy": "force-rejected",
  "operator_lock": true,
  "benchmark_family_targets": ["planning_architecture"],
  "last_benchmark_compare_count": 1,
  "stale_compare_cycles": 0
}
EOF_JSON

cat >"$plugins_dir/adopted-active.json" <<'EOF_JSON'
{
  "id": "adopted-active",
  "name": "Adopted Active",
  "lineage_key": "adopted-active",
  "generated_at": "2026-04-01T00:00:00Z",
  "enabled": true,
  "adoption_state": "adopted",
  "automatic_adoption_state": "adopted",
  "operator_policy": "auto",
  "operator_lock": false,
  "benchmark_family_targets": ["coding_mutation"],
  "last_benchmark_compare_count": 1,
  "stale_compare_cycles": 0
}
EOF_JSON

evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"latest_scorecard":{"recommendation":"hold"},"latest_compare":{"recommendation":"hold","candidate_promotable":false,"recovered_families":[],"improved_families":[],"new_weak_families":[]},"scorecard_count":4,"compare_count":4}},"counts":{"failure_events":1,"quality_entries":3}}
EOF_JSON
)

report_json=$(cat <<'EOF_JSON'
{"summary":"Prune stale plugins.","winner_lane":"artificer","winner_model":"mistral:latest","plugins":[]}
EOF_JSON
)

store_json=$(self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Prune stale plugins","competition_enabled":true}' "$evidence_json" "$report_json")
plugins_payload=$(self_improve_plugins_json)
inventory_payload=$(self_improve_plugin_inventory_json)
settings_payload=$(self_improve_settings_json)

[ "$(json_query "$plugins_payload" 'len(data)')" = "2" ] || fail "stale auto-managed review/rejected plugins should be removed from the active set"
[ "$(json_query "$plugins_payload" '[item.get("id") for item in data]')" = "[\"adopted-active\",\"rejected-locked\"]" ] || fail "only adopted and operator-managed plugins should remain active after stale pruning"
[ "$(json_query "$inventory_payload" 'data.get("active_count")')" = "2" ] || fail "inventory should report the remaining active plugins"
[ "$(json_query "$inventory_payload" 'data.get("archived_count")')" = "2" ] || fail "inventory should count archived plugins"
[ "$(json_query "$inventory_payload" 'data.get("archived_auto_stale_count")')" = "2" ] || fail "inventory should count stale auto-archived plugins"
[ "$(json_query "$store_json" 'data.get("archived_plugin_ids")')" = "[\"rejected-stale\",\"review-stale\"]" ] || fail "last-run report should record which stale plugins were archived"
[ "$(json_query "$settings_payload" 'data.get("plugin_inventory", {}).get("archived_auto_stale_count")')" = "2" ] || fail "settings payload should surface archived stale-plugin inventory"

archive_review="$plugins_dir/archive/review-stale.json"
archive_rejected="$plugins_dir/archive/rejected-stale.json"
[ -f "$archive_review" ] || fail "review plugin should be moved into archive storage"
[ -f "$archive_rejected" ] || fail "rejected plugin should be moved into archive storage"

review_archive_json=$(cat "$archive_review")
rejected_archive_json=$(cat "$archive_rejected")
[ "$(json_query "$review_archive_json" 'data.get("archived_via")')" = "stale-benchmark-prune" ] || fail "review archive should record stale-prune origin"
[ "$(json_query "$review_archive_json" 'data.get("archived_from_state")')" = "review" ] || fail "review archive should preserve prior adoption state"
[ "$(json_query "$review_archive_json" 'data.get("archived_after_compare_cycles")')" = "3" ] || fail "review archive should report compare-cycle age"
[ "$(json_query "$rejected_archive_json" 'data.get("archived_from_state")')" = "rejected" ] || fail "rejected archive should preserve prior adoption state"
[ "$(json_query "$rejected_archive_json" 'data.get("archived_after_compare_cycles")')" = "2" ] || fail "rejected archive should report compare-cycle age"

printf '%s\n' "ok self-improve stale plugin pruning: stale auto-managed review/rejected plugins archive by compare-cycle age while adopted and operator-managed plugins remain active"
