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

reasoning_followup_anchor_source_for_prompt() {
  prompt_text=$1
  if ! reasoning_followup_text_signals_present "$prompt_text" \
    && ! reasoning_followup_implicit_text_signals_present "$prompt_text" \
    && ! reasoning_followup_delta_only_turn_present "$(reasoning_latest_prompt_text "$prompt_text")"; then
    return 0
  fi

  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  recent_delta_turn=$(reasoning_followup_recent_delta_turn_for_prompt "$prompt_text")
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$(trim "$recent_delta_turn")" ] && [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario" | cut -c1-640
    return 0
  fi
  prior_user_turn=$(printf '%s\n' "$recent_turns" | awk '
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
      } else if (n == 1) {
        print turns[1]
      }
    }
  ')
  if [ -n "$(trim "$prior_user_turn")" ]; then
    printf '%s' "$prior_user_turn" | cut -c1-640
    return 0
  fi

  if [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario" | cut -c1-640
    return 0
  fi

  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  prior_decision=$(reasoning_contract_extract_value "Decision" "$prior_answer")
  if [ -n "$(trim "$prior_decision")" ]; then
    printf '%s' "$prior_decision" | sed 's/^[[:space:]]*//' | cut -c1-320
  fi
}

reasoning_prompt_anchor_source() {
  prompt_text=$1
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$prior_scenario" ]; then
    prompt_primary=$prior_scenario
  else
    followup_anchor_source=$(reasoning_followup_anchor_source_for_prompt "$prompt_text")
    if [ -n "$(trim "$followup_anchor_source")" ]; then
      prompt_primary=$followup_anchor_source
    else
      prompt_primary=$(printf '%s' "$prompt_text" | sed '/Assay execution scope:/,$d')
    fi
  fi
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/Assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_source=$(printf '%s' "$prompt_primary" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//' | cut -c1-640)
  if [ -z "$(trim "$prompt_source")" ]; then
    prompt_source=$(reasoning_prompt_focus "$prompt_text")
  fi
  printf '%s' "$prompt_source"
}

reasoning_prompt_tokens_for_anchor() {
  prompt_source=$(reasoning_prompt_anchor_source "$1")
  printf '%s\n' "$prompt_source" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' | awk '
    length($0) < 4 { next }
    $0 ~ /^[0-9]+$/ { next }
    $0 ~ /^(this|that|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|about|across|against|around|would|could|should|must|need|needs|required|requireds|current|scenario|domain|integration|analysis|decision|strategy|plan|check|final|output|verify|verification|evidence|risk|risks|next|improvement|tradeoff|tradeoffs|priority|fallback|assumption|assumptions|alternative|alternatives|contract|constraints|through|using|user|users|system|service|services|team|teams|stakeholder|stakeholders|request|prompt|design|architecture|regulated|repository|telemetry|noisy|autogenerated|assay|artifact|artifacts|dominate|dominates|thousands|build|create|provide|explicitly|resists|prioritizes|defines|first|wrong|status|output|report|assistant|teacher|mode|scope|execution|mentoring|contract)$/ { next }
    !seen[$0]++ { print }
  ' | sed -n '1,14p'
}

reasoning_indefinite_article_for_phrase() {
  phrase=$(trim "$1")
  if [ -z "$phrase" ]; then
    printf '%s' "a"
    return 0
  fi
  first_char=$(printf '%s' "$phrase" | cut -c1 | tr '[:upper:]' '[:lower:]')
  case "$first_char" in
    a|e|i|o|u)
      printf '%s' "an"
      ;;
    *)
      printf '%s' "a"
      ;;
  esac
}

reasoning_prompt_anchor_clause() {
  prompt_source=$(reasoning_prompt_anchor_source "$1")
  prompt_clause=$(printf '%s' "$prompt_source" | sed -E 's/[.?!][[:space:]].*$//')
  prompt_clause=$(printf '%s' "$prompt_clause" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  printf '%s' "$prompt_clause"
}

reasoning_anchor_phrase_cleanup() {
  phrase=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/^(design|create|assess|deliver|provide|draft|plan|teach why|teach|explain)[[:space:]]+//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/^(a|an|the)[[:space:]]+//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+while[[:space:]]+noisy warnings dominate logs$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+deliver[[:space:]]+a[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+make[[:space:]]+the[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+provide[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+explain[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  printf '%s' "$phrase"
}

reasoning_anchor_phrase_truncate() {
  phrase=$(trim "$1")
  if [ -z "$phrase" ]; then
    printf '%s' "$phrase"
    return 0
  fi
  phrase_length=$(printf '%s' "$phrase" | wc -c | tr -d ' ')
  case "$phrase_length" in
    ""|*[!0-9]*)
      phrase_length=0
      ;;
  esac
  if [ "$phrase_length" -gt 128 ]; then
    phrase=$(printf '%s' "$phrase" | cut -c1-128 | sed 's/[[:space:]][^[:space:]]*$//')
    phrase=$(trim "$phrase")
  fi
  if [ -z "$phrase" ]; then
    phrase="scenario anchors"
  fi
  printf '%s' "$phrase"
}

reasoning_prompt_anchor_phrase_fallback() {
  prompt_clause=$(reasoning_prompt_anchor_clause "$1")
  anchor_phrase=$(reasoning_anchor_phrase_cleanup "$prompt_clause")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    fallback_tokens=$(prompt_anchor_tokens_for_depth "$1")
    seg_one=$(printf '%s\n' "$fallback_tokens" | sed -n '1p')
    seg_two=$(printf '%s\n' "$fallback_tokens" | sed -n '2p')
    seg_three=$(printf '%s\n' "$fallback_tokens" | sed -n '3p')
    if [ -n "$seg_three" ]; then
      anchor_phrase="$seg_one, $seg_two, and $seg_three"
    elif [ -n "$seg_two" ]; then
      anchor_phrase="$seg_one and $seg_two"
    elif [ -n "$seg_one" ]; then
      anchor_phrase=$seg_one
    fi
  fi
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase="scenario anchors"
  fi
  reasoning_anchor_phrase_truncate "$anchor_phrase"
}

reasoning_prompt_anchor_phrase() {
  prompt_text=$1
  prompt_source=$(reasoning_prompt_anchor_source "$prompt_text")
  prompt_lower=$(printf '%s' "$prompt_source" | tr '[:upper:]' '[:lower:]')
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  anchor_phrase=""

  case "$domain_hint" in
    architecture)
      if printf '%s' "$prompt_lower" | grep -Eq 'shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'merchant retention mismatch|merchant-specific retention|retention differs by merchant|retention' && printf '%s' "$prompt_lower" | grep -Eq 'late failover replays|late failover events|late events after failover|late failover' && printf '%s' "$prompt_lower" | grep -Eq 'replay|replays'; then
        anchor_phrase="shared partner-event ingestion with replay ordering, merchant-specific retention, and late failover events"
      elif printf '%s' "$prompt_lower" | grep -Eq 'one shared feed looks simpler|shared feed for partner events|shared feed is easier to operate|partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'retention differs by merchant|merchants have different retention rules|different retention duties|retention duties differ|merchant-specific retention|retention rules differ' && printf '%s' "$prompt_lower" | grep -Eq 'replay out of order|replay-order matters|replay order matters|replay ordering matters|replay order' && printf '%s' "$prompt_lower" | grep -Eq 'late failover events|late events after failover|late events|late arrivals after failover|failover'; then
        anchor_phrase="shared partner-event ingestion with replay ordering, merchant-specific retention, and late failover events"
      elif printf '%s' "$prompt_lower" | grep -Eq 'partner-event ingestion' && printf '%s' "$prompt_lower" | grep -Eq 'pci retention'; then
        anchor_phrase="partner-event ingestion with replay guarantees, tenant isolation, and pci retention constraints"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared feed for partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'late and out-of-order|late and out of order|out-of-order replays|replays mix tenants|mix tenants' && printf '%s' "$prompt_lower" | grep -Eq 'retention exceptions|retention exception|retention' && printf '%s' "$prompt_lower" | grep -Eq 'smaller merchants|merchant'; then
        anchor_phrase="shared partner-event ingestion with replay guarantees, merchant isolation, and retention rules"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared intake lane|single event lane|partner intake' && printf '%s' "$prompt_lower" | grep -Eq 'late arrivals|late arrival' && printf '%s' "$prompt_lower" | grep -Eq 'replay out of order|replay order|out of order' && printf '%s' "$prompt_lower" | grep -Eq 'retention clocks|retention clock' && printf '%s' "$prompt_lower" | grep -Eq 'merchant'; then
        anchor_phrase="shared partner-event intake with replay guarantees, merchant isolation, and retention clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared partner-event path|shared feed for partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'replay drills|replay tests|replay' && printf '%s' "$prompt_lower" | grep -Eq 'interleave two merchants|cross merchant boundaries|merchant boundaries|merchant isolation' && printf '%s' "$prompt_lower" | grep -Eq 'retention timers differ by merchant|retention clocks differ by merchant|retention'; then
        anchor_phrase="shared partner-event ingestion with replay guarantees, merchant isolation, and retention rules"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared partner-event ingestion path|partner-event ingestion path' && printf '%s' "$prompt_lower" | grep -Eq 'replay drills|replay' && printf '%s' "$prompt_lower" | grep -Eq 'merchant records cannot bleed|cannot bleed together|tenant isolation'; then
        anchor_phrase="partner-event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'retail partner' && printf '%s' "$prompt_lower" | grep -Eq 'late and out of order' && printf '%s' "$prompt_lower" | grep -Eq 'merchant'; then
        anchor_phrase="retail order events that arrive late, out of order, and must stay merchant-isolated"
      elif printf '%s' "$prompt_lower" | grep -Eq 'partner-event ingestion'; then
        anchor_phrase="partner-event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'event ingestion' && printf '%s' "$prompt_lower" | grep -Eq 'replay' && printf '%s' "$prompt_lower" | grep -Eq 'tenant'; then
        anchor_phrase="event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replay guarantees' && printf '%s' "$prompt_lower" | grep -Eq 'tenant isolation'; then
        anchor_phrase="replay guarantees and tenant isolation"
      fi
      ;;
    forensics)
      if printf '%s' "$prompt_lower" | grep -Eq 'replica divergence|replica diverged|replica kept diverging' && printf '%s' "$prompt_lower" | grep -Eq 'drifting node clocks|node clocks disagreed|node clocks did not agree|clock drift|clock skew' && printf '%s' "$prompt_lower" | grep -Eq 'replay batches twice|replay batches arrive twice|replay-order|replay order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice looked clean|failover practice|failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'one replica diverged|replica kept diverging|replica keeps diverging|replica divergence' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks disagreed|node clocks did not agree|clock skew|clock drift|drifting node clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replayed writes landed differently|replayed writes land differently|replay order|replay-order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover drill looked clean|failover practice looked clean|failover drill' && printf '%s' "$prompt_lower" | grep -Eq 'one replica diverged|replica diverged|replica divergence' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks disagreed|node clocks did not agree|event order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect' && printf '%s' "$prompt_lower" | grep -Eq 'failover drills' && printf '%s' "$prompt_lower" | grep -Eq 'privacy-control rollback'; then
        anchor_phrase="reconciliation defect during failover drills after a privacy-control rollback"
      elif printf '%s' "$prompt_lower" | grep -Eq 'disaster-recovery rehearsal|recovery rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'rejoin' && printf '%s' "$prompt_lower" | grep -Eq 'clock skews|clock skew|clock drifts|clock drift|replica drifts by seconds|node clock skews' && printf '%s' "$prompt_lower" | grep -Eq 'replay order|replay out of order|replay-order|replay order flips|replay order changes'; then
        anchor_phrase="replica divergence after disaster-recovery rehearsal with clock skew and replay-order drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice|failover practices' && printf '%s' "$prompt_lower" | grep -Eq 'replica diverges|replica kept diverging|replica keeps diverging|replica still diverges|replica divergence|one replica kept diverging|one replica keeps diverging' && printf '%s' "$prompt_lower" | grep -Eq 'replay|replay batches arrive twice|arrive twice' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks did not agree|node clocks disagree|event order|clock skew|clock drifts|clock drift|drifting node clocks'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice|failover practices' && printf '%s' "$prompt_lower" | grep -Eq 'clock drift|drifting clocks|drifting node clocks|machines with clock drift|nodes with drifting clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replay order flips|replayed writes land in a different order|different order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replicas? disagree' && printf '%s' "$prompt_lower" | grep -Eq 'failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'different hosts|timestamps came from different hosts|host clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replay ordering|replay'; then
        anchor_phrase="replica divergence after a clean failover rehearsal with unsynced host clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replicas? disagree' && printf '%s' "$prompt_lower" | grep -Eq 'clean failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'timestamps|different hosts|host clocks'; then
        anchor_phrase="replica divergence after a clean failover rehearsal with unsynced host clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect' && printf '%s' "$prompt_lower" | grep -Eq 'failover drills'; then
        anchor_phrase="reconciliation defect during failover drills"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect'; then
        anchor_phrase="reconciliation defect investigation"
      fi
      ;;
    security/compliance)
      if printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access expansion|analyst access|access expansion' && printf '%s' "$prompt_lower" | grep -Eq 'residency drift|residency drifts' && printf '%s' "$prompt_lower" | grep -Eq 'deletion-proof loss|deletion proof weakens|deletion proof'; then
        anchor_phrase="regional outage override with analyst-access expansion, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'crisis share link is fast|crisis share link|emergency data-sharing|data-sharing shortcut|data sharing shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'logging is not attributable|not attributable|attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts during failover|residency drifts|residency drift|crosses residency lines' && printf '%s' "$prompt_lower" | grep -Eq 'deletion proof breaks after copying|deletion proof breaks|deletion proof remains incomplete|deletion'; then
        anchor_phrase="emergency data-sharing shortcut with attribution gaps, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency share link active|emergency share link' && printf '%s' "$prompt_lower" | grep -Eq 'logging is not attributable|not attributable|attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts during failover|residency drifts|residency drift|crosses residency lines'; then
        anchor_phrase="emergency share link with attribution gaps and residency drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'customer-managed keys' && printf '%s' "$prompt_lower" | grep -Eq 'analyst workflows'; then
        anchor_phrase="customer-managed keys and analyst workflows under residency, retention, and audit constraints"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency support bypass|emergency analyst access|temporary analyst-access shortcut|temporary analyst access shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'audit cannot prove|audit cannot tie|audit cannot attribute|who accessed what' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries drift|region boundaries drift|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'deletion guarantees|deletion-proof|copied records|copied data'; then
        anchor_phrase="emergency analyst access with residency drift, weak auditability, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'temporary plaintext export during failover|crisis share link|regional customer records|emergency data-sharing|data-sharing shortcut|data sharing shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps|not attributable|logging is not attributable' && printf '%s' "$prompt_lower" | grep -Eq 'residency spill|crosses residency lines|residency lines|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'retention proof|cannot prove deletion|deletion breaks|deletion'; then
        anchor_phrase="emergency data-sharing shortcut with attribution gaps, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'incident responders' && printf '%s' "$prompt_lower" | grep -Eq 'attribute exports|attribution' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries shift during failover|failover'; then
        anchor_phrase="regional outage override with export gaps, residency drift, and plaintext expansion"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access|access expands|expands analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'deletion proof weakens|deletion proof breaks|deletion proof remains incomplete|deletion proof'; then
        anchor_phrase="regional outage override with analyst-access expansion, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'temporary analyst-access shortcut|temporary analyst access shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'incident window' && printf '%s' "$prompt_lower" | grep -Eq 'retention proof' && printf '%s' "$prompt_lower" | grep -Eq 'auditability' && printf '%s' "$prompt_lower" | grep -Eq 'region-bound dataset|region bound dataset|wrong boundary'; then
        anchor_phrase="temporary analyst-access shortcut with retention gaps, weak auditability, and boundary drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'narrow outage exception' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries'; then
        anchor_phrase="short-lived analyst-access outage exception with attribution gaps and residency drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps|attributable' && printf '%s' "$prompt_lower" | grep -Eq 'residency|region-bound|region bound|data residency'; then
        anchor_phrase="emergency analyst access during outages under attributable regional controls"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attributable' && printf '%s' "$prompt_lower" | grep -Eq 'region-bound|region bound|region-bound|regional'; then
        anchor_phrase="emergency analyst access during outages under attributable regional controls"
      elif printf '%s' "$prompt_lower" | grep -Eq 'customer-managed keys'; then
        anchor_phrase="customer-managed keys under audit constraints"
      fi
      ;;
    product/ux)
      if printf '%s' "$prompt_lower" | grep -Eq 'visible review gate|review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user drop|honest user drop|honest-user completion falls|honest user completion falls' && printf '%s' "$prompt_lower" | grep -Eq 'latency volatility|volatile latency|latency remains volatile|latency stays volatile'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trust wants a visible review gate|visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation adds friction|consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency stays volatile|backend latency remains volatile|latency stays volatile|latency remains volatile|volatile latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trust wants a visible review gate|visible review gate|review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation adds friction|consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'something feels off|feels off'; then
        anchor_phrase="regulated signup friction with consent confirmation and trust review gates"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regulated signup|signup flow|signup|review friction|permission wall|review gate|strict review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation|consent step|one more consent|consent checkpoints|extra consent checkpoints' && printf '%s' "$prompt_lower" | grep -Eq 'review gate|visible review gate|trust wants a visible review gate|trust says .*consent confirmation|trust wants manual review|trust queues grow|manual review|review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'page latency swings|backend latency keeps swinging|latency swings|latency keeps swinging|document checks spike latency|document verification latency|document latency' && printf '%s' "$prompt_lower" | grep -Eq 'support volume|support contacts|support contact|support load'; then
        anchor_phrase="regulated signup friction with consent checkpoints, trust review queues, and spiky document latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'reduce abuse during signup|signup' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest users|honest-user|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'review queues grow|review queues|trust wants a visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency keeps swinging|backend latency stays volatile|latency stays volatile|latency remains volatile|volatile latency|backend latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'visible review gate|trust wants a visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'signup' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency stays volatile|backend latency remains volatile|latency stays volatile|volatile latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation wall|consent-confirmation wall|consent wall' && printf '%s' "$prompt_lower" | grep -Eq 'fraud' && printf '%s' "$prompt_lower" | grep -Eq 'review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'document latency' && printf '%s' "$prompt_lower" | grep -Eq 'support contacts|support contact|support load|support volume'; then
        anchor_phrase="consent-confirmation wall with review queues, document latency, and support contacts"
      elif printf '%s' "$prompt_lower" | grep -Eq 'strict consent-confirmation gate|regulated signup' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion drops|review queues lengthen|document latency raises support contacts' && printf '%s' "$prompt_lower" | grep -Eq 'review staffing doubled|fraud pressure returned|document latency dropped'; then
        anchor_phrase="regulated signup friction with consent confirmation, review queues, and document latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signup|review friction|permission wall' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation|consent step|one more consent' && printf '%s' "$prompt_lower" | grep -Eq 'review gate|visible review gate|trust wants a visible review gate|trust says .*consent confirmation|review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'page latency swings|backend latency keeps swinging|latency swings|latency keeps swinging|document latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'consent checks' && printf '%s' "$prompt_lower" | grep -Eq 'trust gates|stronger gates|trust wants stronger gates' && printf '%s' "$prompt_lower" | grep -Eq 'volatile latency|latency is volatile|latency remains volatile'; then
        anchor_phrase="regulated onboarding with consent checks, trust gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'remove identity friction|identity friction' && printf '%s' "$prompt_lower" | grep -Eq 'signup completion|recover signup completion' && printf '%s' "$prompt_lower" | grep -Eq 'fraud losses' && printf '%s' "$prompt_lower" | grep -Eq 'support load|support volume|support tickets'; then
        anchor_phrase="signup identity friction, fraud loss, support volume, and unstable page speed"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signup completion' && printf '%s' "$prompt_lower" | grep -Eq 'identity friction' && printf '%s' "$prompt_lower" | grep -Eq 'fraud losses' && printf '%s' "$prompt_lower" | grep -Eq 'page speed'; then
        anchor_phrase="signup identity friction, fraud loss, support volume, and unstable page speed"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'trust checks' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency'; then
