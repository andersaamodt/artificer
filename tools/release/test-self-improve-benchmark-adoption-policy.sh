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

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-improve-adoption.XXXXXX")
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
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[{"id":"planning_architecture","critical":true,"reason":"gate-failed"},{"id":"admin_env_repair","critical":true,"reason":"missing-report"}],"latest_scorecard":{"recommendation":"promote","weak_families":[{"id":"planning_architecture","critical":true,"score":62.0,"reason":"gate-failed"},{"id":"admin_env_repair","critical":true,"score":58.0,"reason":"missing-report"}]},"latest_compare":{"recommendation":"promote-candidate","candidate_promotable":true,"recovered_families":["planning_architecture"],"improved_families":[{"id":"planning_architecture","score_delta":12.0},{"id":"coding_mutation","score_delta":4.0}],"new_weak_families":["review_document"]},"scorecard_count":2,"compare_count":1}},"counts":{"failure_events":1,"quality_entries":9}}
EOF_JSON
)

report_json=$(cat <<'EOF_JSON'
{"summary":"Auto-adoption policy exercise.","winner_lane":"challenger","winner_model":"deepseek-coder:latest","plugins":[{"id":"planning-gate","name":"Planning Gate","description":"Tighten architecture planning.","instructions":"Require explicit architecture tradeoffs and contradiction checks.","implementation_plan":"Add a planning gate before execution.","rationale":"Planning is a current weak family.","domain_tags":["planning","architecture"],"benchmark_family_targets":["planning_architecture"],"targeted_capability_gaps":["planning_architecture"],"evidence_refs":["planning gap"],"admin_actions":[],"risk_level":"low","promotion_state":"priority"},{"id":"mutation-driver","name":"Mutation Driver","description":"Strengthen bounded coding verification.","instructions":"Run mutation-specific verification before finalize.","implementation_plan":"Route coding flows through a mutation verifier.","rationale":"Coding quality improved in the latest compare.","domain_tags":["programming","verification"],"benchmark_family_targets":["coding_mutation"],"targeted_capability_gaps":[],"evidence_refs":["coding compare"],"admin_actions":[],"risk_level":"low","promotion_state":"candidate"},{"id":"admin-driver","name":"Admin Driver","description":"Improve environment repair behavior.","instructions":"Add environment repair probes before retries.","implementation_plan":"Run repair-specific checks on setup failures.","rationale":"Admin setup remains a live weak family.","domain_tags":["admin-setup"],"benchmark_family_targets":["admin_env_repair"],"targeted_capability_gaps":["admin_env_repair"],"evidence_refs":["admin weak family"],"admin_actions":["refresh install probe"],"risk_level":"low","promotion_state":"priority"},{"id":"research-pack","name":"Research Pack","description":"Improve retrieval breadth.","instructions":"Gather a tighter retrieval pack before synthesis.","implementation_plan":"Add retrieval-pack construction before answer synthesis.","rationale":"Maps to research but has no compare proof yet.","domain_tags":["web-research","knowledge-integration"],"benchmark_family_targets":["research_integration"],"targeted_capability_gaps":[],"evidence_refs":["research mapping"],"admin_actions":[],"risk_level":"medium","promotion_state":"candidate"},{"id":"review-pack","name":"Review Pack","description":"Improve document review.","instructions":"Require review checklists before shipping docs.","implementation_plan":"Insert review checklist pass.","rationale":"Review is still weak in the latest compare.","domain_tags":["verification"],"benchmark_family_targets":["review_document"],"targeted_capability_gaps":[],"evidence_refs":["review weak family"],"admin_actions":[],"risk_level":"medium","promotion_state":"candidate"}]}
EOF_JSON
)

store_json=$(self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Benchmark-gated adoption","competition_enabled":true}' "$promote_evidence_json" "$report_json")
plugins_payload=$(self_improve_plugins_json)

[ "$(json_query "$plugins_payload" '[item.get("adoption_state") for item in data]')" = "[\"trial\",\"trial\",\"trial\",\"review\",\"review\"]" ] || fail "first measured compare should stage promising plugins as trial/review instead of immediately locking them in"
[ "$(json_query "$plugins_payload" 'sum(1 for item in data if item.get("enabled") is True)')" = "3" ] || fail "adopted and trial plugins should auto-enable"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_recovered_family_hits")')" = "[\"planning_architecture\"]" ] || fail "planning plugin should record recovered-family evidence"
[ "$(json_query "$plugins_payload" 'data[0].get("benchmark_success_streak")')" = "1" ] || fail "planning plugin should start with a single success streak after one promotable compare"
[ "$(json_query "$plugins_payload" 'data[1].get("benchmark_improved_family_hits")')" = "[\"coding_mutation\"]" ] || fail "coding plugin should record improved-family evidence"
[ "$(json_query "$plugins_payload" 'data[2].get("adoption_state")')" = "trial" ] || fail "admin weak-gap plugin should remain in trial when compare is promotable overall but lacks direct family proof"
[ "$(json_query "$plugins_payload" 'data[4].get("benchmark_new_weak_family_hits")')" = "[\"review_document\"]" ] || fail "review plugin should record weak-family compare evidence"
[ "$(json_query "$plugins_payload" 'data[4].get("benchmark_hold_streak")')" = "1" ] || fail "review plugin should record an initial hold streak when compare evidence is weak"
[ "$(json_query "$plugins_payload" 'data[4].get("enabled")')" = "false" ] || fail "review plugin should stay disabled until repeated compare evidence promotes it"
[ "$(json_query "$store_json" 'data.get("capability_benchmark", {}).get("compare_recommendation")')" = "promote-candidate" ] || fail "last-run payload should preserve compare recommendation"
[ "$(json_query "$store_json" 'data.get("capability_benchmark", {}).get("candidate_promotable")')" = "true" ] || fail "last-run payload should preserve compare promotable flag"

plugins_dir_hold="$tmp_root/plugins-hold"
last_run_hold_file="$tmp_root/last-run-hold.json"
mkdir -p "$plugins_dir_hold"
self_improve_plugins_dir="$plugins_dir_hold"
self_improve_last_run_file="$last_run_hold_file"

hold_evidence_json=$(cat <<'EOF_JSON'
{"runtime_signals":{"capability_benchmark":{"high_leverage_gaps":[{"id":"admin_env_repair","critical":true,"reason":"missing-report"}],"latest_scorecard":{"recommendation":"hold","weak_families":[{"id":"admin_env_repair","critical":true,"score":58.0,"reason":"missing-report"}]},"latest_compare":{"recommendation":"hold","candidate_promotable":false,"recovered_families":[],"improved_families":[],"new_weak_families":[]},"scorecard_count":2,"compare_count":1}},"counts":{"failure_events":2,"quality_entries":11}}
EOF_JSON
)

hold_report_json=$(cat <<'EOF_JSON'
{"summary":"Hold scenario.","winner_lane":"artificer","winner_model":"mistral:latest","plugins":[{"id":"admin-driver","name":"Admin Driver","description":"Improve environment repair behavior.","instructions":"Add environment repair probes before retries.","implementation_plan":"Run repair-specific checks on setup failures.","rationale":"Admin setup remains a live weak family.","domain_tags":["admin-setup"],"benchmark_family_targets":["admin_env_repair"],"targeted_capability_gaps":["admin_env_repair"],"evidence_refs":["admin weak family"],"admin_actions":["refresh install probe"],"risk_level":"low","promotion_state":"priority"}]}
EOF_JSON
)

self_improve_store_report_and_plugins "mistral:latest" '{"objective":"Benchmark-gated adoption","competition_enabled":true}' "$hold_evidence_json" "$hold_report_json" >/dev/null
hold_plugins_payload=$(self_improve_plugins_json)
[ "$(json_query "$hold_plugins_payload" 'data[0].get("adoption_state")')" = "review" ] || fail "latest hold compare should demote unproven plugins to review"
[ "$(json_query "$hold_plugins_payload" 'data[0].get("enabled")')" = "false" ] || fail "latest hold compare should disable unproven plugins"

printf '%s\n' "ok self-improve benchmark adoption policy: compare evidence automatically adopts, stages, or rejects plugins and disables unproven ideas after a hold compare"
