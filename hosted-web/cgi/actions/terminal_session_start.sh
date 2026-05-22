# action: terminal_session_start
    workspace_id=$(trim "$(param "workspace_id")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    workspace_path=$(workspace_path_for_id "$workspace_id")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi

    set +e
    session_id=$(terminal_session_start_for_workspace "$workspace_id" "$workspace_path" 2>/dev/null)
    start_rc=$?
    set -e
    if [ "$start_rc" -ne 0 ] || [ -z "$session_id" ]; then
      emit_error "could not start terminal session"
      exit 0
    fi

    output_file=$(terminal_session_output_file_for_workspace "$workspace_id")
    output_delta_json=$(terminal_output_delta_json "$output_file" "0")
    printf '{"success":true,"session_id":"%s","running":true,%s}\n' \
      "$(json_escape "$session_id")" \
      "$(printf '%s' "$output_delta_json" | sed 's/^{//;s/}$//')"
    exit 0
