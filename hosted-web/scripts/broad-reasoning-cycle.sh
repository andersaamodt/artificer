#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PARENT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)

SITE_ROOT=""
if [ -x "$PROJECT_ROOT/hosted-web/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT/hosted-web"
elif [ -x "$PROJECT_ROOT/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT"
elif [ -x "$PARENT_ROOT/web/artificer/cgi/artificer-api" ]; then
  SITE_ROOT="$PARENT_ROOT/web/artificer"
fi

if [ -z "$SITE_ROOT" ]; then
  echo "Could not locate artificer site root from $SCRIPT_DIR" >&2
  exit 1
fi

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

API="$SITE_ROOT/cgi/artificer-api"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_TASKS="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-battery-v16.tsv"

usage() {
  cat <<'USAGE'
Usage:
  broad-reasoning-cycle.sh run [--label NAME] [--tasks-file FILE] [--run-budget-sec N] [--timeout-buffer-sec N] [--task-timeout-sec N]
  broad-reasoning-cycle.sh transfer [--label NAME] --battery-summary FILE --holdout-summary FILE [--enforce-gates]

Examples:
  hosted-web/scripts/broad-reasoning-cycle.sh run --label broad-baseline --tasks-file hosted-web/tests/fixtures/artificer-broad-reasoning-battery-v1.tsv
  hosted-web/scripts/broad-reasoning-cycle.sh transfer --label broad-baseline --battery-summary "$ARTIFICER_ASSAY_REPORTS_DIR"/broad-baseline-summary.json --holdout-summary "$ARTIFICER_ASSAY_REPORTS_DIR"/broad-holdout-summary.json --enforce-gates
USAGE
}

urlenc() {
  jq -rn --arg v "$1" '$v|@uri'
}

json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

post_api() {
  body=$1
  if [ ! -x "$API" ]; then
    echo "API endpoint is not executable: $API" >&2
    return 1
  fi
  REQUEST_METHOD=POST sh "$API" <<EOF_BODY
$body
EOF_BODY
}

post_api_json() {
  body=$1
  raw=$(post_api "$body")
  json=$(printf '%s' "$raw" | json_only)
  if [ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ]; then
    echo "API response did not include JSON payload." >&2
    return 1
  fi
  ok=$(printf '%s' "$json" | jq -r 'if (type=="object" and has("success")) then (.success|tostring) else "true" end' 2>/dev/null || printf '%s' "false")
  if [ "$ok" = "false" ]; then
    err=$(printf '%s' "$json" | jq -r '.error // "unknown error"' 2>/dev/null || printf '%s' "unknown error")
    echo "API returned failure: $err" >&2
    return 1
  fi
  printf '%s' "$json"
}

run_with_timeout() {
  timeout_sec=$1
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_sec" "$@"
}

normalize_budget_runtime() {
  budget=$1
  case "$budget" in
    quick)
      printf '%s' "70"
      ;;
    standard|auto)
      printf '%s' "100"
      ;;
    long)
      printf '%s' "140"
      ;;
    until-complete)
      printf '%s' "170"
      ;;
    *)
      printf '%s' "100"
      ;;
  esac
}

normalize_max_iterations() {
  mode=$1
  budget=$2
  max_iterations=3
  case "$budget" in
    quick)
      max_iterations=2
      ;;
    long|until-complete)
      max_iterations=4
      ;;
  esac
  case "$mode" in
    assistant|report|teacher)
      if [ "$max_iterations" -lt 3 ]; then
        max_iterations=3
      fi
      ;;
    programming|security-audit|pentest)
      if [ "$max_iterations" -lt 4 ]; then
        max_iterations=4
      fi
      ;;
  esac
  printf '%s' "$max_iterations"
}

score_event_row() {
  event_json=$1
  task_id=$2
  mode=$3
  budget=$4
  domain=$5
  pair_id=$6
  variant=$7
  tactics=$8
  required_patterns=$9
  forbidden_patterns=${10}
  conversation_id=${11}

  printf '%s' "$event_json" | jq -r \
    --arg task_id "$task_id" \
    --arg mode "$mode" \
    --arg budget "$budget" \
    --arg domain "$domain" \
    --arg pair_id "$pair_id" \
    --arg variant "$variant" \
    --arg tactics "$tactics" \
    --arg required "$required_patterns" \
    --arg forbidden "$forbidden_patterns" \
    --arg conversation_id "$conversation_id" '
      def clamp(x): if x < 0 then 0 elif x > 100 then 100 else x end;
      def split_patterns(s): [ (s | split(";"))[] | gsub("^[[:space:]]+|[[:space:]]+$"; "") | select(length > 0 and (ascii_downcase != "__none__")) ];
      . as $e |
      ($e.status // "error") as $status |
      ($e.stream_text // "") as $stream |
      (if (($e.assistant // "") | length) > 0 then ($e.assistant // "") else "" end) as $assistant_text |
      (($assistant_text + "\n" + $stream) | ascii_downcase) as $all_lower |
      ($assistant_text | ascii_downcase) as $assistant_lower |
      ($stream | ascii_downcase) as $stream_lower |
      ([($e.commands // [])[]] | length) as $cmd |
      ([($stream | split("\n"))[] | select(test("^\\[[0-9]{2}:[0-9]{2}:[0-9]{2}\\]"))] | length) as $ts_steps |
      (split_patterns($required)) as $reqs |
      (split_patterns($forbidden)) as $forb |
      ([ $reqs[]? as $pat | if ($all_lower | contains($pat | ascii_downcase)) then 1 else 0 end ] | add // 0) as $req_hits |
      ([ $forb[]? as $pat | select($all_lower | contains($pat | ascii_downcase)) ] | length) as $forb_hits |
      (if ($reqs | length) > 0 then ($req_hits / ($reqs | length)) else 1 end) as $req_ratio |
      (($assistant_lower | test("verification evidence:|verification plan|verified|validation|test(s)? passed|falsif")) or ($stream_lower | test("verification|verify"))) as $verify_signal |
      ($assistant_lower | test("assumption|assume|uncertain|unknown|given incomplete")) as $assumption_signal |
      ($assistant_lower | test("alternative|counterfactual|other option|another path")) as $alternative_signal |
      ($assistant_lower | test("conflict|collision|cannot satisfy|mutually exclusive|trade[- ]?off|priority order|non-negotiable")) as $conflict_signal |
      ($assistant_lower | test("misconception|false assumption|trap|deceptive|counterevidence")) as $trap_signal |
      ($assistant_lower | test("decision:|chosen path|selected path|recommendation")) as $decision_signal |
      ($assistant_lower | test("fallback path:|fallback|contingency|alternative path")) as $fallback_signal |
      ($assistant_lower | test("disconfirm|falsif|would change this decision|counterevidence|leading indicator|invalidation trigger")) as $disconfirm_signal |
      ($assistant_lower | test("re-plan trigger|rollback threshold|abort criteria|if .* then .*switch|switch to fallback")) as $recovery_trigger_signal |
      ($assistant_lower | test("assumptions and alternatives:|assumption register|critical assumptions")) as $assumption_register_signal |
      ($assistant_lower | test("uncertainty range|confidence range|bounded uncertainty|sensitivity check|upper bound|lower bound")) as $uncertainty_bounds_signal |
      ($assistant_lower | test("scenario-specific check:|context anchor:|for this scenario")) as $scenario_anchor_signal |
      ($assistant_lower | test("architecture lens|product/ux lens|security/compliance lens|metrics/causality lens|incident/ops lens")) as $lens_mapping_signal |
      ($assistant_lower | test("abuse case|deception vector|counterfactual test|red-team probe")) as $adversarial_probe_signal |
      ($assistant_lower | test("blast radius|cost of being wrong|risk register|guardrail")) as $risk_cost_signal |
      ($assistant_lower | test("evidence anchors?:|claim[- ]?to[- ]?evidence map|evidence traceability|source traceability")) as $traceability_signal |
      (($assistant_lower | test("claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:")) or (($domain == "document creation/editing") and ($assistant_lower | test("evidence anchors:")) and ($assistant_lower | test("claim 1 \\(")) and ($assistant_lower | test("verification method")) and ($assistant_lower | test("invalidation trigger")))) as $claim_map_signal |
      (((($assistant_lower | test("claim[- ]?to[- ]?evidence map:")) and (($assistant_lower | test("claim 1 \\(")) and ($assistant_lower | test("claim 2 \\(")))) or (($assistant_lower | test("claim[- ]?to[- ]?evidence map:")) and ($assistant_lower | test("additional claim map entry"))) or (($domain == "document creation/editing") and ($assistant_lower | test("evidence anchors:")) and ($assistant_lower | test("claim 1 \\(")) and ($assistant_lower | test("claim 2 \\("))))) as $claim_map_multi_signal |
      (((($assistant_lower | test("claim[- ]?to[- ]?evidence map:")) and ($assistant_lower | test("verification method")) and ($assistant_lower | test("invalidation trigger"))) or (($domain == "document creation/editing") and ($assistant_lower | test("evidence anchors:")) and ($assistant_lower | test("verification method")) and ($assistant_lower | test("invalidation trigger"))))) as $claim_map_linkage_signal |
      ($assistant_lower | test("log|trace|metric|query|dashboard|incident|ticket|experiment|runbook|policy clause|commit|test output|command output")) as $concrete_anchor_signal |
      ($assistant_lower | test("[0-9]+(\\.[0-9]+)?[[:space:]]*(%|ms|sec|seconds|min|mins|hours|x|kb|mb|gb|p95|p99|p999)")) as $quantified_signal |
      ($assistant_lower | test("freshness|stale|confidence|uncertainty|caveat|limitation")) as $evidence_caveat_signal |
      ($assistant_lower | test("source quality ranking:|high-confidence sources|medium-confidence sources|low-confidence sources")) as $source_quality_signal |
      ($assistant_lower | test("source conflict resolution:|confidence downgrade|provisional until|unresolved contradiction")) as $source_conflict_resolution_signal |
      ($assistant_lower | test("command anchors:")) as $command_anchor_signal |
      ((($assistant_lower | test("context:")) and ($assistant_lower | test("decision:")) and ($assistant_lower | test("why not:")) and ($assistant_lower | test("fallback:")) and ($assistant_lower | test("migration plan:")) and ($assistant_lower | test("open questions:")) and ($assistant_lower | test("evidence anchors:")))
        or
       (($assistant_lower | test("summary:")) and ($assistant_lower | test("customer impact:")) and ($assistant_lower | test("timeline:")) and ($assistant_lower | test("root cause:")) and ($assistant_lower | test("mitigations:")) and ($assistant_lower | test("follow-up owners:")) and ($assistant_lower | test("evidence anchors:")))
        or
       (($assistant_lower | test("context:")) and ($assistant_lower | test("preconditions:")) and ($assistant_lower | test("procedure:")) and ($assistant_lower | test("verification:")) and ($assistant_lower | test("rollback:")) and ($assistant_lower | test("open risks:")) and ($assistant_lower | test("evidence anchors:")))) as $document_section_signal |
      ((($assistant_lower | test("outcome:")) and ($assistant_lower | test("verification evidence:")) and ($assistant_lower | test("risks:")) and ($assistant_lower | test("next improvement:"))) or (($domain == "document creation/editing") and $document_section_signal)) as $section_signal |
      (($assistant_lower | test("contradiction check|consistency check|cannot both be true|mutually exclusive"))) as $contradiction_check_signal |
      ((if $assistant_lower | test("architecture|service|api|database|queue|latency|throughput|state machine") then 1 else 0 end)
       + (if $assistant_lower | test("ux|user|onboarding|stakeholder|journey|adoption|product") then 1 else 0 end)
       + (if $assistant_lower | test("security|compliance|policy|gdpr|hipaa|soc 2|legal|risk") then 1 else 0 end)
       + (if $assistant_lower | test("metric|causal|experiment|counterfactual|confound|confidence") then 1 else 0 end)
       + (if $assistant_lower | test("incident|rollback|escalation|error budget|stabilization|runbook") then 1 else 0 end)
      ) as $domain_axes |
      (($stream_lower | test("retry|revised|corrected|switch strategy|fallback|re-plan|self-correct")) or ($assistant_lower | test("initially|revised|after re-evaluating|i was wrong"))) as $recovery_signal |
      (($assistant_lower | test("i was wrong|initial hypothesis was wrong|revised from")) or ($stream_lower | test("failed assumptions detected"))) as $hard_self_correction_signal |
      (($status == "timeout") or ($assistant_lower | test("configured run-time budget|before full completion|partial deliverable|result may be partial|partial or stale|loop ended before done mode|run (timed out|ended incomplete|was incomplete)"))) as $partial_timeout_signal |
      (clamp(30
        + (if $status == "done" then 24 elif $status == "error" then -20 elif $status == "timeout" then -26 else 0 end)
        + (20 * $req_ratio)
        + (if $verify_signal then 12 else 0 end)
        + (if $conflict_signal then 8 else 0 end)
        + (if $partial_timeout_signal then -14 else 0 end)
        - (if $forb_hits > 0 then (20 * $forb_hits) else 0 end)
      ) | floor) as $validity |
      (clamp(12
        + (if $verify_signal then 30 else 0 end)
        + (if $cmd >= 3 then 20 elif $cmd == 2 then 14 elif $cmd == 1 then 8 else 0 end)
        + (if $section_signal then 8 else 0 end)
        + (if $concrete_anchor_signal then 14 else 0 end)
        + (if $traceability_signal then 12 else 0 end)
        + (if $quantified_signal then 10 else 0 end)
        + (if $evidence_caveat_signal then 8 else 0 end)
        + (if $status == "done" then 6 else -12 end)
        + (if $partial_timeout_signal then -26 else 0 end)
        - (if ($verify_signal and ($concrete_anchor_signal | not)) then 20 else 0 end)
        - (if ($verify_signal and ($traceability_signal | not)) then 14 else 0 end)
        - (if ($verify_signal and ($quantified_signal | not)) then 10 else 0 end)
        - (if ($variant == "adversarial" and ($evidence_caveat_signal | not)) then 8 else 0 end)
      ) | floor) as $evidence |
      (clamp(8
        + (if $claim_map_signal then 30 else 0 end)
        + (if $claim_map_multi_signal then 12 else 0 end)
        + (if $claim_map_linkage_signal then 8 else 0 end)
        + (if $traceability_signal then 18 else 0 end)
        + (if $concrete_anchor_signal then 14 else 0 end)
        + (if $quantified_signal then 12 else 0 end)
        + (if $evidence_caveat_signal then 8 else 0 end)
        + (if $command_anchor_signal then 6 else 0 end)
        + (if $source_quality_signal then 8 else 0 end)
        + (if $source_conflict_resolution_signal then 6 else 0 end)
        + (if $partial_timeout_signal then -20 else 0 end)
        - (if ($verify_signal and ($claim_map_signal | not)) then 18 else 0 end)
        - (if ($claim_map_signal and ($claim_map_multi_signal | not)) then 8 else 0 end)
        - (if ($claim_map_signal and ($claim_map_linkage_signal | not)) then 8 else 0 end)
        - (if ($verify_signal and ($concrete_anchor_signal | not)) then 12 else 0 end)
        - (if ($verify_signal and ($quantified_signal | not)) then 10 else 0 end)
        - (if ($verify_signal and ($evidence_caveat_signal | not)) then 8 else 0 end)
        - (if ($variant == "adversarial" and ($source_conflict_resolution_signal | not)) then 6 else 0 end)
      ) | floor) as $claim_evidence_completeness |
      (clamp(12
        + (if $assumption_signal then 24 else -12 end)
        + (if $alternative_signal then 16 else 0 end)
        + (if $conflict_signal then 16 else 0 end)
        + (if $contradiction_check_signal then 10 else 0 end)
        + (if $assumption_register_signal then 12 else 0 end)
        + (if $uncertainty_bounds_signal then 10 else 0 end)
        + (if ($variant == "adversarial" and (($assumption_signal | not) or ($conflict_signal | not))) then -20 else 0 end)
      ) | floor) as $ambiguity |
      (clamp(15
        + ($domain_axes * 12)
        + (if $lens_mapping_signal then 16 else 0 end)
        + (if $assistant_lower | contains($domain | ascii_downcase) then 9 else 0 end)
        + (if ($variant == "adversarial" and $scenario_anchor_signal) then 8 elif ($variant == "adversarial") then -25 else 0 end)
      ) | floor) as $cross_domain |
      (clamp(20
        + (if $variant == "adversarial" then 0 else 12 end)
        + (if $conflict_signal then 14 else 0 end)
        + (if $trap_signal then 12 else 0 end)
        + (if $contradiction_check_signal then 10 else 0 end)
        + (if ($decision_signal and $fallback_signal and $disconfirm_signal) then 12 else 0 end)
        + (if $adversarial_probe_signal then 12 else 0 end)
        + (if $risk_cost_signal then 8 else 0 end)
        + (if ($variant == "adversarial" and $scenario_anchor_signal) then 10 elif ($variant == "adversarial") then -30 else 0 end)
        - (if $forb_hits > 0 then (30 * $forb_hits) else 0 end)
      ) | floor) as $adversarial |
      (clamp(18
        + (if $recovery_signal then 25 else 0 end)
        + (if $recovery_trigger_signal then 20 else 0 end)
        + (if $status == "done" then 15 else 0 end)
        + (if $hard_self_correction_signal then 22 else 0 end)
        + (if $partial_timeout_signal then -18 else 0 end)
      ) | floor) as $recovery |
      (clamp(18
        + (if $section_signal then 40 else 0 end)
        + (if $ts_steps >= 4 then 20 elif $ts_steps >= 2 then 12 elif $ts_steps >= 1 then 6 else 0 end)
        + (if $assistant_lower | test("decision|rationale|because|therefore|priority") then 12 else 0 end)
        + (if $partial_timeout_signal then -22 else 0 end)
      ) | floor) as $clarity |
      (((($validity + $evidence + $claim_evidence_completeness + $ambiguity + $cross_domain + $adversarial + $recovery + $clarity) / 8)) | floor) as $overall |
      (if $domain == "document creation/editing"
        then (if ($status == "done" and ($validity < 60 or ($document_section_signal | not) or $req_ratio < 1)) then 1 else 0 end)
        else (if ($status == "done" and ($validity < 60 or $adversarial < 55)) then 1 else 0 end)
      end) as $fail_open |
      (if (($variant == "adversarial" or ($tactics | test("underspecified|conflicting|plausible"; "i"))) and ($assumption_signal | not)) then 1 else 0 end) as $assumption_leak |
      (if ($forb_hits > 0 or ($variant == "adversarial" and ($conflict_signal | not))) then 1 else 0 end) as $contradiction |
      (if $domain == "document creation/editing"
        then (if (($status == "timeout" or $partial_timeout_signal) or ($status == "done" and ($cmd < 2 or ($document_section_signal | not) or $ts_steps < 1 or ($verify_signal | not)))) then 1 else 0 end)
        else (if (($status == "timeout" or $partial_timeout_signal) or ($status == "done" and ($cmd < 2 or ($section_signal | not) or $ts_steps < 2 or ($verify_signal and (($concrete_anchor_signal | not) or ($traceability_signal | not) or ($quantified_signal | not)))))) then 1 else 0 end)
      end) as $shallow |
      [
        $task_id,
        $mode,
        $budget,
        $domain,
        $pair_id,
        $variant,
        $tactics,
        $status,
        ($cmd|tostring),
        ($ts_steps|tostring),
        ($req_ratio|tostring),
        ($forb_hits|tostring),
        ($validity|tostring),
        ($evidence|tostring),
        ($claim_evidence_completeness|tostring),
        ($ambiguity|tostring),
        ($cross_domain|tostring),
        ($adversarial|tostring),
        ($recovery|tostring),
        ($clarity|tostring),
        ($overall|tostring),
        ($fail_open|tostring),
        ($assumption_leak|tostring),
        ($contradiction|tostring),
        ($shallow|tostring),
        $conversation_id,
        ($e.id // "")
      ] | @tsv
    '
}

emit_summary_json() {
  score_file=$1
  summary_file=$2
  awk -F '\t' '
    NR==1 { next }
    {
      rows += 1
      val += ($13 + 0)
      ev += ($14 + 0)
      claim_comp += ($15 + 0)
      amb += ($16 + 0)
      cross += ($17 + 0)
      adv += ($18 + 0)
      rec += ($19 + 0)
      clr += ($20 + 0)
      overall += ($21 + 0)
      transfer += ((($14 + 0) + ($15 + 0) + ($16 + 0) + ($17 + 0) + ($18 + 0) + ($19 + 0)) / 6.0)
      fail_open += ($22 + 0)
      assumption += ($23 + 0)
      contradiction += ($24 + 0)
      shallow += ($25 + 0)
      if (($15 + 0) < 70) claim_gap += 1
      if ($8 == "done") done += 1
      if ($6 == "adversarial") adv_tasks += 1
      if (($18 + 0) >= 70) adv_good += 1
      if (($16 + 0) >= 70) amb_good += 1
      if (($17 + 0) >= 70) cross_good += 1
      if (($19 + 0) >= 70) rec_good += 1

      ov = ($21 + 0)
      ov_key = sprintf("%.2f", ov)
      overall_hist[ov_key] += 1
      if (overall_hist[ov_key] > overall_peak) overall_peak = overall_hist[ov_key]

      if (rows == 1) {
        min_validity = max_validity = ($13 + 0)
        min_evidence = max_evidence = ($14 + 0)
        min_claim = max_claim = ($15 + 0)
        min_ambiguity = max_ambiguity = ($16 + 0)
        min_cross = max_cross = ($17 + 0)
        min_adversarial = max_adversarial = ($18 + 0)
        min_recovery = max_recovery = ($19 + 0)
        min_clarity = max_clarity = ($20 + 0)
        min_overall = max_overall = ov
      } else {
        if (($13 + 0) < min_validity) min_validity = ($13 + 0)
        if (($13 + 0) > max_validity) max_validity = ($13 + 0)
        if (($14 + 0) < min_evidence) min_evidence = ($14 + 0)
        if (($14 + 0) > max_evidence) max_evidence = ($14 + 0)
        if (($15 + 0) < min_claim) min_claim = ($15 + 0)
        if (($15 + 0) > max_claim) max_claim = ($15 + 0)
        if (($16 + 0) < min_ambiguity) min_ambiguity = ($16 + 0)
        if (($16 + 0) > max_ambiguity) max_ambiguity = ($16 + 0)
        if (($17 + 0) < min_cross) min_cross = ($17 + 0)
        if (($17 + 0) > max_cross) max_cross = ($17 + 0)
        if (($18 + 0) < min_adversarial) min_adversarial = ($18 + 0)
        if (($18 + 0) > max_adversarial) max_adversarial = ($18 + 0)
        if (($19 + 0) < min_recovery) min_recovery = ($19 + 0)
        if (($19 + 0) > max_recovery) max_recovery = ($19 + 0)
        if (($20 + 0) < min_clarity) min_clarity = ($20 + 0)
        if (($20 + 0) > max_clarity) max_clarity = ($20 + 0)
        if (ov < min_overall) min_overall = ov
        if (ov > max_overall) max_overall = ov
      }
    }
    END {
      total = rows
      if (total < 1) {
        total = 1
        overall_peak = 0
        min_validity = max_validity = 0
        min_evidence = max_evidence = 0
        min_claim = max_claim = 0
        min_ambiguity = max_ambiguity = 0
        min_cross = max_cross = 0
        min_adversarial = max_adversarial = 0
        min_recovery = max_recovery = 0
        min_clarity = max_clarity = 0
        min_overall = max_overall = 0
      }

      flat_dimension_count = 0
      if ((max_validity - min_validity) <= 2) flat_dimension_count += 1
      if ((max_evidence - min_evidence) <= 2) flat_dimension_count += 1
      if ((max_claim - min_claim) <= 2) flat_dimension_count += 1
      if ((max_ambiguity - min_ambiguity) <= 2) flat_dimension_count += 1
      if ((max_cross - min_cross) <= 2) flat_dimension_count += 1
      if ((max_adversarial - min_adversarial) <= 2) flat_dimension_count += 1
      if ((max_recovery - min_recovery) <= 2) flat_dimension_count += 1
      if ((max_clarity - min_clarity) <= 2) flat_dimension_count += 1
      if ((max_overall - min_overall) <= 2) flat_dimension_count += 1

      overall_range = max_overall - min_overall
      overall_peak_ratio = (overall_peak + 0) / total

      saturation_risk = "false"
      if (rows >= 8 && overall_peak_ratio >= 0.75 && flat_dimension_count >= 6 && (done + 0) >= (rows * 0.8)) {
        saturation_risk = "true"
      }
      printf "{\"tasks\":%d,\"done\":%d,\"avg_validity\":%.2f,\"avg_evidence\":%.2f,\"avg_claim_evidence_completeness\":%.2f,\"claim_evidence_gap_rate\":%.4f,\"avg_ambiguity\":%.2f,\"avg_cross_domain\":%.2f,\"avg_adversarial\":%.2f,\"avg_recovery\":%.2f,\"avg_clarity\":%.2f,\"avg_overall\":%.2f,\"avg_transfer_readiness\":%.2f,\"fail_open_rate\":%.4f,\"assumption_leak_rate\":%.4f,\"contradiction_rate\":%.4f,\"shallow_completion_rate\":%.4f,\"score_uniformity\":{\"overall_range\":%.2f,\"overall_peak_ratio\":%.4f,\"flat_dimension_count\":%d},\"saturation_risk\":%s,\"improvement_axes\":{\"adversarial\":%.4f,\"ambiguity\":%.4f,\"cross_domain\":%.4f,\"recovery\":%.4f}}\n", \
        total, done + 0, val / total, ev / total, claim_comp / total, claim_gap / total, amb / total, cross / total, adv / total, rec / total, clr / total, overall / total, \
        transfer / total, \
        fail_open / total, assumption / total, contradiction / total, shallow / total, \
        overall_range, overall_peak_ratio, flat_dimension_count, saturation_risk, \
        adv_good / total, amb_good / total, cross_good / total, rec_good / total
    }
  ' "$score_file" > "$summary_file"
}

emit_taxonomy() {
  score_file=$1
  taxonomy_file=$2
  taxonomy_tmp=$(mktemp)
  awk -F '\t' '
    NR==1 { next }
    {
      if (($16 + 0) < 60 || ($23 + 0) == 1) {
        c["assumption-leak"] += 1
        s["assumption-leak"] += (60 - ($16 + 0) > 0 ? 60 - ($16 + 0) : 8)
      }
      if (($18 + 0) < 60 || ($24 + 0) == 1) {
        c["adversarial-trap-vulnerability"] += 1
        s["adversarial-trap-vulnerability"] += (60 - ($18 + 0) > 0 ? 60 - ($18 + 0) : 10)
      }
      if (($6 == "adversarial") && (($18 + 0) < 75)) {
        c["adversarial-depth-gap"] += 1
        s["adversarial-depth-gap"] += (75 - ($18 + 0) > 0 ? 75 - ($18 + 0) : 9)
      }
      if (($6 == "adversarial") && (($11 + 0) < 1)) {
        c["adversarial-completeness-gap"] += 1
        s["adversarial-completeness-gap"] += (1 - ($11 + 0)) * 25
      }
      if (($17 + 0) < 60) {
        c["cross-domain-narrowness"] += 1
        s["cross-domain-narrowness"] += (60 - ($17 + 0) > 0 ? 60 - ($17 + 0) : 6)
      }
      if (($15 + 0) < 70) {
        c["claim-evidence-completeness-gap"] += 1
        s["claim-evidence-completeness-gap"] += (70 - ($15 + 0) > 0 ? 70 - ($15 + 0) : 8)
      }
      if (($11 + 0) < 1) {
        c["decision-completeness-gap"] += 1
        s["decision-completeness-gap"] += (1 - ($11 + 0)) * 20
      }
      if (($19 + 0) < 60) {
        c["recovery-self-correction-gap"] += 1
        s["recovery-self-correction-gap"] += (60 - ($19 + 0) > 0 ? 60 - ($19 + 0) : 7)
      }
      if (($14 + 0) < 60 || ($25 + 0) == 1) {
        c["shallow-verification"] += 1
        s["shallow-verification"] += (60 - ($14 + 0) > 0 ? 60 - ($14 + 0) : 8)
      }
      if (($20 + 0) < 60) {
        c["trace-clarity-gap"] += 1
        s["trace-clarity-gap"] += (60 - ($20 + 0) > 0 ? 60 - ($20 + 0) : 5)
      }
    }
    END {
      for (k in c) {
        if (c[k] > 0) {
          sev = s[k] / c[k]
          w = sev * c[k]
          printf "%s\t%d\t%.2f\t%.2f\n", k, c[k], sev, w
        }
      }
    }
  ' "$score_file" > "$taxonomy_tmp"
  {
    printf 'failure_mode\trecurrence\tseverity\tweight\n'
    sort -t "$(printf '\t')" -k4,4nr "$taxonomy_tmp"
  } > "$taxonomy_file"
  rm -f "$taxonomy_tmp"
}

render_report() {
  label=$1
  score_file=$2
  summary_file=$3
  taxonomy_file=$4
  report_file=$5

  summary_json=$(cat "$summary_file")
  avg_overall=$(printf '%s' "$summary_json" | jq -r '.avg_overall')
  avg_transfer_readiness=$(printf '%s' "$summary_json" | jq -r '.avg_transfer_readiness')
  avg_claim_evidence_completeness=$(printf '%s' "$summary_json" | jq -r '.avg_claim_evidence_completeness')
  claim_evidence_gap_rate=$(printf '%s' "$summary_json" | jq -r '.claim_evidence_gap_rate')
  fail_open_rate=$(printf '%s' "$summary_json" | jq -r '.fail_open_rate')
  assumption_leak_rate=$(printf '%s' "$summary_json" | jq -r '.assumption_leak_rate')
  contradiction_rate=$(printf '%s' "$summary_json" | jq -r '.contradiction_rate')
  shallow_rate=$(printf '%s' "$summary_json" | jq -r '.shallow_completion_rate')
  overall_uniformity_range=$(printf '%s' "$summary_json" | jq -r '.score_uniformity.overall_range // 0')
  overall_peak_ratio=$(printf '%s' "$summary_json" | jq -r '.score_uniformity.overall_peak_ratio // 0')
  flat_dimension_count=$(printf '%s' "$summary_json" | jq -r '.score_uniformity.flat_dimension_count // 0')
  saturation_risk=$(printf '%s' "$summary_json" | jq -r '.saturation_risk // false')

  {
    printf '# Broad Reasoning Assay Report: %s\n\n' "$label"
    printf '## Summary\n'
    printf -- '- Average overall score: %s\n' "$avg_overall"
    printf -- '- Average transfer-readiness score: %s\n' "$avg_transfer_readiness"
    printf -- '- Average claim-to-evidence completeness score: %s\n' "$avg_claim_evidence_completeness"
    printf -- '- Claim-to-evidence completeness gap rate (<70): %s\n' "$claim_evidence_gap_rate"
    printf -- '- Fail-open rate: %s\n' "$fail_open_rate"
    printf -- '- Assumption leak rate: %s\n' "$assumption_leak_rate"
    printf -- '- Contradiction rate: %s\n' "$contradiction_rate"
    printf -- '- Shallow-completion rate: %s\n' "$shallow_rate"
    printf -- '- Score uniformity (overall range): %s\n' "$overall_uniformity_range"
    printf -- '- Score uniformity (overall peak ratio): %s\n' "$overall_peak_ratio"
    printf -- '- Flat-dimension count (<=2 range across 9 dimensions): %s\n' "$flat_dimension_count"
    printf -- '- Saturation risk flagged: %s\n' "$saturation_risk"

    printf '\n## Top Failure Modes (ranked)\n'
    awk -F '\t' 'NR==1 { next } { printf "- %s: recurrence=%s, severity=%s, weight=%s\n", $1, $2, $3, $4 }' "$taxonomy_file" | sed -n '1,8p'

    printf '\n## Task Scores\n'
    printf '| Task | Variant | Status | Validity | Evidence | Claim-Evidence | Ambiguity | Cross | Adversarial | Recovery | Clarity | Overall |\n'
    printf '|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n'
    awk -F '\t' 'NR>1 { printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $6, $8, $13, $14, $15, $16, $17, $18, $19, $20, $21 }' "$score_file"
  } > "$report_file"
}

run_panel_turn() {
  ws_id=$1
  conv_id=$2
  label=$3
  task_id=$4
  mode=$5
  budget=$6
  runtime_sec=$7
  timeout_this=$8
  max_iterations=$9
  prompt_text=${10}

  prompt_suffix=$(cat <<EOF_SCOPE

Assay execution scope:
- Work only inside $ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id/
- If details are ambiguous or conflicting, state assumptions explicitly and continue with a defensible choice.
- Include at least one explicit verification plan and one contradiction/consistency check.
- Keep streamed progress concise and timestamped.
EOF_SCOPE
)
  prompt_for_run=$(printf '%s\n%s' "$prompt_text" "$prompt_suffix")
  body="action=run&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")&prompt=$(urlenc "$prompt_for_run")&run_mode=$(urlenc "$mode")&compute_budget=$(urlenc "$budget")&advanced_loop=1&max_iterations=$max_iterations&programmer_review=1&programmer_review_rounds=2&assay_task_id=$(urlenc "$task_id")"

  turn_timed_out=0
  if ! run_with_timeout "$timeout_this" sh -c "ARTIFICER_RUN_TIME_BUDGET_SEC=$runtime_sec REQUEST_METHOD=POST sh \"$API\" <<'EOF_RUN' >/dev/null
$body
EOF_RUN
" 2>/dev/null; then
    turn_timed_out=1
  fi

  if [ "$turn_timed_out" -eq 1 ]; then
    post_api "action=queue_stop&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")" >/dev/null || true
  fi

  settle_try=0
  settle_limit=70
  while [ "$settle_try" -lt "$settle_limit" ]; do
    queue_json=$(post_api_json "action=queue_list&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")")
    queue_running=$(printf '%s' "$queue_json" | jq -r '.queue_running // 0')
    if [ "$queue_running" != "1" ]; then
      break
    fi
    sleep 0.5
    settle_try=$((settle_try + 1))
  done

  turn_state_json=$(post_api_json "action=get_conversation&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")")
  turn_event_json=$(printf '%s' "$turn_state_json" | jq -c '.conversation.run_events[-1] // {}')
  turn_assistant_text=$(printf '%s' "$turn_state_json" | jq -r '.conversation.messages | map(select(.role=="assistant")) | last | .content // ""')
  if [ -n "$turn_assistant_text" ]; then
    turn_event_json=$(printf '%s' "$turn_event_json" | jq -c --arg a "$turn_assistant_text" '.assistant = (if ((.assistant // "") | length) > 0 then .assistant else $a end)')
  fi
  turn_stream_text=$(printf '%s' "$turn_event_json" | jq -r '.stream_text // ""')
  turn_run_status=$(printf '%s' "$turn_event_json" | jq -r '.status // "error"')
  turn_run_event_id=$(printf '%s' "$turn_event_json" | jq -r '.id // ""')
}

run_panel() {
  label=$1
  tasks_file=$2
  run_budget_default=$3
  timeout_buffer_sec=$4
  task_timeout_sec=$5

  mkdir -p "$OUT_DIR"
  mkdir -p "$ARTIFICER_ASSAY_RUNS_DIR/$label"
  raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
  mkdir -p "$raw_dir"

  score_file="$OUT_DIR/$label-scores.tsv"
  summary_file="$OUT_DIR/$label-summary.json"
  taxonomy_file="$OUT_DIR/$label-taxonomy.tsv"
  report_file="$OUT_DIR/$label-report.md"

  printf 'task_id\tmode\tbudget\tdomain\tpair_id\tvariant\ttactics\tstatus\tcommands\ttimestamp_steps\trequired_ratio\tforbidden_hits\tvalidity\tevidence\tclaim_evidence_completeness\tambiguity\tcross_domain\tadversarial_robustness\trecovery\tclarity\toverall\tfail_open\tassumption_leak\tcontradiction\tshallow_completion\tconversation_id\trun_event_id\n' > "$score_file"

  ws_json=$(post_api_json "action=add_workspace&path=$(urlenc "$PROJECT_ROOT")&name=$(urlenc "Broad Reasoning $label")")
  ws_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id')
  if [ -z "$ws_id" ] || [ "$ws_id" = "null" ]; then
    echo "Failed to create/get workspace for panel run." >&2
    exit 1
  fi

  tab_char=$(printf '\t')
  while IFS="$tab_char" read -r task_id mode budget domain pair_id variant tactics required_patterns forbidden_patterns prompt followup_prompt || [ -n "$task_id" ]; do
    task_id=$(printf '%s' "$task_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$task_id" ] || continue
    case "$task_id" in
      task_id) continue ;;
      \#*) continue ;;
    esac

    runtime_sec=$run_budget_default
    if [ "$runtime_sec" -le 0 ]; then
      runtime_sec=$(normalize_budget_runtime "$budget")
    fi
    max_iterations=$(normalize_max_iterations "$mode" "$budget")
    timeout_this=$((runtime_sec + timeout_buffer_sec))
    if [ "$timeout_this" -lt "$task_timeout_sec" ]; then
      timeout_this=$task_timeout_sec
    fi

    mkdir -p "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id"

    conv_title="${label}-${task_id}"
    conv_json=$(post_api_json "action=new_conversation&workspace_id=$(urlenc "$ws_id")&title=$(urlenc "$conv_title")")
    conv_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id')

    run_panel_turn "$ws_id" "$conv_id" "$label" "$task_id" "$mode" "$budget" "$runtime_sec" "$timeout_this" "$max_iterations" "$prompt"
    initial_state_json=$turn_state_json
    initial_event_json=$turn_event_json
    initial_assistant_text=$turn_assistant_text
    initial_stream_text=$turn_stream_text
    initial_run_status=$turn_run_status
    initial_run_event_id=$turn_run_event_id
    initial_timed_out=$turn_timed_out

    state_json=$initial_state_json
    event_json=$initial_event_json
    assistant_from_messages=$initial_assistant_text
    stream_text=$initial_stream_text
    timed_out=$initial_timed_out

    followup_prompt=$(printf '%s' "${followup_prompt:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$followup_prompt" ] && [ "$initial_run_status" = "done" ] && [ -n "$(printf '%s' "$initial_assistant_text" | sed 's/[[:space:]]//g')" ]; then
      run_panel_turn "$ws_id" "$conv_id" "$label" "$task_id" "$mode" "$budget" "$runtime_sec" "$timeout_this" "$max_iterations" "$followup_prompt"
      state_json=$turn_state_json
      event_json=$turn_event_json
      assistant_from_messages=$turn_assistant_text
      stream_text=$turn_stream_text
      timed_out=$turn_timed_out
    fi

    printf '%s\n' "$initial_state_json" > "$raw_dir/${task_id}-conversation-initial.json"
    printf '%s\n' "$initial_event_json" > "$raw_dir/${task_id}-event-initial.json"
    printf '%s\n' "$initial_assistant_text" > "$raw_dir/${task_id}-assistant-initial.txt"
    printf '%s\n' "$initial_stream_text" > "$raw_dir/${task_id}-stream-initial.txt"
    printf '%s\n' "$state_json" > "$raw_dir/${task_id}-conversation.json"
    printf '%s\n' "$event_json" > "$raw_dir/${task_id}-event.json"
    printf '%s\n' "$assistant_from_messages" > "$raw_dir/${task_id}-assistant.txt"
    printf '%s\n' "$stream_text" > "$raw_dir/${task_id}-stream.txt"

    row=$(score_event_row "$event_json" "$task_id" "$mode" "$budget" "$domain" "$pair_id" "$variant" "$tactics" "$required_patterns" "$forbidden_patterns" "$conv_id")

    if [ "$timed_out" -eq 1 ]; then
      row=$(printf '%s' "$row" | awk -F '\t' 'BEGIN{OFS=FS}{$8="timeout"; print}')
    fi

    printf '%s\n' "$row" >> "$score_file"
    echo "panel[$label] done: $task_id" >&2
  done < "$tasks_file"

  emit_summary_json "$score_file" "$summary_file"
  emit_taxonomy "$score_file" "$taxonomy_file"
  render_report "$label" "$score_file" "$summary_file" "$taxonomy_file" "$report_file"

  printf '%s\n' "$score_file"
  printf '%s\n' "$summary_file"
  printf '%s\n' "$taxonomy_file"
  printf '%s\n' "$report_file"
}

run_transfer_gap_analysis() {
  label=$1
  battery_summary=$2
  holdout_summary=$3
  out_json=$4
  out_report=$5

  jq -n \
    --arg label "$label" \
    --slurpfile battery "$battery_summary" \
    --slurpfile holdout "$holdout_summary" '
      def nz(x): if (x == null) then 0 else x end;
      def nb(x): if (x == true) then true else false end;
      ($battery[0] // {}) as $b |
      ($holdout[0] // {}) as $h |
      ((nz($h.avg_overall) - nz($b.avg_overall))) as $delta_overall |
      ((nz($h.avg_transfer_readiness) - nz($b.avg_transfer_readiness))) as $delta_transfer |
      ((nz($h.fail_open_rate) - nz($b.fail_open_rate))) as $delta_fail_open |
      ((nz($h.contradiction_rate) - nz($b.contradiction_rate))) as $delta_contradiction |
      ((nz($h.avg_evidence) - nz($b.avg_evidence))) as $delta_evidence |
      ((nz($h.avg_claim_evidence_completeness) - nz($b.avg_claim_evidence_completeness))) as $delta_claim_comp |
      ((nz($h.avg_ambiguity) - nz($b.avg_ambiguity))) as $delta_ambiguity |
      ((nz($h.avg_cross_domain) - nz($b.avg_cross_domain))) as $delta_cross |
      ((nz($h.avg_adversarial) - nz($b.avg_adversarial))) as $delta_adversarial |
      ((nz($h.avg_recovery) - nz($b.avg_recovery))) as $delta_recovery |
      (nb($b.saturation_risk) or nb($h.saturation_risk)) as $saturation_flag |
      ([
        {name:"adversarial", battery:nz($b.avg_adversarial), holdout:nz($h.avg_adversarial), delta:$delta_adversarial},
        {name:"ambiguity", battery:nz($b.avg_ambiguity), holdout:nz($h.avg_ambiguity), delta:$delta_ambiguity},
        {name:"cross_domain", battery:nz($b.avg_cross_domain), holdout:nz($h.avg_cross_domain), delta:$delta_cross},
        {name:"recovery", battery:nz($b.avg_recovery), holdout:nz($h.avg_recovery), delta:$delta_recovery}
      ]) as $tracked_axes |
      ([$tracked_axes[] | select(.delta > 0)] | length) as $improved_axes |
      ([$tracked_axes[] | select((.battery >= 99.5) and (.holdout >= 99.5) and (.delta >= 0))] | length) as $stable_axes |
      ([$tracked_axes[] | select((.delta > 0) or ((.battery >= 99.5) and (.holdout >= 99.5) and (.delta >= 0)))] | length) as $robust_axes |
      (
        (nz($h.avg_overall) >= 70) and
        (nz($h.avg_transfer_readiness) >= 65) and
        (nz($h.avg_evidence) >= 90) and
        (nz($h.avg_claim_evidence_completeness) >= 90) and
        (nz($h.fail_open_rate) == 0) and
        (nz($h.contradiction_rate) == 0) and
        (nz($h.shallow_completion_rate) == 0) and
        ($delta_overall >= 0) and
        ($delta_transfer >= 0) and
        ($delta_fail_open <= 0) and
        ($delta_contradiction <= 0)
      ) as $stable_quality_floor |
      {
        label: $label,
        battery: $b,
        holdout: $h,
        tracked_axes: $tracked_axes,
        deltas: {
          overall: $delta_overall,
          transfer_readiness: $delta_transfer,
          evidence: $delta_evidence,
          claim_evidence_completeness: $delta_claim_comp,
          ambiguity: $delta_ambiguity,
          cross_domain: $delta_cross,
          adversarial: $delta_adversarial,
          recovery: $delta_recovery,
          fail_open_rate: $delta_fail_open,
          contradiction_rate: $delta_contradiction
        },
        gap: {
          overall_drop: (nz($b.avg_overall) - nz($h.avg_overall)),
          transfer_drop: (nz($b.avg_transfer_readiness) - nz($h.avg_transfer_readiness))
        },
        gates: {
          fail_open_non_increase: ($delta_fail_open <= 0),
          contradiction_non_increase: ($delta_contradiction <= 0),
          holdout_not_worse_overall: ($delta_overall >= 0),
          improved_axes_at_least_two: ($improved_axes >= 2),
          robustness_coverage_at_least_two: ($robust_axes >= 2),
          stable_quality_floor: $stable_quality_floor,
          no_saturation_risk: ($saturation_flag | not)
        },
        all_gates_pass: (
          ($delta_fail_open <= 0) and
          ($delta_contradiction <= 0) and
          ($delta_overall >= 0) and
          (($robust_axes >= 2) or $stable_quality_floor) and
          ($saturation_flag | not)
        ),
        improved_axes_count: $improved_axes,
        stable_excellence_axes_count: $stable_axes,
        robustness_coverage_axes_count: $robust_axes,
        saturation_risk: $saturation_flag,
        transfer_risk: (
          if ($saturation_flag) then "high"
          elif ($delta_overall < -3 or $delta_transfer < -3) then "high"
          elif ($delta_overall < -1.5 or $delta_transfer < -1.5 or $delta_fail_open > 0 or $delta_contradiction > 0) then "medium"
          else "low" end
        ),
        overfit_risk: (
          $saturation_flag or ($delta_overall < -1.5 and ($delta_evidence < 0 or $delta_claim_comp < 0 or $delta_adversarial < 0 or $delta_cross < 0))
        )
      }
    ' > "$out_json"

  risk=$(jq -r '.transfer_risk' "$out_json")
  improved_axes=$(jq -r '.improved_axes_count' "$out_json")
  stable_axes=$(jq -r '.stable_excellence_axes_count // 0' "$out_json")
  robust_axes=$(jq -r '.robustness_coverage_axes_count // 0' "$out_json")
  gate_fail_open=$(jq -r '.gates.fail_open_non_increase' "$out_json")
  gate_contradiction=$(jq -r '.gates.contradiction_non_increase' "$out_json")
  gate_holdout=$(jq -r '.gates.holdout_not_worse_overall' "$out_json")
  gate_axes=$(jq -r '.gates.improved_axes_at_least_two' "$out_json")
  gate_robust_axes=$(jq -r '.gates.robustness_coverage_at_least_two // false' "$out_json")
  gate_stable_floor=$(jq -r '.gates.stable_quality_floor // false' "$out_json")
  gate_saturation=$(jq -r '.gates.no_saturation_risk' "$out_json")

  {
    printf '# Transfer Gap Report: %s\n\n' "$label"
    printf '## Battery vs Holdout\n'
    printf -- '- Overall delta (holdout - battery): %s\n' "$(jq -r '.deltas.overall' "$out_json")"
    printf -- '- Transfer-readiness delta: %s\n' "$(jq -r '.deltas.transfer_readiness' "$out_json")"
    printf -- '- Evidence delta: %s\n' "$(jq -r '.deltas.evidence' "$out_json")"
    printf -- '- Claim-to-evidence completeness delta: %s\n' "$(jq -r '.deltas.claim_evidence_completeness' "$out_json")"
    printf -- '- Ambiguity delta: %s\n' "$(jq -r '.deltas.ambiguity' "$out_json")"
    printf -- '- Cross-domain delta: %s\n' "$(jq -r '.deltas.cross_domain' "$out_json")"
    printf -- '- Adversarial delta: %s\n' "$(jq -r '.deltas.adversarial' "$out_json")"
    printf -- '- Recovery delta: %s\n' "$(jq -r '.deltas.recovery' "$out_json")"
    printf -- '- Fail-open delta: %s\n' "$(jq -r '.deltas.fail_open_rate' "$out_json")"
    printf -- '- Contradiction-rate delta: %s\n' "$(jq -r '.deltas.contradiction_rate' "$out_json")"

    printf '\n## Gate Check\n'
    printf -- '- no fail-open increase: %s\n' "$gate_fail_open"
    printf -- '- no contradiction-rate increase: %s\n' "$gate_contradiction"
    printf -- '- holdout not worse overall: %s\n' "$gate_holdout"
    printf -- '- improved axes >= 2: %s (count=%s)\n' "$gate_axes" "$improved_axes"
    printf -- '- improved or stably excellent axes >= 2: %s (coverage=%s stable=%s)\n' "$gate_robust_axes" "$robust_axes" "$stable_axes"
    printf -- '- stable quality floor satisfied: %s\n' "$gate_stable_floor"
    printf -- '- no saturation-risk flag in battery/holdout: %s\n' "$gate_saturation"
    printf -- '- all gates pass: %s\n' "$(jq -r '.all_gates_pass' "$out_json")"

    printf '\n## Risk\n'
    printf -- '- Transfer risk: %s\n' "$risk"
    printf -- '- Saturation risk flagged: %s\n' "$(jq -r '.saturation_risk' "$out_json")"
    printf -- '- Overfit risk flagged: %s\n' "$(jq -r '.overfit_risk' "$out_json")"
  } > "$out_report"
}

mode=${1:-}
if [ -z "$mode" ]; then
  usage
  exit 1
fi
shift

case "$mode" in
  run)
    label="broad-$(date +%Y%m%d-%H%M%S)"
    tasks_file="$DEFAULT_TASKS"
    run_budget_sec=0
    timeout_buffer_sec=140
    task_timeout_sec=180

    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --tasks-file)
          tasks_file=$2
          shift 2
          ;;
        --run-budget-sec)
          run_budget_sec=$2
          shift 2
          ;;
        --timeout-buffer-sec)
          timeout_buffer_sec=$2
          shift 2
          ;;
        --task-timeout-sec)
          task_timeout_sec=$2
          shift 2
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done

    if [ ! -f "$tasks_file" ]; then
      echo "Tasks file not found: $tasks_file" >&2
      exit 1
    fi

    run_panel "$label" "$tasks_file" "$run_budget_sec" "$timeout_buffer_sec" "$task_timeout_sec"
    ;;
  transfer)
    label="broad-transfer-$(date +%Y%m%d-%H%M%S)"
    battery_summary=""
    holdout_summary=""
    enforce_transfer_gates=0

    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --battery-summary)
          battery_summary=$2
          shift 2
          ;;
        --holdout-summary)
          holdout_summary=$2
          shift 2
          ;;
        --enforce-gates)
          enforce_transfer_gates=1
          shift
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done

    if [ ! -f "$battery_summary" ]; then
      echo "Battery summary not found: $battery_summary" >&2
      exit 1
    fi
    if [ ! -f "$holdout_summary" ]; then
      echo "Holdout summary not found: $holdout_summary" >&2
      exit 1
    fi

    mkdir -p "$OUT_DIR"
    transfer_json="$OUT_DIR/$label-transfer.json"
    transfer_report="$OUT_DIR/$label-transfer.md"
    run_transfer_gap_analysis "$label" "$battery_summary" "$holdout_summary" "$transfer_json" "$transfer_report"
    printf '%s\n' "$transfer_json"
    printf '%s\n' "$transfer_report"
    if [ "$enforce_transfer_gates" -eq 1 ]; then
      if ! jq -e '.all_gates_pass == true' "$transfer_json" >/dev/null 2>&1; then
        echo "Transfer gates failed for label '$label'." >&2
        exit 2
      fi
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
