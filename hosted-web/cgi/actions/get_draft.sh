# action: get_draft
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

    draft_file=$(workspace_draft_file_for "$workspace_id")
    draft_text=$(cat "$draft_file" 2>/dev/null || true)
    draft_json=$(json_escape "$draft_text")
    printf '{"success":true,"draft":"%s"}\n' "$draft_json"
    exit 0
