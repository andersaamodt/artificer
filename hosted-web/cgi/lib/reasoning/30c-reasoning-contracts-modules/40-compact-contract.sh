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
    product/ux)
      printf 'next cohort pass with harm metrics inside guardrails'
      ;;
    metrics/causality)
      printf 'next analysis cycle plus one lagged-outcome window'
      ;;
    incident\ response)
      printf 'first mitigation window before blast radius expands'
      ;;
    teaching)
      printf 'next counterexample and near-miss check'
      ;;
    strategy)
      printf 'next planning checkpoint before the sacrifice is locked in'
      ;;
    *)
      printf 'next decision window before irreversible action'
      ;;
  esac
}

reasoning_compact_claim_map_value_for_prompt() {
  prompt_text=$1
  evidence_basis=$(reasoning_compact_evidence_basis_for_prompt "$prompt_text")
  owner_clause=$(reasoning_compact_owner_clause_for_prompt "$prompt_text")
  review_window_clause=$(reasoning_compact_review_window_clause_for_prompt "$prompt_text")
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  claim_map_entry=$(reasoning_claim_map_primary_line_for_prompt "$prompt_text" "$evidence_basis")
  claim_map_entry=$(printf '%s\n' "$claim_map_entry" | awk '
    {
      line = $0
      sub(/^- Claim 1 \([^)]*\):[[:space:]]*/, "", line)
      print line
      exit
    }
  ')
  if [ -z "$(trim "$claim_map_entry")" ]; then
    claim_map_entry="primary claim -> anchor: $evidence_basis -> invalidation trigger: $disconfirming_line"
  fi
  printf '%s; owner: %s; review window: %s' "$claim_map_entry" "$owner_clause" "$review_window_clause"
}

reasoning_compact_followup_outcome_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    reasoning_decision_line_for_prompt "$prompt_text"
    return 0
  fi
  printf 'Selected the revised path for %s after reassessing the change set: %s.' "$anchor_phrase" "$followup_delta"
}

reasoning_compact_followup_initial_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Initial Assumption" "$(normalize_reasoning_placeholder_contract "Initial Assumption: For this scenario ($(reasoning_scenario_reference_for_prompt "$prompt_text")), state the first plausible assumption that guided the initial approach." "$prompt_text" "")"
    return 0
  fi
  printf 'The updated read was that the change set %s was enough to keep the prior recommendation for %s.' "$followup_delta" "$anchor_phrase"
}

reasoning_compact_followup_invalidating_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Invalidating Evidence" "$(normalize_reasoning_placeholder_contract "Invalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive." "$prompt_text" "")"
    return 0
  fi
  printf 'That updated read fails if concentrated harm, lagged regressions, or returning risk still break guardrails for %s despite the change set %s.' "$anchor_phrase" "$followup_delta"
}

reasoning_compact_followup_revised_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Revised Decision" "$(normalize_reasoning_placeholder_contract "Revised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it." "$prompt_text" "")"
    return 0
  fi
  printf 'Keep or tighten the staged safer path for %s until the change set %s is validated without the returning risk signals.' "$anchor_phrase" "$followup_delta"
}

normalize_compact_reasoning_contract() {
  output_text=$(trim "$1")
  prompt_text=$2
  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s' "$output_lower" | grep -Eq '^model timed out after |^model request failed |^model returned an embedding vector|^run completed, but the model did not return content'; then
    printf '%s' "$output_text"
    return 0
  fi

  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  anchor_phrase_lower=$(compact_reasoning_contract_lower_text "$anchor_phrase")
  decision_value=$(reasoning_decision_line_for_prompt "$prompt_text")
  placeholder_scaffold=$(cat <<EOF
Initial Assumption: For this scenario ($scenario_ref), state the first plausible assumption that guided the initial approach.
Invalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive.
Revised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it.
Claim-to-Evidence Map: For each major claim, provide {claim -> anchor -> verification method -> invalidation trigger} with an assigned owner and review window.
EOF
)
  placeholder_scaffold=$(normalize_reasoning_placeholder_contract "$placeholder_scaffold" "$prompt_text" "")

  outcome_value=$(compact_reasoning_contract_extract_value "Outcome" "$output_text")
  initial_value=$(compact_reasoning_contract_extract_value "Initial Assumption" "$output_text")
  invalidating_value=$(compact_reasoning_contract_extract_value "Invalidating Evidence" "$output_text")
  revised_value=$(compact_reasoning_contract_extract_value "Revised Decision" "$output_text")
  claim_map_value=$(compact_reasoning_contract_extract_value "Claim-to-Evidence Map" "$output_text")

  default_initial_value=$(compact_reasoning_contract_extract_value "Initial Assumption" "$placeholder_scaffold")
  default_invalidating_value=$(compact_reasoning_contract_extract_value "Invalidating Evidence" "$placeholder_scaffold")
  default_revised_value=$(compact_reasoning_contract_extract_value "Revised Decision" "$placeholder_scaffold")
  default_claim_map_value=$(reasoning_compact_claim_map_value_for_prompt "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_outcome_value=$(compact_reasoning_prior_answer_value_for_prompt "Outcome" "$prompt_text")
  prior_initial_value=$(compact_reasoning_prior_answer_value_for_prompt "Initial Assumption" "$prompt_text")
  prior_invalidating_value=$(compact_reasoning_prior_answer_value_for_prompt "Invalidating Evidence" "$prompt_text")
  prior_revised_value=$(compact_reasoning_prior_answer_value_for_prompt "Revised Decision" "$prompt_text")
  prior_claim_map_value=$(compact_reasoning_prior_answer_value_for_prompt "Claim-to-Evidence Map" "$prompt_text")

  if [ -n "$(trim "$followup_delta")" ]; then
    followup_outcome_value=$(reasoning_compact_followup_outcome_value_for_prompt "$prompt_text")
    followup_initial_value=$(reasoning_compact_followup_initial_value_for_prompt "$prompt_text")
    followup_invalidating_value=$(reasoning_compact_followup_invalidating_value_for_prompt "$prompt_text")
    followup_revised_value=$(reasoning_compact_followup_revised_value_for_prompt "$prompt_text")
    if [ -n "$(trim "$prior_outcome_value")" ] && [ "$(compact_reasoning_contract_lower_text "$outcome_value")" = "$(compact_reasoning_contract_lower_text "$prior_outcome_value")" ]; then
      outcome_value=$followup_outcome_value
    fi
    if [ -n "$(trim "$prior_initial_value")" ] && [ "$(compact_reasoning_contract_lower_text "$initial_value")" = "$(compact_reasoning_contract_lower_text "$prior_initial_value")" ]; then
      initial_value=$followup_initial_value
    fi
    if [ -n "$(trim "$prior_invalidating_value")" ] && [ "$(compact_reasoning_contract_lower_text "$invalidating_value")" = "$(compact_reasoning_contract_lower_text "$prior_invalidating_value")" ]; then
      invalidating_value=$followup_invalidating_value
    fi
    if [ -n "$(trim "$prior_revised_value")" ] && [ "$(compact_reasoning_contract_lower_text "$revised_value")" = "$(compact_reasoning_contract_lower_text "$prior_revised_value")" ]; then
      revised_value=$followup_revised_value
    fi
    if [ -n "$(trim "$prior_claim_map_value")" ] && [ "$(compact_reasoning_contract_lower_text "$claim_map_value")" = "$(compact_reasoning_contract_lower_text "$prior_claim_map_value")" ]; then
      claim_map_value=$default_claim_map_value
    fi
  fi

  if compact_reasoning_contract_value_needs_upgrade "Outcome" "$outcome_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      outcome_value=$followup_outcome_value
    else
      outcome_value=$decision_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Initial Assumption" "$initial_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      initial_value=$followup_initial_value
    else
      initial_value=$default_initial_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Invalidating Evidence" "$invalidating_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      invalidating_value=$followup_invalidating_value
    else
      invalidating_value=$default_invalidating_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Revised Decision" "$revised_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      revised_value=$followup_revised_value
    else
      revised_value=$default_revised_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Claim-to-Evidence Map" "$claim_map_value" "$prompt_text"; then
    claim_map_value=$default_claim_map_value
  elif [ -n "$(trim "$anchor_phrase_lower")" ] && ! printf '%s' "$claim_map_value" | tr '[:upper:]' '[:lower:]' | grep -Fq "$anchor_phrase_lower"; then
    claim_map_value=$default_claim_map_value
  fi

  outcome_value=$(compact_reasoning_contract_squash_value "$outcome_value")
  initial_value=$(compact_reasoning_contract_squash_value "$initial_value")
  invalidating_value=$(compact_reasoning_contract_squash_value "$invalidating_value")
  revised_value=$(compact_reasoning_contract_squash_value "$revised_value")
  claim_map_value=$(compact_reasoning_contract_squash_value "$claim_map_value")

  printf '%s\n%s\n%s\n%s\n%s' \
    "Outcome: $outcome_value" \
    "Initial Assumption: $initial_value" \
    "Invalidating Evidence: $invalidating_value" \
    "Revised Decision: $revised_value" \
    "Claim-to-Evidence Map: $claim_map_value"
}

