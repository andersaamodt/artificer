assay_output_has_required_sections() {
  text=$1
  for required in "Outcome:" "Verification Evidence:" "Risks:" "Next Improvement:"; do
    if ! printf '%s\n' "$text" | grep -q "$required"; then
      return 1
    fi
  done
  return 0
}

output_is_intermediate_contract() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$text_lower")" ]; then
    return 0
  fi
  if printf '%s' "$text_lower" | grep -Eq '^outcome:[[:space:]]+produced a defensible intermediate result|^outcome:[[:space:]]+best-effort progress was produced|^outcome:[[:space:]]+run was interrupted before full completion|current result may be partial|partial or stale|loop ended before done mode|run ended in mode:'; then
    return 0
  fi
  return 1
}

final_has_instructional_placeholders() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$final_text_lower")" ]; then
    return 1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq \
    'false premise challenge:[[:space:]]*name one plausible but false assumption|premise validation:[[:space:]]*define the first disconfirming check|adversarial probe:[[:space:]]*for this scenario .* specify one abuse (path|case)|disconfirming threshold:[[:space:]]*define at least one measurable trigger|domain linkage:[[:space:]]*for this scenario .* explain at least one dependency|architecture lens:[[:space:]]*for this scenario .* summarize|product/ux lens:[[:space:]]*for this scenario .* summarize|security/compliance lens:[[:space:]]*for this scenario .* summarize|metrics/causality lens:[[:space:]]*for this scenario .* summarize|incident/ops lens:[[:space:]]*for this scenario .* summarize|tradeoff ledger:[[:space:]]*for this scenario .* list two non-obvious tradeoffs|rejected alternative:[[:space:]]*name the strongest alternative path|stakeholder impact map:[[:space:]]*summarize impact on end users|self-correction evidence:[[:space:]]*identify one tested assumption|evidence anchors:[[:space:]]*for this scenario .* tie major claims|claim-to-evidence map:[[:space:]]*for each major claim, provide|quantified thresholds:[[:space:]]*define at least one numeric acceptance threshold|evidence caveats:[[:space:]]*state freshness limits|scenario-specific check:[[:space:]]*for this scenario .* define one counterexample test|near-miss guard:[[:space:]]*state one similar-looking pattern|assumption register:[[:space:]]*list critical assumptions|uncertainty range:[[:space:]]*provide lower bound|initial assumption:[[:space:]]*for this scenario .* state the first plausible assumption|invalidating evidence:[[:space:]]*state the first concrete evidence|revised decision:[[:space:]]*explain how the recommendation changed|evidence delta:[[:space:]]*contrast before/after confidence'
  then
    return 0
  fi
  return 1
}

assay_next_action_from_plan() {
  plan_text=$1
  next_action_line=$(printf '%s\n' "$plan_text" | sed -n '/^Next Action:/,$p' | sed -n '2p')
  next_action_line=$(trim "$next_action_line")
  if [ -z "$next_action_line" ]; then
    next_action_line="continue from the failure ledger and retry with a narrower scope."
  fi
  printf '%s' "$next_action_line"
}

assay_prefers_scenario_reasoning_normalization() {
  prompt_text=$1
  if prompt_prefers_reasoning_completion "$prompt_text"; then
    return 0
  fi
  if prompt_requires_high_risk_fail_closed "$prompt_text" ""; then
    return 0
  fi
  if prompt_requires_decision_completeness "$prompt_text"; then
    return 0
  fi
  if prompt_requires_cross_domain_reasoning "$prompt_text"; then
    return 0
  fi
  if prompt_requires_adversarial_reasoning "$prompt_text"; then
    return 0
  fi
  return 1
}

sanitize_reasoning_next_action() {
  next_action_line=$(trim "$1")
  prompt_text=$2
  next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  default_reasoning_next_action=$(reasoning_next_improvement_line_for_prompt "$prompt_text")

  if [ -z "$next_action_line" ]; then
    next_action_line=$default_reasoning_next_action
    next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  fi

  if assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    if printf '%s' "$next_action_lower" | grep -Eq 'list all files|list files|inspect workspace|inspect relevant files|read-only tools|readme|git status|ls -|open repository|review folder structure|^completion criteria|^goal:|identified files and their contents|requested change implemented|continue from the failure ledger|narrower scope|latest checkpoint|implementation patch|run verify checks|validate the highest-risk assumption first'; then
      next_action_line=$default_reasoning_next_action
    fi
  fi

  printf '%s' "$next_action_line"
}

assay_reasoning_verification_line_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$(trim "$scenario_ref")" ]; then
    printf '%s' "Verification Evidence: Review the run trace for executed steps, commands, and controller transitions."
    return 0
  fi
  printf 'Verification Evidence: Review the run trace and command anchors for scenario (%s).' "$scenario_ref"
}

assay_sanitize_reasoning_outcome() {
  outcome_line=$(trim "$1")
  prompt_text=$2
  outcome_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')

  if ! assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    printf '%s' "$outcome_line"
    return 0
  fi

  if [ -z "$outcome_line" ] || [ "$outcome_lower" = "none" ] || [ "$outcome_lower" = "null" ] || [ "$outcome_lower" = "n/a" ]; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq '^security findings report(\b|[[:space:]]*\()|^pentest findings report(\b|[[:space:]]*\()|^security review run completed; synthesized findings were normalized from available run evidence\.?$'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  printf '%s' "$outcome_line"
}

reasoning_prompt_focus() {
  prompt_text=$1
  prompt_primary=$(printf '%s' "$prompt_text" | sed '/Assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/Assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_focus=$(printf '%s' "$prompt_primary" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//' | cut -c1-96)
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  printf '%s' "$prompt_focus"
}

prompt_anchor_tokens_for_depth() {
  prompt_focus=$(reasoning_prompt_focus "$1")
  printf '%s\n' "$prompt_focus" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '\n' | awk '
    length($0) < 4 { next }
    $0 ~ /^[0-9]+$/ { next }
    $0 ~ /^(this|that|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|about|across|against|around|would|could|should|must|need|needs|required|requireds|current|scenario|domain|integration|analysis|decision|strategy|plan|check|final|output|verify|verification|evidence|risk|risks|next|improvement|tradeoff|tradeoffs|priority|fallback|assumption|assumptions|alternative|alternatives|contract|constraints|through|using|user|users|system|service|services|team|teams|stakeholder|stakeholders|request|prompt)$/ { next }
    !seen[$0]++ { print }
  ' | sed -n '1,8p'
}

reasoning_prompt_focus_brief() {
  prompt_focus=$(reasoning_prompt_focus "$1")
  prompt_focus=$(printf '%s' "$prompt_focus" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  prompt_focus=$(printf '%s' "$prompt_focus" | cut -c1-84)
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  printf '%s' "$prompt_focus"
}

reasoning_recent_user_turns_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Recent user turns:$/ { capture = 1; next }
    /^Prior compact answer:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 0 }
    /^Attachment context:$/ { capture = 0 }
    /^Web context:$/ { capture = 0 }
    /^Run mode directive:$/ { capture = 0 }
    /^Assay mentoring contract:$/ { capture = 0 }
    /^Explicit skill actuator results:$/ { capture = 0 }
    /^Team metadata:$/ { capture = 0 }
    /^Teacher pacing signal:$/ { capture = 0 }
    capture { print }
  '
}

reasoning_latest_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        latest = line
      }
    }
    END {
      print latest
    }
  '
}

reasoning_followup_previous_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n >= 2) {
        print turns[n - 1]
      }
    }
  '
}

reasoning_followup_turn_before_previous_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n >= 3) {
        print turns[n - 2]
      }
    }
  '
}

reasoning_followup_token_overlap_present() {
  candidate_text=$(printf '%s' "${1-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  reference_text=$(printf '%s' "${2-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$candidate_text")" ] || return 1
  [ -n "$(trim "$reference_text")" ] || return 1
  awk -v candidate="$candidate_text" -v reference="$reference_text" '
    function load_tokens(text, bag,    normalized, n, i, token) {
      normalized = tolower(text)
      gsub(/[^[:alnum:]]+/, " ", normalized)
      n = split(normalized, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        token = parts[i]
        if (length(token) < 4) {
          continue
        }
        if (token ~ /^(that|this|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|here|about|across|against|around|would|could|should|must|need|needs|required|current|scenario|outcome|decision|fallback|path|disconfirming|evidence|risk|risks|next|improvement|initial|assumption|invalidating|revised|delta|review|window|owner|priority|prior|recent|still|again|after|before|remains|remained|stayed|keeps|kept|continued|updated|update|your|call|read|take|land|now|then)$/) {
          continue
        }
        bag[token] = 1
      }
    }
    BEGIN {
      load_tokens(candidate, cand)
      load_tokens(reference, ref)
      overlap = 0
      for (token in cand) {
        if (token in ref) {
          overlap++
        }
      }
      exit(overlap >= 2 ? 0 : 1)
    }
  '
}

reasoning_followup_delta_only_turn_present() {
  prompt_text=$1
  normalized_prompt=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  normalized_prompt=$(trim "$normalized_prompt")
  [ -n "$normalized_prompt" ] || return 1
  if reasoning_followup_text_signals_present "$normalized_prompt"; then
    return 1
  fi
  if reasoning_followup_implicit_text_signals_present "$normalized_prompt"; then
    return 1
  fi
  if reasoning_followup_short_question_present "$normalized_prompt"; then
    return 1
  fi
  if printf '%s' "$normalized_prompt" | grep -Eqi 'in short labeled sections|short labeled sections|same labels|keep the same labels|give outcome|fallback path|next improvement|disconfirming evidence|implement|apply patch|modify file|update file|write file|fix bug|run tests|compile|build target'; then
    return 1
  fi
  word_count=$(printf '%s\n' "$normalized_prompt" | awk '{ print NF }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 40 ]; then
    return 1
  fi
  if reasoning_followup_changed_condition_cues_present "$normalized_prompt" \
    || reasoning_followup_fragment_delta_present "$normalized_prompt"; then
    return 0
  fi
  return 1
}

reasoning_followup_prior_scenario_from_turns_block() {
  turns_block=$1
  latest_prompt=${2:-}
  latest_prompt=$(trim "$latest_prompt")
  printf '%s\n' "$turns_block" | awk -v latest_prompt="$latest_prompt" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      line = trim(line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n == 0) {
        exit
      }
      latest = tolower(latest_prompt)
      gsub(/[[:space:]]+/, " ", latest)
      latest = trim(latest)
      latest_plain = latest
      sub(/[[:space:][:punct:]]+$/, "", latest_plain)
      gsub(/\047/, "", latest_plain)
      if (latest_plain == "your call" || latest_plain == "your read" || latest_plain == "your take" || latest_plain == "your instinct" || latest_plain == "where do you land" || latest_plain == "where do you land now" || latest_plain == "where does this leave you" || latest_plain == "so" || latest_plain == "and" || latest_plain == "and now" || latest_plain == "what now" || latest_plain == "well" || latest_plain == "still" || latest_plain == "still yes" || latest_plain == "still safe" || latest_plain == "still harmless" || latest_plain == "thoughts" || latest_plain == "thought" || latest_plain == "gut check" || latest_plain == "gut reaction" || latest_plain == "initial take" || latest_plain == "first instinct" || latest_plain == "quick read" || latest_plain == "whats your take" || latest_plain == "whats your read" || latest_plain == "whats your call" || latest_plain == "whats the move" || latest_plain == "how does this strike you") {
        print turns[1]
        exit
      }
      if (n >= 2) {
        print turns[n - 1]
        exit
      }
      print turns[1]
    }
  '
}

reasoning_prior_scenario_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior scenario:$/ { capture = 1; next }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
    /^Prior memo:$/ { capture = 0 }
    /^Prior compact answer:$/ { capture = 0 }
    /^Attachment context:$/ { capture = 0 }
    /^Web context:$/ { capture = 0 }
    /^Run mode directive:$/ { capture = 0 }
    /^Assay mentoring contract:$/ { capture = 0 }
    /^Explicit skill actuator results:$/ { capture = 0 }
    /^Team metadata:$/ { capture = 0 }
    /^Teacher pacing signal:$/ { capture = 0 }
    capture { print }
  '
}

