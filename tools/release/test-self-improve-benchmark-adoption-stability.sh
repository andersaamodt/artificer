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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-adoption-stability.XXXXXX")
plugins_dir="$tmp_root/plugins"
last_run_file="$tmp_root/last-run.json"
mkdir -p "$plugins_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
self_improve_plugins_dir="$plugins_dir" \
self_improve_last_run_file="$last_run_file" \
. "$self_improve_lib"

promote_evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[{"id":"planning_architecture","critical":true,"reason":"gate-failed"}],"latest_scorecard":{"recommendation":"promote","weak_families":[{"id":"planning_architecture","critical":true,"score":62.0,"reason":"gate-failed"}]},"latest_compare":{"recommendation":"promote-candidate","candidate_promotable":true,"recovered_families":["planning_architecture"],"improved_families":[{"id":"planning_architecture","score_delta":12.0}],"new_weak_families":[]},"scorecard_count":2,"compare_count":1}},"counts":{"failure_events":1,"quality_entries":9}}
EOF_JSON
)

hold_evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[{"id":"planning_architecture","critical":true,"reason":"gate-failed"}],"latest_scorecard":{"recommendation":"hold","weak_families":[{"id":"planning_architecture","critical":true,"score":58.0,"reason":"still-weak"}]},"latest_compare":{"recommendation":"hold","candidate_promotable":false,"recovered_families":[],"improved_families":[],"new_weak_families":["planning_architecture"]},"scorecard_count":3,"compare_count":2}},"counts":{"failure_events":2,"quality_entries":12}}
EOF_JSON
)

report_json=$(cat <<'EOF_JSON'
{"summary":"Track a single planning plugin over repeated compares.","winner_lane":"challenger","winner_model":"deepseek-coder:latest","plugins":[{"id":"planning-gate","name":"Planning Gate","description":"Tighten architecture planning.","instructions":"Require explicit architecture tradeoffs and contradiction checks.","implementation_plan":"Add a planning gate before execution.","rationale":"Planning is a current weak family.","domain_tags":["planning","architecture"],"benchmark_family_targets":["planning_architecture"],"targeted_capability_gaps":["planning_architecture"],"evidence_refs":["planning gap"],"admin_actions":[],"risk_level":"low","promotion_state":"priority"}]}
EOF_JSON
)

self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Stability gating","competition_enabled":true}' "$promote_evidence_json" "$report_json" >/dev/null
plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" 'len(data)')" = "1" ] || fail "first pass should write exactly one lineage record"
[ "$(json_query "$plugins_payload" 'data[0].get("adoption_state")')" = "trial" ] || fail "first promotable compare should keep plugin in trial"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_success_streak")')" = "1" ] || fail "first promotable compare should start success streak"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_compare_count")')" = "1" ] || fail "first promotable compare should increment compare count"

self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Stability gating","competition_enabled":true}' "$promote_evidence_json" "$report_json" >/dev/null
plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" 'len(data)')" = "1" ] || fail "same-lineage plugin should replace the prior record instead of accumulating duplicates"
[ "$(json_query "$plugins_payload" 'data[0].get("adoption_state")')" = "adopted" ] || fail "second consecutive promotable compare should adopt the plugin"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_success_streak")')" = "2" ] || fail "second consecutive promotable compare should advance success streak"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_promotable_hit_count")')" = "2" ] || fail "second consecutive promotable compare should advance promotable hit count"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_compare_count")')" = "2" ] || fail "second consecutive promotable compare should advance compare count"

self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Stability gating","competition_enabled":true}' "$hold_evidence_json" "$report_json" >/dev/null
plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" 'data[0].get("adoption_state")')" = "review" ] || fail "first failed compare after adoption should demote plugin to review"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_hold_streak")')" = "1" ] || fail "first failed compare should start hold streak"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_hold_count")')" = "1" ] || fail "first failed compare should increment hold count"

self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Stability gating","competition_enabled":true}' "$hold_evidence_json" "$report_json" >/dev/null
plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" 'data[0].get("adoption_state")')" = "rejected" ] || fail "second consecutive failed compare should reject the plugin"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_hold_streak")')" = "2" ] || fail "second consecutive failed compare should advance hold streak"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_compare_count")')" = "4" ] || fail "compare count should persist across promotable and failed compares"

printf '%s\n' "ok self-improve benchmark adoption stability: one lineage record persists history, requires two promotable compares to adopt, and rejects after two failed compares"
