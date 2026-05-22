# action: command_policy_get
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
    mode=$(command_policy_mode_for_workspace "$workspace_id")
    printf '{"success":true,"mode":"%s"}\n' "$(json_escape "$mode")"
    exit 0
