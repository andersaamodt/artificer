#!/bin/sh
set -eu

label=""
manifest_path=""
out_json=""
out_md=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=${2-}
      shift 2
      ;;
    --manifest)
      manifest_path=${2-}
      shift 2
      ;;
    --out-json)
      out_json=${2-}
      shift 2
      ;;
    --out-md)
      out_md=${2-}
      shift 2
      ;;
    *)
      printf '%s\n' "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -n "$label" ] || {
  printf '%s\n' "missing --label" >&2
  exit 1
}
[ -n "$manifest_path" ] || {
  printf '%s\n' "missing --manifest" >&2
  exit 1
}
[ -n "$out_json" ] || {
  printf '%s\n' "missing --out-json" >&2
  exit 1
}
[ -n "$out_md" ] || {
  printf '%s\n' "missing --out-md" >&2
  exit 1
}

mkdir -p "$(dirname "$out_json")" "$(dirname "$out_md")"

cat > "$out_json" <<EOF_JSON
{
  "label": "$label",
  "generated_at": "2026-04-01T00:00:00Z",
  "manifest_path": "$manifest_path",
  "family_count": 6,
  "families": [
    {"id":"research_integration","name":"Research And Knowledge Integration","axis":"research","weight":1.0,"critical":true,"score":92.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"regressions_pass_rate":1.0,"holdout_pass_rate":0.95}},
    {"id":"planning_architecture","name":"Planning And Architecture","axis":"planning","weight":1.0,"critical":true,"score":91.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"avg_overall":91.0}},
    {"id":"coding_mutation","name":"Coding And Bounded Mutation","axis":"coding","weight":1.0,"critical":true,"score":90.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"regressions_pass_rate":1.0,"holdout_pass_rate":0.9}},
    {"id":"review_document","name":"Review And Document Quality","axis":"review","weight":1.0,"critical":false,"score":89.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"avg_overall":89.0}},
    {"id":"teaching_reassessment","name":"Teaching And Long-context Reassessment","axis":"teaching","weight":1.0,"critical":false,"score":93.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"avg_overall":93.0}},
    {"id":"admin_env_repair","name":"Admin Setup And Environment Repair","axis":"admin","weight":1.0,"critical":true,"score":88.0,"gate_pass":true,"risk":"low","weak_reason":"","metrics":{"regressions_pass_rate":1.0,"holdout_pass_rate":0.88}}
  ],
  "totals": {
    "overall_score": 90.5,
    "coverage_ratio": 1.0,
    "critical_failures": 0,
    "high_risk_family_count": 0,
    "weak_family_count": 0,
    "present_family_count": 6
  },
  "weak_families": [],
  "recommendation": "promote"
}
EOF_JSON

cat > "$out_md" <<EOF_MD
# Mock External Capability Scorecard: $label

- Manifest: $manifest_path
- Overall score: 90.5
- Recommendation: promote
EOF_MD
