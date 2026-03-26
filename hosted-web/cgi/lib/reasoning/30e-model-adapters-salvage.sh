adapt_prompt_for_model() {
  model_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  original_prompt=$2
  plugin_guidance=$(active_self_improve_plugin_guidance)
  plugin_prefix=""
  if [ -n "$(trim "$plugin_guidance")" ]; then
    plugin_prefix=$(printf '%s\n%s\n\n' \
      "Additional Artificer self-improvement plugins are enabled right now. Apply them when they improve reasoning quality and do not conflict with the user request:" \
      "$plugin_guidance")
  fi

  case "$model_lower" in
    starcoder*|*codegeex*|*codellama*|*coder*)
      printf '%s\n%s\n%s\n%s\n%s\n%s' \
        "You are a helpful coding assistant." \
        "Follow the instruction and answer directly." \
        "Do not include role prefixes or planning scaffolding." \
        "" \
        "${plugin_prefix}### Instruction
$original_prompt

### Response" \
        ""
      return 0
      ;;
  esac

  printf '%s%s' "$plugin_prefix" "$original_prompt"
}

output_looks_derailed() {
  text_raw=$1
  text_lower=$(printf '%s' "$text_raw" | tr '[:upper:]' '[:lower:]')
  case "$text_lower" in
    *"workspace snapshot:"*|*"recent conversation:"*|*"current plan:"*|*"loop summary:"*|*"write a concise final response"*|*"mode_update:"*|*"commands:"*|*"plan_update:"*|*"done_claim:"*|*"decision_request:"*|*"final:"*|*"next action: completion criteria:"*|*"transition:"*|*"checkpoint:"*|*"final action plan"*|*"## response## diff"*)
      return 0
      ;;
  esac
  if printf '%s\n' "$text_raw" | grep -Eq '^##[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    return 0
  fi
  return 1
}

chat_output_looks_off_topic() {
  user_prompt_raw=$1
  assistant_raw=$2
  prompt_lower=$(printf '%s' "$user_prompt_raw" | tr '[:upper:]' '[:lower:]')
  assistant_lower=$(printf '%s' "$assistant_raw" | tr '[:upper:]' '[:lower:]')

  # Strong mismatch: conceptual self-modeling request answered as app onboarding mechanics.
  if printf '%s' "$prompt_lower" | grep -Eq 'prior to|higher-order|self|identity|values'; then
    if printf '%s' "$assistant_lower" | grep -Eq 'onboarding|registration|sign[ -]?up|create (an )?account|user profile|profile setup'; then
      return 0
    fi
  fi

  # Correction follow-up ("no, ...") followed by generic wellness list indicates derailment.
  if printf '%s' "$prompt_lower" | grep -Eq '^(no|not exactly|not quite|that.s not|i mean|rather)\b|^no,|^no\.'; then
    generic_hits=$(printf '%s\n' "$assistant_lower" | grep -Eo 'mindfulness|journaling|meditation|stress management|anxiety reduction|trusted friends|books and online resources|dialogue with others|well-being' | wc -l | tr -d '[:space:]' || printf '0')
    case "$generic_hits" in
      ""|*[!0-9]*) generic_hits=0 ;;
    esac
    if [ "$generic_hits" -ge 3 ]; then
      return 0
    fi
  fi

  return 1
}

salvage_direct_response() {
  model_name=$1
  user_prompt=$2
  salvage_model=$model_name
  preferred_model=$(preferred_chat_model || true)
  if [ -n "$preferred_model" ]; then
    salvage_model=$preferred_model
  fi
  fallback_prompt=$(cat <<EOF
You are a coding assistant.
Respond directly to the latest user message in 1-3 concise sentences.
Do not include planning scaffolding, role prefixes, or tool/control sections.

User message:
$user_prompt
EOF
)
  repaired=$(run_model "$salvage_model" "$fallback_prompt" || true)
  repaired=$(normalize_assistant_output "$repaired")
  printf '%s' "$repaired"
}

salvage_chat_response() {
  model_name=$1
  user_prompt=$2
  recent_history=$3
  salvage_model=$model_name
  preferred_model=$(preferred_chat_model || true)
  if [ -n "$preferred_model" ]; then
    salvage_model=$preferred_model
  fi
  fallback_prompt=$(cat <<EOF
You are a high-quality conversational assistant in a multi-turn thread.
Answer the latest user message while preserving conversation continuity.
Hard constraints:
- Treat the latest user message as an in-thread refinement.
- If the user corrects framing, acknowledge the correction briefly and answer with the corrected framing.
- Avoid generic wellness/productivity lists unless explicitly requested.
- Prefer concise conceptual distinctions over broad platitudes.
- Do not switch to app onboarding/setup unless the user asks for implementation details.

Latest user message:
$user_prompt

Recent conversation:
$recent_history

Return only assistant reply text.
EOF
)
  repaired=$(run_model "$salvage_model" "$fallback_prompt" || true)
  repaired=$(normalize_assistant_output "$repaired")
  printf '%s' "$repaired"
}

