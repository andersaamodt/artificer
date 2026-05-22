#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
benchmark_script="$repo_root/hosted-web/scripts/capability-benchmark-cycle.sh"
manifest_path="$repo_root/hosted-web/tests/fixtures/artificer-capability-benchmark-manifest-v1.tsv"

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
value = eval(query, {"__builtins__": {"len": len, "sorted": sorted, "sum": sum, "min": min, "max": max}}, {"data": payload})
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

require_contains() {
  haystack=$1
  needle=$2
  label=$3
  if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "$label (missing: $needle)"
  fi
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-capability-benchmark.XXXXXX")
reports_dir="$tmp_root/reports"
mkdir -p "$reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

candidate_label="candidate-battery"
baseline_label="baseline-battery"

create_simple_report() {
  label=$1
  family=$2
  reg_rate=$3
  hold_rate=$4
  gates=$5
  risk=$6
  cat > "$reports_dir/$label-$family-transfer.json" <<EOF_JSON
{"label":"$label-$family","regressions_pass_rate":$reg_rate,"holdout_pass_rate":$hold_rate,"all_gates_pass":$gates,"transfer_risk":"$risk"}
EOF_JSON
}

create_broad_report() {
  label=$1
  family=$2
  overall=$3
  transfer=$4
  evidence=$5
  claim=$6
  gates=$7
  risk=$8
  overfit=$9
  cat > "$reports_dir/$label-$family-transfer.json" <<EOF_JSON
{"label":"$label-$family","all_gates_pass":$gates,"transfer_risk":"$risk","overfit_risk":$overfit,"holdout":{"avg_overall":$overall,"avg_transfer_readiness":$transfer,"avg_evidence":$evidence,"avg_claim_evidence_completeness":$claim},"battery":{"avg_overall":$overall,"avg_transfer_readiness":$transfer,"avg_evidence":$evidence,"avg_claim_evidence_completeness":$claim},"deltas":{"overall":0,"transfer_readiness":0,"evidence":0,"claim_evidence_completeness":0}}
EOF_JSON
}

create_rich_report() {
  label=$1
  family=$2
  overall=$3
  gates=$4
  risk=$5
  cat > "$reports_dir/$label-$family-transfer.json" <<EOF_JSON
{"label":"$label-$family","all_gates_pass":$gates,"transfer_risk":"$risk","holdout":{"avg_overall":$overall,"exact_contract_rate":0.92,"avg_required_ratio":0.95,"generic_fallback_rate":0.02},"battery":{"avg_overall":$overall},"deltas":{"overall":0}}
EOF_JSON
}

manifest_json=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" manifest)
[ "$(json_query "$manifest_json" 'data.get("family_count")')" = "6" ] || fail "manifest should contain six benchmark families"
require_contains "$manifest_json" "research_integration" "manifest should include research_integration"
require_contains "$manifest_json" "planning_architecture" "manifest should include planning_architecture"
require_contains "$manifest_json" "coding_mutation" "manifest should include coding_mutation"
require_contains "$manifest_json" "review_document" "manifest should include review_document"
require_contains "$manifest_json" "teaching_reassessment" "manifest should include teaching_reassessment"
require_contains "$manifest_json" "admin_env_repair" "manifest should include admin_env_repair"

plan_json=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" plan --label "$candidate_label")
[ "$(json_query "$plan_json" 'data.get("family_count")')" = "6" ] || fail "plan should cover every family"
require_contains "$plan_json" "repo-runtime-web-triage-cycle.sh" "plan should include research cycle"
require_contains "$plan_json" "broad-reasoning-cycle.sh" "plan should include planning cycle"
require_contains "$plan_json" "$candidate_label-research_integration-transfer.json" "plan should include expected transfer path"

create_simple_report "$candidate_label" "research_integration" "1.0" "0.875" "true" "low"
create_broad_report "$candidate_label" "planning_architecture" "84" "79" "95" "94" "true" "low" "false"
create_simple_report "$candidate_label" "coding_mutation" "1.0" "1.0" "true" "low"
create_broad_report "$candidate_label" "review_document" "81" "77" "94" "92" "true" "low" "false"
create_rich_report "$candidate_label" "teaching_reassessment" "86" "true" "low"
create_simple_report "$candidate_label" "admin_env_repair" "1.0" "0.75" "true" "low"

create_simple_report "$baseline_label" "research_integration" "0.5" "0.5" "false" "high"
create_broad_report "$baseline_label" "planning_architecture" "69" "60" "84" "82" "false" "high" "true"
create_simple_report "$baseline_label" "coding_mutation" "0.75" "0.5" "false" "medium"
create_broad_report "$baseline_label" "review_document" "72" "67" "88" "85" "true" "medium" "false"
create_rich_report "$baseline_label" "teaching_reassessment" "74" "true" "medium"
create_simple_report "$baseline_label" "admin_env_repair" "0.5" "0.25" "false" "high"

candidate_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" score --label "$candidate_label")
candidate_json=$(printf '%s\n' "$candidate_paths" | sed -n '1p')
candidate_md=$(printf '%s\n' "$candidate_paths" | sed -n '2p')
[ -f "$candidate_json" ] || fail "candidate scorecard json missing"
[ -f "$candidate_md" ] || fail "candidate scorecard markdown missing"
candidate_payload=$(cat "$candidate_json")

[ "$(json_query "$candidate_payload" 'data.get("family_count")')" = "6" ] || fail "candidate scorecard should include six families"
[ "$(json_query "$candidate_payload" 'data["totals"].get("coverage_ratio")')" = "1.0" ] || fail "candidate coverage should be complete"
[ "$(json_query "$candidate_payload" 'data["totals"].get("critical_failures")')" = "0" ] || fail "candidate should have no critical failures"
[ "$(json_query "$candidate_payload" 'data.get("recommendation")')" = "promote" ] || fail "candidate should be promotable"
[ "$(json_query "$candidate_payload" 'data["totals"].get("weak_family_count")')" = "0" ] || fail "candidate should not have weak families"
require_contains "$candidate_payload" "\"planning_architecture\"" "candidate scorecard should include planning family row"
require_contains "$candidate_payload" "\"teaching_reassessment\"" "candidate scorecard should include teaching family row"

baseline_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" score --label "$baseline_label")
baseline_json=$(printf '%s\n' "$baseline_paths" | sed -n '1p')
[ -f "$baseline_json" ] || fail "baseline scorecard json missing"
baseline_payload=$(cat "$baseline_json")

[ "$(json_query "$baseline_payload" 'data.get("recommendation")')" = "hold" ] || fail "baseline should be held"
[ "$(json_query "$baseline_payload" 'data["totals"].get("critical_failures")')" != "0" ] || fail "baseline should have critical failures"
require_contains "$baseline_payload" "\"research_integration\"" "baseline scorecard should include research family row"

compare_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" compare --baseline "$baseline_json" --candidate "$candidate_json" --label "candidate-vs-baseline")
compare_json=$(printf '%s\n' "$compare_paths" | sed -n '1p')
compare_md=$(printf '%s\n' "$compare_paths" | sed -n '2p')
[ -f "$compare_json" ] || fail "compare json missing"
[ -f "$compare_md" ] || fail "compare markdown missing"
compare_payload=$(cat "$compare_json")

[ "$(json_query "$compare_payload" 'data.get("candidate_promotable")')" = "true" ] || fail "candidate should be promotable against baseline"
[ "$(json_query "$compare_payload" 'data.get("recommendation")')" = "promote-candidate" ] || fail "compare recommendation should promote candidate"
[ "$(json_query "$compare_payload" 'data["deltas"].get("overall_score") > 0')" = "true" ] || fail "candidate overall score should exceed baseline"
require_contains "$compare_payload" "research_integration" "compare payload should mention recovered research family"

printf '%s\n' "ok capability benchmark cycle: manifest, plan, score, and compare produce promotable cross-domain capability scorecards"
