  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'The unresolved question is whether %s can stay operable under failover and replay stress without breaking tenant boundaries or cost limits.' "$anchor_phrase"
      ;;
    forensics)
      printf 'The unresolved question is which hypothesis around %s survives deterministic repro once the ordering conflict is cleaned up.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'The unresolved question is how much operational pressure around %s remains once the defensible control path is implemented correctly.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'The unresolved question is whether the current friction around %s buys real risk reduction or mostly delays honest users.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'The unresolved question is how much of the apparent effect around %s survives lagged-outcome checks and cleaner controls.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'The unresolved question is whether the apparent mitigation for %s actually reduces concentrated harm before the next burn window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'The unresolved question is whether the explanation for %s transfers once the wording changes and the first boundary case appears.' "$anchor_phrase"
      ;;
    strategy)
      printf 'The unresolved question is how much upside for %s survives once the likeliest veto and delayed downside are fully priced in.' "$anchor_phrase"
      ;;
    *)
      printf 'The unresolved question is whether the leading explanation for %s survives the next direct disconfirming check.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_reflection_for_prompt() {
  prompt_text=$1
  opening=$(reasoning_freeform_reflection_opening_sentence_for_prompt "$prompt_text")
  tension=$(reasoning_freeform_reflection_tension_sentence_for_prompt "$prompt_text")
  unresolved=$(reasoning_freeform_reflection_unresolved_sentence_for_prompt "$prompt_text")
  printf '%s %s %s' "$opening" "$tension" "$unresolved"
}

reasoning_freeform_frame_opening_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  printf 'This reads as a status picture for %s, not a settled decision request yet.' "$anchor_phrase"
}

reasoning_freeform_frame_moving_parts_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The key moving parts are replay ordering, merchant-specific retention, and failover recovery behavior.'
      ;;
    forensics)
      printf '%s' 'The key moving parts are timeline integrity, event ordering, and deterministic reproduction.'
      ;;
    security/compliance)
      printf '%s' 'The key moving parts are attributable access, residency boundaries, and deletion or retention guarantees.'
      ;;
    product/ux)
      printf '%s' 'The key moving parts are honest-user completion, review burden, and hidden abuse or support cost.'
      ;;
    metrics/causality)
      printf '%s' 'The key moving parts are lagged harm, cohort shape, and whether the visible lift survives cleaner controls.'
      ;;
    incident\ response)
      printf '%s' 'The key moving parts are concentrated user harm, dependency pressure, and rollback cost.'
      ;;
    teaching)
      printf '%s' 'The key moving parts are learner misconception, boundary cases, and whether the lesson transfers beyond the example.'
      ;;
    strategy)
      printf '%s' 'The key moving parts are near-term growth, reliability or margin budget, and the likeliest veto constraint.'
      ;;
    *)
      printf '%s' 'The key moving parts are the visible upside, the hidden downside, and the weakest piece of evidence.'
      ;;
  esac
}

reasoning_freeform_frame_offer_sentence() {
  printf '%s' 'If you want, I can turn that into a recommendation, risk review, or explanation.'
}

reasoning_freeform_frame_for_prompt() {
  prompt_text=$1
  opening=$(reasoning_freeform_frame_opening_sentence_for_prompt "$prompt_text")
  moving_parts=$(reasoning_freeform_frame_moving_parts_sentence_for_prompt "$prompt_text")
  offer=$(reasoning_freeform_frame_offer_sentence)
  printf '%s %s %s' "$opening" "$moving_parts" "$offer"
}

reasoning_freeform_clarifying_question_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Do you want a recommendation on %s, or are you just capturing architecture notes? If you want the call, I can give the safer design, main risk, and what would change it.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Do you want an investigation read on %s, or are you just recording forensics notes? If you want the call, I can give the leading hypothesis, biggest unknown, and what would falsify it.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Do you want a policy call on %s, or are you just recording constraints? If you want the call, I can give the safer path, main gap, and what evidence would justify changing it.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Do you want a recommendation on %s, or are you just capturing product notes? If you want the call, I can give the safer direction, main hidden cost, and what would change it.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Do you want a causality read on %s, or are you just recording metric notes? If you want the call, I can give the likely read, main confound, and what evidence would reverse it.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Do you want an incident recommendation on %s, or are you just recording status notes? If you want the call, I can give the containment path, main risk, and what would change it.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Do you want a teaching recommendation on %s, or are you just capturing notes? If you want the call, I can give the explanation approach, main misconception risk, and what would change it.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Do you want a strategy call on %s, or are you just recording stakeholder notes? If you want the call, I can give the direction, main tradeoff, and what would change it.' "$anchor_phrase"
      ;;
    *)
      printf 'Do you want a recommendation on %s, or are you just capturing notes? If you want the call, I can give the direction, main uncertainty, and what would change it.' "$anchor_phrase"
      ;;
  esac
}

reasoning_priority_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Priority Order: Preserve replay integrity, tenant isolation, and bounded recovery for %s before throughput or cost optimization.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Priority Order: Preserve evidence order and reproducibility for %s before fast root-cause storytelling.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Priority Order: Preserve policy boundaries, auditability, and least-privilege controls for %s before workflow acceleration.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Priority Order: Preserve user trust, compliance guardrails, and bounded abuse/support load for %s before completion gains.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Priority Order: Preserve causal validity and downside containment for %s before scaling uplift claims.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Priority Order: Reduce user harm and keep mitigation reversible for %s before waiting for perfect telemetry.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Priority Order: Correct the misconception and verify transfer for %s before optimizing fluency.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Priority Order: Make non-negotiables and real stakeholder ranking explicit for %s before speed or optics.' "$anchor_phrase"
      ;;
    *)
      printf 'Priority Order: Rank safety, correctness, and reversibility ahead of speed-only gains for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_risk_register_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Risk Register: Track replay divergence, cross-tenant spillover, backlog recovery drift, and cost-ceiling breach around %s.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Risk Register: Track false-cause lock-in, timeline inconsistency, noisy-log overfitting, and wrong-mitigation risk around %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Risk Register: Track policy-boundary breach, audit-proof gaps, exception creep, and recovery-path non-compliance around %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Risk Register: Track abuse-rate growth, support-load spillover, latency-driven abandonment, and hidden operator rescue around %s.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Risk Register: Track confound exposure, proxy-metric drift, lagged harm reversal, and over-scaling from weak causal evidence around %s.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Risk Register: Track customer-harm burn, mitigation blast-radius growth, rollback delay, and evidence-loss risk around %s.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Risk Register: Track misconception persistence, fluency-without-transfer, boundary-case failure, and overloaded instruction around %s.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Risk Register: Track hidden tradeoff debt, unfunded non-negotiables, stakeholder veto risk, and reliability/margin erosion around %s.' "$anchor_phrase"
      ;;
    *)
      printf 'Risk Register: Track blast radius, cost of being wrong, and live guardrails for the main decision around %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_evidence_anchor_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = replay correctness checks, tenant-failure drills, backlog recovery timings, and cost-per-event measurements for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = ordered timelines, deterministic repro steps, failing samples, and eliminated alternative hypotheses for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = policy clauses, data-flow maps, access boundaries, audit evidence, and recovery-path checks for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = cohort completion, abuse rates, support load, latency tails, and fallback-path completion for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = controlled comparisons, cohort slices, lagged-outcome tracking, and mechanism diagnostics for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = direct user-harm signals, mitigation timing, burn-rate windows, and blast-radius observations for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = learner predictions, counterexample responses, near-miss transfer checks, and corrected restatements for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = goal ranking, resource assumptions, veto constraints, review windows, and leading-indicator ownership for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = direct risk signals, review windows, and boundary-condition checks for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

reasoning_command_anchor_fallback_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'current command anchors plus replay, isolation, and cost-check snapshots for %s' "$anchor_phrase"
      ;;
    forensics)
      printf 'current command anchors plus timeline, repro, and alternative-hypothesis checkpoints for %s' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'current command anchors plus policy-control, audit, and data-boundary checkpoints for %s' "$anchor_phrase"
      ;;
    product/ux)
      printf 'current command anchors plus cohort, latency, abuse, and support checkpoints for %s' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'current command anchors plus controlled-comparison and lagged-harm checkpoints for %s' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'current command anchors plus direct-harm, mitigation-window, and blast-radius checkpoints for %s' "$anchor_phrase"
      ;;
    teaching)
      printf 'current command anchors plus learner-transfer, counterexample, and misconception checks for %s' "$anchor_phrase"
      ;;
    strategy)
      printf 'current command anchors plus review-window, resource-fit, and stakeholder-guardrail checkpoints for %s' "$anchor_phrase"
      ;;
    *)
      printf 'current command anchors plus boundary-condition checkpoints for %s' "$anchor_phrase"
      ;;
  esac
}

reasoning_quantified_thresholds_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Quantified Thresholds: Accept only if replay mismatch stays at 0, peer-tenant impact remains at 0 during failure drills, recovery stays within 30 min, and unit cost for %s stays within ceiling.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Quantified Thresholds: Advance the leading hypothesis only if %s reproduces in the failing conditions at least 1x, timeline-order contradictions stay at 0, and at least 1x strong alternative is ruled out.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Quantified Thresholds: Proceed only if 100%% of mandatory controls for %s have owners and evidence, prohibited-boundary crossings remain at 0, and recovery does not depend on undocumented exceptions.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Quantified Thresholds: Accept only if %s improves completion in at least 2 cohorts while abuse and support load stay within 10%% drift and p95 latency stays within 250 ms for 2 review windows.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Quantified Thresholds: Proceed only if the estimated effect for %s stays above 0%% after confound controls, the confidence interval excludes 0, and lagged-harm deltas remain at or below 0%% over 1 lag window.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Quantified Thresholds: Keep the current mitigation only if direct harm indicators tied to %s improve within 15 min and no new region, tenant, or dependency enters blast radius over 1 review window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Quantified Thresholds: Keep the current explanation only if the learner passes 2x transfer checks for %s, correctly predicts 1x counterexample, and distinguishes 1x near miss without reverting to the misconception.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Quantified Thresholds: Continue only if the top priorities tied to %s hold for 2x review checkpoints and the intentionally sacrificed dimension stays within 1x declared guardrail breach.' "$anchor_phrase"
      ;;
    *)
      printf 'Quantified Thresholds: Define concrete accept/reject thresholds with at least 1x primary benefit metric, 1x opposing risk metric, and 1x review checkpoint before irreversible action on %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_primary_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf -- '- Claim 1 (primary architecture choice): claim -> anchor: %s -> verification method: replay, tenant-failure, and cost drills for %s -> invalidation trigger: replay mismatch, peer-tenant spillover, or cost ceiling breach.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Claim 1 (leading hypothesis): claim -> anchor: %s -> verification method: deterministic repro plus timeline-consistency checks for %s -> invalidation trigger: failed repro or stronger competing evidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Claim 1 (policy-safe path): claim -> anchor: %s -> verification method: control ownership, data-boundary, and auditability checks for %s -> invalidation trigger: any unowned control gap or prohibited-boundary crossing.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Claim 1 (primary UX/system path): claim -> anchor: %s -> verification method: cohort comparison across completion, abuse, latency, and support load for %s -> invalidation trigger: downstream harm breaches rollback guardrails.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Claim 1 (causal recommendation): claim -> anchor: %s -> verification method: controlled comparison with confound checks and lagged-harm tracking for %s -> invalidation trigger: effect collapse, sign reversal, or delayed harm breach.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Claim 1 (current mitigation path): claim -> anchor: %s -> verification method: bounded mitigation test plus direct user-harm checks for %s -> invalidation trigger: no improvement in the review window or broader blast radius.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Claim 1 (teaching strategy): claim -> anchor: %s -> verification method: counterexample prediction and near-miss transfer checks for %s -> invalidation trigger: learner reverts to the misconception in applied reasoning.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Claim 1 (selected strategy): claim -> anchor: %s -> verification method: explicit goal ranking, resource-fit checks, and leading-indicator ownership for %s -> invalidation trigger: a non-negotiable loses coverage or the hidden tradeoff surfaces.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf -- '- Claim 1 (primary decision): claim -> anchor: %s -> verification method: rerun the same anchor checks plus one independent boundary-condition check for %s -> invalidation trigger: disconfirming evidence appears or the main guardrail breaches.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_fallback_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf -- '- Claim 2 (fallback isolation path): claim -> anchor: fallback rehearsal output and tenant-failure drills -> verification method: exercise segmented rollback and replay containment for %s -> invalidation trigger: fallback broadens blast radius or misses recovery window.' "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Claim 2 (fallback hypothesis path): claim -> anchor: eliminated-alternative log and next-hypothesis checklist -> verification method: run the next repro branch for %s in evidence order -> invalidation trigger: the fallback hypothesis also fails deterministic checks.' "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Claim 2 (fallback narrower rollout): claim -> anchor: segmented rollout plan and policy-control matrix -> verification method: verify the reduced-scope path for %s preserves control coverage and recoverability -> invalidation trigger: the fallback still needs policy exceptions.' "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Claim 2 (fallback gated path): claim -> anchor: fallback flow rehearsal and support playbook -> verification method: run high-risk and high-latency cohorts through the gated %s path -> invalidation trigger: fallback still exceeds abuse, support, or latency guardrails.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Claim 2 (fallback experiment path): claim -> anchor: control-policy baseline and revised experiment plan -> verification method: re-estimate %s with a cleaner identification strategy -> invalidation trigger: the fallback still cannot isolate the effect from confounds.' "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Claim 2 (fallback containment path): claim -> anchor: rollback rehearsal output and containment checklist -> verification method: execute the narrower mitigation for %s and compare direct harm signals -> invalidation trigger: fallback still fails the first review window.' "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Claim 2 (fallback counterexample-first path): claim -> anchor: revised lesson outline and learner checkpoint results -> verification method: retest %s with smaller diagnostic steps -> invalidation trigger: transfer still fails on the near miss.' "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Claim 2 (fallback phased plan): claim -> anchor: phased roadmap and review-window owners -> verification method: test whether the narrower %s plan preserves non-negotiables while sacrificing speed explicitly -> invalidation trigger: the phased path still overruns declared guardrails.' "$anchor_phrase"
      ;;
    *)
      printf -- '- Claim 2 (fallback safety): claim -> anchor: fallback rehearsal output and review-window checks -> verification method: execute fallback rehearsal for %s and compare risk/cost guardrails -> invalidation trigger: fallback cannot preserve the primary safety threshold.' "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_additional_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second replay/isolation checkpoint -> invalidation trigger: freshness decay, contradictory drill output, or boundary-condition failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second deterministic repro/timeline checkpoint -> invalidation trigger: contradictory trace order or failed repro downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second control-ownership/audit checkpoint -> invalidation trigger: stale policy evidence, contradictory control state, or audit gap downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second cohort/latency checkpoint -> invalidation trigger: contradictory harm metrics or fallback failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second controlled or lagged-outcome checkpoint -> invalidation trigger: confound exposure, sign reversal, or freshness decay downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second mitigation-review checkpoint -> invalidation trigger: contradictory harm signals, wider blast radius, or stale telemetry downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second transfer/counterexample checkpoint -> invalidation trigger: misconception relapse or boundary-case failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second review-window/owner checkpoint -> invalidation trigger: contradictory stakeholder signals, stale assumptions, or guardrail breach downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second independent checkpoint -> invalidation trigger: contradiction, freshness decay, or boundary-condition failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

compact_reasoning_contract_extract_value() {
  label=$1
  text=$2
  if [ -z "$(trim "$text")" ]; then
    return 0
  fi
  printf '%s\n' "$text" | awk -v label="$label" '
    BEGIN {
      prefix = tolower(label) ":"
    }
    {
      lowered = tolower($0)
      if (index(lowered, prefix) == 1) {
        line = $0
        sub(/^[^:]*:[[:space:]]*/, "", line)
        print line
        exit
      }
    }
  '
}

compact_reasoning_contract_lower_text() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

reasoning_contract_extract_value() {
  compact_reasoning_contract_extract_value "$@"
}

reasoning_contract_lower_text() {
  compact_reasoning_contract_lower_text "$1"
}

compact_reasoning_contract_value_is_placeholder() {
  label=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  value=$(compact_reasoning_contract_lower_text "$2")
  case "$value" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac
  case "$label" in
    outcome)
      :
      ;;
    initial\ assumption)
      if printf '%s' "$value" | grep -Eq '^for this scenario .*state the first plausible assumption'; then
        return 0
      fi
      ;;
    invalidating\ evidence)
      if printf '%s' "$value" | grep -Eq '^state the first concrete evidence'; then
        return 0
      fi
      ;;
    revised\ decision)
      if printf '%s' "$value" | grep -Eq '^explain how the recommendation changed'; then
        return 0
      fi
      ;;
    claim-to-evidence\ map)
      if printf '%s' "$value" | grep -Eq '^for each major claim, provide'; then
        return 0
      fi
      ;;
  esac
  return 1
}

compact_reasoning_contract_squash_value() {
  value=$1
  printf '%s' "$value" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

compact_reasoning_contract_reference_phrase_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_trimmed=$(trim "$anchor_phrase")
  if [ -n "$anchor_trimmed" ] && [ "$anchor_trimmed" != "scenario anchors" ] && [ "$anchor_trimmed" != "current scenario" ]; then
    printf '%s' "$anchor_trimmed"
    return 0
  fi
  printf '%s' "$scenario_ref"
}

compact_reasoning_followup_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'same labels|keep the same labels|same 5[- ]line|same five[- ]line|same format|same contract|same structure|same labeled lines|same five labeled lines|same short labeled lines|same plan|revise that same plan|revise the same plan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'revise|revised|revision|update|updated|pivot|changed|change explicit|make the revised|make the shift|show the pivot|spell out the pivot|what changed|overturned'; then
    return 1
  fi
  return 0
}

compact_reasoning_contract_value_needs_upgrade() {
  label=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  value=$2
  prompt_text=$3
  value_lower=$(compact_reasoning_contract_lower_text "$value")
  reference_phrase=$(compact_reasoning_contract_reference_phrase_for_prompt "$prompt_text")
  reference_lower=$(compact_reasoning_contract_lower_text "$reference_phrase")

  if compact_reasoning_contract_value_is_placeholder "$label" "$value"; then
    return 0
  fi

  case "$value_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac

  case "$label" in
    outcome|initial\ assumption|invalidating\ evidence|revised\ decision)
      if [ -n "$reference_lower" ] && ! printf '%s' "$value_lower" | grep -Fq "$reference_lower"; then
        return 0
      fi
      ;;
    claim-to-evidence\ map)
      if [ -n "$reference_lower" ] && ! printf '%s' "$value_lower" | grep -Fq "$reference_lower"; then
        return 0
      fi
      if ! printf '%s' "$value_lower" | grep -Eq 'owner:|assigned owner|validation owner'; then
        return 0
      fi
      if ! printf '%s' "$value_lower" | grep -Eq 'review window|time window|decision window|checkpoint'; then
        return 0
      fi
      ;;
  esac

  return 1
}

reasoning_compact_evidence_basis_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  case "$domain_hint" in
    architecture)
      evidence_basis=$(printf 'replay, tenant-isolation, and cost-drill evidence for %s' "$anchor_phrase")
      ;;
    forensics)
      evidence_basis=$(printf 'timeline reconstruction, deterministic repro, and eliminated-alternative checks for %s' "$anchor_phrase")
      ;;
    security/compliance)
      evidence_basis=$(printf 'control-ownership, auditability, and policy-boundary checks for %s' "$anchor_phrase")
      ;;
    product/ux)
      evidence_basis=$(printf 'cohort completion, abuse, support-load, and latency evidence for %s' "$anchor_phrase")
      ;;
    metrics/causality)
      evidence_basis=$(printf 'same-cohort lift, refund, cancellation, and queue-age evidence for %s' "$anchor_phrase")
      ;;
    incident\ response)
      evidence_basis=$(printf 'direct-harm, blast-radius, and mitigation-window evidence for %s' "$anchor_phrase")
      ;;
    teaching)
      evidence_basis=$(printf 'counterexample, near-miss, and learner-restatement evidence for %s' "$anchor_phrase")
      ;;
    strategy)
      evidence_basis=$(printf 'goal-ranking, guardrail, and veto-constraint evidence for %s' "$anchor_phrase")
      ;;
    *)
      evidence_basis=$(printf 'primary evidence and boundary-condition checks for %s' "$anchor_phrase")
      ;;
  esac
  if [ -n "$(trim "$followup_delta")" ]; then
    printf '%s after reassessing the change set: %s' "$evidence_basis" "$followup_delta"
  else
    printf '%s' "$evidence_basis"
  fi
}

reasoning_compact_owner_clause_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'platform or SRE owner before broad rollout'
      ;;
    forensics)
      printf 'incident or debugging owner in the current investigation window'
      ;;
    security/compliance)
      printf 'security control owner plus compliance reviewer before rollout'
      ;;
    product/ux)
      printf 'product owner with risk/support counterparts before expansion'
      ;;
    metrics/causality)
      printf 'decision owner plus analytics lead before scaling'
      ;;
    incident\ response)
      printf 'incident commander plus service owner in the first mitigation window'
      ;;
    teaching)
      printf 'instructor or reviewer before misconception closure'
      ;;
    strategy)
      printf 'strategy owner with finance/legal/operations counterparts before commitment'
      ;;
    *)
      printf 'directly responsible owner before irreversible action'
      ;;
  esac
}

reasoning_compact_review_window_clause_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'next replay and isolation stress window before any traffic increase'
      ;;
    forensics)
      printf 'current investigation window with one independent confirmation pass'
      ;;
    security/compliance)
      printf 'before rollout and before any recovery exception is exercised'
      ;;
