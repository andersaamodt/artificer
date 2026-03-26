# action: terminal_session_poll
    workspace_id=$(trim "$(param "workspace_id")")
    session_id=$(trim "$(param "session_id")")
    offset_raw=$(trim "$(param "offset")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$session_id"; then
      emit_error "invalid session_id"
      exit 0
    fi

    current_id=$(terminal_session_id_for_workspace "$workspace_id")
    if [ "$current_id" != "$session_id" ]; then
      printf '{"success":true,"session_changed":true,"running":false,"delta":"","offset":0}\n'
      exit 0
    fi

    output_file=$(terminal_session_output_file_for_workspace "$workspace_id")
    running=false
    if terminal_session_running_for_workspace "$workspace_id"; then
      running=true
    fi
    output_delta_json=$(terminal_output_delta_json "$output_file" "$offset_raw")
    printf '{"success":true,"session_changed":false,"running":%s,%s}\n' \
      "$running" \
      "$(printf '%s' "$output_delta_json" | sed 's/^{//;s/}$//')"
    exit 0
