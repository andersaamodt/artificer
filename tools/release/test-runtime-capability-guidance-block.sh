#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
self_improve_lib="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-runtime-capability-guidance.XXXXXX")
assay_reports_dir="$tmp_root/assay-reports"
mkdir -p "$assay_reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cat > "$assay_reports_dir/20260402-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260402-candidate","family_count":6,"totals":{"overall_score":84.2,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":3,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"coding_mutation","score":72.0,"critical":true,"reason":"score-below-threshold"},{"id":"planning_architecture","score":76.0,"critical":true,"reason":"design-drift"},{"id":"review_document","score":75.0,"critical":false,"reason":"evidence-surface"}],"families":[{"id":"planning_architecture","score":76.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":72.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"review_document","score":75.0,"critical":false,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260331-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260331-candidate","family_count":6,"totals":{"overall_score":82.8,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":2,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"planning_architecture","score":82.0,"critical":true,"reason":"design-drift"},{"id":"coding_mutation","score":70.0,"critical":true,"reason":"score-below-threshold"}],"families":[{"id":"planning_architecture","score":82.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":70.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"review_document","score":78.0,"critical":false,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260329-candidate-capability-benchmark-scorecard.json" <<'EOF_JSON'
{"label":"20260329-candidate","family_count":6,"totals":{"overall_score":80.1,"coverage_ratio":1.0,"critical_failures":0,"weak_family_count":2,"high_risk_family_count":0},"recommendation":"hold","weak_families":[{"id":"planning_architecture","score":88.0,"critical":true,"reason":"design-drift"},{"id":"coding_mutation","score":66.0,"critical":true,"reason":"score-below-threshold"}],"families":[{"id":"planning_architecture","score":88.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"coding_mutation","score":66.0,"critical":true,"gate_pass":true,"risk":"low"},{"id":"review_document","score":80.0,"critical":false,"gate_pass":true,"risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260402-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260402-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260402-frontier","candidate_label":"20260402-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-7.1,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-14.0,"candidate_score":75.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"},{"id":"teaching_reassessment","score_delta":-9.0,"candidate_score":79.0,"external_score":88.0,"candidate_critical":false,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260331-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260331-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260331-frontier","candidate_label":"20260331-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-6.0,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-12.0,"candidate_score":77.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"},{"id":"teaching_reassessment","score_delta":-11.0,"candidate_score":77.0,"external_score":88.0,"candidate_critical":false,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

cat > "$assay_reports_dir/20260329-candidate-vs-frontier-capability-benchmark-external-compare.json" <<'EOF_JSON'
{"label":"20260329-candidate-vs-frontier","external_baseline":{"name":"Frontier Reference","kind":"model","model":"gpt-5.4","notes":"reference workflow"},"external_label":"20260329-frontier","candidate_label":"20260329-candidate","recommendation":"external-still-ahead","candidate_beats_external":false,"deltas":{"overall_score":-4.8,"coverage_ratio":0.0,"critical_failures":0,"high_risk_family_count":0},"candidate_gap_families":[{"id":"research_integration","score_delta":-8.0,"candidate_score":81.0,"external_score":89.0,"candidate_critical":true,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"},{"id":"teaching_reassessment","score_delta":-13.0,"candidate_score":75.0,"external_score":88.0,"candidate_critical":false,"candidate_gate_pass":true,"candidate_weak_reason":"external-gap","external_risk":"low"}]}
EOF_JSON

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
ARTIFICER_ASSAY_REPORTS_DIR="$assay_reports_dir" \
. "$self_improve_lib"

programming_guidance=$(self_improve_capability_guidance_prompt_block "programming" "Fix the failing tests, refactor the code path, and keep the patch verifiable.")
printf '%s\n' "$programming_guidance" | grep -Fq "coding_mutation" || fail "programming guidance should prioritize coding mutation"
printf '%s\n' "$programming_guidance" | grep -Fq "planning_architecture" || fail "programming guidance should include planning architecture when it is a measured weak family"
printf '%s\n' "$programming_guidance" | grep -Fq "sustained regressing internal benchmark trend" || fail "programming guidance should preserve sustained regressing internal benchmark trend context"
if printf '%s\n' "$programming_guidance" | grep -Fq "teaching_reassessment"; then
  fail "programming guidance should not inject teaching reassessment for unrelated code work"
fi

teacher_guidance=$(self_improve_capability_guidance_prompt_block "teacher" "Explain how Ollama works so I can learn it deeply enough to contribute.")
printf '%s\n' "$teacher_guidance" | grep -Fq "teaching_reassessment" || fail "teacher guidance should prioritize teaching reassessment"
printf '%s\n' "$teacher_guidance" | grep -Fq "closing external-baseline gap with sustained recovery" || fail "teacher guidance should preserve closing persistent external-gap trend context"
if printf '%s\n' "$teacher_guidance" | grep -Fq "coding_mutation"; then
  fail "teacher guidance should not inject coding mutation for unrelated teaching work"
fi

report_guidance=$(self_improve_capability_guidance_prompt_block "report" "Search online, compare sources, and produce a sourced overview with links and quotes.")
printf '%s\n' "$report_guidance" | grep -Fq "research_integration" || fail "report guidance should prioritize research integration"
printf '%s\n' "$report_guidance" | grep -Fq "sustained worsening external-baseline gap" || fail "report guidance should preserve sustained worsening external-gap urgency"

instant_guidance=$(self_improve_capability_guidance_prompt_block "instant" "Say hi.")
[ "$instant_guidance" = "NONE" ] || fail "instant guidance should stay empty when no measured family is relevant"

printf '%s\n' "ok runtime capability guidance block: measured benchmark evidence becomes bounded task-relevant guidance for normal runs"
