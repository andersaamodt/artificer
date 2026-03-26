# action: terminal_session_input
    workspace_id=$(trim "$(param "workspace_id")")
    session_id=$(trim "$(param "session_id")")
    input_text=$(param "input")

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
      emit_error "terminal session changed"
      exit 0
    fi
    if ! terminal_session_running_for_workspace "$workspace_id"; then
      emit_error "terminal session is not running"
      exit 0
    fi

    input_fifo=$(terminal_session_input_fifo_for_workspace "$workspace_id")
    if [ ! -p "$input_fifo" ]; then
      emit_error "terminal session input is unavailable"
      exit 0
    fi

    if [ -n "$input_text" ]; then
      set +e
      printf '%s' "$input_text" > "$input_fifo"
      write_rc=$?
      set -e
      if [ "$write_rc" -ne 0 ]; then
        emit_error "could not send terminal input"
        exit 0
      fi
    fi

    printf '{"success":true}\n'
    exit 0
