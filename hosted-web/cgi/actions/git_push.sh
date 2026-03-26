# action: git_push
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
    push_raw=$(run_artificer_git push "$workspace_path" 2>&1)
    push_rc=$?
    set -e
    if [ "$push_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$push_raw")"
      exit 0
    fi

    output_json=$(json_escape "$(strip_terminal_noise "$push_raw")")
    printf '{"success":true,"output":"%s"}\n' "$output_json"
    exit 0
