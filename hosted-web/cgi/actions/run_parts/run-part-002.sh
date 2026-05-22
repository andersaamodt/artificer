    if is_hello_world_script_task "$user_prompt"; then
      stream_emit_line "$stream_output_file" "Detected hello-world script task."
      hello_file="$workspace_path/hello.sh"
      write_ok=1
      run_status="failed"
      run_output=""
      run_decision_hint=""
      blocked_commands_json="[]"
      quick_plan=$(cat <<EOF
Goal:
- Create hello.sh, make it executable, and run it.
Subgoals:
- write script content
- set executable bit
- execute and capture output
Constraints:
- stay inside workspace root
Unknowns:
- command approval policy
Next Action:
- run ./hello.sh
Completion Criteria:
- output is "Hello, world!"
EOF
)

      if [ "$allow_workspace_writes" -ne 1 ]; then
        write_ok=0
      elif ! cat > "$hello_file" <<'EOF'
#!/bin/sh
printf '%s\n' 'Hello, world!'
EOF
      then
        write_ok=0
      fi
      if [ "$write_ok" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Created hello.sh."
      else
        if [ "$allow_workspace_writes" -ne 1 ]; then
          stream_emit_line "$stream_output_file" "Write blocked by read-only permissions."
        else
          stream_emit_line "$stream_output_file" "Failed to create hello.sh."
        fi
      fi
      if [ "$write_ok" -eq 1 ]; then
        chmod +x "$hello_file" 2>/dev/null || true
        stream_emit_line "$stream_output_file" "Marked hello.sh executable. Running ./hello.sh."
        tool_out=$(mktemp)
        tool_status_file=$(mktemp)
        tool_decision_hint_file=$(mktemp)
        execute_mediated_command "$workspace_id" "$workspace_path" "./hello.sh" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file" "$tool_decision_hint_file"
        run_status=$(cat "$tool_status_file" 2>/dev/null || printf '%s' "failed")
        run_decision_hint=$(cat "$tool_decision_hint_file" 2>/dev/null || printf '%s' "")
        run_output=$(sed -n '1,220p' "$tool_out")
        stream_emit_line "$stream_output_file" "Command status: $run_status"
        rm -f "$tool_out" "$tool_status_file" "$tool_decision_hint_file"
      fi

      if [ "$write_ok" -ne 1 ]; then
        if [ "$allow_workspace_writes" -ne 1 ]; then
          assistant_output="I couldn't create hello.sh because permissions are set to Read only. Switch permissions to Workspace write or Default and retry."
        else
          assistant_output="I couldn't create hello.sh in the workspace root."
        fi
      elif [ "$run_status" = "ok" ]; then
        hello_line=$(trim "$(printf '%s\n' "$run_output" | sed -n '1p')")
        if [ -n "$hello_line" ]; then
          assistant_output="I created hello.sh, made it executable, and ran it. Output: $hello_line"
        else
          assistant_output="I created hello.sh and ran it successfully."
        fi
      elif [ "$run_status" = "approval_required" ]; then
        assistant_output="I created hello.sh. I need command approval to run it."
        stream_emit_line "$stream_output_file" "Waiting for command approval."
      else
        assistant_output="I created hello.sh, but running it failed: $(trim "$run_output")"
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
        if [ "$run_status" = "approval_required" ]; then
          save_approval_request "$conv_dir" "./hello.sh" "approval-required" >/dev/null 2>&1 || true
        fi
      elif [ "$write_ok" -ne 1 ] || [ "$run_status" = "failed" ] || [ "$run_status" = "blocked" ]; then
        queue_status_from_run="error"
      fi
      if [ "$queue_status_from_run" != "awaiting_approval" ]; then
        clear_approval_request "$conv_dir"
      fi
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$quick_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      session_log=$(cat <<EOF
## hello-fast-path
write_ok=$write_ok
run_status=$run_status
run_output:
$run_output
EOF
)
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      run_error_text=""
      hello_task_status_json=$(task_status_empty_json)
      if [ "$queue_status_from_run" = "error" ]; then
        run_error_text=$assistant_output
      fi
      hello_event_json=$(build_run_event_json \
        "$queue_status_from_run" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$quick_plan" \
        "[]" \
        "$run_stream_preview" \
        "" \
        "$session_log" \
        "mode=DONE" \
        "$git_status" \
        "$git_diff" \
        "$run_error_text" \
        "$run_decision_hint" \
        "$run_event_id" \
        "$hello_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output" \
        "")
      append_run_event_json "$conv_dir" "$hello_event_json"
      run_runtime_mark_finalized
      session_json=$(json_escape "$session_log")
      state_json=$(json_escape "mode=DONE")
      decision_hint_json=$(json_escape "$(trim "$run_decision_hint")")

      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[],"blocked_commands":%s,"decision_request":null,"failures":"","session_log":"%s","state":"%s","decision_hint":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$blocked_commands_json" "$session_json" "$state_json" "$decision_hint_json" "$hello_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    model_inventory_known=0
    model_installed=0
    model_inventory=$(list_models_raw || true)
    if [ -n "$(trim "$model_inventory")" ]; then
      model_inventory_known=1
      if model_present_in_inventory "$model" "$model_inventory"; then
        model_installed=1
      fi
    fi
    model_install_runtime=$(model_install_runtime_status_for_model "$model")
    model_install_status=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f1)
    model_install_phase=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f2)
    model_install_progress=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f3)

    if [ "$model_installed" -ne 1 ] && [ "$model_inventory_known" -eq 1 ] && { [ "$run_mode" = "programming" ] || prompt_requires_code_implementation "$user_prompt"; }; then
      task_snippet=$(programming_task_snippet_for_prompt "$user_prompt")
      if [ "$model_install_status" = "running" ]; then
        stream_emit_line "$stream_output_file" "Selected model is still installing; stopping before implementation loop."
        install_detail="$model"
        if [ -n "$(trim "$model_install_phase")" ]; then
          install_detail="$install_detail ($model_install_phase"
          if [ -n "$(trim "$model_install_progress")" ]; then
            install_detail="${install_detail}, ${model_install_progress}%)"
          else
            install_detail="${install_detail})"
          fi
        fi
        assistant_output=$(cat <<EOF
Outcome: I did not start the implementation for $task_snippet because the selected model is still downloading.
Verification Evidence: Model inventory did not list $model. Active install status: $install_detail.
Risks: Waiting here would stall the run and can leak install chatter into the conversation instead of doing project work.
Next Improvement: Let the download finish in Settings > Models or switch this conversation to an installed model, then rerun.
EOF
)
      else
        stream_emit_line "$stream_output_file" "Selected model is not installed; stopping before implementation loop."
        assistant_output=$(cat <<EOF
Outcome: I did not start the implementation for $task_snippet because the selected model is not installed locally.
Verification Evidence: Current model inventory is available, and it does not include $model.
Risks: Starting the run anyway would likely stall, auto-pull a model unexpectedly, or produce unreliable implementation output.
Next Improvement: Install $model in Settings > Models or switch this conversation to an installed model, then rerun.
EOF
)
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      queue_status_from_run="error"
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"

      preflight_plan=$(cat <<EOF
Goal:
- Execute the requested programming task with the selected local model.
Subgoals:
- verify model availability
- avoid stalled implementation loops
- return a concise actionable status if the model is not ready
Constraints:
- do not auto-pull a missing model inside the user conversation
Unknowns:
- when the user will finish the model download or switch models
Next Action:
- rerun after the selected model is installed locally
Completion Criteria:
- implementation starts only after the model is ready
EOF
)
      preflight_session_log=$(cat <<EOF
## programming-model-preflight
requested_model=$model
inventory_known=$model_inventory_known
model_installed=$model_installed
install_status=$model_install_status
install_phase=$model_install_phase
install_progress=$model_install_progress
EOF
)
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      preflight_task_status_json=$(task_status_empty_json)
      preflight_event_json=$(build_run_event_json \
        "error" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$preflight_plan" \
        "[]" \
        "$run_stream_preview" \
        "" \
        "$preflight_session_log" \
        "mode=VERIFY" \
        "$git_status" \
        "$git_diff" \
        "$assistant_output" \
        "" \
        "$run_event_id" \
        "$preflight_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output" \
        "")
      append_run_event_json "$conv_dir" "$preflight_event_json"
      run_runtime_mark_finalized

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$preflight_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      session_json=$(json_escape "$preflight_session_log")
      state_json=$(json_escape "mode=VERIFY")
      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[],"blocked_commands":[],"decision_request":null,"failures":"","session_log":"%s","state":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$session_json" "$state_json" "$preflight_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    run_started_epoch=$(date +%s)
    run_time_budget_raw=${ARTIFICER_RUN_TIME_BUDGET_SEC-}
    run_time_budget_explicit=0
    if [ -n "$run_time_budget_raw" ]; then
      run_time_budget_explicit=1
    fi
    run_time_budget=${ARTIFICER_RUN_TIME_BUDGET_SEC:-900}
    case "$run_time_budget" in
      ""|*[!0-9]*)
        run_time_budget=900
        run_time_budget_explicit=0
        ;;
    esac
    run_time_budget_floor=120
    if [ "$assay_run_profile" -eq 1 ]; then
      run_time_budget_floor=45
    fi
    if [ "$run_time_budget" -lt "$run_time_budget_floor" ]; then
      run_time_budget=$run_time_budget_floor
    fi
    prompt_lower_budget_runtime=$(printf '%s' "$user_prompt" | tr '[:upper:]' '[:lower:]')
    if [ "$assay_run_profile" -ne 1 ]; then
      if [ "$run_time_budget" -lt 420 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'godot|barnes[- ]?hut|checksum|replay|self[- ]?tests?|regression|gameplay|challenge|objective|polish'; then
        run_time_budget=420
      fi
      if [ "$run_time_budget" -lt 540 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq '120\\+|100\\+|80\\+|at least[[:space:]]+(80|100|120)([^0-9]|$)|deterministic replay|final[ -]?state checksum|barnes[- ]?hut' && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'gameplay|challenge|polish|objective|score|combo'; then
        run_time_budget=540
      fi
      if [ "$run_time_budget" -lt 900 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'large[ -]?context|large[ -]?scale|architecture|monorepo|multi[- ]module|multi[- ]service|refactor|migration|distributed'; then
        run_time_budget=900
      fi
      if [ "$run_time_budget" -lt 1200 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'launch|business|go[- ]to[- ]market|compliance|legal|regulatory|operations|sales|pricing|growth'; then
        run_time_budget=1200
      fi
      case "$run_mode" in
        auto)
          # Keep heuristic-derived budget for adaptive mode; compute-budget floors/ceilings
          # still apply below.
          ;;
        programming)
          if [ "$programming_quick_bounded_run" -eq 1 ]; then
            if [ "$run_time_budget" -lt 180 ]; then
              run_time_budget=180
            fi
          elif [ "$run_time_budget" -lt 420 ]; then
            run_time_budget=420
          fi
          ;;
        pentest)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        security-audit)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        report)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        teacher)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        text-perfecter)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        gui-testing)
          if [ "$run_time_budget" -lt 1200 ]; then
            run_time_budget=1200
          fi
          ;;
        assistant)
          if [ "$run_time_budget" -lt 1200 ]; then
            run_time_budget=1200
          fi
          ;;
        instant|chat)
          if [ "$compute_budget" = "quick" ] && [ "$run_time_budget" -gt 420 ]; then
            run_time_budget=420
          elif [ "$compute_budget" = "auto" ] && [ "$run_time_budget" -gt 900 ]; then
            run_time_budget=900
          fi
          ;;
      esac
    fi
    compute_budget_floor=$(compute_budget_runtime_floor_sec "$compute_budget")
    compute_budget_ceiling=$(compute_budget_runtime_ceiling_sec "$compute_budget")
    if [ "$run_time_budget_explicit" -ne 1 ]; then
      if [ "$run_time_budget" -lt "$compute_budget_floor" ]; then
        run_time_budget=$compute_budget_floor
      fi
      if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$run_time_budget" -gt 180 ]; then
        run_time_budget=180
      fi
    fi
    if [ "$run_time_budget" -gt "$compute_budget_ceiling" ]; then
      run_time_budget=$compute_budget_ceiling
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      case "$compute_budget" in
        quick)
          assay_runtime_ceiling=100
          ;;
        standard|auto)
          assay_runtime_ceiling=145
          ;;
        long)
          assay_runtime_ceiling=200
          ;;
        until-complete)
          assay_runtime_ceiling=260
          ;;
        *)
          assay_runtime_ceiling=220
          ;;
      esac
      if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$assay_runtime_ceiling" -gt 70 ]; then
        assay_runtime_ceiling=70
      fi
      if printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'race|concurren|migration|idempotent|rollback|security|audit|failure recovery|fallback|benchmark|stress|flaky|end[- ]to[- ]end|contract tests?'; then
        assay_runtime_ceiling=$((assay_runtime_ceiling + 30))
      fi
      if [ "$assay_runtime_ceiling" -gt 320 ]; then
        assay_runtime_ceiling=320
      fi
      if [ "$run_time_budget" -gt "$assay_runtime_ceiling" ]; then
        run_time_budget=$assay_runtime_ceiling
      fi
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      assay_dynamic_iteration_cap=5
      if [ "$run_time_budget" -le 70 ]; then
        assay_dynamic_iteration_cap=2
      elif [ "$run_time_budget" -le 115 ]; then
        assay_dynamic_iteration_cap=3
      elif [ "$run_time_budget" -le 170 ]; then
        assay_dynamic_iteration_cap=4
      fi
      if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 7 ]; then
        assay_dynamic_iteration_cap=7
      elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 6 ]; then
        assay_dynamic_iteration_cap=6
      elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 5 ]; then
        assay_dynamic_iteration_cap=5
      elif [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 4 ]; then
        assay_dynamic_iteration_cap=4
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 3 ]; then
        assay_dynamic_iteration_cap=3
      fi
      if [ "$assay_dynamic_iteration_cap" -gt 0 ]; then
        if [ "$max_iterations" -eq 0 ] || [ "$max_iterations" -gt "$assay_dynamic_iteration_cap" ]; then
          max_iterations=$assay_dynamic_iteration_cap
        fi
      fi
    fi
    if [ "$run_time_budget" -gt 86400 ]; then
      run_time_budget=86400
    fi
    model_timeout_scale=1
    if [ "$assay_run_profile" -ne 1 ]; then
      case "$compute_budget" in
        long)
          model_timeout_scale=2
          ;;
        until-complete)
          model_timeout_scale=3
          ;;
      esac
    fi
    export ARTIFICER_MODEL_TIMEOUT_SCALE=$model_timeout_scale
    if [ "$assay_run_profile" -eq 1 ]; then
      export ARTIFICER_COMMAND_TIMEOUT_SEC=14
    else
      unset ARTIFICER_COMMAND_TIMEOUT_SEC 2>/dev/null || true
    fi

    quick_mode=${ARTIFICER_QUICK_MODE:-0}
    simple_direct_prompt=0
    compact_reasoning_prompt=0
    compact_reasoning_followup_prompt=0
    compact_reasoning_context_text=$user_prompt
    document_revision_prompt=0
    document_revision_context_text=$user_prompt
    diagram_annotation_read_prompt=0
    dashboard_chart_read_prompt=0
    before_after_ui_delta_prompt=0
    terminal_state_recovery_read_prompt=0
    terminal_screenshot_debug_prompt=0
    gui_screenshot_layout_triage_prompt=0
    repo_runtime_web_triage_prompt=0
    browser_image_run_investigation_prompt=0
    tool_failure_handoff_prompt=0
    current_api_migration_prompt=0
    current_ops_guidance_prompt=0
    standards_grounded_answer_prompt=0
    multi_artifact_judgment_prompt=0
    multi_service_partial_rollback_prompt=0
    remote_release_pack_prompt=0
    remote_boundary_pack_prompt=0
    system_release_pack_prompt=0
    system_boundary_pack_prompt=0
    partial_system_rollback_prompt=0
    local_env_drift_prompt=0
    background_process_recovery_prompt=0
    local_package_upgrade_prompt=0
    long_running_command_polling_prompt=0
    filesystem_mutation_prompt=0
    remote_boundary_rollback_prompt=0
    remote_boundary_rollout_prompt=0
    remote_bastion_cutover_prompt=0
    remote_multi_host_rollout_prompt=0
    remote_multi_host_prompt=0
    remote_deploy_rollback_prompt=0
    remote_single_host_prompt=0
    local_service_restart_prompt=0
    rich_reasoning_prompt=0
    freeform_reasoning_prompt=0
    freeform_clarify_prompt=0
    freeform_reflection_prompt=0
    freeform_frame_prompt=0
    freeform_reflection_context_text=$user_message_text
    freeform_frame_context_text=$user_message_text
    freeform_post_clarify_prompt=0
    rich_reasoning_context_text=$user_message_text
    reasoning_followup_prompt=0
    reasoning_followup_context_text=$user_message_text
    force_agent_execution=0
    if is_simple_direct_prompt "$user_prompt"; then
      simple_direct_prompt=1
    fi
    if prompt_prefers_compact_reasoning_contract "$user_prompt"; then
      compact_reasoning_prompt=1
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_compact_reasoning_followup_contract "$user_prompt" "$conv_dir"; then
      compact_reasoning_prompt=1
      compact_reasoning_followup_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" = "1" ]; then
      compact_reasoning_context_text=$(compact_reasoning_context_prompt "$user_prompt" "$conv_dir")
    fi
    document_revision_fast_path_kind=$(document_revision_fast_path_kind_for_prompt "$user_prompt" "$conv_dir")
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$document_revision_fast_path_kind" != "unknown" ]; then
      document_revision_prompt=1
      document_revision_context_text=$(document_revision_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_diagram_annotation_read_task "$user_prompt"; then
      diagram_annotation_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_dashboard_chart_read_task "$user_prompt"; then
      dashboard_chart_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_before_after_ui_delta_task "$user_prompt"; then
      before_after_ui_delta_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_terminal_state_recovery_read_task "$user_prompt"; then
      terminal_state_recovery_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_terminal_screenshot_debug_task "$user_prompt"; then
      terminal_screenshot_debug_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && [ "$run_mode" = "assistant" ] && prompt_prefers_browser_image_run_investigation_task "$user_prompt"; then
      browser_image_run_investigation_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && [ "$browser_image_run_investigation_prompt" != "1" ] \
      && prompt_prefers_gui_screenshot_layout_triage_task "$user_prompt"; then
      gui_screenshot_layout_triage_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_repo_runtime_web_triage_task "$user_prompt"; then
      repo_runtime_web_triage_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_tool_failure_handoff_task "$user_prompt"; then
      tool_failure_handoff_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_current_api_migration_task "$user_prompt"; then
      current_api_migration_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_current_ops_guidance_task "$user_prompt"; then
      current_ops_guidance_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_standards_grounded_answer_task "$user_prompt"; then
      standards_grounded_answer_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_multi_artifact_judgment_task "$user_prompt"; then
      multi_artifact_judgment_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_release_pack_task "$user_prompt"; then
      remote_release_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_pack_task "$user_prompt"; then
      remote_boundary_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_multi_service_partial_rollback_task "$user_prompt"; then
      multi_service_partial_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_system_release_pack_task "$user_prompt"; then
      system_release_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_system_boundary_pack_task "$user_prompt"; then
      system_boundary_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_partial_system_rollback_task "$user_prompt"; then
      partial_system_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_env_drift_task "$user_prompt"; then
      local_env_drift_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_background_process_recovery_task "$user_prompt"; then
      background_process_recovery_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_package_upgrade_task "$user_prompt"; then
      local_package_upgrade_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_long_running_command_polling_task "$user_prompt"; then
      long_running_command_polling_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_filesystem_mutation_task "$user_prompt"; then
      filesystem_mutation_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_rollback_task "$user_prompt"; then
      remote_boundary_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_rollout_task "$user_prompt"; then
      remote_boundary_rollout_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_bastion_cutover_task "$user_prompt"; then
      remote_bastion_cutover_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_multi_host_rollout_task "$user_prompt"; then
      remote_multi_host_rollout_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_multi_host_task "$user_prompt"; then
      remote_multi_host_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$remote_multi_host_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_deploy_rollback_task "$user_prompt"; then
      remote_deploy_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$remote_multi_host_prompt" != "1" ] && [ "$remote_deploy_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_single_host_task "$user_prompt"; then
      remote_single_host_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_service_restart_task "$user_prompt"; then
      local_service_restart_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_intent_clarify "$user_prompt"; then
      freeform_clarify_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_reflection "$user_prompt"; then
      freeform_reflection_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_frame "$user_prompt"; then
      freeform_frame_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_reasoning_completion "$user_prompt" && ! prompt_requires_code_implementation "$user_prompt"; then
      rich_reasoning_prompt=1
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_reasoning_reply "$user_prompt"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ -n "$conv_dir" ] && [ -d "$conv_dir" ] \
      && freeform_clarify_reply_prefers_reasoning "$user_prompt"; then
      prior_freeform_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
      if assistant_output_is_freeform_clarify_question "$prior_freeform_assistant_text"; then
        freeform_reasoning_prompt=1
        freeform_post_clarify_prompt=1
        rich_reasoning_prompt=1
        rich_reasoning_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
        simple_direct_prompt=0
      fi
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reflection_after_clarify "$user_prompt" "$conv_dir"; then
      freeform_reflection_prompt=1
      freeform_reflection_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_frame_after_clarify "$user_prompt" "$conv_dir"; then
      freeform_frame_prompt=1
      freeform_frame_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reflection_after_frame "$user_prompt" "$conv_dir"; then
      freeform_reflection_prompt=1
      freeform_reflection_context_text=$(reasoning_freeform_post_frame_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reasoning_after_frame "$user_prompt" "$conv_dir"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$(reasoning_freeform_post_frame_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reasoning_followup_memo "$user_prompt" "$conv_dir"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$(reasoning_freeform_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_reasoning_followup_contract "$user_prompt" "$conv_dir"; then
      reasoning_followup_prompt=1
      reasoning_followup_context_text=$(reasoning_context_prompt "$user_prompt" "$conv_dir")
      freeform_reasoning_prompt=0
      freeform_clarify_prompt=0
      freeform_reflection_prompt=0
      freeform_frame_prompt=0
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$reasoning_followup_context_text
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$freeform_reasoning_prompt" = "1" ] \
      && [ -n "$conv_dir" ] && [ -d "$conv_dir" ] \
      && freeform_clarify_reply_prefers_reasoning "$user_prompt"; then
      prior_freeform_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
      if assistant_output_is_freeform_clarify_question "$prior_freeform_assistant_text"; then
        freeform_post_clarify_prompt=1
        rich_reasoning_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      fi
    fi
    if requires_agent_execution_prompt "$user_prompt"; then
      force_agent_execution=1
    fi
    case "$(printf '%s' "$advanced_loop_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on)
        quick_mode=0
        ;;
      0|false|no|off)
        quick_mode=1
        ;;
    esac
    if [ "$simple_direct_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$compact_reasoning_prompt" = "1" ] && [ "$run_mode" = "auto" ]; then
      quick_mode=1
    fi
    if [ "$freeform_clarify_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$freeform_reflection_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$freeform_frame_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$rich_reasoning_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$force_agent_execution" = "1" ]; then
      quick_mode=0
    fi
    case "$run_mode" in
      instant)
        quick_mode=1
        ;;
      auto)
        ;;
      programming)
        quick_mode=0
        force_agent_execution=1
        ;;
      pentest)
        quick_mode=0
        force_agent_execution=1
        ;;
      security-audit)
        quick_mode=0
        force_agent_execution=1
        ;;
      chat)
        quick_mode=1
        ;;
      report)
        quick_mode=0
        force_agent_execution=1
        ;;
      text-perfecter)
        quick_mode=0
        force_agent_execution=1
        ;;
      gui-testing)
        quick_mode=0
        force_agent_execution=1
        ;;
      teacher)
        quick_mode=0
        force_agent_execution=1
        ;;
      assistant)
        quick_mode=0
        force_agent_execution=1
        ;;
    esac
    if [ "$assay_run_profile" -eq 1 ]; then
      # Assay runs must exercise the full loop for comparable intelligence/flow scoring.
      quick_mode=0
      force_agent_execution=1
    fi
    if [ "$assay_run_profile" -ne 1 ] && [ "$compact_reasoning_prompt" = "1" ]; then
      # Compact reasoning contracts are explicit no-tool synthesis requests.
      # Enforce the deterministic quick path even if UI or queue metadata drifted
      # into a long-loop mode; otherwise the run can thrash or surface tool plans.
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$document_revision_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$diagram_annotation_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$dashboard_chart_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$before_after_ui_delta_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$terminal_state_recovery_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$terminal_screenshot_debug_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$gui_screenshot_layout_triage_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$repo_runtime_web_triage_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$browser_image_run_investigation_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$tool_failure_handoff_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$current_api_migration_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$current_ops_guidance_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
