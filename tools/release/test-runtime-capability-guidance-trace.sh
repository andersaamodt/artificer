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
value = eval(query, {"__builtins__": {"len": len, "sorted": sorted}}, {"data": payload})
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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-runtime-capability-trace.XXXXXX")
assay_reports_dir="$tmp_root/assay-reports"
mkdir -p "$assay_reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cat > "$assay_reports_dir/20260402-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260402-candidate","family_count":6,"totals":{"overall_score":84.2,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":2,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"coding_mutation","score":72.0,"critical":true,"reason":"score-below-threshold"},{"id":"planning_architecture","score":76.0,"critical":true,"reason":"design-drift"}]}
EOF_JSON

cat > "$assay_reports_dir/20260402-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260402-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260402-frontier","candidate_label":"20260402-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-7.1,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-14.0,"candidate_score":75.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260331-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260331-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260331-frontier","candidate_label":"20260331-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-6.0,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-12.0,"candidate_score":77.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260329-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260329-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260329-frontier","candidate_label":"20260329-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-4.8,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-8.0,"candidate_score":81.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
ARTIFICER_ASSAY_REPORTS_DIR="$assay_reports_dir" \
. "$self_improve_lib"

guidance_block=$(self_improve_capability_guidance_prompt_block "programming" "Fix the failing tests, refactor the code path, and keep the patch verifiable.")
trace_json=$(self_improve_capability_guidance_trace_json_from_block "$guidance_block")

[ "$(json_query "$trace_json" 'data.get("count") >= 2')" = "true" ] || fail "guidance trace should record selected families"
[ "$(json_query "$trace_json" 'data["items"][0].get("id")')" = "coding_mutation" ] || fail "guidance trace should preserve first family id"
[ "$(json_query "$trace_json" '"measured weak family" in data["items"][0].get("reason", "")')" = "true" ] || fail "guidance trace should preserve measured weak-family reason"
[ "$(json_query "$trace_json" '"bounded verifiable slices" in data["items"][0].get("guidance", "")')" = "true" ] || fail "guidance trace should preserve operational guidance text"
[ "$(json_query "$trace_json" '"coding_mutation" in data.get("summary", "")')" = "true" ] || fail "guidance trace summary should mention selected family"

summary_text=$(self_improve_capability_guidance_trace_summary_text "$trace_json")
printf '%s\n' "$summary_text" | grep -Fq "coding_mutation" || fail "trace summary helper should echo selected family ids"

printf '%s\n' "ok runtime capability guidance trace: structured per-run trace preserves selected families, reasons, and guidance text"
