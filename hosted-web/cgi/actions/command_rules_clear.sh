# action: command_rules_clear
    workspace_id=$(trim "$(param "workspace_id")")
    scope=$(trim "$(param "scope")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    ensure_command_policy_layout "$workspace_id"
    case "$scope" in
      remember)
        : > "$(command_policy_rules_file_for "$workspace_id")"
        ;;
      once)
        : > "$(command_policy_once_rules_file_for "$workspace_id")"
        ;;
      all)
        : > "$(command_policy_rules_file_for "$workspace_id")"
        : > "$(command_policy_once_rules_file_for "$workspace_id")"
        ;;
      *)
        emit_error "invalid scope"
        exit 0
        ;;
    esac
    printf '{"success":true,"cleared":true}\n'
    exit 0
