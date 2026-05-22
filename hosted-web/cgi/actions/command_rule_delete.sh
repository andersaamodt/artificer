# action: command_rule_delete
    workspace_id=$(trim "$(param "workspace_id")")
    scope=$(trim "$(param "scope")")
    index_raw=$(trim "$(param "index")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    case "$scope" in
      remember|once) ;;
      *) emit_error "invalid scope"; exit 0 ;;
    esac
    if ! delete_command_rule_by_index "$workspace_id" "$scope" "$index_raw"; then
      emit_error "rule not found"
      exit 0
    fi
    printf '{"success":true,"deleted":true}\n'
    exit 0
