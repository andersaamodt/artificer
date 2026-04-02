# action: control_plane_sessions
    op=$(trim "$(param "op")")
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    title=$(trim "$(param "title")")
    model=$(trim "$(param "model")")
    prompt_text=$(param "prompt")
    position=$(trim "$(param "position")")
    attachments=$(param "attachments")
    run_mode=$(trim "$(param "run_mode")")
    assistant_mode_id=$(trim "$(param "assistant_mode_id")")
    compute_budget=$(trim "$(param "compute_budget")")
    command_exec_mode=$(trim "$(param "command_exec_mode")")
    permission_mode=$(trim "$(param "permission_mode")")
    reflexive_knowledge=$(trim "$(param "reflexive_knowledge")")
    self_actuation=$(trim "$(param "self_actuation")")
    programmer_review=$(trim "$(param "programmer_review")")
    programmer_review_rounds=$(trim "$(param "programmer_review_rounds")")
    assay_task_id=$(trim "$(param "assay_task_id")")
    explicit_skill_ids=$(param "explicit_skill_ids")
    offset=$(trim "$(param "offset")")

    case "$op" in
      ""|list)
        control_plane_sessions_list_json "$workspace_id"
        ;;
      get)
        if ! valid_workspace_id "$workspace_id" || ! valid_id "$conversation_id"; then
          emit_error "invalid session coordinates"
          exit 0
        fi
        session_json=$(control_plane_session_object_json "$workspace_id" "$conversation_id" 1 1 || true)
        if [ -z "$session_json" ]; then
          emit_error "session not found"
          exit 0
        fi
        printf '{"success":true,"api_version":"%s","session":%s}\n' "$(json_escape "$(control_plane_api_version)")" "$session_json"
        ;;
      create)
        create_json=$(control_plane_call_action_post_json "new_conversation" "workspace_id" "$workspace_id" "title" "$title" "model" "$model")
        if ! control_plane_json_success "$create_json"; then
          printf '%s\n' "$create_json"
          exit 0
        fi
        created_conversation_id=$(control_plane_json_extract_scalar "$create_json" '((data.get("conversation") or {}).get("id") or "")')
        session_json=$(control_plane_session_object_json "$workspace_id" "$created_conversation_id" 1 1 || true)
        printf '{"success":true,"api_version":"%s","session":%s}\n' "$(json_escape "$(control_plane_api_version)")" "$session_json"
        ;;
      archive)
        archive_json=$(control_plane_call_action_post_json "archive_conversation" "workspace_id" "$workspace_id" "conversation_id" "$conversation_id")
        printf '%s\n' "$archive_json"
        ;;
      message)
        enqueue_json=$(control_plane_call_action_post_json "queue_enqueue" \
          "workspace_id" "$workspace_id" \
          "conversation_id" "$conversation_id" \
          "prompt" "$prompt_text" \
          "position" "$position" \
          "attachments" "$attachments" \
          "run_mode" "$run_mode" \
          "assistant_mode_id" "$assistant_mode_id" \
          "compute_budget" "$compute_budget" \
          "command_exec_mode" "$command_exec_mode" \
          "permission_mode" "$permission_mode" \
          "reflexive_knowledge" "$reflexive_knowledge" \
          "self_actuation" "$self_actuation" \
          "programmer_review" "$programmer_review" \
          "programmer_review_rounds" "$programmer_review_rounds" \
          "assay_task_id" "$assay_task_id" \
          "explicit_skill_ids" "$explicit_skill_ids")
        if ! control_plane_json_success "$enqueue_json"; then
          printf '%s\n' "$enqueue_json"
          exit 0
        fi
        item_id=$(control_plane_json_extract_scalar "$enqueue_json" 'data.get("item_id", "")')
        session_json=$(control_plane_session_object_json "$workspace_id" "$conversation_id" 1 1 || true)
        printf '{"success":true,"api_version":"%s","item_id":"%s","session":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" \
          "$(json_escape "$item_id")" \
          "$session_json"
        ;;
      events)
        if ! valid_workspace_id "$workspace_id" || ! valid_id "$conversation_id"; then
          emit_error "invalid session coordinates"
          exit 0
        fi
        conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
        if [ ! -d "$conv_dir" ]; then
          emit_error "session not found"
          exit 0
        fi
        printf '{"success":true,"api_version":"%s","session_id":"%s","trace":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" \
          "$(json_escape "$conversation_id")" \
          "$(control_plane_trace_json_for_conversation "$conv_dir" 1)"
        ;;
      stream)
        control_plane_call_action_get_json "run_stream_poll" "workspace_id" "$workspace_id" "conversation_id" "$conversation_id" "stream_session" "$(trim "$(param "stream_session")")" "offset" "$offset"
        ;;
      *)
        emit_error "unsupported control_plane_sessions op"
        ;;
    esac
    exit 0
