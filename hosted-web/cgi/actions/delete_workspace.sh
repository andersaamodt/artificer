# action: delete_workspace
    workspace_id=$(trim "$(param "workspace_id")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi

    rm -rf "$ws_dir"
    emit_ok_message "workspace deleted"
    exit 0
