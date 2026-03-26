# action: get_conversation_draft
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

    draft_file=$(conversation_draft_file_for "$workspace_id" "$conversation_id")
    draft_text=$(cat "$draft_file" 2>/dev/null || true)
    draft_json=$(json_escape "$draft_text")
    printf '{"success":true,"draft":"%s"}\n' "$draft_json"
    exit 0
