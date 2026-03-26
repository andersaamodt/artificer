"
        fi
        assistant_raw=$(current_api_migration_summary \
          "$current_api_repo_output" \
          "$current_api_doc_url" \
          "$current_api_doc_excerpt")
        model_rc=0
      elif [ "$use_current_ops_guidance_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded current ops guidance fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/state-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        current_ops_state_output=$quick_mode_last_command_output
        current_ops_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        current_ops_doc_excerpt=""
        if [ -n "$current_ops_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $current_ops_doc_url"
          current_ops_doc_excerpt=$(fetch_url_text_excerpt "$current_ops_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $current_ops_doc_url
$(printf '%s' "$current_ops_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(current_ops_guidance_summary \
          "$current_ops_state_output" \
          "$current_ops_doc_url" \
          "$current_ops_doc_excerpt")
        model_rc=0
      elif [ "$use_multi_artifact_judgment_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic multi-artifact judgment fast path."
        assistant_raw=$(multi_artifact_judgment_summary "$user_prompt")
        model_rc=0
      elif [ "$use_standards_grounded_answer_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded standards-grounded answer fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/repo-scan.sh" "all" "$blocked_commands_file" "$stream_output_file"
        standards_repo_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/runtime-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        standards_runtime_status=$quick_mode_last_command_status
        standards_runtime_output=$quick_mode_last_command_output
        standards_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        standards_doc_excerpt=""
        if [ -n "$standards_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $standards_doc_url"
          standards_doc_excerpt=$(fetch_url_text_excerpt "$standards_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $standards_doc_url
$(printf '%s' "$standards_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(standards_grounded_answer_summary \
          "$standards_repo_output" \
          "$standards_runtime_output" \
          "$standards_runtime_status" \
          "$standards_doc_url" \
          "$standards_doc_excerpt")
        model_rc=0
      elif [ "$use_gui_screenshot_layout_triage_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached screenshot triage."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_repo_runtime_web_triage_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic repo/runtime/web triage fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/repo-scan.sh" "all" "$blocked_commands_file" "$stream_output_file"
        repo_runtime_repo_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/runtime-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        repo_runtime_runtime_status=$quick_mode_last_command_status
        repo_runtime_runtime_output=$quick_mode_last_command_output
        repo_runtime_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        repo_runtime_doc_excerpt=""
        if [ -n "$repo_runtime_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $repo_runtime_doc_url"
          repo_runtime_doc_excerpt=$(fetch_url_text_excerpt "$repo_runtime_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $repo_runtime_doc_url
$(printf '%s' "$repo_runtime_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(repo_runtime_web_triage_summary \
          "$repo_runtime_repo_output" \
          "$repo_runtime_runtime_output" \
          "$repo_runtime_runtime_status" \
          "$repo_runtime_doc_url" \
          "$repo_runtime_doc_excerpt")
        model_rc=0
      elif [ "$use_multi_service_partial_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic multi-service partial rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-api.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_api_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-worker.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_worker_status_output=$quick_mode_last_command_output
        if multi_service_partial_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/multi-service.env to approve one shared rollback, restore the stable API and worker release/mode state, and keep the rollback read-only.
"
          stream_emit_line "$stream_output_file" "Quick-mode multi-service fix: rewrote state/multi-service.env for the bounded API-plus-worker rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/multi-service.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode multi-service fix failed: could not rewrite state/multi-service.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback-api.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_api_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback-worker.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_worker_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_health_status=$quick_mode_last_command_status
        multi_service_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_verify_status=$quick_mode_last_command_status
        multi_service_verify_output=$quick_mode_last_command_output
        assistant_raw=$(multi_service_partial_rollback_summary \
          "$multi_service_api_status_output" \
          "$multi_service_worker_status_output" \
          "$multi_service_api_rollback_output" \
          "$multi_service_worker_rollback_output" \
          "$multi_service_health_output" \
          "$multi_service_health_status" \
          "$multi_service_verify_output" \
          "$multi_service_verify_status")
        model_rc=0
      elif [ "$use_system_release_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic system release pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_core_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_edge_status_output=$quick_mode_last_command_output
        if system_release_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/release-pack.env to approve one shared release pack, mark the core and edge boundaries ready, preserve the current and target release values, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-release fix: rewrote state/release-pack.env for the bounded core-plus-edge release pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/release-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-release fix failed: could not rewrite state/release-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_core_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_edge_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/publish-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_publish_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_verify_status=$quick_mode_last_command_status
        system_release_verify_output=$quick_mode_last_command_output
        assistant_raw=$(system_release_pack_summary \
          "$system_release_core_status_output" \
          "$system_release_edge_status_output" \
          "$system_release_core_cutover_output" \
          "$system_release_edge_cutover_output" \
          "$system_release_publish_output" \
          "$system_release_verify_output" \
          "$system_release_verify_status")
        model_rc=0
      elif [ "$use_system_boundary_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic system boundary pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_core_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_edge_status_output=$quick_mode_last_command_output
        if system_boundary_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/boundary-pack.env to approve one shared cutover, mark the core and edge boundaries ready, preserve the current and target boundary values, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-boundary fix: rewrote state/boundary-pack.env for the bounded core-plus-edge cutover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/boundary-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-boundary fix failed: could not rewrite state/boundary-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_core_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_edge_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-pack.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_verify_status=$quick_mode_last_command_status
        system_boundary_verify_output=$quick_mode_last_command_output
        assistant_raw=$(system_boundary_pack_summary \
          "$system_boundary_core_status_output" \
          "$system_boundary_edge_status_output" \
          "$system_boundary_core_cutover_output" \
          "$system_boundary_edge_cutover_output" \
          "$system_boundary_verify_output" \
          "$system_boundary_verify_status")
        model_rc=0
      elif [ "$use_partial_system_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic partial-system-rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_status_output=$quick_mode_last_command_output
        if partial_system_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/system.env to approve the bounded rollback, restore the stable release/package/worker state, and keep the rollback read-only.
"
          stream_emit_line "$stream_output_file" "Quick-mode rollback fix: rewrote state/system.env for the bounded partial rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/system.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode rollback fix failed: could not rewrite state/system.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_apply_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_health_status=$quick_mode_last_command_status
        partial_rollback_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_verify_status=$quick_mode_last_command_status
        partial_rollback_verify_output=$quick_mode_last_command_output
        assistant_raw=$(partial_system_rollback_summary \
          "$partial_rollback_status_output" \
          "$partial_rollback_apply_output" \
          "$partial_rollback_health_output" \
          "$partial_rollback_health_status" \
          "$partial_rollback_verify_output" \
          "$partial_rollback_verify_status")
        model_rc=0
      elif [ "$use_background_process_recovery_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic background-process recovery fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ps.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_ps_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/stop.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_stop_output=$quick_mode_last_command_output
        if background_process_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote process/worker.env to MODE=healthy, AUTO_START=1, READ_ONLY=1, and preserved the existing QUEUE value for the bounded worker recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode worker fix: rewrote process/worker.env for a bounded worker recovery."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite process/worker.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode worker fix failed: could not rewrite process/worker.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/start.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_start_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_health_status=$quick_mode_last_command_status
        background_process_health_output=$quick_mode_last_command_output
        assistant_raw=$(background_process_recovery_summary \
          "$background_process_ps_output" \
          "$background_process_stop_output" \
          "$background_process_start_output" \
          "$background_process_health_output" \
          "$background_process_health_status")
        model_rc=0
      elif [ "$use_local_env_drift_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local env drift fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/doctor.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_env_doctor_output=$quick_mode_last_command_output
        if local_env_drift_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote config/toolchain.env to align the active tool path, active version, and read-only guard with the expected values.
"
          stream_emit_line "$stream_output_file" "Quick-mode env fix: rewrote config/toolchain.env for the expected toolchain state."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite config/toolchain.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode env fix failed: could not rewrite config/toolchain.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_env_verify_status=$quick_mode_last_command_status
        local_env_verify_output=$quick_mode_last_command_output
        assistant_raw=$(local_env_drift_summary \
          "$local_env_doctor_output" \
          "$local_env_verify_output" \
          "$local_env_verify_status")
        model_rc=0
      elif [ "$use_local_package_upgrade_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local package upgrade fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/audit.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_package_audit_output=$quick_mode_last_command_output
        if local_package_upgrade_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote package.json and package-lock.json to upgrade demo-lib to 2.1.0 and keep the change bounded to the local package manifest/lockfile pair.
"
          stream_emit_line "$stream_output_file" "Quick-mode package fix: rewrote package.json and package-lock.json for the bounded demo-lib upgrade."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite package.json and package-lock.json in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode package fix failed: could not rewrite package.json and package-lock.json."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/test.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_package_test_status=$quick_mode_last_command_status
        local_package_test_output=$quick_mode_last_command_output
        assistant_raw=$(local_package_upgrade_summary \
          "$local_package_audit_output" \
          "$local_package_test_output" \
          "$local_package_test_status")
        model_rc=0
      elif [ "$use_long_running_command_polling_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic long-running command fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_first_poll_output=$quick_mode_last_command_output
        if long_running_command_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote job/run.env to enable checkpointing, allow the bounded finalize step, preserve the target step count, and keep the job read-only during the final polling sequence.
"
          stream_emit_line "$stream_output_file" "Quick-mode long-running fix: rewrote job/run.env for the bounded polling sequence."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite job/run.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode long-running fix failed: could not rewrite job/run.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_second_poll_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/checkpoint.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_checkpoint_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_third_poll_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/finalize.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_finalize_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_verify_status=$quick_mode_last_command_status
        long_running_verify_output=$quick_mode_last_command_output
        assistant_raw=$(long_running_command_summary \
          "$long_running_first_poll_output" \
          "$long_running_second_poll_output" \
          "$long_running_checkpoint_output" \
          "$long_running_third_poll_output" \
          "$long_running_finalize_output" \
          "$long_running_verify_output" \
          "$long_running_verify_status")
        model_rc=0
      elif [ "$use_filesystem_mutation_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic filesystem mutation fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/inventory.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_inventory_output=$quick_mode_last_command_output
        if filesystem_mutation_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/layout.env to approve the bounded archive/promote/link operation, preserve the live/staging/archive paths, and keep the mutation pack read-only during verification.
"
          stream_emit_line "$stream_output_file" "Quick-mode filesystem fix: rewrote state/layout.env for the bounded archive/promote/link operation."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/layout.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode filesystem fix failed: could not rewrite state/layout.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/apply.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_apply_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_verify_status=$quick_mode_last_command_status
        filesystem_verify_output=$quick_mode_last_command_output
        assistant_raw=$(filesystem_mutation_summary \
          "$filesystem_inventory_output" \
          "$filesystem_apply_output" \
          "$filesystem_verify_output" \
          "$filesystem_verify_status")
        model_rc=0
      elif [ "$use_remote_release_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote release pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_status_output=$quick_mode_last_command_output
        if remote_release_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/release-pack.env to approve the shared core and edge target releases, mark the bastion tunnel plus all bounded private-boundary helpers ready, approve release publication, preserve host identities, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote release-pack fix: rewrote remote/release-pack.env for the bounded bastion-plus-core/edge release pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/release-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote release-pack fix failed: could not rewrite remote/release-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_health_status=$quick_mode_last_command_status
        remote_release_pack_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_health_status=$quick_mode_last_command_status
        remote_release_pack_core_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_health_status=$quick_mode_last_command_status
        remote_release_pack_core_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_health_status=$quick_mode_last_command_status
        remote_release_pack_edge_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_health_status=$quick_mode_last_command_status
        remote_release_pack_edge_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/publish-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_publish_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_verify_status=$quick_mode_last_command_status
        remote_release_pack_verify_output=$quick_mode_last_command_output
        assistant_raw=$(remote_release_pack_summary \
          "$remote_release_pack_bastion_status_output" \
          "$remote_release_pack_bastion_tunnel_output" \
          "$remote_release_pack_bastion_health_output" \
          "$remote_release_pack_bastion_health_status" \
          "$remote_release_pack_core_canary_status_output" \
          "$remote_release_pack_core_canary_deploy_output" \
          "$remote_release_pack_core_canary_health_output" \
          "$remote_release_pack_core_canary_health_status" \
          "$remote_release_pack_core_fleet_status_output" \
          "$remote_release_pack_core_fleet_deploy_output" \
          "$remote_release_pack_core_fleet_health_output" \
          "$remote_release_pack_core_fleet_health_status" \
          "$remote_release_pack_edge_canary_status_output" \
          "$remote_release_pack_edge_canary_deploy_output" \
          "$remote_release_pack_edge_canary_health_output" \
          "$remote_release_pack_edge_canary_health_status" \
          "$remote_release_pack_edge_fleet_status_output" \
          "$remote_release_pack_edge_fleet_deploy_output" \
          "$remote_release_pack_edge_fleet_health_output" \
          "$remote_release_pack_edge_fleet_health_status" \
          "$remote_release_pack_publish_output" \
          "$remote_release_pack_verify_output" \
          "$remote_release_pack_verify_status")
        model_rc=0
      elif [ "$use_remote_boundary_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary-pack.env to approve the core and edge target releases, mark the bastion tunnel plus all bounded private-boundary helpers ready, preserve host identities, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary-pack fix: rewrote remote/boundary-pack.env for the bounded bastion-plus-core/edge boundary pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary-pack fix failed: could not rewrite remote/boundary-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_pack_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_health_status=$quick_mode_last_command_status
        remote_boundary_pack_core_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_pack_core_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_health_status=$quick_mode_last_command_status
        remote_boundary_pack_edge_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_pack_edge_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-pack.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_verify_status=$quick_mode_last_command_status
        remote_boundary_pack_verify_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_pack_summary \
          "$remote_boundary_pack_bastion_status_output" \
          "$remote_boundary_pack_bastion_tunnel_output" \
          "$remote_boundary_pack_bastion_health_output" \
          "$remote_boundary_pack_bastion_health_status" \
          "$remote_boundary_pack_core_canary_status_output" \
          "$remote_boundary_pack_core_canary_deploy_output" \
          "$remote_boundary_pack_core_canary_health_output" \
          "$remote_boundary_pack_core_canary_health_status" \
          "$remote_boundary_pack_core_fleet_status_output" \
          "$remote_boundary_pack_core_fleet_deploy_output" \
          "$remote_boundary_pack_core_fleet_health_output" \
          "$remote_boundary_pack_core_fleet_health_status" \
          "$remote_boundary_pack_edge_canary_status_output" \
          "$remote_boundary_pack_edge_canary_deploy_output" \
          "$remote_boundary_pack_edge_canary_health_output" \
          "$remote_boundary_pack_edge_canary_health_status" \
          "$remote_boundary_pack_edge_fleet_status_output" \
          "$remote_boundary_pack_edge_fleet_deploy_output" \
          "$remote_boundary_pack_edge_fleet_health_output" \
          "$remote_boundary_pack_edge_fleet_health_status" \
          "$remote_boundary_pack_verify_output" \
          "$remote_boundary_pack_verify_status")
        model_rc=0
      elif [ "$use_remote_boundary_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary.env to approve the stable release, mark the bastion tunnel plus private canary/fleet rollbacks ready, preserve host identities, and keep the bounded rollback read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary rollback fix: rewrote remote/boundary.env for the bounded bastion-plus-private rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary rollback fix failed: could not rewrite remote/boundary.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh rollback" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_health_status=$quick_mode_last_command_status
        remote_boundary_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh rollback" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_rollback_summary \
          "$remote_boundary_bastion_status_output" \
          "$remote_boundary_bastion_tunnel_output" \
          "$remote_boundary_bastion_health_output" \
          "$remote_boundary_bastion_health_status" \
          "$remote_boundary_canary_status_output" \
          "$remote_boundary_canary_rollback_output" \
          "$remote_boundary_canary_health_output" \
          "$remote_boundary_canary_health_status" \
          "$remote_boundary_fleet_status_output" \
          "$remote_boundary_fleet_rollback_output" \
          "$remote_boundary_fleet_health_output" \
          "$remote_boundary_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_boundary_rollout_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary rollout fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_rollout_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary.env to approve the target release, mark the bastion tunnel plus private canary/fleet targets ready, preserve host identities, and keep the bounded rollout read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary fix: rewrote remote/boundary.env for the bounded bastion-plus-private rollout."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary fix failed: could not rewrite remote/boundary.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_health_status=$quick_mode_last_command_status
        remote_boundary_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_rollout_summary \
          "$remote_boundary_bastion_status_output" \
          "$remote_boundary_bastion_tunnel_output" \
          "$remote_boundary_bastion_health_output" \
          "$remote_boundary_bastion_health_status" \
          "$remote_boundary_canary_status_output" \
          "$remote_boundary_canary_deploy_output" \
          "$remote_boundary_canary_health_output" \
          "$remote_boundary_canary_health_status" \
          "$remote_boundary_fleet_status_output" \
          "$remote_boundary_fleet_deploy_output" \
          "$remote_boundary_fleet_health_output" \
          "$remote_boundary_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_bastion_cutover_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote bastion cutover fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_status_output=$quick_mode_last_command_output
        if remote_bastion_cutover_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/bastion.env to approve the target private host, mark the bastion and target host ready, preserve the bastion host identity, and keep the bounded cutover read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote bastion fix: rewrote remote/bastion.env for the bounded bastion cutover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/bastion.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote bastion fix failed: could not rewrite remote/bastion.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_health_status=$quick_mode_last_command_status
        remote_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh cutover" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_health_status=$quick_mode_last_command_status
        remote_private_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_bastion_cutover_summary \
          "$remote_bastion_status_output" \
          "$remote_private_status_output" \
          "$remote_bastion_tunnel_output" \
          "$remote_bastion_health_output" \
          "$remote_bastion_health_status" \
          "$remote_private_cutover_output" \
          "$remote_private_health_output" \
          "$remote_private_health_status")
        model_rc=0
      elif [ "$use_remote_multi_host_rollout_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote multi-host rollout fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_status_output=$quick_mode_last_command_output
        if remote_multi_host_rollout_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/rollout.env to approve the target release, mark the canary and fleet hosts ready, preserve host identities, and keep the bounded staged rollout read-only during deployment.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote rollout fix: rewrote remote/rollout.env for the bounded staged rollout."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/rollout.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote rollout fix failed: could not rewrite remote/rollout.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_health_status=$quick_mode_last_command_status
        remote_rollout_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_health_status=$quick_mode_last_command_status
        remote_rollout_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_multi_host_rollout_summary \
          "$remote_rollout_canary_status_output" \
          "$remote_rollout_fleet_status_output" \
          "$remote_rollout_canary_deploy_output" \
          "$remote_rollout_canary_health_output" \
          "$remote_rollout_canary_health_status" \
          "$remote_rollout_fleet_deploy_output" \
          "$remote_rollout_fleet_health_output" \
          "$remote_rollout_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_multi_host_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote multi-host fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_status_output=$quick_mode_last_command_output
        if remote_multi_host_failover_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/topology.env to promote the replica host, point the app host at the new primary, preserve host identities, and keep the bounded failover read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote multi-host fix: rewrote remote/topology.env for the bounded failover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/topology.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote multi-host fix failed: could not rewrite remote/topology.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh promote" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_promote_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_health_status=$quick_mode_last_command_status
        remote_multi_host_db_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh restart" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_health_status=$quick_mode_last_command_status
        remote_multi_host_app_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_multi_host_replica_summary \
          "$remote_multi_host_app_status_output" \
          "$remote_multi_host_db_status_output" \
          "$remote_multi_host_db_promote_output" \
          "$remote_multi_host_db_health_output" \
          "$remote_multi_host_db_health_status" \
          "$remote_multi_host_app_restart_output" \
          "$remote_multi_host_app_health_output" \
          "$remote_multi_host_app_health_status")
        model_rc=0
      elif [ "$use_remote_deploy_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote deploy fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_status_output=$quick_mode_last_command_output
        if remote_deploy_release_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/release.env to approve the target release, mark the deploy ready, and preserve the existing remote host binding for the bounded deploy.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote deploy fix: rewrote remote/release.env for the bounded release deployment."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/release.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote deploy fix failed: could not rewrite remote/release.env."
        fi
