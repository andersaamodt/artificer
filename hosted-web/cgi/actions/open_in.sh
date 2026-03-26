# action: open_in
    workspace_id=$(trim "$(param "workspace_id")")
    target=$(trim "$(param "target")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    case "$target" in
      finder|terminal|textmate) ;;
      *)
        emit_error "invalid open target"
        exit 0
        ;;
    esac

    workspace_path=$(workspace_path_for_id "$workspace_id")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi

    set +e
    open_raw=$(run_artificer_git open "$workspace_path" "$target" 2>&1)
    open_rc=$?
    set -e
    if [ "$open_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$open_raw")"
      exit 0
    fi

    emit_ok_message "opened"
    exit 0
