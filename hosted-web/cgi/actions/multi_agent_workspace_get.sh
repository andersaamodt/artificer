# action: multi_agent_workspace_get
    workspace_id=$(trim "$(param "workspace_id")")
    if ! valid_workspace_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    if ! command -v ma_workspace_state_json >/dev/null 2>&1; then
      emit_error "Multi-agent runtime is unavailable"
      exit 0
    fi
    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
