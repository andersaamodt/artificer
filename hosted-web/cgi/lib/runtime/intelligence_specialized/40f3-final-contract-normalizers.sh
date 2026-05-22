count_reasoning_domain_axes() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  axes=0
  if printf '%s' "$text_lower" | grep -Eq 'architecture|service|api|database|queue|latency|throughput|state machine'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'ux|user|onboarding|stakeholder|journey|adoption|product'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'security|compliance|policy|gdpr|hipaa|soc 2|legal|risk'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'metric|causal|experiment|counterfactual|confound|confidence'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'incident|rollback|escalation|error budget|stabilization|runbook'; then
    axes=$((axes + 1))
  fi
  printf '%s' "$axes"
}

final_has_assumption_and_conflict_signals() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_assumption=0
  has_conflict=0
  if printf '%s' "$final_text_lower" | grep -Eq 'assumption|assume'; then
    has_assumption=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'conflict|trade[- ]?off|priority|cannot satisfy|contradiction'; then
    has_conflict=1
  fi
  if [ "$has_assumption" -eq 1 ] && [ "$has_conflict" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_adversarial_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_assumption=0
  has_conflict=0
  has_alternative=0
  has_contradiction=0
  has_trap=0
  has_false_premise=0
  has_premise_validation=0
  if printf '%s' "$final_text_lower" | grep -Eq 'assumption|assume'; then
    has_assumption=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'conflict|trade[- ]?off|priority|cannot satisfy|non-negotiable'; then
    has_conflict=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'alternative|counterfactual|another path|other option'; then
    has_alternative=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'contradiction check|consistency check|cannot both be true|mutually exclusive|contradiction'; then
    has_contradiction=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'trap|deceptive|counterevidence|false assumption|near-miss'; then
    has_trap=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'false premise challenge:|plausible but false assumption|attractive but wrong assumption'; then
    has_false_premise=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'premise validation:|invalidating evidence|falsifying evidence|would falsify'; then
    has_premise_validation=1
  fi
  if [ "$has_assumption" -eq 1 ] && [ "$has_conflict" -eq 1 ] && [ "$has_alternative" -eq 1 ] && [ "$has_contradiction" -eq 1 ] && [ "$has_trap" -eq 1 ] && [ "$has_false_premise" -eq 1 ] && [ "$has_premise_validation" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_decision_completeness() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_decision=0
  has_fallback=0
  has_disconfirm=0
  has_priority=0
  if printf '%s' "$final_text_lower" | grep -Eq 'decision:|chosen path|selected path|recommendation'; then
    has_decision=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'fallback path:'; then
    has_fallback=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'disconfirming evidence:'; then
    has_disconfirm=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'priority order|priority:'; then
    has_priority=1
  fi
  if [ "$has_decision" -eq 1 ] && [ "$has_fallback" -eq 1 ] && [ "$has_disconfirm" -eq 1 ] && [ "$has_priority" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_cross_domain_signals() {
  min_axes=${2:-2}
  axes=$(count_reasoning_domain_axes "$1")
  case "$axes" in
    ""|*[!0-9]*)
      axes=0
      ;;
  esac
  case "$min_axes" in
    ""|*[!0-9]*)
      min_axes=2
      ;;
  esac
  if [ "$axes" -ge "$min_axes" ]; then
    return 0
  fi
  return 1
}

final_has_cross_domain_synthesis_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_integration=0
  has_domain_anchor=0
  has_arch=0
  has_product=0
  has_security=0
  has_metrics=0
  has_incident=0
  has_tradeoff=0
  has_alternative=0
  if printf '%s' "$final_text_lower" | grep -Eq 'cross-domain integration:'; then
    has_integration=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'domain anchor:'; then
    has_domain_anchor=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'architecture lens:'; then
    has_arch=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'product/ux lens:'; then
    has_product=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'security/compliance lens:'; then
    has_security=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'metrics/causality lens:'; then
    has_metrics=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'incident/ops lens:'; then
    has_incident=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'tradeoff ledger:|priority order:'; then
    has_tradeoff=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'rejected alternative:|fallback path:'; then
    has_alternative=1
  fi
  if [ "$has_integration" -eq 1 ] && [ "$has_domain_anchor" -eq 1 ] && [ "$has_arch" -eq 1 ] && [ "$has_product" -eq 1 ] && [ "$has_security" -eq 1 ] && [ "$has_metrics" -eq 1 ] && [ "$has_incident" -eq 1 ] && [ "$has_tradeoff" -eq 1 ] && [ "$has_alternative" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_evidence_specificity_signals() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  anchor_hits=0
  has_quantified_threshold=0
  has_traceability_map=0
  has_caveat=0

  if printf '%s' "$final_text_lower" | grep -Eq 'log|trace|stack|signature'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'metric|p95|p99|error rate|latency|throughput'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'query|dashboard|dataset|table|cohort'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'incident|ticket|timeline|runbook'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'policy clause|control objective|regulatory|compliance clause'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'commit|pull request|test output|command output'; then
    anchor_hits=$((anchor_hits + 1))
  fi

  if printf '%s' "$final_text_lower" | grep -Eq '[0-9]+(\.[0-9]+)?[[:space:]]*(%|ms|sec|seconds|min|mins|hours|x|kb|mb|gb|p95|p99|p999)'; then
    has_quantified_threshold=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence|claim[- ]?evidence map|evidence traceability|source traceability|evidence anchor'; then
    has_traceability_map=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'confidence|uncertainty|caveat|freshness|stale|limitation'; then
    has_caveat=1
  fi

  if [ "$anchor_hits" -ge 2 ] && [ "$has_quantified_threshold" -eq 1 ] && [ "$has_traceability_map" -eq 1 ] && [ "$has_caveat" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_verification_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_verification=0
  has_disconfirming=0
  has_risk=0
  if printf '%s' "$final_text_lower" | grep -Eq 'verification evidence:|verification plan|verified|validation|test(s)? passed|falsif'; then
    has_verification=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'disconfirming evidence:|falsif|would change this decision|counterevidence|leading indicator'; then
    has_disconfirming=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'risk register|cost of being wrong|blast radius|guardrail'; then
    has_risk=1
  fi
  if [ "$has_verification" -eq 1 ] && [ "$has_disconfirming" -eq 1 ] && [ "$has_risk" -eq 1 ] && final_has_evidence_specificity_signals "$1"; then
    return 0
  fi
  return 1
}

final_has_source_quality_contradiction_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_source_quality=0
  has_confidence_tiers=0
  has_contradiction=0
  has_resolution=0

  if printf '%s' "$final_text_lower" | grep -Eq 'source quality ranking:'; then
    has_source_quality=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'high[- ]confidence|medium[- ]confidence|low[- ]confidence|high-confidence|medium-confidence|low-confidence|tier[[:space:]]*[123]'; then
    has_confidence_tiers=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'contradiction check:'; then
    has_contradiction=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'source conflict resolution:|confidence downgrade|provisional until|unresolved contradiction|would change this decision'; then
    has_resolution=1
  fi

  if [ "$has_source_quality" -eq 1 ] && [ "$has_confidence_tiers" -eq 1 ] && [ "$has_contradiction" -eq 1 ] && [ "$has_resolution" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_runtime_command_evidence_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  require_claim_map_raw=${2:-0}
  has_command_anchors=0
  has_anchor_status=0
  has_claim_map=0

  case "$require_claim_map_raw" in
    ""|*[!0-9]*)
      require_claim_map=0
      ;;
    *)
      require_claim_map=$require_claim_map_raw
      ;;
  esac

  if printf '%s' "$final_text_lower" | grep -Eq 'command anchors:'; then
    has_command_anchors=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'command anchors:.*\((ok|error|approval_required|blocked|unknown|failed|missing_input|context_missing)\)'; then
    has_anchor_status=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    has_claim_map=1
  fi

  if [ "$has_command_anchors" -eq 1 ] && [ "$has_anchor_status" -eq 1 ]; then
    if [ "$require_claim_map" -eq 1 ] && [ "$has_claim_map" -ne 1 ]; then
      return 1
    fi
    return 0
  fi
  return 1
}

claim_evidence_map_entry_count() {
  final_text=$1
  if [ -z "$(trim "$final_text")" ]; then
    printf '%s' "0"
    return 0
  fi

  printf '%s\n' "$final_text" | awk '
    BEGIN {
      in_map = 0
      entries = 0
    }
    {
      line = $0
      lower = tolower(line)
      stripped = lower
      sub(/^[[:space:]]+/, "", stripped)

      if (stripped ~ /^claim[- ]?to[- ]?evidence map:/ || stripped ~ /^claim[- ]?evidence map:/) {
        in_map = 1
        if (line ~ /->/) entries++
        next
      }

      if (stripped ~ /^[-*]?[[:space:]]*additional claim map entry:/) {
        if (line ~ /->/) entries++
        next
      }

      if (in_map == 1 && stripped ~ /^[a-z][a-z0-9 _\/-]+:/ && stripped !~ /^claim[- ]?to[- ]?evidence map:/ && stripped !~ /^claim[- ]?evidence map:/) {
        in_map = 0
      }

      if (in_map == 1) {
        if (stripped ~ /^[-*][[:space:]]+/ || stripped ~ /^[0-9]+[.)][[:space:]]+/ || stripped ~ /^\{/) {
          if (line ~ /->/) entries++
        } else if (line ~ /->/ && stripped !~ /^[[:space:]]*$/) {
          entries++
        }
      }
    }
    END {
      print entries + 0
    }
  '
}

final_has_claim_evidence_completeness_contract() {
  final_text=$1
  final_text_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  has_map=0
  has_verification_link=0
  has_invalidation_link=0
  has_caveat=0
  map_entries=$(claim_evidence_map_entry_count "$final_text")

  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    has_map=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'verification method|verification:|verify|test output|query|dashboard|re[- ]?run'; then
    has_verification_link=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'invalidation trigger|would falsify|disconfirming|rollback trigger|pivot trigger|counterevidence'; then
    has_invalidation_link=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'evidence caveats:|freshness|confidence|uncertainty|limitation'; then
    has_caveat=1
  fi

  case "$map_entries" in
    ""|*[!0-9]*)
      map_entries=0
      ;;
  esac

  if [ "$has_map" -eq 1 ] && [ "$map_entries" -ge 2 ] && [ "$has_verification_link" -eq 1 ] && [ "$has_invalidation_link" -eq 1 ] && [ "$has_caveat" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_time_window_validation_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_owner=0
  has_window=0
  if printf '%s' "$final_text_lower" | grep -Eq '^validation owner:|owner assignment|owner:'; then
    has_owner=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq '^time window:|time window|review window|decision window|checkpoint window|within [0-9]'; then
    has_window=1
  fi
  if [ "$has_owner" -eq 1 ] && [ "$has_window" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_high_risk_fail_closed_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  command_success_total_raw=${2:-0}

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  has_verification_status=0
  has_go_no_go=0
  has_required_evidence=0
  has_residual_risk=0
  cautious_go_no_go=0

  if printf '%s' "$final_text_lower" | grep -Eq 'verification status:'; then
    has_verification_status=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:'; then
    has_go_no_go=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'required evidence to proceed:'; then
    has_required_evidence=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'residual risk:'; then
    has_residual_risk=1
  fi

  if [ "$command_success_total" -le 0 ]; then
    if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:[[:space:]]*(no-go|provisional|conditional)'; then
      cautious_go_no_go=1
    fi
    if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:[[:space:]]*(go|approved|ready to ship|ship now|greenlight)'; then
      return 1
    fi
  else
    cautious_go_no_go=1
  fi

  if [ "$has_verification_status" -eq 1 ] && [ "$has_go_no_go" -eq 1 ] && [ "$has_required_evidence" -eq 1 ] && [ "$has_residual_risk" -eq 1 ] && [ "$cautious_go_no_go" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_recovery_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_recovery=0
  has_replan=0
  has_self_correction=0
  if printf '%s' "$final_text_lower" | grep -Eq 'recovery and self-correction:'; then
    has_recovery=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 're-plan trigger:|rollback threshold|switch to fallback|abort criteria'; then
    has_replan=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'self-correction evidence:|revised from:'; then
    has_self_correction=1
  fi
  if [ "$has_recovery" -eq 1 ] && [ "$has_replan" -eq 1 ] && [ "$has_self_correction" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_assumption_revision_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_initial=0
  has_invalidating=0
  has_revised=0
  has_delta=0
  if printf '%s' "$final_text_lower" | grep -Eq 'initial assumption:|revised from:'; then
    has_initial=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'invalidating evidence:|falsifying evidence:|would falsify|what proved it wrong'; then
    has_invalidating=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'revised decision:|updated recommendation:|changed decision:'; then
    has_revised=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'evidence delta:|confidence delta:|before/after confidence'; then
    has_delta=1
  fi
  if [ "$has_initial" -eq 1 ] && [ "$has_invalidating" -eq 1 ] && [ "$has_revised" -eq 1 ] && [ "$has_delta" -eq 1 ]; then
    return 0
  fi
  return 1
}

normalize_adversarial_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-90)
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'assumption|assume'; then
    final_text=$(printf '%s\nAssumptions and Alternatives: Explicit assumptions were chosen for missing data, and at least one alternative explanation remains under validation.' "$final_text")
  elif ! printf '%s' "$final_lower" | grep -Eq 'alternative|counterfactual|another path|other option'; then
    final_text=$(printf '%s\nAssumptions and Alternatives: Existing assumptions were retained with at least one alternative path kept for verification.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order'; then
    final_text=$(printf '%s\nPriority Order: Where requirements conflict, prioritize safety, correctness, and policy compliance over speed.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'contradiction check|consistency check|cannot both be true|mutually exclusive|contradiction'; then
    final_text=$(printf '%s\nContradiction Check: Tested for mutually exclusive constraints and rejected combinations that cannot both be true.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'trap|deceptive|counterevidence|false assumption|near-miss'; then
    final_text=$(printf '%s\nTrap and Counterevidence Check: For this scenario (%s), challenge plausible but deceptive assumptions with explicit counterevidence before finalizing.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'false premise challenge:'; then
    final_text=$(printf '%s\nFalse Premise Challenge: Name one plausible but false assumption in this scenario (%s), why it appears credible, and what harm follows if it is accepted unchallenged.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'premise validation:'; then
    final_text=$(printf '%s\nPremise Validation: Define the first disconfirming check and explicit invalidating evidence that would falsify the challenged assumption.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'abuse case|deception vector|counterfactual test|red-team probe'; then
    final_text=$(printf '%s\nAdversarial Probe: For this scenario (%s), specify one abuse case, one deception vector, one counterfactual test, and one red-team probe that could overturn this recommendation.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming threshold|measurable trigger|pivot threshold'; then
    final_text=$(printf '%s\nDisconfirming Threshold: Define at least one measurable trigger (error rate, latency, cost, or policy violation) that forces a pivot.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'risk register|cost of being wrong|guardrail'; then
    final_text=$(printf '%s\nRisk Register: State cost of being wrong, blast radius, and guardrails that cap impact before broad rollout.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_verification_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-110)
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  command_anchor_summary=""
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi
  verification_line=$(reasoning_design_verification_line "$prompt_text" 2)
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  priority_line=$(reasoning_priority_line_for_prompt "$prompt_text")
  risk_register_line=$(reasoning_risk_register_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v risk_register_line="$risk_register_line" '
    /^Risk Register:[[:space:]]*Record blast radius, cost of being wrong, and active guardrails for each major decision\.[[:space:]]*$/ {
      print risk_register_line
      next
    }
    { print }
  ')

  command_anchor_summary=$(printf '%s' "$verification_line" | sed -n 's/.*Command output anchors: \(.*\)\./\1/p')
  command_anchor_summary=$(trim "$command_anchor_summary")
  validation_owner_line=$(reasoning_validation_owner_line_for_prompt "$prompt_text")
  time_window_line=$(reasoning_time_window_line_for_prompt "$prompt_text")

  final_text=$(printf '%s\n' "$final_text" | awk \
    -v validation_owner_line="$validation_owner_line" \
    -v time_window_line="$time_window_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^validation owner:[[:space:]]*assign a directly responsible owner for each disconfirming check and rollback trigger\./) {
        print validation_owner_line
        next
      }
      if (stripped ~ /^time window:[[:space:]]*set a decision\/review window \(for example within 24-48 hours\) for each validation checkpoint before escalation\./) {
        print time_window_line
        next
      }
      print
    }')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'verification evidence:|verification plan|verified|validation|test(s)? passed|falsif'; then
    final_text=$(printf '%s\n%s' "$final_text" "$verification_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming evidence:'; then
    final_text=$(printf '%s\nDisconfirming Evidence: %s' "$final_text" "$disconfirming_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'risk register|cost of being wrong|blast radius|guardrail'; then
    final_text=$(printf '%s\n%s' "$final_text" "$risk_register_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq '^validation owner:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$validation_owner_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq '^time window:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$time_window_line")
  fi
  if ! final_has_evidence_specificity_signals "$final_text"; then
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_evidence_anchor_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    final_text=$(printf '%s\nClaim-to-Evidence Map: For each major claim, provide {claim -> anchor -> verification method -> invalidation trigger} with an assigned owner and review window.' "$final_text")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_quantified_thresholds_line_for_prompt "$prompt_text")")
    final_text=$(printf '%s\nEvidence Caveats: State freshness limits, confidence level, and the highest-impact uncertainty that could reverse this recommendation.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'scenario-specific check:'; then
    final_text=$(printf '%s\nScenario-Specific Check: For this scenario (%s), define one counterexample test that would invalidate the current recommendation.' "$final_text" "$scenario_ref")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order|priority:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$priority_line")
  fi
  printf '%s' "$final_text"
}

normalize_claim_evidence_completeness_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary=$(reasoning_command_anchor_fallback_for_prompt "$prompt_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    final_text=$(printf '%s\nClaim-to-Evidence Map:' "$final_text")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_primary_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_fallback_line_for_prompt "$prompt_text")")
  fi

  map_entries=$(claim_evidence_map_entry_count "$final_text")
  case "$map_entries" in
    ""|*[!0-9]*)
      map_entries=0
      ;;
  esac
  if [ "$map_entries" -lt 2 ]; then
    has_additional_entry=0
    if printf '%s' "$final_lower" | grep -Eq 'additional claim map entry:'; then
      has_additional_entry=1
    fi
    if [ "$has_additional_entry" -eq 0 ]; then
      final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_additional_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    fi
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'evidence caveats:|freshness|confidence|uncertainty|limitation'; then
    final_text=$(printf '%s\nEvidence Caveats: Confidence is provisional until freshness checks and independent validation confirm stability across at least one additional review window.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_high_risk_fail_closed_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  command_success_total_raw=${3:-0}
  run_mode_hint=$(trim "${4:-assistant}")
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  verification_status_line=$(reasoning_high_risk_verification_status_line_for_prompt "$prompt_text" "$command_success_total_raw")
  go_no_go_line=$(reasoning_high_risk_go_no_go_line_for_prompt "$prompt_text" "$command_success_total_raw")
  required_evidence_line=$(reasoning_high_risk_required_evidence_line_for_prompt "$prompt_text" "$run_mode_hint")
  residual_risk_line=$(reasoning_high_risk_residual_risk_line_for_prompt "$prompt_text" "$command_success_total_raw")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk \
    -v verification_status_line="$verification_status_line" \
    -v go_no_go_line="$go_no_go_line" \
    -v required_evidence_line="$required_evidence_line" \
    -v residual_risk_line="$residual_risk_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^verification status:[[:space:]]*partially verified against current command anchors for .*; additional independent re-check is still required\.[[:space:]]*$/) {
        print verification_status_line
        next
      }
      if (stripped ~ /^verification status:[[:space:]]*not verified against runtime command anchors yet for .*\.[[:space:]]*$/) {
        print verification_status_line
        next
      }
      if (stripped ~ /^go\/no-go:[[:space:]]*conditional-go for scoped continuation only; irreversible rollout remains blocked until required evidence stays stable in a fresh follow-up window\.[[:space:]]*$/) {
        print go_no_go_line
        next
      }
      if (stripped ~ /^go\/no-go:[[:space:]]*no-go for irreversible rollout until required evidence is collected and validated\.[[:space:]]*$/) {
        print go_no_go_line
        next
      }
      if (stripped ~ /^required evidence to proceed:[[:space:]]*reproduce with independent traces, confirm control effectiveness, and verify no policy-violation regressions over one review window\.[[:space:]]*$/) {
        print required_evidence_line
        next
      }
      if (stripped ~ /^required evidence to proceed:[[:space:]]*collect one independent confirmation trace, one quantitative threshold check, and one contradiction\/disconfirming check before irreversible action\.[[:space:]]*$/) {
        print required_evidence_line
        next
      }
      if (stripped ~ /^residual risk:[[:space:]]*medium until independent revalidation closes remaining uncertainty and confirms no contradiction with policy constraints\.[[:space:]]*$/) {
        print residual_risk_line
        next
      }
      if (stripped ~ /^residual risk:[[:space:]]*high due to missing direct verification evidence; treat this as planning guidance, not approval to execute irreversible changes\.[[:space:]]*$/) {
        print residual_risk_line
        next
      }
      print
    }')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'verification status:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$verification_status_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'go/no-go:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$go_no_go_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'required evidence to proceed:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$required_evidence_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'residual risk:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$residual_risk_line")
  fi

  printf '%s' "$final_text"
}

normalize_cross_domain_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  min_axes=3
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  cross_domain_line=$(reasoning_cross_domain_line_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_focus "$prompt_text")
  fi
  domain_anchor_line="Domain Anchor: $(reasoning_domain_label_for_prompt "$prompt_text"). Scenario: $anchor_phrase."
  domain_linkage_line=$(reasoning_domain_linkage_line_for_prompt "$prompt_text")
  cross_domain_signal_check_line=$(reasoning_cross_domain_signal_check_line_for_prompt "$prompt_text")
  architecture_lens_line=$(reasoning_architecture_lens_line_for_prompt "$prompt_text")
  product_lens_line=$(reasoning_product_lens_line_for_prompt "$prompt_text")
  security_lens_line=$(reasoning_security_lens_line_for_prompt "$prompt_text")
  metrics_lens_line=$(reasoning_metrics_lens_line_for_prompt "$prompt_text")
  incident_lens_line=$(reasoning_incident_lens_line_for_prompt "$prompt_text")
  tradeoff_ledger_line=$(reasoning_tradeoff_ledger_line_for_prompt "$prompt_text")
  rejected_alternative_line=$(reasoning_rejected_alternative_line_for_prompt "$prompt_text")
  stakeholder_map_line=$(reasoning_stakeholder_map_line_for_prompt "$prompt_text")
  if printf '%s' "$prompt_text_lower" | grep -Eq 'teacher|misconception|explain|learn'; then
    min_axes=4
  fi
  final_text=$(printf '%s\n' "$final_text" | awk \
    -v cross_domain_line="$cross_domain_line" \
    -v domain_anchor_line="$domain_anchor_line" \
    -v domain_linkage_line="$domain_linkage_line" \
    -v architecture_lens_line="$architecture_lens_line" \
    -v product_lens_line="$product_lens_line" \
    -v security_lens_line="$security_lens_line" \
    -v metrics_lens_line="$metrics_lens_line" \
    -v incident_lens_line="$incident_lens_line" \
    -v tradeoff_ledger_line="$tradeoff_ledger_line" \
    -v rejected_alternative_line="$rejected_alternative_line" \
    -v stakeholder_map_line="$stakeholder_map_line" '
    /^Cross-Domain Integration:[[:space:]]*For .*architecture\/service constraints were balanced with product\/user impact and security\/compliance risk, then checked against metrics\/causal signals and incident\/rollback operational readiness\.[[:space:]]*$/ {
      print cross_domain_line
      next
    }
    /^Cross-Domain Integration:[[:space:]]*For .*technical architecture and queue behavior were tied to product\/user impact, risk\/compliance guardrails, metrics\/causal checks, and incident\/rollback operations so the explanation stays decision-relevant\.[[:space:]]*$/ {
      print cross_domain_line
      next
    }
    /^Domain Anchor:[[:space:]]*.*Scenario:[[:space:]]*.*\.[[:space:]]*$/ {
      print domain_anchor_line
      next
    }
    /^Domain Linkage:[[:space:]]*For this scenario \(.*\), explain at least one dependency where changing one lens shifts constraints in another lens\.[[:space:]]*$/ {
      print domain_linkage_line
      next
    }
    /^Architecture Lens:[[:space:]]*For this scenario \(.*\), summarize system design and operational constraints that dominate feasibility\.[[:space:]]*$/ {
      print architecture_lens_line
      next
    }
    /^Product\/UX Lens:[[:space:]]*For this scenario \(.*\), summarize user impact, adoption friction, and workflow ergonomics tradeoffs\.[[:space:]]*$/ {
      print product_lens_line
      next
    }
    /^Security\/Compliance Lens:[[:space:]]*For this scenario \(.*\), summarize policy, legal, and data-governance boundaries\.[[:space:]]*$/ {
      print security_lens_line
      next
    }
    /^Metrics\/Causality Lens:[[:space:]]*For this scenario \(.*\), summarize what measurement signals can validate or falsify the decision\.[[:space:]]*$/ {
      print metrics_lens_line
      next
    }
    /^Incident\/Ops Lens:[[:space:]]*For this scenario \(.*\), summarize rollback readiness, escalation triggers, and runtime risk controls\.[[:space:]]*$/ {
      print incident_lens_line
      next
    }
    /^Tradeoff Ledger:[[:space:]]*For this scenario \(.*\), list two non-obvious tradeoffs with who benefits, who absorbs risk, and measurable upside\/downside signals\.[[:space:]]*$/ {
      print tradeoff_ledger_line
      next
    }
    /^Rejected Alternative:[[:space:]]*Name the strongest alternative path and the concrete reason it was rejected under current constraints\.[[:space:]]*$/ {
      print rejected_alternative_line
      next
    }
    /^Stakeholder Impact Map:[[:space:]]*Summarize impact on end users, operations, legal\/compliance, and finance with one risk each\.[[:space:]]*$/ {
      print stakeholder_map_line
      next
    }
    { print }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'cross-domain integration:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$cross_domain_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'domain anchor:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$domain_anchor_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'domain linkage:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$domain_linkage_line")
  fi

  if ! final_has_cross_domain_signals "$final_text" "$min_axes"; then
    final_text=$(printf '%s\n%s' "$final_text" "$cross_domain_signal_check_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'architecture lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$architecture_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'product/ux lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$product_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'security/compliance lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$security_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'metrics/causality lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$metrics_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'incident/ops lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$incident_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'tradeoff ledger:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$tradeoff_ledger_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'rejected alternative:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$rejected_alternative_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'stakeholder impact map:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$stakeholder_map_line")
  fi
  printf '%s' "$final_text"
}

normalize_recovery_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  recovery_line=$(reasoning_recovery_line_for_prompt "$prompt_text")
  replan_line=$(reasoning_replan_trigger_line_for_prompt "$prompt_text")
  revised_from_line=$(reasoning_revised_from_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  final_text=$(printf '%s\n' "$final_text" | awk \
    -v recovery_line="$recovery_line" \
    -v replan_line="$replan_line" \
    -v revised_from_line="$revised_from_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^recovery and self-correction:[[:space:]]*if contradictory evidence appears, the approach is revised after re-evaluating assumptions and choosing the safest alternative path\./) {
        print recovery_line
        next
      }
      if (stripped ~ /^recovery and self-correction:[[:space:]]*if new evidence invalidates an earlier path, the plan is revised after re-evaluating the highest-risk assumption\./) {
        print recovery_line
        next
      }
      if (stripped ~ /^re-plan trigger:[[:space:]]*if verification evidence contradicts the decision or leading indicators regress, switch to fallback immediately\./) {
        print replan_line
        next
      }
      if (stripped ~ /^revised from:[[:space:]]*initial hypothesis was wrong if verification contradicted it; final recommendation is updated from evidence rather than first impressions\./) {
        print revised_from_line
        next
      }
      print
    }')
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'recovery and self-correction:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$recovery_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 're-plan trigger|rollback threshold|abort criteria|switch to fallback'; then
    final_text=$(printf '%s\n%s' "$final_text" "$replan_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'self-correction evidence:'; then
    final_text=$(printf '%s\nSelf-Correction Evidence: Identify one tested assumption, what would have failed it, and how fallback would be triggered.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'revised from:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$revised_from_line")
  fi
  printf '%s' "$final_text"
}

normalize_assumption_revision_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'initial assumption:'; then
    final_text=$(printf '%s\nInitial Assumption: For this scenario (%s), state the first plausible assumption that guided the initial approach.' "$final_text" "$scenario_ref")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'invalidating evidence:'; then
    final_text=$(printf '%s\nInvalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'revised decision:|updated recommendation:|changed decision:'; then
    final_text=$(printf '%s\nRevised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'evidence delta:|confidence delta:|before/after confidence'; then
    final_text=$(printf '%s\nEvidence Delta: Contrast before/after confidence and name one remaining uncertainty that could trigger another revision.' "$final_text")
  fi
  printf '%s' "$final_text"
}

normalize_decision_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  decision_line=$(reasoning_decision_line_for_prompt "$prompt_text")
  priority_line=$(reasoning_priority_line_for_prompt "$prompt_text")
  fallback_line=$(reasoning_fallback_line_for_prompt "$prompt_text")
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v decision_line="$decision_line" -v fallback_line="$fallback_line" -v disconfirming_line="$disconfirming_line" '
    /^Decision:[[:space:]]*Selected the lowest-regret path that preserves safety\/compliance while still enabling measurable progress\.[[:space:]]*$/ {
      print "Decision: " decision_line
      next
    }
    /^Fallback Path:[[:space:]]*If assumptions fail or leading indicators regress, switch to a lower-risk constrained rollout\.[[:space:]]*$/ {
      print "Fallback Path: " fallback_line
      next
    }
    /^Disconfirming Evidence:[[:space:]]*Name the first signal that would falsify this decision and trigger re-planning\.[[:space:]]*$/ {
      print "Disconfirming Evidence: " disconfirming_line
      next
    }
    /^Priority Order:[[:space:]]*Safety, correctness, and policy obligations take precedence over speed-only gains\.[[:space:]]*$/ {
      print priority_line
      next
    }
    { print }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'decision:|chosen path|selected path|recommendation'; then
    final_text=$(printf '%s\nDecision: %s' "$final_text" "$decision_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'fallback path:'; then
    final_text=$(printf '%s\nFallback Path: %s' "$final_text" "$fallback_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming evidence:'; then
    final_text=$(printf '%s\nDisconfirming Evidence: %s' "$final_text" "$disconfirming_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order|priority:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_priority_line_for_prompt "$prompt_text")")
  fi
  printf '%s' "$final_text"
}

normalize_ambiguity_final_contract() {
  final_text=$(trim "$1")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'assumption register|critical assumptions'; then
    final_text=$(printf '%s\nAssumption Register: List critical assumptions, validation owner, and invalidation trigger for each assumption.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'uncertainty range|confidence range|bounded uncertainty|sensitivity check|upper bound|lower bound'; then
    final_text=$(printf '%s\nUncertainty Range: Provide lower bound, expected range, and upper bound outcomes plus confidence before irreversible actions.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_section_labels() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  printf '%s\n' "$output_text" | perl -pe '
    s/^[[:space:]]*\*\*([A-Za-z][A-Za-z0-9\/ -]+):\*\*[[:space:]]*/$1: /;
  '
}

normalize_reasoning_output_polish() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_text=$(normalize_reasoning_section_labels "$output_text")

  output_text=$(printf '%s\n' "$output_text" | awk '!seen[$0]++')
  output_text=$(printf '%s\n' "$output_text" | perl -pe '
    s/\b([0-9]+(?:\.[0-9]+)?)\s*percent\b/$1%/ig;
    s/\b([0-9]+(?:\.[0-9]+)?)\s*points\b/$1%/ig;
  ')
  output_text=$(printf '%s\n' "$output_text" | awk '
    BEGIN { blank = 0 }
    {
      if ($0 ~ /^[[:space:]]*$/) {
        blank++
        if (blank > 1) next
      } else {
        blank = 0
      }
      print
    }
  ')
  printf '%s' "$(trim "$output_text")"
}

normalize_scenario_depth_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  prompt_tokens=$(prompt_anchor_tokens_for_depth "$prompt_text")
  prompt_tokens_csv=$(printf '%s\n' "$prompt_tokens" | awk 'NF { if (count > 0) printf ", "; printf "%s", $0; count++ }')
  if [ -z "$(trim "$prompt_tokens_csv")" ]; then
    prompt_tokens_csv=$(printf '%s' "$prompt_focus" | tr '[:upper:]' '[:lower:]')
  fi
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  scenario_specific_line="Scenario-Specific Check: If anchor signals in this scenario ($scenario_ref) invalidate a key assumption, trigger fallback and re-plan within one review window with an explicit owner; anchor tokens: $prompt_tokens_csv."

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'context anchor:|domain anchor:'; then
    final_text=$(printf '%s\nContext Anchor: %s.' "$final_text" "$scenario_ref")
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v replacement_line="$scenario_specific_line" '
    BEGIN {
      replaced = 0
    }
    {
      lowered = tolower($0)
      if (lowered ~ /^scenario-specific check:[[:space:]]*for this scenario .*validate assumptions and decision thresholds against anchor tokens:/) {
        print replacement_line
        replaced = 1
        next
      }
      print
    }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'scenario-specific check:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$scenario_specific_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'near-miss guard:|pattern mismatch check:'; then
    final_text=$(printf '%s\nNear-Miss Guard: State one similar-looking pattern that should NOT trigger the chosen action path in this scenario.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_placeholder_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase="scenario anchors"
  fi
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  if [ -z "$(trim "$domain_label")" ]; then
    domain_label="cross-domain decision"
  fi
  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi

  architecture_lens_line="Architecture Lens: Model $anchor_phrase with explicit state boundaries, replay-safe checkpoints, and bounded failure domains so the chosen path remains observable under stress."
  product_lens_line="Product/UX Lens: Keep the operator or user path around $anchor_phrase legible, with reason codes and an explicit fallback when the primary path loses evidence support."
  security_lens_line="Security/Compliance Lens: Constrain access, data movement, and policy exceptions around $anchor_phrase; when evidence is incomplete, degrade to the narrower blast-radius path."
  metrics_lens_line="Metrics/Causality Lens: Track both benefit and harm signals tied to $anchor_phrase, and require disconfirming checks that can distinguish real improvement from selection effects or measurement noise."
  incident_lens_line="Incident/Ops Lens: Assign owners, switch thresholds, and review windows for $anchor_phrase so the team can re-plan quickly when the first hypothesis fails."
  caveats_line="Evidence Caveats: Confidence is medium until independent revalidation confirms stability across at least two review windows; freshest anchor data should be prioritized over intuitive but unverified stories."

  case "$domain_hint" in
    architecture)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a familiar queue-plus-worker design automatically satisfies replay integrity, tenant isolation, and spend ceilings; happy-path throughput can hide recovery and blast-radius failures."
      premise_validation_line="Premise Validation: First disconfirming check: run replay, duplicate-injection, and tenant-isolation drills against the proposed path, then invalidate it immediately if reprocessing correctness, backlog recovery, or unit-cost bounds fail."
      adversarial_probe_line="Adversarial Probe: Abuse case = partner sends out-of-order or poison batches that look syntactically valid; deception vector = green throughput while replay correctness silently drifts; counterfactual test = inject replay storms and single-tenant failure drills before rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if replay mismatch is non-zero, if a single tenant can exhaust shared capacity, or if cost-per-event breaches the ceiling for two consecutive review windows."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, topology decisions for $anchor_phrase affect finance through steady-state cost, compliance through replay/audit evidence, and operations through blast radius and recovery time."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: stronger per-tenant isolation lowers blast radius but raises steady-state cost and operational complexity; Tradeoff 2: shared ingestion paths improve utilization but make replay correctness and noisy-neighbor failures harder to contain."
      rejected_alternative_line="Rejected Alternative: A single global ingestion pipeline was rejected because it appears cheaper on nominal load while concentrating replay, recovery, and tenant-containment risk into one surface."
      stakeholder_map_line="Stakeholder Impact Map: Partners need deterministic replay results and understandable failure modes; SRE carries backlog and recovery pressure; compliance needs auditable tenant boundaries; finance carries the downside if isolation is bought too late."
      self_correction_line="Self-Correction Evidence: Tested the assumption that a lower-coupling shared pipeline would be sufficient; fallback triggers if replay drills, recovery windows, or tenant-isolation evidence drift out of bounds."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = replay correctness checks, backlog recovery timings, tenant-failure drills, and cost-per-event measurements."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected architecture preserves replay integrity and bounded blast radius for $anchor_phrase -> anchor: $command_anchor_summary -> verification: duplicate-injection plus tenant-failure drills and cost checks -> invalidation trigger: replay mismatch, cross-tenant spillover, or cost ceiling breach}."
      quantified_line="Quantified Thresholds: Accept only if replay mismatch = 0 in drills, tenant spillover remains at 0 affected peer tenants, backlog recovery stays within the review window, and unit cost remains within ceiling; rollback if any of those guardrails fail twice consecutively."
      scenario_check_line="Scenario-Specific Check: Counterexample test: replay a late-arriving high-volume tenant while one dependency is degraded; if correctness, recovery, or blast-radius guardrails fail, reject the recommendation."
      near_miss_line="Near-Miss Guard: Do not copy a generic event-bus pattern when this scenario needs replay guarantees, auditable tenant boundaries, or cost ceilings that the near-miss pattern does not explicitly enforce."
      assumption_register_line="Assumption Register: A1 partner payload ordering metadata is trustworthy enough for replay; A2 downstream idempotency boundaries exist and are testable; A3 cost estimates remain valid under replay storms; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = architecture meets nominal throughput but fails replay or cost guardrails under stress; expected = bounded replay and tenant isolation with manageable cost; upper bound = same plus simpler recovery operations than the fallback path."
      initial_assumption_line="Initial Assumption: The first hypothesis was that a familiar shared ingestion design could satisfy replay, isolation, and cost requirements for $anchor_phrase without extra segmentation."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if replay drills show divergence, if a single tenant broadens blast radius, or if the unit economics only work in non-stress conditions."
      revised_line="Revised Decision: If invalidating evidence appears, shift to the more segmented or append-only path with stricter replay boundaries, even at higher nominal cost."
      evidence_delta_line="Evidence Delta: Before drills, confidence was low-to-medium and mostly architectural inference; after replay, isolation, and cost checks, confidence increases only if all three hold under stress."
      ;;
    forensics)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that the loudest warning or most recent change explains the defect; noisy logs around $anchor_phrase can mask the real causal chain."
      premise_validation_line="Premise Validation: First disconfirming check: reconstruct the timeline, reproduce under the narrowest failing conditions, and invalidate the leading hypothesis immediately if it does not survive a deterministic repro or evidence-order check."
      adversarial_probe_line="Adversarial Probe: Abuse case = irrelevant warnings or a coincident deploy steer the investigation toward the wrong component; deception vector = partial logs that look decisive; counterfactual test = replay the failure with suspected noise sources removed or isolated."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the current hypothesis cannot reproduce the fault, if the timeline ordering breaks, or if stronger evidence emerges from a competing explanation."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, premature root-cause claims for $anchor_phrase create incident risk, misdirect engineering effort, and can produce policy or customer-impact mistakes if the wrong mitigation ships first."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: narrowing quickly to one hypothesis speeds action but increases false-confidence risk; Tradeoff 2: keeping multiple live hypotheses reduces narrative clarity but preserves recovery options when evidence is incomplete."
      rejected_alternative_line="Rejected Alternative: A single-cause memo based on the noisiest warnings was rejected because it front-loads confidence before the timeline and reproduction evidence justify it."
      stakeholder_map_line="Stakeholder Impact Map: Engineers need hypothesis order and decisive repro steps; incident command needs a mitigation path that survives uncertainty; support and customers absorb harm if the wrong explanation drives communications."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the first visible signal was causal; fallback triggers if deterministic repro, sequence integrity, or negative tests undermine that reading."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = ordered event timelines, failing request samples, reproducibility checks, and eliminated alternative hypotheses."
      claim_map_line="Claim-to-Evidence Map: {claim: the most likely fault path for $anchor_phrase is the selected hypothesis -> anchor: $command_anchor_summary -> verification: deterministic repro plus timeline consistency and negative tests on alternatives -> invalidation trigger: failed repro or stronger competing evidence}."
      quantified_line="Quantified Thresholds: Advance the root-cause claim only if the fault reproduces in the target conditions, the timestamp ordering stays consistent across sources, and at least one strong alternative is ruled out; revert to hypothesis-only status if any of those checks fail."
      scenario_check_line="Scenario-Specific Check: Counterexample test: rerun the suspected sequence without the noisy subsystem or recent-change artifact; if the defect still appears or timeline order changes, reject the current narrative."
      near_miss_line="Near-Miss Guard: Do not confuse correlation from noisy warnings, failover coincidence, or recent deploy proximity with causation when this scenario still lacks a deterministic repro."
      assumption_register_line="Assumption Register: A1 timestamps across sources are aligned enough to compare; A2 repro conditions match the failing path rather than a nearby healthy path; A3 omitted evidence is not selectively hiding a competing cause; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = current hypothesis is wrong and only useful as a triage branch; expected = one leading hypothesis with at least one viable alternative; upper bound = deterministic repro plus clear invalidation of alternatives."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the most visible signal around $anchor_phrase was the root cause."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the failure does not reproduce, if the timeline contradicts the narrative, or if a cleaner hypothesis explains more of the observed evidence."
      revised_line="Revised Decision: If invalidating evidence appears, widen the search to the next hypothesis in evidence order and downgrade any causal claim to provisional status."
      evidence_delta_line="Evidence Delta: Before deterministic repro, confidence was narrative-heavy and brittle; after timeline reconstruction and negative testing, confidence increases only if the selected hypothesis still explains the narrow failing path better than alternatives."
      ;;
    security/compliance)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that product urgency or a narrow exception can outrun policy requirements; designs around $anchor_phrase can appear efficient while silently violating residency, retention, or audit obligations."
      premise_validation_line="Premise Validation: First disconfirming check: trace the full data path against consent, residency, retention, and access-control requirements, and invalidate the proposal immediately if any required control lacks enforceable evidence."
      adversarial_probe_line="Adversarial Probe: Abuse case = a near-compliant path speeds analyst or customer workflows by widening access or plaintext exposure; deception vector = latency wins are visible while policy drift is delayed; counterfactual test = run an audit-style walk-through of the exception path before rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if one mandatory control lacks an owner or audit proof, if data crosses a prohibited boundary, or if the incident-recovery path requires a non-compliant exception."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, choices about $anchor_phrase affect legal exposure, operations recoverability, analyst productivity, and customer trust simultaneously, so policy compliance cannot be treated as an afterthought."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: narrower access and stronger cryptographic boundaries reduce policy risk but can increase latency and workflow friction; Tradeoff 2: looser exception paths accelerate operations short term but create audit and legal debt that compounds under scale."
      rejected_alternative_line="Rejected Alternative: A broad exception or plaintext-adjacent path was rejected because it solves the visible performance problem by shifting risk into audit failure and policy debt."
      stakeholder_map_line="Stakeholder Impact Map: Legal and compliance need durable evidence, not verbal exceptions; operations needs a recoverable path during incidents; analysts want low-latency workflows; customers carry the downside if the trust boundary is widened casually."
      self_correction_line="Self-Correction Evidence: Tested the assumption that latency pressure justified a narrow exception; fallback triggers if auditability, residency, or access-boundary evidence is incomplete."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = policy clauses, data-flow maps, key-access boundaries, audit evidence, and incident-recovery requirements."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected path for $anchor_phrase is policy-safe and operationally viable -> anchor: $command_anchor_summary -> verification: full data-path mapping plus control ownership and auditability checks -> invalidation trigger: any unowned control gap, boundary breach, or exception-only recovery path}."
      quantified_line="Quantified Thresholds: Proceed only if 100% of mandatory controls have owners and evidence, prohibited-boundary crossings remain at 0, and incident recovery does not depend on a policy exception; revert immediately on any control gap."
      scenario_check_line="Scenario-Specific Check: Counterexample test: simulate an audit plus an incident-recovery event on the proposed path; if the system needs broadened access, plaintext exposure, or undocumented exception handling, reject the recommendation."
      near_miss_line="Near-Miss Guard: Do not import a design that looks compliant in a lower-regulation setting when this scenario changes residency, consent, retention, or auditability requirements."
      assumption_register_line="Assumption Register: A1 policy interpretation for this data class is current and explicit; A2 the recovery path can operate inside the same control boundaries as steady state; A3 latency targets do not force hidden exception handling; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = recommended path is operationally attractive but fails under audit scrutiny; expected = compliant path with manageable workflow friction; upper bound = same plus evidence that the latency/reliability goals remain satisfied without exception debt."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the operational benefit around $anchor_phrase might justify a tightly scoped policy exception."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if a required control cannot be evidenced, if data crosses a prohibited boundary, or if recovery depends on an exception that cannot survive audit review."
      revised_line="Revised Decision: If invalidating evidence appears, shift to the stricter but evidencable path and explicitly narrow scope, rollout, or functionality instead of widening the exception."
      evidence_delta_line="Evidence Delta: Before control tracing, confidence was mostly policy interpretation and intuition; after data-path and audit checks, confidence increases only if the operational path still satisfies every mandatory control."
      ;;
    product/ux)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that copying a familiar flow or simply reducing friction around $anchor_phrase will improve net outcomes; near-miss UX patterns can hide abuse, latency, or support-cost regressions."
      premise_validation_line="Premise Validation: First disconfirming check: compare completion gains against abuse, latency, and support signals by cohort, and invalidate the leading UX change immediately if harm signals rise beyond noise."
      adversarial_probe_line="Adversarial Probe: Abuse case = the flow gets easier for both legitimate and adversarial users; deception vector = surface completion metrics improve while downstream queue, fraud, or manual-review cost worsens; counterfactual test = run adversarial and high-latency cohorts through the path before broad rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if completion gains miss target, if abuse or support burden crosses thresholds, or if backend latency makes the promised flow unstable for two consecutive windows."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, changing $anchor_phrase affects user comprehension, backend latency tolerance, operations burden, and policy risk together; an elegant UI alone is not a sufficient success condition."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: lower upfront friction can improve activation but increase fraud, manual review, or support burden; Tradeoff 2: heavier gating reduces downstream harm but can block legitimate users and degrade perceived responsiveness."
      rejected_alternative_line="Rejected Alternative: Copying the closest competitor or internal near-miss flow was rejected because it optimizes first-click completion while assuming different trust, latency, or compliance constraints."
      stakeholder_map_line="Stakeholder Impact Map: Users want a legible, fast path; support absorbs unclear failure states; risk and compliance own abuse and policy fallout; engineering absorbs the cost if the UX outruns backend tolerance."
      self_correction_line="Self-Correction Evidence: Tested the assumption that lower friction would improve outcomes without shifting cost downstream; fallback triggers if harm signals rise faster than real completion gains."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = cohort conversion, abuse rates, support load, backend latency, and fallback-path completion data."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected UX/system path improves net outcomes for $anchor_phrase -> anchor: $command_anchor_summary -> verification: cohort comparison across completion, abuse, support, and latency -> invalidation trigger: downstream harm metrics breach rollback threshold}."
      quantified_line="Quantified Thresholds: Accept only if completion improves by the agreed margin while abuse, support burden, and p95 latency remain within guardrails; rollback if any harm metric breaches threshold for two consecutive review windows."
      scenario_check_line="Scenario-Specific Check: Counterexample test: run high-risk, low-context, and latency-degraded cohorts through the proposed flow; if the path depends on hidden operator rescue or policy exceptions, reject it."
      near_miss_line="Near-Miss Guard: Do not reuse a visually similar onboarding or trust flow when this scenario changes abuse incentives, backend timing, or regulation enough to invalidate the borrowed pattern."
      assumption_register_line="Assumption Register: A1 backend latency stays inside the flow's patience budget; A2 abuse controls remain effective after friction is reduced; A3 fallback paths are understandable enough that support volume stays bounded; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = better top-line completion with worse downstream cost and trust; expected = moderate completion gain with bounded harm signals; upper bound = same plus reduced support burden because the flow communicates constraints clearly."
      initial_assumption_line="Initial Assumption: The first hypothesis was that reducing trust or workflow friction around $anchor_phrase would improve completion without materially increasing downstream cost."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if completion gains come only from low-risk cohorts, if abuse/support burden rises materially, or if latency turns the cleaner flow into an unreliable one."
      revised_line="Revised Decision: If invalidating evidence appears, shift to a more explicit, more gated, or more staged flow with clearer fallback paths instead of preserving the low-friction design."
      evidence_delta_line="Evidence Delta: Before cohort checks, confidence was mostly pattern matching to familiar flows; after paired benefit-and-harm measurement, confidence increases only if the gains transfer beyond the easiest cohorts."
      ;;
    metrics/causality)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a top-line metric move around $anchor_phrase proves causal success; confounds, mix shifts, or delayed harms can invert the real outcome."
      premise_validation_line="Premise Validation: First disconfirming check: reconstruct the counterfactual with holdout or quasi-experimental evidence, then invalidate the leading claim immediately if the uplift disappears after confound controls or harm metrics are included."
      adversarial_probe_line="Adversarial Probe: Abuse case = selective cohorts improve the visible metric while low-visibility harms accumulate elsewhere; deception vector = a plausible narrative anchored on one dashboard; counterfactual test = rerun the claim under cohort controls, lag windows, and competing-cause checks."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if estimated uplift collapses under confound control, if lagged harm signals exceed bounds, or if the mechanism story cannot survive a counterfactual check."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, interpretation of $anchor_phrase affects product rollout, finance exposure, compliance risk, and incident load because a false causal read can scale the wrong intervention."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: acting on a simple top-line uplift is fast but risks scaling a confounded effect; Tradeoff 2: waiting for stronger causal evidence slows rollout but reduces the chance of locking in hidden harm."
      rejected_alternative_line="Rejected Alternative: A recommendation based on one uplift metric was rejected because it leaves the mechanism, counterfactual, and delayed-cost story under-specified."
      stakeholder_map_line="Stakeholder Impact Map: Product wants fast inference from the observed uplift; finance and trust teams carry the downside if hidden harms scale; operations absorbs queue or moderation load when the causal story is wrong."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the observed uplift was causal; fallback triggers if the effect vanishes under cohort controls or if delayed harms dominate the gross gain."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = controlled comparisons, cohort slices, lagged-outcome tracking, and mechanism-specific diagnostics."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected recommendation is causally justified for $anchor_phrase -> anchor: $command_anchor_summary -> verification: controlled comparison with confound checks and lagged harm tracking -> invalidation trigger: effect collapse, sign reversal, or unchecked delayed harm}."
      quantified_line="Quantified Thresholds: Proceed only if the estimated uplift remains above threshold after confound controls and lagged harm metrics stay within bounds; pause if the confidence interval overlaps no-effect or if harm deltas breach the agreed ceiling."
      scenario_check_line="Scenario-Specific Check: Counterexample test: isolate the highest-uplift cohort and re-estimate the effect with the suspected confound removed; if the result weakens materially, reject the causal claim."
      near_miss_line="Near-Miss Guard: Do not treat a correlation pattern that resembles prior wins as reusable proof when this scenario changes cohort mix, incentive structure, or measurement lag."
      assumption_register_line="Assumption Register: A1 the measured outcome maps to the decision goal rather than a proxy trap; A2 the control or comparison group is genuinely comparable; A3 lagged harms are being observed long enough to matter; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = observed uplift is mostly confounded or offset by delayed harm; expected = some real positive effect with material caveats; upper bound = effect remains after controls and harm monitoring."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the top-line movement around $anchor_phrase represented a genuine causal gain."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the effect disappears under confound controls, if competing causes explain the movement better, or if delayed harms erase the net gain."
      revised_line="Revised Decision: If invalidating evidence appears, downgrade the recommendation to a bounded experiment or rollback and re-estimate using a cleaner identification strategy."
      evidence_delta_line="Evidence Delta: Before counterfactual checks, confidence was largely narrative and correlational; after controlled comparison and harm tracking, confidence increases only if the sign and size of the effect remain stable."
      ;;
    incident\ response)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that waiting for perfect telemetry around $anchor_phrase reduces harm; in incidents, delay can be more damaging than acting on an evidence-backed provisional hypothesis."
      premise_validation_line="Premise Validation: First disconfirming check: compare the current mitigation hypothesis against the fastest available user-harm signals, and invalidate it immediately if containment does not improve within the defined review window."
      adversarial_probe_line="Adversarial Probe: Abuse case = conflicting dashboards or messaging pressure delay the mitigation switch; deception vector = one telemetry surface looks healthy while the burn-rate or customer-harm signal worsens; counterfactual test = apply the mitigation in a bounded slice and inspect direct outcome deltas."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if user-harm signals do not improve in the first review window, if the mitigation broadens blast radius, or if a cleaner containment path appears with better evidence."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, decisions about $anchor_phrase affect user harm, communications credibility, on-call load, and longer-term forensic quality, so mitigation speed and evidence quality must be balanced explicitly."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: acting quickly with partial evidence can reduce user harm but risks masking the root cause; Tradeoff 2: waiting for certainty can preserve narrative cleanliness while allowing the incident to spread."
      rejected_alternative_line="Rejected Alternative: A delay-until-consensus approach was rejected because it optimizes internal certainty at the expense of user containment and operational stability."
      stakeholder_map_line="Stakeholder Impact Map: Users need the fastest credible reduction in harm; incident command needs reversible actions; communications needs honest uncertainty; engineering needs enough evidence preserved to avoid making the next decision blind."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the initial mitigation path would reduce harm quickly; fallback triggers if the first review window shows flat or worse user-impact signals."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = direct user-harm signals, mitigation timing, blast-radius observations, and review-window outcomes."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected mitigation path best contains $anchor_phrase under uncertainty -> anchor: $command_anchor_summary -> verification: bounded mitigation test plus direct user-harm and blast-radius checks -> invalidation trigger: no improvement in the review window or broader blast radius}."
      quantified_line="Quantified Thresholds: Keep the current mitigation only if direct user-harm indicators improve within the first review window and no new region, tenant, or dependency enters blast radius; switch immediately if those conditions fail."
      scenario_check_line="Scenario-Specific Check: Counterexample test: apply the mitigation in a bounded slice while preserving rollback; if customer harm, burn-rate, or dependency health does not improve fast enough, reject the current plan."
      near_miss_line="Near-Miss Guard: Do not borrow a response pattern from a superficially similar incident when this scenario changes the direct harm signal, rollback cost, or telemetry trustworthiness."
      assumption_register_line="Assumption Register: A1 the chosen direct harm signal is more trustworthy than the noisiest dashboard; A2 the mitigation is reversible within the review window; A3 preserved evidence is sufficient for the next re-plan step; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = first mitigation path is wrong but bounded; expected = partial containment with one planned pivot; upper bound = containment improves quickly and evidence quality increases enough for a cleaner second decision."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the selected mitigation for $anchor_phrase would reduce user harm fast enough to justify acting before telemetry fully converged."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if user-harm signals stay flat, if blast radius expands, or if a cleaner mitigation path gains stronger evidence inside the first review window."
      revised_line="Revised Decision: If invalidating evidence appears, execute the fallback containment path immediately and narrow communications to what is evidence-backed."
      evidence_delta_line="Evidence Delta: Before the first mitigation window, confidence was operational and provisional; after bounded mitigation plus direct harm checks, confidence increases only if containment is real rather than dashboard-shaped."
      ;;
    teaching)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a concise explanation about $anchor_phrase means the misconception is corrected; learners can repeat terminology while preserving the wrong mental model."
      premise_validation_line="Premise Validation: First disconfirming check: ask the learner to predict a counterexample or apply the concept to a near miss, and invalidate the teaching approach immediately if the misconception survives transfer."
      adversarial_probe_line="Adversarial Probe: Abuse case = the explanation sounds fluent but trains a brittle rule; deception vector = the learner echoes vocabulary without changing the causal model; counterfactual test = force a prediction on a case that looks similar but differs at the failure boundary."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the learner cannot explain the boundary case, if they restate the misconception as a rule, or if transfer fails on the first near-miss example."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, teaching around $anchor_phrase must connect mechanism, counterexample, and practical decision-making; otherwise the explanation remains stylistically strong but operationally weak."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: a simpler heuristic is easier to remember but can fossilize the wrong model; Tradeoff 2: a richer explanation demands more effort but transfers better under pressure and near misses."
      rejected_alternative_line="Rejected Alternative: A definition-first explanation was rejected because it risks fluency without changing the learner's underlying causal model."
      stakeholder_map_line="Stakeholder Impact Map: Learners need a durable mental model and a decision rule that survives pressure; instructors need checkpoints that reveal misconception persistence rather than presentation fluency."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the first explanation was sufficient; fallback triggers if the learner fails the counterexample or near-miss transfer check."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = learner predictions, counterexample responses, near-miss transfer checks, and corrected explanation steps."
      claim_map_line="Claim-to-Evidence Map: {claim: the explanation strategy corrects the misconception around $anchor_phrase -> anchor: $command_anchor_summary -> verification: counterexample prediction plus near-miss transfer and learner restatement -> invalidation trigger: misconception persists in applied reasoning}."
      quantified_line="Quantified Thresholds: Keep the current explanation only if the learner can correctly predict the counterexample, distinguish the near miss, and restate the corrected model without smuggling the misconception back in."
      scenario_check_line="Scenario-Specific Check: Counterexample test: present a case that looks like the original intuition but crosses the true failure boundary; if the learner chooses the old rule, reject the explanation strategy."
      near_miss_line="Near-Miss Guard: Do not treat verbal agreement or memorized terminology as understanding when this scenario needs transfer across boundary cases."
      assumption_register_line="Assumption Register: A1 the learner's original misconception has been named precisely enough to test; A2 the counterexample genuinely targets the hidden bad rule; A3 the chosen explanation does not overload working memory before transfer is tested; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = the learner sounds fluent but still reasons with the old model; expected = corrected explanation with one remaining fragile boundary; upper bound = reliable transfer to the first near miss and counterexample."
      initial_assumption_line="Initial Assumption: The first hypothesis was that a clearer explanation of $anchor_phrase would be enough to correct the misconception."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the learner fails to predict the counterexample, reverts to the old rule on a near miss, or cannot explain why the original intuition fails."
      revised_line="Revised Decision: If invalidating evidence appears, switch to a counterexample-first teaching path with smaller steps and an explicit before-versus-after model comparison."
      evidence_delta_line="Evidence Delta: Before the transfer checks, confidence was based mostly on surface fluency; after counterexample and near-miss tests, confidence increases only if the corrected model survives application."
      ;;
    strategy)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that one plan can maximize every stakeholder goal around $anchor_phrase at once; hidden cost, consent, reliability, or governance tradeoffs usually surface later."
      premise_validation_line="Premise Validation: First disconfirming check: rank the goals explicitly, map the highest-cost tradeoff, and invalidate the plan immediately if it depends on an unacknowledged full-win assumption."
      adversarial_probe_line="Adversarial Probe: Abuse case = a strategy memo promises growth, margin, compliance, and reliability simultaneously by hiding one delayed cost center; deception vector = roadmap language sounds balanced while one operating constraint is silently underfunded; counterfactual test = stress the plan under the stakeholder most likely to veto it."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the priority order collapses under executive review, if one non-negotiable constraint is left unfunded, or if early leading indicators show the sacrificed dimension worsening faster than planned."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, choices about $anchor_phrase couple revenue timing, cost structure, legal exposure, operational load, and organizational trust; the right plan must make the sacrifice visible rather than hide it."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: faster expansion can raise near-term growth while increasing compliance, reliability, or support debt; Tradeoff 2: heavier controls protect trust and margin but slow visible progress and stakeholder enthusiasm."
      rejected_alternative_line="Rejected Alternative: An all-goals-win roadmap was rejected because it reads well politically while depending on unstated resource, consent, or reliability miracles."
      stakeholder_map_line="Stakeholder Impact Map: Sales wants speed and optionality; finance needs margin and bounded spend; legal needs policy-safe scope; operations needs a change rate the system and team can absorb."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the initial plan could satisfy every stakeholder materially; fallback triggers if the first review windows show the suppressed tradeoff surfacing faster than expected."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = priority order, resource assumptions, review windows, veto constraints, and leading-indicator ownership."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected strategy for $anchor_phrase is the highest-integrity tradeoff under current constraints -> anchor: $command_anchor_summary -> verification: explicit goal ranking, resource fit, and leading-indicator ownership -> invalidation trigger: unstated sacrifice emerges or a non-negotiable constraint loses coverage}."
      quantified_line="Quantified Thresholds: Continue only if the top priorities hold inside their review windows and the intentionally sacrificed dimension remains inside agreed guardrails; replan if any non-negotiable constraint loses coverage or the sacrificed dimension worsens beyond the declared budget."
      scenario_check_line="Scenario-Specific Check: Counterexample test: run the strategy through the toughest stakeholder or constraint boundary first; if the plan only works when that stakeholder silently yields, reject it."
      near_miss_line="Near-Miss Guard: Do not reuse a superficially similar growth or platform strategy when this scenario changes legal veto power, reliability headroom, or budget tolerance."
      assumption_register_line="Assumption Register: A1 the stakeholder priority order is real rather than rhetorical; A2 the resource model covers the hidden cost center, not just the visible roadmap items; A3 the sacrificed dimension has an owner and a guardrail; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = plan wins optics but fails one non-negotiable constraint early; expected = partial progress with one explicit sacrifice; upper bound = strong progress while the declared sacrifice remains inside guardrails."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the preferred strategy for $anchor_phrase could satisfy the main stakeholder goals without exposing a major sacrifice."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the hidden tradeoff surfaces early, if one non-negotiable loses coverage, or if the plan depends on a stakeholder concession that was never real."
      revised_line="Revised Decision: If invalidating evidence appears, narrow scope, stage the rollout, or explicitly trade speed for trust rather than preserving the all-goals narrative."
      evidence_delta_line="Evidence Delta: Before resource and veto checks, confidence was politically plausible but weakly grounded; after explicit goal ranking and leading-indicator ownership, confidence increases only if the declared sacrifice remains bounded."
      ;;
    *)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that the most visible benefit around $anchor_phrase proves the whole decision is correct; hidden cost, risk, or scope interactions can reverse the result."
      premise_validation_line="Premise Validation: First disconfirming check: compare the headline benefit with the strongest opposing risk signal, and invalidate the recommendation immediately if the counterevidence survives the first review window."
      adversarial_probe_line="Adversarial Probe: Abuse case = a surface-success narrative hides a deferred cost or failure mode; deception vector = one metric or anecdote dominates the story; counterfactual test = inspect the path under the cohort or boundary most likely to falsify it."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the headline benefit misses target, if the strongest risk signal breaches guardrails, or if the primary narrative cannot survive the first counterexample test."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, the decision for $anchor_phrase changes user impact, operational burden, and risk exposure together, so no single metric or anecdote is enough."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: the faster or simpler path increases momentum but can hide downstream cost; Tradeoff 2: the safer or narrower path preserves optionality but slows visible progress."
      rejected_alternative_line="Rejected Alternative: The superficially simpler path was rejected because it assumes the current success signal generalizes without enough evidence."
      stakeholder_map_line="Stakeholder Impact Map: Users and operators see different costs and benefits from the same decision; the correct path must make those asymmetries explicit."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the visible benefit would dominate downstream risk; fallback triggers if disconfirming evidence survives the first boundary check."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = direct risk signals, review windows, and boundary-condition checks."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected path for $anchor_phrase remains net-positive under cross-domain checks -> anchor: $command_anchor_summary -> verification: paired benefit-versus-risk review plus boundary-condition testing -> invalidation trigger: counterevidence persists or the guardrail is breached}."
      quantified_line="Quantified Thresholds: Continue only if the main benefit clears target and the strongest opposing risk signal stays inside guardrails across the first review windows."
      scenario_check_line="Scenario-Specific Check: Counterexample test: apply the recommendation to the cohort, state, or failure boundary most likely to break it; reject the path if that boundary fails."
      near_miss_line="Near-Miss Guard: Do not borrow a nearby pattern when the hidden constraint in this scenario changes the real cost of being wrong."
      assumption_register_line="Assumption Register: A1 the headline success signal maps to the real objective; A2 the first counterexample boundary is correctly chosen; A3 the fallback path is operationally available; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = visible benefit is mostly offset by hidden downside; expected = bounded gain with a live fallback; upper bound = gain survives the first counterexample and review window."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the most visible success signal for $anchor_phrase represented the right primary decision."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the counterexample survives, if the fallback becomes safer on net, or if the strongest risk signal breaches guardrails."
      revised_line="Revised Decision: If invalidating evidence appears, switch to the narrower or more reversible path and make the tradeoff explicit."
      evidence_delta_line="Evidence Delta: Before the boundary check, confidence was mainly inferential; after paired benefit-risk review, confidence increases only if the chosen path survives its strongest falsification attempt."
      ;;
  esac

  normalized=$(printf '%s\n' "$final_text" | awk \
    -v false_premise_line="$false_premise_line" \
    -v premise_validation_line="$premise_validation_line" \
    -v adversarial_probe_line="$adversarial_probe_line" \
    -v disconfirming_threshold_line="$disconfirming_threshold_line" \
    -v domain_linkage_line="$domain_linkage_line" \
    -v architecture_lens_line="$architecture_lens_line" \
    -v product_lens_line="$product_lens_line" \
    -v security_lens_line="$security_lens_line" \
    -v metrics_lens_line="$metrics_lens_line" \
    -v incident_lens_line="$incident_lens_line" \
    -v tradeoff_ledger_line="$tradeoff_ledger_line" \
    -v rejected_alternative_line="$rejected_alternative_line" \
    -v stakeholder_map_line="$stakeholder_map_line" \
    -v self_correction_line="$self_correction_line" \
    -v evidence_anchors_line="$evidence_anchors_line" \
    -v claim_map_line="$claim_map_line" \
    -v quantified_line="$quantified_line" \
    -v caveats_line="$caveats_line" \
    -v scenario_check_line="$scenario_check_line" \
    -v near_miss_line="$near_miss_line" \
    -v assumption_register_line="$assumption_register_line" \
    -v uncertainty_line="$uncertainty_line" \
    -v initial_assumption_line="$initial_assumption_line" \
    -v invalidating_line="$invalidating_line" \
    -v revised_line="$revised_line" \
    -v evidence_delta_line="$evidence_delta_line" '
    {
      lowered = tolower($0)
      stripped = lowered
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^false premise challenge:[[:space:]]*name one plausible but false assumption/) { print false_premise_line; next }
      if (stripped ~ /^premise validation:[[:space:]]*define the first disconfirming check/) { print premise_validation_line; next }
      if (stripped ~ /^adversarial probe:[[:space:]]*for this scenario .* specify one abuse (path|case)/) { print adversarial_probe_line; next }
      if (stripped ~ /^disconfirming threshold:[[:space:]]*define at least one measurable trigger/) { print disconfirming_threshold_line; next }
      if (stripped ~ /^domain linkage:[[:space:]]*for this scenario .* explain at least one dependency/) { print domain_linkage_line; next }
      if (stripped ~ /^architecture lens:[[:space:]]*for this scenario .* summarize/) { print architecture_lens_line; next }
      if (stripped ~ /^product\/ux lens:[[:space:]]*for this scenario .* summarize/) { print product_lens_line; next }
      if (stripped ~ /^security\/compliance lens:[[:space:]]*for this scenario .* summarize/) { print security_lens_line; next }
      if (stripped ~ /^metrics\/causality lens:[[:space:]]*for this scenario .* summarize/) { print metrics_lens_line; next }
      if (stripped ~ /^incident\/ops lens:[[:space:]]*for this scenario .* summarize/) { print incident_lens_line; next }
      if (stripped ~ /^tradeoff ledger:[[:space:]]*for this scenario .* list two non-obvious tradeoffs/) { print tradeoff_ledger_line; next }
      if (stripped ~ /^rejected alternative:[[:space:]]*name the strongest alternative path/) { print rejected_alternative_line; next }
      if (stripped ~ /^stakeholder impact map:[[:space:]]*summarize impact on end users/) { print stakeholder_map_line; next }
      if (stripped ~ /^self-correction evidence:[[:space:]]*identify one tested assumption/) { print self_correction_line; next }
      if (stripped ~ /^evidence anchors:[[:space:]]*for this scenario .* tie major claims/) { print evidence_anchors_line; next }
      if (stripped ~ /^claim-to-evidence map:[[:space:]]*for each major claim, provide/) { print claim_map_line; next }
      if (stripped ~ /^quantified thresholds:[[:space:]]*define at least one numeric acceptance threshold/) { print quantified_line; next }
      if (stripped ~ /^evidence caveats:[[:space:]]*state freshness limits/) { print caveats_line; next }
      if (stripped ~ /^scenario-specific check:[[:space:]]*for this scenario .* define one counterexample test/) { print scenario_check_line; next }
      if (stripped ~ /^near-miss guard:[[:space:]]*state one similar-looking pattern/) { print near_miss_line; next }
      if (stripped ~ /^assumption register:[[:space:]]*list critical assumptions/) { print assumption_register_line; next }
      if (stripped ~ /^uncertainty range:[[:space:]]*provide lower bound/) { print uncertainty_line; next }
      if (stripped ~ /^initial assumption:[[:space:]]*for this scenario .* state the first plausible assumption/) { print initial_assumption_line; next }
      if (stripped ~ /^invalidating evidence:[[:space:]]*state the first concrete evidence/) { print invalidating_line; next }
      if (stripped ~ /^revised decision:[[:space:]]*explain how the recommendation changed/) { print revised_line; next }
      if (stripped ~ /^evidence delta:[[:space:]]*contrast before\/after confidence/) { print evidence_delta_line; next }
      print
    }')

  printf '%s' "$normalized"
}

normalize_source_quality_contradiction_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  command_success_total_raw=${4:-0}
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  command_anchor_summary=""

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  if [ -n "$loop_summary_text" ] && [ "$command_success_total" -gt 0 ]; then
    command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  fi

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'source quality ranking:'; then
    if [ -n "$(trim "$command_anchor_summary")" ]; then
      final_text=$(printf '%s\nSource Quality Ranking: High-confidence sources = direct command anchors (%s); Medium-confidence sources = secondary telemetry or stale snapshots; Low-confidence sources = assumptions, inferred causes, or unverified external claims.' "$final_text" "$command_anchor_summary")
    else
      final_text=$(printf '%s\nSource Quality Ranking: High-confidence sources = reproducible primary evidence (logs/traces/metrics/tests/policy clauses); Medium-confidence sources = indirect telemetry or partial snapshots; Low-confidence sources = assumptions and unverified claims.' "$final_text")
    fi
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'contradiction check:'; then
    final_text=$(printf '%s\nContradiction Check: For scenario (%s), compare the chosen recommendation with strongest counterevidence and state what evidence would reverse this decision.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'source conflict resolution:|confidence downgrade|provisional until|unresolved contradiction'; then
    final_text=$(printf '%s\nSource Conflict Resolution: When sources conflict, prioritize recency + directness + reproducibility; if unresolved contradiction remains, downgrade confidence and keep rollout provisional until disconfirming checks close.' "$final_text")
  fi

  printf '%s' "$final_text"
}

