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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-capability-closure.XXXXXX")
assay_reports_dir="$tmp_root/assay-reports"
mkdir -p "$assay_reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cat > "$assay_reports_dir/20260402-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260402-candidate","family_count":6,"totals":{"overall_score":84.8,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":1,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"planning_architecture","score":76.0,"critical":true,"reason":"design-drift"}],"families":[{"id":"planning_architecture","score":76.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":82.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"research_integration","score":86.0,"critical":true,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260331-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260331-candidate","family_count":6,"totals":{"overall_score":82.6,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":1,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"planning_architecture","score":82.0,"critical":true,"reason":"design-drift"}],"families":[{"id":"planning_architecture","score":82.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":78.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"research_integration","score":84.0,"critical":true,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260329-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260329-candidate","family_count":6,"totals":{"overall_score":80.1,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":2,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"planning_architecture","score":88.0,"critical":true,"reason":"design-drift"},{"id":"coding_mutation","score":74.0,"critical":true,"reason":"score-below-threshold"}],"families":[{"id":"planning_architecture","score":88.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":74.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"research_integration","score":83.0,"critical":true,"gate_pass":true,"risk":"low"}]}
EOF_JSON

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
ARTIFICER_ASSAY_REPORTS_DIR="$assay_reports_dir" \
. "$self_improve_lib"

summary_json=$(self_improve_capability_benchmark_summary_cached_json)
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][0]["id"]')" = "planning_architecture" ] || fail "closure report should prioritize latest weak regressing family"
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][0]["trend_direction"]')" = "regressing" ] || fail "planning_architecture should be marked regressing"
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][0]["trend_scorecard_streak"]')" = "2" ] || fail "planning_architecture should carry sustained regressing streak"
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][0]["latest_weak"]')" = "true" ] || fail "planning_architecture should preserve latest weak status"
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][1]["id"]')" = "coding_mutation" ] || fail "coding_mutation should remain in internal closure report"
[ "$(json_query "$summary_json" 'data["internal_family_closure_report"][1]["trend_direction"]')" = "improving" ] || fail "coding_mutation should be improving over time"
[ "$(json_query "$summary_json" '",".join(data["regressing_internal_family_ids"])')" = "planning_architecture" ] || fail "regressing internal family ids should expose planning_architecture"
[ "$(json_query "$summary_json" '",".join(data["sustained_regressing_internal_family_ids"])')" = "planning_architecture" ] || fail "sustained regressing ids should expose planning_architecture"
[ "$(json_query "$summary_json" '",".join(data["improving_internal_family_ids"])')" = "coding_mutation,research_integration" ] || fail "improving family ids should include coding and research trajectories"

printf '%s\n' "ok capability benchmark internal closure report: recent scorecards produce family-level regressing/improving trajectories with sustained streaks and latest weak status"
