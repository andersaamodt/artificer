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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-external-benchmark.XXXXXX")
assay_reports_dir="$tmp_root/assay-reports"
mode_runtime_root="$tmp_root/mode-runtime"
mkdir -p "$assay_reports_dir" "$mode_runtime_root"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cat > "$assay_reports_dir/20260401-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260401-candidate","family_count":6,"totals":{"overall_score":88.4,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":1,"high_risk_family_count":0},"recommendation":"promote","weak_families":[{"id":"teaching_reassessment","score":74.0}],"families":[{"id":"planning_architecture","score":90.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"teaching_reassessment","score":74.0,"critical":false,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260401-candidate-vs-baseline-capability-benchmark-compare.json" <<'EOF_JSON'
{"label":"20260401-candidate-vs-baseline","baseline_label":"20260328-baseline","candidate_label":"20260401-candidate","recommendation":"promote-candidate","candidate_promotable":true,"deltas":{"overall_score":12.5,"coverage_ratio":0.0},"recovered_families":["planning_architecture","research_integration"],"new_weak_families":[]}
EOF_JSON

cat > "$assay_reports_dir/20260401-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260401-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260401-frontier","candidate_label":"20260401-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-6.4,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"teaching_reassessment","score_delta":-14.0,"candidate_score":74.0,"external_score":88.0,"candidate_critical":false,"candidate_gate_pass":true,"candidate_weak_reason":"score-below-threshold","external_risk":"low"}],"candidate_lead_families":[{"id":"planning_architecture","score_delta":2.0,"candidate_score":90.0,"external_score":88.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"","external_risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260330-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260330-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260330-frontier","candidate_label":"20260330-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-8.1,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"teaching_reassessment","score_delta":-16.0,"candidate_score":72.0,"external_score":88.0,"candidate_critical":false,"candidate_gate_pass":true,"candidate_weak_reason":"score-below-threshold","external_risk":"low"},{"id":"research_integration","score_delta":-9.0,"candidate_score":80.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}],"candidate_lead_families":[]}
EOF_JSON

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
ARTIFICER_ASSAY_REPORTS_DIR="$assay_reports_dir" \
mode_runtime_lib_loaded=0 \
mode_runtime_root="$mode_runtime_root" \
self_improve_plugins_dir="$tmp_root/plugins" \
self_improve_last_run_file="$tmp_root/self-improve-last-run.json" \
. "$self_improve_lib"

kv_get() {
  key=$1
  text=$2
  printf '%s\n' "$text" | awk -F '=' -v target="$key" '$1 == target { print $2; exit }'
}

runtime_json=$(self_improve_runtime_signals_json)
[ "$(json_query "$runtime_json" 'data["capability_benchmark"]["latest_external_compare"].get("external_baseline", {}).get("name")')" = "Frontier Reference" ] || fail "runtime signals should expose latest external baseline compare"
[ "$(json_query "$runtime_json" 'data["capability_benchmark"]["latest_external_compare"].get("recommendation")')" = "external-still-ahead" ] || fail "runtime signals should expose external compare recommendation"
[ "$(json_query "$runtime_json" 'data["capability_benchmark"]["external_gap_families"][0].get("id")')" = "teaching_reassessment" ] || fail "runtime signals should expose external gap families"
[ "$(json_query "$runtime_json" 'data["capability_benchmark"]["persistent_external_gaps"][0].get("id")')" = "teaching_reassessment" ] || fail "runtime signals should expose persistent external gaps"
[ "$(json_query "$runtime_json" 'data["capability_benchmark"]["persistent_external_gaps"][0].get("occurrence_count")')" = "2" ] || fail "persistent external gaps should aggregate repeated family misses"
[ "$(json_query "$runtime_json" 'data["counts"].get("capability_benchmark_external_compares")')" = "2" ] || fail "runtime counts should include external benchmark comparisons"

evidence_json=$(self_improve_build_evidence_bundle_json '{"objective":"Improve measured capability against an external reference","sources":{"runtime":true,"papers":false,"web":false,"repo":false,"platform":false}}')
[ "$(json_query "$evidence_json" 'data["runtime_signals"]["capability_benchmark"]["latest_external_compare"].get("external_baseline", {}).get("model")')" = "gpt-5.4" ] || fail "evidence bundle should carry external baseline metadata"
[ "$(json_query "$evidence_json" 'data["runtime_signals"]["capability_benchmark"]["persistent_external_gaps"][1].get("id")')" = "research_integration" ] || fail "evidence bundle should carry persistent external gap ranking"
[ "$(json_query "$evidence_json" 'data["counts"].get("capability_benchmark_external_compares")')" = "2" ] || fail "evidence bundle counts should include external benchmark comparisons"

printf '%s\n' "ok self-improve runtime external capability benchmark: runtime signals and evidence bundle expose external baseline compares and gap families"
