reasoning_outcome_stub_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  domain_article=$(reasoning_indefinite_article_for_phrase "$domain_label")
  if [ -n "$(trim "$anchor_phrase")" ] && [ "$scenario_ref" != "$anchor_phrase" ]; then
    printf 'Delivered %s %s decision synthesis for %s, grounded in %s.' "$domain_article" "$domain_label" "$scenario_ref" "$anchor_phrase"
    return 0
  fi
  printf 'Delivered %s %s decision synthesis for %s.' "$domain_article" "$domain_label" "$scenario_ref"
}

reasoning_decision_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Selected the architecture that protects %s before latency/cost optimization.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Selected the forensics path that tests %s in evidence order before root-cause claims.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Selected the policy-safe plan that secures %s before workflow acceleration.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Selected the UX/system path that balances %s against abuse and support-risk growth.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Selected the causal path that stress-tests %s against confounds and counterfactuals.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Selected the mitigation sequence that contains %s and minimizes user harm under uncertainty.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Selected the explanation strategy that corrects misconceptions around %s before abstraction.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Selected the staged strategy that makes speed-versus-risk tradeoffs explicit for %s.' "$anchor_phrase"
      ;;
    *)
      printf 'Selected a defensible primary path with explicit tradeoffs around %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_fallback_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'If %s signals drift out of bounds, switch to the lower-coupling architecture tier.' "$anchor_phrase"
      ;;
    forensics)
      printf 'If %s tests fail disconfirming checks, pivot to the next hypothesis and widen evidence capture.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'If %s controls show policy or audit drift, revert to segmented rollout with stricter boundaries.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'If %s gains come with abuse/support overload, revert to a more gated onboarding path.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'If %s uplift disappears under confound controls, revert to control policy and re-estimate causal effects.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'If mitigation around %s misses the burn-rate trigger window, execute rollback and containment immediately.' "$anchor_phrase"
      ;;
    teaching)
      printf 'If misconception checks for %s still fail, switch to counterexample-first instruction with smaller diagnostic steps.' "$anchor_phrase"
      ;;
    strategy)
      printf 'If margin, consent, or reliability thresholds tied to %s miss, shift to a phased plan prioritizing risk controls.' "$anchor_phrase"
      ;;
    *)
      printf 'If leading indicators tied to %s regress, switch to the lower-risk alternative path with smaller blast radius.' "$anchor_phrase"
      ;;
  esac
}

reasoning_disconfirming_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Trigger a pivot if evidence around %s invalidates replay integrity, tenant isolation, or cost-per-transaction bounds.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Trigger a pivot when evidence around %s fails deterministic repro or log-chain consistency checks.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Trigger a pivot on policy violations, audit gaps, or scope creep tied to %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Trigger a pivot if %s improvements coincide with abuse or support burden crossing thresholds.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Trigger a pivot if %s uplift fails controlled experiments or counterfactual checks within confidence bounds.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Trigger a pivot if user-impact or error-budget burn linked to %s fails to improve in the first mitigation window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Trigger a pivot if learners still fail contradiction checks after counterexamples on %s.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Trigger a pivot if strategy indicators tied to %s cross pre-set margin, compliance-risk, or reliability thresholds.' "$anchor_phrase"
      ;;
    *)
      printf 'Trigger a pivot when evidence around %s invalidates a core assumption.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_recommendation_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Use the lower-coupling architecture for %s rather than a single shared path.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Treat %s as an evidence-order investigation, not a confirmed root cause.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Take the policy-safe path for %s rather than expanding access or exceptions for speed.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Keep the more constrained product path for %s until the upside is proven without hidden harm.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Treat %s as a provisional signal, not a scale-up decision yet.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Use the containment path for %s that cuts direct harm fastest, even if it looks less calm externally.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Teach %s with a counterexample-first explanation rather than a fluent summary.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Take the staged strategy for %s and make the sacrifice explicit now.' "$anchor_phrase"
      ;;
    *)
      printf 'Take the lower-risk path for %s until the uncertain parts are better evidenced.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_rationale_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The simpler-looking option concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The fastest narrative is not yet the best-supported explanation once timeline quality and deterministic repro are considered.'
      ;;
    security/compliance)
      printf '%s' 'The faster path leaves auditability, residency, or deletion guarantees too weak to defend later.'
      ;;
    product/ux)
      printf '%s' 'The cleaner-looking flow can improve completion while quietly pushing abuse, review load, or support costs upward.'
      ;;
    metrics/causality)
      printf '%s' 'The visible lift can still be partly confounded or offset by delayed harm in refunds, churn, or queue age.'
      ;;
    incident\ response)
      printf '%s' 'A calmer-looking option can still let concentrated user harm and blast radius persist.'
      ;;
    teaching)
      printf '%s' 'The learner can sound correct while still carrying the old rule into the first near miss.'
      ;;
    strategy)
      printf '%s' 'The superficially ambitious plan hides at least one delayed cost or veto constraint.'
      ;;
    *)
      printf '%s' 'The optimistic reading still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_anchor_phrase_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(trim "$anchor_phrase")
  anchor_phrase_lower=$(printf '%s' "$anchor_phrase" | tr '[:upper:]' '[:lower:]')
  if prompt_prefers_freeform_frame "$prompt_text" && printf '%s' "$anchor_phrase_lower" | grep -Eq '^(current picture:|current state:|status:|for context:|snapshot:|today:|what we know:)'; then
    anchor_phrase=""
  fi
  if [ -n "$anchor_phrase" ]; then
    printf '%s' "$anchor_phrase"
    return 0
  fi
  reasoning_prompt_anchor_phrase "$prompt_text"
}

reasoning_freeform_uncertainty_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'The main uncertainty is whether %s can stay correct under failover and replay stress without blowing the cost envelope.' "$anchor_phrase"
      ;;
    forensics)
      printf 'The main uncertainty is which hypothesis survives deterministic repro once the trace conflicts around %s are cleaned up.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'The main uncertainty is how much operational friction remains once the tighter control path for %s is implemented correctly.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'The main uncertainty is whether the current friction around %s is buying real risk reduction or only delaying honest users.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'The main uncertainty is how much of the observed effect around %s survives lagged-outcome checks and cleaner controls.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'The main uncertainty is whether the chosen mitigation for %s actually reduces concentrated harm before the next burn window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'The main uncertainty is whether the explanation for %s transfers once the wording changes and the boundary case arrives.' "$anchor_phrase"
      ;;
    strategy)
      printf 'The main uncertainty is how much upside for %s survives once the most likely stakeholder veto and delayed downside are priced in.' "$anchor_phrase"
      ;;
    *)
      printf 'The main uncertainty is whether the leading explanation for %s survives the next direct disconfirming check.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_reversal_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'I would reverse this only if replay drills show %s can preserve merchant boundaries, retention rules, and recovery behavior without breaching the cost ceiling.' "$anchor_phrase"
      ;;
    forensics)
      printf 'I would reverse this only if a competing hypothesis gains cleaner timeline, reproduction, and log-chain support than the current lead for %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'I would reverse this only if attributable logs, residency boundaries, and deletion or retention proofs stay intact while the faster path still meets the target for %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'I would reverse this only if cohort data shows %s improves while abuse, support volume, and latency all stay inside guardrails.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'I would reverse this only if controlled or same-cohort checks keep the upside for %s while downstream harm signals stay bounded.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'I would reverse this only if the current path for %s fails to improve harm or burn-rate signals in the first mitigation window and the fallback materially reduces exposure.' "$anchor_phrase"
      ;;
    teaching)
      printf 'I would reverse this only if the learner can handle the near miss for %s and restate the corrected rule without leaning on memorized phrasing.' "$anchor_phrase"
      ;;
    strategy)
      printf 'I would reverse this only if the faster plan for %s clears margin, compliance, and reliability thresholds without borrowing risk into a later quarter.' "$anchor_phrase"
      ;;
    *)
      printf 'I would reverse this only if the next direct evidence check invalidates the current recommendation for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_delta_sentence_for_prompt() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Updated conditions:$'; then
    return 0
  fi
  followup_delta=$(reasoning_freeform_followup_delta_for_prompt "$prompt_text")
  [ -n "$(trim "$followup_delta")" ] || return 0
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  fi
  printf 'Given the updated conditions for %s, especially %s, the revised recommendation should be read against that new evidence rather than the first-pass intuition.' "$anchor_phrase" "$followup_delta"
}

reasoning_freeform_memo_for_prompt() {
  prompt_text=$1
  recommendation=$(reasoning_freeform_recommendation_sentence_for_prompt "$prompt_text")
  rationale=$(reasoning_freeform_rationale_sentence_for_prompt "$prompt_text")
  delta_sentence=$(reasoning_freeform_delta_sentence_for_prompt "$prompt_text")
  uncertainty=$(reasoning_freeform_uncertainty_sentence_for_prompt "$prompt_text")
  reversal=$(reasoning_freeform_reversal_sentence_for_prompt "$prompt_text")
  if [ -n "$(trim "$delta_sentence")" ]; then
    printf '%s %s %s %s %s' "$recommendation" "$rationale" "$delta_sentence" "$uncertainty" "$reversal"
    return 0
  fi
  printf '%s %s %s %s' "$recommendation" "$rationale" "$uncertainty" "$reversal"
}

reasoning_freeform_reflection_opening_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  printf 'This looks less settled than it first appears for %s.' "$anchor_phrase"
}

reasoning_freeform_reflection_tension_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The tension is that the simpler-looking shape concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The tension is that the cleanest first story can still be the least reliable once timeline quality and deterministic repro are tested.'
      ;;
    security/compliance)
      printf '%s' 'The tension is that the faster-looking path weakens auditability, residency, or deletion guarantees exactly where later scrutiny will land.'
      ;;
    product/ux)
      printf '%s' 'The tension is that the smoother-looking flow can improve visible completion while quietly moving cost into abuse, review load, or support burden.'
      ;;
    metrics/causality)
      printf '%s' 'The tension is that the visible lift can still be partly confounded or offset by delayed harm that arrives after the headline metric.'
      ;;
    incident\ response)
      printf '%s' 'The tension is that the calmer-looking move can still leave concentrated harm and blast radius untouched during the next burn window.'
      ;;
    teaching)
      printf '%s' 'The tension is that the material can feel anonymized and still teach the wrong lesson once the first near miss shows up.'
      ;;
    strategy)
      printf '%s' 'The tension is that the ambitious-looking upside is arriving alongside at least one delayed veto, cost, or reliability constraint.'
      ;;
    *)
      printf '%s' 'The tension is that the first clean story still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_reflection_unresolved_sentence_for_prompt() {
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

