# action: multi_agent_log_delete
    workspace_id=$(trim "$(param "workspace_id")")
    log_kind=$(trim "$(param "log_kind")")
    entry_id=$(trim "$(param "entry_id")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$entry_id"; then
      emit_error "invalid entry_id"
      exit 0
    fi
    if ! ma_delete_workspace_log_entry "$workspace_id" "$log_kind" "$entry_id"; then
      emit_error "entry not found"
      exit 0
    fi
    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
