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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-priority.XXXXXX")
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

empty_last_run_json=$(self_improve_last_run_json)
[ "$(json_query "$empty_last_run_json" 'data.get("capability_benchmark", {}).get("compare_recommendation", "__missing__")')" = "" ] || fail "default last-run payload should expose a structured capability benchmark object"
[ "$(json_query "$empty_last_run_json" 'data.get("capability_benchmark", {}).get("candidate_promotable")')" = "false" ] || fail "default last-run payload should expose compare promotion state defaults"

evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[{"id":"planning_architecture","critical":true,"reason":"gate-failed"},{"id":"coding_mutation","critical":true,"reason":"score-below-threshold"}],"latest_scorecard":{"recommendation":"hold","weak_families":[{"id":"planning_architecture","critical":true,"score":62.0,"reason":"gate-failed"},{"id":"coding_mutation","critical":true,"score":68.0,"reason":"score-below-threshold"}]}}},"counts":{"failure_events":2,"quality_entries":14,"proposal_items":0}}
EOF_JSON
)

primary_report_json=$(cat <<'EOF_JSON'
{"summary":"Primary proposed broad but generic plugins.","strategy":"Cover many domains lightly.","plugins":[{"id":"generic-research","name":"Generic Research Widening","description":"Broaden web and synthesis behavior.","instructions":"Search more sources before answering.","implementation_plan":"Add a broader web search pre-pass.","rationale":"Broader evidence may help sometimes.","domain_tags":["web-research","knowledge-integration"],"evidence_refs":["generic papers"],"admin_actions":[],"risk_level":"medium"}]}
EOF_JSON
)

challenger_report_json=$(cat <<'EOF_JSON'
{"summary":"Challenger focused on measured weak families.","strategy":"Target planning and coding gaps from the benchmark.","plugins":[{"id":"planning-gate","name":"Planning Gate Hardener","description":"Tighten architecture planning and contradiction checks.","instructions":"Before implementation, require explicit architecture decision checkpoints plus contradiction checks.","implementation_plan":"Add a planning gate that asks for architecture tradeoffs before execution.","rationale":"Current benchmark evidence shows planning/architecture is a critical weak family.","domain_tags":["planning","architecture"],"evidence_refs":["planning gap from capability benchmark"],"admin_actions":[],"risk_level":"low"},{"id":"mutation-verifier","name":"Mutation Verification Driver","description":"Strengthen bounded coding and verification loops.","instructions":"For coding tasks, require bounded mutation verification before finalization.","implementation_plan":"Route coding flows through a mutation-specific verification pass.","rationale":"Current benchmark evidence shows coding mutation is a critical weak family.","domain_tags":["programming","verification"],"evidence_refs":["coding gap from capability benchmark"],"admin_actions":["refresh mutation regression battery"],"risk_level":"low"}]}
EOF_JSON
)

compare_json=$(self_improve_compare_reports_json \
  "Improve benchmark-measured weak families" \
  "$evidence_json" \
  "$primary_report_json" \
  "$challenger_report_json" \
  "mistral:latest" \
  "deepseek-coder:latest" \
  "1")

[ "$(json_query "$compare_json" 'data.get("winner_lane")')" = "challenger" ] || fail "benchmark-guided comparison should prefer the challenger lane"
[ "$(json_query "$compare_json" 'data["lane_scores"]["challenger"] > data["lane_scores"]["artificer"]')" = "true" ] || fail "challenger score should exceed primary score"
[ "$(json_query "$compare_json" 'data["lanes"][1]["score"].get("critical_weak_gap_hits") >= 2')" = "true" ] || fail "challenger score should register critical weak-gap hits"
[ "$(json_query "$compare_json" 'data["plugins"][0]["promotion_state"]')" = "priority" ] || fail "top merged plugin should be benchmark priority"
[ "$(json_query "$compare_json" '"planning_architecture" in data["plugins"][0].get("benchmark_family_targets", []) or "coding_mutation" in data["plugins"][0].get("benchmark_family_targets", [])')" = "true" ] || fail "top merged plugin should target a benchmark family"
[ "$(json_query "$compare_json" 'data["plugins"][0].get("targeted_capability_gaps", []) != []')" = "true" ] || fail "top merged plugin should target active capability gaps"
[ "$(json_query "$compare_json" 'data.get("capability_benchmark_focus", {}).get("weak_family_ids", []) == ["coding_mutation","planning_architecture"] or data.get("capability_benchmark_focus", {}).get("weak_family_ids", []) == ["planning_architecture","coding_mutation"]')" = "true" ] || fail "compare result should carry capability benchmark weak-family focus"

store_json=$(self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Improve benchmark-measured weak families","competition_enabled":true}' "$evidence_json" "$compare_json")
[ -f "$last_run_file" ] || fail "last run file was not written"

plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$plugins_payload" 'len(data)')" = "3" ] || fail "expected three stored plugins"
[ "$(json_query "$plugins_payload" '[item.get("adoption_state") for item in data]')" = "[\"trial\",\"trial\",\"review\"]" ] || fail "plugins without compare evidence should stage weak-gap plugins as trials and leave the rest for review"
[ "$(json_query "$plugins_payload" '[item.get("promotion_state") for item in data]')" = "[\"priority\",\"priority\",\"candidate\"]" ] || fail "stored plugins should return priority-ranked plugins first"
[ "$(json_query "$plugins_payload" 'sorted([item.get("promotion_state") for item in data])')" = "[\"candidate\",\"priority\",\"priority\"]" ] || fail "stored plugins should preserve benchmark promotion states"
[ "$(json_query "$plugins_payload" 'sum(1 for item in data if item.get("enabled") is True)')" = "2" ] || fail "only trial plugins should auto-enable before compare evidence exists"
[ "$(json_query "$store_json" 'data.get("capability_benchmark", {}).get("latest_recommendation")')" = "hold" ] || fail "last-run payload should preserve capability benchmark recommendation"
[ "$(json_query "$store_json" 'len(data.get("capability_benchmark", {}).get("weak_family_ids", []))')" = "2" ] || fail "last-run payload should preserve weak family ids"

printf '%s\n' "ok self-improve benchmark prioritization: weak-family evidence changes lane scoring, merged plugin ranking, and stored promotion metadata"
