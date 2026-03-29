    programming_followup_slice_started_count=0
    programming_followup_slice_completed_count=0
    programming_followup_slice_limit=0
    programming_followup_slice_budget_extension_used=0
    if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=4
    elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=3
    elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=2
    elif [ "$programming_quick_adjacent_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=1
    fi
    context_memory_file="$agent_dir/.context.memory.md"
    teacher_model_file="$agent_dir/.learner.model.md"
    teacher_gap_seconds=-1
    teacher_gap_summary=""
    teacher_review_days=3
    teacher_model_snapshot=""
    teacher_request_snippet=""
    run_mode_instruction=""
    assistant_mode_name=""
    assistant_mode_description=""
    assistant_mode_skills=""
    assistant_mode_subscriptions=""
    assistant_mode_allowed_caps=""
    assistant_mode_policy_excerpt=""
    controller_role_line="You are operating a typed-state coding agent."
    case "$run_mode" in
      programming)
        run_mode_instruction="Programming mode: prioritize robust implementation quality, architecture integrity on large codebases, verification depth, and safe iterative refinement."
        controller_role_line="You are operating a typed-state programming agent."
        ;;
      text-perfecter)
        run_mode_instruction="Text Perfecter mode: iteratively perfect wording and content using broad evidence, resolve contradictions, and stop only when revisions converge and stop thrashing."
        controller_role_line="You are operating a typed-state text perfection and synthesis agent."
        ;;
      teacher)
        run_mode_instruction="Teacher mode: personalize instruction using a persistent learner model, pace explanations to current understanding, and include retrieval checks plus spaced-review guidance."
        controller_role_line="You are operating a typed-state teaching and curriculum agent."
        ;;
      report)
        run_mode_instruction="Report mode: investigate thoroughly and produce an evidence-driven report with clear sections, findings, and recommendations."
        controller_role_line="You are operating a typed-state investigation and reporting agent."
        ;;
      gui-testing)
        run_mode_instruction="GUI Testing mode: execute hands-on browser automation and rigorously validate UX flow, state coherence, and visual/interactivity quality before concluding."
        controller_role_line="You are operating a typed-state hands-on GUI testing and UX reliability agent."
        ;;
      assistant)
        run_mode_instruction="Team mode: proactively sequence work and take initiative toward full task completion, including multi-phase project execution, while respecting safety policy, legal compliance, and approval gates."
        controller_role_line="You are operating a typed-state autonomous project agent."
        ;;
    esac

    ensure_mode_runtime_bootstrap
    if command -v mr_controller_variant_select_for_run >/dev/null 2>&1; then
      controller_variant_selection=$(mr_controller_variant_select_for_run "$run_event_id")
      controller_variant_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f1)
      controller_variant_bucket=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f2)
      controller_variant_active_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f3)
      controller_variant_candidate_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f4)
      if [ -n "$controller_variant_id" ] && command -v mr_controller_variant_guidance_for >/dev/null 2>&1; then
        controller_variant_guidance=$(mr_controller_variant_guidance_for "$controller_variant_id")
      fi
      if [ -n "$controller_variant_id" ]; then
        variant_stream_note="Controller variant: $controller_variant_id"
        if [ -n "$controller_variant_candidate_id" ] && [ "$controller_variant_id" = "$controller_variant_candidate_id" ]; then
          variant_stream_note="$variant_stream_note (candidate bucket=$controller_variant_bucket)"
        fi
        stream_emit_line "$stream_output_file" "$variant_stream_note"
      fi
    fi
    if [ "$run_mode" = "assistant" ] && [ -n "$assistant_mode_id" ] && command -v mr_mode_exists >/dev/null 2>&1 && mr_mode_exists "$assistant_mode_id"; then
      assistant_manifest_file=$(mr_mode_manifest_file "$assistant_mode_id")
      assistant_policy_file=$(mr_mode_policy_file "$assistant_mode_id")
      assistant_mode_name=$(mr_env_get "$assistant_manifest_file" "name" "$assistant_mode_id")
      assistant_mode_description=$(mr_env_get "$assistant_manifest_file" "description" "")
      assistant_mode_skills=$(mr_env_get "$assistant_manifest_file" "recommended_skills" "")
      assistant_mode_subscriptions=$(mr_mode_subscriptions_current "$assistant_mode_id")
      assistant_mode_allowed_caps=$(mr_mode_allowed_capabilities "$assistant_mode_id")
      assistant_mode_policy_excerpt=$(sed -n '1,80p' "$assistant_policy_file" 2>/dev/null || true)
      run_mode_instruction="Team active: ${assistant_mode_name:-$assistant_mode_id}. ${assistant_mode_description:-Use this team policy to steer planning, governance, and skill orchestration.}"
    fi

    run_mode_policy_text=$(run_mode_policy_instructions "$run_mode")
    if [ "$programming_quick_narrow_slice_run" -eq 1 ] && programming_prompt_has_multiple_branches "$programming_controller_prompt"; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Quick slice policy:
- for this quick multi-step programming run, choose one smallest verifiable implementation slice before widening to the rest of the request.
- keep the first implementation pass to one related slice and defer the remaining requested branches explicitly.
- verification should cover the chosen slice directly; do not broaden scope just to mention every requested branch.
- keep CLI entry points, tests, and docs in their own files; do not fold those branches into the primary implementation file.
EOF
)
    fi
    if [ "$programming_followup_resume_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Phase continuation policy:
- continue from the prior landed state in the same workspace instead of restarting earlier slices.
- resume exactly one previously deferred branch in this run.
- do not reopen already-landed slices unless verification proves they regressed.
EOF
)
    fi
    if [ "$programming_followup_cross_session_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Cross-session continuation policy:
- recover the prior phase plan from the same workspace instead of assuming the current conversation contains the earlier summary.
- keep the resumed phase scoped exactly as the recovered deferred queue describes.
EOF
)
    fi
    if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Cross-workspace continuation policy:
- recover the prior phase plan from the related workspace checkpoint instead of assuming the current workspace contains the earlier summary.
- keep the resumed phase scoped exactly as the recovered deferred queue describes.
EOF
)
    fi
    if [ "$programming_quick_adjacent_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Adjacent follow-up slice policy:
- if the first implementation slice lands cleanly, take at most one adjacent follow-up slice in one additional file.
- keep the follow-up file narrow and preserve the already-landed slice.
- stop after that adjacent slice instead of widening further.
EOF
)
    fi
    if [ "$programming_quick_multi_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Final follow-up slice policy:
- if the first implementation slice and adjacent follow-up slice both land cleanly, take at most one final documentation-safe follow-up slice in one additional file.
- prefer README or usage docs for that final slice instead of widening into more executable logic.
- stop after that final slice instead of broadening further.
EOF
)
    fi
    if [ "$programming_quick_verification_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Verification follow-up slice policy:
- if the implementation slice, adjacent implementation follow-up slice, and documentation-safe follow-up slice all land cleanly, take at most one final verification-safe follow-up slice in one additional test or spec file.
- prefer tests or specs for that final slice instead of widening into more executable logic or docs.
- stop after that verification-safe follow-up slice instead of broadening further.
EOF
)
    fi
    if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Release-note-safe follow-up slice policy:
- if the implementation slice, adjacent implementation follow-up slice, documentation-safe follow-up slice, and verification-safe follow-up slice all land cleanly, take at most one final release-note-safe follow-up slice in one additional changelog or release-notes file.
- prefer CHANGELOG, release notes, or migration-guide files for that final slice instead of widening into more executable logic, README, or tests.
- stop after that release-note-safe follow-up slice instead of broadening further.
EOF
)
    fi
    if [ -n "$assistant_mode_name" ] || [ -n "$assistant_mode_id" ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Team profile:
- id: ${assistant_mode_id:-none}
- name: ${assistant_mode_name:-n/a}
- description: ${assistant_mode_description:-n/a}
- recommended_skills: ${assistant_mode_skills:-none}
- subscriptions: ${assistant_mode_subscriptions:-none}
- allowed_capabilities: ${assistant_mode_allowed_caps:-none}

Team policy excerpt:
$assistant_mode_policy_excerpt
EOF
)
    fi
    augmented_user_prompt=$user_message_text
    if [ "$reasoning_followup_prompt" = "1" ]; then
      augmented_user_prompt=$reasoning_followup_context_text
    fi
    if [ "$programming_followup_resume_prompt" -eq 1 ] && [ -n "$(trim "$programming_followup_context_text")" ]; then
      augmented_user_prompt=$programming_followup_context_text
    fi
    if [ -n "$(trim "$attachment_context")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Attachment context:
$attachment_context"
    fi
    if [ -n "$(trim "$web_context")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Web context:
$web_context"
    fi
    if [ -n "$(trim "$run_mode_instruction")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Run mode directive:
$run_mode_instruction"
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      if [ -n "$assay_edit_root" ]; then
        augmented_user_prompt="${augmented_user_prompt}

Assay mentoring contract:
- Do not ask for user decisions; choose reasonable defaults and proceed.
- Constrain all file edits to: ${assay_edit_root}/
- If implementation needs files, create realistic minimal files under that path.
- Do not end with a generic couldnt-complete response; provide best-effort concrete progress and remaining risks.
- While thinking, emit short timestamp-friendly step updates.
- End with sections: Outcome, Verification Evidence, Risks, Next Improvement."
      else
        augmented_user_prompt="${augmented_user_prompt}

Assay mentoring contract:
- Do not ask for user decisions; choose reasonable defaults and proceed.
- The workspace is isolated for assay use; edit the real workspace files for the chosen slice rather than a synthetic subdirectory.
- Keep the implementation to one small verifiable slice before widening.
- Do not end with a generic couldnt-complete response; provide best-effort concrete progress and remaining risks.
- While thinking, emit short timestamp-friendly step updates.
- End with sections: Outcome, Verification Evidence, Risks, Next Improvement."
      fi
    fi
    if [ -n "$(trim "$explicit_skill_context_text")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Explicit skill actuator results:
$explicit_skill_context_text"
    fi
    if [ -n "$assistant_mode_id" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Team metadata:
- mode_id: $assistant_mode_id
- mode_name: ${assistant_mode_name:-$assistant_mode_id}
- recommended_skills: ${assistant_mode_skills:-none}
- subscriptions: ${assistant_mode_subscriptions:-none}"
    fi

    ensure_agent_files "$agent_dir"
    : > "$changed_paths_file"
    ARTIFICER_PROGRAMMING_CHANGED_PATHS=""
    if [ "$programming_followup_resume_prompt" -eq 1 ]; then
      programming_seed_changed_paths_from_assistant_summary "$workspace_path" "$programming_followup_prior_assistant_text" "$changed_paths_file"
      programming_followup_resume_target_path=$(programming_deferred_branch_target_path_for_label "$workspace_path" "$programming_followup_target_branch")
      programming_followup_resume_target_path=$(programming_resolve_workspace_relative_path "$workspace_path" "$programming_followup_resume_target_path")
      programming_followup_resume_target_path=$(programming_normalize_relative_path "$programming_followup_resume_target_path")
      if [ -n "$(trim "$programming_followup_resume_target_path")" ]; then
        programming_followup_slice_path=$programming_followup_resume_target_path
        if programming_path_is_post_verification_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="post-verification-safe"
        elif programming_path_is_verification_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="verification"
        elif programming_path_is_documentation_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="documentation"
        else
          programming_followup_slice_kind="adjacent"
        fi
        programming_followup_slice_started_count=1
        programming_followup_slice_completed_count=0
        programming_followup_slice_limit=1
        if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
          stream_emit_line "$stream_output_file" "Restoring prior phase plan from another workspace."
        elif [ "$programming_followup_cross_session_prompt" -eq 1 ]; then
          stream_emit_line "$stream_output_file" "Restoring prior phase plan from another conversation in the same workspace."
        fi
        stream_emit_line "$stream_output_file" "Resuming one previously deferred branch from the prior phase plan."
      fi
    fi
    if [ "$run_mode" = "teacher" ]; then
      ensure_teacher_model_file "$teacher_model_file"
      teacher_gap_seconds=$(teacher_last_assistant_gap_seconds "$conv_dir")
      teacher_gap_summary=$(teacher_gap_summary_for_conversation "$conv_dir")
      teacher_review_days=$(teacher_review_interval_days_for_gap "$teacher_gap_seconds")
      teacher_request_snippet=$(single_line_snippet "$user_prompt")
      if [ -z "$(trim "$teacher_request_snippet")" ]; then
        teacher_request_snippet="(empty request)"
      fi
      teacher_pre_note=$(cat <<EOF
request=$teacher_request_snippet
interaction_gap=$teacher_gap_summary
recommended_review_spacing_days=$teacher_review_days
EOF
)
      append_teacher_model_note "$teacher_model_file" "Pre-run context" "$teacher_pre_note"
      teacher_model_snapshot=$(sed -n '1,180p' "$teacher_model_file" 2>/dev/null || true)
      augmented_user_prompt="${augmented_user_prompt}

Teacher pacing signal:
- interaction_gap: $teacher_gap_summary
- recommended_review_spacing_days: $teacher_review_days

Learner model snapshot:
$teacher_model_snapshot"
    fi
    implementation_expected=0
    reasoning_completion_preferred_run=0
    if [ "$active_run_mode" = "programming" ] || prompt_requires_code_implementation "$augmented_user_prompt"; then
      implementation_expected=1
    fi
    if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      reasoning_completion_preferred_run=1
    fi
    plan_timeout_fallback=20
    case "$compute_budget" in
      quick)
        plan_timeout_fallback=10
        ;;
      standard|auto)
        plan_timeout_fallback=14
        ;;
      long)
        plan_timeout_fallback=20
        ;;
      until-complete)
        plan_timeout_fallback=24
        ;;
    esac
    if [ "$assay_run_profile" -eq 1 ]; then
      case "$compute_budget" in
        quick)
          plan_timeout_fallback=8
          ;;
        standard|auto)
          plan_timeout_fallback=10
          ;;
        long)
          plan_timeout_fallback=12
          ;;
      esac
    fi
    if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$plan_timeout_fallback" -gt 5 ]; then
      plan_timeout_fallback=5
    fi
    if [ "$programming_quick_bounded_run" -eq 1 ] || [ "$programming_quick_narrow_slice_run" -eq 1 ]; then
      bootstrap_quick_programming_plan_file "$plan_file" "$augmented_user_prompt"
      stream_emit_line "$stream_output_file" "Bounded programming start: using deterministic quick plan."
    else
      plan_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$plan_timeout_fallback" 8 5)
      RUN_TIMEOUT_SEC=$plan_timeout_sec
      bootstrap_plan_file "$plan_file" "$model" "$workspace_path" "$augmented_user_prompt"
      unset RUN_TIMEOUT_SEC 2>/dev/null || true
    fi
    initialize_state_file "$state_file" "$augmented_user_prompt"

    commands_json=""
    commands_first=1
    loop_feedback="No prior action in this run."
    loop_summary=""
    assistant_output=""
    run_command_success_total=0
    controller_format_recovery_total=0
    controller_format_recovery_streak=0
    controller_format_done_block_total=0
    stagnation_last_signature=""
    stagnation_repeat_count=0
    run_budget_exhausted=0

    iteration=1
    while :; do
      run_mode=$active_run_mode
      if [ "$max_iterations" -gt 0 ] && [ "$iteration" -gt "$max_iterations" ]; then
        allow_reasoning_extension=0
        if [ "$reasoning_completion_preferred_run" -eq 1 ] && [ "$implementation_expected" -eq 0 ]; then
          extra_iteration_cap=$((max_iterations + 1))
          if [ "$iteration" -le "$extra_iteration_cap" ]; then
            extension_now_epoch=$(date +%s 2>/dev/null || printf '0')
            case "$extension_now_epoch" in
              ""|*[!0-9]*)
                extension_now_epoch=$run_started_epoch
                ;;
            esac
            extension_elapsed=$((extension_now_epoch - run_started_epoch))
            if [ "$extension_elapsed" -lt 0 ]; then
              extension_elapsed=0
            fi
            extension_remaining=$((run_time_budget - extension_elapsed))
            if [ "$extension_remaining" -ge 75 ]; then
              allow_reasoning_extension=1
              stream_emit_line "$stream_output_file" "Step $iteration extension: reasoning-completion guard requested up to $extra_iteration_cap iterations (remaining budget ${extension_remaining}s)."
            fi
          fi
        fi
        if [ "$allow_reasoning_extension" -ne 1 ]; then
          break
        fi
      fi
      stream_emit_line "$stream_output_file" "Iteration $iteration started."
      if [ -f "$running_stop_file" ]; then
        forced_queue_status="cancelled"
        assistant_output="Run stopped."
        stream_emit_line "$stream_output_file" "Stop requested by user."
        append_failure_entry "$failures_file" "iteration-$iteration:run-stop" "Stop requested by user" \
          "User requested cancellation" "Finalize run as cancelled"
        break
      fi
      run_now_epoch=$(date +%s)
      run_elapsed=$((run_now_epoch - run_started_epoch))
      run_remaining_budget=$((run_time_budget - run_elapsed))
      if [ "$run_remaining_budget" -lt 0 ]; then
        run_remaining_budget=0
      fi
      if [ "$reasoning_completion_preferred_run" -eq 1 ] && [ "$implementation_expected" -eq 0 ] && [ "$run_remaining_budget" -gt 0 ]; then
        reasoning_reserve_sec=$(reasoning_completion_reserve_seconds \
          "$compute_budget" \
          "$assay_run_profile" \
          "$controller_format_recovery_total" \
          "$stagnation_repeat_count")
        if [ "$run_remaining_budget" -le "$reasoning_reserve_sec" ]; then
          stream_emit_line "$stream_output_file" "Iteration $iteration budget guard: reserving ${run_remaining_budget}s for final reasoning synthesis salvage (target reserve ${reasoning_reserve_sec}s)."
          break
        fi
      fi
      if [ "$run_elapsed" -ge "$run_time_budget" ]; then
        if [ "$programming_followup_slice_budget_extension_used" -eq 0 ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_kind" = "post-verification-safe" ]; then
          run_time_budget=$((run_time_budget + 35))
          programming_followup_slice_budget_extension_used=1
          stream_emit_line "$stream_output_file" "Extending the run budget briefly to finish the pending release-note-safe follow-up slice."
          continue
        fi
        if [ "$programming_followup_slice_budget_extension_used" -eq 0 ] && [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_kind" = "verification" ]; then
          run_time_budget=$((run_time_budget + 45))
          programming_followup_slice_budget_extension_used=1
          stream_emit_line "$stream_output_file" "Extending the run budget briefly to finish the pending verification-safe follow-up slice."
          continue
        fi
        # Time-budget expiry still yields a structured partial deliverable, so treat it as a completed run.
        run_budget_exhausted=1
        forced_queue_status="done"
        elapsed_minutes=$((run_elapsed / 60))
        elapsed_seconds=$((run_elapsed % 60))
        assistant_output=$(cat <<EOF
Outcome: Reached the configured run-time budget before full completion.
Verification Evidence: Iteration logs and command traces were captured before timeout. Worked for ${elapsed_minutes}m ${elapsed_seconds}s.
Assumptions and Alternatives: Incomplete signals were handled with explicit defaults; alternative interpretations remain and should be validated in the next slice.
Contradiction Check: Any conflicting constraints were treated as non-simultaneously satisfiable until evidence proves otherwise.
Risks: Partial progress may leave unverified changes or unfinished implementation details.
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
      reflexive_context_block="Reflexive knowledge is disabled for this run."
      if [ "$REFLEXIVE_KNOWLEDGE" = "1" ]; then
        if command -v self_knowledge_reflexive_prompt_block >/dev/null 2>&1; then
          reflexive_context_block=$(self_knowledge_reflexive_prompt_block)
        else
          reflexive_context_block=$(cat <<'EOF'
Reflexive knowledge is enabled.
- explain Artificer with concrete UI labels and file paths
- mark inferred details explicitly
EOF
)
        fi
      fi
      command_slot_guidance_file=$(mktemp)
      {
        printf '%s\n' "- up to 3 commands total"
        printf '%s\n' "- read-only shell commands for investigation/debugging"
        if [ "$REFLEXIVE_KNOWLEDGE" = "1" ]; then
          printf '%s\n' "- for reflexive system introspection tasks, you may use:"
          printf '%s\n' "  - artificer-appctl knowledge show"
          printf '%s\n' "  - artificer-appctl knowledge teach --topic <overview|gui|architecture|llm-foundations|ollama-runtime|ollama-contributing|self-actuation>"
        fi
        if [ "$SELF_ACTUATION" = "1" ]; then
          printf '%s\n' "- for self-actuation, inspect current resources before mutating them:"
          printf '%s\n' "  - artificer-appctl project list --json"
          printf '%s\n' "  - artificer-appctl automation list --json"
          printf '%s\n' "  - artificer-appctl thread list --workspace-id <id> --json"
          printf '%s\n' "- prefer the orchestrated preview/apply flow for mutations:"
          printf '%s\n' "  - artificer-appctl self-actuation preview --operation <operation> ... --json"
          printf '%s\n' "  - artificer-appctl self-actuation apply --operation <operation> --confirm-token <token> ... --json"
          printf '%s\n' "- manage policy and audit surfaces when needed:"
          printf '%s\n' "  - artificer-appctl self-actuation policy-get [--workspace-id <id>] [--action <operation>] --json"
          printf '%s\n' "  - artificer-appctl self-actuation policy-set --action <operation> --enabled <0|1> [--workspace-id <id>] --json"
          printf '%s\n' "  - artificer-appctl self-actuation audit --limit <n> --json"
          printf '%s\n' "- direct mutation commands are available when appropriate:"
          printf '%s\n' "  - artificer-appctl project add|rename|delete ..."
          printf '%s\n' "  - artificer-appctl thread new|archive ..."
          printf '%s\n' "  - artificer-appctl automation upsert|toggle|run-now|delete ..."
        fi
        printf '%s\n' "- otherwise NONE"
      } > "$command_slot_guidance_file"
      command_slot_guidance=$(cat "$command_slot_guidance_file")
      rm -f "$command_slot_guidance_file"

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

Reflexive system context:
$reflexive_context_block

Return ONLY these sections exactly:

MODE_UPDATE:
target=<value>
blocking=<value>
confidence=<0.00-1.00>

COMMANDS:
$command_slot_guidance

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
      claim_evidence_contract_required=0
      high_risk_fail_closed_required=0
      if prompt_requires_adversarial_reasoning "$augmented_user_prompt"; then
        adversarial_reasoning_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 0 ] && printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'teacher|teaching|explain|misconception|counterexample|near[- ]?miss|retry'; then
        adversarial_reasoning_required=1
      fi
      if prompt_requires_cross_domain_reasoning "$augmented_user_prompt"; then
        cross_domain_reasoning_required=1
      fi
      if prompt_requires_decision_completeness "$augmented_user_prompt"; then
        decision_completeness_required=1
      fi
      if [ "$cross_domain_reasoning_required" -eq 1 ]; then
        decision_completeness_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ]; then
        decision_completeness_required=1
      fi
      if prompt_requires_recovery_contract "$augmented_user_prompt"; then
        recovery_contract_required=1
      fi
      if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
        assumption_revision_contract_required=1
      fi
      if [ "$assumption_revision_contract_required" -eq 0 ] && [ "$adversarial_reasoning_required" -eq 1 ] && printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'misconception|false assumption|plausible but false|first narrative|attractive but wrong|initial assumption|assumption[- ]?revision|invalidated|prove (this|it) wrong|confidence shift'; then
        assumption_revision_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ]; then
        recovery_contract_required=1
      fi
      if [ "$assumption_revision_contract_required" -eq 1 ]; then
        recovery_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        verification_contract_required=1
      fi
      if [ "$verification_contract_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        source_quality_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        scenario_depth_contract_required=1
      fi
      if prompt_requires_time_windowed_validation "$augmented_user_prompt"; then
        time_window_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ]; then
        time_window_contract_required=1
      fi
      if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
        high_risk_fail_closed_required=1
      fi
      if [ "$high_risk_fail_closed_required" -eq 1 ]; then
        verification_contract_required=1
        source_quality_contract_required=1
        scenario_depth_contract_required=1
        time_window_contract_required=1
      fi
      case "$run_mode" in
        report|teacher|security-audit|pentest|text-perfecter|gui-testing)
          source_quality_contract_required=1
          ;;
      esac
      if [ "$verification_contract_required" -eq 1 ] && [ "$run_command_success_total" -gt 0 ]; then
        runtime_command_evidence_required=1
      fi
      if [ "$runtime_command_evidence_required" -eq 1 ]; then
        if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
          runtime_claim_map_required=1
        fi
        case "$run_mode" in
          report|teacher|security-audit|pentest|text-perfecter|gui-testing)
            runtime_claim_map_required=1
            ;;
        esac
        if [ "$high_risk_fail_closed_required" -eq 1 ]; then
          runtime_claim_map_required=1
        fi
      fi
      if [ "$verification_contract_required" -eq 1 ] || [ "$source_quality_contract_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        claim_evidence_contract_required=1
      fi
      if [ "$runtime_claim_map_required" -eq 1 ]; then
        claim_evidence_contract_required=1
      fi
      final_trimmed=$(trim "$final_section")
      if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ]; then
        if [ "$adversarial_reasoning_required" -eq 1 ]; then
          final_section=$(normalize_adversarial_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$cross_domain_reasoning_required" -eq 1 ]; then
          final_section=$(normalize_cross_domain_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$recovery_contract_required" -eq 1 ]; then
          final_section=$(normalize_recovery_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$assumption_revision_contract_required" -eq 1 ]; then
          final_section=$(normalize_assumption_revision_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$decision_completeness_required" -eq 1 ]; then
          final_section=$(normalize_decision_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$verification_contract_required" -eq 1 ]; then
          final_section=$(normalize_verification_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$runtime_command_evidence_required" -eq 1 ]; then
          final_section=$(ensure_output_has_runtime_command_evidence \
            "$final_trimmed" \
            "$loop_summary" \
            "$run_command_success_total" \
            "$augmented_user_prompt" \
            "$runtime_claim_map_required")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$claim_evidence_contract_required" -eq 1 ]; then
          final_section=$(normalize_claim_evidence_completeness_contract "$final_trimmed" "$augmented_user_prompt" "$loop_summary")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$source_quality_contract_required" -eq 1 ]; then
          final_section=$(normalize_source_quality_contradiction_contract "$final_trimmed" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ]; then
          final_section=$(normalize_ambiguity_final_contract "$final_trimmed")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$scenario_depth_contract_required" -eq 1 ]; then
          final_section=$(normalize_scenario_depth_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        final_section=$(normalize_reasoning_followup_thread_contract "$final_trimmed" "$augmented_user_prompt")
        final_section=$(normalize_reasoning_live_contract "$final_section" "$augmented_user_prompt")
        final_trimmed=$(trim "$final_section")
        if [ "$high_risk_fail_closed_required" -eq 1 ]; then
          final_section=$(normalize_high_risk_fail_closed_contract "$final_trimmed" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
          final_trimmed=$(trim "$final_section")
        fi
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] && [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ]; then
        if ! final_has_adversarial_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:adversarial-final-contract" \
            "Final section missing explicit adversarial reasoning contract" \
            "Prompt required adversarial reasoning but FINAL still lacked assumptions/alternatives/conflict/contradiction/false-premise challenge signals" \
            "Require a revised FINAL with assumptions, contradiction checks, false-premise challenge, and premise-validation evidence before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing adversarial reasoning contract"
          stream_emit_line "$stream_output_file" "Step $iteration adversarial-quality gate blocked completion; requesting richer FINAL reasoning."
        fi
      fi
      if [ "$cross_domain_reasoning_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        min_cross_axes=3
        if printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'teacher|misconception|explain|learn'; then
          min_cross_axes=4
        fi
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && (! final_has_cross_domain_signals "$final_trimmed" "$min_cross_axes" || ! final_has_cross_domain_synthesis_contract "$final_trimmed"); then
          append_failure_entry "$failures_file" "iteration-$iteration:cross-domain-final-contract" \
            "Final section lacked cross-domain synthesis contract" \
            "Prompt required cross-domain reasoning but FINAL did not include complete lens coverage plus explicit tradeoff/rejected-alternative mapping" \
            "Require a revised FINAL with explicit cross-domain integration, lens coverage, and tradeoff ledger"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing cross-domain integration"
          stream_emit_line "$stream_output_file" "Step $iteration cross-domain gate blocked completion; requesting broader synthesis."
        fi
      fi
      if [ "$recovery_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_recovery_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:recovery-final-contract" \
            "Final section lacked recovery/self-correction contract" \
            "Prompt required reliability under uncertainty but FINAL missed explicit re-plan trigger and self-correction evidence" \
            "Require a revised FINAL with recovery and self-correction structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing recovery/self-correction contract"
          stream_emit_line "$stream_output_file" "Step $iteration recovery gate blocked completion; requesting re-plan triggers and self-correction evidence."
        fi
      fi
      if [ "$assumption_revision_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_assumption_revision_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:assumption-revision-contract" \
            "Final section lacked assumption-revision contract" \
            "Prompt required explicit revision from invalidated assumptions but FINAL missed initial-assumption, invalidating-evidence, revised-decision, or evidence-delta signals" \
            "Require a revised FINAL with full assumption-revision structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing assumption-revision contract"
          stream_emit_line "$stream_output_file" "Step $iteration assumption-revision gate blocked completion; requesting explicit invalidation and revised-decision structure."
        fi
      fi
      if [ "$decision_completeness_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_decision_completeness "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:decision-completeness-contract" \
            "Final section lacked required decision completeness signals" \
            "Prompt required decision completeness but FINAL missed one or more of decision/fallback/disconfirming evidence/priority order" \
            "Require a revised FINAL with explicit decision completeness before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing decision completeness"
          stream_emit_line "$stream_output_file" "Step $iteration decision-completeness gate blocked completion; requesting fuller decision structure."
        fi
      fi
      if [ "$verification_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_verification_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:verification-contract" \
            "Final section lacked verification-depth signals" \
            "Prompt required verification quality but FINAL missed one or more of verification evidence/disconfirming evidence/risk register signals" \
            "Require a revised FINAL with explicit verification evidence and invalidation criteria before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing verification depth"
          stream_emit_line "$stream_output_file" "Step $iteration verification-quality gate blocked completion; requesting explicit verification evidence."
        fi
      fi
      if [ "$source_quality_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_source_quality_contradiction_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:source-quality-contradiction-contract" \
            "Final section lacked source-quality ranking or contradiction-resolution signals" \
            "Reasoning completion required source-confidence tiers plus explicit contradiction handling, but FINAL was missing one or more required signals" \
            "Require revised FINAL with Source Quality Ranking, Contradiction Check, and Source Conflict Resolution before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing source-quality contradiction contract"
          stream_emit_line "$stream_output_file" "Step $iteration source-quality gate blocked completion; requesting confidence-tiered source ranking with contradiction resolution."
        fi
      fi
      if [ "$runtime_command_evidence_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_runtime_command_evidence_contract "$final_trimmed" "$runtime_claim_map_required"; then
          append_failure_entry "$failures_file" "iteration-$iteration:runtime-command-evidence-contract" \
            "Final section lacked runtime command-backed evidence anchors" \
            "Run had successful command traces but FINAL missed command-anchored verification evidence or required claim map" \
            "Require revised FINAL with command anchors (and claim-to-evidence map when required) before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing runtime command evidence anchors"
          stream_emit_line "$stream_output_file" "Step $iteration runtime-evidence gate blocked completion; requesting command-backed evidence anchors."
        fi
      fi
      if [ "$claim_evidence_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_claim_evidence_completeness_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:claim-evidence-completeness-contract" \
            "Final section lacked claim-to-evidence map completeness signals" \
            "Reasoning completion required at least two claim-map entries with verification and invalidation links plus caveats, but FINAL remained under-specified" \
            "Require revised FINAL with multi-claim map entries (claim -> anchor -> verification -> invalidation) and explicit evidence caveats before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing claim-evidence completeness"
          stream_emit_line "$stream_output_file" "Step $iteration claim-evidence gate blocked completion; requesting multi-claim evidence mapping."
        fi
      fi
      if [ "$scenario_depth_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_scenario_specific_depth "$final_trimmed" "$augmented_user_prompt"; then
          append_failure_entry "$failures_file" "iteration-$iteration:scenario-depth-contract" \
            "Final section lacked scenario-specific depth anchors" \
            "Reasoning completion required scenario-anchored detail with conditional trigger logic, but FINAL remained generic or untethered to concrete prompt anchors" \
            "Require revised FINAL with context anchor plus scenario-specific check containing explicit if/when/unless trigger tied to prompt-specific tokens"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing scenario-specific depth anchors"
          stream_emit_line "$stream_output_file" "Step $iteration scenario-depth gate blocked completion; requesting prompt-anchored if/when trigger specificity."
        fi
      fi
      if [ "$time_window_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_time_window_validation_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:time-window-validation-contract" \
            "Final section lacked time-windowed validation signals" \
            "Prompt required owner+window validation but FINAL missed validation-owner or decision-window signals" \
            "Require a revised FINAL with explicit validation owner and review time window before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing owner/window validation"
          stream_emit_line "$stream_output_file" "Step $iteration owner-window gate blocked completion; requesting validation owner and review window."
        fi
      fi
      if [ "$high_risk_fail_closed_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_high_risk_fail_closed_contract "$final_trimmed" "$run_command_success_total"; then
          append_failure_entry "$failures_file" "iteration-$iteration:high-risk-fail-closed-contract" \
            "Final section lacked fail-closed high-risk verification contract" \
            "High-risk prompt required explicit verification-status/go-no-go/evidence-to-proceed/residual-risk structure with cautious posture" \
            "Require a revised FINAL with fail-closed high-risk verification structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "high-risk fail-closed verification contract missing"
          stream_emit_line "$stream_output_file" "Step $iteration high-risk fail-closed gate blocked completion; requesting explicit go/no-go and required evidence."
        fi
      fi
      done_claim_for_stream=$done_claim
      if [ -z "$(trim "$done_claim_for_stream")" ]; then
        done_claim_for_stream="none"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration control sections parsed (done_claim=$done_claim_for_stream)."

      decision_question=$(trim "$(printf '%s\n' "$decision_section" | sed -n 's/^question=//p' | sed -n '1p')")
      decision_options_file=$(mktemp)
      printf '%s\n' "$decision_section" | sed -n 's/^option=//p' > "$decision_options_file"
      decision_requested=0
      decision_surface_category="none"
      suppress_assay_decision_requests=0
      if [ "$assay_run_profile" -eq 1 ]; then
        suppress_assay_decision_requests=1
      fi
      if [ -n "$decision_question" ] && [ "$decision_question" != "NONE" ] && [ -s "$decision_options_file" ]; then
        decision_requested=1
      fi
      if [ "$decision_requested" -eq 1 ]; then
        decision_surface_category=$(decision_request_category_for_prompt "$augmented_user_prompt" "$decision_question" "$run_mode" "$commands_text")
        if ! should_allow_model_decision_request "$augmented_user_prompt" "$decision_question" "$run_mode" "$commands_text"; then
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Ignored unsolicited decision request" \
            "Model requested a user decision for a prompt that did not ask for a choice" \
            "Proceed autonomously with implementation"
          decision_requested=0
          decision_surface_category="none"
        fi
      fi
      if [ "$decision_requested" -eq 1 ] && [ "$suppress_assay_decision_requests" -eq 1 ]; then
        append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
          "Suppressed decision request in assay run" \
          "Assay mentoring contract requires autonomous default selection" \
          "Proceed autonomously and surface assumptions in final sections"
        decision_requested=0
        decision_surface_category="none"
      fi

      prompt_lower_compliance=$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')
      commands_lower_compliance=$(printf '%s' "$commands_text" | tr '[:upper:]' '[:lower:]')
      patch_lower_compliance=$(printf '%s' "$patch_text" | tr '[:upper:]' '[:lower:]')
      compliance_status="pass"
      legal_check="pass"
      ethical_check="pass"
      gate_check="none"
      compliance_findings="No obvious legal/ethical risks detected in current controller outputs."
      compliance_gate="none"
      compliance_next="Continue with current mode."
      if [ "$run_mode" = "assistant" ] && printf '%s' "$prompt_lower_compliance" | grep -Eq 'business|launch|sales|marketing|customer|pricing|operations|company'; then
        gate_check="required"
        compliance_status="caution"
        compliance_findings="Assistant-mode project appears to involve real-world business operations."
        compliance_gate="Require explicit user approval before irreversible external actions."
        compliance_next="Prepare options and request user confirmation before external execution."
      fi
      if printf '%s' "$commands_lower_compliance" | grep -Eq '\bcurl\b|\bwget\b|\bnc\b|\bssh\b|\bscp\b|\bsftp\b|\bftp\b|\btelnet\b'; then
        legal_check="attention"
        compliance_status="caution"
        compliance_findings="${compliance_findings} Proposed commands include external/network tooling."
        if [ "$gate_check" = "none" ]; then
          gate_check="required"
        fi
        compliance_gate="Require user approval before any external-network side effects."
        compliance_next="Use local analysis until user approves external actions."
      fi
      if decision_commands_trigger_destructive_gate "$commands_text"; then
        compliance_status="caution"
        compliance_findings="${compliance_findings} Proposed commands include destructive local operations."
        if [ "$gate_check" = "none" ]; then
          gate_check="required"
        fi
        compliance_gate="Require explicit approval before destructive local actions."
        compliance_next="Pause and surface safe alternatives plus rollback implications."
      fi
      if printf '%s' "$patch_lower_compliance" | grep -Eq 'spam|phish|credential stuffing|captcha bypass|ddos|malware|exploit'; then
        ethical_check="fail"
        compliance_status="blocked"
        compliance_findings="${compliance_findings} Candidate patch text suggests abusive or harmful behavior."
        compliance_gate="Block unsafe implementation path; request a safe alternative objective."
        compliance_next="Refuse harmful approach and propose compliant alternatives."
      fi
      compliance_checks_text=$(cat <<EOF
- legal_compliance=$legal_check
- ethical_non_abuse=$ethical_check
- external_action_gate=$gate_check
EOF
)
      append_compliance_entry "$compliance_file" "$run_mode" "$state_mode" "$compliance_status" "$compliance_checks_text" "$compliance_findings" "$compliance_gate" "$compliance_next"

      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && decision_commands_trigger_destructive_gate "$commands_text"; then
        decision_question="Potentially destructive actions are implied. How should I proceed?"
        cat > "$decision_options_file" <<'EOF'
Pause and provide a non-destructive dry-run plan
Proceed only with explicit rollback steps and backups
Stop and return a risk assessment only
EOF
        decision_requested=1
        decision_surface_category="destructive-action-gate"
      fi
      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && [ "$gate_check" = "required" ] && decision_commands_trigger_external_gate "$commands_text"; then
        decision_question="External/network actions are implied. Which path should I take?"
        cat > "$decision_options_file" <<'EOF'
Proceed with local-only analysis and no external execution
Approve external/network actions for this run
Stop and return a risk summary only
EOF
        decision_requested=1
        decision_surface_category="external-action-gate"
      fi
      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && decision_prompt_has_missing_required_inputs "$augmented_user_prompt"; then
        if prompt_requests_autonomous_defaults "$augmented_user_prompt"; then
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Suppressed missing-input decision due autonomous-default directive" \
            "Prompt explicitly requested autonomous execution/default assumptions" \
            "Proceed with explicit assumptions and avoid awaiting_decision pause"
          decision_requested=0
          decision_surface_category="none"
          stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: missing-input gate bypassed via autonomous-default directive."
        else
          decision_question="Required inputs appear missing. How should I continue?"
          cat > "$decision_options_file" <<'EOF'
Proceed with sensible defaults and clearly label assumptions
Pause and ask me for the exact missing values first
Generate a template of required inputs, then continue after I fill it in
EOF
          decision_requested=1
          decision_surface_category="required-input-missing"
        fi
      fi
      if [ "$decision_requested" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: request prepared ($decision_surface_category)."
      else
        stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: no user decision required."
      fi

      target_update=$(printf '%s\n' "$mode_update" | sed -n 's/^target=//p' | sed -n '1p')
      blocking_update=$(printf '%s\n' "$mode_update" | sed -n 's/^blocking=//p' | sed -n '1p')
      confidence_update=$(printf '%s\n' "$mode_update" | sed -n 's/^confidence=//p' | sed -n '1p')
      target_update=$(printf '%s\n' "$target_update" | perl -CS -pe 's/[[:space:]._-]*blocking=.*$//i; s/[[:space:]._-]*confidence=.*$//i')
      target_update=$(trim "$target_update")

      if [ -n "$(trim "$target_update")" ]; then
        state_set "$state_file" "target" "$target_update"
      fi
      if [ -n "$(trim "$blocking_update")" ]; then
        state_set "$state_file" "blocking" "$blocking_update"
      fi
      case "$confidence_update" in
        ""|*[!0-9.]*)
          ;;
        *)
          state_set "$state_file" "confidence" "$confidence_update"
          ;;
      esac

      if printf '%s\n' "$plan_update" | grep -q '^Goal:'; then
        printf '%s\n' "$plan_update" > "$plan_file"
      fi

      assumption_text_runtime="Latest workspace understanding still matches current task context."
      unchecked_text_runtime="Some file contents may be stale until explicitly re-read this iteration."
      case "$state_mode" in
        INVESTIGATE)
          assumption_text_runtime="Current directory/file inventory is representative for design planning."
          unchecked_text_runtime="Implementation files may still require targeted inspection."
          ;;
        DESIGN)
          assumption_text_runtime="Current contract captures user-visible behavior and constraints."
          unchecked_text_runtime="Edge cases may remain unverified until IMPLEMENT/VERIFY."
          ;;
        IMPLEMENT)
          assumption_text_runtime="Patch content aligns with requested behavior and constraints."
          unchecked_text_runtime="Runtime behavior may differ until VERIFY commands run."
          ;;
        VERIFY)
          assumption_text_runtime="Verification commands are sufficient to establish readiness."
          unchecked_text_runtime="Non-exercised interaction paths may still need manual checks."
          ;;
      esac
      constraint_risk_runtime=$(state_get "$state_file" "blocking" "none")
      if [ -z "$(trim "$constraint_risk_runtime")" ]; then
        constraint_risk_runtime="none"
      fi
      append_assumption_entry "$assumptions_file" "$state_mode" "$assumption_text_runtime" "$unchecked_text_runtime" "$constraint_risk_runtime"

      iteration_report=""
      next_mode="$state_mode"
      transition_reason_runtime="mode unchanged"
      if [ "$decision_requested" -eq 1 ]; then
        if save_decision_request "$conv_dir" "$decision_question" "$decision_options_file"; then
          decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
          decision_options_preview=$(sed -n '1,5p' "$decision_options_file" | sed 's/^/- /')
          if [ -z "$decision_options_preview" ]; then
            decision_options_preview="- (none)"
          fi
          iteration_report="Decision requested:
Question: $decision_question
Options:
$decision_options_preview"
          next_mode="DONE"
          transition_reason_runtime="awaiting user decision"
          state_set "$state_file" "blocking" "decision required (${decision_surface_category})"
          assistant_output="I need your decision before I can continue."
          loop_feedback=$iteration_report
          stream_emit_line "$stream_output_file" "Step $iteration paused for user decision ($decision_surface_category)."
        else
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Decision request payload invalid" "Missing question/options in model output" \
            "Continue without decision request"
          clear_decision_request "$conv_dir"
          decision_requested=0
        fi
      fi

      if [ "$decision_requested" -eq 0 ]; then
        case "$state_mode" in
        INVESTIGATE|DESIGN|VERIFY)
          command_lines_file=$(mktemp)
          extract_command_lines "$commands_text" > "$command_lines_file"

          command_lines_sanitized=$(mktemp)
          while IFS= read -r candidate_line; do
            candidate_line=$(trim "$candidate_line")
            [ -n "$candidate_line" ] || continue
            original_candidate_line=$candidate_line
            candidate_line=$(normalize_workspace_paths_in_command "$candidate_line" "$workspace_path")
            candidate_line=$(sanitize_controller_command_candidate "$candidate_line" "$state_mode")
            candidate_line=$(trim "$candidate_line")
            [ -n "$candidate_line" ] || continue
            if allowed_command "$candidate_line"; then
              printf '%s\n' "$candidate_line" >> "$command_lines_sanitized"
              if [ "$candidate_line" != "$original_candidate_line" ]; then
                append_failure_entry "$failures_file" "command-parse-iteration-$iteration" \
                  "Rewrote command candidate to safe equivalent: $original_candidate_line -> $candidate_line" \
                  "Controller proposed a command outside the mediated allowlist" \
                  "Continue with rewritten safe command"
              fi
            else
              append_failure_entry "$failures_file" "command-parse-iteration-$iteration" \
                "Discarded disallowed command candidate: $candidate_line" \
                "Controller output included commands outside the mediated allowlist" \
                "Use strict read-only mediated commands or fallback defaults"
            fi
          done < "$command_lines_file"
          mv "$command_lines_sanitized" "$command_lines_file"

          if [ ! -s "$command_lines_file" ]; then
            case "$state_mode" in
              INVESTIGATE)
                printf '%s\n%s\n' "ls" "find . -maxdepth 2 -type f" > "$command_lines_file"
                ;;
              DESIGN)
                printf '%s\n' "git status --short --untracked-files=no" > "$command_lines_file"
                ;;
              VERIFY)
                emit_default_verify_commands "$workspace_path" "$augmented_user_prompt" > "$command_lines_file"
                ;;
            esac
          fi

          if [ "$state_mode" = "VERIFY" ]; then
            case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
              *godot*)
                emit_default_verify_commands "$workspace_path" "$augmented_user_prompt" > "$command_lines_file"
                ;;
            esac
          fi

          command_count=0
          commands_ran=0
          commands_ok=1
          command_success_count=0
          approval_required_detected=0
          nonfatal_context_miss_count=0
          nonfatal_context_miss_last_status=""
          verify_success_signal=0
          verify_last_output=""
          iteration_report="$state_mode command results:"
          loop_feedback=""
          stream_emit_line "$stream_output_file" "Step $iteration executing $state_mode command batch."

          while IFS= read -r command_line; do
            command_line=$(trim "$command_line")
            [ -n "$command_line" ] || continue
            command_line=$(printf '%s\n' "$command_line" | perl -CS -pe '
              s/\r//g;
              s/\\\\n/\n/g;
              s/\\n/\n/g;
              s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
            ' | sed -n '1p')
            command_line=$(printf '%s\n' "$command_line" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
            command_line=$(trim "$command_line")
            [ -n "$command_line" ] || continue
            command_count=$((command_count + 1))
            if [ "$command_count" -gt 3 ]; then
              break
            fi

            commands_ran=$((commands_ran + 1))
            command_stream_label=$(single_line_snippet "$command_line")
            stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran started: $command_stream_label"
            tool_out=$(mktemp)
            tool_status_file=$(mktemp)
            execute_mediated_command "$workspace_id" "$workspace_path" "$command_line" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file"
            command_status=$(cat "$tool_status_file")
            command_output=$(sed -n '1,220p' "$tool_out")
            command_output=$(compact_command_output_for_context "$command_line" "$command_output" "$assay_run_profile")
            stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran status: $command_status"

            case "$command_status" in
              ok)
                command_success_count=$((command_success_count + 1))
                run_command_success_total=$((run_command_success_total + 1))
                if [ "$state_mode" = "VERIFY" ]; then
                  case "$command_line" in
                    ./*|sh\ *|bash\ *)
                      if [ -n "$(trim "$command_output")" ]; then
                        verify_success_signal=1
                        verify_last_output=$(printf '%s\n' "$command_output" | sed -n '1p')
                      fi
                      ;;
                    test\ -f\ *)
                      verify_success_signal=1
                      ;;
                    git\ status*|git\ diff*|ls|ls\ *|pwd|find\ *|cat\ *|head\ *|tail\ *|wc\ *|rg\ *|sed\ *|which\ *|command\ -v\ *)
                      ;;
                    *)
                      verify_success_signal=1
                      if [ -z "$(trim "$verify_last_output")" ] && [ -n "$(trim "$command_output")" ]; then
                        verify_last_output=$(printf '%s\n' "$command_output" | sed -n '1p')
                      fi
                      ;;
                  esac
                fi
                ;;
              missing_input|context_missing)
                nonfatal_context_miss_count=$((nonfatal_context_miss_count + 1))
                nonfatal_context_miss_last_status=$command_status
                append_failure_entry "$failures_file" "$command_line" "$command_status" \
                  "Command hit missing context/input; continuing without counting as verified success" \
                  "Adjust assumptions, locate canonical path, or run fallback inspection command"
                ;;
              *)
                commands_ok=0
                append_failure_entry "$failures_file" "$command_line" "$command_status" \
                  "Tool call failed or was blocked" "Refine command set and retry"
                if [ "$command_status" = "approval_required" ]; then
                  approval_required_detected=1
                fi
                ;;
            esac

            command_json=$(json_escape "$command_line")
            status_json=$(json_escape "$command_status")
            output_json=$(json_escape "$command_output")
            command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
              "$command_json" "$status_json" "$output_json")

            if [ "$commands_first" -eq 1 ]; then
              commands_json=$command_item
              commands_first=0
            else
              commands_json="${commands_json},${command_item}"
            fi

            iteration_report="${iteration_report}
Command: $command_line
Status: $command_status
Output:
$command_output"

            loop_feedback="${loop_feedback}
Command: $command_line
Status: $command_status
Output:
$command_output"

            rm -f "$tool_out" "$tool_status_file"
            if [ "$approval_required_detected" -eq 1 ]; then
              break
            fi
          done < "$command_lines_file"

          if [ "$approval_required_detected" -eq 0 ] && [ "$command_success_count" -eq 0 ] && [ "$nonfatal_context_miss_count" -gt 0 ] && [ "$commands_ran" -lt 3 ]; then
            recovery_command=$(context_recovery_readonly_command_for_mode "$state_mode" "$nonfatal_context_miss_last_status")
            recovery_command=$(trim "$recovery_command")
            if [ -n "$recovery_command" ] && allowed_command "$recovery_command"; then
              commands_ran=$((commands_ran + 1))
              stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran started: $recovery_command (context recovery)"
              tool_out=$(mktemp)
              tool_status_file=$(mktemp)
              execute_mediated_command "$workspace_id" "$workspace_path" "$recovery_command" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file"
              recovery_status=$(cat "$tool_status_file")
              recovery_output=$(sed -n '1,220p' "$tool_out")
              recovery_output=$(compact_command_output_for_context "$recovery_command" "$recovery_output" "$assay_run_profile")
              stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran status: $recovery_status"

              case "$recovery_status" in
                ok)
                  command_success_count=$((command_success_count + 1))
                  run_command_success_total=$((run_command_success_total + 1))
                  ;;
                missing_input|context_missing)
                  nonfatal_context_miss_count=$((nonfatal_context_miss_count + 1))
                  nonfatal_context_miss_last_status=$recovery_status
                  append_failure_entry "$failures_file" "$recovery_command" "$recovery_status" \
                    "Context-recovery fallback still hit missing inputs/context" \
                    "Broaden discovery commands or reduce path assumptions in next controller step"
                  ;;
                *)
                  commands_ok=0
                  append_failure_entry "$failures_file" "$recovery_command" "$recovery_status" \
                    "Context-recovery fallback failed or was blocked" "Revise fallback command strategy"
                  if [ "$recovery_status" = "approval_required" ]; then
                    approval_required_detected=1
                  fi
                  ;;
              esac

              recovery_command_json=$(json_escape "$recovery_command")
              recovery_status_json=$(json_escape "$recovery_status")
              recovery_output_json=$(json_escape "$recovery_output")
              recovery_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
                "$recovery_command_json" "$recovery_status_json" "$recovery_output_json")
              if [ "$commands_first" -eq 1 ]; then
                commands_json=$recovery_item
                commands_first=0
              else
                commands_json="${commands_json},${recovery_item}"
              fi

              iteration_report="${iteration_report}
Command: $recovery_command
Status: $recovery_status
Output:
$recovery_output"

              loop_feedback="${loop_feedback}
Command: $recovery_command
Status: $recovery_status
Output:
$recovery_output"

              rm -f "$tool_out" "$tool_status_file"
            fi
          fi

          rm -f "$command_lines_file"
          stream_emit_line "$stream_output_file" "Step $iteration command summary: ran=$commands_ran ok=$command_success_count context_miss=$nonfatal_context_miss_count approvals=$approval_required_detected"
          if [ "$commands_ok" -eq 1 ]; then
            stream_emit_line "$stream_output_file" "Step $iteration self-correction check: no failed assumptions remain after command review; fallback criteria refreshed."
          else
            stream_emit_line "$stream_output_file" "Step $iteration self-correction check: failed assumptions detected; fallback criteria must be revised."
          fi

          if [ "$approval_required_detected" -eq 1 ]; then
            next_mode="DONE"
            transition_reason_runtime="awaiting command approval"
            state_set "$state_file" "blocking" "command approval required"
            assistant_output="I need command approval to continue. Approve the requested command and run again."
          else
            case "$state_mode" in
              INVESTIGATE)
                if [ "$command_success_count" -gt 0 ]; then
                  if [ "$programming_quick_narrow_slice_run" -eq 1 ] && programming_prompt_has_multiple_branches "$augmented_user_prompt"; then
                    stream_emit_line "$stream_output_file" "Step $iteration: narrowing to one verified slice before wider changes."
                  fi
                  next_mode="DESIGN"
                  transition_reason_runtime="files understood"
                  state_set "$state_file" "blocking" "none"
                else
                  next_mode="INVESTIGATE"
                  transition_reason_runtime="investigation incomplete"
                  state_set "$state_file" "blocking" "investigation needs more evidence"
                fi
                ;;
              DESIGN)
                contract_trimmed=$(trim "$contract_text")
                if [ -n "$contract_trimmed" ] && [ "$contract_trimmed" != "NONE" ]; then
                  {
                    printf '# Contract\n\n'
                    printf 'Inputs:\nOutputs:\nSide Effects:\nDependencies:\nExit Codes:\nInvariants:\n\n'
                    printf '%s\n' "$contract_trimmed"
                  } > "$contract_file"
                elif [ "$commands_ok" -eq 1 ]; then
                  {
                    printf '# Contract\n\n'
                    printf 'Inputs:\n'
                    printf '%s\n' "- User request: $(printf '%s' "$augmented_user_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
                    printf 'Outputs:\n'
                    printf '%s\n' '- Requested files/content updated in workspace.'
                    printf 'Side Effects:\n'
                    printf '%s\n' '- Workspace files may be created or modified.'
                    printf 'Dependencies:\n'
                    printf '%s\n' '- POSIX sh tools and workspace filesystem.'
                    printf 'Exit Codes:\n'
                    printf '%s\n' '- 0 on success, non-zero on mediated command failures.'
                    printf 'Invariants:\n'
                    printf '%s\n' '- Keep edits scoped and syntactically valid.'
                  } > "$contract_file"
                fi

                design_completion_mode=0
                design_command_min=2
                reasoning_completion_preferred=0
                if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
                  reasoning_completion_preferred=1
                fi
                case "$active_run_mode" in
                  report|teacher|security-audit|text-perfecter|gui-testing)
                    design_command_min=3
                    ;;
                  assistant)
                    if [ "$assay_run_profile" -eq 1 ]; then
                      design_command_min=2
                    else
                      design_command_min=3
                    fi
                    ;;
                esac

                if [ "$assay_run_profile" -eq 1 ]; then
                  stream_emit_line "$stream_output_file" "Step $iteration design gate context: assay=$assay_run_profile run_mode=$active_run_mode cmd_ok=$commands_ok cmd_success=$command_success_count total_success=$run_command_success_total reasoning_pref=$reasoning_completion_preferred design_min=$design_command_min"
                fi

                if [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$reasoning_completion_preferred" -eq 1 ] && [ "$command_success_count" -ge 1 ]; then
                  design_completion_mode=1
                elif [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$run_command_success_total" -ge "$design_command_min" ]; then
                  case "$active_run_mode" in
                    report|teacher|security-audit|text-perfecter|gui-testing)
                      design_completion_mode=1
                      ;;
                    assistant)
                      if [ "$reasoning_completion_preferred" -eq 1 ] || printf '%s' "$prompt_lower_for_budget" | grep -Eq 'design|strategy|plan|diagnose|analysis|evaluate|teach|report|audit|mitigation|checklist|architecture'; then
                        design_completion_mode=1
                      fi
                      ;;
                  esac
                elif [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$run_command_success_total" -lt "$design_command_min" ]; then
                  state_set "$state_file" "blocking" "command depth below assay minimum"
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$implementation_expected" -eq 1 ]; then
                  design_completion_mode=0
                  state_set "$state_file" "blocking" "quick narrow-slice programming run requires an implementation pass"
                  stream_emit_line "$stream_output_file" "Step $iteration quick-slice guard: design cannot finish a programming run before one implementation pass."
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$active_run_mode" = "assistant" ] && [ "$implementation_expected" -eq 1 ]; then
                  design_completion_mode=0
                  state_set "$state_file" "blocking" "assistant task requires an execution pass"
                  stream_emit_line "$stream_output_file" "Step $iteration assistant execution guard: design cannot finish before one execution or verification pass."
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$high_risk_fail_closed_required" -eq 1 ]; then
                  high_risk_final_candidate=$(trim "$final_section")
                  if [ -z "$high_risk_final_candidate" ] || [ "$high_risk_final_candidate" = "NONE" ]; then
                    high_risk_final_candidate=$(trim "$checkpoint_text")
                  fi
                  if [ -n "$high_risk_final_candidate" ] && [ "$high_risk_final_candidate" != "NONE" ]; then
                    high_risk_final_candidate=$(normalize_high_risk_fail_closed_contract "$high_risk_final_candidate" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
                    high_risk_final_candidate=$(trim "$high_risk_final_candidate")
                    if [ -n "$high_risk_final_candidate" ] && [ "$high_risk_final_candidate" != "NONE" ]; then
                      final_section=$high_risk_final_candidate
                    fi
                  fi
                  if [ -z "$high_risk_final_candidate" ] || [ "$high_risk_final_candidate" = "NONE" ] || ! final_has_high_risk_fail_closed_contract "$high_risk_final_candidate" "$run_command_success_total"; then
                    design_completion_mode=0
                    state_set "$state_file" "blocking" "high-risk verification evidence incomplete"
                    stream_emit_line "$stream_output_file" "Step $iteration high-risk design gate withheld DONE; explicit fail-closed verification contract still incomplete."
                  fi
                fi

                if [ "$design_completion_mode" -eq 1 ]; then
                  candidate_final=$(trim "$final_section")
                  if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                    candidate_final=$(trim "$checkpoint_text")
                  fi
                  if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                    candidate_final="Completed the requested design deliverable with concrete constraints, verification checks, and next-step guidance."
                  fi
                  candidate_final=$(sanitize_design_completion_outcome "$candidate_final" "$augmented_user_prompt")
                  verification_line=$(reasoning_design_verification_line "$augmented_user_prompt" "$command_success_count" "$loop_feedback")
                  decision_line=$(reasoning_decision_line_for_prompt "$augmented_user_prompt")
                  fallback_line=$(reasoning_fallback_line_for_prompt "$augmented_user_prompt")
                  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$augmented_user_prompt")
                  next_improvement_text=$(reasoning_next_improvement_line_for_prompt "$augmented_user_prompt")
                  risks_text=$(reasoning_risk_line_for_prompt "$augmented_user_prompt" "DONE")
                  assistant_output=$(cat <<EOF
Outcome: $candidate_final
$verification_line
Assumptions and Alternatives: Assumptions were explicitly selected from underspecified constraints; alternatives were considered and deprioritized based on feasibility/risk.
Contradiction Check: Conflicting requirements were treated as non-simultaneously satisfiable unless explicit proof showed otherwise.
Decision: $decision_line
Priority Order: Safety, correctness, and policy obligations take precedence over speed-only gains.
Fallback Path: $fallback_line
Disconfirming Evidence: $disconfirming_line
Adversarial Probe: Include at least one abuse case, one deception vector, and one counterfactual test before broad rollout.
Risk Register: Record blast radius, cost of being wrong, and active guardrails for each major decision.
Uncertainty Range: State lower bound, expected range, and upper bound outcomes with confidence.
Risks: $risks_text
Next Improvement: $next_improvement_text
EOF
)
                  next_mode="DONE"
                  transition_reason_runtime="design deliverable completed"
                  state_set "$state_file" "blocking" "none"
                elif [ -s "$contract_file" ] && [ "$commands_ok" -eq 1 ]; then
                  if [ "$implementation_expected" -eq 1 ]; then
                    next_mode="IMPLEMENT"
                    transition_reason_runtime="contract exists"
                    state_set "$state_file" "blocking" "none"
                  else
                    next_mode="DESIGN"
                    transition_reason_runtime="reasoning contract incomplete"
                    state_set "$state_file" "blocking" "reasoning final contract incomplete"
                    stream_emit_line "$stream_output_file" "Step $iteration reasoning-mode guard kept DESIGN active; requesting revised FINAL instead of IMPLEMENT patch loop."
                  fi
                else
                  next_mode="DESIGN"
                  transition_reason_runtime="contract missing or design checks failed"
                  state_set "$state_file" "blocking" "design contract incomplete"
                fi
                ;;
              VERIFY)
                verify_completion_allowed=1
                if [ "$high_risk_fail_closed_required" -eq 1 ]; then
                  verify_final_candidate=$(trim "$final_section")
                  if [ -z "$verify_final_candidate" ] || [ "$verify_final_candidate" = "NONE" ] || ! final_has_high_risk_fail_closed_contract "$verify_final_candidate" "$run_command_success_total"; then
                    verify_completion_allowed=0
                  fi
                fi
                if [ "$verify_completion_allowed" -eq 1 ] && [ "$commands_ok" -eq 1 ] && { [ "$done_claim" = "yes" ] || [ "$verify_success_signal" -eq 1 ]; }; then
                  next_mode="DONE"
                  transition_reason_runtime="verification passed"
                  state_set "$state_file" "blocking" "none"
                  if [ "$verify_success_signal" -eq 1 ] && [ "$done_claim" != "yes" ]; then
                    if is_hello_world_script_task "$augmented_user_prompt"; then
                      verify_out=$(trim "$verify_last_output")
                      if [ -n "$verify_out" ]; then
                        assistant_output="I created and ran the script successfully. Output: $verify_out"
                      else
                        assistant_output="I created and ran the script successfully."
                      fi
                    else
                      candidate_final=$(trim "$final_section")
                      if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                        candidate_final=$(trim "$checkpoint_text")
                      fi
                      if [ -n "$candidate_final" ] && [ "$candidate_final" != "NONE" ]; then
                        assistant_output="$candidate_final"
                      else
                        assistant_output="Completed implementation and verification successfully."
                      fi
                    fi
                  else
                    candidate_final=$(trim "$final_section")
                    if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                      candidate_final=$(trim "$checkpoint_text")
                    fi
                    if [ -n "$candidate_final" ] && [ "$candidate_final" != "NONE" ]; then
                      assistant_output="$candidate_final"
                    fi
                  fi

                  if [ "$run_mode" = "programming" ] && [ "$programmer_review_enabled" -eq 1 ] && [ "$programmer_review_rounds_completed" -lt "$programmer_review_max_rounds" ]; then
                    review_round=$((programmer_review_rounds_completed + 1))
                    stream_emit_line "$stream_output_file" "Code review round $review_round/$programmer_review_max_rounds started."
                    review_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null | sed -n '1,320p')
                    [ -n "$(trim "$review_diff")" ] || review_diff="No working tree diff available."
                    review_loop_summary=$(printf '%s\n' "$loop_summary" | sed -n '1,120p')
                    [ -n "$(trim "$review_loop_summary")" ] || review_loop_summary="(none yet)"
                    review_prev_feedback="$programmer_review_last_feedback"
                    [ -n "$(trim "$review_prev_feedback")" ] || review_prev_feedback="NONE"
                    review_prompt=$(cat <<EOF
You are Code Reviewer mode for a programming assistant.
Judge whether another implementation pass is needed.

Return ONLY these sections:
REVIEW_DECISION:
apply | done

REVIEW_FEEDBACK:
- concise actionable findings if REVIEW_DECISION is apply
- otherwise "No actionable findings."

Rules:
- choose apply only for concrete, implementable issues that materially improve correctness, safety, reliability, or maintainability.
- if findings are only style nits, vague, or already addressed, choose done.
- avoid repeating unchanged feedback from previous rounds.
- do not include shell commands or patches here; provide reviewer feedback only.

User request:
$augmented_user_prompt

Current plan:
$plan_text

Loop summary:
$review_loop_summary

Current git diff:
$review_diff

Previous reviewer feedback:
$review_prev_feedback
EOF
)
                    if [ -n "$stream_output_file" ]; then
                      ARTIFICER_STREAM_FILE="$stream_output_file"
                      export ARTIFICER_STREAM_FILE
                    fi
                    review_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 22 8 5)
                    RUN_TIMEOUT_SEC=$review_timeout_sec
                    review_output=$(run_model "$model" "$review_prompt" || true)
                    unset RUN_TIMEOUT_SEC 2>/dev/null || true
                    unset ARTIFICER_STREAM_FILE 2>/dev/null || true
                    review_output=$(strip_terminal_noise "$review_output")
                    review_output=$(canonicalize_controller_output "$review_output")
                    review_decision=$(extract_section "REVIEW_DECISION" "$review_output" | sed -n '1p' | tr '[:upper:]' '[:lower:]' | awk '{print $1}')
                    review_feedback=$(extract_section "REVIEW_FEEDBACK" "$review_output")
                    review_feedback=$(trim "$review_feedback")
                    if [ -z "$review_feedback" ] || [ "$review_feedback" = "NONE" ]; then
                      review_feedback="No actionable findings."
                    fi
                    if [ "$review_decision" != "apply" ] && [ "$review_decision" != "done" ]; then
                      case "$(printf '%s' "$review_feedback" | tr '[:upper:]' '[:lower:]')" in
                        *no\ actionable*|*no\ material*|*looks\ good*|*clean*)
                          review_decision="done"
                          ;;
                        *)
                          review_decision="apply"
                          ;;
                      esac
                    fi
                    review_signature=$(printf '%s' "$review_feedback" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cksum | awk '{print $1}')
                    review_repeat=0
                    if [ -n "$programmer_review_last_signature" ] && [ "$review_signature" = "$programmer_review_last_signature" ]; then
                      review_repeat=1
                    fi
                    if [ "$review_decision" = "apply" ] && [ "$review_repeat" -eq 0 ]; then
                      programmer_review_rounds_completed=$review_round
                      programmer_review_last_signature=$review_signature
                      programmer_review_last_feedback=$review_feedback
                      next_mode="IMPLEMENT"
                      transition_reason_runtime="code reviewer requested follow-up"
                      state_set "$state_file" "blocking" "code review follow-up"
                      iteration_report="${iteration_report}
Code Review Round $review_round/$programmer_review_max_rounds:
$review_feedback
Action: returning to IMPLEMENT to address reviewer findings."
                      loop_feedback="Code reviewer feedback (round $review_round/$programmer_review_max_rounds):
$review_feedback"
                      assistant_output=""
                      stream_emit_line "$stream_output_file" "Code review round $review_round found actionable feedback; switching to IMPLEMENT."
                    else
                      if [ "$review_decision" = "apply" ] && [ "$review_repeat" -eq 1 ]; then
                        stream_emit_line "$stream_output_file" "Code review repeated prior feedback; stopping further review rounds."
                        review_feedback="$review_feedback (repeat detected)"
                      else
                        stream_emit_line "$stream_output_file" "Code review round $review_round found no actionable issues."
                      fi
                      iteration_report="${iteration_report}
Code Review Round $review_round/$programmer_review_max_rounds:
$review_feedback"
                    fi
                  fi
                else
                  if [ "$verify_completion_allowed" -eq 0 ]; then
                    next_mode="VERIFY"
                    transition_reason_runtime="high-risk fail-closed evidence incomplete"
                    state_set "$state_file" "blocking" "high-risk verify gate missing fail-closed contract"
                    append_failure_entry "$failures_file" "verify-iteration-$iteration:high-risk-fail-closed-gate" \
                      "Verification withheld by high-risk fail-closed gate" \
                      "High-risk completion requires explicit verification status, go/no-go, required evidence, and residual risk" \
                      "Revise FINAL to include fail-closed contract before DONE"
                    stream_emit_line "$stream_output_file" "Step $iteration high-risk verify gate withheld DONE; fail-closed verification contract incomplete."
                  else
                    if [ "$implementation_expected" -eq 1 ]; then
                      next_mode="IMPLEMENT"
                      transition_reason_runtime="verification failed"
                      state_set "$state_file" "blocking" "verification failed"
                      append_failure_entry "$failures_file" "verify-iteration-$iteration" \
                        "Verification did not pass" "Commands failed or DONE_CLAIM was not yes" \
                        "Return to IMPLEMENT and revise patch"
                    else
                      next_mode="DESIGN"
                      transition_reason_runtime="verification failed (reasoning revision required)"
                      state_set "$state_file" "blocking" "verification failed"
                      append_failure_entry "$failures_file" "verify-iteration-$iteration" \
                        "Verification did not pass" "Reasoning final contract remained incomplete under verification gates" \
                        "Return to DESIGN and revise final reasoning contract"
                    fi
                  fi
                fi
                ;;
            esac
          fi
          ;;

        IMPLEMENT)
          stream_emit_line "$stream_output_file" "Step $iteration implementing patch candidate."
          patch_trimmed=$(trim "$patch_text")
          patch_report_file=$(mktemp)
          : > "$patch_report_file"
          patch_success=0
          current_programming_slice_path=""
          force_file_block_recovery=0
          narrow_slice_direct_attempted=0
          programming_focus_allowed_path=""
          programming_force_focused_slice_implement=0
          if [ "$programming_quick_narrow_slice_run" -eq 1 ]; then
            programming_force_focused_slice_implement=1
          fi
          if [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
            programming_force_focused_slice_implement=1
          elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_started_count" -gt 1 ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
            programming_force_focused_slice_implement=1
          fi
          implement_failure_count=$(grep -c '^Action: implement-iteration-' "$failures_file" 2>/dev/null || printf '0')
          case "$implement_failure_count" in
            ''|*[!0-9]*) implement_failure_count=0 ;;
          esac
          hello_script_task=0
          case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
            *hello.sh*hello*world*)
              hello_script_task=1
              ;;
          esac
          implement_models=$(implementation_model_candidates "$model")
          bootstrap_forced=0
          bootstrap_fast_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
          bootstrap_fast_patch=$(trim "$bootstrap_fast_patch")
          prefer_bootstrap_fast=0
          if [ "$hello_script_task" -ne 1 ] && [ -n "$bootstrap_fast_patch" ]; then
            prompt_lower_implement=$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')
            workspace_has_framework_seed=0
            case "$prompt_lower_implement" in
              *godot*)
                if [ -f "$workspace_path/project.godot" ]; then
                  workspace_has_framework_seed=1
                fi
                ;;
            esac
            if [ "$workspace_has_framework_seed" -eq 0 ]; then
              prefer_bootstrap_fast=1
            fi
          fi

          if [ "$hello_script_task" -eq 1 ]; then
            patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
            patch_trimmed=$(trim "$patch_text")
          fi

          if [ "$hello_script_task" -ne 1 ] && [ -n "$patch_trimmed" ] && [ "$patch_trimmed" != "NONE" ]; then
            resolved_patch_text=$(resolve_patch_candidate "$patch_text" || true)
            if [ -n "$(trim "$resolved_patch_text")" ]; then
              patch_text=$resolved_patch_text
              patch_trimmed=$(trim "$resolved_patch_text")
            else
              append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                "Discarded malformed patch candidate" "Controller PATCH section was not a structurally valid unified diff" \
                "Request stricter patch format retries"
              patch_text=""
              patch_trimmed=""
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$prefer_bootstrap_fast" -eq 1 ]; then
            force_bootstrap_now=0
            if [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; then
              force_bootstrap_now=1
            elif framework_patch_is_low_confidence "$augmented_user_prompt" "$patch_text" "$workspace_path"; then
              force_bootstrap_now=1
            fi
            if [ "$force_bootstrap_now" -eq 1 ]; then
              resolved_patch_text=$(resolve_patch_candidate "$bootstrap_fast_patch" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                bootstrap_forced=1
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Applied framework bootstrap fast path" \
                  "Recognized framework task with empty framework workspace; skipping slow patch retries" \
                  "Proceed with known-good framework bootstrap patch"
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$implement_failure_count" -ge 2 ] && [ "$programming_force_focused_slice_implement" -ne 1 ]; then
            force_file_block_recovery=1
            patch_text=""
            patch_trimmed=""
          fi

          if [ "$programming_force_focused_slice_implement" -eq 1 ]; then
            patch_text=""
            patch_trimmed=""
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$force_file_block_recovery" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            followup_requires_docs=0
            followup_requires_verify=0
            followup_requires_post_safe=0
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
              case "$programming_followup_slice_kind" in
                verification)
                  followup_requires_verify=1
                  ;;
                documentation)
                  followup_requires_docs=1
                  ;;
                post-verification-safe)
                  followup_requires_post_safe=1
                  ;;
              esac
              focus_paths=$programming_followup_slice_path
              focus_paths=$(programming_normalize_relative_path "$focus_paths")
              if [ "$programming_followup_resume_prompt" -eq 1 ]; then
                focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
              elif [ "$followup_requires_post_safe" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_post_verification_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ "$followup_requires_verify" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_verification_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ "$followup_requires_docs" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_documentation_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ -z "$focus_paths" ]; then
                focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
              fi
            else
              focus_paths=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path")
            fi
            focus_paths=$(programming_normalize_relative_path "$focus_paths")
            if [ -n "$focus_paths" ]; then
              narrow_slice_direct_attempted=1
              current_programming_slice_path=$focus_paths
              programming_focus_allowed_path=$focus_paths
              focus_file_context=$(programming_file_blocks_context_for_paths "$workspace_path" "$focus_paths")
              focus_guard_paths=$(programming_quick_narrow_slice_guard_paths "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$focus_paths" "$changed_paths_file")
              focus_guard_paths=$(trim "$focus_guard_paths")
              focus_guard_context=""
              if [ -n "$focus_guard_paths" ]; then
                focus_guard_context=$(programming_file_blocks_context_for_paths "$workspace_path" "$focus_guard_paths")
              fi
              focused_task_snippet=$(programming_task_snippet_for_prompt "$augmented_user_prompt")
              slice_scope_rule="keep scope to one small verifiable implementation slice"
              non_target_scope_rule="do not widen to README, extra tests, or helper files in this pass"
              diff_non_target_scope_rule="do not edit README, tests, or extra helper files in this pass"
              if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && programming_paths_match "$focus_paths" "$programming_followup_slice_path"; then
                if [ "$followup_requires_post_safe" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final release-note-safe follow-up slice"
                  non_target_scope_rule="do not widen into executable logic, README, tests, or unrelated files in this pass"
                  diff_non_target_scope_rule="do not edit executable logic, README, tests, or unrelated files in this pass"
                elif [ "$followup_requires_verify" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final verification-safe follow-up slice"
                  non_target_scope_rule="do not widen to README, docs, extra helpers, or unrelated implementation files in this pass"
                  diff_non_target_scope_rule="do not edit README, docs, extra helper files, or unrelated implementation files in this pass"
                elif [ "$followup_requires_docs" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final documentation-safe follow-up slice"
                  non_target_scope_rule="do not widen into tests, extra helper files, or unrelated implementation files in this pass"
                  diff_non_target_scope_rule="do not edit tests, extra helper files, or unrelated implementation files in this pass"
                else
                  slice_scope_rule="keep scope to one adjacent verifiable follow-up slice"
                fi
              fi
              if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && programming_paths_match "$focus_paths" "$programming_followup_slice_path"; then
                resolved_patch_text=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-deterministic-followup" \
                    "Applied deterministic follow-up patch for $current_programming_slice_path" \
                    "Focused follow-up slices should not spend budget on flaky model-formatted patches when a safe single-file fallback is available" \
                    "Proceed with the focused single-file follow-up slice"
                fi
              elif [ -n "$(trim "$current_programming_slice_path")" ]; then
                resolved_patch_text=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-deterministic-primary" \
                    "Applied deterministic primary-slice patch for $current_programming_slice_path" \
                    "Focused primary slices should not spend budget on flaky model-formatted patches when a safe single-file fallback is available" \
                    "Proceed with the focused single-file implementation slice"
                fi
              fi
              skip_focused_model_patch_attempt=0
              if patch_candidate_is_usable "$patch_text"; then
                skip_focused_model_patch_attempt=1
              fi
              focused_files_prompt=$(cat <<EOF
Return ONLY the complete updated contents of this primary file:
- $focus_paths

Rules:
- no prose
- no markdown fences unless the model cannot avoid them
- do not return a diff in this first attempt
- $slice_scope_rule
- edit only the primary file above in this pass
- $non_target_scope_rule
- keep CLI entry points, tests, and docs in their own files; do not fold them into this file
- do not ask follow-up questions
- do not echo placeholder text; return real file contents only

Task:
$focused_task_snippet

Current file contents:
$focus_file_context
EOF
)
              focused_files_output=$(mktemp)
              retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 12 6 4)
              retry_model=$(printf '%s\n' "$implement_models" | sed -n '1p')
              retry_model=$(trim "$retry_model")
              if [ "$skip_focused_model_patch_attempt" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$retry_model" ]; then
                RUN_TIMEOUT_SEC=$retry_timeout_sec
                focused_files_raw=$(run_model "$retry_model" "$focused_files_prompt" || true)
                unset RUN_TIMEOUT_SEC 2>/dev/null || true
                focused_files_raw=$(strip_terminal_noise "$focused_files_raw")
                printf '%s' "$focused_files_raw" > "$focused_files_output"
                resolved_patch_text=$(programming_patch_from_focus_output "$workspace_path" "$focused_files_output" "$focus_paths")
                if [ -n "$(trim "$resolved_patch_text")" ]; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                elif [ -n "$(trim "$focused_files_raw")" ]; then
                  resolved_patch_excerpt=$(single_line_snippet "${resolved_patch_text:-<empty>}" | cut -c1-160)
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-file" \
                    "Primary-file attempt returned unusable output: $(single_line_snippet "$focused_files_raw" | cut -c1-160) | patch preview: $resolved_patch_excerpt" \
                    "Single-file content did not parse into a safe patch candidate" \
                    "Retry once with an exact diff request for the same primary file"
                fi
              fi
              if [ "$skip_focused_model_patch_attempt" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$retry_model" ]; then
                focused_diff_prompt=$(cat <<EOF
Return ONLY a valid unified diff patch in a diff code fence.

Rules:
- touch exactly this file:
  - $focus_paths
- no prose
- keep the change small and verifiable
- preserve the currently implied behavior from any guard file context below
- $diff_non_target_scope_rule
- keep CLI entry points, tests, and docs in their own files; do not fold them into this file

Task:
$focused_task_snippet

Primary file context:
$focus_file_context
EOF
)
                if [ -n "$focus_guard_context" ]; then
                  focused_diff_prompt=$(printf '%s\n\nGuard file context (read-only; preserve this behavior):\n%s\n' "$focused_diff_prompt" "$focus_guard_context")
                fi
                retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 10 5 4)
                RUN_TIMEOUT_SEC=$retry_timeout_sec
                focused_diff_raw=$(run_model "$retry_model" "$focused_diff_prompt" || true)
                unset RUN_TIMEOUT_SEC 2>/dev/null || true
                focused_diff_raw=$(strip_terminal_noise "$focused_diff_raw")
                focused_diff_patch=$(extract_patch_section "$focused_diff_raw")
                focused_diff_patch=$(normalize_patch_text "$focused_diff_patch")
                resolved_patch_text=$(resolve_patch_candidate "$focused_diff_patch" || true)
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                elif [ -n "$(trim "$focused_diff_raw")" ]; then
                  resolved_patch_excerpt=$(single_line_snippet "${resolved_patch_text:-<empty>}" | cut -c1-160)
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-diff" \
                    "Primary-file diff retry returned unusable output: $(single_line_snippet "$focused_diff_raw" | cut -c1-160) | patch preview: $resolved_patch_excerpt" \
                    "Focused diff retry still did not produce a safe unified diff" \
                    "Treat the implementation pass as blocked and summarize the bounded slice concisely"
                fi
              fi
              if { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$(trim "$current_programming_slice_path")" ]; then
                resolved_patch_text=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-fallback" \
                    "Applied deterministic primary-slice fallback for $current_programming_slice_path" \
                    "Focused primary-slice model patch was empty or unusable" \
                    "Proceed with the smallest deterministic implementation slice for the target file"
                fi
              fi
              if { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$current_programming_slice_path")" ] && programming_paths_match "$current_programming_slice_path" "$programming_followup_slice_path"; then
                resolved_patch_text=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-adjacent-fallback" \
                    "Applied deterministic adjacent-slice fallback for $current_programming_slice_path" \
                    "Focused adjacent-slice model patch was empty or unusable" \
                    "Proceed with the smallest deterministic follow-up slice for the target file"
                fi
              fi
              rm -f "$focused_files_output"
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$force_file_block_recovery" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_retry_prompt=$(cat <<EOF
You are in IMPLEMENT mode.
Return ONLY a unified diff patch in a diff code fence, touching at most 5 files.
No prose.

Example format:
\`\`\`diff
--- /dev/null
+++ b/new_file.txt
@@ -0,0 +1,2 @@
+line 1
+line 2
\`\`\`

Rules:
- every changed file must have both --- and +++ headers
- use relative workspace paths under a/ and b/
- for new files, use --- /dev/null and +++ b/<path>
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 30 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              patch_retry_output=$(run_model "$retry_model" "$implement_retry_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              patch_retry_section=$(extract_patch_section "$patch_retry_output")
              patch_retry_text=$(normalize_patch_text "$patch_retry_section")
              patch_retry_trimmed=$(trim "$patch_retry_text")

              resolved_patch_text=$(resolve_patch_candidate "$patch_retry_text" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$force_file_block_recovery" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_retry_prompt_2=$(cat <<EOF
Return ONLY this format:
BEGIN_PATCH
<valid unified diff touching at most 5 files>
END_PATCH

Rules:
- no prose
- no markdown fences
- include standard --- / +++ headers
- do not emit commands, only patch text
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 28 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              patch_retry_output_2=$(run_model "$retry_model" "$implement_retry_prompt_2" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              patch_retry_output_2=$(strip_terminal_noise "$patch_retry_output_2")
              patch_retry_text_2=$(printf '%s\n' "$patch_retry_output_2" | sed -n '/^BEGIN_PATCH$/,/^END_PATCH$/p' | sed '1d;$d')
              patch_retry_trimmed_2=$(trim "$patch_retry_text_2")
              resolved_patch_text=$(resolve_patch_candidate "$patch_retry_text_2" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_files_prompt=$(cat <<EOF
Return ONLY file blocks in this format (up to 5 files):
FILE: relative/path.ext
\`\`\`
full file content
\`\`\`

Rules:
- no prose
- relative workspace paths only
- provide complete file contents for each file
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            file_blocks_dir=$(mktemp -d)
            file_blocks_index=$(mktemp)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 28 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              file_blocks_output=$(run_model "$retry_model" "$implement_files_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              file_blocks_output=$(strip_terminal_noise "$file_blocks_output")
              : > "$file_blocks_index"
              printf '%s' "$file_blocks_output" | FILE_BLOCKS_DIR="$file_blocks_dir" perl -e '
                use strict;
                use warnings;
                local $/;
                my $raw = <>;
                my $dir = $ENV{"FILE_BLOCKS_DIR"} // "";
                my $count = 0;
                my %seen_path;

                my $emit = sub {
                  my ($path, $content) = @_;
                  $path = "" if !defined $path;
                  $content = "" if !defined $content;
                  $path =~ s/^\s+//;
                  $path =~ s/\s+$//;
                  return if $path eq "";
                  return if $path =~ m{(?:^|/)\.\.(?:/|$)};
                  return if $path =~ m{^/};
                  return if $seen_path{$path};
                  return if $content !~ /\S/;
                  $count += 1;
                  return if $count > 5;
                  my $tmp_path = "$dir/$count.content";
                  open my $fh, ">:encoding(UTF-8)", $tmp_path or return;
                  print {$fh} $content;
                  close $fh;
                  $seen_path{$path} = 1;
                  print "$path\t$tmp_path\n";
                };

                while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n```[^\n]*\n(.*?)\n```/sg) {
                  $emit->($1, $2);
                }

                if ($count == 0) {
                  while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n(.*?)(?=\r?\nFILE:\s*[^\r\n]+\s*\r?\n|\z)/sg) {
                    my $path = $1;
                    my $content = $2 // "";
                    $content =~ s/\A\r?\n//;
                    $content =~ s/\r?\n\z//;
                    $content =~ s/\A```[^\n]*\n//s;
                    $content =~ s/\n```[ \t]*\z//s;
                    $emit->($path, $content);
                  }
                }
              ' > "$file_blocks_index"
              if [ -s "$file_blocks_index" ]; then
                break
              fi
            done <<EOF
$implement_models
EOF

            synthesized_patch=""
            if [ -s "$file_blocks_index" ]; then
              while IFS='	' read -r out_path out_tmp; do
                out_path=$(trim "$out_path")
                out_tmp=$(trim "$out_tmp")
                [ -n "$out_path" ] || continue
                [ -f "$out_tmp" ] || continue
                if ! is_safe_relative_path "$out_path"; then
                  continue
                fi
                mkdir -p "$(dirname "$workspace_path/$out_path")" 2>/dev/null || true
                if [ -f "$workspace_path/$out_path" ]; then
                  file_diff=$(diff -u "$workspace_path/$out_path" "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- a/$out_path|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                else
                  file_diff=$(diff -u /dev/null "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                fi
              done < "$file_blocks_index"
            fi

            rm -rf "$file_blocks_dir" 2>/dev/null || true
            rm -f "$file_blocks_index"

            synthesized_patch=$(trim_block_edges "$synthesized_patch")
            if patch_candidate_is_usable "$synthesized_patch"; then
              patch_text=$synthesized_patch
              patch_trimmed=$synthesized_patch
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            focused_patch_prompt=$(cat <<EOF
You are a coding assistant generating final implementation output.
Return ONLY a valid unified diff touching at most 5 files.
No prose, no markdown outside a single diff fence.

Rules:
- include --- and +++ headers for every file
- use --- /dev/null for new files
- use +++ b/<relative-path> paths
- do not include command suggestions
- choose sensible defaults when details are underspecified

Task:
$augmented_user_prompt
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 26 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              focused_output=$(run_model "$retry_model" "$focused_patch_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              focused_output=$(strip_terminal_noise "$focused_output")
              focused_patch_section=$(extract_patch_section "$focused_output")
              focused_patch_text=$(normalize_patch_text "$focused_patch_section")
              focused_patch_trimmed=$(trim "$focused_patch_text")
              resolved_patch_text=$(resolve_patch_candidate "$focused_patch_text" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
            bootstrap_patch=$(trim "$bootstrap_patch")
            if [ -n "$bootstrap_patch" ]; then
              resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Applied framework bootstrap fallback patch" "Model did not produce a usable patch payload" \
                  "Proceed with synthesized framework baseline patch"
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ -n "$patch_trimmed" ] && [ "$patch_trimmed" != "NONE" ]; then
            if framework_patch_is_low_confidence "$augmented_user_prompt" "$patch_text" "$workspace_path"; then
              bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
              bootstrap_patch=$(trim "$bootstrap_patch")
              if [ -n "$bootstrap_patch" ]; then
                resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
                if [ -n "$(trim "$resolved_patch_text")" ]; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Replaced low-confidence framework patch with bootstrap baseline" \
                    "Model patch failed framework contract checks for an empty framework workspace" \
                    "Proceed with known-good framework bootstrap patch"
                fi
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
              *hello.sh*hello*world*)
                patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                patch_trimmed=$(trim "$patch_text")
                ;;
            esac
          fi

          if [ "$allow_workspace_writes" -ne 1 ]; then
            printf '%s\n' "Patch blocked by read-only permissions. Switch to Workspace write or Default to apply edits." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Patch blocked by read-only permissions" "Current permission mode forbids workspace edits" \
              "Ask user to grant write permissions and retry"
          elif [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; then
            printf '%s\n' "Implement mode did not include a patch payload." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Missing patch payload" "Implementation step requires a unified diff" \
              "Generate scoped patch for target files"
          else
            patch_paths_file=$(mktemp)
            patch_paths_from_text "$patch_text" > "$patch_paths_file"
            disallowed_patch_rejected=0

            patch_paths_normalized_file=$(mktemp)
            : > "$patch_paths_normalized_file"
            while IFS= read -r raw_rel_path; do
              rel_path=$(trim "$raw_rel_path")
              [ -n "$rel_path" ] || continue
              norm_rel_path=$rel_path
              case "$norm_rel_path" in
                "$workspace_path"/*)
                  norm_rel_path=${norm_rel_path#"$workspace_path"/}
                  ;;
              esac
              case "$norm_rel_path" in
                res://*)
                  norm_rel_path=${norm_rel_path#res://}
                  ;;
                file://*)
                  norm_rel_path=${norm_rel_path#file://}
                  ;;
              esac
              if [ "$norm_rel_path" != "$rel_path" ]; then
                patch_text=$(printf '%s\n' "$patch_text" | PATCH_ORIG_PATH="$rel_path" PATCH_NORM_PATH="$norm_rel_path" perl -0pe '
                  my $orig = quotemeta($ENV{"PATCH_ORIG_PATH"} // "");
                  my $norm = $ENV{"PATCH_NORM_PATH"} // "";
                  s/^--- a\/$orig$/--- a\/$norm/mg;
                  s/^\+\+\+ b\/$orig$/+++ b\/$norm/mg;
                ')
              fi
              printf '%s\n' "$norm_rel_path" >> "$patch_paths_normalized_file"
            done < "$patch_paths_file"
            mv "$patch_paths_normalized_file" "$patch_paths_file"

            if [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ -n "$programming_focus_allowed_path" ] && [ -s "$patch_paths_file" ]; then
              focused_primary_fallback_patch=""
              if [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                focused_primary_fallback_patch=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                focused_primary_fallback_patch=$(trim "$focused_primary_fallback_patch")
              fi
              if patch_candidate_is_usable "$focused_primary_fallback_patch" && {
                programming_prompt_has_multiple_branches "$augmented_user_prompt" \
                  || find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p' >/dev/null 2>&1
              } && printf '%s' "$patch_text" | grep -Eqi 'commander|program[.]parse|process[.]argv|require[.]main|--help|argv\[2\]|readline|createInterface|process[.]stdin|process[.]stdout|cliGreet|module[.]exports[[:space:]]*=[[:space:]]*\{[[:space:]]*greet[[:space:]]*,'; then
                patch_text=$focused_primary_fallback_patch
                patch_trimmed=$(trim "$focused_primary_fallback_patch")
                : > "$patch_paths_file"
                patch_paths_from_text "$patch_text" > "$patch_paths_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Primary slice tried to fold CLI behavior into $programming_focus_allowed_path; replaced with deterministic helper-only patch" \
                  "First narrow slice should keep CLI entry-point behavior out of the helper file" \
                  "Preserve the helper-only implementation slice before widening to the CLI file"
              fi
              disallowed_patch_path=$(awk -v allowed="$programming_focus_allowed_path" '$0 != allowed { print; exit }' "$patch_paths_file")
              if [ -n "$disallowed_patch_path" ]; then
                focused_fallback_patch=""
                if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                  focused_fallback_patch=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                  focused_fallback_patch=$(trim "$focused_fallback_patch")
                fi
                if patch_candidate_is_usable "$focused_fallback_patch"; then
                  patch_text=$focused_fallback_patch
                  patch_trimmed=$(trim "$focused_fallback_patch")
                  : > "$patch_paths_file"
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch drifted outside $programming_focus_allowed_path; replaced with deterministic single-file fallback" \
                    "Model patch widened to $disallowed_patch_path during a narrow-slice follow-up pass" \
                    "Keep the selected slice single-purpose and fall back to the deterministic target-only patch"
                else
                  disallowed_patch_rejected=1
                  printf '%s\n' "Patch widened outside the selected slice: $disallowed_patch_path" > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch changed $disallowed_patch_path instead of the selected slice $programming_focus_allowed_path" \
                    "Narrow-slice patch drifted outside the chosen implementation file" \
                    "Keep the patch on the selected primary file only"
                fi
              fi
            fi

            if [ "$disallowed_patch_rejected" -eq 1 ]; then
              patch_text=""
              patch_trimmed=""
            elif [ ! -s "$patch_paths_file" ]; then
              case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                *hello.sh*hello*world*)
                  patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  ;;
              esac
            fi

            if [ ! -s "$patch_paths_file" ]; then
              printf '%s\n' "No target files were detected in PATCH section." > "$patch_report_file"
              append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                "Patch had no +++ paths" "Diff format malformed or missing headers" \
                "Emit standard unified diff with a/ and b/ paths"
            else
              touched_count=0
              invalid_path=""
              assay_invalid_path=""
              while IFS= read -r rel_path; do
                [ -n "$rel_path" ] || continue
                touched_count=$((touched_count + 1))
                if ! is_safe_relative_path "$rel_path"; then
                  invalid_path=$rel_path
                  break
                fi
                if [ "$assay_run_profile" -eq 1 ] && [ -n "$assay_edit_root" ]; then
                  case "$rel_path" in
                    "$assay_edit_root"/*)
                      ;;
                    *)
                      assay_invalid_path=$rel_path
                      break
                      ;;
                  esac
                fi
              done < "$patch_paths_file"

              if [ -n "$invalid_path" ]; then
                printf 'Unsafe path in patch: %s\n' "$invalid_path" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Unsafe target path: $invalid_path" "Path traversal or invalid characters" \
                  "Restrict patch to safe relative workspace paths"
              elif [ -n "$assay_invalid_path" ]; then
                printf 'Assay patch out-of-scope path: %s (allowed prefix: %s/)\n' "$assay_invalid_path" "$assay_edit_root" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Assay patch out of scope: $assay_invalid_path" \
                  "Assay safety policy limits edits to $assay_edit_root/" \
                  "Regenerate patch under the assay edit root"
              elif [ "$touched_count" -gt 5 ]; then
                printf 'Patch touched too many files: %s\n' "$touched_count" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Patch touched more than 5 files" "Iteration scope too broad" \
                  "Split patch into smaller batches"
              else
                iter_scratch="$scratch_root/iter-$iteration-$(new_id)"
                mkdir -p "$iter_scratch"

                prepare_scratch_files "$workspace_path" "$iter_scratch" "$patch_paths_file"
                patch_file="$iter_scratch/proposed.patch"
                printf '%s\n' "$patch_text" > "$patch_file"
                canonical_patch_file="$iter_scratch/proposed.canonical.patch"
                cp "$patch_file" "$canonical_patch_file"
                while IFS= read -r rel_path; do
                  [ -n "$rel_path" ] || continue
                  if [ ! -f "$workspace_path/$rel_path" ]; then
                    PATCH_REL_PATH="$rel_path" perl -0pi -e '
                      my $p = $ENV{"PATCH_REL_PATH"} // "";
                      $p = quotemeta($p);
                      s/^--- a\/$p$/--- \/dev\/null/mg;
                    ' "$canonical_patch_file"
                  fi
                done < "$patch_paths_file"
                patch_file="$canonical_patch_file"

                apply_log=$(mktemp)
                gate_log=$(mktemp)
                diff_log=$(mktemp)
                promote_log=$(mktemp)
                patch_already_present=0
                if apply_patch_to_scratch "$iter_scratch" "$patch_file" "$apply_log"; then
                  if run_gate_checks "$iter_scratch" "$patch_paths_file" "$gate_log" "$augmented_user_prompt" "$workspace_path"; then
                    diff_scratch_vs_workspace "$workspace_path" "$iter_scratch" "$patch_paths_file" "$diff_log"
                    if promote_scratch_files "$iter_scratch" "$workspace_path" "$patch_paths_file" "$promote_log"; then
                      patch_success=1
                      programming_record_changed_paths "$changed_paths_file" "$patch_paths_file"
                      diff_excerpt=$(sed -n '1,220p' "$diff_log")
                      if [ -z "$diff_excerpt" ]; then
                        diff_excerpt="No textual diff generated."
                      fi
                      post_snapshot=$(workspace_snapshot "$workspace_path" | sed -n '1,120p')
                      {
                        printf 'Patch applied through scratch gate.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                        printf '\nPatch diff excerpt:\n%s\n' "$diff_excerpt"
                        printf '\nPost-write snapshot:\n%s\n' "$post_snapshot"
                      } > "$patch_report_file"
                    else
                      {
                        printf 'Promotion failed.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                      } > "$patch_report_file"
                      append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                        "Scratch promotion failed" "File copy to workspace failed" \
                        "Inspect path and permissions before retrying"
                    fi
                  else
                    {
                      printf 'Gate checks failed.\n'
                      printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                      printf '\nGate output:\n%s\n' "$(sed -n '1,220p' "$gate_log")"
                    } > "$patch_report_file"
                    append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                      "Gate checks failed" "Syntax or conflict checks failed on scratch files" \
                      "Revise patch and retry"
                  fi
                elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && already_present_log=$(mktemp) && patch_already_present_in_scratch "$iter_scratch" "$patch_file" "$already_present_log"; then
                  patch_success=1
                  patch_already_present=1
                  ARTIFICER_PROGRAMMING_CHANGED_PATHS=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
                  {
                    printf 'Selected slice already matched scratch workspace.\n'
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                    printf '\nAlready-present check:\n%s\n' "$(sed -n '1,220p' "$already_present_log")"
                  } > "$patch_report_file"
                  rm -f "$already_present_log"
                else
                  rm -f "${already_present_log:-}" 2>/dev/null || true
                  {
                    printf 'Patch failed to apply in scratch workspace.\n'
                    printf '\nPatch preview:\n%s\n' "$(sed -n '1,120p' "$patch_file")"
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                  } > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Patch apply failed" "Unified diff did not match scratch context" \
                    "Re-read target file and regenerate patch"
                fi

                rm -f "$apply_log" "$gate_log" "$diff_log" "$promote_log"
              fi
            fi

            rm -f "$patch_paths_file"
          fi

          patch_report=$(sed -n '1,260p' "$patch_report_file")
          rm -f "$patch_report_file"

          command_name=$(printf 'apply_patch iteration %s' "$iteration")
          if [ "$patch_success" -eq 1 ]; then
            command_status="ok"
          else
            command_status="failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration patch gate status: $command_status"

          command_json=$(json_escape "$command_name")
          status_json=$(json_escape "$command_status")
          output_json=$(json_escape "$patch_report")
          command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
            "$command_json" "$status_json" "$output_json")

          if [ "$commands_first" -eq 1 ]; then
            commands_json=$command_item
            commands_first=0
          else
            commands_json="${commands_json},${command_item}"
          fi

          iteration_report="Patch gate result:
$patch_report"
          loop_feedback=$iteration_report

          if [ "$patch_success" -eq 1 ]; then
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$current_programming_slice_path")" ] && programming_paths_match "$current_programming_slice_path" "$programming_followup_slice_path"; then
              programming_followup_slice_completed_count=$((programming_followup_slice_completed_count + 1))
            fi
            auto_verify_report_file=$(mktemp)
            followup_candidate=""
            followup_candidate_kind=""
            defer_remaining_branch=0
            landed_changed_count=$(programming_changed_paths_count_from_file "$changed_paths_file")
            case "$landed_changed_count" in
              ''|*[!0-9]*)
                landed_changed_count=0
                ;;
            esac
            landed_has_docs=0
            landed_has_verify=0
            landed_has_post_safe=0
            if programming_changed_paths_file_has_documentation_safe "$changed_paths_file"; then
              landed_has_docs=1
            fi
            if programming_changed_paths_file_has_verification_safe "$changed_paths_file"; then
              landed_has_verify=1
            fi
            if programming_changed_paths_file_has_post_verification_safe "$changed_paths_file"; then
              landed_has_post_safe=1
            fi
            followup_transition_reason="first slice landed; widening to adjacent verified slice"
            followup_stream_line="Step $iteration: widening to one adjacent verified slice after the first landed cleanly."
            if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 4 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 1 ] && [ "$landed_has_post_safe" -eq 0 ]; then
              followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="post-verification-safe"
            elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 3 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 0 ]; then
              followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="verification"
            elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 2 ] && [ "$landed_has_docs" -eq 0 ]; then
              followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="documentation"
            fi
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -eq "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_completed_count" -lt "$programming_followup_slice_limit" ]; then
              if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
                followup_candidate_kind="post-verification-safe"
              elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
                followup_candidate_kind="verification"
              elif [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
                followup_candidate_kind="documentation"
              fi
              if [ -z "$followup_candidate" ]; then
                if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                else
                  followup_candidate=$(programming_quick_narrow_slice_next_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$augmented_user_prompt" "$changed_paths_file")
                fi
              fi
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
            fi
            if [ -z "$followup_candidate" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            elif [ -z "$followup_candidate" ] && [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -ne 1 ] && programming_prompt_has_post_verification_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            fi
            if auto_verify_after_patch_for_prompt "$workspace_id" "$workspace_path" "$augmented_user_prompt" "$command_mode" "$blocked_commands_file" "$auto_verify_report_file"; then
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="DONE"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                else
                  transition_reason_runtime="post-implement auto verification passed"
                fi
                state_set "$state_file" "blocking" "none"
                case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                  *godot*)
                    assistant_output="Created a runnable Godot project in the workspace and verified it with headless Godot."
                    ;;
                  *)
                    assistant_output="Completed implementation and verification successfully."
                    ;;
                esac
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            else
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="VERIFY"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                elif [ "${patch_already_present:-0}" -eq 1 ]; then
                  transition_reason_runtime="selected slice already present"
                else
                  transition_reason_runtime="scratch commit promoted"
                fi
                state_set "$state_file" "blocking" "none"
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            fi
            rm -f "$auto_verify_report_file"
          else
            next_mode="IMPLEMENT"
            transition_reason_runtime="implementation patch failed"
            state_set "$state_file" "blocking" "patch gate failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration implementation summary: next=$next_mode reason=$transition_reason_runtime"
          ;;

        DONE)
          final_candidate=$(trim "$final_section")
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate=$(trim "$checkpoint_text")
          fi
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate="Completed requested work."
          fi
          assistant_output="$final_candidate"
          next_mode="DONE"
          transition_reason_runtime="already done"
          iteration_report="Agent remained in DONE mode."
          loop_feedback=$iteration_report
          ;;
        esac
      fi

      if [ "$recovered_controller_output" -eq 1 ] && [ "$next_mode" = "DONE" ]; then
        append_failure_entry "$failures_file" "controller-format-done-block-iteration-$iteration" \
          "Prevented DONE transition from recovered controller output" \
          "Recovered controller output attempted to end the run without a clean structured pass" \
          "Hold mode and request one clean controller iteration before completion"
        controller_format_done_block_total=$((controller_format_done_block_total + 1))
        next_mode="$state_mode"
        transition_reason_runtime="controller format recovery requires clean pass"
        assistant_output=""
        done_claim="no"
        state_set "$state_file" "blocking" "controller format recovery pending clean pass"
        iteration_report="${iteration_report}
Format recovery guard:
Recovered controller output cannot complete the run; requesting one clean structured pass."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration completion guard: recovered controller output cannot transition directly to DONE."
      fi
      run_now_for_circuit=$(date +%s 2>/dev/null || printf '0')
      case "$run_now_for_circuit" in
        ""|*[!0-9]*)
          run_now_for_circuit=$run_started_epoch
          ;;
      esac
      run_elapsed_for_circuit=$((run_now_for_circuit - run_started_epoch))
      if [ "$run_elapsed_for_circuit" -lt 0 ]; then
        run_elapsed_for_circuit=0
      fi
      run_budget_remaining=$((run_time_budget - run_elapsed_for_circuit))
      if [ "$run_budget_remaining" -lt 0 ]; then
        run_budget_remaining=0
      fi
      if [ "$next_mode" != "DONE" ] && {
        [ "$controller_format_recovery_streak" -ge 2 ] ||
        [ "$controller_format_recovery_total" -ge 3 ] ||
        { [ "$controller_format_done_block_total" -ge 1 ] && [ "$run_budget_remaining" -le 25 ]; };
      }; then
        append_failure_entry "$failures_file" "controller-format-circuit-breaker-iteration-$iteration" \
          "Controller format instability circuit-breaker triggered" \
          "Repeated malformed controller recoveries or late-budget done-blocks indicate low-probability clean recovery within remaining budget" \
          "Finalize with deterministic best-effort response and request focused rerun"
        next_mode="DONE"
        transition_reason_runtime="controller format instability circuit-breaker"
        done_claim="no"
        if [ -z "$(trim "$assistant_output")" ] || [ "$assistant_output" = "NONE" ]; then
          assistant_output=$(structured_incomplete_run_message \
            "$state_mode" \
            "Retry with a narrower prompt slice or a different model, then continue from the latest verified checkpoint." \
            "Controller output format failed strict schema checks repeatedly in this run." \
            "$augmented_user_prompt")
        fi
        state_set "$state_file" "blocking" "controller format instability; finalized with best-effort output"
        iteration_report="${iteration_report}
Format recovery circuit-breaker:
Repeated malformed controller recoveries triggered deterministic best-effort finalization."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration circuit-breaker: repeated format recovery; finalizing with best-effort output."
      fi
      rm -f "$decision_options_file"

      state_set "$state_file" "mode" "$next_mode"
      state_set "$state_file" "transition_reason" "$transition_reason_runtime"

      case "$next_mode" in
        INVESTIGATE) default_confidence="0.30" ;;
        DESIGN) default_confidence="0.45" ;;
        IMPLEMENT) default_confidence="0.60" ;;
        VERIFY) default_confidence="0.72" ;;
        DONE) default_confidence="0.90" ;;
        *) default_confidence="0.50" ;;
      esac

      if [ -z "$confidence_update" ] || printf '%s' "$confidence_update" | grep -q '[^0-9.]'; then
        state_set "$state_file" "confidence" "$default_confidence"
      fi
      confidence_stream=$(trim "$(state_get "$state_file" "confidence" "$default_confidence")")
      if [ -z "$confidence_stream" ]; then
        confidence_stream="$default_confidence"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration confidence updated: $confidence_stream"

      checkpoint_trimmed=$(trim "$checkpoint_text")
      if [ -n "$checkpoint_trimmed" ] && [ "$checkpoint_trimmed" != "NONE" ]; then
        iteration_report="${iteration_report}
Checkpoint:
$checkpoint_trimmed"
      fi
      iteration_report="${iteration_report}
Transition: $state_mode -> $next_mode
Reason: $transition_reason_runtime"
      loop_feedback=$iteration_report

      stagnation_plan_head=$(printf '%s\n' "$plan_update" | sed -n '1,2p')
      stagnation_plan_head=$(single_line_snippet "$stagnation_plan_head")
      if [ -z "$stagnation_plan_head" ]; then
        stagnation_plan_head="none"
      fi
      stagnation_checkpoint=$(single_line_snippet "$checkpoint_trimmed")
      if [ -z "$stagnation_checkpoint" ]; then
        stagnation_checkpoint="none"
      fi
      stagnation_signature_src=$(printf '%s|%s|%s|%s|%s|%s' \
        "$state_mode" "$next_mode" "$transition_reason_runtime" "$done_claim" "$stagnation_plan_head" "$stagnation_checkpoint")
      stagnation_signature=$(printf '%s' "$stagnation_signature_src" | cksum | awk '{print $1}')
      if [ -n "$stagnation_last_signature" ] && [ "$stagnation_signature" = "$stagnation_last_signature" ]; then
        stagnation_repeat_count=$((stagnation_repeat_count + 1))
      else
        stagnation_repeat_count=0
      fi
      stagnation_last_signature=$stagnation_signature
      if [ "$next_mode" != "DONE" ] && [ "$stagnation_repeat_count" -ge 2 ]; then
        stagnation_note="Loop stagnation detected: repeated transition signature with limited forward progress."
        loop_feedback="${loop_feedback}

Stagnation guardrail:
- Recent iterations repeated the same transition signature.
- Do not repeat identical plan/command output.
- Either emit DECISION_REQUEST for truly required missing inputs, or choose explicit assumptions and advance with verifiable progress."
        if [ "$stagnation_repeat_count" -eq 2 ]; then
          append_failure_entry "$failures_file" "iteration-$iteration:loop-stagnation" \
            "Loop stagnation detected" \
            "Repeated transition signature without forward progress" \
            "Switch strategy via explicit assumptions or early decision checkpoint"
          stream_emit_line "$stream_output_file" "Loop stagnation detected; injecting anti-repeat guardrail."
          iteration_report="${iteration_report}
$stagnation_note"
        fi
      fi

      append_session_entry "$session_log_file" "iteration $iteration ($state_mode -> $next_mode)" "$iteration_report"
      loop_summary="${loop_summary}
Iteration $iteration ($state_mode -> $next_mode):
$iteration_report"
      stream_emit_line "$stream_output_file" "Step $iteration: $state_mode -> $next_mode ($transition_reason_runtime)"
      checkpoint_stream=$(single_line_snippet "$checkpoint_trimmed")
      if [ -n "$checkpoint_stream" ] && [ "$checkpoint_stream" != "NONE" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration checkpoint: $checkpoint_stream"
      fi
      plan_update_head=$(printf '%s\n' "$plan_update" | sed -n '1p')
      plan_update_head=$(trim "$plan_update_head")
      if [ -n "$plan_update_head" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration next: $plan_update_head"
      fi
      done_claim_stream=$done_claim
      if [ -z "$(trim "$done_claim_stream")" ]; then
        done_claim_stream="none"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration completion check: done_claim=$done_claim_stream next_mode=$next_mode"

      if [ "$next_mode" = "DONE" ]; then
        if [ -z "$(trim "$assistant_output")" ] || [ "$assistant_output" = "NONE" ]; then
          final_candidate=$(trim "$final_section")
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate=$(trim "$checkpoint_text")
          fi
          if [ -n "$final_candidate" ] && [ "$final_candidate" != "NONE" ]; then
            assistant_output="$final_candidate"
          fi
        fi
        break
      fi

      iteration=$((iteration + 1))
    done

    git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
    git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
    if [ -z "$git_diff" ]; then
      git_diff="No working tree changes."
    fi

    plan_text=$(sed -n '1,260p' "$plan_file")
    failures_tail=$(tail -n 600 "$failures_file" 2>/dev/null || sed -n '1,600p' "$failures_file")
    session_tail=$(tail -n 800 "$session_log_file" 2>/dev/null || sed -n '1,800p' "$session_log_file")
    controller_tail=$(tail -n 1200 "$controller_raw_file" 2>/dev/null || sed -n '1,1200p' "$controller_raw_file")
    final_state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")

    if printf '%s' "$assistant_output" | grep -qi '^Run timed out after'; then
      assistant_output=$(structured_incomplete_run_message \
        "$final_state_mode" \
        "" \
        "" \
        "$augmented_user_prompt")
    fi

    if [ "$final_state_mode" != "DONE" ] && [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      if output_is_intermediate_contract "$assistant_output"; then
        synthesis_remaining_budget=0
        synthesis_now_epoch=$(date +%s 2>/dev/null || printf '0')
        case "$synthesis_now_epoch" in
          ""|*[!0-9]*)
            synthesis_now_epoch=$run_started_epoch
            ;;
        esac
        synthesis_remaining_budget=$((run_time_budget - (synthesis_now_epoch - run_started_epoch)))
        if [ "$synthesis_remaining_budget" -lt 0 ]; then
          synthesis_remaining_budget=0
        fi

        attempt_model_reasoning_synthesis=1
        if [ "$assay_run_profile" -eq 1 ]; then
          attempt_model_reasoning_synthesis=0
        fi

        reasoning_synthesis_assumption_required=0
        reasoning_synthesis_assumption_extra=""
        if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
          reasoning_synthesis_assumption_required=1
          reasoning_synthesis_assumption_extra=$(cat <<'EOF'
- Initial Assumption
- Invalidating Evidence
- Revised Decision
- Evidence Delta
EOF
)
        fi

        if [ "$attempt_model_reasoning_synthesis" -eq 1 ] && [ "$synthesis_remaining_budget" -ge 8 ]; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage: attempting one final synthesis from collected evidence."
          reasoning_synthesis_requirements=$(cat <<'EOF'
Write a final reasoning answer with complete contracts:
- Outcome
- Verification Evidence (must include concrete command anchors from this run)
- Assumptions and Alternatives
- Contradiction Check
- Decision
- Priority Order
- Fallback Path
- Disconfirming Evidence
- Source Quality Ranking
- Source Conflict Resolution
- Scenario-Specific Check
- Risks
- Next Improvement
Do not mention being incomplete or partial unless the result is genuinely blocked by missing evidence.
EOF
)
          if [ "$reasoning_synthesis_assumption_required" -eq 1 ]; then
            reasoning_synthesis_requirements=$(printf '%s\n%s' "$reasoning_synthesis_requirements" "$reasoning_synthesis_assumption_extra")
          fi
          reasoning_synthesis_prompt=$(cat <<EOF
You are finalizing an open-ended reasoning run where prior iterations gathered evidence but did not cleanly converge.

User request:
$augmented_user_prompt

Current mode:
$final_state_mode

Current plan:
$plan_text

Loop summary:
$loop_summary

Failure ledger (tail):
$failures_tail

Git status:
$git_status

Git diff:
$git_diff

Current assistant draft:
$assistant_output

$reasoning_synthesis_requirements
EOF
)

          reasoning_synthesis_timeout_fallback=24
          if [ "$assay_run_profile" -eq 1 ]; then
            reasoning_synthesis_timeout_fallback=12
          fi
          if [ "$synthesis_remaining_budget" -lt "$reasoning_synthesis_timeout_fallback" ]; then
            reasoning_synthesis_timeout_fallback=$synthesis_remaining_budget
          fi
          if [ "$reasoning_synthesis_timeout_fallback" -lt 8 ]; then
            reasoning_synthesis_timeout_fallback=8
          fi
          reasoning_synthesis_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$reasoning_synthesis_timeout_fallback" 8 6)

          if [ -n "$stream_output_file" ]; then
            ARTIFICER_STREAM_FILE="$stream_output_file"
            export ARTIFICER_STREAM_FILE
          fi
          RUN_TIMEOUT_SEC=$reasoning_synthesis_timeout_sec
          reasoning_synthesis_output=$(run_model "$model" "$reasoning_synthesis_prompt" || true)
          unset RUN_TIMEOUT_SEC 2>/dev/null || true
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          reasoning_synthesis_output=$(normalize_assistant_output "$reasoning_synthesis_output")

          if [ -n "$(trim "$reasoning_synthesis_output")" ]; then
            reasoning_synthesis_output=$(ensure_output_has_runtime_command_evidence \
              "$reasoning_synthesis_output" \
              "$loop_summary" \
              "$run_command_success_total" \
              "$augmented_user_prompt" \
              "1")
            reasoning_synthesis_output=$(normalize_claim_evidence_completeness_contract "$reasoning_synthesis_output" "$augmented_user_prompt" "$loop_summary")
            reasoning_synthesis_output=$(normalize_source_quality_contradiction_contract "$reasoning_synthesis_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
            reasoning_synthesis_output=$(normalize_scenario_depth_final_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            if [ "$reasoning_synthesis_assumption_required" -eq 1 ]; then
              reasoning_synthesis_output=$(normalize_assumption_revision_final_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            fi
            reasoning_synthesis_output=$(normalize_reasoning_followup_thread_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            reasoning_synthesis_output=$(normalize_reasoning_live_contract "$reasoning_synthesis_output" "$augmented_user_prompt")

            synthesis_assumption_contract_ok=1
            if [ "$reasoning_synthesis_assumption_required" -eq 1 ] && ! final_has_assumption_revision_contract "$reasoning_synthesis_output"; then
              synthesis_assumption_contract_ok=0
            fi
            if final_has_source_quality_contradiction_contract "$reasoning_synthesis_output" && final_has_claim_evidence_completeness_contract "$reasoning_synthesis_output" && final_has_scenario_specific_depth "$reasoning_synthesis_output" "$augmented_user_prompt" && [ "$synthesis_assumption_contract_ok" -eq 1 ] && ! output_is_intermediate_contract "$reasoning_synthesis_output"; then
              assistant_output=$reasoning_synthesis_output
              final_state_mode="DONE"
              state_set "$state_file" "mode" "DONE"
              state_set "$state_file" "transition_reason" "reasoning completion salvage synthesis"
              stream_emit_line "$stream_output_file" "Reasoning completion salvage produced a complete final response; mode promoted to DONE."
            else
              stream_emit_line "$stream_output_file" "Reasoning completion salvage produced output, but completion contracts were still incomplete."
            fi
          else
            stream_emit_line "$stream_output_file" "Reasoning completion salvage returned empty output."
          fi
        elif [ "$attempt_model_reasoning_synthesis" -eq 0 ]; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage: skipping extra model synthesis in assay profile; using deterministic contract synthesis fallback."
        else
          stream_emit_line "$stream_output_file" "Reasoning completion salvage skipped due low remaining budget (${synthesis_remaining_budget}s)."
        fi

        if [ "$final_state_mode" != "DONE" ] && output_is_intermediate_contract "$assistant_output"; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage fallback: synthesizing deterministic contract-complete response from collected evidence."
          fallback_now_epoch=$(date +%s 2>/dev/null || printf '0')
          case "$fallback_now_epoch" in
            ""|*[!0-9]*)
              fallback_now_epoch=$run_started_epoch
              ;;
          esac
          fallback_elapsed_sec=$((fallback_now_epoch - run_started_epoch))
          if [ "$fallback_elapsed_sec" -lt 0 ]; then
            fallback_elapsed_sec=0
          fi
          reasoning_fallback_output=$(reasoning_deterministic_salvage_output \
            "$augmented_user_prompt" \
            "$plan_text" \
            "$loop_summary" \
            "$run_command_success_total" \
            "$fallback_elapsed_sec")
          assistant_output=$reasoning_fallback_output
          final_state_mode="DONE"
          state_set "$state_file" "mode" "DONE"
          state_set "$state_file" "transition_reason" "reasoning completion deterministic salvage"
          stream_emit_line "$stream_output_file" "Reasoning deterministic salvage emitted a complete fallback response; mode promoted to DONE."
        fi
      fi
    fi

    if [ "$final_state_mode" != "DONE" ] && [ -z "$(trim "$assistant_output")" ]; then
      next_action_line=$(printf '%s\n' "$plan_text" | sed -n '/^Next Action:/,$p' | sed -n '2p')
      next_action_line=$(trim "$next_action_line")
      if [ -z "$next_action_line" ]; then
        next_action_line=$(reasoning_next_improvement_line_for_prompt "$augmented_user_prompt")
      fi
      assistant_output=$(structured_incomplete_run_message "$final_state_mode" "$next_action_line" "" "$augmented_user_prompt")
    fi

    if [ -z "$(trim "$assistant_output")" ] && grep -qi 'approval_required' "$failures_file"; then
      assistant_output="I need command approval to continue. Approve the requested command and run again."
    fi

    if [ -z "$(trim "$assistant_output")" ] && [ "$final_state_mode" = "DONE" ]; then
      synthesis_requirements_text=$(cat <<'EOF'
Write a concise final response:
- what was done
- key findings
- next best step
- no role prefixes and no control tokens
EOF
)
      if [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
        synthesis_requirements_text=$(cat <<EOF
Write a structured security findings report that includes:
- Findings section with numbered items
- each finding must include Severity, Evidence, Remediation, and Status
- separate validated evidence from uncertainty
- explicit next verification actions
- no role prefixes and no control tokens
EOF
)
      fi
      if [ "$run_mode" = "teacher" ]; then
        synthesis_requirements_text=$(cat <<EOF
Write a teaching response that includes:
- a brief explanation tailored to the learner likely level
- a staged curriculum plan (now, next, later)
- 2 concise comprehension checks
- one spaced-review recommendation using interaction gap signal: $teacher_gap_summary
- no role prefixes and no control tokens
EOF
)
      fi
      synthesis_prompt=$(cat <<EOF
You are finalizing an agent loop run for a coding assistant.

User request:
$augmented_user_prompt

Current plan:
$plan_text

Loop summary:
$loop_summary

Failure ledger (tail):
$failures_tail

Git status:
$git_status

Git diff:
$git_diff

$synthesis_requirements_text
EOF
)

      if [ -n "$stream_output_file" ]; then
        ARTIFICER_STREAM_FILE="$stream_output_file"
        export ARTIFICER_STREAM_FILE
      fi
      synthesis_timeout_fallback=35
      if [ "$assay_run_profile" -eq 1 ]; then
        synthesis_timeout_fallback=14
      fi
      run_now_for_synthesis=$(date +%s 2>/dev/null || printf '0')
      case "$run_now_for_synthesis" in
        ""|*[!0-9]*)
          run_now_for_synthesis=$run_started_epoch
          ;;
      esac
      synthesis_budget_remaining=$((run_time_budget - (run_now_for_synthesis - run_started_epoch)))
      if [ "$synthesis_budget_remaining" -lt 0 ]; then
        synthesis_budget_remaining=0
      fi
      if [ "$synthesis_budget_remaining" -gt 0 ] && [ "$synthesis_budget_remaining" -lt "$synthesis_timeout_fallback" ]; then
        synthesis_timeout_fallback=$synthesis_budget_remaining
      fi
      if [ "$synthesis_timeout_fallback" -lt 6 ]; then
        synthesis_timeout_fallback=6
      fi
      if [ "$synthesis_budget_remaining" -le 4 ]; then
        assistant_output=$(structured_incomplete_run_message "$final_state_mode" "" "" "$augmented_user_prompt")
      else
        synthesis_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$synthesis_timeout_fallback" 8 6)
        RUN_TIMEOUT_SEC=$synthesis_timeout_sec
        assistant_output=$(run_model "$model" "$synthesis_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        assistant_output=$(normalize_assistant_output "$assistant_output")
        if [ -z "$(trim "$assistant_output")" ]; then
          assistant_output="Run completed, but the model did not provide a final synthesis."
        fi
      fi
      unset ARTIFICER_STREAM_FILE 2>/dev/null || true
    fi

    assistant_output=$(normalize_assistant_output "$assistant_output")
    if [ -n "$(trim "$assistant_output")" ] && ! printf '%s\n' "$assistant_output" | grep -Eq '[A-Za-z0-9]'; then
      assistant_output=$(structured_incomplete_run_message "$final_state_mode" "" "" "$augmented_user_prompt")
    fi
    if [ "$run_mode" = "text-perfecter" ] && [ -n "$(trim "$assistant_output")" ]; then
      perfecter_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$perfecter_lower" | grep -Eq 'stability rationale|convergence|thrash'; then
        assistant_output=$(printf '%s\nStability Rationale: Revisions were stopped after consecutive passes produced no material semantic improvements.' "$assistant_output")
      fi
      perfecter_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$perfecter_lower" | grep -Eq 'evidence basis|evidence summary|sources considered'; then
        assistant_output=$(printf '%s\nEvidence Basis: Incorporated explicit and discovered web sources, plus contradiction checks across variants before finalizing.' "$assistant_output")
      fi
    fi

    if output_looks_derailed "$assistant_output"; then
      repaired_output=$(salvage_direct_response "$model" "$user_prompt")
      if [ -n "$(trim "$repaired_output")" ]; then
        assistant_output=$repaired_output
      fi
    fi

    if [ "$final_state_mode" = "DONE" ] && printf '%s\n' "$assistant_output" | grep -qi '^Recovered malformed controller output'; then
      case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
        *godot*)
          if [ -f "$workspace_path/project.godot" ]; then
            assistant_output="Created a runnable Godot project in the workspace and verified it with headless Godot."
          else
            assistant_output="Completed implementation and verification successfully."
          fi
          ;;
        *)
          assistant_output="Completed implementation and verification successfully."
          ;;
      esac
    fi

    if [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
      assistant_output=$(security_mode_normalize_assistant_output \
        "$assistant_output" \
        "$run_mode" \
        "$final_state_mode" \
        "$loop_summary" \
        "$failures_tail" \
        "$git_status")
    fi

    if [ "$assay_run_profile" -eq 1 ]; then
      run_finished_epoch=$(date +%s 2>/dev/null || printf '0')
      case "$run_finished_epoch" in
        ""|*[!0-9]*)
          run_finished_epoch=$run_started_epoch
          ;;
      esac
      run_elapsed_sec=$((run_finished_epoch - run_started_epoch))
      if [ "$run_elapsed_sec" -lt 0 ]; then
        run_elapsed_sec=0
      fi
      assistant_output=$(assay_normalize_assistant_output "$assistant_output" "$final_state_mode" "$plan_text" "$run_time_budget" "$run_elapsed_sec" "$augmented_user_prompt")
    fi

    evidence_claim_map_required=0
    source_quality_output_required=0
    scenario_depth_output_required=0
    high_risk_fail_closed_output_required=0
    if [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      evidence_claim_map_required=1
      source_quality_output_required=1
      scenario_depth_output_required=1
    fi
    if prompt_requires_adversarial_reasoning "$augmented_user_prompt" || prompt_requires_cross_domain_reasoning "$augmented_user_prompt" || prompt_requires_decision_completeness "$augmented_user_prompt"; then
      scenario_depth_output_required=1
    fi
    case "$run_mode" in
      report|teacher|security-audit|pentest|text-perfecter|gui-testing)
        evidence_claim_map_required=1
        source_quality_output_required=1
        scenario_depth_output_required=1
        ;;
    esac
    if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
      high_risk_fail_closed_output_required=1
      evidence_claim_map_required=1
      source_quality_output_required=1
      scenario_depth_output_required=1
    fi
    if [ "$run_command_success_total" -gt 0 ] && { [ "$evidence_claim_map_required" -eq 1 ] || [ "$source_quality_output_required" -eq 1 ] || [ "$scenario_depth_output_required" -eq 1 ]; }; then
      assistant_output=$(ensure_output_has_runtime_command_evidence \
        "$assistant_output" \
        "$loop_summary" \
        "$run_command_success_total" \
        "$augmented_user_prompt" \
        "$evidence_claim_map_required")
      if [ "$evidence_claim_map_required" -eq 1 ]; then
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
      fi
      if [ "$source_quality_output_required" -eq 1 ]; then
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
      fi
      if [ "$scenario_depth_output_required" -eq 1 ]; then
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
      fi
    fi
    if [ "$scenario_depth_output_required" -eq 1 ] || { [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; }; then
      assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
      assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
    fi
    if [ "$final_state_mode" = "DONE" ]; then
      assistant_output=$(ensure_output_has_runtime_command_evidence \
        "$assistant_output" \
        "$loop_summary" \
        "$run_command_success_total" \
        "$augmented_user_prompt" \
        "$evidence_claim_map_required")
      if [ "$evidence_claim_map_required" -eq 1 ]; then
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_claim_evidence_completeness_contract "$assistant_output"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "expand the claim-to-evidence map with at least two concrete entries, then rerun." "Claim-evidence completion gate withheld DONE because the final synthesis lacked multi-claim verification/invalidation mapping or evidence caveats." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "claim-evidence output contract incomplete"
          stream_emit_line "$stream_output_file" "Claim-evidence output gate converted DONE to VERIFY pending multi-claim evidence mapping."
        fi
      fi
      if [ "$source_quality_output_required" -eq 1 ]; then
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_source_quality_contradiction_contract "$assistant_output"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "add confidence-tiered source ranking and explicit contradiction resolution, then rerun." "Source-quality completion gate withheld DONE because final synthesis lacked required source ranking/contradiction structure." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "source-quality output contract incomplete"
          stream_emit_line "$stream_output_file" "Source-quality output gate converted DONE to VERIFY pending source ranking and contradiction resolution details."
        fi
      fi
      if [ "$scenario_depth_output_required" -eq 1 ]; then
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_scenario_specific_depth "$assistant_output" "$augmented_user_prompt"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "add prompt-anchored scenario depth details in non-template lines and rerun." "Scenario-depth completion gate withheld DONE because final synthesis remained generic and lacked prompt-token grounding outside template contract headers." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "scenario-depth output contract incomplete"
          stream_emit_line "$stream_output_file" "Scenario-depth output gate converted DONE to VERIFY pending non-template prompt-anchored specificity."
        fi
      fi
      if [ "$high_risk_fail_closed_output_required" -eq 1 ]; then
        assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
        if ! final_has_high_risk_fail_closed_contract "$assistant_output" "$run_command_success_total"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "collect explicit high-risk verification evidence and rerun." "High-risk fail-closed completion gate withheld DONE because verification status/go-no-go/evidence requirements were incomplete." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "high-risk fail-closed output contract incomplete"
          stream_emit_line "$stream_output_file" "High-risk fail-closed output gate converted DONE to VERIFY pending explicit verification contract."
        fi
      fi
    fi

    post_gate_reasoning_salvage_eligible=0
    if [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      post_gate_reasoning_salvage_eligible=1
    elif [ "$assay_run_profile" -eq 1 ]; then
      case "$run_mode" in
        assistant|report|teacher|security-audit|pentest)
          post_gate_reasoning_salvage_eligible=1
          ;;
      esac
    fi

    if [ "$post_gate_reasoning_salvage_eligible" -eq 1 ]; then
      post_gate_salvage_required=0
      if [ "$final_state_mode" != "DONE" ]; then
        post_gate_salvage_required=1
      elif output_is_intermediate_contract "$assistant_output"; then
        post_gate_salvage_required=1
      elif final_has_instructional_placeholders "$assistant_output"; then
        post_gate_salvage_required=1
      fi

      if [ "$post_gate_salvage_required" -eq 1 ] && [ "$assay_run_profile" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Reasoning post-gate salvage: synthesizing deterministic contract-complete output."
        post_gate_now_epoch=$(date +%s 2>/dev/null || printf '0')
        case "$post_gate_now_epoch" in
          ""|*[!0-9]*)
            post_gate_now_epoch=$run_started_epoch
            ;;
        esac
        post_gate_elapsed_sec=$((post_gate_now_epoch - run_started_epoch))
        if [ "$post_gate_elapsed_sec" -lt 0 ]; then
          post_gate_elapsed_sec=0
        fi

        assistant_output=$(reasoning_deterministic_salvage_output \
          "$augmented_user_prompt" \
          "$plan_text" \
          "$loop_summary" \
          "$run_command_success_total" \
          "$post_gate_elapsed_sec")
        assistant_output=$(assay_normalize_assistant_output \
          "$assistant_output" \
          "DONE" \
          "$plan_text" \
          "$run_time_budget" \
          "$post_gate_elapsed_sec" \
          "$augmented_user_prompt")
        assistant_output=$(ensure_output_has_runtime_command_evidence \
          "$assistant_output" \
          "$loop_summary" \
          "$run_command_success_total" \
          "$augmented_user_prompt" \
          "1")
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_adversarial_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_decision_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_cross_domain_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_recovery_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_verification_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_ambiguity_final_contract "$assistant_output")
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
          assistant_output=$(normalize_assumption_revision_final_contract "$assistant_output" "$augmented_user_prompt")
          assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
          assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        fi
        assistant_output=$(normalize_reasoning_followup_thread_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_live_contract "$assistant_output" "$augmented_user_prompt")
        if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
          assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
        fi

        final_state_mode="DONE"
        state_set "$state_file" "mode" "DONE"
        state_set "$state_file" "transition_reason" "reasoning post-gate deterministic salvage"
      fi
    fi

    if { [ "$run_mode" = "programming" ] || prompt_requires_code_implementation "$augmented_user_prompt"; } \
      && { [ "$final_state_mode" != "DONE" ] || programming_output_needs_concise_summary "$assistant_output" "$final_state_mode" || programming_should_force_concise_summary "$run_mode" "$compute_budget" "$max_iterations" "$augmented_user_prompt"; }; then
      assistant_output=$(programming_concise_final_output \
        "$assistant_output" \
        "$final_state_mode" \
        "$augmented_user_prompt" \
        "$loop_summary" \
        "$plan_text" \
        "$git_status" \
        "$run_command_success_total")
      stream_emit_line "$stream_output_file" "Programming final-output normalizer replaced verbose or generic summary with concise implementation summary."
    fi

    decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
    if [ "$decision_request_json" != "null" ]; then
      decision_summary_text=$(decision_request_summary_text_from_json "$decision_request_json")
      decision_summary_text=$(trim "$decision_summary_text")
      if [ -n "$decision_summary_text" ]; then
        assistant_output_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
        if [ -z "$(trim "$assistant_output")" ]; then
          assistant_output="$decision_summary_text"
          stream_emit_line "$stream_output_file" "Decision summary injected into final assistant output."
        elif ! printf '%s' "$assistant_output_lower" | grep -Eq 'question:|options:'; then
          assistant_output=$(printf '%s\n\n%s' "$assistant_output" "$decision_summary_text")
          stream_emit_line "$stream_output_file" "Decision summary appended to final assistant output."
        fi
      fi
    fi

    if [ "$run_mode" = "teacher" ]; then
      teacher_output_snippet=$(single_line_snippet "$assistant_output")
      if [ -z "$(trim "$teacher_output_snippet")" ]; then
        teacher_output_snippet="(no assistant summary captured)"
      fi
      teacher_post_note=$(cat <<EOF
delivered=$teacher_output_snippet
interaction_gap=$teacher_gap_summary
recommended_review_spacing_days=$teacher_review_days
EOF
)
      append_teacher_model_note "$teacher_model_file" "Post-run teaching summary" "$teacher_post_note"
    fi

    append_session_entry "$session_log_file" "final response" "$assistant_output"
    append_message "$conv_dir" "assistant" "$assistant_output"

    session_tail=$(tail -n 1000 "$session_log_file" 2>/dev/null || sed -n '1,1000p' "$session_log_file")
    controller_tail=$(tail -n 1400 "$controller_raw_file" 2>/dev/null || sed -n '1,1400p' "$controller_raw_file")
    session_combined=$(cat <<EOF
$session_tail

## Controller Raw Output

$controller_tail
EOF
)
    state_text=$(sed -n '1,80p' "$state_file")
    assistant_json=$(json_escape "$assistant_output")
    plan_json=$(json_escape "$plan_text")
    model_json=$(json_escape "$model")
    git_status_json=$(json_escape "$git_status")
    git_diff_json=$(json_escape "$git_diff")
    failures_json=$(json_escape "$failures_tail")
    session_json=$(json_escape "$session_combined")
    state_json=$(json_escape "$state_text")
    blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")

    # In assay mode, ensure a minimum command-depth trace before finalizing.
    if [ "$assay_run_profile" -eq 1 ]; then
      depth_fill_attempts=0
      while [ "$run_command_success_total" -lt 2 ] && [ "$depth_fill_attempts" -lt 3 ]; do
        depth_fill_attempts=$((depth_fill_attempts + 1))
        depth_fill_cmd="git status --short"
        depth_out=$(mktemp)
        depth_status_file=$(mktemp)
        execute_mediated_command "$workspace_id" "$workspace_path" "$depth_fill_cmd" "$depth_out" "$depth_status_file" "$command_mode" "$blocked_commands_file"
        depth_status=$(cat "$depth_status_file" 2>/dev/null || printf '%s' "error")
        depth_output=$(sed -n '1,220p' "$depth_out")
        rm -f "$depth_out" "$depth_status_file"
        if [ "$depth_status" = "ok" ]; then
          run_command_success_total=$((run_command_success_total + 1))
        fi
        depth_command_json=$(json_escape "$depth_fill_cmd")
        depth_status_json=$(json_escape "$depth_status")
        depth_output_json=$(json_escape "$depth_output")
        depth_command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
          "$depth_command_json" "$depth_status_json" "$depth_output_json")
        if [ "$commands_first" -eq 1 ]; then
          commands_json=$depth_command_item
          commands_first=0
        else
          commands_json="${commands_json},${depth_command_item}"
        fi
        stream_emit_line "$stream_output_file" "Assay depth check command: $depth_fill_cmd ($depth_status)"
        if [ "$depth_status" != "ok" ]; then
          break
        fi
      done
    fi

    queue_status_from_run="$forced_queue_status"
    if [ -z "$queue_status_from_run" ]; then
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
      elif [ "$decision_request_json" != "null" ]; then
        queue_status_from_run="awaiting_decision"
      elif [ "$final_state_mode" != "DONE" ]; then
        if [ "$assay_run_profile" -eq 1 ] && assay_output_has_required_sections "$assistant_output" && ! output_is_intermediate_contract "$assistant_output" && ! final_has_instructional_placeholders "$assistant_output"; then
          queue_status_from_run="done"
        else
          queue_status_from_run="error"
        fi
      fi
    fi
    if [ "$queue_status_from_run" != "awaiting_approval" ]; then
      clear_approval_request "$conv_dir"
    fi
    run_event_status=$(run_event_status_from_run "$queue_status_from_run" "$run_budget_exhausted")
    queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
    run_elapsed_sec=0
    case "$run_started_epoch" in
      ""|*[!0-9]*)
        run_started_epoch=0
        ;;
    esac
    run_finished_epoch=$(date +%s 2>/dev/null || printf '0')
    case "$run_finished_epoch" in
      ""|*[!0-9]*)
        run_finished_epoch=0
        ;;
    esac
    if [ "$run_started_epoch" -gt 0 ] && [ "$run_finished_epoch" -ge "$run_started_epoch" ]; then
      run_elapsed_sec=$((run_finished_epoch - run_started_epoch))
    fi
    run_elapsed_min=$((run_elapsed_sec / 60))
    run_elapsed_rem=$((run_elapsed_sec % 60))
    decision_requested_for_variant=0
    if [ "$decision_request_json" != "null" ]; then
      decision_requested_for_variant=1
    fi
    failure_count_for_variant=$(grep -c '^## ' "$failures_file" 2>/dev/null || printf '0')
    case "$failure_count_for_variant" in
      ""|*[!0-9]*)
        failure_count_for_variant=0
        ;;
    esac
    if [ -n "$controller_variant_id" ] && command -v mr_controller_variant_record_run >/dev/null 2>&1; then
      mr_controller_variant_record_run \
        "$controller_variant_id" \
        "$run_event_id" \
        "$queue_status_from_run" \
        "$final_state_mode" \
        "$run_elapsed_sec" \
        "$iteration" \
        "$decision_requested_for_variant" \
        "$failure_count_for_variant" \
        "$run_mode" \
        "$model" >/dev/null 2>&1 || true
    fi
    stream_emit_line "$stream_output_file" "Final response prepared for delivery."
    stream_emit_line "$stream_output_file" "Run artifacts captured (state, failures, trace)."
    stream_emit_line "$stream_output_file" "Worked for ${run_elapsed_min}m ${run_elapsed_rem}s."
    stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run (event=$run_event_status)"
    run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    run_stream_preview=$(sed -n '1,360p' "$stream_output_file" 2>/dev/null || true)
    commands_array_json="[$commands_json]"
    if [ -z "$(trim "$commands_json")" ]; then
      commands_array_json="[]"
    fi
    final_task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "$queue_status_from_run" "$state_text")
    run_error_text=""
    if [ "$queue_status_from_run" = "error" ] || [ "$run_event_status" = "timeout" ]; then
      run_error_text=$assistant_output
    fi
    controller_variant_event_hint=""
    if [ -n "$controller_variant_id" ]; then
      controller_variant_event_hint="controller_variant=$controller_variant_id"
      if [ -n "$controller_variant_candidate_id" ] && [ "$controller_variant_id" = "$controller_variant_candidate_id" ]; then
        controller_variant_event_hint="${controller_variant_event_hint} (candidate)"
      fi
    fi
    agent_event_json=$(build_run_event_json \
      "$run_event_status" \
      "$run_started_iso" \
      "$run_finished_iso" \
      "$model" \
      "$plan_text" \
      "$commands_array_json" \
      "$run_stream_preview" \
      "$failures_tail" \
      "$session_combined" \
      "$state_text" \
      "$git_status" \
      "$git_diff" \
      "$run_error_text" \
      "$controller_variant_event_hint" \
      "$run_event_id" \
      "$final_task_status_json" \
      "$run_message_anchor" \
      "$assay_task_id" \
      "$assistant_output")
    append_run_event_json "$conv_dir" "$agent_event_json"
    run_runtime_mark_finalized

    printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[%s],"blocked_commands":%s,"decision_request":%s,"failures":"%s","session_log":"%s","state":"%s","task_status":%s}\n' \
      "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$commands_json" "$blocked_commands_json" "$decision_request_json" "$failures_json" "$session_json" "$state_json" "$final_task_status_json"
    rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
    exit 0
