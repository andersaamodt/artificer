# action: control_plane_automations
    op=$(trim "$(param "op")")
    automation_id=$(trim "$(param "automation_id")")

    case "$op" in
      ""|list)
        printf '{"success":true,"api_version":"%s","automations":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" "$(automations_state_json)"
        ;;
      get)
        if ! valid_id "$automation_id"; then
          emit_error "invalid automation_id"
          exit 0
        fi
        automation_json=$(automation_json_for_id "$automation_id" 2>/dev/null || true)
        if [ -z "$(trim "$automation_json")" ]; then
          emit_error "automation not found"
          exit 0
        fi
        printf '{"success":true,"api_version":"%s","automation":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" "$automation_json"
        ;;
      upsert)
        control_plane_call_action_post_json "automation_upsert" \
          "automation_id" "$automation_id" \
          "name" "$(param "name")" \
          "workspace_id" "$(trim "$(param "workspace_id")")" \
          "conversation_id" "$(trim "$(param "conversation_id")")" \
          "prompt" "$(param "prompt")" \
          "schedule_kind" "$(trim "$(param "schedule_kind")")" \
          "schedule_value" "$(trim "$(param "schedule_value")")" \
          "enabled" "$(trim "$(param "enabled")")" \
          "allow_self_reschedule" "$(trim "$(param "allow_self_reschedule")")" \
          "run_mode" "$(trim "$(param "run_mode")")" \
          "assistant_mode_id" "$(trim "$(param "assistant_mode_id")")" \
          "compute_budget" "$(trim "$(param "compute_budget")")" \
          "command_exec_mode" "$(trim "$(param "command_exec_mode")")" \
          "permission_mode" "$(trim "$(param "permission_mode")")" \
          "programmer_review" "$(trim "$(param "programmer_review")")" \
          "programmer_review_rounds" "$(trim "$(param "programmer_review_rounds")")" \
          "assay_task_id" "$(trim "$(param "assay_task_id")")" \
          "explicit_skill_ids" "$(param "explicit_skill_ids")" \
          "next_run" "$(trim "$(param "next_run")")"
        ;;
      toggle)
        control_plane_call_action_post_json "automation_toggle" "automation_id" "$automation_id" "enabled" "$(trim "$(param "enabled")")"
        ;;
      run-now)
        control_plane_call_action_post_json "automation_run_now" "automation_id" "$automation_id"
        ;;
      delete)
        control_plane_call_action_post_json "automation_delete" "automation_id" "$automation_id"
        ;;
      *)
        emit_error "unsupported control_plane_automations op"
        ;;
    esac
    exit 0
