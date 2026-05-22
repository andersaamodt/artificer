# action: multi_agent_interpretation_add
    workspace_id=$(trim "$(param "workspace_id")")
    statement=$(trim "$(param "statement")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -z "$statement" ]; then
      emit_error "statement is required"
      exit 0
    fi
    entry_id=$(ma_add_interpretation_entry "$workspace_id" "$statement")
    printf '{"success":true,"entry_id":"%s","workspace_multi_agent":%s}\n' "$(json_escape "$entry_id")" "$(ma_workspace_state_json "$workspace_id")"
    exit 0
