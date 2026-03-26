Next Improvement: Narrow scope or increase compute budget, then continue from the latest checkpoint.
EOF
)
        stream_emit_line "$stream_output_file" "Run reached time budget of ${run_time_budget}s; finalizing with partial deliverable."
        append_failure_entry "$failures_file" "iteration-$iteration:run-timeout" "Exceeded run time budget (${run_time_budget}s)" \
          "Model/controller loop exceeded time budget" "Return timeout response and finalize run"
        break
      fi

      plan_text=$(sed -n '1,220p' "$plan_file")
      history_text=$(conversation_history "$conv_dir" | sed -n '1,220p')
      snapshot_text=$(workspace_snapshot "$workspace_path" | sed -n '1,220p')
      workspace_context_text=$(workspace_shared_context "$ws_dir" "$conversation_id" | sed -n '1,320p')
      if [ "$assay_run_profile" -eq 1 ]; then
        history_text=$(printf '%s\n' "$history_text" | sed -n '1,140p')
        snapshot_text=$(printf '%s\n' "$snapshot_text" | sed -n '1,140p')
        workspace_context_text=""
      fi
      contract_context_text=$(sed -n '1,220p' "$contract_file" 2>/dev/null || true)
      failures_tail=$(tail -n 80 "$failures_file" 2>/dev/null || sed -n '1,80p' "$failures_file")
      session_tail=$(tail -n 80 "$session_log_file" 2>/dev/null || sed -n '1,80p' "$session_log_file")
      assumptions_tail=$(tail -n 80 "$assumptions_file" 2>/dev/null || sed -n '1,80p' "$assumptions_file")
      compliance_tail=$(tail -n 80 "$compliance_file" 2>/dev/null || sed -n '1,80p' "$compliance_file")
      if [ "$run_mode" = "programming" ]; then
        refresh_programming_artifacts "$plan_file" "$state_file" "$session_log_file" "$failures_file" "$contract_file" "$architecture_file" "$tasks_dir"
      fi
      architecture_context_text=$(sed -n '1,220p' "$architecture_file" 2>/dev/null || true)
      tasks_context_text=$(sed -n '1,220p' "$tasks_index_file" 2>/dev/null || true)
      refresh_context_memory_file "$plan_file" "$contract_file" "$session_log_file" "$failures_file" "$assumptions_file" "$compliance_file" "$architecture_file" "$tasks_index_file" "$snapshot_text" "$run_mode" "$context_memory_file"
      context_memory_text=$(sed -n '1,260p' "$context_memory_file" 2>/dev/null || true)
      context_tokens=$(model_context_tokens_for "$model")
      case "$context_tokens" in
        ""|*[!0-9]*)
          context_tokens=8192
          ;;
      esac
      context_prompt_budget=$((context_tokens * 62 / 100))
      case "$run_mode" in
        programming|teacher|report|text-perfecter|assistant|gui-testing)
          context_prompt_budget=$((context_tokens * 72 / 100))
          ;;
      esac
      if [ "$context_prompt_budget" -lt 1600 ]; then
        context_prompt_budget=1600
      fi
      case "$run_mode" in
        programming|teacher|assistant|gui-testing)
          if [ "$context_prompt_budget" -lt 2200 ]; then
            context_prompt_budget=2200
          fi
          ;;
        report)
          if [ "$context_prompt_budget" -lt 2000 ]; then
            context_prompt_budget=2000
          fi
          ;;
        text-perfecter)
          if [ "$context_prompt_budget" -lt 2200 ]; then
            context_prompt_budget=2200
          fi
          ;;
      esac
      if [ "$assay_run_profile" -eq 1 ] && [ "$context_prompt_budget" -gt 2000 ]; then
        context_prompt_budget=2000
      fi
      ratio_total=136
      plan_budget=$((context_prompt_budget * 12 / ratio_total))
      contract_budget=$((context_prompt_budget * 10 / ratio_total))
      memory_budget=$((context_prompt_budget * 12 / ratio_total))
      architecture_budget=$((context_prompt_budget * 12 / ratio_total))
      tasks_budget=$((context_prompt_budget * 10 / ratio_total))
      history_budget=$((context_prompt_budget * 16 / ratio_total))
      snapshot_budget=$((context_prompt_budget * 14 / ratio_total))
      workspace_budget=$((context_prompt_budget * 10 / ratio_total))
      failures_budget=$((context_prompt_budget * 8 / ratio_total))
      session_budget=$((context_prompt_budget * 8 / ratio_total))
      assumptions_budget=$((context_prompt_budget * 6 / ratio_total))
      compliance_budget=$((context_prompt_budget * 8 / ratio_total))
      feedback_budget=$((context_prompt_budget * 10 / ratio_total))
      user_request_budget=$((context_prompt_budget * 12 / ratio_total))
      if [ "$plan_budget" -lt 180 ]; then plan_budget=180; fi
      if [ "$contract_budget" -lt 160 ]; then contract_budget=160; fi
      if [ "$memory_budget" -lt 200 ]; then memory_budget=200; fi
      if [ "$architecture_budget" -lt 170 ]; then architecture_budget=170; fi
      if [ "$tasks_budget" -lt 150 ]; then tasks_budget=150; fi
      if [ "$history_budget" -lt 260 ]; then history_budget=260; fi
      if [ "$snapshot_budget" -lt 220 ]; then snapshot_budget=220; fi
      if [ "$workspace_budget" -lt 180 ]; then workspace_budget=180; fi
      if [ "$failures_budget" -lt 120 ]; then failures_budget=120; fi
      if [ "$session_budget" -lt 120 ]; then session_budget=120; fi
      if [ "$assumptions_budget" -lt 100 ]; then assumptions_budget=100; fi
      if [ "$compliance_budget" -lt 110 ]; then compliance_budget=110; fi
      if [ "$feedback_budget" -lt 120 ]; then feedback_budget=120; fi
      if [ "$user_request_budget" -lt 240 ]; then user_request_budget=240; fi
      if [ "$user_request_budget" -gt 1400 ]; then user_request_budget=1400; fi

      plan_before_tokens=$(estimate_tokens_approx "$plan_text")
      contract_before_tokens=$(estimate_tokens_approx "$contract_context_text")
      memory_before_tokens=$(estimate_tokens_approx "$context_memory_text")
      architecture_before_tokens=$(estimate_tokens_approx "$architecture_context_text")
      tasks_before_tokens=$(estimate_tokens_approx "$tasks_context_text")
      history_before_tokens=$(estimate_tokens_approx "$history_text")
      snapshot_before_tokens=$(estimate_tokens_approx "$snapshot_text")
      workspace_before_tokens=$(estimate_tokens_approx "$workspace_context_text")
      failures_before_tokens=$(estimate_tokens_approx "$failures_tail")
      session_before_tokens=$(estimate_tokens_approx "$session_tail")
      assumptions_before_tokens=$(estimate_tokens_approx "$assumptions_tail")
      compliance_before_tokens=$(estimate_tokens_approx "$compliance_tail")
      feedback_before_tokens=$(estimate_tokens_approx "$loop_feedback")
      user_request_before_tokens=$(estimate_tokens_approx "$augmented_user_prompt")

      plan_text=$(compact_text_block "Plan" "$plan_text" "$plan_budget")
      contract_context_text=$(compact_text_block "Contract context" "$contract_context_text" "$contract_budget")
      context_memory_text=$(compact_text_block "Context memory" "$context_memory_text" "$memory_budget")
      architecture_context_text=$(compact_text_block "Architecture map" "$architecture_context_text" "$architecture_budget")
      tasks_context_text=$(compact_text_block "Task index" "$tasks_context_text" "$tasks_budget")
      history_text=$(compact_text_block "Conversation context" "$history_text" "$history_budget")
      snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" "$snapshot_budget")
      workspace_context_text=$(compact_text_block "Other threads context" "$workspace_context_text" "$workspace_budget")
      failures_tail=$(compact_text_block "Failure ledger" "$failures_tail" "$failures_budget")
      session_tail=$(compact_text_block "Session log" "$session_tail" "$session_budget")
      assumptions_tail=$(compact_text_block "Assumptions ledger" "$assumptions_tail" "$assumptions_budget")
      compliance_tail=$(compact_text_block "Compliance ledger" "$compliance_tail" "$compliance_budget")
      loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" "$feedback_budget")
      augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" "$user_request_budget")
      if [ "$controller_format_recovery_streak" -gt 0 ] || [ "$controller_format_recovery_total" -gt 0 ]; then
        recovery_user_budget=$((user_request_budget * 65 / 100))
        if [ "$recovery_user_budget" -lt 180 ]; then
          recovery_user_budget=180
        fi
        recovery_history_budget=$((history_budget * 55 / 100))
        if [ "$recovery_history_budget" -lt 160 ]; then
          recovery_history_budget=160
        fi
        recovery_snapshot_budget=$((snapshot_budget * 60 / 100))
        if [ "$recovery_snapshot_budget" -lt 160 ]; then
          recovery_snapshot_budget=160
        fi
        recovery_feedback_budget=$((feedback_budget * 60 / 100))
        if [ "$recovery_feedback_budget" -lt 90 ]; then
          recovery_feedback_budget=90
        fi
        history_text=$(compact_text_block "Conversation context" "$history_text" "$recovery_history_budget")
        snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" "$recovery_snapshot_budget")
        loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" "$recovery_feedback_budget")
        workspace_context_text=""
        augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" "$recovery_user_budget")
        stream_emit_line "$stream_output_file" "Controller format-recovery pressure active; using reduced context profile."
      fi
      if [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        history_text=""
        workspace_context_text=""
        context_memory_text=""
        compliance_tail=""
        architecture_context_text=$(compact_text_block "Architecture map" "$architecture_context_text" 120)
        tasks_context_text=$(compact_text_block "Task index" "$tasks_context_text" 100)
        assumptions_tail=$(compact_text_block "Assumptions ledger" "$assumptions_tail" 90)
        failures_tail=$(compact_text_block "Failure ledger" "$failures_tail" 120)
        session_tail=$(compact_text_block "Session log" "$session_tail" 160)
        loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" 120)
        snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" 240)
        augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" 260)
        stream_emit_line "$stream_output_file" "Quick narrow-slice implement step: using focused context profile."
      fi

      plan_after_tokens=$(estimate_tokens_approx "$plan_text")
      contract_after_tokens=$(estimate_tokens_approx "$contract_context_text")
      memory_after_tokens=$(estimate_tokens_approx "$context_memory_text")
      architecture_after_tokens=$(estimate_tokens_approx "$architecture_context_text")
      tasks_after_tokens=$(estimate_tokens_approx "$tasks_context_text")
      history_after_tokens=$(estimate_tokens_approx "$history_text")
      snapshot_after_tokens=$(estimate_tokens_approx "$snapshot_text")
      workspace_after_tokens=$(estimate_tokens_approx "$workspace_context_text")
      failures_after_tokens=$(estimate_tokens_approx "$failures_tail")
      session_after_tokens=$(estimate_tokens_approx "$session_tail")
      assumptions_after_tokens=$(estimate_tokens_approx "$assumptions_tail")
      compliance_after_tokens=$(estimate_tokens_approx "$compliance_tail")
      feedback_after_tokens=$(estimate_tokens_approx "$loop_feedback")
      user_request_after_tokens=$(estimate_tokens_approx "$augmented_user_prompt_controller")

      compacted_any=0
      if [ "$plan_after_tokens" -lt "$plan_before_tokens" ] || \
         [ "$contract_after_tokens" -lt "$contract_before_tokens" ] || \
         [ "$memory_after_tokens" -lt "$memory_before_tokens" ] || \
         [ "$architecture_after_tokens" -lt "$architecture_before_tokens" ] || \
         [ "$tasks_after_tokens" -lt "$tasks_before_tokens" ] || \
         [ "$history_after_tokens" -lt "$history_before_tokens" ] || \
         [ "$snapshot_after_tokens" -lt "$snapshot_before_tokens" ] || \
         [ "$workspace_after_tokens" -lt "$workspace_before_tokens" ] || \
         [ "$failures_after_tokens" -lt "$failures_before_tokens" ] || \
         [ "$session_after_tokens" -lt "$session_before_tokens" ] || \
         [ "$assumptions_after_tokens" -lt "$assumptions_before_tokens" ] || \
         [ "$compliance_after_tokens" -lt "$compliance_before_tokens" ] || \
         [ "$feedback_after_tokens" -lt "$feedback_before_tokens" ] || \
         [ "$user_request_after_tokens" -lt "$user_request_before_tokens" ]; then
        compacted_any=1
      fi
      if [ "$compacted_any" = "1" ]; then
        stream_emit_line "$stream_output_file" "Context compacted for model window (~${context_tokens} tokens) to preserve relevance."
      fi
      state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")
      stream_emit_line "$stream_output_file" "Current mode: $state_mode"
      state_target=$(state_get "$state_file" "target" "workspace")
      state_blocking=$(state_get "$state_file" "blocking" "none")
      state_confidence=$(state_get "$state_file" "confidence" "0.20")
      state_reason=$(state_get "$state_file" "transition_reason" "none")
      mode_hint=$(mode_instructions "$state_mode")
      context_miss_guidance=$(context_miss_guidance_for_prompt "$loop_feedback" "$state_mode")
      context_miss_guidance=$(compact_text_block "Context miss guidance" "$context_miss_guidance" 140)
      if [ -n "$stream_output_file" ] && [ -n "$(trim "$context_miss_guidance")" ] && [ "$context_miss_guidance" != "NONE" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration anti-thrash hint: context-miss guidance active for next command selection."
      fi
      explicit_skill_prompt_text=$explicit_skill_context_text
      if [ -z "$(trim "$explicit_skill_prompt_text")" ]; then
        explicit_skill_prompt_text="NONE"
      fi
      controller_variant_prompt_block="Controller variant guidance: NONE"
      if [ -n "$(trim "$controller_variant_id")" ]; then
        controller_variant_prompt_block=$(cat <<EOF
Controller variant:
- selected_id: $controller_variant_id
- active_id: ${controller_variant_active_id:-none}
- candidate_id: ${controller_variant_candidate_id:-none}
- sample_bucket: ${controller_variant_bucket:-0}
- guidance: ${controller_variant_guidance:-baseline policy only}
EOF
)
      fi
      runtime_failure_summary="none"
      if command -v mr_failure_taxonomy_recent_summary_text >/dev/null 2>&1; then
        runtime_failure_summary=$(mr_failure_taxonomy_recent_summary_text "6")
      fi
      runtime_failure_summary=$(printf '%s' "$runtime_failure_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_failure_summary")" ]; then
        runtime_failure_summary="none"
      fi
      runtime_quality_summary="none"
      if command -v mr_quality_scorecard_recent_summary_text >/dev/null 2>&1; then
        runtime_quality_summary=$(mr_quality_scorecard_recent_summary_text "8")
      fi
      runtime_quality_summary=$(printf '%s' "$runtime_quality_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_quality_summary")" ]; then
        runtime_quality_summary="none"
      fi
      runtime_proposal_summary="none"
      if command -v mr_improvement_proposals_recent_summary_text >/dev/null 2>&1; then
        runtime_proposal_summary=$(mr_improvement_proposals_recent_summary_text "$run_mode" "12" "3")
      fi
      runtime_proposal_summary=$(printf '%s' "$runtime_proposal_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_proposal_summary")" ]; then
        runtime_proposal_summary="none"
      fi
      runtime_guardrails="none"
      if command -v mr_runtime_learning_guardrails_text >/dev/null 2>&1; then
        runtime_guardrails=$(mr_runtime_learning_guardrails_text)
      fi
      runtime_guardrails=$(printf '%s' "$runtime_guardrails" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_guardrails")" ]; then
        runtime_guardrails="none"
      fi
      workspace_context_block=""
      if [ -n "$(trim "$workspace_context_text")" ]; then
        workspace_context_block=$(cat <<EOF
$workspace_context_block

EOF
)
      fi

      use_seeded_programming_controller=0
      use_seeded_programming_narrow_slice_controller=0
      if { [ "$programming_quick_bounded_run" -eq 1 ] || [ "$programming_quick_narrow_slice_run" -eq 1 ]; } && [ "$iteration" -eq 1 ] && [ "$run_command_success_total" -eq 0 ] && [ "$state_mode" = "INVESTIGATE" ]; then
        use_seeded_programming_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -eq 2 ] && [ "$run_command_success_total" -gt 0 ] && [ "$state_mode" = "DESIGN" ]; then
        use_seeded_programming_narrow_slice_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -ge 3 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        use_seeded_programming_narrow_slice_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -ge 4 ] && [ "$state_mode" = "VERIFY" ]; then
        use_seeded_programming_narrow_slice_controller=1
      fi

      controller_prompt=$(cat <<EOF
$controller_role_line
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget (run_time_budget=${run_time_budget}s)

Current mode: $state_mode
Typed state:
- mode=$state_mode
- target=$state_target
- blocking=$state_blocking
- confidence=$state_confidence
- transition_reason=$state_reason

$mode_hint

$run_mode_policy_text

$controller_variant_prompt_block

Runtime learning signals:
- failure_taxonomy: $runtime_failure_summary
- quality_scorecard: $runtime_quality_summary
- improvement_proposals: $runtime_proposal_summary

Runtime adaptation guardrails:
- $runtime_guardrails

Explicit skill actuator context:
$explicit_skill_prompt_text

Return ONLY these sections exactly:

MODE_UPDATE:
target=<value>
blocking=<value>
confidence=<0.00-1.00>

COMMANDS:
- up to 3 read-only shell commands, or NONE

CONTRACT:
- contract text for DESIGN mode, otherwise NONE

PATCH:
- unified diff in a diff code fence for IMPLEMENT mode, otherwise NONE

DONE_CLAIM:
yes | no

PLAN_UPDATE:
Goal:
Subgoals:
Constraints:
Unknowns:
Next Action:
Completion Criteria:

CHECKPOINT:
- one concise status line
- include assumptions when defaults were chosen due ambiguity

DECISION_REQUEST:
- use question=<text> and one or more option=<text> lines when user choice is needed
- if details are unspecified, choose sensible defaults instead of asking
- otherwise NONE

FINAL:
- final user-facing answer only when work is complete, otherwise NONE
- for complex work, structure FINAL with: Outcome, Verification Evidence, Risks, Next Improvement
- when requirements are ambiguous/conflicting, also include: Assumptions and Alternatives, Contradiction Check
- for adversarial/plausible-false prompts, also include: False Premise Challenge, Premise Validation
- when recovery or misconception pressure is present, also include: Initial Assumption, Invalidating Evidence, Revised Decision, Evidence Delta

Rules:
- never invent mode transitions; orchestration handles transitions
- use mediated commands only
- no shell separators or redirects in COMMANDS
- if Context-miss guidance is present, run discovery-first and avoid repeating listed missing-context commands until new evidence appears
- patch at most 5 files
- do not output role prefixes ("Assistant:" / "User:") in FINAL
- if user input is required to proceed, emit DECISION_REQUEST with 2-5 concrete options
- default to reasonable assumptions when requirements are underspecified
- only emit DECISION_REQUEST when the user explicitly asks to choose or required data cannot be inferred
- if ambiguity remains after assumptions, narrow scope and complete one verifiable slice rather than stopping early
- only set DONE_CLAIM yes when verification evidence exists in this run command outputs
- for complex reasoning tasks, use all 3 command slots unless blocked by safety/compliance

Current plan:
$plan_text

Contract context:
$contract_context_text

Compressed project memory:
$context_memory_text

Architecture map:
$architecture_context_text

Task index:
$tasks_context_text

Compliance ledger (tail):
$compliance_tail

Failure ledger (tail):
$failures_tail

Session log (tail):
$session_tail

Assumptions ledger (tail):
$assumptions_tail

Previous iteration feedback:
$loop_feedback

Context-miss guidance:
$context_miss_guidance

Workspace snapshot:
$snapshot_text

Conversation context:
$history_text

Other threads in this same workspace:
$workspace_context_text

Latest user request:
$augmented_user_prompt_controller
EOF
)

      controller_retry_used=0
      controller_format_retry_used=0
      if [ "$use_seeded_programming_controller" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Step $iteration: starting immediate workspace discovery."
        iteration_output=$(seed_programming_quick_controller_output "$augmented_user_prompt" "$plan_text")
      elif [ "$use_seeded_programming_narrow_slice_controller" -eq 1 ]; then
        if [ "$state_mode" = "IMPLEMENT" ]; then
          iteration_output=$(seed_programming_quick_narrow_slice_implement_output "$augmented_user_prompt" "$plan_text" || true)
        elif [ "$state_mode" = "VERIFY" ]; then
          iteration_output=$(seed_programming_quick_narrow_slice_verify_output "$augmented_user_prompt" "$plan_text" "$workspace_path" || true)
        else
          iteration_output=$(seed_programming_quick_narrow_slice_controller_output "$augmented_user_prompt" "$plan_text" "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" || true)
        fi
        if [ -n "$(trim "$iteration_output")" ]; then
          if [ "$state_mode" = "IMPLEMENT" ]; then
            stream_emit_line "$stream_output_file" "Step $iteration: applying one focused implementation slice."
          elif [ "$state_mode" = "VERIFY" ]; then
            stream_emit_line "$stream_output_file" "Step $iteration: verifying the focused implementation slice."
          else
            stream_emit_line "$stream_output_file" "Step $iteration: focusing on one implementation slice before patching."
          fi
        else
          use_seeded_programming_narrow_slice_controller=0
        fi
      fi
      if [ "$use_seeded_programming_controller" -ne 1 ] && [ "$use_seeded_programming_narrow_slice_controller" -ne 1 ]; then
        if [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        fi
        controller_timeout_fallback=30
        case "$compute_budget" in
          quick)
            controller_timeout_fallback=14
            ;;
          standard|auto)
            controller_timeout_fallback=20
            ;;
          long)
            controller_timeout_fallback=28
            ;;
          until-complete)
            controller_timeout_fallback=36
            ;;
        esac
        if [ "$assay_run_profile" -eq 1 ]; then
          case "$compute_budget" in
            quick)
              controller_timeout_fallback=10
              ;;
            standard|auto)
              controller_timeout_fallback=14
              ;;
            long)
              controller_timeout_fallback=18
              ;;
          esac
        fi
        controller_timeout_reserve=10
        controller_timeout_min=5
        if [ "$programming_quick_bounded_run" -eq 1 ]; then
          if [ "$controller_timeout_fallback" -gt 8 ]; then
            controller_timeout_fallback=8
          fi
          controller_timeout_reserve=6
          controller_timeout_min=4
        elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
          if [ "$controller_timeout_fallback" -gt 10 ]; then
            controller_timeout_fallback=10
          fi
          controller_timeout_reserve=6
          controller_timeout_min=4
        fi
        controller_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_timeout_fallback" "$controller_timeout_reserve" "$controller_timeout_min")
        stream_emit_line "$stream_output_file" "Step $iteration controller prompt assembled."
        stream_emit_line "$stream_output_file" "Step $iteration controller call started (mode=$state_mode, timeout=${controller_timeout_sec}s)."
        controller_stream_raw=${ARTIFICER_STREAM_RAW_CONTROLLER:-0}
        if [ "$active_run_mode" = "programming" ]; then
          controller_stream_raw=0
        fi
        if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        else
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        fi
        RUN_TIMEOUT_SEC=$controller_timeout_sec
        iteration_output=$(run_model "$model" "$controller_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        iteration_output=$(strip_terminal_noise "$iteration_output")
        iteration_output=$(canonicalize_controller_output "$iteration_output")
      fi
      if [ -z "$(trim "$iteration_output")" ] && [ "$programming_quick_bounded_run" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; }; then
        controller_retry_used=1
        append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model (first attempt)" \
          "Model failed to emit control sections on first attempt" "Retry controller once with stricter format reminder"
        stream_emit_line "$stream_output_file" "Controller returned empty output; retrying once with strict format reminder."
        controller_retry_prompt=$(cat <<EOF
$controller_prompt

Retry requirement:
- Return all required sections exactly once.
- If a section has no content, write NONE.
- Do not omit section headers.
EOF
)
        controller_retry_timeout_fallback=$((controller_timeout_fallback / 2))
        if [ "$controller_retry_timeout_fallback" -lt 8 ]; then
          controller_retry_timeout_fallback=8
        fi
        controller_retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_retry_timeout_fallback" 8 4)
        if [ "$active_run_mode" = "programming" ]; then
          controller_stream_raw=0
        fi
        if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        else
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        fi
        RUN_TIMEOUT_SEC=$controller_retry_timeout_sec
        iteration_output=$(run_model "$model" "$controller_retry_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        iteration_output=$(strip_terminal_noise "$iteration_output")
        iteration_output=$(canonicalize_controller_output "$iteration_output")
        if [ -n "$(trim "$iteration_output")" ]; then
          stream_emit_line "$stream_output_file" "Controller retry produced a structured response."
        fi
      elif [ -z "$(trim "$iteration_output")" ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model in focused narrow-slice implement step" \
          "Focused implementation step returned no controller output; retry would likely waste remaining budget" \
          "Proceed directly to local fallback summary for the chosen slice"
        stream_emit_line "$stream_output_file" "Focused implement step returned empty output; skipping retry and falling back immediately."
      fi
      stream_emit_line "$stream_output_file" "Step $iteration controller response captured."
      iteration_output_original=$iteration_output
      if [ -z "$(trim "$iteration_output")" ]; then
        if [ "$controller_retry_used" -eq 1 ]; then
          append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model after retry" \
            "Model failed to emit control sections after retry" "Fallback response generated for current mode"
        else
          append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model" \
            "Model failed to emit control sections" "Fallback response generated for current mode"
        fi
        iteration_output=$(cat <<EOF
MODE_UPDATE:
target=$state_target
blocking=model returned empty response
confidence=$state_confidence
COMMANDS:
- git status --short --untracked-files=no
CONTRACT:
NONE
PATCH:
NONE
DONE_CLAIM:
no
PLAN_UPDATE:
$plan_text
CHECKPOINT:
fallback command execution
DECISION_REQUEST:
NONE
FINAL:
NONE
EOF
)
      fi

      iteration_output_before_format_retry=$iteration_output
      if ! controller_output_has_required_sections "$iteration_output"; then
        controller_format_retry_budget_remaining=$(run_budget_remaining_seconds "$run_started_epoch" "$run_time_budget")
        if [ "$programming_quick_bounded_run" -eq 1 ]; then
          append_failure_entry "$failures_file" "controller-format-retry-skip-iteration-$iteration" \
            "Skipped format retry for bounded quick programming run" \
            "Bounded quick programming path prefers a deterministic partial summary over another controller retry" \
            "Proceed directly to local controller recovery scaffolding"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; skipping retry for bounded quick programming run."
        elif should_skip_controller_format_retry \
          "$controller_format_retry_budget_remaining" \
          "$controller_format_recovery_total" \
          "$controller_format_recovery_streak" \
          "$run_mode"; then
          append_failure_entry "$failures_file" "controller-format-retry-skip-iteration-$iteration" \
            "Skipped format retry under budget pressure" \
            "Remaining budget and prior recoveries indicate low-value extra model retry" \
            "Proceed directly to local controller recovery scaffolding"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; skipping retry under budget pressure and applying recovery scaffolding."
        else
          controller_format_retry_used=1
          append_failure_entry "$failures_file" "controller-format-retry-iteration-$iteration" \
            "Missing required controller sections on first pass" \
            "Model response omitted one or more control section headers" \
            "Retry controller once with strict section-order contract"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; retrying once with strict section-order contract."
          retry_mode_update=$(extract_section "MODE_UPDATE" "$iteration_output_before_format_retry")
          retry_mode_update=$(trim "$retry_mode_update")
          if [ -z "$retry_mode_update" ]; then
            retry_mode_update=$(cat <<EOF
target=$state_target
blocking=controller format correction required
confidence=$state_confidence
EOF
)
          fi
          retry_plan_update=$(extract_section "PLAN_UPDATE" "$iteration_output_before_format_retry")
          retry_plan_update=$(trim "$retry_plan_update")
          if [ -z "$retry_plan_update" ]; then
            retry_plan_update=$plan_text
          fi
          controller_format_retry_prompt=$(cat <<EOF
Format correction retry requirement:
- Return ONLY the required controller sections exactly once and in this order.
- MODE_UPDATE, COMMANDS, CONTRACT, PATCH, DONE_CLAIM, PLAN_UPDATE, CHECKPOINT, DECISION_REQUEST, FINAL
- Keep existing intent, but complete every missing section.
- Include every required section exactly once and in the exact order.
- Use NONE for empty sections.
- Do not omit or rename headers.
- Do not add any extra headers or prose outside sections.

Current mode: $state_mode

Preserve this MODE_UPDATE block:
$retry_mode_update

Use this PLAN_UPDATE block if missing:
$retry_plan_update

Partial output to repair:
$iteration_output_before_format_retry
EOF
)
          controller_format_retry_timeout_fallback=$((controller_timeout_fallback / 2))
          if [ "$controller_format_retry_timeout_fallback" -lt 8 ]; then
            controller_format_retry_timeout_fallback=8
          fi
          controller_format_retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_format_retry_timeout_fallback" 8 4)
          if [ "$active_run_mode" = "programming" ]; then
            controller_stream_raw=0
          fi
          if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
            ARTIFICER_STREAM_FILE="$stream_output_file"
            export ARTIFICER_STREAM_FILE
          else
            unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          fi
          RUN_TIMEOUT_SEC=$controller_format_retry_timeout_sec
          format_retry_output=$(run_model "$model" "$controller_format_retry_prompt" || true)
          unset RUN_TIMEOUT_SEC 2>/dev/null || true
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          format_retry_output=$(strip_terminal_noise "$format_retry_output")
          format_retry_output=$(canonicalize_controller_output "$format_retry_output")
          if [ -n "$(trim "$format_retry_output")" ]; then
            iteration_output=$format_retry_output
            stream_emit_line "$stream_output_file" "Controller format retry produced a non-empty response."
          else
            stream_emit_line "$stream_output_file" "Controller format retry returned empty output; continuing with recovery scaffolding."
          fi
        fi
      fi

      partially_repaired_controller_output=0
      if ! controller_output_has_required_sections "$iteration_output"; then
        partially_repaired_output=$(repair_partial_controller_output "$iteration_output" "$state_mode" "$state_target" "$state_confidence" "$plan_text")
        if [ -n "$(trim "$partially_repaired_output")" ] && controller_output_has_required_sections "$partially_repaired_output"; then
          if [ "$(trim "$partially_repaired_output")" != "$(trim "$iteration_output")" ]; then
            partially_repaired_controller_output=1
            append_failure_entry "$failures_file" "controller-format-partial-completion-iteration-$iteration" \
              "Completed partial controller output with deterministic defaults" \
              "Model returned key sections but omitted one or more trailing required sections" \
              "Continue with completed sections and avoid full malformed-output recovery"
            stream_emit_line "$stream_output_file" "Completed partial controller output by filling missing required sections."
          fi
          iteration_output=$partially_repaired_output
        fi
      fi

      recovered_controller_output=0
      if ! controller_output_has_required_sections "$iteration_output"; then
        recovered_iteration_output=$(recover_controller_output "$iteration_output" "$state_mode" "$state_target" "$state_confidence" "$plan_text")
        if [ -n "$(trim "$recovered_iteration_output")" ]; then
          recovered_controller_output=1
          append_failure_entry "$failures_file" "controller-format-iteration-$iteration" \
            "Recovered malformed controller output" "Model omitted required control sections" \
            "Continue with recovered section scaffolding and safe defaults"
          if [ "$run_mode" != "programming" ] || [ "${programming_quick_narrow_slice_run:-0}" -ne 1 ]; then
            stream_emit_line "$stream_output_file" "Recovered malformed controller output."
          fi
          iteration_output=$recovered_iteration_output
        fi
      fi

      if [ "$recovered_controller_output" -eq 1 ]; then
        recovered_log=$(cat <<EOF
## Original
$iteration_output_original

## Recovered
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$recovered_log"
      elif [ "$partially_repaired_controller_output" -eq 1 ]; then
        partial_repair_log=$(cat <<EOF
## Initial
$iteration_output_before_format_retry

## Partial Completion
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$partial_repair_log"
      elif [ "$controller_format_retry_used" -eq 1 ]; then
        format_retry_log=$(cat <<EOF
## Initial
$iteration_output_before_format_retry

## Format Retry
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$format_retry_log"
      else
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$iteration_output"
      fi
      if [ "$recovered_controller_output" -eq 1 ]; then
        controller_format_recovery_total=$((controller_format_recovery_total + 1))
        controller_format_recovery_streak=$((controller_format_recovery_streak + 1))
      else
        controller_format_recovery_streak=0
      fi

      mode_update=$(extract_section "MODE_UPDATE" "$iteration_output")
      commands_text=$(extract_section "COMMANDS" "$iteration_output")
      contract_text=$(extract_section "CONTRACT" "$iteration_output")
      patch_section=$(extract_patch_section "$iteration_output")
      patch_text=$(normalize_patch_text "$patch_section")
      if [ "${programming_quick_narrow_slice_run:-0}" -eq 1 ] && [ -n "$(trim "$patch_text")" ] && ! patch_candidate_is_usable "$patch_text"; then
        patch_text=""
      fi
      done_claim=$(extract_section "DONE_CLAIM" "$iteration_output" | sed -n '1p' | tr 'A-Z' 'a-z' | awk '{print $1}')
      plan_update=$(extract_section "PLAN_UPDATE" "$iteration_output")
      plan_update=$(sanitize_plan_update_text "$plan_update")
      checkpoint_text=$(extract_section "CHECKPOINT" "$iteration_output")
      decision_section=$(extract_section "DECISION_REQUEST" "$iteration_output")
      final_section=$(extract_section "FINAL" "$iteration_output")
      if [ "$recovered_controller_output" -eq 1 ]; then
        done_claim="no"
        final_section="NONE"
        append_failure_entry "$failures_file" "controller-format-guard-iteration-$iteration" \
          "Completion blocked after malformed controller recovery" \
          "Recovered scaffolding must not finalize a run" \
          "Require a clean structured controller pass before DONE"
        state_set "$state_file" "blocking" "controller format recovery pending clean pass"
        stream_emit_line "$stream_output_file" "Step $iteration format-recovery guard: completion blocked until a clean structured controller pass."
      fi
      adversarial_reasoning_required=0
      cross_domain_reasoning_required=0
      recovery_contract_required=0
      assumption_revision_contract_required=0
      decision_completeness_required=0
      verification_contract_required=0
      scenario_depth_contract_required=0
      source_quality_contract_required=0
      time_window_contract_required=0
      runtime_command_evidence_required=0
      runtime_claim_map_required=0
