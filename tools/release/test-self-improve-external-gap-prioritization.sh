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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-external-priority.XXXXXX")
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

evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[],"external_gap_families":[{"id":"teaching_reassessment","critical":false,"score_delta":-12.0,"reason":"external-baseline-ahead"},{"id":"research_integration","critical":true,"score_delta":-9.0,"reason":"external-baseline-ahead"}],"persistent_external_gaps":[{"id":"research_integration","critical":true,"occurrence_count":3,"avg_score_delta":-10.0,"latest_score_delta":-12.0,"oldest_score_delta":-8.0,"trend_score_delta":-4.0,"close_rate_per_compare":-2.0,"trend_direction":"worsening","trend_compare_streak":2,"window_trend_direction":"worsening","trajectory_summary":"worsening for 2 compare cycles","reason":"persistent-external-baseline-gap"},{"id":"teaching_reassessment","critical":false,"occurrence_count":2,"avg_score_delta":-13.0,"latest_score_delta":-12.0,"oldest_score_delta":-14.0,"trend_score_delta":2.0,"close_rate_per_compare":2.0,"trend_direction":"closing","trend_compare_streak":2,"window_trend_direction":"closing","trajectory_summary":"closing for 2 compare cycles","reason":"persistent-external-baseline-gap"}],"worsening_persistent_external_gap_family_ids":["research_integration"],"closing_persistent_external_gap_family_ids":["teaching_reassessment"],"flat_persistent_external_gap_family_ids":[],"new_persistent_external_gap_family_ids":[],"sustained_worsening_persistent_external_gap_family_ids":["research_integration"],"sustained_flat_persistent_external_gap_family_ids":[],"sustained_closing_persistent_external_gap_family_ids":["teaching_reassessment"],"latest_scorecard":{"recommendation":"promote","weak_families":[]},"latest_external_compare":{"recommendation":"external-still-ahead","candidate_beats_external":false,"external_baseline":{"name":"Frontier Reference","model":"gpt-5.4"},"candidate_gap_families":[{"id":"teaching_reassessment","candidate_critical":false,"score_delta":-12.0},{"id":"research_integration","candidate_critical":true,"score_delta":-9.0}]}}},"counts":{"failure_events":1,"quality_entries":9,"proposal_items":0}}
EOF_JSON
)

primary_report_json=$(cat <<'EOF_JSON'
{"summary":"Primary proposed broad but generic plugins.","strategy":"Cover many domains lightly.","plugins":[{"id":"generic-admin","name":"Generic Admin Tuning","description":"Broaden setup reliability.","instructions":"Retry setup steps more aggressively.","implementation_plan":"Add more retries around setup work.","rationale":"Extra retries may help some environments.","domain_tags":["admin-setup"],"evidence_refs":["generic runtime evidence"],"admin_actions":[],"risk_level":"medium"}]}
EOF_JSON
)

challenger_report_json=$(cat <<'EOF_JSON'
{"summary":"Challenger targeted external benchmark gaps.","strategy":"Close the specific families where the external baseline still leads.","plugins":[{"id":"teaching-calibrator","name":"Teaching Calibration Pack","description":"Improve explanatory depth and reassessment quality.","instructions":"For teaching and long-context explanations, require explicit concept scaffolding, misconception checks, and end-of-answer reassessment.","implementation_plan":"Route teaching-style answers through a calibration pass that checks concept sequence, misconceptions, and reassessment coverage.","rationale":"The external benchmark still leads on teaching reassessment and this plugin targets that measured gap.","domain_tags":["knowledge-integration","verification"],"benchmark_family_targets":["teaching_reassessment"],"evidence_refs":["external benchmark teaching gap"],"admin_actions":[],"risk_level":"low"},{"id":"research-grounder","name":"Research Grounder","description":"Improve source-grounded retrieval and synthesis.","instructions":"For research tasks, require explicit source cross-checking and evidence-backed synthesis before final output.","implementation_plan":"Add a source-grounding pass to research workflows before final synthesis.","rationale":"The external benchmark still leads on research integration and this plugin targets that measured gap.","domain_tags":["web-research","knowledge-integration"],"benchmark_family_targets":["research_integration"],"evidence_refs":["external benchmark research gap"],"admin_actions":[],"risk_level":"low"}]}
EOF_JSON
)

compare_json=$(self_improve_compare_reports_json \
  "Improve measured gaps against an external baseline" \
  "$evidence_json" \
  "$primary_report_json" \
  "$challenger_report_json" \
  "mistral:latest" \
  "deepseek-coder:latest" \
  "1")

[ "$(json_query "$compare_json" 'data.get("winner_lane")')" = "challenger" ] || fail "external-gap-guided comparison should prefer the challenger lane"
[ "$(json_query "$compare_json" 'data["lane_scores"]["challenger"] > data["lane_scores"]["artificer"]')" = "true" ] || fail "challenger score should exceed primary score on external-gap evidence"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("critical_external_gap_hits") >= 1')" = "true" ] || fail "challenger score should register critical external-gap hits"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("critical_persistent_external_gap_hits") >= 1')" = "true" ] || fail "challenger score should register critical persistent external-gap hits"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("worsening_persistent_external_gap_hits") >= 1')" = "true" ] || fail "challenger score should prioritize worsening persistent external-gap hits"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("sustained_worsening_persistent_external_gap_hits") >= 1')" = "true" ] || fail "challenger score should prioritize sustained worsening persistent external-gap hits"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("closing_persistent_external_gap_hits") >= 1')" = "true" ] || fail "challenger score should retain visibility into closing persistent external-gap hits"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("promotion_state")')" = "priority" ] || fail "top merged plugin should be priority when it targets external gaps"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("targeted_external_capability_gaps", []) != []')" = "true" ] || fail "top merged plugin should record targeted external capability gaps"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("targeted_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "top merged plugin should record targeted persistent external capability gaps"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("targeted_worsening_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "top merged plugin should record worsening persistent external capability gaps"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("targeted_sustained_worsening_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "top merged plugin should record sustained worsening persistent external capability gaps"
[ "$(json_query "$compare_json" '"worsening" in [item.get("trend_direction") for item in data["plugins"][0].get("persistent_external_gap_trends", [])]')" = "true" ] || fail "top merged plugin should preserve persistent external gap trend metadata"
[ "$(json_query "$compare_json" '"worsening for 2 compare cycles" in [item.get("trajectory_summary") for item in data["plugins"][0].get("persistent_external_gap_trends", [])]')" = "true" ] || fail "top merged plugin should preserve persistent external gap trajectory summaries"
[ "$(json_query "$compare_json" '"research_integration" in data.get("capability_benchmark_focus", {}).get("external_gap_family_ids", [])')" = "true" ] || fail "compare result should carry external benchmark gap focus"
[ "$(json_query "$compare_json" '"research_integration" in data.get("capability_benchmark_focus", {}).get("persistent_external_gap_family_ids", [])')" = "true" ] || fail "compare result should carry persistent external benchmark gap focus"
[ "$(json_query "$compare_json" '"research_integration" in data.get("capability_benchmark_focus", {}).get("worsening_persistent_external_gap_family_ids", [])')" = "true" ] || fail "compare result should carry worsening persistent external benchmark gap focus"
[ "$(json_query "$compare_json" '"teaching_reassessment" in data.get("capability_benchmark_focus", {}).get("closing_persistent_external_gap_family_ids", [])')" = "true" ] || fail "compare result should carry closing persistent external benchmark gap focus"
[ "$(json_query "$compare_json" '"research_integration" in data.get("capability_benchmark_focus", {}).get("sustained_worsening_persistent_external_gap_family_ids", [])')" = "true" ] || fail "compare result should carry sustained worsening persistent external benchmark gap focus"

store_json=$(self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Improve measured gaps against an external baseline","competition_enabled":true}' "$evidence_json" "$compare_json")
plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" '[item.get("promotion_state") for item in data]')" = "[\"priority\",\"priority\",\"candidate\"]" ] || fail "stored plugins should keep external-gap-targeting plugins first"
[ "$(json_query "$plugins_payload" 'data[0].get("targeted_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "stored plugins should preserve persistent external gap targeting metadata"
[ "$(json_query "$plugins_payload" 'data[0].get("targeted_worsening_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "stored plugins should preserve worsening persistent external gap targeting metadata"
[ "$(json_query "$plugins_payload" 'data[0].get("targeted_sustained_worsening_persistent_external_capability_gaps", []) != []')" = "true" ] || fail "stored plugins should preserve sustained worsening persistent external gap targeting metadata"
[ "$(json_query "$store_json" 'data.get("capability_benchmark", {}).get("external_compare_recommendation")')" = "external-still-ahead" ] || fail "last-run payload should preserve external compare recommendation"
[ "$(json_query "$store_json" 'data.get("capability_benchmark", {}).get("external_baseline_name")')" = "Frontier Reference" ] || fail "last-run payload should preserve external baseline name"
[ "$(json_query "$store_json" '"research_integration" in data.get("capability_benchmark", {}).get("persistent_external_gap_family_ids", [])')" = "true" ] || fail "last-run payload should preserve persistent external gap ids"
[ "$(json_query "$store_json" '"research_integration" in data.get("capability_benchmark", {}).get("worsening_persistent_external_gap_family_ids", [])')" = "true" ] || fail "last-run payload should preserve worsening persistent external gap ids"
[ "$(json_query "$store_json" '"research_integration" in data.get("capability_benchmark", {}).get("sustained_worsening_persistent_external_gap_family_ids", [])')" = "true" ] || fail "last-run payload should preserve sustained worsening persistent external gap ids"

printf '%s\n' "ok self-improve external gap prioritization: external baseline gap trends change lane scoring, merged plugin priority, and stored benchmark metadata"
