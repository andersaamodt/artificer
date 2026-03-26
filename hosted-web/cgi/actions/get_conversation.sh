# action: get_conversation
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi
    seed_missing_initial_message_if_needed "$conv_dir"

    title=$(read_file_line "$conv_dir/title" "Conversation")
    model=$(read_file_line "$conv_dir/model" "$(default_model)")

    title_json=$(json_escape "$title")
    model_json=$(json_escape "$model")
    conversation_id_json=$(json_escape "$conversation_id")
    decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
    approval_request_json=$(approval_request_json_for_conversation "$conv_dir")
    draft_file=$(conversation_draft_file_for "$workspace_id" "$conversation_id")
    draft_text=$(cat "$draft_file" 2>/dev/null || true)
    draft_json=$(json_escape "$draft_text")

    printf '{"success":true,"conversation":{"id":"%s","title":"%s","model":"%s","decision_request":%s,"approval_request":%s,"draft":"%s","messages":' \
      "$conversation_id_json" "$title_json" "$model_json" "$decision_request_json" "$approval_request_json" "$draft_json"
    json_messages "$conv_dir"
    printf ',"run_events":'
    json_run_events_with_active "$conv_dir"
    printf '}}\n'
    exit 0
