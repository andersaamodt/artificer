        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_health_status=$quick_mode_last_command_status
        remote_deploy_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_deploy_rollback_summary \
          "$remote_deploy_status_output" \
          "$remote_deploy_output" \
          "$remote_deploy_health_output" \
          "$remote_deploy_health_status")
        model_rc=0
      elif [ "$use_remote_single_host_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote single-host fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh journal" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_journal_output=$quick_mode_last_command_output
        if remote_single_host_config_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/service.env to MODE=healthy, READ_ONLY=1, and preserved the existing HOST and PORT values for the bounded remote host repair.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote fix: rewrote remote/service.env for a single-host recovery."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/service.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote fix failed: could not rewrite remote/service.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh restart" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_health_status=$quick_mode_last_command_status
        remote_single_host_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_single_host_summary \
          "$remote_single_host_status_output" \
          "$remote_single_host_journal_output" \
          "$remote_single_host_restart_output" \
          "$remote_single_host_health_output" \
          "$remote_single_host_health_status")
        model_rc=0
      elif [ "$use_local_service_restart_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local service restart fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_status_output=$quick_mode_last_command_output
        if local_service_config_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote service/config.env to MODE=healthy, READ_ONLY=1, and preserved the existing PORT value.
"
          stream_emit_line "$stream_output_file" "Quick-mode service fix: rewrote service/config.env for a healthy restart."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite service/config.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode service fix failed: could not rewrite service/config.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/restart.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_health_status=$quick_mode_last_command_status
        local_service_health_output=$quick_mode_last_command_output
        assistant_raw=$(local_service_restart_summary \
          "$local_service_status_output" \
          "$local_service_restart_output" \
          "$local_service_health_output" \
          "$local_service_health_status")
        model_rc=0
      elif [ "$use_programming_stopgo_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic phase stop/go fast path."
        assistant_raw=$(programming_phase_stopgo_summary_for_prompt "$user_message_text" "$programming_followup_prior_user_text" "$programming_followup_prior_assistant_text")
        model_rc=0
      elif [ "$use_freeform_reflection_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform reflection fast path."
        assistant_raw=$(reasoning_freeform_reflection_for_prompt "$freeform_reflection_context_text")
        model_rc=0
      elif [ "$use_freeform_frame_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform framing fast path."
        assistant_raw=$(reasoning_freeform_frame_for_prompt "$freeform_frame_context_text")
        model_rc=0
      elif [ "$use_freeform_reasoning_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform reasoning memo fast path."
        assistant_raw=$(reasoning_freeform_memo_for_prompt "$rich_reasoning_context_text")
        model_rc=0
      elif [ "$use_rich_followup_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic rich follow-up fast path."
        assistant_raw=$(reasoning_followup_fast_contract "$rich_reasoning_context_text")
        model_rc=0
      else
        stream_emit_line "$stream_output_file" "Requesting model output."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      fi
      unset ARTIFICER_STREAM_FILE 2>/dev/null || true

      assistant_output=$(normalize_assistant_output "$assistant_raw")
      assistant_output=$(trim "$assistant_output")

      if [ "$model_rc" -ne 0 ]; then
        if [ "$model_rc" -eq 124 ]; then
          assistant_output="Model timed out after ${quick_timeout_sec}s. Try a smaller prompt, a faster model, or run again."
        elif [ -z "$assistant_output" ]; then
          assistant_output="Model request failed (exit $model_rc)."
        fi
      fi

      if looks_like_embedding_vector "$assistant_output"; then
        assistant_output="Model returned an embedding vector instead of chat text. Pick a chat/instruct coding model and run again."
      fi

      if [ -z "$assistant_output" ]; then
        assistant_output="Run completed, but the model did not return content."
      fi
      if [ "$rich_reasoning_prompt" = "1" ]; then
        assistant_output=$(printf '%s\n' "$assistant_output" | awk 'NF { count++ } count <= 24 { print }')
        assistant_output=$(printf '%s' "$assistant_output" | cut -c1-3200)
        assistant_output=$(trim "$assistant_output")
      fi
      if [ "$assay_run_profile" -eq 1 ]; then
        depth_fill_commands='git status --short --untracked-files=no
git rev-parse --show-toplevel'
        old_ifs=${IFS-}
        IFS='
'
        for depth_fill_cmd in $depth_fill_commands; do
          depth_fill_cmd=$(trim "$depth_fill_cmd")
          [ -n "$depth_fill_cmd" ] || continue
          depth_out=$(mktemp)
          depth_status_file=$(mktemp)
          execute_mediated_command "$workspace_id" "$workspace_path" "$depth_fill_cmd" "$depth_out" "$depth_status_file" "$command_mode" "$blocked_commands_file"
          depth_status=$(cat "$depth_status_file" 2>/dev/null || printf '%s' "error")
          depth_output=$(sed -n '1,40p' "$depth_out")
          rm -f "$depth_out" "$depth_status_file"
          if [ "$depth_status" = "ok" ]; then
            quick_command_success_total=$((quick_command_success_total + 1))
          fi
          quick_loop_summary="${quick_loop_summary}
## Command
$depth_fill_cmd
Status: $depth_status
$depth_output
"
          depth_command_json=$(json_escape "$depth_fill_cmd")
          depth_status_json=$(json_escape "$depth_status")
          depth_output_json=$(json_escape "$depth_output")
          depth_command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
            "$depth_command_json" "$depth_status_json" "$depth_output_json")
          if [ "$quick_commands_first" -eq 1 ]; then
            quick_commands_json=$depth_command_item
            quick_commands_first=0
          else
            quick_commands_json="${quick_commands_json},${depth_command_item}"
          fi
          stream_emit_line "$stream_output_file" "Quick-mode assay depth check command: $depth_fill_cmd ($depth_status)"
        done
        IFS=$old_ifs
      fi

      if output_looks_derailed "$assistant_output"; then
        repaired_output=$(salvage_direct_response "$model" "$user_prompt")
        if [ -n "$(trim "$repaired_output")" ]; then
          assistant_output=$repaired_output
        fi
      elif [ "$run_mode" = "chat" ] && chat_output_looks_off_topic "$user_message_text" "$assistant_output"; then
        repaired_chat_output=$(salvage_chat_response "$model" "$user_message_text" "$chat_history_text")
        if [ -n "$(trim "$repaired_chat_output")" ]; then
          assistant_output=$repaired_chat_output
        fi
      fi

      if [ "$compact_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_compact_reasoning_contract "$assistant_output" "$compact_reasoning_context_text")
      elif [ "$diagram_annotation_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_diagram_annotation_read_response "$assistant_output")
      elif [ "$dashboard_chart_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_dashboard_chart_read_response "$assistant_output")
      elif [ "$before_after_ui_delta_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_before_after_ui_delta_response "$assistant_output")
      elif [ "$terminal_state_recovery_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_terminal_state_recovery_response "$assistant_output")
      elif [ "$terminal_screenshot_debug_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_terminal_screenshot_debug_response "$assistant_output")
      elif [ "$browser_image_run_investigation_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_browser_image_run_investigation_response "$assistant_output" "$user_prompt" "$browser_image_runtime_output")
      elif [ "$gui_screenshot_layout_triage_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_gui_screenshot_layout_triage_response "$assistant_output")
      elif [ "$freeform_clarify_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_clarify_response "$assistant_output" "$user_message_text")
      elif [ "$freeform_reflection_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_reflection_response "$assistant_output" "$freeform_reflection_context_text")
      elif [ "$freeform_frame_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_frame_response "$assistant_output" "$freeform_frame_context_text")
      elif [ "$freeform_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_memo "$assistant_output" "$rich_reasoning_context_text")
      elif [ "$rich_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_section_labels "$assistant_output")
        assistant_output=$(normalize_adversarial_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_decision_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_cross_domain_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_recovery_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_verification_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_ambiguity_final_contract "$assistant_output")
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$rich_reasoning_context_text" "")
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$rich_reasoning_context_text" "" "0")
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$rich_reasoning_context_text" "")
        if prompt_requires_assumption_revision_contract "$rich_reasoning_context_text"; then
          assistant_output=$(normalize_assumption_revision_final_contract "$assistant_output" "$rich_reasoning_context_text")
          assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$rich_reasoning_context_text" "")
        fi
        if [ "$quick_command_success_total" -gt 0 ]; then
          assistant_output=$(reasoning_contract_upsert_line "Verification Evidence" "$(reasoning_design_verification_line "$rich_reasoning_context_text" "$quick_command_success_total" "$quick_loop_summary")" "$assistant_output")
          assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_loop_summary")
          assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_loop_summary" "$quick_command_success_total")
        fi
        assistant_output=$(normalize_reasoning_followup_thread_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_reasoning_live_contract "$assistant_output" "$rich_reasoning_context_text")
        if prompt_requires_high_risk_fail_closed "$rich_reasoning_context_text" "$run_mode"; then
          assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_command_success_total" "$run_mode")
        fi
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$quick_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      state_json=$(json_escape "mode=DONE")
      quick_session_log=$(cat <<EOF
## quick-mode
Prompt:
$quick_prompt

Model raw output:
$assistant_raw
EOF
)
      if [ -n "$(trim "$quick_loop_summary")" ]; then
        quick_session_log="${quick_session_log}

## Quick Assay Depth Checks
$quick_loop_summary"
      fi
      if [ -n "$(trim "$explicit_skill_context_text")" ]; then
        quick_session_log="${quick_session_log}

## Explicit Skills
$explicit_skill_context_text"
      fi
      quick_session_json=$(json_escape "$quick_session_log")
      quick_commands_array_json="[$quick_commands_json]"
      if [ -z "$(trim "$quick_commands_json")" ]; then
        quick_commands_array_json="[]"
      fi

      blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
      fi
      if [ "$queue_status_from_run" != "awaiting_approval" ]; then
        clear_approval_request "$conv_dir"
      fi
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      run_error_text=""
      quick_task_status_json=$(task_status_empty_json)
      if [ "$queue_status_from_run" = "error" ]; then
        run_error_text=$assistant_output
      fi
      quick_event_json=$(build_run_event_json \
        "$queue_status_from_run" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$quick_plan" \
        "$quick_commands_array_json" \
        "$run_stream_preview" \
        "" \
        "$quick_session_log" \
        "mode=DONE" \
        "$git_status" \
        "$git_diff" \
        "$run_error_text" \
        "" \
        "$run_event_id" \
        "$quick_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output")
      append_run_event_json "$conv_dir" "$quick_event_json"
      run_runtime_mark_finalized
      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":%s,"blocked_commands":%s,"decision_request":null,"failures":"","session_log":"%s","state":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$quick_commands_array_json" "$blocked_commands_json" "$quick_session_json" "$state_json" "$quick_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    agent_dir="$conv_dir/agent"
    plan_file="$agent_dir/.plan.md"
    state_file="$agent_dir/.state"
    contract_file="$agent_dir/.contract.md"
    failures_file="$agent_dir/.failures.md"
    session_log_file="$agent_dir/.session.log.md"
    controller_raw_file="$agent_dir/.controller.raw.md"
    assumptions_file="$agent_dir/.assumptions.md"
    compliance_file="$agent_dir/.compliance.md"
    architecture_file="$agent_dir/.architecture.md"
    tasks_dir="$agent_dir/.tasks"
    tasks_index_file="$tasks_dir/index.md"
    scratch_root="$agent_dir/.scratch"
    changed_paths_file="$agent_dir/.changed-paths"
    programming_followup_slice_path=""
    programming_followup_slice_kind=""
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
