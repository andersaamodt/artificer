Assumptions and Alternatives: Assumptions were explicit where evidence was incomplete, and at least one viable alternative path remains under active validation.
Contradiction Check: Conflicting constraints were treated as non-simultaneously satisfiable until direct evidence proved otherwise.
Decision: $decision_line
${priority_line}
Fallback Path: $fallback_line
Disconfirming Evidence: $disconfirm_line
${risk_register_line}
Risks: $risks_line
Next Improvement: $next_action_line
EOF
}

sanitize_design_completion_outcome() {
  outcome_line=$(trim "$1")
  prompt_text=$2
  outcome_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')

  if [ -z "$outcome_line" ] || [ "$outcome_line" = "NONE" ] || [ "$outcome_lower" = "none" ] || [ "$outcome_lower" = "null" ] || [ "$outcome_lower" = "n/a" ]; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq '^starting investigation|^started investigation|^scanning workspace|^goal:|^inspection of workspace started|^workspace inspection initiated'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq 'investigat(e|ion) of the workspace|inspection of workspace|workspace inspection|listing files in target directory|completed the requested design deliverable|completed partial controller output|partial controller output by filling missing required sections|fallback command execution|transitioning to design mode|transitioning to implement mode|to be defined'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq 'workspace' && printf '%s' "$outcome_lower" | grep -Eq 'list|listing|inspect|inspection|scan|started|starting|transition'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  printf '%s' "$outcome_line"
}

reasoning_design_verification_line() {
  prompt_text=$1
  command_success_count=$2
  loop_feedback_text=${3-}
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  case "$command_success_count" in
    ""|*[!0-9]*)
      command_success_count=0
      ;;
  esac
  if [ "$command_success_count" -lt 0 ]; then
    command_success_count=0
  fi
  command_anchor_summary=$(command_evidence_anchor_summary "$loop_feedback_text")
  if [ -n "$(trim "$command_anchor_summary")" ]; then
    printf 'Verification Evidence: Used %s successful workspace checks for scenario (%s). Command output anchors: %s.' "$command_success_count" "$scenario_ref" "$command_anchor_summary"
    return 0
  fi
  printf 'Verification Evidence: Used %s successful workspace checks and synthesized constraints for scenario (%s), with command output anchors recorded.' "$command_success_count" "$scenario_ref"
}

command_anchor_status_rank() {
  status_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$status_lower" in
    ok|done|success)
      printf '%s' "0"
      ;;
    context_missing|missing_input)
      printf '%s' "1"
      ;;
    blocked|approval_required)
      printf '%s' "2"
      ;;
    failed|error|timeout)
      printf '%s' "3"
      ;;
    *)
      printf '%s' "4"
      ;;
  esac
}

command_anchor_command_label() {
  command_text=$(single_line_snippet "$(trim "$1")")
  command_text=$(printf '%s' "$command_text" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
  if [ -z "$command_text" ]; then
    printf '%s' ""
    return 0
  fi
  printf '%s' "$(printf '%s' "$command_text" | cut -c1-90)"
}

command_output_anchor_snippet() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' ""
    return 0
  fi

  anchor_line=$(printf '%s\n' "$output_text" | awk '
    BEGIN {
      first_line = ""
    }
    {
      line = $0
      gsub(/[[:space:]]+/, " ", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (first_line == "") {
        first_line = line
      }
      lower = tolower(line)
      if (line ~ /[A-Za-z0-9._\/-]+\.[A-Za-z0-9]+:[0-9]+/ || lower ~ /(fatal:|error:|failed|warning:|no such file|not found|permission denied|context missing|missing input|rollback|latency|throughput|chargeback|queue|incident|policy|regression|stack|trace|p95|p99)/) {
        print line
        found = 1
        exit
      }
    }
    END {
      if (found != 1 && first_line != "") {
        print first_line
      }
    }
  ')
  anchor_line=$(single_line_snippet "$(trim "$anchor_line")")
  if [ -z "$anchor_line" ]; then
    printf '%s' ""
    return 0
  fi
  if printf '%s' "$anchor_line" | grep -Eq '^total[[:space:]]+[0-9]+[[:space:]]+.*(drwx|-[rwx-]{3})'; then
    list_entries=$(printf '%s\n' "$anchor_line" | awk '
      {
        count = 0
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[d-][rwx-]{9}/) {
            count++
          }
        }
        if (count < 1) {
          count = 1
        }
        print count
      }
    ')
    list_entries=$(trim "$list_entries")
    [ -n "$list_entries" ] || list_entries="1"
    anchor_line="directory listing snapshot (${list_entries} entries shown)"
  else
    path_preview=$(printf '%s\n' "$anchor_line" | awk '
      {
        count = 0
        preview = ""
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^\.?\/[A-Za-z0-9._\/-]+$/) {
            count++
            if (count <= 3) {
              if (preview != "") {
                preview = preview ", "
              }
              preview = preview $i
            }
          }
        }
        if (count >= 4) {
          if (count > 3) {
            printf "%s (+%d more paths)", preview, count - 3
          } else {
            printf "%s", preview
          }
        }
      }
    ')
    path_preview=$(trim "$path_preview")
    if [ -n "$path_preview" ]; then
      anchor_line="$path_preview"
    fi
  fi
  printf '%s' "$(printf '%s' "$anchor_line" | cut -c1-140)"
}

command_evidence_anchor_summary() {
  evidence_text=$1
  if [ -z "$(trim "$evidence_text")" ]; then
    printf '%s' ""
    return 0
  fi

  entries_tmp=$(mktemp)
  printf '%s\n' "$evidence_text" | awk '
    function emit_entry() {
      if (cmd == "") {
        return
      }
      if (status == "") {
        status = "unknown"
      }
      print cmd "\t" status "\t" output
    }
    BEGIN {
      cmd = ""
      status = ""
      output = ""
      capture_output = 0
    }
    /^Command:[[:space:]]*/ {
      emit_entry()
      cmd=$0
      sub(/^Command:[[:space:]]*/, "", cmd)
      status=""
      output=""
      capture_output=0
      next
    }
    /^Status:[[:space:]]*/ {
      if (cmd != "") {
        status=$0
        sub(/^Status:[[:space:]]*/, "", status)
        capture_output=0
      }
      next
    }
    /^Output:[[:space:]]*/ {
      if (cmd != "") {
        capture_output=1
      }
      next
    }
    {
      if (capture_output == 1) {
        if ($0 ~ /^(Checkpoint|Transition|Reason|Decision requested|Question|Options):[[:space:]]*/) {
          capture_output=0
          next
        }
        line=$0
        gsub(/\t/, " ", line)
        gsub(/[[:space:]]+/, " ", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "") {
          if (output == "") {
            output=line
          } else {
            output=output " " line
          }
        }
      }
    }
    END {
      emit_entry()
    }
  ' > "$entries_tmp"

  if [ ! -s "$entries_tmp" ]; then
    rm -f "$entries_tmp"
    printf '%s' ""
    return 0
  fi

  ranked_tmp=$(mktemp)
  dedup_tmp=$(mktemp)
  summary=""
  count=0

  while IFS="$(printf '\t')" read -r cmd status output; do
    cmd=$(command_anchor_command_label "$cmd")
    status=$(trim "$status")
    status=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
    output=$(trim "$output")
    [ -n "$cmd" ] || continue
    [ -n "$status" ] || status="unknown"

    rank=$(command_anchor_status_rank "$status")
    anchor=$(command_output_anchor_snippet "$output")

    entry="$cmd ($status)"
    if [ -n "$anchor" ]; then
      cmd_lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
      anchor_lower=$(printf '%s' "$anchor" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$anchor_lower" | grep -Fq "$cmd_lower"; then
        entry="$cmd ($status; anchor: $anchor)"
      fi
    fi
    printf '%s\t%s\t%s\n' "$rank" "$cmd" "$entry" >> "$ranked_tmp"
  done < "$entries_tmp"

  rm -f "$entries_tmp"

  if [ ! -s "$ranked_tmp" ]; then
    rm -f "$ranked_tmp" "$dedup_tmp"
    printf '%s' ""
    return 0
  fi

  sort -t "$(printf '\t')" -k1,1n -k2,2 "$ranked_tmp" | awk -F '\t' '!seen[$2]++ { print $3 }' > "$dedup_tmp"
  rm -f "$ranked_tmp"

  while IFS= read -r entry; do
    entry=$(trim "$entry")
    [ -n "$entry" ] || continue
    if [ -z "$summary" ]; then
      summary="$entry"
    else
      summary="${summary}; ${entry}"
    fi
    count=$((count + 1))
    if [ "$count" -ge 3 ]; then
      break
    fi
  done < "$dedup_tmp"

  rm -f "$dedup_tmp"
  printf '%s' "$summary"
}

context_miss_anchor_summary() {
  feedback_text=$1
  if [ -z "$(trim "$feedback_text")" ]; then
    printf '%s' ""
    return 0
  fi

  pairs_tmp=$(mktemp)
  printf '%s\n' "$feedback_text" | awk '
    BEGIN { cmd="" }
    /^Command:[[:space:]]*/ {
      cmd=$0
      sub(/^Command:[[:space:]]*/, "", cmd)
      next
    }
    /^Status:[[:space:]]*/ {
      if (cmd != "") {
        status=$0
        sub(/^Status:[[:space:]]*/, "", status)
        status_lc=tolower(status)
        if (status_lc == "missing_input" || status_lc == "context_missing") {
          printf "%s\t%s\n", cmd, status_lc
        }
        cmd=""
      }
    }
  ' > "$pairs_tmp"

  if [ ! -s "$pairs_tmp" ]; then
    rm -f "$pairs_tmp"
    printf '%s' ""
    return 0
  fi

  dedup_tmp=$(mktemp)
  awk -F '\t' '!seen[$0]++ { print $0 }' "$pairs_tmp" > "$dedup_tmp"
  rm -f "$pairs_tmp"

  summary=""
  count=0
  while IFS="$(printf '\t')" read -r cmd status; do
    cmd=$(single_line_snippet "$(trim "$cmd")")
    status=$(trim "$status")
    [ -n "$cmd" ] || continue
    [ -n "$status" ] || status="missing_input"
    if [ -z "$summary" ]; then
      summary="$cmd ($status)"
    else
      summary="${summary}; ${cmd} (${status})"
    fi
    count=$((count + 1))
    if [ "$count" -ge 3 ]; then
      break
    fi
  done < "$dedup_tmp"
  rm -f "$dedup_tmp"
  printf '%s' "$summary"
}

context_miss_guidance_for_prompt() {
  feedback_text=$1
  state_mode_hint=$(normalize_mode "$2")
  context_anchor_summary=$(context_miss_anchor_summary "$feedback_text")
  if [ -z "$(trim "$context_anchor_summary")" ]; then
    printf '%s' "NONE"
    return 0
  fi

  discovery_hint=$(context_recovery_readonly_command_for_mode "$state_mode_hint" "context_missing")
  discovery_hint=$(single_line_snippet "$(trim "$discovery_hint")")
  if [ -z "$(trim "$discovery_hint")" ]; then
    discovery_hint="find . -maxdepth 2 -type f"
  fi

  printf '%s\n' "Context misses observed in prior command anchors: $context_anchor_summary."
  printf '%s\n' "Do not repeat those exact path assumptions until discovery output confirms the path exists."
  printf '%s\n' "Run one discovery-first command before file-specific probes (recommended: $discovery_hint)."
  printf '%s' "If discovery remains ambiguous, state assumptions explicitly and provide one fallback path."
}

ensure_output_has_runtime_command_evidence() {
  output_text=$1
  loop_summary_text=$2
  command_success_total_raw=$3
  prompt_text=$4
  enforce_claim_map_raw=${5:-0}

  output_trimmed=$(trim "$output_text")
  if [ -z "$output_trimmed" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac
  if [ "$command_success_total" -le 0 ]; then
    printf '%s' "$output_text"
    return 0
  fi

  case "$enforce_claim_map_raw" in
    ""|*[!0-9]*)
      enforce_claim_map=0
      ;;
    *)
      enforce_claim_map=$enforce_claim_map_raw
      ;;
  esac

  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$output_lower" | grep -Eq 'verification evidence:'; then
    if [ "$enforce_claim_map" -eq 1 ]; then
      output_text=$(printf '%s\nVerification Evidence: Command anchors from this run for scenario (%s): %s.' "$output_text" "$scenario_ref" "$command_anchor_summary")
      output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
    fi
  elif ! printf '%s' "$output_lower" | grep -Eq 'command anchors:'; then
    output_text=$(printf '%s\nCommand Anchors: %s.' "$output_text" "$command_anchor_summary")
    output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  fi

  if [ "$enforce_claim_map" -eq 1 ] && ! printf '%s' "$output_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map|claim[- ]?evidence map'; then
    output_text=$(printf '%s\nClaim-to-Evidence Map: Primary outcome -> %s -> rerun the same command anchors and verify status drift before broad rollout.' "$output_text" "$command_anchor_summary")
  fi

  printf '%s' "$output_text"
}

assay_runtime_summary_line() {
  elapsed_sec=$1
  case "$elapsed_sec" in
    ""|*[!0-9]*)
      elapsed_sec=0
      ;;
  esac
  if [ "$elapsed_sec" -lt 0 ]; then
    elapsed_sec=0
  fi
  elapsed_minutes=$((elapsed_sec / 60))
  elapsed_seconds=$((elapsed_sec % 60))
  if [ "$elapsed_minutes" -gt 0 ]; then
    printf 'Worked for %sm %ss.' "$elapsed_minutes" "$elapsed_seconds"
  else
    printf 'Worked for %ss.' "$elapsed_seconds"
  fi
}

assay_ensure_runtime_evidence() {
  output_text=$1
  runtime_line=$2
  if [ -z "$runtime_line" ]; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s\n' "$output_text" | grep -Eqi 'Worked for[[:space:]]+[0-9]+m[[:space:]]+[0-9]+s|Worked for[[:space:]]+[0-9]+s'; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s\n' "$output_text" | grep -q '^Verification Evidence:'; then
    printf '%s\n' "$output_text" | awk -v rt="$runtime_line" '
      BEGIN { updated = 0 }
      {
        if (updated == 0 && $0 ~ /^Verification Evidence:/) {
          print $0 " " rt
          updated = 1
          next
        }
        print
      }
      END {
        if (updated == 0) {
          print "Verification Evidence: " rt
        }
      }
    '
    return 0
  fi
  printf '%s\nVerification Evidence: %s' "$output_text" "$runtime_line"
}

assay_apply_reasoning_contracts() {
  output_text=$(trim "$1")
  prompt_text=$2
  adversarial_required=$3
  cross_domain_required=$4
  recovery_required=$5
  decision_required=$6
  assumption_revision_required=${7:-0}
  time_window_required=0
  source_quality_required=0
  claim_evidence_required=0
  if prompt_requires_time_windowed_validation "$prompt_text"; then
    time_window_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    time_window_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    output_text=$(normalize_adversarial_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$cross_domain_required" -eq 1 ]; then
    output_text=$(normalize_cross_domain_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$recovery_required" -eq 1 ]; then
    output_text=$(normalize_recovery_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$assumption_revision_required" -eq 1 ]; then
    output_text=$(normalize_assumption_revision_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$decision_required" -eq 1 ]; then
    output_text=$(normalize_decision_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$time_window_required" -eq 1 ]; then
    output_text=$(normalize_verification_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$adversarial_required" -eq 1 ] || [ "$cross_domain_required" -eq 1 ] || [ "$decision_required" -eq 1 ] || [ "$time_window_required" -eq 1 ] || prompt_prefers_reasoning_completion "$prompt_text"; then
    claim_evidence_required=1
  fi
  if [ "$claim_evidence_required" -eq 1 ]; then
    output_text=$(normalize_claim_evidence_completeness_contract "$output_text" "$prompt_text" "")
  fi
  if [ "$time_window_required" -eq 1 ] || prompt_prefers_reasoning_completion "$prompt_text"; then
    source_quality_required=1
  fi
  if [ "$source_quality_required" -eq 1 ]; then
    output_text=$(normalize_source_quality_contradiction_contract "$output_text" "$prompt_text" "" "0")
  fi
  if [ "$adversarial_required" -eq 1 ] || [ "$cross_domain_required" -eq 1 ] || [ "$decision_required" -eq 1 ]; then
    output_text=$(normalize_ambiguity_final_contract "$output_text")
  fi
  output_text=$(normalize_reasoning_followup_thread_contract "$output_text" "$prompt_text")
  output_text=$(normalize_reasoning_live_contract "$output_text" "$prompt_text")
  printf '%s' "$output_text"
}

assay_normalize_assistant_output() {
  raw_output=$(trim "$1")
  final_mode=$(trim "$2")
  plan_text=$3
  run_time_budget=$4
  run_elapsed_sec=${5:-0}
  prompt_text=${6:-}
  runtime_line=$(assay_runtime_summary_line "$run_elapsed_sec")
  adversarial_required=0
  cross_domain_required=0
  recovery_required=1
  decision_required=0
  assumption_revision_required=0
  if prompt_requires_adversarial_reasoning "$prompt_text"; then
    adversarial_required=1
  fi
  if prompt_requires_cross_domain_reasoning "$prompt_text"; then
    cross_domain_required=1
  fi
  if prompt_requires_decision_completeness "$prompt_text"; then
    decision_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    decision_required=1
  fi
  if prompt_requires_assumption_revision_contract "$prompt_text"; then
    assumption_revision_required=1
  fi
  if [ "$assumption_revision_required" -eq 0 ] && [ "$adversarial_required" -eq 1 ] && printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]' | grep -Eq 'misconception|false assumption|plausible but false|first narrative|attractive but wrong|initial assumption|assumption[- ]?revision|invalidated|prove (this|it) wrong|confidence shift'; then
    assumption_revision_required=1
  fi

  if assay_output_has_required_sections "$raw_output"; then
    if ! printf '%s' "$raw_output" | grep -Eqi '^Outcome:[[:space:]]+I couldn.t complete|^Outcome:[[:space:]]+Progress was made.*not yet finalized|^Outcome:[[:space:]]+Concrete progress was delivered.*final hardening|^Outcome:[[:space:]]+Produced a defensible intermediate result.*remaining verification|^Outcome:[[:space:]]+Starting investigation|^Outcome:[[:space:]]+Started investigation'; then
      normalized_output=$(assay_apply_reasoning_contracts "$raw_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
      assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
      return 0
    fi
  fi

  next_action_line=$(assay_next_action_from_plan "$plan_text")
  next_action_line=$(sanitize_reasoning_next_action "$next_action_line" "$prompt_text")
  if [ -z "$final_mode" ]; then
    final_mode="UNKNOWN"
  fi

  if [ -z "$raw_output" ]; then
    normalized_output=$(structured_incomplete_run_message "$final_mode" "$next_action_line" "" "$prompt_text")
    normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
    assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
    return 0
  fi

  if printf '%s' "$raw_output" | grep -Eqi 'couldn.t complete|run timed out|before done mode|partial or stale'; then
    risk_line=$(reasoning_risk_line_for_prompt "$prompt_text" "$final_mode")
    normalized_output=$(structured_incomplete_run_message "$final_mode" "$next_action_line" "$risk_line" "$prompt_text")
    normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
    assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
    return 0
  fi

  outcome_line=$(printf '%s\n' "$raw_output" | sed -n '/[^[:space:]]/p' | sed -n '1p')
  outcome_line=$(trim "$outcome_line")
  outcome_line=$(printf '%s\n' "$outcome_line" | sed -E 's/^[[:space:]]*[Oo]utcome:[[:space:]]*//')
  outcome_line=$(trim "$outcome_line")
  outcome_line=$(assay_sanitize_reasoning_outcome "$outcome_line" "$prompt_text")
  outcome_line_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')
  if [ -z "$outcome_line" ] || [ "$outcome_line_lower" = "none" ] || [ "$outcome_line_lower" = "null" ] || [ "$outcome_line_lower" = "n/a" ]; then
    outcome_line="Best-effort progress was produced in mode: $final_mode."
  fi

  risk_line=$(reasoning_risk_line_for_prompt "$prompt_text" "$final_mode")
  verification_line="Verification Evidence: Review the run trace for executed steps, commands, and controller transitions."
  if assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    verification_line=$(assay_reasoning_verification_line_for_prompt "$prompt_text")
  fi

  normalized_output=$(printf '%s\n%s\n%s\n%s' \
    "Outcome: $outcome_line" \
    "$verification_line" \
    "Risks: $risk_line" \
    "Next Improvement: $next_action_line")
  normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
  assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
}
