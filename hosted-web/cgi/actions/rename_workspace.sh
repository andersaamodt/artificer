# action: rename_workspace
    workspace_id=$(trim "$(param "workspace_id")")
    workspace_name=$(trim "$(param "name")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi

    if [ -z "$workspace_name" ]; then
      emit_error "name is required"
      exit 0
    fi

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi

    printf '%s\n' "$workspace_name" > "$ws_dir/name"

    workspace_id_json=$(json_escape "$workspace_id")
    workspace_name_json=$(json_escape "$workspace_name")
    printf '{"success":true,"workspace":{"id":"%s","name":"%s"}}\n' \
      "$workspace_id_json" "$workspace_name_json"
    exit 0
