# action: git_init
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
    init_raw=$(run_artificer_git init "$workspace_path" 2>&1)
    init_rc=$?
    set -e
    if [ "$init_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$init_raw")"
      exit 0
    fi

    message_json=$(json_escape "$(strip_terminal_noise "$init_raw")")
    printf '{"success":true,"message":"%s"}\n' "$message_json"
    exit 0
