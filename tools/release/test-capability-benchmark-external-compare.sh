#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
benchmark_script="$repo_root/hosted-web/scripts/capability-benchmark-cycle.sh"

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

require_contains() {
  haystack=$1
  needle=$2
  label=$3
  if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "$label (missing: $needle)"
  fi
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-capability-benchmark-external.XXXXXX")
reports_dir="$tmp_root/reports"
mkdir -p "$reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

candidate_label="candidate-battery"
external_label="external-battery"

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
{"label":"$label-$family","all_gates_pass":$gates,"transfer_risk":"$risk","holdout":{"avg_overall":$overall,"exact_contract_rate":0.90,"avg_required_ratio":0.94,"generic_fallback_rate":0.03},"battery":{"avg_overall":$overall},"deltas":{"overall":0}}
EOF_JSON
}

create_simple_report "$candidate_label" "research_integration" "1.0" "0.875" "true" "low"
create_broad_report "$candidate_label" "planning_architecture" "80" "76" "93" "92" "true" "low" "false"
create_simple_report "$candidate_label" "coding_mutation" "1.0" "0.875" "true" "low"
create_broad_report "$candidate_label" "review_document" "82" "78" "94" "93" "true" "low" "false"
create_rich_report "$candidate_label" "teaching_reassessment" "78" "true" "low"
create_simple_report "$candidate_label" "admin_env_repair" "1.0" "0.875" "true" "low"

create_simple_report "$external_label" "research_integration" "1.0" "1.0" "true" "low"
create_broad_report "$external_label" "planning_architecture" "92" "89" "97" "96" "true" "low" "false"
create_simple_report "$external_label" "coding_mutation" "1.0" "0.875" "true" "low"
create_broad_report "$external_label" "review_document" "83" "79" "94" "93" "true" "low" "false"
create_rich_report "$external_label" "teaching_reassessment" "91" "true" "low"
create_simple_report "$external_label" "admin_env_repair" "1.0" "0.875" "true" "low"

candidate_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" score --label "$candidate_label")
candidate_json=$(printf '%s\n' "$candidate_paths" | sed -n '1p')
external_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" score --label "$external_label")
external_json=$(printf '%s\n' "$external_paths" | sed -n '1p')

compare_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" external-compare \
  --external-baseline "$external_json" \
  --candidate "$candidate_json" \
  --external-name "Frontier Reference" \
  --external-kind "model" \
  --external-model "gpt-5.4" \
  --external-notes "reference workflow" \
  --label "candidate-vs-frontier")
compare_json=$(printf '%s\n' "$compare_paths" | sed -n '1p')
compare_md=$(printf '%s\n' "$compare_paths" | sed -n '2p')
[ -f "$compare_json" ] || fail "external compare json missing"
[ -f "$compare_md" ] || fail "external compare markdown missing"
compare_payload=$(cat "$compare_json")

[ "$(json_query "$compare_payload" 'data.get("external_baseline", {}).get("name")')" = "Frontier Reference" ] || fail "external compare should preserve baseline name"
[ "$(json_query "$compare_payload" 'data.get("external_baseline", {}).get("model")')" = "gpt-5.4" ] || fail "external compare should preserve baseline model"
[ "$(json_query "$compare_payload" 'data.get("candidate_beats_external")')" = "false" ] || fail "candidate should not beat stronger external baseline"
[ "$(json_query "$compare_payload" 'data.get("recommendation")')" = "external-still-ahead" ] || fail "recommendation should report external still ahead"
[ "$(json_query "$compare_payload" 'len(data.get("candidate_gap_families", [])) >= 2')" = "true" ] || fail "external compare should report candidate gap families"
[ "$(json_query "$compare_payload" '"planning_architecture" in [item.get("id") for item in data.get("candidate_gap_families", [])]')" = "true" ] || fail "external compare should report planning gap"
[ "$(json_query "$compare_payload" '"teaching_reassessment" in [item.get("id") for item in data.get("candidate_gap_families", [])]')" = "true" ] || fail "external compare should report teaching gap"
require_contains "$compare_payload" "\"score_delta\"" "external compare should include family score deltas"

printf '%s\n' "ok capability benchmark external compare: external baseline metadata, family gaps, and recommendation persist as first-class benchmark evidence"
