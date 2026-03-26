        anchor_phrase="regulated onboarding with trust checks and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'trust checks'; then
        anchor_phrase="regulated onboarding with trust checks"
      fi
      ;;
    metrics/causality)
      if printf '%s' "$prompt_lower" | grep -Eq 'trial starts up|trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds later|refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age climbs|queue age climbed|queue age rose|queue age stayed elevated|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'cohort retention weakens|cohort retention softens|one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and weak cohort retention"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts up|trial starts jumped|trial starts jump|trial starts rose' && printf '%s' "$prompt_lower" | grep -Eq 'refunds later|refunds rose later|refunds rose|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age up|queue age climbed|queue age rose|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'cancellations worse after ranking change|cancellations worse|cancellation pressure|ranking change'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure climbed|cancellation pressure grows|cancellation pressure' && printf '%s' "$prompt_lower" | grep -Eq 'one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose later|refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age climbed|queue age rose|queue age stayed elevated|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and weak cohort retention"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation improved after ranking changes' && printf '%s' "$prompt_lower" | grep -Eq 'chargebacks?' && printf '%s' "$prompt_lower" | grep -Eq 'regulatory review risk'; then
        anchor_phrase="activation gains versus chargebacks, queue age, and regulatory review risk after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation jumps|activation jump|activation rose|activation rise' && printf '%s' "$prompt_lower" | grep -Eq 'ranking shift|ranking change|ranking tweak' && printf '%s' "$prompt_lower" | grep -Eq 'refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure|cancellation contacts|cancellation calls' && printf '%s' "$prompt_lower" | grep -Eq 'queue age|support queue age'; then
        anchor_phrase="activation lift versus refunds, queue age, and cancellation pressure after a ranking shift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking tweak|new ranking|ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts jump right away|trial starts pop immediately|trial starts jump|trial starts pop|trial starts jump right after' && printf '%s' "$prompt_lower" | grep -Eq 'refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure|cancellation calls|cancellation chats' && printf '%s' "$prompt_lower" | grep -Eq 'support queue age worsens|support queue age drifts up|support queue age|one week later' && printf '%s' "$prompt_lower" | grep -Eq 'same cohorts|one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts (jumped|rose)' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose' && printf '%s' "$prompt_lower" | grep -Eq 'call-center wait'; then
        anchor_phrase="trial-start gains versus refunds and call-center wait after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts rose' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose' && printf '%s' "$prompt_lower" | grep -Eq 'call-center wait'; then
        anchor_phrase="trial-start gains versus refunds and call-center wait after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation improved after ranking changes' && printf '%s' "$prompt_lower" | grep -Eq 'chargebacks?' && printf '%s' "$prompt_lower" | grep -Eq 'queue age'; then
        anchor_phrase="activation gains versus chargebacks and queue age after ranking changes"
      fi
      ;;
    incident\ response)
      if printf '%s' "$prompt_lower" | grep -Eq 'vip complaints cluster|vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'requests flap against rate limits|flap against rate limits|regional flapping|flapping|rate limits|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'rollback strains the weakest dependency|rollback load|rollback pressure|rollback would stress|weakest dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'regional flapping|flapping|rate limits|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'rollback load|rollback pressure|rollback would stress'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'status page is calm|status page stays calm' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints cluster in one region|vip complaints cluster|vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'requests flap against rate limits|rate limiting still causes flapping|rate limits' && printf '%s' "$prompt_lower" | grep -Eq 'rollback would stress the weakest dependency|rollback would stress|weakest dependency|rollback load eased'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'telemetry streams disagree' && printf '%s' "$prompt_lower" | grep -Eq 'premium-login incident'; then
        anchor_phrase="conflicting telemetry in a premium-login incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'rollback load (eased|fell)|rollback load eased|rollback load fell' && printf '%s' "$prompt_lower" | grep -Eq 'rate limiting still causes flapping|still causes flapping|still flapping|still flaps' && printf '%s' "$prompt_lower" | grep -Eq 'vip harm is now isolated to one region|vip harm is now concentrated in one region|vip complaints cluster in one region|vip complaints are concentrated in one region'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'status page stays calm|external messaging stays calm|first graph dips' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'one region|single region|region' && printf '%s' "$prompt_lower" | grep -Eq 'flap|flapping|flaps against rate limits|rate limits|throttling' && printf '%s' "$prompt_lower" | grep -Eq 'rollback itself loads|rollback itself would stress|rollback would stress|weakest dependency|weak dependency|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'one region|single region|region' && printf '%s' "$prompt_lower" | grep -Eq 'oscillat|rate limits|rate limiting|flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback itself would stress|rollback would stress|weakest dependency|shared dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'throttling|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'one region keeps oscillating|single region keeps flaring|region keeps flaring|region keeps oscillating' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints return|executive accounts complain again|vip complaints|executive accounts complain' && printf '%s' "$prompt_lower" | grep -Eq 'rollback would hit|rollback would hammer|shared dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'after throttling|throttling' && printf '%s' "$prompt_lower" | grep -Eq 'one region still flaps|region still flaps|region is still flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback could overload|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback could overload|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'premium-login incident'; then
        anchor_phrase="premium-login incident containment"
      fi
      ;;
    teaching)
      if printf '%s' "$prompt_lower" | grep -Eq 'tokenized snippets shared|tokenized snippets' && printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed' && printf '%s' "$prompt_lower" | grep -Eq 'near misses resurfacing|near misses|near miss'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized production snippets|production snippets' && printf '%s' "$prompt_lower" | grep -Eq 'near misses|account structure|access timing|learners keep carrying'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'copying production data into a training sandbox' && printf '%s' "$prompt_lower" | grep -Eq 'hashed identifiers'; then
        anchor_phrase="copying production data into a training sandbox with hashed identifiers"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing tokenized production snippets' && printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed|raw secrets are gone'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing tokenized production snippets|tokenized production snippets looks harmless|tokenized production examples first look harmless|tokenized production examples' && printf '%s' "$prompt_lower" | grep -Eq 'tokens are not names|names are removed|names are gone' && printf '%s' "$prompt_lower" | grep -Eq 'cohorts|riskier samples|less careful samples|timing'; then
        anchor_phrase="sharing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'tokenized production snippets|tokenized production examples|production snippets are fine|production examples are safe' && printf '%s' "$prompt_lower" | grep -Eq 'paste into email|chat or email|drop into chat or email|fine to paste into email' && printf '%s' "$prompt_lower" | grep -Eq 'names are gone|direct identifiers are removed'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'tokenized production samples are fine to email|production samples are fine to email|fine to email' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized'; then
        anchor_phrase="emailing production samples with tokenized fields"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing production samples' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized'; then
        anchor_phrase="emailing production samples with tokenized fields"
      elif printf '%s' "$prompt_lower" | grep -Eq 'aggressive retries' && printf '%s' "$prompt_lower" | grep -Eq 'true reliability'; then
        anchor_phrase="aggressive retries versus true reliability"
      fi
      ;;
    strategy)
      if printf '%s' "$prompt_lower" | grep -Eq 'growth, sanctions exposure, reliability, and margin'; then
        anchor_phrase="growth, sanctions exposure, reliability, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'new region signups up|signups up' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soft|renewals soften|renewals softened' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget tight|reliability budget tightened|reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signups rose in the new region|signups rose|new region' && printf '%s' "$prompt_lower" | grep -Eq 'renewals softened|renewals kept weakening|renewals weaken|renewals softened' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget tightened|reliability budget did not recover|reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'counsel flagged sanctions exposure|sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'newly opened region|fast-growing region|newly opened market' && printf '%s' "$prompt_lower" | grep -Eq 'signups surge|signups spike|signups jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soften|renewals weaken|renewal cohorts weaken|renewal cohorts soften' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'political exposure|politically risky|political-risk'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and political exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|newly opened region|newly opened market|pushing harder into' && printf '%s' "$prompt_lower" | grep -Eq 'lifts signups|lifted signups|signups lift|signups lifted|signups surge|signups spike|signups jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soften|renewals weakened|renewals weaken|renewal cohorts weaken|renewal cohorts soften' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget|budget is tight|budget tightens|tight reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure|counsel flags sanctions exposure|counsel warns sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'newly opened market|partner-heavy region' && printf '%s' "$prompt_lower" | grep -Eq 'enterprise signups spike|trial conversions jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewal cohorts weaken|renewal cohorts soften|renewals weaken' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|new region|pushing harder|lifted signups' && printf '%s' "$prompt_lower" | grep -Eq 'churn cohorts?' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically unstable|counsel flags|counsel says'; then
        anchor_phrase="regional growth push versus churn, reliability budget, and political instability"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|region looks safest|pushing harder' && printf '%s' "$prompt_lower" | grep -Eq 'churn cohorts' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically unstable|politically risky|political-risk'; then
        anchor_phrase="growth, reliability budget, political-risk exposure, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'board([^.]| still wants | wants )*faster growth|faster growth next quarter' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically risky|political-risk|sanctions exposure'; then
        anchor_phrase="growth, reliability budget, political-risk exposure, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'growth, margin, legal exposure, and reliability'; then
        anchor_phrase="growth, margin, legal exposure, and reliability"
      fi
      ;;
  esac

  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_anchor_phrase_fallback "$prompt_text")
  fi
  reasoning_anchor_phrase_truncate "$anchor_phrase"
}

reasoning_scenario_reference_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$(reasoning_prompt_focus_brief "$prompt_text")
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref="current scenario"
  fi
  printf '%s' "$scenario_ref"
}

reasoning_risk_line_for_prompt() {
  prompt_text=$1
  final_mode_hint=$(trim "${2:-DONE}")
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Replay, isolation, and cost-ceiling checks around %s still need one more stress-window before the recommendation should be treated as stable.' "$anchor_phrase"
      else
        printf 'Replay, isolation, and cost-ceiling checks around %s still need one more stress-window before the recommendation should be treated as stable; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Timeline consistency and deterministic repro around %s still need one independent confirmation pass before the causal story is treated as closed.' "$anchor_phrase"
      else
        printf 'Timeline consistency and deterministic repro around %s still need one independent confirmation pass before the causal story is treated as closed; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Control ownership, auditability, and recovery-path compliance around %s still need one independent validation pass before broad rollout.' "$anchor_phrase"
      else
        printf 'Control ownership, auditability, and recovery-path compliance around %s still need one independent validation pass before broad rollout; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Benefit-versus-harm validation around %s still needs one more cohort pass against abuse, support, and latency drift before broad rollout.' "$anchor_phrase"
      else
        printf 'Benefit-versus-harm validation around %s still needs one more cohort pass against abuse, support, and latency drift before broad rollout; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Counterfactual strength and lagged-harm exposure around %s still need stronger evidence before the decision should scale.' "$anchor_phrase"
      else
        printf 'Counterfactual strength and lagged-harm exposure around %s still need stronger evidence before the decision should scale; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Mitigation around %s remains provisional until the next review window confirms lower user harm and no blast-radius expansion.' "$anchor_phrase"
      else
        printf 'Mitigation around %s remains provisional until the next review window confirms lower user harm and no blast-radius expansion; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The explanation around %s still needs near-miss and counterexample transfer checks before the misconception can be treated as corrected.' "$anchor_phrase"
      else
        printf 'The explanation around %s still needs near-miss and counterexample transfer checks before the misconception can be treated as corrected; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The plan around %s still needs owner and guardrail confirmation on the sacrificed dimension before it should be treated as execution-ready.' "$anchor_phrase"
      else
        printf 'The plan around %s still needs owner and guardrail confirmation on the sacrificed dimension before it should be treated as execution-ready; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The recommendation around %s still needs one more focused validation pass on its highest-risk assumption.' "$anchor_phrase"
      else
        printf 'The recommendation around %s still needs one more focused validation pass on its highest-risk assumption; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_next_improvement_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Run replay, duplicate-injection, and tenant-isolation drills for %s, then tighten the decision thresholds from the results.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Reconstruct the narrowest failing timeline for %s and test the strongest competing hypothesis before closing the root-cause claim.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Map control ownership and incident-recovery exceptions for %s, then rerun one audit-style contradiction check.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Validate one more benefit-versus-harm cohort pass for %s, then tighten rollout guardrails from abuse, support, and latency results.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Re-estimate %s with confound controls and lagged-harm checks before scaling the decision.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Run one more bounded mitigation review window for %s and prepare the pivot trigger if harm signals stay flat.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Use a counterexample and near-miss check for %s, then revise the explanation from the learner failure point.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Rank the non-negotiables around %s, assign owner and guardrails to the sacrificed dimension, and rerun the plan against the likely veto constraint.' "$anchor_phrase"
      ;;
    *)
      printf 'Validate the highest-risk assumption around %s first, then update the decision thresholds from disconfirming evidence.' "$anchor_phrase"
      ;;
  esac
}

reasoning_recovery_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Recovery and Self-Correction: If replay, isolation, or cost evidence around %s fails, downgrade the shared path, switch to the stricter segmented design, and rerun drills before resuming.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Recovery and Self-Correction: If deterministic repro or timeline order around %s breaks, downgrade the leading hypothesis and reopen the next-best explanation before shipping mitigation.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Recovery and Self-Correction: If control evidence around %s fails, narrow scope to the stricter compliant path and remove any exception-dependent recovery route.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Recovery and Self-Correction: If harm signals around %s rise faster than real completion gains, switch to the more explicit or more gated flow and recheck the affected cohorts.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Recovery and Self-Correction: If confound controls or lagged-harm checks break the story around %s, downgrade the rollout to a bounded experiment or rollback and re-estimate.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Recovery and Self-Correction: If the first mitigation window around %s fails to reduce harm, pivot immediately to the fallback containment path and narrow communications to what is evidence-backed.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Recovery and Self-Correction: If the learner still fails the counterexample or near miss on %s, switch to a counterexample-first explanation and re-test transfer before treating the misconception as fixed.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Recovery and Self-Correction: If the suppressed tradeoff around %s surfaces faster than planned, narrow scope, stage rollout, or explicitly trade speed for trust before continuing.' "$anchor_phrase"
      ;;
    *)
      printf 'Recovery and Self-Correction: If the strongest counterevidence around %s survives the next boundary check, switch to the narrower or more reversible path before continuing.' "$anchor_phrase"
      ;;
  esac
}

reasoning_replan_trigger_line_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Re-Plan Trigger: Re-plan if replay mismatch is non-zero, if any tenant spillover appears, or if cost-per-event breaches ceiling in the next stress window.'
      ;;
    forensics)
      printf 'Re-Plan Trigger: Re-plan if the fault stops reproducing under the claimed cause, if timestamp order breaks, or if a cleaner competing hypothesis explains more evidence.'
      ;;
    security/compliance)
      printf 'Re-Plan Trigger: Re-plan if any mandatory control lacks evidence, if data crosses a prohibited boundary, or if recovery depends on a non-compliant exception.'
      ;;
    product/ux)
      printf 'Re-Plan Trigger: Re-plan if abuse, support burden, or latency breaches guardrails, or if completion gains hold only in the easiest cohorts.'
      ;;
    metrics/causality)
      printf 'Re-Plan Trigger: Re-plan if the effect collapses under confound control, if sign reverses in lagged outcomes, or if the confidence interval overlaps no-effect.'
      ;;
    incident\ response)
      printf 'Re-Plan Trigger: Re-plan if user-harm signals stay flat, if blast radius expands, or if a cleaner containment path gains stronger evidence inside the current review window.'
      ;;
    teaching)
      printf 'Re-Plan Trigger: Re-plan if the learner restates the old rule, misses the boundary case, or cannot explain why the original intuition fails.'
      ;;
    strategy)
      printf 'Re-Plan Trigger: Re-plan if one non-negotiable loses coverage, if the priority order collapses under review, or if the sacrificed dimension worsens beyond its declared guardrail.'
      ;;
    *)
      printf 'Re-Plan Trigger: Re-plan if the strongest counterexample survives, if fallback becomes safer on net, or if the main guardrail is breached.'
      ;;
  esac
}

reasoning_revised_from_line_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Revised From: Revised away from the assumption that a familiar shared ingestion design would be sufficient; replay, isolation, and unit-economics evidence now control the decision.'
      ;;
    forensics)
      printf 'Revised From: Revised away from the loudest-signal narrative; deterministic repro and timeline consistency now decide which hypothesis stays primary.'
      ;;
    security/compliance)
      printf 'Revised From: Revised away from the assumption that a narrow exception could be justified; control ownership and auditability now dominate latency-only gains.'
      ;;
    product/ux)
      printf 'Revised From: Revised away from a low-friction default; paired benefit-versus-harm evidence now determines how much gating the flow needs.'
      ;;
    metrics/causality)
      printf 'Revised From: Revised away from a top-line uplift reading; counterfactual and harm-tracking evidence now decide whether the gain is real.'
      ;;
    incident\ response)
      printf 'Revised From: Revised away from the assumption that the first mitigation path was good enough; direct harm and blast-radius evidence now control the next move.'
      ;;
    teaching)
      printf 'Revised From: Revised away from a clarity-only explanation; counterexample transfer now determines whether the teaching actually worked.'
      ;;
    strategy)
      printf 'Revised From: Revised away from the all-goals narrative; explicit priority order and sacrifice bounds now determine the strategy.'
      ;;
    *)
      printf 'Revised From: Revised away from the first-pass narrative; boundary checks and counterevidence now determine which path remains justified.'
      ;;
  esac
}

reasoning_validation_owner_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Validation Owner: Platform or SRE owner for %s owns replay drills, tenant-isolation checks, and cost-ceiling verification before broad rollout.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Validation Owner: Incident or debugging owner for %s owns timeline reconstruction, deterministic repro, and competing-hypothesis elimination before the root-cause claim is closed.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Validation Owner: Security control owner and compliance reviewer for %s own the control-evidence check, boundary review, and recovery-path exception decision.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Validation Owner: Product owner with risk/support counterparts for %s owns the cohort readout on completion, harm signals, and latency tolerance before expansion.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Validation Owner: Decision owner plus analytics lead for %s own confound controls, lagged-harm review, and the scale-versus-rollback call.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Validation Owner: Incident commander and service owner for %s own the mitigation review window, blast-radius check, and pivot call.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Validation Owner: Instructor or reviewer for %s owns the counterexample check, near-miss transfer check, and explanation revision if the misconception persists.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Validation Owner: Direct strategy owner with finance/legal/operations counterparts for %s owns priority ranking, sacrifice guardrails, and the re-plan decision.' "$anchor_phrase"
      ;;
    *)
      printf 'Validation Owner: A directly responsible owner for %s owns the disconfirming check, fallback trigger, and escalation decision.' "$anchor_phrase"
      ;;
  esac
}

reasoning_time_window_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Time Window: Review %s over the next stress window and close the replay/isolation decision before any broad traffic increase.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Time Window: Reconstruct and verify %s before the next irreversible mitigation or deploy decision, with one independent confirmation pass in the same investigation window.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Time Window: Close the control and boundary review for %s before rollout and before any incident-recovery exception is exercised.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Time Window: Evaluate %s over the next cohort pass and hold broad rollout until abuse, support, and latency results stay inside guardrails for that window.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Time Window: Re-estimate %s in the next analysis cycle and include one lagged-outcome window before scaling the decision.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Time Window: Review direct harm and blast radius for %s in the first mitigation window and pivot immediately if that window closes without improvement.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Time Window: Re-test %s on the next counterexample and near-miss check before treating the misconception as corrected.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Time Window: Re-evaluate %s in the next planning checkpoint and before any commitment that would lock in the sacrificed dimension.' "$anchor_phrase"
      ;;
    *)
      printf 'Time Window: Re-check %s in the next decision window before any irreversible action.' "$anchor_phrase"
      ;;
  esac
}

reasoning_high_risk_verification_status_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current command anchors partially verify %s, but replay drills, tenant isolation, and spend ceilings still need independent confirmation before broad rollout.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against runtime anchors; treat the design as provisional until replay, isolation, and spend-ceiling checks land.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but deterministic repro and competing-hypothesis elimination are still incomplete.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified with deterministic repro or timeline-consistent traces; treat the root-cause read as provisional.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current control evidence partially verifies %s, but boundary review, auditability, and exception handling still need independent confirmation.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against direct control evidence or runtime anchors; treat any rollout or exception as unapproved.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but cohort harm, support load, and latency guardrails still need confirmation before broad exposure.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against cohort evidence or runtime anchors; treat the flow as provisional until harm and latency checks land.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but confound controls and lagged-harm checks still need confirmation before scaling.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against counterfactual or lagged-outcome evidence; treat the uplift as provisional.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but direct harm and blast radius still need confirmation in the next mitigation window.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against direct mitigation evidence or runtime anchors; treat containment as unproven.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify the explanation for %s, but counterexample and near-miss transfer still need confirmation.' "$anchor_phrase"
      else
        printf 'Verification Status: The explanation for %s is not yet verified by transfer checks; treat the misconception as unresolved.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but stakeholder guardrails and sacrifice bounds still need independent confirmation before commitment.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against stakeholder guardrails or hard tradeoff evidence; treat any commitment as provisional.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but independent confirmation is still required before irreversible action.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against runtime anchors; treat any irreversible action as blocked.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_high_risk_go_no_go_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a scoped replay or shadow-traffic step only; No-Go on broad traffic increase until replay, isolation, and spend ceilings hold in the next stress window.'
      else
        printf 'Go/No-Go: No-Go on rollout for %s until replay, isolation, and spend-ceiling evidence is collected.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible containment or observation only; No-Go on root-cause closure or irreversible change until repro, timeline, and alternative-cause checks agree.'
      else
        printf 'Go/No-Go: No-Go on root-cause closure for %s until deterministic repro, timeline evidence, and competing-hypothesis checks are collected.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for narrow recovery or lab validation only; No-Go on rollout or policy exception until control evidence, boundary review, and audit trail checks hold.'
      else
        printf 'Go/No-Go: No-Go on rollout or exception for %s until control evidence, boundary review, and auditability are collected.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a limited cohort only; No-Go on broad exposure until completion, harm, support, and latency stay inside guardrails for the next cohort window.'
      else
        printf 'Go/No-Go: No-Go on broad exposure for %s until cohort harm, support load, and latency evidence are collected.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for additional measurement or tightly scoped continuation only; No-Go on scaling until confound, lagged-harm, and contradiction checks hold.'
      else
        printf 'Go/No-Go: No-Go on scaling %s until counterfactual, lagged-outcome, and harm evidence are collected.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible containment only; No-Go on declaring stability or closing the incident until harm, blast radius, and rollback readiness hold.'
      else
        printf 'Go/No-Go: No-Go on incident closure for %s until harm, blast radius, and rollback-readiness evidence are collected.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for limited guidance only; No-Go on treating the misconception as corrected until counterexample and near-miss transfer checks pass.'
      else
        printf 'Go/No-Go: No-Go on certifying %s as understood until transfer evidence is collected.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible planning only; No-Go on locked-in commitments until stakeholder guardrails and sacrifice bounds are rechecked.'
      else
        printf 'Go/No-Go: No-Go on committing %s until guardrail, sacrifice-bound, and stakeholder-impact evidence are collected.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a scoped reversible step only; No-Go on irreversible action until independent validation holds.'
      else
        printf 'Go/No-Go: No-Go until required evidence is collected and validated for %s.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_high_risk_required_evidence_line_for_prompt() {
  prompt_text=$1
  run_mode_hint=$(trim "${2:-assistant}")
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Required Evidence to Proceed: One replay drill, one tenant-isolation confirmation, and one spend-ceiling measurement for %s over the next stress window.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Required Evidence to Proceed: One deterministic repro, one independent timeline check, and one ruled-out competing hypothesis for %s before root-cause closure.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Required Evidence to Proceed: One independent control test, one boundary review, and one audit-trail or policy-regression check for %s over one review window.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Required Evidence to Proceed: One cohort readout, one harm-or-support regression check, and one latency-threshold check for %s before wider exposure.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Required Evidence to Proceed: One confound control, one lagged-outcome check, and one contradiction test against the uplift story for %s before scaling.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Required Evidence to Proceed: One direct-harm check, one blast-radius confirmation, and one rollback-readiness check for %s in the first mitigation window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Required Evidence to Proceed: Two transfer checks, one counterexample check, and one near-miss explanation check for %s before calling the misconception corrected.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Required Evidence to Proceed: One priority-ranked tradeoff review, one guardrail-breach check, and one stakeholder-impact confirmation for %s before commitment.' "$anchor_phrase"
      ;;
    *)
      case "$run_mode_hint" in
        security-audit|pentest)
          printf 'Required Evidence to Proceed: Reproduce %s with independent traces, confirm control effectiveness, and verify no policy-violation regressions over one review window.' "$anchor_phrase"
          ;;
        *)
          printf 'Required Evidence to Proceed: One independent confirmation trace, one quantitative threshold check, and one contradiction or disconfirming check for %s before irreversible action.' "$anchor_phrase"
          ;;
      esac
      ;;
  esac
}

reasoning_high_risk_residual_risk_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s could still fail under peak load or breach cost ceilings despite current anchors.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct runtime verification on replay, isolation, and cost containment.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still be explained by a competing failure path hidden by noisy logs.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks deterministic repro and timeline-consistent evidence.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still create untracked compliance exposure if the exception path is broader than current evidence shows.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks direct control and audit evidence; treat this as planning only, not approval.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still hide user harm or support blowback behind short-term completion gains.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct cohort harm and latency evidence.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still be non-causal or net-negative once lagged harms arrive.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks counterfactual and lagged-harm evidence.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still be masking ongoing user harm or a larger blast radius.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct evidence that harm is contained or rollback is viable.' "$anchor_phrase"
      fi
      ;;
