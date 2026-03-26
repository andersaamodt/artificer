# action: terminal_session_stop
    workspace_id=$(trim "$(param "workspace_id")")
    session_id=$(trim "$(param "session_id")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$session_id"; then
      emit_error "invalid session_id"
      exit 0
    fi
    current_id=$(terminal_session_id_for_workspace "$workspace_id")
    if [ "$current_id" = "$session_id" ]; then
      terminal_session_cleanup_for_workspace "$workspace_id"
    fi
    printf '{"success":true}\n'
    exit 0
