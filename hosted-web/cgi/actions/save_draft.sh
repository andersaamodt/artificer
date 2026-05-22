# action: save_draft
    workspace_id=$(trim "$(param "workspace_id")")
    draft_text=$(param "draft")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi

    draft_file=$(workspace_draft_file_for "$workspace_id")
    if [ -z "$(trim "$draft_text")" ]; then
      rm -f "$draft_file"
    else
      printf '%s' "$draft_text" > "$draft_file"
    fi

    emit_ok_message "draft saved"
    exit 0
