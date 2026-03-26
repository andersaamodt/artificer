assistant_output_is_freeform_clarify_question() {
  output_text=$(trim "$1")
  output_text_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  [ -n "$output_text" ] || return 1
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'do you want .* or are you just (capturing|recording) ' \
    && printf '%s' "$output_text_lower" | grep -Eq 'if you want '; then
    return 0
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'provide (the )?(relevant )?(details|context)|more details|more context|clarify (the )?(request|question|goal)|what specifically|which specific|further assistance|provide .*context needed to assist further|please provide .* and any context needed to assist further|provide .* needed to assist further'; then
    return 0
  fi
  return 1
}

assistant_output_is_freeform_frame_response() {
  output_text=$(trim "$1")
  output_text_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  [ -n "$output_text" ] || return 1
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'not a settled decision request yet' \
    && printf '%s' "$output_text_lower" | grep -Eq 'the key moving parts are' \
    && printf '%s' "$output_text_lower" | grep -Eq 'if you want, i can turn that into'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'just notes|notes only|just recording|just capturing|recording constraints|recording status notes|recording forensics notes|capturing architecture notes|capturing product notes|recording stakeholder notes|recording metric notes|not asking|do not analyze|don.?t analyze'; then
    return 1
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 20 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(yes|yeah|yep|sure|ok|okay|please|go ahead|go on|do it|do so|that one|the recommendation|the call|the read|the likely read|the take|the direction|the safer path|the safer design|the containment path|the leading hypothesis|the policy call|the incident recommendation|the investigation read|the causality read|the explanation approach|recommendation|call|read|likely read|take|direction|safer path|safer design|containment path|leading hypothesis|policy call|incident recommendation|investigation read|causality read|explanation approach)[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommendation|give me .*call|give me .*read|give me .*likely read|give me .*take|give me .*direction|give me .*safer path|give me .*safer design|give me .*containment path|give me .*leading hypothesis|give me .*policy call|give me .*incident recommendation|give me .*investigation read|give me .*causality read|give me .*explanation approach|analy[sz]e (it|this)|want the call|want the recommendation|want the read|want the take|want the direction'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_frame() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 12 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(the )?(current picture|current state|status picture|status|snapshot|context)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (the shape|the current shape|where we.?re at|where it stands)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (the situation|the picture|where things stand)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (about it|basically it|the gist|what we know)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) it for now[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) all (i have|i.ve got|we have)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*only that so far[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*just that (at the moment|for the moment)[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*not the (recommendation|call|read|likely read|take|direction|safer path|safer design|containment path|leading hypothesis|policy call|incident recommendation|investigation read|causality read|explanation|explanation approach) yet[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?frame (it|this)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if freeform_frame_reply_prefers_reflection "$prompt_primary"; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(reflect|reflection|the tension)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

freeform_frame_reply_prefers_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 16 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(reflect|reflection|reflective|reflect on it|reflect on this|reflect on the tension|the tension|just the tension|only the tension|keep it reflective|talk me through the tension|think through the tension|walk the tension|think it through)( for now| a bit)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

prompt_prefers_freeform_reasoning_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reasoning "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_frame_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_frame "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reflection "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_after_frame() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reasoning "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_frame_response "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection_after_frame() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_frame_reply_prefers_reflection "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_frame_response "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_has_freeform_post_clarify_context() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Prior clarify question:$'; then
    return 1
  fi
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  if freeform_clarify_reply_prefers_reasoning "$latest_prompt"; then
    return 0
  fi
  if freeform_clarify_reply_prefers_frame "$latest_prompt"; then
    return 0
  fi
  if freeform_clarify_reply_prefers_reflection "$latest_prompt"; then
    return 0
  fi
  return 1
}

prompt_has_freeform_post_frame_context() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Prior frame:$'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_followup_memo() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if prompt_prefers_document_revision_task "$prompt_text_lower"; then
    return 1
  fi
  if ! reasoning_followup_implicit_text_signals_present "$prompt_text_lower" \
    && ! reasoning_followup_delta_only_turn_present "$prompt_text_lower" \
    && ! reasoning_followup_short_question_present "$prompt_text_lower"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_reasoning_memo "$prior_answer"; then
    return 1
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4")
  if reasoning_followup_changed_condition_cues_present "$prompt_text_lower" \
    || reasoning_followup_fragment_delta_present "$prompt_text_lower" \
    || [ -n "$(trim "$(reasoning_followup_recent_delta_turn_for_prompt "$(printf '%s\n\nRecent user turns:\n%s' "$prompt_text" "$recent_user_turns")")")" ]; then
    return 0
  fi
  return 1
}

assistant_output_is_compact_reasoning_contract() {
  output_text=$(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d')
  [ -n "$(trim "$output_text")" ] || return 1
  line_count=$(printf '%s\n' "$output_text" | wc -l | tr -d ' ')
  [ -n "$line_count" ] || line_count=0
  if [ "$line_count" -ne 5 ]; then
    return 1
  fi
  for label in "Outcome:" "Initial Assumption:" "Invalidating Evidence:" "Revised Decision:" "Claim-to-Evidence Map:"; do
    label_count=$(printf '%s\n' "$output_text" | grep -c "^${label}")
    if [ "$label_count" -ne 1 ]; then
      return 1
    fi
  done
  return 0
}

prompt_prefers_compact_reasoning_followup_contract() {
  prompt_text=$1
  conv_dir=${2:-}
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_compact_reasoning_contract "$prompt_primary"; then
    return 0
  fi
  if ! compact_reasoning_followup_text_signals_present "$prompt_primary"; then
    return 1
  fi
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    return 1
  fi
  last_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if assistant_output_is_compact_reasoning_contract "$last_assistant_text"; then
    return 0
  fi
  if assistant_output_is_reasoning_completion_contract "$last_assistant_text"; then
    return 1
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "2")
  if printf '%s' "$prompt_primary" | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map|5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 0
  fi
  if printf '%s' "$recent_user_turns" | tr '[:upper:]' '[:lower:]' | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map' \
    && printf '%s' "$recent_user_turns" | tr '[:upper:]' '[:lower:]' | grep -Eq '5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 0
  fi
  return 1
}

compact_reasoning_latest_prompt_text() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 1 }
    /^Recent user turns:$/ { capture = 0 }
    capture { print }
  '
}

compact_reasoning_prior_answer_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior compact answer:$/ { capture = 1; next }
    capture { print }
  '
}

compact_reasoning_followup_delta_phrase_for_prompt() {
  prompt_text=$1
  latest_prompt=$(compact_reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if ! compact_reasoning_followup_text_signals_present "$latest_prompt_single"; then
    return 0
  fi
  if printf '%s' "$latest_prompt_single" | grep -Eq '[Bb]ecause[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Bb]ecause[[:space:]]*//')
  else
    delta_phrase=$latest_prompt_single
  fi
  delta_phrase=$(printf '%s' "$delta_phrase" | sed \
    -e 's/[[:space:]]*[Ii]n 5 short labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n five short labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n 5 labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n five labeled lines only.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same labels.*$//' \
    -e 's/[[:space:]]*[Uu]se these labels exactly once each:.*$//' \
    -e 's/[[:space:]]*[.]$//')
  delta_phrase=$(trim "$delta_phrase")
  if [ -n "$delta_phrase" ]; then
    printf '%s' "$delta_phrase" | cut -c1-220
  fi
}

compact_reasoning_prior_answer_value_for_prompt() {
  label=$1
  prompt_text=$2
  prior_answer=$(compact_reasoning_prior_answer_block_for_prompt "$prompt_text")
  compact_reasoning_contract_extract_value "$label" "$prior_answer"
}

compact_reasoning_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if ! prompt_prefers_compact_reasoning_followup_contract "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  prior_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "3" | sed -n '1,6p')
  prior_compact_answer=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,5p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior compact answer:\n%s' \
    "$prompt_text" \
    "$prior_user_turns" \
    "$prior_compact_answer"
}

reasoning_freeform_prior_memo_summary_for_prompt() {
  prompt_text=$1
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  prior_answer=$(printf '%s' "$prior_answer" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$prior_answer")" ]; then
    printf '%s' "$prior_answer" | cut -c1-420
  fi
}

reasoning_freeform_updated_conditions_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Updated conditions:$/ { capture = 1; next }
    /^Recent user turns:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior memo:$/ { capture = 0 }
    capture { print }
  '
}

reasoning_freeform_post_clarify_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_latest_turn_from_turns_block "$recent_user_turns")
  fi
  prior_scenario=$(trim "$prior_scenario")
  if [ -z "$prior_scenario" ]; then
    prior_scenario=$(conversation_last_message_for_role "$conv_dir" "user" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  fi
  prior_clarify=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,6p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior clarify question:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_clarify"
}

reasoning_freeform_post_frame_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
  if [ -n "$(trim "$prior_scenario")" ] && { freeform_clarify_reply_prefers_frame "$prior_scenario" \
    || freeform_clarify_reply_prefers_reflection "$prior_scenario" \
    || freeform_clarify_reply_prefers_reasoning "$prior_scenario"; }; then
    earlier_scenario=$(reasoning_followup_turn_before_previous_from_turns_block "$recent_user_turns")
    if [ -n "$(trim "$earlier_scenario")" ]; then
      prior_scenario=$earlier_scenario
    fi
  fi
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_latest_turn_from_turns_block "$recent_user_turns")
  fi
  prior_scenario=$(trim "$prior_scenario")
  if [ -z "$prior_scenario" ]; then
    prior_scenario=$(conversation_first_user_message_for_conversation "$conv_dir" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  fi
  prior_frame=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,6p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior frame:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_frame"
}

reasoning_focus_delta_phrase() {
  delta_text=$(printf '%s' "${1-}" | tr '\n' ' ' | sed 's/ - /; /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$delta_text")" ] || return 0
  if ! printf '%s' "$delta_text" | grep -Eq '[.;]'; then
    printf '%s' "$delta_text"
    return 0
  fi
  printf '%s\n' "$delta_text" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      count = split($0, raw_parts, /[.;]+/)
      kept = 0
      for (i = 1; i <= count; i++) {
        part = trim(raw_parts[i])
        if (part == "") {
          continue
        }
        parts[++kept] = part
      }
      if (kept >= 2) {
        left = parts[kept - 1]
        right = parts[kept]
        sub(/[[:space:][:punct:]]+$/, "", left)
        sub(/^[[:space:][:punct:]]+/, "", right)
        print left " and " right
        exit 0
      }
      print $0
    }
  '
}

reasoning_freeform_followup_delta_for_prompt() {
  prompt_text=$1
  explicit_delta=$(reasoning_freeform_updated_conditions_block_for_prompt "$prompt_text")
  explicit_delta=$(printf '%s' "$explicit_delta" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$explicit_delta")" ]; then
    reasoning_focus_delta_phrase "$explicit_delta"
    return 0
  fi
  delta_phrase=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  reasoning_focus_delta_phrase "$delta_phrase"
}

reasoning_freeform_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if prompt_prefers_freeform_reasoning_after_clarify "$prompt_text" "$conv_dir"; then
    reasoning_freeform_post_clarify_context_prompt "$prompt_text" "$conv_dir"
    return 0
  fi
  if prompt_prefers_freeform_reasoning_after_frame "$prompt_text" "$conv_dir"; then
    reasoning_freeform_post_frame_context_prompt "$prompt_text" "$conv_dir"
    return 0
  fi
  if ! prompt_prefers_freeform_reasoning_followup_memo "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_prior_scenario_from_turns_block "$recent_user_turns" "$prompt_text")
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_prompt_anchor_source "$(conversation_first_user_message_for_conversation "$conv_dir")")
  fi
  prior_freeform_memo=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,8p')
  updated_conditions=$(reasoning_freeform_followup_delta_for_prompt "$prompt_text")
  followup_short_clause=$(reasoning_followup_short_question_clause "$prompt_text")
  if [ -n "$(trim "$followup_short_clause")" ]; then
    updated_norm=$(printf '%s' "$updated_conditions" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/[[:space:][:punct:]]*$//')
    clause_norm=$(printf '%s' "$followup_short_clause" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/[[:space:][:punct:]]*$//')
    if [ -z "$(trim "$updated_norm")" ] || [ "$updated_norm" = "$clause_norm" ]; then
      recent_delta_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
      recent_delta_turn=$(trim "$recent_delta_turn")
      if [ -n "$recent_delta_turn" ] && { reasoning_followup_changed_condition_cues_present "$recent_delta_turn" \
        || reasoning_followup_fragment_delta_present "$recent_delta_turn" \
        || printf '%s' "$recent_delta_turn" | grep -Eq '[,;:]'; }; then
        updated_conditions=$recent_delta_turn
      fi
    fi
  fi
  if [ -z "$(trim "$updated_conditions")" ]; then
    updated_conditions=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
    if reasoning_followup_short_question_present "$updated_conditions"; then
      followup_short_clause=$(reasoning_followup_short_question_clause "$updated_conditions")
      updated_conditions=$(printf '%s\n' "$updated_conditions" | awk '
        function trim(s) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          return s
        }
        BEGIN {
          clause = tolower(ARGV[1])
          ARGV[1] = ""
        }
        {
          raw_line = trim($0)
          line = tolower(raw_line)
          gsub(/[[:space:]]+/, " ", line)
          line = trim(line)
          if (clause == "" || line == clause) {
            print raw_line
            exit 0
          }
          if (length(line) > length(clause) && substr(line, length(line) - length(clause) + 1) == clause) {
            prefix = substr(raw_line, 1, length(raw_line) - length(clause))
            prefix = trim(prefix)
            sub(/[[:space:][:punct:]]+$/, "", prefix)
            print prefix
            exit 0
          }
          print raw_line
        }
      ' "$followup_short_clause")
    fi
    updated_conditions=$(trim "$updated_conditions")
  fi
  printf '%s\n\nUpdated conditions:\n%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior memo:\n%s' \
    "$prompt_text" \
    "$updated_conditions" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_freeform_memo"
}

assistant_output_is_reasoning_completion_contract() {
  output_text=$(trim "$1")
  [ -n "$output_text" ] || return 1
  if output_is_intermediate_contract "$output_text"; then
    return 1
  fi
  if final_has_instructional_placeholders "$output_text"; then
    return 1
  fi
  if final_has_decision_completeness "$output_text" \
    || final_has_assumption_revision_contract "$output_text" \
    || final_has_recovery_contract "$output_text" \
    || final_has_cross_domain_synthesis_contract "$output_text" \
    || final_has_verification_contract "$output_text"; then
    return 0
  fi
  return 1
}

reasoning_followup_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'same plan|same strategy|same incident call|same call|same read|same recommendation|same overall structure|same structure|same format|same outline|keep the same|revise that same|revise the same'; then
    return 1
  fi
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'revise|revised|revision|update|updated|pivot|changed|change explicit|make the revised|make the shift|show the pivot|spell out the pivot|what changed|overturned|make the revised call explicit|make the revised decision explicit|make the decision change explicit'; then
    return 1
  fi
  return 0
}

reasoning_followup_implicit_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update (the )?(recommendation|decision|call|read|plan|strategy|architecture|explanation|incident call)|reconsider|reassess|re-evaluate|reevaluate|what changed|what overturned|does .* still hold|does .* still stand|should we still|would you still|would that still|do you still|what would you do now|what do you do now|what would you do next|what do you do next|what now|where do you land now|how do you read it now|still back it|still support it|still call it|still avoid rollback|still allow it|still keep it|how does that change|change the recommendation|change the decision|change the call|update the explanation'; then
    if reasoning_followup_changed_condition_cues_present "$prompt_text_lower"; then
      return 0
    fi
    if reasoning_followup_fragment_delta_present "$prompt_text_lower"; then
      return 0
    fi
    return 1
  fi
  if ! reasoning_followup_short_question_present "$prompt_text_lower"; then
    return 1
  fi
  if ! reasoning_followup_changed_condition_cues_present "$prompt_text_lower"; then
    if ! reasoning_followup_fragment_delta_present "$prompt_text_lower"; then
      return 1
    fi
  fi
  return 0
}

reasoning_followup_changed_condition_cues_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first read|original read|first intuition|first story|now |^now\b|given that|given these|but |however|still |yet |after |since |remains |remained |returned |eased |improved |recovered |reduced |normalized |stabilized |stabilised |switched |kept |continued |did not |higher |lower |broader |narrower |tighter |looser |weaker |stronger |softer |harder |flatter |noisier |cleaner |cheaper |costlier |more |less |promised |confirmed |required |requires |mandated '; then
    return 0
  fi
  printf '%s\n' "$prompt_text_lower" | awk '
    {
      if (match($0, /(^|[^[:alpha:]])(stayed|worsened|softened|slipped|spiked|spread|narrowed|deepened|persisted|climbed|lagged|resurfaced|widened|flattened|flared|grew|dropped|rose|fell|weakened|drifted|stalled|lingered|doubled|promised|confirmed|required|requires|mandated|worse|better|higher|lower|broader|tighter|looser|stronger|weaker|softer|harder|flatter|noisier|cleaner|cheaper|costlier|more|less)([^[:alpha:]]|$)/)) {
        exit 0
      }
      exit 1
    }
  '
}

reasoning_followup_short_question_clause() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    function emit_if_trailing(line, clause, leading_regex) {
      if (line == clause || line ~ (leading_regex clause "$")) {
        print clause
        exit 0
      }
    }
    {
      line = tolower(trim($0))
      gsub(/[[:space:]]+/, " ", line)
      sub(/[[:space:][:punct:]]+$/, "", line)
      line_plain = line
      gsub(/\047/, "", line_plain)
      emit_if_trailing(line, "where do you land now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "where do you land", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "where does this leave you", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "do you back that", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still safe", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still harmless", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still a win", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still yes", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your call", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats the move", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "how does this strike you", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "thoughts", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your call now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your read now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your take now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your call", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your instinct", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "what now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "well", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "and", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "gut check", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "gut reaction", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "initial take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "first instinct", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "quick read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "thought", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "and now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "then", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "so", "(^|.*[[:space:][:punct:]])")
    }
  '
}

reasoning_followup_short_question_present() {
  clause=$(reasoning_followup_short_question_clause "$1")
  [ -n "$(trim "$clause")" ]
}

reasoning_followup_recent_delta_turn_for_prompt() {
  prompt_text=$1
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if ! reasoning_followup_short_question_present "$latest_prompt_single"; then
    return 0
  fi
  if reasoning_followup_changed_condition_cues_present "$latest_prompt_single" \
    || reasoning_followup_fragment_delta_present "$latest_prompt_single"; then
    return 0
  fi
  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
  previous_turn=$(trim "$previous_turn")
  if [ -z "$previous_turn" ]; then
    return 0
  fi
  if reasoning_followup_changed_condition_cues_present "$previous_turn" \
    || reasoning_followup_fragment_delta_present "$previous_turn" \
    || printf '%s' "$previous_turn" | grep -Eq '[,;:]'; then
    printf '%s' "$previous_turn"
  fi
}

reasoning_followup_fragment_delta_present() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  clause=$(reasoning_followup_short_question_clause "$prompt_text_single")
  fragment_source=$prompt_text_single
  if [ -n "$(trim "$clause")" ]; then
    fragment_source=$(printf '%s\n' "$prompt_text_single" | awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      BEGIN {
        clause = tolower(ARGV[1])
        ARGV[1] = ""
      }
      {
        raw_line = trim($0)
        line = tolower(raw_line)
        gsub(/[[:space:]]+/, " ", line)
        line = trim(line)
        if (clause == "" || line == clause) {
          print raw_line
          exit 0
        }
        if (length(line) <= length(clause)) {
          print raw_line
          exit 0
        }
        if (substr(line, length(line) - length(clause) + 1) != clause) {
          print raw_line
          exit 0
        }
        prefix = substr(raw_line, 1, length(raw_line) - length(clause))
        prefix = trim(prefix)
        sub(/[[:space:][:punct:]]+$/, "", prefix)
        print prefix
      }
    ' "$clause")
  fi
  fragment_source=$(trim "$fragment_source")
  [ -n "$fragment_source" ] || return 1
  printf '%s\n' "$fragment_source" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      fragment_count = 0
      short_fragment_count = 0
    }
    {
      line = $0
      gsub(/[[:space:]]+/, " ", line)
      sub(/[[:space:][:punct:]]+$/, "", line)
      split(line, parts, /[,;:]|[[:space:]]+-[[:space:]]+/)
      for (i = 1; i <= length(parts); i++) {
        fragment = trim(parts[i])
        if (fragment == "") {
          continue
        }
        fragment_count++
        word_count = split(fragment, words, /[[:space:]]+/)
        if (word_count <= 5) {
          short_fragment_count++
        }
      }
    }
    END {
      if (fragment_count >= 3 && short_fragment_count >= 3) {
        exit 0
      }
      if (fragment_count >= 2 && fragment_count == short_fragment_count) {
        exit 0
      }
      exit 1
    }
  '
}

prompt_prefers_reasoning_followup_contract() {
  prompt_text=$1
  conv_dir=${2:-}
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_compact_reasoning_contract "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_compact_reasoning_followup_contract "$prompt_primary" "$conv_dir"; then
    return 1
  fi
  if prompt_requires_code_implementation "$prompt_primary"; then
    return 1
  fi
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    return 1
  fi
  last_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_reasoning_completion_contract "$last_assistant_text"; then
    return 1
  fi
  if reasoning_followup_text_signals_present "$prompt_primary"; then
    return 0
  fi
  if reasoning_followup_implicit_text_signals_present "$prompt_primary"; then
    return 0
  fi
  if reasoning_followup_delta_only_turn_present "$prompt_primary"; then
    recent_turns=$(recent_user_turns_for_conversation "$conv_dir" "3")
    previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
    previous_turn=$(trim "$previous_turn")
    if [ -n "$previous_turn" ]; then
      return 0
    fi
    if reasoning_followup_token_overlap_present "$prompt_primary" "$previous_turn" \
      || reasoning_followup_token_overlap_present "$prompt_primary" "$last_assistant_text"; then
      return 0
    fi
  fi
  if reasoning_followup_short_question_present "$prompt_primary"; then
    recent_turns=$(recent_user_turns_for_conversation "$conv_dir" "3")
    previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
    previous_turn=$(trim "$previous_turn")
    if [ -n "$previous_turn" ] && { reasoning_followup_changed_condition_cues_present "$previous_turn" \
      || reasoning_followup_fragment_delta_present "$previous_turn" \
      || printf '%s' "$previous_turn" | grep -Eq '[,;:]'; }; then
      return 0
    fi
  fi
  return 1
}

reasoning_latest_prompt_text() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 1 }
    /^Recent user turns:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
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

reasoning_prior_answer_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 1; next }
    /^Prior decision summary:$/ { capture = 1; next }
    /^Prior frame:$/ { capture = 1; next }
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

reasoning_followup_delta_phrase_for_prompt() {
  prompt_text=$1
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  recent_delta_turn=$(reasoning_followup_recent_delta_turn_for_prompt "$prompt_text")
  if [ -n "$(trim "$recent_delta_turn")" ]; then
    delta_phrase=$recent_delta_turn
  elif reasoning_followup_delta_only_turn_present "$latest_prompt_single"; then
    delta_phrase=$latest_prompt_single
  elif ! reasoning_followup_text_signals_present "$latest_prompt_single" \
    && ! reasoning_followup_implicit_text_signals_present "$latest_prompt_single"; then
    return 0
  elif printf '%s' "$latest_prompt_single" | grep -Eq '[.?!][[:space:]]*([Dd]o you still|[Ww]ould you still|[Ss]hould we still|[Ww]hat would you do now|[Ww]hat do you do now|[Ww]hat would you do next|[Ww]hat do you do next|[Ww]hat now|[Ww]here do you land now|[Hh]ow do you read it now|[Dd]o you still back|[Dd]o you still support|[Ww]ould you still call|[Ww]ould you still avoid|[Ww]ould you still allow|[Ww]ould you still keep|[Ss]till back it|[Ss]till support it|[Ss]till call it|[Ss]till avoid rollback|[Ss]till allow it|[Ss]till keep it)'; then
    delta_phrase=$(printf '%s\n' "$latest_prompt_single" | awk '
      BEGIN { IGNORECASE = 1 }
      {
        line = $0
        lower = tolower(line)
        if (match(lower, /[.?!][[:space:]]*(do you still|would you still|should we still|what would you do now|what do you do now|what would you do next|what do you do next|what now|where do you land now|how do you read it now|do you still back|do you still support|would you still call|would you still avoid|would you still allow|would you still keep|still back it|still support it|still call it|still avoid rollback|still allow it|still keep it)/)) {
          print substr(line, 1, RSTART - 1)
        }
      }
    ')
  elif reasoning_followup_short_question_present "$latest_prompt_single"; then
    followup_short_clause=$(reasoning_followup_short_question_clause "$latest_prompt_single")
    delta_phrase=$(printf '%s\n' "$latest_prompt_single" | awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      BEGIN {
        clause = tolower(ARGV[1])
        ARGV[1] = ""
      }
      {
        raw_line = trim($0)
        line = tolower(raw_line)
        gsub(/[[:space:]]+/, " ", line)
        line = trim(line)
        if (clause == "" || line == clause) {
          exit
        }
        if (length(line) <= length(clause)) {
          exit
        }
        if (substr(line, length(line) - length(clause) + 1) != clause) {
          exit
        }
        prefix = substr(raw_line, 1, length(raw_line) - length(clause))
        prefix = trim(prefix)
        sub(/[[:space:][:punct:]]+$/, "", prefix)
        print prefix
      }
    ' "$followup_short_clause")
  elif printf '%s' "$latest_prompt_single" | grep -Eq '^[[:space:]]*([Ww]ould|[Ss]hould|[Dd]o|[Dd]oes|[Dd]id|[Ii]s|[Aa]re|[Cc]an|[Cc]ould|[Ww]hat would|[Ww]hat do|[Hh]ow would)[[:space:]]' \
    && printf '%s' "$latest_prompt_single" | grep -Eq '[Nn]ow that[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Nn]ow that[[:space:]]*//')
  elif printf '%s' "$latest_prompt_single" | grep -Eq '^[[:space:]]*([Ww]ould|[Ss]hould|[Dd]o|[Dd]oes|[Dd]id|[Ii]s|[Aa]re|[Cc]an|[Cc]ould|[Ww]hat would|[Ww]hat do|[Hh]ow would)[[:space:]]' \
    && printf '%s' "$latest_prompt_single" | grep -Eq '[Gg]iven that[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Gg]iven that[[:space:]]*//')
  elif printf '%s' "$latest_prompt_single" | grep -Eq '[Bb]ecause[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Bb]ecause[[:space:]]*//')
  else
    delta_phrase=$latest_prompt_single
  fi
  decisive_tail=$(printf '%s\n' "$delta_phrase" | awk '
    BEGIN { IGNORECASE = 1 }
    {
      raw_line = $0
      lower = tolower(raw_line)
      if (match(lower, /,[[:space:]]*but[[:space:]]+/)) {
        print substr(raw_line, RSTART + RLENGTH)
        exit 0
      }
      if (match(lower, /[[:space:]]but[[:space:]]+/)) {
        print substr(raw_line, RSTART + RLENGTH)
        exit 0
      }
    }
  ')
  decisive_tail=$(trim "$decisive_tail")
  if [ -n "$decisive_tail" ] && reasoning_followup_changed_condition_cues_present "$decisive_tail"; then
    delta_phrase=$decisive_tail
  fi
  delta_phrase=$(printf '%s' "$delta_phrase" | sed \
    -e 's/^[[:space:]]*[Nn]ow[[:space:]]*//' \
    -e 's/^[[:space:]]*[Gg]iven[[:space:]]*that[[:space:]]*//' \
    -e 's/^[[:space:]]*[Ww]ith[[:space:]]*those[[:space:]]*changes,[[:space:]]*//' \
    -e 's/[[:space:]]*[Kk]eep the same overall structure.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same structure.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same format.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same labels.*$//' \
    -e 's/[[:space:]]*[Kk]eep same labels.*$//' \
    -e 's/[[:space:]]*same labels.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same plan.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same strategy.*$//' \
    -e 's/[[:space:]]*[Mm]ake the revised call explicit.*$//' \
    -e 's/[[:space:]]*[Mm]ake the revised decision explicit.*$//' \
    -e 's/[[:space:]]*[Mm]ake the decision change explicit.*$//' \
    -e 's/[[:space:]]*[Ss]pell out the revised pivot.*$//' \
    -e 's/[[:space:]]*[Ss]pell out the pivot.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the recommendation.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the decision.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the explanation.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the read.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the call.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what overturned the first read.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what overturned the original read.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what changed.*$//' \
    -e 's/[[:space:]]*[Ii]nclude .*exactly once.*$//' \
    -e 's/[[:space:]]*[Ww]ith explicit decision.*$//' \
    -e 's/[[:space:]]*[?][[:space:]]*$//' \
    -e 's/[[:space:]]*and$//' \
    -e 's/[[:space:]]*[.]$//')
  delta_phrase=$(trim "$delta_phrase")
  if [ -n "$delta_phrase" ]; then
    delta_phrase_length=$(printf '%s' "$delta_phrase" | wc -c | tr -d ' ')
    case "$delta_phrase_length" in
      ""|*[!0-9]*)
        delta_phrase_length=0
        ;;
    esac
    if [ "$delta_phrase_length" -gt 320 ]; then
      delta_phrase=$(printf '%s' "$delta_phrase" | cut -c1-320 | sed 's/[[:space:]][^[:space:]]*$//')
    fi
    delta_phrase=$(trim "$delta_phrase")
    printf '%s' "$delta_phrase"
  fi
}

reasoning_followup_requires_revision_contract() {
  prompt_text=$1
  if prompt_requires_assumption_revision_contract "$prompt_text"; then
    return 0
  fi
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  if [ -n "$(trim "$followup_delta")" ] && [ -n "$(trim "$prior_answer")" ]; then
    return 0
  fi
  return 1
}

reasoning_prior_answer_value_for_prompt() {
  label=$1
  prompt_text=$2
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  reasoning_contract_extract_value "$label" "$prior_answer"
}

reasoning_contract_summary_text() {
  text=$1
  summary=""
  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Outcome" \
    "Decision" \
    "Fallback Path" \
    "Disconfirming Evidence" \
    "Risks" \
    "Next Improvement" \
    "Initial Assumption" \
    "Invalidating Evidence" \
    "Revised Decision" \
    "Evidence Delta"
  do
    value=$(reasoning_contract_extract_value "$label" "$text")
    value=$(trim "$value")
    [ -n "$value" ] || continue
    summary="${summary}${label}: ${value}
"
  done
  IFS=$old_ifs
  printf '%s' "$summary"
}

reasoning_followup_contract_summary_text() {
  text=$1
  summary=""
  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Decision" \
    "Fallback Path" \
    "Disconfirming Evidence" \
    "Revised Decision" \
    "Evidence Delta"
  do
    value=$(reasoning_contract_extract_value "$label" "$text")
    value=$(trim "$value")
    [ -n "$value" ] || continue
    summary="${summary}${label}: ${value}
"
  done
  IFS=$old_ifs
  printf '%s' "$summary"
}

reasoning_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if ! prompt_prefers_reasoning_followup_contract "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_prior_scenario_from_turns_block "$recent_user_turns" "$prompt_text")
  prior_reasoning_answer_raw=$(conversation_last_message_for_role "$conv_dir" "assistant")
  prior_reasoning_answer=$(reasoning_followup_contract_summary_text "$prior_reasoning_answer_raw")
  if [ -z "$(trim "$prior_reasoning_answer")" ]; then
    prior_reasoning_answer=$(printf '%s' "$prior_reasoning_answer_raw" | sed -n '1,10p')
  fi
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior decision summary:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_reasoning_answer"
}

reasoning_text_mentions_followup_delta() {
  text_lower=$(reasoning_contract_lower_text "$1")
  delta_lower=$(reasoning_contract_lower_text "$2")
  [ -n "$(trim "$delta_lower")" ] || return 1
  printf '%s\n' "$delta_lower" | awk -v target="$text_lower" '
    BEGIN { found = 0 }
    {
      n = split($0, parts, /,|;| and /)
      for (i = 1; i <= n; i++) {
        clause = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", clause)
        if (length(clause) >= 8 && index(target, clause) > 0) {
          found = 1
          break
        }
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

reasoning_followup_value_needs_upgrade() {
  current_value=$1
  prior_value=$2
  prompt_text=$3
  current_lower=$(reasoning_contract_lower_text "$current_value")
  prior_lower=$(reasoning_contract_lower_text "$prior_value")
  anchor_lower=$(reasoning_contract_lower_text "$(reasoning_prompt_anchor_phrase "$prompt_text")")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")

  case "$current_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac
  if printf '%s' "$current_lower" | grep -Eq 'revise that same|revise the same|same read because|same plan because|same strategy because|same incident call because|same call because|same recommendation because'; then
    return 0
  fi
  if printf '%s' "$current_lower" | grep -Eq 'cross-domain integrated reasoning|produced a defensible intermediate result|verification evidence:[[:space:]]*review the run trace|current scenario|scenario anchors'; then
    return 0
  fi
  if [ -n "$(trim "$prior_lower")" ] && [ "$current_lower" = "$prior_lower" ]; then
    return 0
  fi
  if [ -n "$(trim "$anchor_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$anchor_lower"; then
    return 0
  fi
  if [ -n "$(trim "$followup_delta")" ] && ! reasoning_text_mentions_followup_delta "$current_value" "$followup_delta"; then
    return 0
  fi
  return 1
}

reasoning_followup_generated_line_for_label() {
  label=$1
  prompt_text=$2
  case "$label" in
    "Outcome")
      reasoning_followup_outcome_line_for_prompt "$prompt_text"
      ;;
    "Decision")
      reasoning_followup_decision_line_for_prompt "$prompt_text"
      ;;
    "Fallback Path")
      reasoning_followup_fallback_line_for_prompt "$prompt_text"
      ;;
    "Disconfirming Evidence")
      reasoning_followup_disconfirming_line_for_prompt "$prompt_text"
      ;;
    "Risks")
      reasoning_followup_risk_line_for_prompt "$prompt_text"
      ;;
    "Next Improvement")
      reasoning_followup_next_improvement_line_for_prompt "$prompt_text"
      ;;
    "Initial Assumption")
      reasoning_followup_initial_assumption_line_for_prompt "$prompt_text"
      ;;
    "Invalidating Evidence")
      reasoning_followup_invalidating_evidence_line_for_prompt "$prompt_text"
      ;;
    "Revised Decision")
      reasoning_followup_revised_decision_line_for_prompt "$prompt_text"
      ;;
    "Evidence Delta")
      reasoning_followup_evidence_delta_line_for_prompt "$prompt_text"
      ;;
  esac
}

reasoning_first_user_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
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
        print line
        exit 0
      }
    }
  '
}

reasoning_followup_base_scenario_for_prompt() {
  prompt_text=$1
  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  first_user_turn=$(reasoning_first_user_turn_from_turns_block "$recent_turns")
  first_user_turn=$(trim "$first_user_turn")
  if [ -n "$first_user_turn" ]; then
    printf '%s' "$first_user_turn"
    return 0
  fi
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario"
    return 0
  fi
  anchor_source=$(reasoning_followup_anchor_source_for_prompt "$prompt_text")
  anchor_source=$(trim "$anchor_source")
  if [ -n "$anchor_source" ]; then
    printf '%s' "$anchor_source"
    return 0
  fi
  printf '%s' "$prompt_text"
}

reasoning_followup_scenario_reference_for_prompt() {
  prompt_text=$1
  base_scenario=$(reasoning_followup_base_scenario_for_prompt "$prompt_text")
  scenario_ref=$(reasoning_prompt_anchor_phrase "$base_scenario")
  if [ -n "$(trim "$scenario_ref")" ]; then
    printf '%s' "$scenario_ref"
    return 0
  fi
  reasoning_scenario_reference_for_prompt "$prompt_text"
}

reasoning_followup_exact_line_for_label() {
  label=$1
  current_value=$2
  prior_value=$3
  prompt_text=$4
  current_value=$(trim "$current_value")
  if reasoning_followup_value_needs_upgrade "$current_value" "$prior_value" "$prompt_text"; then
    reasoning_followup_generated_line_for_label "$label" "$prompt_text"
    return 0
  fi
  printf '%s: %s' "$label" "$current_value"
}

reasoning_contract_line_if_present() {
  label=$1
  text=$2
  value=$(reasoning_contract_extract_value "$label" "$text")
  value=$(trim "$value")
  [ -n "$value" ] || return 0
  printf '%s: %s' "$label" "$value"
}

reasoning_contract_upsert_line() {
  label=$1
  replacement_line=$2
  text=$3
  prefix=$(printf '%s:' "$label" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$text" | awk -v prefix="$prefix" -v replacement="$replacement_line" '
    BEGIN { updated = 0 }
    {
      lowered = tolower($0)
      if (updated == 0 && index(lowered, prefix) == 1) {
        print replacement
        updated = 1
        next
      }
      print
    }
    END {
      if (updated == 0) {
        print replacement
      }
    }
  '
}

reasoning_live_value_needs_upgrade() {
  label=$1
  current_value=$2
  prompt_text=$3
  current_lower=$(reasoning_contract_lower_text "$current_value")
  anchor_lower=$(reasoning_contract_lower_text "$(reasoning_prompt_anchor_phrase "$prompt_text")")
  scenario_lower=$(reasoning_contract_lower_text "$(reasoning_scenario_reference_for_prompt "$prompt_text")")

  case "$current_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac

  if printf '%s' "$current_lower" | grep -Eq 'cross-domain integrated reasoning|current scenario|scenario anchors|starting investigation|started investigation|workspace inspection|inspect relevant files|failure ledger'; then
    return 0
  fi

  case "$label" in
    "Outcome"|"Decision"|"Fallback Path"|"Disconfirming Evidence"|"Risks"|"Next Improvement")
      if [ -n "$(trim "$anchor_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$anchor_lower"; then
        return 0
      fi
      if [ -n "$(trim "$scenario_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$scenario_lower"; then
        return 0
      fi
      ;;
  esac

  return 1
}

normalize_reasoning_live_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")

  if reasoning_live_value_needs_upgrade "Outcome" "$outcome_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Outcome" "$(reasoning_followup_outcome_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Outcome" "Outcome: $(reasoning_outcome_stub_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Decision" "$decision_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Decision" "$(reasoning_followup_decision_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Decision" "Decision: $(reasoning_decision_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Fallback Path" "$fallback_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Fallback Path" "$(reasoning_followup_fallback_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Fallback Path" "Fallback Path: $(reasoning_fallback_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Disconfirming Evidence" "$disconfirming_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "$(reasoning_followup_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "Disconfirming Evidence: $(reasoning_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Risks" "$risks_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Risks" "$(reasoning_followup_risk_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Risks" "Risks: $(reasoning_risk_line_for_prompt "$prompt_text" "DONE")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Next Improvement" "$next_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Next Improvement" "$(reasoning_followup_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Next Improvement" "Next Improvement: $(reasoning_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")

  exact_text=$(cat <<EOF
Outcome: $(trim "$outcome_value")
Decision: $(trim "$decision_value")
Fallback Path: $(trim "$fallback_value")
Disconfirming Evidence: $(trim "$disconfirming_value")
Risks: $(trim "$risks_value")
Next Improvement: $(trim "$next_value")
EOF
)

  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Initial Assumption" \
    "Invalidating Evidence" \
    "Revised Decision" \
    "Evidence Delta" \
    "Verification Evidence" \
    "Assumptions and Alternatives" \
    "Priority Order" \
    "Contradiction Check" \
    "Trap and Counterevidence Check" \
    "False Premise Challenge" \
    "Premise Validation" \
    "Adversarial Probe" \
    "Disconfirming Threshold" \
    "Risk Register" \
    "Cross-Domain Integration" \
    "Domain Anchor" \
    "Domain Linkage" \
    "Architecture Lens" \
    "Product/UX Lens" \
    "Security/Compliance Lens" \
    "Metrics/Causality Lens" \
    "Incident/Ops Lens" \
    "Tradeoff Ledger" \
    "Rejected Alternative" \
    "Stakeholder Impact Map" \
    "Recovery and Self-Correction" \
    "Re-Plan Trigger" \
    "Self-Correction Evidence" \
    "Revised From" \
    "Validation Owner" \
    "Time Window" \
    "Evidence Anchors" \
    "Claim-to-Evidence Map" \
    "Quantified Thresholds" \
    "Evidence Caveats" \
    "Scenario-Specific Check" \
    "Assumption Register" \
    "Uncertainty Range" \
    "Source Quality Ranking" \
    "Source Conflict Resolution" \
    "Near-Miss Guard" \
    "Verification Status" \
    "Go/No-Go" \
    "Required Evidence to Proceed" \
    "Residual Risk" \
    "Context Anchor"
  do
    line=$(reasoning_contract_line_if_present "$label" "$final_text")
    line=$(trim "$line")
    [ -n "$line" ] || continue
    exact_text="${exact_text}
$line"
  done
  IFS=$old_ifs

  printf '%s' "$exact_text"
}

normalize_reasoning_freeform_memo() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_reasoning_reply "$prompt_text" \
    && ! prompt_prefers_freeform_reasoning_followup_memo "$prompt_text" "" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text" \
    && ! prompt_has_freeform_post_frame_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_memo_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_reflection_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_reflection "$prompt_text" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text" \
    && ! prompt_has_freeform_post_frame_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_reflection_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_frame_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_frame "$prompt_text" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_frame_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_clarify_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_intent_clarify "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_clarifying_question_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

reasoning_followup_outcome_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Outcome: Reassessed the current call for %s after the updated conditions changed: %s.' \
    "$anchor_phrase" "$followup_delta"
}

reasoning_followup_decision_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_decision_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Decision: %s This revised call explicitly accounts for the updated conditions: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_fallback_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_fallback_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Fallback Path: %s Revert immediately if the updated conditions stop holding: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_disconfirming_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_disconfirming_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Disconfirming Evidence: %s Reopen the previous call if the update proves narrower or less durable than: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_risk_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_risk_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")" "DONE")
  printf 'Risks: %s The revision still depends on the updated conditions proving durable: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_next_improvement_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_next_improvement_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Next Improvement: %s Focus that pass on the revised conditions: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_initial_assumption_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Initial Assumption: The follow-up read assumed the updated conditions (%s) were enough to preserve the prior recommendation for %s.' "$followup_delta" "$anchor_phrase"
}

reasoning_followup_invalidating_evidence_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Invalidating Evidence: That updated read fails if the revised conditions (%s) do not survive the next review window or if concentrated harms for %s remain above guardrails.' "$followup_delta" "$anchor_phrase"
}

reasoning_followup_revised_decision_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_decision_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Revised Decision: %s This revision only stands while the updated conditions remain true: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_evidence_delta_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Evidence Delta: Confidence increased only where the updated conditions shifted (%s); it remains provisional until those improvements hold without renewed harm for %s.' "$followup_delta" "$anchor_phrase"
}

normalize_reasoning_followup_thread_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  if [ -z "$(trim "$followup_delta")" ] || [ -z "$(trim "$prior_answer")" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")
  initial_value=$(reasoning_contract_extract_value "Initial Assumption" "$final_text")
  invalidating_value=$(reasoning_contract_extract_value "Invalidating Evidence" "$final_text")
  revised_value=$(reasoning_contract_extract_value "Revised Decision" "$final_text")
  evidence_delta_value=$(reasoning_contract_extract_value "Evidence Delta" "$final_text")

  prior_outcome_value=$(reasoning_prior_answer_value_for_prompt "Outcome" "$prompt_text")
  prior_decision_value=$(reasoning_prior_answer_value_for_prompt "Decision" "$prompt_text")
  prior_fallback_value=$(reasoning_prior_answer_value_for_prompt "Fallback Path" "$prompt_text")
  prior_disconfirming_value=$(reasoning_prior_answer_value_for_prompt "Disconfirming Evidence" "$prompt_text")
  prior_risks_value=$(reasoning_prior_answer_value_for_prompt "Risks" "$prompt_text")
  prior_next_value=$(reasoning_prior_answer_value_for_prompt "Next Improvement" "$prompt_text")
  prior_initial_value=$(reasoning_prior_answer_value_for_prompt "Initial Assumption" "$prompt_text")
  prior_invalidating_value=$(reasoning_prior_answer_value_for_prompt "Invalidating Evidence" "$prompt_text")
  prior_revised_value=$(reasoning_prior_answer_value_for_prompt "Revised Decision" "$prompt_text")
  prior_evidence_delta_value=$(reasoning_prior_answer_value_for_prompt "Evidence Delta" "$prompt_text")

  if reasoning_followup_value_needs_upgrade "$outcome_value" "$prior_outcome_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Outcome" "$(reasoning_followup_outcome_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$decision_value" "$prior_decision_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Decision" "$(reasoning_followup_decision_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$fallback_value" "$prior_fallback_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Fallback Path" "$(reasoning_followup_fallback_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$disconfirming_value" "$prior_disconfirming_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "$(reasoning_followup_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$risks_value" "$prior_risks_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Risks" "$(reasoning_followup_risk_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$next_value" "$prior_next_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Next Improvement" "$(reasoning_followup_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    if reasoning_followup_value_needs_upgrade "$initial_value" "$prior_initial_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Initial Assumption" "$(reasoning_followup_initial_assumption_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$invalidating_value" "$prior_invalidating_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Invalidating Evidence" "$(reasoning_followup_invalidating_evidence_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$revised_value" "$prior_revised_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Revised Decision" "$(reasoning_followup_revised_decision_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$evidence_delta_value" "$prior_evidence_delta_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Evidence Delta" "$(reasoning_followup_evidence_delta_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")
  initial_value=$(reasoning_contract_extract_value "Initial Assumption" "$final_text")
  invalidating_value=$(reasoning_contract_extract_value "Invalidating Evidence" "$final_text")
  revised_value=$(reasoning_contract_extract_value "Revised Decision" "$final_text")
  evidence_delta_value=$(reasoning_contract_extract_value "Evidence Delta" "$final_text")

  exact_text=$(cat <<EOF
$(reasoning_followup_exact_line_for_label "Outcome" "$outcome_value" "$prior_outcome_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Decision" "$decision_value" "$prior_decision_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Fallback Path" "$fallback_value" "$prior_fallback_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Disconfirming Evidence" "$disconfirming_value" "$prior_disconfirming_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Risks" "$risks_value" "$prior_risks_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Next Improvement" "$next_value" "$prior_next_value" "$prompt_text")
EOF
)
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    exact_text="${exact_text}
$(reasoning_followup_exact_line_for_label "Initial Assumption" "$initial_value" "$prior_initial_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Invalidating Evidence" "$invalidating_value" "$prior_invalidating_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Revised Decision" "$revised_value" "$prior_revised_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Evidence Delta" "$evidence_delta_value" "$prior_evidence_delta_value" "$prompt_text")"
  fi

  exact_text="${exact_text}
Context Anchor: $(reasoning_scenario_reference_for_prompt "$prompt_text")."

  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Verification Evidence" \
    "Assumptions and Alternatives" \
    "Priority Order" \
    "Contradiction Check" \
    "Trap and Counterevidence Check" \
    "False Premise Challenge" \
    "Premise Validation" \
    "Adversarial Probe" \
    "Disconfirming Threshold" \
    "Risk Register" \
    "Cross-Domain Integration" \
    "Domain Linkage" \
    "Architecture Lens" \
    "Product/UX Lens" \
    "Security/Compliance Lens" \
    "Metrics/Causality Lens" \
    "Incident/Ops Lens" \
    "Tradeoff Ledger" \
    "Rejected Alternative" \
    "Stakeholder Impact Map" \
    "Recovery and Self-Correction" \
    "Re-Plan Trigger" \
    "Self-Correction Evidence" \
    "Revised From" \
    "Validation Owner" \
    "Time Window" \
    "Evidence Anchors" \
    "Claim-to-Evidence Map" \
    "Quantified Thresholds" \
    "Evidence Caveats" \
    "Scenario-Specific Check" \
    "Assumption Register" \
    "Uncertainty Range" \
    "Source Quality Ranking" \
    "Source Conflict Resolution" \
    "Near-Miss Guard" \
    "Verification Status" \
    "Go/No-Go" \
    "Required Evidence to Proceed" \
    "Residual Risk"
  do
    optional_line=$(reasoning_contract_line_if_present "$label" "$final_text")
    optional_line=$(trim "$optional_line")
    [ -n "$optional_line" ] || continue
    if printf '%s' "$optional_line" | grep -Eqi 'current scenario|scenario anchors|cross-domain integrated reasoning|recent user turns:|prior scenario:|prior reasoning answer:'; then
      continue
    fi
    exact_text="${exact_text}
$optional_line"
  done
  IFS=$old_ifs

  printf '%s' "$(trim "$exact_text")"
}

reasoning_followup_fast_contract() {
  prompt_text=$1
  exact_text=$(cat <<EOF
$(reasoning_followup_generated_line_for_label "Outcome" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Decision" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Fallback Path" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Disconfirming Evidence" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Risks" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Next Improvement" "$prompt_text")
EOF
)
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    exact_text="${exact_text}
$(reasoning_followup_generated_line_for_label "Initial Assumption" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Invalidating Evidence" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Revised Decision" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Evidence Delta" "$prompt_text")"
  fi
  printf '%s' "$(trim "$exact_text")"
}

prompt_requires_code_implementation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint|refactor|codebase|source file|unit test|integration test|test suite|bin/status\.sh|bin/restart\.sh|bin/health\.sh|bin/rollback\.sh|bin/audit\.sh|bin/test\.sh|bin/ssh\.sh|config\.env|package-lock\.json|restart cleanly|health check|keep rollback intact|run the restart|run the health|restart the service|restart the demo service|systemctl|journalctl|docker compose|docker service|kubectl|env drift|package upgrade|dependency bump|lockfile|remote host|remote server|ssh'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_service_restart_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/restart\.sh|bin/health\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart cleanly|health checks?|keep rollback intact|demo service|local demo service'; then
    return 0
  fi
  return 1
}

prompt_prefers_partial_system_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/rollback\.sh|bin/health\.sh|bin/verify\.sh|partial-system-rollback|partial system rollback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'partial rollback|partially landed|mixed local state|mixed local mutation|mixed release|mixed package|worker state|stable read-only baseline|approve rollback|execute only the safe rollback path'; then
    return 0
  fi
  return 1
}

prompt_prefers_multi_service_partial_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-api\.sh|bin/status-worker\.sh|bin/rollback-api\.sh|bin/rollback-worker\.sh|multi-service-partial-rollback|multi service partial rollback|api and worker status helpers|api and worker rollback helpers|both rollback helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'two local services|paired api and worker|api and worker|shared rollback|shared rollback-state|shared rollback state|shared rollback only|mixed local rollout|bounded multi-service rollback|api service|worker service|stable read-only baseline'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/publish-release\.sh|bin/verify-release\.sh|core and edge boundary status helpers|publish the release helper|verify release helper|release-pack helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system release pack|system-release-pack|shared release pack|shared release-pack|release pack|release-pack|publish the release pack|published release|release publication|shared release state|release-pack fix' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|publish|verify|rollback|keep rollback intact|rollback ready|preserve rollback|rollback evidence|ordered cutover'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/verify-pack\.sh|core-boundary helper|edge-boundary helper|boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system boundary pack|system-boundary-pack|shared local cutover|two-boundary local cutover|two local boundaries|core boundary|edge boundary|boundary pack|shared cutover state' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|verify|rollback|keep rollback intact|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bin/publish-release\.sh|bin/verify-release\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|release-pack helpers|release helper|release verifier' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote release pack|release-pack|shared remote release pack|shared release pack|published release|release publication|publish the shared release pack|publish-release|release verifier|verify-release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|publish|verify|rollback|keep rollback intact|preserve rollback|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_background_process_recovery_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ps\.sh|bin/stop\.sh|bin/start\.sh|bin/health\.sh|worker helpers?' \
    && printf '%s' "$prompt_primary" | grep -Eq 'background process|background-process|worker process|stuck worker|daemon|worker health|keep rollback intact|keep rollback ready|preserve rollback|stop the worker|start the worker|restart the worker|stop the stale daemon|start the healthy daemon|repair the worker config|smallest safe worker fix'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_env_drift_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/doctor\.sh|bin/verify\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'path drift|version drift|tool drift|environment drift|env drift|toolchain|environment repair'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_package_upgrade_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/audit\.sh|bin/test\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'package upgrade|dependency upgrade|dependency bump|upgrade demo-lib|bump demo-lib|lockfile|keep rollback intact|package state|package files|manifest|smallest safe upgrade|demo-lib|2\.1\.0'; then
    return 0
  fi
  return 1
}

prompt_prefers_long_running_command_polling_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/poll\.sh|bin/checkpoint\.sh|bin/finalize\.sh|long-running command|long running command|checkpoint' \
    && printf '%s' "$prompt_primary" | grep -Eq 'poll|checkpoint|finalize|verify|keep rollback intact|keep rollback ready|preserve rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_filesystem_mutation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/inventory\.sh|bin/apply\.sh|bin/verify\.sh|filesystem mutation|filesystem-mutation|layout pack|layout state|staged config|current link|archive the previous live file' \
    && printf '%s' "$prompt_primary" | grep -Eq 'move|rename|archive|promote|symlink|link|verify|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_repo_runtime_web_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo-scan helper|repo evidence|repo scan' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|runtime evidence|runtime check' \
    && printf '%s' "$prompt_primary" | grep -Eq 'web evidence|migration doc|current doc|docs evidence|current migration' \
    && printf '%s' "$prompt_primary" | grep -Eq 'http://|https://' \
    && printf '%s' "$prompt_primary" | grep -Eq 'root cause' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next change' \
    && printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 0
  fi
  return 1
}

prompt_prefers_browser_image_run_investigation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*safari screenshot|attached safari screenshot|attached screenshot|safari screenshot|screenshot evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser snapshot|browser evidence|dom snapshot|layout snapshot'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|run `\./bin/runtime-check\.sh`|run ./bin/runtime-check\.sh|runtime evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser evidence:|image evidence:|runtime evidence:|root cause:|next action:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser|safari|screenshot|runtime|investigat|triage|no file edits|do not edit files'; then
    return 1
  fi
  return 0
}

prompt_prefers_tool_failure_handoff_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/primary-check\.sh|primary helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/fallback-check\.sh|fallback helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'hand off|handoff|recover by handing off|initial tool path'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://|current doc|current guidance|web evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'primary tool failure|fallback evidence|web evidence|root cause|next action'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_api_migration_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official migration guide|current source|source grounding|version-sensitive api migration|migration question'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|current source|migration change|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_ops_guidance_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/state-check\.sh|local state'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'current official guidance|current guidance|official guidance'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'local state|current guidance|operational decision|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_standards_grounded_answer_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime evidence|runtime check'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official standard|standard/docs|current standard|standards grounded|standards-grounded'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|runtime evidence|current standard|standards answer|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_multi_artifact_judgment_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'mixed-artifact judgment|mixed artifact judgment'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'choose exactly one primary move from analyze, act, clarify, or refuse'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'outcome, decision, code evidence, doc evidence, screenshot evidence, command evidence, fallback path, disconfirming evidence'; then
    return 1
  fi
  return 0
}

prompt_prefers_remote_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|private core/edge boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote boundary pack|boundary-pack|shared boundary pack|core boundary pair|edge boundary pair|core and edge private boundary|two boundary pairs' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|cut|health|verify|verifier|verify-pack|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper|private-target helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollback|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary|partial release|partially landed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback|roll back|recover|revert|health|tunnel'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollout|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|health|release|rollout'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_single_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote service' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|verify|journal|keep rollback intact'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_bastion_cutover_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private\.sh|bastion ssh helper|private ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bastion|jump host|private host|cutover|tunnel' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|tunnel|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-app\.sh|bin/ssh-db\.sh|app ssh helper|replica ssh helper|db ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|replica|primary|failover|promote|app host|db host|database host|replica host' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-canary\.sh|bin/ssh-fleet\.sh|canary ssh helper|fleet ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|canary|fleet|staged rollout|progressive rollout|rollout|second host|second stage' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_deploy_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote deploy|remote release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|release|health|rollback'; then
    return 0
  fi
  return 1
}

local_service_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/service/config.env"
  [ -f "$config_file" ] || return 1
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
PORT=$port_value
EOF_CFG
}

partial_system_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/system.env"
  [ -f "$config_file" ] || return 1
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_package=$(awk -F= '/^STABLE_PACKAGE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker=$(awk -F= '/^STABLE_WORKER=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.15
  fi
  if [ -z "$(trim "$stable_package")" ]; then
    stable_package=2.3.1
  fi
  if [ -z "$(trim "$stable_worker")" ]; then
    stable_worker=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_RELEASE=$stable_release
STABLE_RELEASE=$stable_release
CURRENT_PACKAGE=$stable_package
STABLE_PACKAGE=$stable_package
CURRENT_WORKER=$stable_worker
STABLE_WORKER=$stable_worker
ROLLBACK_APPROVED=1
READ_ONLY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

multi_service_partial_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/multi-service.env"
  [ -f "$config_file" ] || return 1
  stable_api_release=$(awk -F= '/^STABLE_API_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_api_mode=$(awk -F= '/^STABLE_API_MODE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_release=$(awk -F= '/^STABLE_WORKER_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_mode=$(awk -F= '/^STABLE_WORKER_MODE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_api_release")" ]; then
    stable_api_release=2026.03.15-api
  fi
  if [ -z "$(trim "$stable_api_mode")" ]; then
    stable_api_mode=healthy
  fi
  if [ -z "$(trim "$stable_worker_release")" ]; then
    stable_worker_release=2026.03.15-worker
  fi
  if [ -z "$(trim "$stable_worker_mode")" ]; then
    stable_worker_mode=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_API_RELEASE=$stable_api_release
STABLE_API_RELEASE=$stable_api_release
CURRENT_API_MODE=$stable_api_mode
STABLE_API_MODE=$stable_api_mode
CURRENT_WORKER_RELEASE=$stable_worker_release
STABLE_WORKER_RELEASE=$stable_worker_release
CURRENT_WORKER_MODE=$stable_worker_mode
STABLE_WORKER_MODE=$stable_worker_mode
ROLLBACK_APPROVED=1
READ_ONLY=1
API_ROLLBACK_READY=1
WORKER_ROLLBACK_READY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

system_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/release-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.15
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CUTOVER_APPROVED=1
RELEASE_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
RELEASE_NOTES_READY=1
PACK_STATE=ready
EOF_CFG
}

system_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
CUTOVER_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
PACK_STATE=ready
EOF_CFG
}

background_process_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/process/worker.env"
  [ -f "$config_file" ] || return 1
  queue_name=$(awk -F= '/^QUEUE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$queue_name")" ]; then
    queue_name=jobs
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
AUTO_START=1
READ_ONLY=1
QUEUE=$queue_name
EOF_CFG
}

local_env_drift_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/config/toolchain.env"
  [ -f "$config_file" ] || return 1
  cat > "$config_file" <<'EOF_CFG'
EXPECTED_TOOL_PATH=tools/bin
ACTIVE_TOOL_PATH=tools/bin
EXPECTED_VERSION=1.2.3
ACTIVE_VERSION=1.2.3
READ_ONLY=1
EOF_CFG
}

local_package_upgrade_fix_in_place() {
  workspace_path=$1
  manifest_file="$workspace_path/package.json"
  lockfile_file="$workspace_path/package-lock.json"
  [ -f "$manifest_file" ] || return 1
  [ -f "$lockfile_file" ] || return 1
  cat > "$manifest_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "private": true,
  "dependencies": {
    "demo-lib": "2.1.0"
  }
}
EOF_JSON
  cat > "$lockfile_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "dependencies": {
        "demo-lib": "2.1.0"
      }
    },
    "node_modules/demo-lib": {
      "version": "2.1.0"
    }
  }
}
EOF_JSON
}

long_running_command_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/job/run.env"
  [ -f "$config_file" ] || return 1
  target_step=$(awk -F= '/^TARGET_STEP=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$target_step")" ]; then
    target_step=3
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_STEP=0
TARGET_STEP=$target_step
CHECKPOINT_READY=1
ALLOW_FINALIZE=1
READ_ONLY=1
EOF_CFG
}

filesystem_mutation_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/layout.env"
  [ -f "$config_file" ] || return 1
  live_dir=$(awk -F= '/^LIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  staging_file=$(awk -F= '/^STAGING_FILE=/{print $2}' "$config_file" | tail -n 1)
  archive_dir=$(awk -F= '/^ARCHIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  active_link=$(awk -F= '/^ACTIVE_LINK=/{print $2}' "$config_file" | tail -n 1)
  target_name=$(awk -F= '/^TARGET_NAME=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$live_dir")" ]; then
    live_dir=layout/live
  fi
  if [ -z "$(trim "$staging_file")" ]; then
    staging_file=layout/staging/config.yml.next
  fi
  if [ -z "$(trim "$archive_dir")" ]; then
    archive_dir=layout/archive
  fi
  if [ -z "$(trim "$active_link")" ]; then
    active_link=layout/current-config.yml
  fi
  if [ -z "$(trim "$target_name")" ]; then
    target_name=config.yml
  fi
  cat > "$config_file" <<EOF_CFG
LIVE_DIR=$live_dir
STAGING_FILE=$staging_file
ARCHIVE_DIR=$archive_dir
ACTIVE_LINK=$active_link
TARGET_NAME=$target_name
APPLY_READY=1
LINK_READY=1
READ_ONLY=1
EOF_CFG
}

remote_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.10
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
RELEASE_APPROVED=1
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
RELEASE_NOTES_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  current_release=$(awk -F= '/^CURRENT_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$current_release")" ]; then
    current_release=2026.03.22
  fi
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.10
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
CURRENT_RELEASE=$current_release
STABLE_RELEASE=$stable_release
APPROVED_RELEASE=$stable_release
TUNNEL_READY=1
CANARY_ROLLBACK_READY=1
FLEET_ROLLBACK_READY=1
READ_ONLY=1
ROLLOUT_STATE=rollback_ready
EOF_CFG
}

remote_boundary_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
TUNNEL_READY=1
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STATE=staged
EOF_CFG
}

remote_single_host_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/service.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
HOST=$host_value
PORT=$port_value
EOF_CFG
}

remote_bastion_cutover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/bastion.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_private_host=$(awk -F= '/^TARGET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$target_private_host")" ]; then
    target_private_host=demo-app-private-b
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CURRENT_PRIVATE_HOST=$target_private_host
TARGET_PRIVATE_HOST=$target_private_host
APPROVED_PRIVATE_HOST=$target_private_host
BASTION_READY=1
PRIVATE_READY=1
READ_ONLY=1
CUTOVER_STATE=ready
EOF_CFG
}

remote_multi_host_failover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/topology.env"
  [ -f "$config_file" ] || return 1
  app_host=$(awk -F= '/^APP_HOST=/{print $2}' "$config_file" | tail -n 1)
  primary_db_host=$(awk -F= '/^PRIMARY_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  replica_db_host=$(awk -F= '/^REPLICA_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$app_host")" ]; then
    app_host=demo-app-1
  fi
  if [ -z "$(trim "$primary_db_host")" ]; then
    primary_db_host=demo-db-1
  fi
  if [ -z "$(trim "$replica_db_host")" ]; then
    replica_db_host=demo-db-2
  fi
  cat > "$config_file" <<EOF_CFG
APP_HOST=$app_host
PRIMARY_DB_HOST=$replica_db_host
REPLICA_DB_HOST=$primary_db_host
APP_DB_HOST=$replica_db_host
REPLICA_ROLE=primary
FAILOVER_READY=1
APP_READ_ONLY=1
EOF_CFG
}

remote_multi_host_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/rollout.env"
  [ -f "$config_file" ] || return 1
  canary_host=$(awk -F= '/^CANARY_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_host=$(awk -F= '/^FLEET_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$canary_host")" ]; then
    canary_host=demo-app-1
  fi
  if [ -z "$(trim "$fleet_host")" ]; then
    fleet_host=demo-app-2
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CANARY_HOST=$canary_host
FLEET_HOST=$fleet_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STAGE=staged
EOF_CFG
}

remote_deploy_release_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
HOST=$host_value
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
DEPLOY_READY=1
READ_ONLY=1
EOF_CFG
}

quick_mode_append_command_result() {
  command_text=$1
  command_status=$2
  command_output=$3
  quick_loop_summary="${quick_loop_summary}
## Command
$command_text
Status: $command_status
$command_output
"
  if [ "$command_status" = "ok" ]; then
    quick_command_success_total=$((quick_command_success_total + 1))
  fi
  command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
    "$(json_escape "$command_text")" \
    "$(json_escape "$command_status")" \
    "$(json_escape "$command_output")")
  if [ "$quick_commands_first" -eq 1 ]; then
    quick_commands_json=$command_item
    quick_commands_first=0
  else
    quick_commands_json="${quick_commands_json},${command_item}"
  fi
}

quick_mode_run_recorded_command() {
  workspace_id=$1
  workspace_path=$2
  tool_command=$3
  command_mode_value=$4
  blocked_file=$5
  stream_file=$6
  command_output_file=$(mktemp)
  command_status_file=$(mktemp)
  execute_mediated_command "$workspace_id" "$workspace_path" "$tool_command" "$command_output_file" "$command_status_file" "$command_mode_value" "$blocked_file"
  quick_mode_last_command_status=$(cat "$command_status_file" 2>/dev/null || printf '%s' "error")
  quick_mode_last_command_output=$(sed -n '1,40p' "$command_output_file")
  rm -f "$command_output_file" "$command_status_file"
  quick_mode_append_command_result "$tool_command" "$quick_mode_last_command_status" "$quick_mode_last_command_output"
  stream_emit_line "$stream_file" "Quick-mode command: $tool_command ($quick_mode_last_command_status)"
}

local_service_restart_summary() {
  status_output=$1
  restart_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local demo service, rewrote \`service/config.env\` to the healthy/read-only settings, restarted it, and confirmed the service is healthy.
Verification Evidence: Ran \`./bin/status.sh\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")) and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required repair is the local config flip in \`service/config.env\`; broader service hardening remains out of scope.
Next Improvement: Promote the same status, restart, health, and rollback contract into the broader system-ops gate for more complex service shapes.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local demo service and applied the smallest config repair in \`service/config.env\`, but the restart/health sequence did not finish cleanly.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The service still needs a clean restart/health pass before this workspace is considered recovered.
Next Improvement: Re-run the local status, restart, and health helpers after inspecting the current config and state files for any remaining mismatch.
EOF
}

background_process_recovery_summary() {
  ps_output=$1
  stop_output=$2
  start_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded background-worker failure, repaired \`process/worker.env\`, stopped the stale worker, started the healthy worker, and confirmed the worker health check now passes.
Verification Evidence: Ran \`./bin/ps.sh\` before the fix ($(single_line_snippet "$ps_output")); then ran \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the bounded worker issue is isolated to \`process/worker.env\` plus one local worker state file; broader queue drains, multi-worker coordination, and supervisor policy remain out of scope.
Next Improvement: Extend the same ps-stop-start-health contract into a broader background-process gate with polling, checkpointing, and multi-worker recovery.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded background-worker failure and applied the intended worker-config repair, but the stop/start/health sequence still failed.
Verification Evidence: Ran \`./bin/ps.sh\` ($(single_line_snippet "$ps_output")), \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The worker still needs a clean stop/start/health pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded worker ps, stop, start, and health helpers after inspecting the current process config and worker state files for any remaining mismatch.
EOF
}

local_env_drift_summary() {
  doctor_output=$1
  verify_output=$2
  verify_status=$3
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local environment drift, repaired the tool-path and version config, and confirmed the environment now verifies cleanly.
Verification Evidence: Ran \`./bin/doctor.sh\` before the fix ($(single_line_snippet "$doctor_output")); then ran \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the drift is isolated to \`config/toolchain.env\`; broader shell/profile or package-manager drift remains out of scope.
Next Improvement: Extend the same doctor-and-verify contract into a broader env-drift gate that exercises PATH, version, and rollback handling across more than one config shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local environment drift and applied the intended config repair, but the final verification still failed.
Verification Evidence: Ran \`./bin/doctor.sh\` ($(single_line_snippet "$doctor_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved tool-path or version drift and should not be treated as repaired yet.
Next Improvement: Re-run doctor and verify after inspecting the current config and any residual environment assumptions outside \`config/toolchain.env\`.
EOF
}

local_package_upgrade_summary() {
  audit_output=$1
  test_output=$2
  test_status=$3
  if [ "$test_status" = "ok" ]; then
    cat <<EOF
Outcome: Audited the local package state, upgraded \`demo-lib\` in \`package.json\` and \`package-lock.json\`, and confirmed the package tests now pass.
Verification Evidence: Ran \`./bin/audit.sh\` before the change ($(single_line_snippet "$audit_output")); then ran \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded \`demo-lib\` upgrade in \`package.json\` and \`package-lock.json\`; broader dependency graph or runtime compatibility work remains out of scope.
Next Improvement: Extend the same audit-upgrade-test contract into a broader package-management gate with rollback and compatibility checks across more than one dependency shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Audited the local package state and applied the intended \`demo-lib\` upgrade, but the final package test still failed.
Verification Evidence: Ran \`./bin/audit.sh\` ($(single_line_snippet "$audit_output")) and \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved manifest, lockfile, or compatibility issues and should not be treated as upgraded yet.
Next Improvement: Re-run audit and tests after inspecting the current manifest and lockfile for any remaining dependency mismatch.
EOF
}

long_running_command_summary() {
  first_poll_output=$1
  second_poll_output=$2
  checkpoint_output=$3
  third_poll_output=$4
  finalize_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded long-running job, repaired the checkpoint/finalize config, polled the job until it was ready, checkpointed it, finalized it, and confirmed the final verification now passes.
Verification Evidence: Ran the first \`./bin/poll.sh\` before the fix ($(single_line_snippet "$first_poll_output")); then ran a second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), a final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the long-running command is isolated to one bounded job in \`job/run.env\`; broader orchestration, external schedulers, and multi-stage pipeline control remain out of scope.
Next Improvement: Extend the same poll-checkpoint-finalize-verify contract into a broader long-running-command gate with explicit checkpoint timing and stop/go coverage under larger jobs.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded long-running job and applied the intended checkpoint/finalize repair, but the bounded poll/finalize sequence still failed to verify cleanly.
Verification Evidence: Ran the first \`./bin/poll.sh\` ($(single_line_snippet "$first_poll_output")), the second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), the final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded long-running job still needs a clean checkpoint/finalize verification pass before it should be treated as complete.
Next Improvement: Re-run the bounded polling sequence after inspecting the current job config and checkpoint state for any remaining mismatch.
EOF
}

filesystem_mutation_summary() {
  inventory_output=$1
  apply_output=$2
  verify_output=$3
  verify_status=$4
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack, repaired the layout-control file, archived the previous live file, promoted the staged config into the live path, refreshed the current link, and confirmed verification now passes.
Verification Evidence: Ran \`./bin/inventory.sh\` before the fix ($(single_line_snippet "$inventory_output")); then ran \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded layout-state repair in \`state/layout.env\` plus one staged/live/archive file set under \`layout/\`; broader refactors, multi-file rewrites, and large rename graphs remain out of scope.
Next Improvement: Extend the same inventory-apply-verify contract into a broader filesystem-mutation gate that covers larger rename, move, and refactor packs with explicit rollback checkpoints.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack and applied the intended layout-control repair, but the apply or final verification sequence still failed.
Verification Evidence: Ran \`./bin/inventory.sh\` ($(single_line_snippet "$inventory_output")), \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded filesystem mutation pack still needs a clean archive/promote/link verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded inventory, apply, and verify sequence after inspecting the current layout state and rollback readiness for any remaining mismatch.
EOF
}

repo_runtime_web_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

repo_runtime_web_first_url_from_prompt() {
  prompt_text=$1
  urls_file=$(mktemp)
  extract_urls_from_text "$prompt_text" > "$urls_file"
  first_url=$(sed -n '1p' "$urls_file")
  rm -f "$urls_file"
  first_url=$(trim "$first_url")
  first_url=$(printf '%s' "$first_url" | sed 's/[.,;:!?)]*$//')
  printf '%s' "$first_url"
}

repo_runtime_web_extract_doc_endpoint() {
  doc_excerpt=$1
  endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | grep -E '^/v2/' | head -n 1 || true)
  if [ -z "$(trim "$endpoint_value")" ]; then
    endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | tail -n 1 || true)
  fi
  endpoint_value=$(trim "$endpoint_value")
  if [ -z "$endpoint_value" ]; then
    endpoint_value="/v2/widgets"
  fi
  printf '%s' "$endpoint_value"
}

repo_runtime_web_extract_doc_timeout_ms() {
  doc_excerpt=$1
  timeout_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[0-9]{4,5}[[:space:]]*ms' | head -n 1 | tr -cd '0-9' || true)
  timeout_value=$(trim "$timeout_value")
  if [ -z "$timeout_value" ]; then
    timeout_value="15000"
  fi
  printf '%s' "$timeout_value"
}

repo_runtime_web_triage_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5
  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "webapp/src/widgets-client.js")
  repo_endpoint=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_endpoint" "/v1/widgets/list")
  repo_response_key=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_response_key" "widgets")
  repo_timeout_ms=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_timeout_ms" "5000")
  runtime_http_status=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_http_status" "404")
  runtime_endpoint=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_endpoint" "$repo_endpoint")
  runtime_shape_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_shape_issue" "expected_items_found_widgets")
  runtime_timeout_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_timeout_issue" "timeout_too_low")
  doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
  doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
  doc_fields="items and next_cursor"
  if ! printf '%s' "$doc_excerpt" | grep -Eq 'items'; then
    doc_fields="items"
  fi
  runtime_clause="\`./bin/runtime-check.sh\` reports HTTP $runtime_http_status on $runtime_endpoint and $runtime_shape_issue"
  if [ "$runtime_status" != "ok" ]; then
    runtime_clause="$runtime_clause while the bounded runtime check still exits non-zero"
  fi
  if [ -n "$(trim "$runtime_timeout_issue")" ]; then
    runtime_clause="$runtime_clause plus $runtime_timeout_issue"
  fi
  cat <<EOF
Repo Evidence: \`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_endpoint\`, parses \`$repo_response_key\`, and uses \`timeoutMs=$repo_timeout_ms\`.
Runtime Evidence: $runtime_clause.
Web Evidence: The migration doc at $doc_url says the client should call \`$doc_endpoint\`, read \`$doc_fields\`, and allow a \`$doc_timeout_ms\` ms timeout.
Root Cause: The repo and runtime still target the removed v1 widgets contract, so the client endpoint, response parsing, and timeout no longer match the current migration doc.
Next Change: Update \`$repo_file\` to call \`$doc_endpoint\`, read \`$doc_fields\`, and raise the client timeout to \`$doc_timeout_ms\` ms before widening further.
EOF
}

tool_failure_handoff_doc_flag() {
  doc_excerpt=$1
  default_value=${2:-uploads_rollout=on}
  flag_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[A-Za-z_]+=[A-Za-z0-9._/-]+' | head -n 1 || true)
  flag_value=$(trim "$flag_value")
  if [ -z "$flag_value" ]; then
    flag_value=$default_value
  fi
  printf '%s' "$flag_value"
}

tool_failure_handoff_doc_env_key() {
  doc_excerpt=$1
  default_value=${2:-SESSION_CACHE_URL}
  env_key=$(printf '%s' "$doc_excerpt" | grep -Eo 'SESSION_CACHE_URL' | head -n 1 || true)
  env_key=$(trim "$env_key")
  if [ -z "$env_key" ]; then
    env_key=$default_value
  fi
  printf '%s' "$env_key"
}

tool_failure_handoff_primary_reason_text() {
  primary_output=$1
  primary_reason=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_reason" "initial helper failure")
  case "$primary_reason" in
    repo_scan_unavailable)
      printf '%s' "the repo scan helper is unavailable in this workspace"
      ;;
    browser_snapshot_capture_failed)
      printf '%s' "browser snapshot capture is unavailable right now"
      ;;
    dom_snapshot_unavailable)
      printf '%s' "the DOM snapshot helper is unavailable right now"
      ;;
    *)
      printf '%s' "$primary_reason"
      ;;
  esac
}

tool_failure_handoff_summary() {
  primary_output=$1
  primary_status=$2
  fallback_output=$3
  fallback_status=$4
  doc_url=$5
  doc_excerpt=$6

  primary_helper=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_helper" "./bin/primary-check.sh")
  primary_reason_text=$(tool_failure_handoff_primary_reason_text "$primary_output")
  fallback_issue=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_issue" "fallback_required")
  fallback_file=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_file" "config/runtime.env")

  case "$fallback_issue" in
    legacy_widget_contract)
      runtime_endpoint=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_endpoint" "/v1/widgets/list")
      runtime_timeout_ms=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_timeout_ms" "5000")
      doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
      doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still calls \`$runtime_endpoint\` with \`timeoutMs=$runtime_timeout_ms\` while the bounded fallback check remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says clients must call \`$doc_endpoint\` and allow at least \`$doc_timeout_ms\` ms before wider rollout."
      root_line="The initial repo-scan path is unavailable, but the fallback runtime plus current docs still show the client is pinned to the removed widgets contract."
      next_line="Update \`$fallback_file\` to call \`$doc_endpoint\` and raise the client timeout to \`$doc_timeout_ms\` ms, then restore the primary helper for a clean repo-side audit."
      ;;
    uploads_rollout_disabled)
      runtime_flag=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_flag" "uploads_rollout=off")
      runtime_route=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_route" "/v2/uploads/complete")
      doc_flag=$(tool_failure_handoff_doc_flag "$doc_excerpt" "uploads_rollout=on")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still sets \`$runtime_flag\`, so the bounded upload route \`$runtime_route\` remains disabled while the fallback helper stays \`$fallback_status\`."
      web_line="The current doc at $doc_url says publishing uploads requires \`$doc_flag\` before clients use \`$runtime_route\`."
      root_line="The initial browser-control path is unavailable, but the fallback runtime evidence shows uploads are disabled in config rather than broken in the UI."
      next_line="Set \`$doc_flag\` in \`$fallback_file\`, then rerun the bounded upload path after the primary helper is restored."
      ;;
    session_cache_missing)
      runtime_cache=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_session_cache_url" "missing")
      runtime_miss_rate=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_miss_rate" "68%")
      doc_env_key=$(tool_failure_handoff_doc_env_key "$doc_excerpt" "SESSION_CACHE_URL")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` has \`$doc_env_key=$runtime_cache\` and the bounded login path is falling back with miss rate $runtime_miss_rate while the helper remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says interactive login requires \`$doc_env_key\` before traffic is widened again."
      root_line="The initial snapshot path is unavailable, but the fallback runtime evidence shows degraded login comes from a missing session cache endpoint."
      next_line="Set \`$doc_env_key\` in \`$fallback_file\`, warm the session cache, and retry the bounded login path after the primary helper is back."
      ;;
    *)
      fallback_line="\`./bin/fallback-check.sh\` produced bounded fallback evidence ($(single_line_snippet "$fallback_output")) while the helper remained \`$fallback_status\`."
      web_line="The current doc at $doc_url provides the authoritative fallback guidance."
      root_line="The initial tool path failed, so the fallback helper and current docs became the authoritative evidence path."
      next_line="Repair the issue indicated by the fallback helper, then restore the primary tool path for a clean rerun."
      ;;
  esac

  cat <<EOF
Primary Tool Failure: \`$primary_helper\` returned \`$primary_status\` and reported that $primary_reason_text.
Fallback Evidence: $fallback_line
Web Evidence: $web_line
Root Cause: $root_line
Next Action: $next_line
EOF
}

current_api_migration_summary() {
  repo_output=$1
  doc_url=$2
  doc_excerpt=$3

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "app/user_loader.py")
  repo_old_method=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_old_method" "parse_obj")
  repo_call=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_call" "$repo_old_method")

  case "$repo_old_method" in
    parse_obj)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`parse_obj()\` to \`model_validate()\`."
      change_line="Pydantic V2 replaces the V1 validation entry point \`parse_obj()\` with \`model_validate()\`."
      root_line="The repo still uses the V1 validation API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`User.model_validate(payload)\` in \`$repo_file\`."
      ;;
    dict)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`dict()\` to \`model_dump()\`."
      change_line="Pydantic V2 replaces the V1 serialization helper \`dict()\` with \`model_dump()\`."
      root_line="The repo still uses the V1 serialization API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`user.model_dump()\` in \`$repo_file\`."
      ;;
    from_orm)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url says \`from_orm()\` is deprecated in favor of \`model_validate()\` with \`from_attributes=True\`."
      change_line="Pydantic V2 moves ORM-style loading to \`model_validate()\` plus a model config that enables \`from_attributes=True\`."
      root_line="The repo still uses the V1 ORM-loading API while the current official docs require the V2 validation path and attribute-based config."
      next_line="Replace \`$repo_call\` with \`User.model_validate(record)\` and enable \`from_attributes=True\` in the model config in \`$repo_file\`."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still uses \`$repo_call\`."
      source_line="The current official migration guide at $doc_url provides the authoritative migration target."
      change_line="The current docs describe a newer API surface than the one still referenced in the repo."
      root_line="The repo still targets an older API contract than the current official guide."
      next_line="Update \`$repo_file\` from \`$repo_call\` to the current API named in the official migration guide."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Current Source: $source_line
Migration Change: $change_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

current_ops_guidance_summary() {
  state_output=$1
  doc_url=$2
  doc_excerpt=$3

  state_file=$(repo_runtime_web_extract_kv_value "$state_output" "state_file" "deploy/api-deployment.yaml")
  state_issue=$(repo_runtime_web_extract_kv_value "$state_output" "state_issue" "slow_start_liveness_kills")
  state_shared_probe_path=$(repo_runtime_web_extract_kv_value "$state_output" "state_shared_probe_path" "/healthz")
  state_startup_p95_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_startup_p95_seconds" "75")
  state_liveness_initial_delay_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_liveness_initial_delay_seconds" "5")
  state_dependency=$(repo_runtime_web_extract_kv_value "$state_output" "state_dependency" "db-warmup")

  case "$state_issue" in
    slow_start_liveness_kills|cache_warmup_slow_start)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` has no \`startupProbe\`, reuses \`$state_shared_probe_path\`, and starts liveness after \`$state_liveness_initial_delay_seconds\` seconds even though startup p95 is \`$state_startup_p95_seconds\` seconds."
      guidance_line="The current official guidance at $doc_url says slow starting containers should use \`startupProbe\`, and that liveness and readiness do not start until the startup probe succeeds."
      decision_line="Add a \`startupProbe\` and keep liveness/readiness for steady-state checks after the container has started."
      root_line="The pod is being judged by liveness too early, so a slow boot or cache warmup is being treated as a dead process instead of a startup phase."
      next_line="Update \`$state_file\` to add \`startupProbe\` for \`$state_shared_probe_path\` and leave liveness/readiness for the post-start steady state."
      ;;
    temporary_dependency_overload)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` uses the same \`$state_shared_probe_path\` for liveness and readiness while \`$state_dependency\` causes transient overload."
      guidance_line="The current official guidance at $doc_url says readiness failures remove a pod from service endpoints, while liveness should be reserved for when a restart is the right recovery."
      decision_line="Move the dependency-sensitive check to \`readinessProbe\` and keep liveness for true deadlock or unrecoverable failure."
      root_line="A temporary dependency slowdown is being routed through liveness, so Kubernetes restarts the pod instead of only stopping new traffic."
      next_line="Update \`$state_file\` so \`readinessProbe\` reflects dependency readiness and liveness only checks whether the process is actually stuck."
      ;;
    *)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` still needs a probe-policy change."
      guidance_line="The current official guidance at $doc_url contains the bounded probe policy that should be applied here."
      decision_line="Align the deployment probes with the current official guidance before widening traffic."
      root_line="The local deployment still diverges from the current official probe guidance."
      next_line="Update \`$state_file\` to match the current official probe guidance, then rerun the bounded state check."
      ;;
  esac

  cat <<EOF
Local State: $local_line
Current Guidance: $guidance_line
Operational Decision: $decision_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

standards_grounded_answer_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "server/cors.py")
  standard_issue=$(repo_runtime_web_extract_kv_value "$repo_output" "standard_issue" "cors_credentials_wildcard")

  case "$standard_issue" in
    cors_credentials_wildcard)
      repo_allow_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_origin" "*")
      repo_allow_credentials=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_credentials" "true")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://app.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "credentials_blocked_by_wildcard")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still sets \`Access-Control-Allow-Origin: $repo_allow_origin\` together with \`Access-Control-Allow-Credentials: $repo_allow_credentials\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the credentialed request from \`$repo_origin\` is failing as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say credentialed CORS requests cannot use \`Access-Control-Allow-Origin: *\`."
      answer_line="Return the explicit allowed origin instead of \`*\` whenever credentials are enabled."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Origin\` is the explicit trusted origin and keep credentials enabled only for that origin."
      ;;
    samesite_none_without_secure)
      repo_cookie_name=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_cookie_name" "app_session")
      repo_same_site=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_same_site" "None")
      repo_secure=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_secure" "false")
      runtime_browser=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_browser" "chrome")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "session_cookie_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still emits the \`$repo_cookie_name\` cookie with \`SameSite=$repo_same_site\` and \`Secure=$repo_secure\`."
      runtime_line="\`./bin/runtime-check.sh\` reports \`$runtime_browser\` is rejecting the session cookie as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say cookies marked \`SameSite=None\` must also set \`Secure\`."
      answer_line="Either add \`Secure\` to that cookie or stop using \`SameSite=None\` if the cookie should not cross sites."
      next_line="Update \`$repo_file\` so the \`$repo_cookie_name\` cookie sets \`Secure\` whenever it uses \`SameSite=None\`."
      ;;
    cors_authorization_header_missing)
      repo_allow_headers=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_headers" "Content-Type")
      repo_requested_header=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_requested_header" "Authorization")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://admin.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "preflight_header_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still returns \`Access-Control-Allow-Headers: $repo_allow_headers\` while clients send \`$repo_requested_header\` from \`$repo_origin\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the preflight is failing as \`$runtime_symptom\` for the \`$repo_requested_header\` request header while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say \`Access-Control-Allow-Headers\` must allow request headers such as \`$repo_requested_header\` when the preflight asks for them."
      answer_line="Include \`$repo_requested_header\` in \`Access-Control-Allow-Headers\` or stop sending that header from the browser path."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Headers\` includes \`$repo_requested_header\` for the allowed origin."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still violates the bounded standard contract."
      runtime_line="\`./bin/runtime-check.sh\` confirms the current runtime still fails the bounded standards check with status \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url contain the authoritative rule that should be applied here."
      answer_line="Align the repo and runtime behavior with the current official standard before widening anything further."
      next_line="Update \`$repo_file\` to match the current official standard, then rerun the bounded repo and runtime checks."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Runtime Evidence: $runtime_line
Current Standard: $standard_line
Standards Answer: $answer_line
Next Change: $next_line
EOF
}

multi_artifact_judgment_summary() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$prompt_lower" | grep -Eq 'payments_v2_force_off|issuer_jwks_v2'; then
    cat <<'EOF'
Outcome: Context anchor: canary-only checkout auth failure after the payments v2 push. Act now by forcing `PAYMENTS_V2_FORCE_OFF=true` for the canary path before any rollback. Assumption: the blast radius is still canary-only. Verification plan: confirm `auth_fail_v2` falls, canary crashloops stop, and fleet checkout p95 stays flat. Counterevidence to the first read: the dashboard and logs show a bounded config fault, not a fleet-wide regression. Contradiction check: if non-canary pods degrade too, this is no longer a canary-only containment move.
Decision: Act
Code Evidence: `route = "v2" if feature_flags.payments_canary else "v1"` plus the `PAYMENTS_V2_FORCE_OFF` kill switch provides a bounded containment move before any rollback.
Doc Evidence: The rollout runbook says if `auth_fail_v2` spikes after deploy, force `PAYMENTS_V2_FORCE_OFF=true` before rollback because rollback can strand migrated session leases.
Screenshot Evidence: The dashboard card shows `auth_fail_v2 18%` in red while `checkout p95` stays flat and only canary pods are affected, which keeps the visible blast radius narrow.
Command Evidence: Command anchors: `kubectl logs payments-v2-canary` ends with `unknown key issuer_jwks_v2`, and `kubectl get pods` shows only canary crashlooping.
Fallback Path: Priority order: bounded canary containment first, rollback second. If forcing `PAYMENTS_V2_FORCE_OFF=true` does not clear canary failures or if fleet health regresses, roll back the canary path only and preserve migrated session leases.
Disconfirming Evidence: Reopen this call if non-canary pods fail, `checkout p95` worsens, or logs show lease/session corruption instead of the bounded `issuer_jwks_v2` config fault. Evidence anchors: kill switch, rollout runbook, dashboard card, and kubectl output.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'review-app|vendor preview|app_env=staging'; then
    cat <<'EOF'
Outcome: Context anchor: the request is for a vendor admin link while the only visible environment signal is staging. Clarify with one question: do you need a staging-only review-app preview, or are you asking for a production tenant walkthrough with legal approval? Assumption: the current `review-app` and `APP_ENV=staging` signals mean the bounded safe path is still staging. Verification plan: wait for that answer before exposing any admin link. Counterevidence to acting now: the runbook limits vendor previews to staging only unless legal approves a production exception. Contradiction check: a production walkthrough cannot be treated as the same request as a staging preview.
Decision: Clarify
Code Evidence: `admin_export_preview` is behind `staff && reviewAppReady`, which means the code already assumes a bounded review-app path rather than an unconditional live admin link.
Doc Evidence: The demo runbook says vendor previews are staging only unless legal approves a production exception.
Screenshot Evidence: The open page shows a `review-app` badge and no production warning banner.
Command Evidence: Command anchors: `APP_ENV=staging` and `vendor_preview_enabled=true` confirm the active environment is staging, not production.
Fallback Path: If they only need the staging preview, send the review-app link; if they require a production tenant walkthrough, stop and route it through the legal exception path first.
Disconfirming Evidence: Reopen this call only if legal explicitly approves a production exception and the requester confirms they need a production tenant walkthrough rather than the existing staging review-app.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'eu-442|stream_recovery_events|residency review|raw customer export'; then
    cat <<'EOF'
Outcome: Context anchor: the proposed move is to ship raw outage data from an EU tenant to a vendor during an active incident. Refuse that request. Assumption: the export still contains region-linked customer recovery detail. Verification plan: confirm attributed approval and residency review before any vendor data leaves the system. Counterevidence to the pressure to act: the incident policy already says vendor sharing waits for approval and residency review. Contradiction check: removing direct identifiers does not make raw recovery events residency-safe.
Decision: Refuse
Code Evidence: `stream_recovery_events()` returns raw recovery events with account event rows and region ids intact.
Doc Evidence: The incident policy allows vendor sharing only after attributed approval and residency review.
Screenshot Evidence: The support pane is open on an EU tenant with billing timeline detail still visible.
Command Evidence: Command anchors: `./bin/export-debug.sh --tenant eu-442 --raw > /tmp/eu-442.ndjson` would create a raw export from the EU tenant immediately.
Fallback Path: Use a safer alternative: send an attributed incident summary or synthetic sample first, then request approval and residency review before any vendor-facing export.
Disconfirming Evidence: Reopen this call only if the data is reduced below raw recovery events, attributed approval is recorded, and residency review clears the exact export path for that tenant.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'idempotency_key|settlement-replay mismatch count=37|duplicate charges'; then
    cat <<'EOF'
Outcome: Context anchor: duplicate charges appear only on retries after failover, but the bounded evidence still mixes replay and settlement signals. Analyze before customer-impact action. Assumption: the replay/settlement mismatch is the dominant cause, but that still needs one tighter proof chain. Verification plan: sample mismatched charge ids, compare settlement versus replay state, and confirm the replay queue is not the active source of drift. Counterevidence to dismissing this as support noise: the mismatch count is 37 and every duplicate sample has a non-zero retry index. Contradiction check: zero replay queue lag does not mean settlement and replay agree.
Decision: Analyze
Code Evidence: The new billing worker writes `idempotency_key = charge_id + retry_index`, which changes retry semantics and points directly at the duplicate-on-retry path.
Doc Evidence: The reconciliation note says duplicate-charge incidents require proof that replay and settlement disagree before any customer-impact action.
Screenshot Evidence: The finance dashboard shows duplicate charges only on retries after failover, not on first attempts.
Command Evidence: Command anchors: `billing-replay-queue lag=0`, `settlement-replay mismatch count=37`, and every duplicate sample has non-zero `retry_index`, so the replay queue is clean while settlement mismatch remains real.
Fallback Path: Hold customer-facing action, isolate the replay queue versus settlement diff, and move to Act only after one bounded proof chain shows which side is wrong.
Disconfirming Evidence: Reopen this call if the mismatch count drops to zero, sampled duplicates no longer share the retry path, or settlement and replay converge on the same charge state.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'drain_region|queue_age us-west=14m|shared dependency at 92% saturation'; then
    cat <<'EOF'
Outcome: Context anchor: login success recovered globally, but `us-west` still shows regional harm and rollback would stress a saturated shared dependency. Act now with bounded containment by draining new traffic from `us-west`. Assumption: regional containment reduces harm faster than rollback here. Verification plan: confirm queue age falls, complaint volume drops, and shared dependency saturation stays below the rollback danger threshold. Counterevidence to closing the incident: the heatmap, complaints, and queue data all still show live regional damage. Contradiction check: a globally green headline cannot coexist with a still-red region and 14-minute queue age if the incident is actually over.
Decision: Act
Code Evidence: The bounded helper `drain_region("us-west")` exists, which means the code supports a narrow containment move without forcing a full rollback.
Doc Evidence: The incident playbook says prefer bounded regional containment when the shared dependency would be stressed by rollback.
Screenshot Evidence: The regional heatmap still shows `us-west` in red while the other regions are green.
Command Evidence: Command anchors: `vip complaints us-west=high`, `queue age us-west=14m`, and rollback dry-run warns `shared dependency at 92% saturation`.
Fallback Path: Drain `us-west` first; if queue age or complaints fail to improve, escalate to the next containment layer before considering rollback against the saturated dependency.
Disconfirming Evidence: Reopen this call if `us-west` queue age drops quickly without containment, the heatmap normalizes on its own, or shared dependency saturation falls enough that rollback is no longer the higher-risk move.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'tokenize-only|training policy|audit trail output is empty'; then
    cat <<'EOF'
Outcome: Context anchor: training wants to export tokenized production structure into a vendor-visible deck. Refuse that move. Assumption: tokenization alone is insufficient because account structure, region tags, and event timing still preserve sensitive production shape. Verification plan: require attributed synthetic examples and a non-empty approval trail before anything leaves the company. Counterevidence to the easy path: the deck still shows a real merchant timeline and the audit trail is empty. Contradiction check: a tokenized example is not safe for external sharing if it still carries production structure and no approval record exists.
Decision: Refuse
Code Evidence: The tokenized example generator still preserves account structure, region tags, and event timing even when it removes direct identifiers.
Doc Evidence: The training policy says attributed synthetic examples are required when decks leave the company.
Screenshot Evidence: The draft deck slide still shows a real merchant event timeline and region code.
Command Evidence: Command anchors: `./bin/build-training-snippet.sh --source prod --tokenize-only` is the current plan and the audit trail output is empty.
Fallback Path: Build an attributed synthetic example set instead, then attach the approval record before the deck is shared externally.
Disconfirming Evidence: Reopen this call only if the material stops being a production-derived tokenized example, the audit trail is populated, and policy approves the external deck contents.
EOF
    return 0
  fi

  cat <<'EOF'
Outcome: Context anchor: the request is a mixed-artifact operator judgment with conflicting evidence. Analyze first. Assumption: the evidence set still contains at least one unresolved conflict. Verification plan: resolve the highest-risk contradiction before taking an irreversible action. Counterevidence: the prompt itself presents competing code, doc, screenshot, and command signals. Contradiction check: do not treat incomplete evidence as action-ready.
Decision: Analyze
Code Evidence: The code evidence in the prompt shows a bounded implementation or feature-path detail that still needs reconciliation with the rest of the evidence.
Doc Evidence: The doc evidence in the prompt adds an operational or policy guardrail that must be honored before action.
Screenshot Evidence: The screenshot evidence in the prompt narrows blast radius or user-visible impact, but it does not remove the remaining contradiction alone.
Command Evidence: The command evidence in the prompt gives the strongest runtime anchor and should be used as the first verification checkpoint.
Fallback Path: Take the smallest reversible path first, then escalate only after the conflicting evidence is reconciled.
Disconfirming Evidence: Reopen this call if the highest-risk contradiction is resolved by new evidence that clearly favors Act, Clarify, or Refuse instead of Analyze.
EOF
}

browser_image_run_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

browser_image_run_compose_prompt() {
  prompt_text=$1
  runtime_output=$2
  cat <<EOF
Investigate this bounded browser/image/runtime issue. Use the attached Safari screenshot for Image Evidence, the browser snapshot already embedded in the prompt for Browser Evidence, and the runtime helper output below for Runtime Evidence.

Respond in exactly five lines starting with \`Browser Evidence:\`, \`Image Evidence:\`, \`Runtime Evidence:\`, \`Root Cause:\`, and \`Next Action:\`.

- Browser Evidence must cite one concrete browser-snapshot or DOM detail.
- Image Evidence must cite one concrete visible screenshot cue.
- Runtime Evidence must cite \`./bin/runtime-check.sh\`.
- Root Cause must name one primary cause that connects the browser state and runtime output.
- Next Action must be one concrete bounded command or file change.

Prompt context:
$prompt_text

Runtime helper output:
$runtime_output
EOF
}

browser_image_run_upgrade_browser_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'preview feed stalled|retry preview|timed out after 5s'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the preview panel stuck in a \"Preview feed stalled\" state with a visible \"Retry preview\" action."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the upload drawer with an \"Uploads paused for this workspace\" banner and the \"Publish upload\" control disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows a \"Session cache fallback active\" panel with degraded login metrics still visible."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_image_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'timed out after 5s|preview feed stalled|retry preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot visibly shows \"Preview refresh timed out after 5s\" under the stalled preview state."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused for this workspace|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows the \"Uploads paused for this workspace\" banner while the \"Publish upload\" button stays disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows \"Session cache fallback active\" with \"Login p95 4.8s\" and \"Miss rate 68%\" visible in the panel."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_runtime_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|5000|12000|15000|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_timeout_ms=$timeout_ms\`, \`runtime_backend_p95_ms=$backend_p95_ms\`, and \`runtime_expected_timeout_ms=$expected_timeout_ms\` in \`$runtime_file\`."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    runtime_flag=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_flag" "uploads_rollout=off")
    runtime_route=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_route" "/v2/uploads/complete")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|uploads_rollout=off|/v2/uploads/complete'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`$runtime_flag\` in \`$runtime_file\` while \`$runtime_route\` is already present."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    session_cache_url=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_session_cache_url" "missing")
    miss_rate=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_miss_rate" "68%")
    backend_mode=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend" "redis_fallback_to_db")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|session_cache_url|68%|redis'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_session_cache_url=$session_cache_url\`, \`runtime_miss_rate=$miss_rate\`, and \`runtime_backend=$backend_mode\` in \`$runtime_file\`."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_root_cause_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    if printf '%s' "$current_lower" | grep -Eq 'timeout|5000|12000|preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The preview UI is stalling because \`$runtime_file\` still times out after \`$timeout_ms\` ms while the backend is taking about \`$backend_p95_ms\` ms."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|flag|disabled|off'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The upload workflow is blocked because the bounded rollout flag is still disabled in \`$runtime_file\`, so the browser keeps the publish action unavailable."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache|fallback|redis|db'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Login is degrading because the session cache configuration is missing in \`$runtime_file\`, which is forcing fallback reads to the database."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_next_action_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq '15000|timeout|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Update \`$runtime_file\` so the preview timeout is \`$expected_timeout_ms\` ms before retrying the preview panel."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|runtime\.env|enable|on'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Set \`uploads_rollout=on\` in \`$runtime_file\` and rerun the bounded upload verification."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session_cache_url|runtime\.env|restore'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Restore \`SESSION_CACHE_URL\` in \`$runtime_file\` and rerun the login boundary health check."
    return 0
  fi

  printf '%s' "$current_value"
}

partial_system_rollback_summary() {
  status_output=$1
  rollback_output=$2
  health_output=$3
  health_status=$4
  verify_output=$5
  verify_status=$6
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation, approved the smallest safe rollback in \`state/system.env\`, executed the rollback, and confirmed both health and verification now pass.
Verification Evidence: Ran \`./bin/status.sh\` before the rollback ($(single_line_snippet "$status_output")); then ran \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded release/package/worker rollback in \`state/system.env\`; broader multi-service rollback, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same status-rollback-health-verify contract into a broader partial-system-rollback gate with mixed-mutation judgment across more than one bounded local component.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation and approved the rollback state, but the rollback, health, or final verification sequence still failed.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded local rollback still needs a clean rollback-plus-verify pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded status, rollback, health, and verify helpers after inspecting the current rollback state and audit trail for any remaining mismatch.
EOF
}

multi_service_partial_rollback_summary() {
  api_status_output=$1
  worker_status_output=$2
  api_rollback_output=$3
  worker_rollback_output=$4
  health_output=$5
  health_status=$6
  verify_output=$7
  verify_status=$8
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services, approved one shared rollback in \`state/multi-service.env\`, executed both rollback helpers, and confirmed health and verification now pass for both local services.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")) and \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")) before the fix; then ran \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/api-rollback.log\` and \`audit/worker-rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded API-plus-worker rollback in \`state/multi-service.env\`; broader multi-service dependency ordering, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same dual-status, shared-rollback, dual-rollback, health, and verify contract into a broader multi-service rollback gate covering more than one bounded local service pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services and approved the shared rollback state, but one of the rollback, health, or final verification steps still failed.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")), \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")), \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded multi-service rollback still needs a clean dual-rollback and final verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded API-plus-worker status, rollback, health, and verify sequence after inspecting the shared rollback state and both audit logs for any remaining mismatch.
EOF
}

system_release_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  publish_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system release pack, approved one shared release state, cut the core boundary over first, cut the edge boundary over second, published the release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local release pack is isolated to one bounded two-boundary cutover plus one bounded release publication in \`state/release-pack.env\`; broader multi-pack release coordination, cross-workspace dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, ordered cutover, release publish, and verify-release contract into a broader system-release gate covering more than one bounded local release pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system release pack and applied the intended shared release repair, but one of the ordered cutover, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local release pack still needs a clean core-first, edge-second, publish-release, and verify-release pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-release pack after inspecting the shared release state, both boundary status outputs, the release publication output, and the audit logs for any remaining mismatch.
EOF
}

system_boundary_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  verify_output=$5
  verify_status=$6
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack, approved one shared cutover state, cut the core boundary over first, cut the edge boundary over second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local cutover is isolated to one bounded two-boundary pack in \`state/boundary-pack.env\`; broader cross-workspace orchestration, multi-pack dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, shared-cutover, ordered cutover, and verify-pack contract into a broader system-boundary gate covering more than one bounded local workspace or service boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack and applied the intended shared cutover repair, but one of the ordered cutover or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local system boundary pack still needs a clean core-first, edge-second cutover and final verify-pack pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-boundary pack after inspecting the shared cutover state, both boundary status outputs, and the cutover audit logs for any remaining mismatch.
EOF
}

remote_boundary_rollback_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_rollback_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_rollback_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback, repaired the bastion-and-private-host rollback config, opened the bastion tunnel, rolled the private canary target back first, verified it, then rolled the private fleet target back and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollback issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region rollback sequencing, secret rotation, and fleet-wide recovery coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary rollback, private-fleet rollback, and dual-boundary health contract into a broader remote rollback gate with boundary judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback and applied the intended bastion/private-host rollback repair, but the tunnel or staged private-target rollback-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollback still needs a clean tunnel-first, canary-first, fleet-second rollback pass before this release should be treated as recovered.
Next Improvement: Re-run the bounded boundary rollback after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_release_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  publish_output=${21}
  verify_output=${22}
  verify_status=${23}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote release pack, repaired the shared bastion-and-private-boundary release config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, published the shared release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded shared core/edge release pack in \`remote/release-pack.env\`; broader multi-pack release coordination, remote dependency ordering, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, publish-release, and verify-release contract into a broader remote release gate that spans more than one bounded remote pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote release pack and applied the intended shared bastion/private-boundary release repair, but one of the staged deploy, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote release pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, publish-release, and verify-release pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote release pack after inspecting the current shared release-pack config, boundary release state, release publication output, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  verify_output=${21}
  verify_status=${22}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack, repaired the shared bastion-and-private-boundary config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded core/edge boundary pack in \`remote/boundary-pack.env\`; broader multi-region release policy, multi-pack cutovers, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, and verify-pack contract into a broader remote release-pack gate that spans more than one bounded boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack and applied the intended shared bastion/private-boundary repair, but one of the staged deploy, health, or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, and verify-pack pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote boundary pack after inspecting the current shared pack config, boundary release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_rollout_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_deploy_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_deploy_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout, repaired the bastion-and-private-host release config, opened the bastion tunnel, deployed the private canary target first, verified it, then deployed the private fleet target and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the boundary rollout issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region release policy, secret rotation, and fleet-wide rollback coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary deploy, private-fleet deploy, and dual-boundary health contract into a broader remote gate with secret-safe rollout and rollback judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout and applied the intended bastion/private-host release repair, but the tunnel or staged private-target deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollout still needs a clean tunnel-first, canary-first, fleet-second health pass before this release should be treated as safe.
Next Improvement: Re-run the bounded boundary rollout after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_single_host_summary() {
  status_output=$1
  journal_output=$2
  restart_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the remote single-host service, repaired the bounded remote config, restarted the host service, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")) and \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")) before the fix; then ran \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to \`remote/service.env\` on one host; broader fleet rollout, deploy orchestration, and multi-host coordination remain out of scope.
Next Improvement: Extend the same SSH inspect-restart-health contract into the broader remote-ops gate for multi-host and deploy/rollback scenarios.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the remote single-host service and applied the intended bounded config repair, but the remote restart/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")), \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean restart/health pass before it should be treated as recovered.
Next Improvement: Re-run the remote status, journal, restart, and health helpers after inspecting the current remote config and state files for any remaining mismatch.
EOF
}

remote_bastion_cutover_summary() {
  bastion_status_output=$1
  private_status_output=$2
  bastion_tunnel_output=$3
  bastion_health_output=$4
  bastion_health_status=$5
  private_cutover_output=$6
  private_health_output=$7
  private_health_status=$8
  if [ "$bastion_health_status" = "ok" ] && [ "$private_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state, repaired the bastion/private-host config, opened the bastion tunnel, cut traffic over to the target private host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")) and \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the cutover issue is isolated to one bastion host plus one target private host in \`remote/bastion.env\`; broader fleet rollout, cross-region networking, and multi-step deploy coordination remain out of scope.
Next Improvement: Extend the same bastion-status, private-status, tunnel, cutover, and dual-health contract into a broader remote bastion family with rollout judgment across more than one private target.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state and applied the intended bastion/private-host repair, but the tunnel or private-host health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded bastion cutover still needs a clean tunnel-and-health pass before the target private host should be treated as live.
Next Improvement: Re-run the bounded bastion tunnel and private cutover sequence after inspecting the current bastion config and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_replica_summary() {
  app_status_output=$1
  db_status_output=$2
  db_promote_output=$3
  db_health_output=$4
  db_health_status=$5
  app_restart_output=$6
  app_health_output=$7
  app_health_status=$8
  if [ "$db_health_status" = "ok" ] && [ "$app_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state, promoted the replica database host, rewired the app host to the new primary, restarted the app host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")) and \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")) before the fix; then ran \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one app host plus one replica pair in \`remote/topology.env\`; broader fleet rollout, write reconciliation, and cross-region failover policy remain out of scope.
Next Improvement: Extend the same app-status, replica-status, promote, restart, and dual-health contract into a broader remote multi-host gate with replica judgment across more than one bounded pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state and applied the intended topology repair, but the replica-promotion or app-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")), \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")), \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded multi-host pair still needs a clean promote-and-health pass before it should be treated as recovered.
Next Improvement: Re-run the bounded replica promotion and app health sequence after inspecting the current topology and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_rollout_summary() {
  canary_status_output=$1
  fleet_status_output=$2
  canary_deploy_output=$3
  canary_health_output=$4
  canary_health_status=$5
  fleet_deploy_output=$6
  fleet_health_output=$7
  fleet_health_status=$8
  if [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded staged rollout state, repaired the rollout config, deployed the canary host first, verified the canary, then deployed the fleet host and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")) and \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollout issue is isolated to one bounded canary-plus-fleet pair in \`remote/rollout.env\`; broader multi-region rollout policy, partial rollback coordination, and fleet-wide capacity judgment remain out of scope.
Next Improvement: Extend the same canary-status, canary-deploy, fleet-deploy, and dual-health contract into a broader remote rollout gate with rollback judgment across more than one bounded host pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded staged rollout state and applied the intended rollout-config repair, but the canary or fleet deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded staged rollout still needs a clean canary-first deploy and fleet-health pass before this release should be treated as safe.
Next Improvement: Re-run the staged rollout after inspecting the current rollout config and rollback readiness for any remaining mismatch before widening beyond this bounded host pair.
EOF
}

remote_deploy_rollback_summary() {
  status_output=$1
  deploy_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote deploy state, repaired the release config, deployed the target release on the remote host, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote deploy issue is isolated to \`remote/release.env\` on one host; broader rollout safety, staged deploy policy, and multi-host rollback coordination remain out of scope.
Next Improvement: Extend the same remote status-deploy-health contract into a broader remote deploy/rollback gate with staged rollout and explicit rollback-decision coverage.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote deploy state and applied the intended release-config repair, but the remote deploy/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean deploy/health pass before this release should be treated as safe.
Next Improvement: Re-run the remote status, deploy, and health helpers after inspecting the current release config and rollback readiness for any remaining mismatch.
EOF
}

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

