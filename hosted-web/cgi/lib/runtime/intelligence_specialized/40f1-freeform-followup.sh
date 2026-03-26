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

