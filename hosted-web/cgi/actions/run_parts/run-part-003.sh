    if [ "$standards_grounded_answer_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$multi_artifact_judgment_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$multi_service_partial_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$system_release_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$system_boundary_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$partial_system_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$background_process_recovery_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_env_drift_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_package_upgrade_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$long_running_command_polling_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$filesystem_mutation_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_release_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_rollout_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_bastion_cutover_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_multi_host_rollout_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_multi_host_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_deploy_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_single_host_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_service_restart_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$programming_followup_stopgo_prompt" -eq 1 ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_clarify_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_reflection_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_frame_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$rich_reasoning_prompt" = "1" ]; then
      # Rich reasoning completion prompts are scenario-synthesis requests, not
      # workspace investigation tasks. Keep them on the bounded direct path so
      # the run budget is spent on reasoning quality rather than controller churn.
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ -n "$inline_mode_tag" ]; then
      stream_emit_line "$stream_output_file" "Inline mode directive detected: $inline_mode_tag -> $run_mode"
    fi
    if [ -n "$queue_mode_override" ]; then
      stream_emit_line "$stream_output_file" "Queue mode lock applied: $queue_mode_override"
    fi
    if [ "$compact_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Compact reasoning fail-safe active: bypassing long-loop execution."
    fi
    if [ "$document_revision_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Document revision fast path active: generating a structured memo."
    fi
    if [ "$diagram_annotation_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Diagram annotation read fast path active: analyzing the attached diagram or annotated screenshot and returning takeaway/evidence/risk/next check."
    fi
    if [ "$dashboard_chart_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Dashboard chart read fast path active: analyzing the attached chart or table and returning finding/evidence/risk/next check."
    fi
    if [ "$before_after_ui_delta_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Before/after UI delta fast path active: comparing the attached screenshots and returning change/before evidence/after evidence/impact."
    fi
    if [ "$terminal_state_recovery_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Terminal-state recovery fast path active: comparing the before/after terminal screenshots and returning state change/before evidence/after evidence/next check."
    fi
    if [ "$terminal_screenshot_debug_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Terminal screenshot debug fast path active: analyzing the attached terminal or log screenshot and returning finding/evidence/next command/risk."
    fi
    if [ "$gui_screenshot_layout_triage_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "GUI screenshot layout triage fast path active: analyzing the attached screenshot directly and returning issue/evidence/cause/fix."
    fi
    if [ "$repo_runtime_web_triage_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Repo/runtime/web triage fast path active: running repo evidence, runtime evidence, and direct web-doc fetch in one bounded pass."
    fi
    if [ "$browser_image_run_investigation_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Browser/image/runtime investigation fast path active: combining Safari screenshot evidence, browser snapshot evidence, and one bounded runtime helper."
    fi
    if [ "$tool_failure_handoff_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Tool-failure handoff fast path active: running the initial helper, capturing the failure, handing off to the fallback helper, and grounding the result in current docs."
    fi
    if [ "$current_api_migration_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Current API migration fast path active: combining repo evidence with the current official migration guide in one bounded pass."
    fi
    if [ "$current_ops_guidance_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Current ops guidance fast path active: combining local state with current official guidance in one bounded pass."
    fi
    if [ "$standards_grounded_answer_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Standards-grounded answer fast path active: combining repo evidence, runtime evidence, and the current official standard/docs in one bounded pass."
    fi
    if [ "$multi_artifact_judgment_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Multi-artifact judgment fast path active: returning one bounded operator decision across code, doc, screenshot, and command evidence."
    fi
    if [ "$multi_service_partial_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Multi-service partial rollback fast path active: inspecting both local services, approving the shared rollback, executing both rollbacks, and verifying recovery."
    fi
    if [ "$system_release_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "System release pack fast path active: inspecting both local boundaries, approving the shared release pack, executing ordered cutovers, publishing the release pack, and verifying the published release."
    fi
    if [ "$system_boundary_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "System boundary pack fast path active: inspecting both local boundaries, approving the shared cutover, executing core-first and edge-second cutovers, and verifying the pack."
    fi
    if [ "$partial_system_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Partial system rollback fast path active: inspecting bounded mixed state, approving rollback, executing it, and verifying recovery."
    fi
    if [ "$background_process_recovery_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Background process fast path active: running ps, stop, fix, start, and health checks."
    fi
    if [ "$local_env_drift_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local env drift fast path active: running doctor, repair, and verify checks."
    fi
    if [ "$local_package_upgrade_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local package upgrade fast path active: running audit, upgrade, and test checks."
    fi
    if [ "$long_running_command_polling_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Long-running command fast path active: polling, checkpointing, finalizing, and verifying the bounded job."
    fi
    if [ "$filesystem_mutation_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Filesystem mutation fast path active: inventorying, applying the bounded layout change, and verifying the result."
    fi
    if [ "$remote_release_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote release pack fast path active: running bastion status, opening the tunnel, deploying the core boundary pair before the edge boundary pair, publishing the shared release pack, and verifying the release."
    fi
    if [ "$remote_boundary_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary pack fast path active: running bastion status, opening the tunnel, then deploying the core boundary pair before the edge boundary pair and verifying the pack."
    fi
    if [ "$remote_boundary_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary rollback fast path active: running bastion status, opening the tunnel, then staged private canary and fleet rollbacks with health checks."
    fi
    if [ "$remote_boundary_rollout_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary rollout fast path active: running bastion status, opening the tunnel, then staging private canary and fleet deploys with health checks."
    fi
    if [ "$remote_bastion_cutover_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote bastion cutover fast path active: running bastion status, tunnel, private cutover, and dual health checks."
    fi
    if [ "$remote_multi_host_rollout_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote multi-host rollout fast path active: running canary status, staged deploys, and dual health checks."
    fi
    if [ "$remote_multi_host_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote multi-host fast path active: running app-host status, replica promotion, restart, and dual health checks."
    fi
    if [ "$remote_deploy_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote deploy fast path active: running remote status, deploy, and health checks."
    fi
    if [ "$remote_single_host_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote single-host fast path active: running SSH status, journal, restart, and health checks."
    fi
    if [ "$local_service_restart_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local service restart fast path active: running status, fix, restart, and health checks."
    fi
    if [ "$programming_followup_stopgo_prompt" -eq 1 ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Phase stop/go fast path active: preserving the current landed slices and deferred queue."
    fi
    if [ "$freeform_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform reasoning fail-safe active: bypassing long-loop execution."
    fi
    if [ "$freeform_clarify_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Ambiguous-intent clarify fail-safe active: asking for a tighter intent signal."
    fi
    if [ "$freeform_reflection_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform reflection fail-safe active: returning a bounded reflection instead of a recommendation."
    fi
    if [ "$freeform_frame_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform framing fail-safe active: returning a bounded framing response instead of a recommendation."
    fi
    if [ "$rich_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Rich reasoning fail-safe active: bypassing long-loop execution."
    fi
    queue_last_mode_file=$(queue_last_mode_file_for "$conv_dir")
    queue_last_assistant_mode_file=$(queue_last_assistant_mode_file_for "$conv_dir")
    queue_last_compute_budget_file=$(queue_last_compute_budget_file_for "$conv_dir")
    queue_last_command_exec_mode_file=$(queue_last_command_exec_mode_file_for "$conv_dir")
    queue_last_permission_mode_file=$(queue_last_permission_mode_file_for "$conv_dir")
    queue_last_programmer_review_file=$(queue_last_programmer_review_file_for "$conv_dir")
    queue_last_programmer_review_rounds_file=$(queue_last_programmer_review_rounds_file_for "$conv_dir")
    queue_last_assay_task_id_file=$(queue_last_assay_task_id_file_for "$conv_dir")
    printf '%s\n' "$run_mode" > "$queue_last_mode_file"
    printf '%s\n' "$assistant_mode_id" > "$queue_last_assistant_mode_file"
    printf '%s\n' "$compute_budget" > "$queue_last_compute_budget_file"
    printf '%s\n' "$command_mode" > "$queue_last_command_exec_mode_file"
    printf '%s\n' "$permission_mode" > "$queue_last_permission_mode_file"
    printf '%s\n' "$programmer_review_enabled" > "$queue_last_programmer_review_file"
    printf '%s\n' "$programmer_review_max_rounds" > "$queue_last_programmer_review_rounds_file"
    printf '%s\n' "$assay_task_id" > "$queue_last_assay_task_id_file"
    max_iterations_label=$max_iterations
    if [ "$max_iterations" -le 0 ]; then
      max_iterations_label="unbounded"
    fi
    if [ -n "$assistant_mode_id" ]; then
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (team=$assistant_mode_id, advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label)"
    elif [ "$run_mode" = "programming" ] || [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label, code_review=${programmer_review_enabled}, review_rounds=${programmer_review_max_rounds})"
    else
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label)"
    fi
    stream_emit_line "$stream_output_file" "Run orchestration initialized."
    stream_emit_line "$stream_output_file" "Initial checkpoints seeded."
    stream_emit_line "$stream_output_file" "Run time budget: ${run_time_budget}s"
    explicit_skill_context_text=""
    explicit_skill_invocation_count=0
    if [ -n "$explicit_skill_ids_csv" ]; then
      ensure_mode_runtime_bootstrap
      stream_emit_line "$stream_output_file" "Explicit skill tags detected: $explicit_skill_ids_csv"
      skill_invoke_mode="assistant"
      if [ "$run_mode" = "assistant" ] && [ -n "$assistant_mode_id" ]; then
        skill_invoke_mode="$assistant_mode_id"
      fi
      while IFS= read -r explicit_skill_id; do
        explicit_skill_id=$(trim "$explicit_skill_id")
        [ -n "$explicit_skill_id" ] || continue
        if [ "$explicit_skill_invocation_count" -ge 8 ]; then
          stream_emit_line "$stream_output_file" "Skipping remaining explicit skills after 8 invocations to keep context focused."
          break
        fi
        explicit_skill_invocation_count=$((explicit_skill_invocation_count + 1))
        if ! command -v mr_skill_exists >/dev/null 2>&1; then
          stream_emit_line "$stream_output_file" "Skill runtime unavailable; could not invoke $explicit_skill_id."
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (skill runtime unavailable)"
          continue
        fi
        if ! mr_skill_exists "$explicit_skill_id"; then
          stream_emit_line "$stream_output_file" "Explicit skill not found: $explicit_skill_id"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (skill not found)"
          continue
        fi
        stream_emit_line "$stream_output_file" "Invoking explicit skill: $explicit_skill_id"
        skill_invocation_json=$(mr_skill_invoke_json "$skill_invoke_mode" "$explicit_skill_id" "$user_prompt" "")
        skill_invocation_ok=0
        if printf '%s' "$skill_invocation_json" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true'; then
          skill_invocation_ok=1
        fi
        if [ "$skill_invocation_ok" -eq 1 ]; then
          skill_result_status=$(printf '%s' "$skill_invocation_json" | perl -MJSON::PP -e '
            use strict;
            use warnings;
            local $/;
            my $raw = <STDIN>;
            my $data = eval { decode_json($raw) };
            exit 1 if $@ || ref($data) ne "HASH";
            my $result = $data->{"result"};
            exit 1 if ref($result) ne "HASH";
            my $value = $result->{"status"};
            exit 1 if !defined($value) || ref($value);
            print $value;
          ' 2>/dev/null || true)
          skill_result_summary=$(printf '%s' "$skill_invocation_json" | perl -MJSON::PP -e '
            use strict;
            use warnings;
            local $/;
            my $raw = <STDIN>;
            my $data = eval { decode_json($raw) };
            exit 1 if $@ || ref($data) ne "HASH";
            my $result = $data->{"result"};
            exit 1 if ref($result) ne "HASH";
            my $value = $result->{"summary"};
            exit 1 if !defined($value) || ref($value);
            print $value;
          ' 2>/dev/null || true)
          skill_result_status=$(trim "$skill_result_status")
          skill_result_summary=$(trim "$skill_result_summary")
          [ -n "$skill_result_status" ] || skill_result_status="ok"
          [ -n "$skill_result_summary" ] || skill_result_summary="Skill invocation completed."
          stream_emit_line "$stream_output_file" "Skill $explicit_skill_id completed with status: $skill_result_status"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: status=${skill_result_status}; summary=${skill_result_summary}"
        else
          skill_error_text=$(json_extract_string_field "error" "$skill_invocation_json" || true)
          skill_error_text=$(trim "$skill_error_text")
          if [ -z "$skill_error_text" ]; then
            skill_error_text="skill invocation failed"
          fi
          stream_emit_line "$stream_output_file" "Skill $explicit_skill_id could not be applied: $skill_error_text"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (${skill_error_text})"
        fi
      done < "$explicit_skills_file"
      explicit_skill_context_text=$(compact_text_block "Explicit skill results" "$explicit_skill_context_text" 900)
    fi
    workspace_context_text=$(workspace_shared_context "$ws_dir" "$conversation_id" | sed -n '1,240p')
