# action: save_conversation_draft
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    draft_text=$(param "draft")

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
    if [ -z "$(trim "$draft_text")" ]; then
      rm -f "$draft_file"
    else
      printf '%s' "$draft_text" > "$draft_file"
    fi

    emit_ok_message "conversation draft saved"
    exit 0
