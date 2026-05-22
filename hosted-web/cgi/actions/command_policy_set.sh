# action: command_policy_set
    workspace_id=$(trim "$(param "workspace_id")")
    mode=$(trim "$(param "mode")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
      none|ask|ask-all|ask-some|all)
        mode=$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')
        ;;
      *)
        emit_error "invalid mode"
        exit 0
        ;;
    esac
    set_command_policy_mode_for_workspace "$workspace_id" "$mode"
    mode=$(command_policy_mode_for_workspace "$workspace_id")
    printf '{"success":true,"mode":"%s"}\n' "$(json_escape "$mode")"
    exit 0
