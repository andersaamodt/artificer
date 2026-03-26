# action: command_approval_save
    workspace_id=$(trim "$(param "workspace_id")")
    command_text=$(normalize_rule_field "$(param "command")")
    decision=$(trim "$(param "decision")")
    scope=$(trim "$(param "scope")")
    match_mode=$(trim "$(param "match_mode")")
    pattern=$(normalize_rule_field "$(param "pattern")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    case "$decision" in
      allow|deny) ;;
      *) emit_error "invalid decision"; exit 0 ;;
    esac
    case "$scope" in
      once|remember) ;;
      *) scope="once" ;;
    esac
    case "$match_mode" in
      exact|regex) ;;
      *) match_mode="exact" ;;
    esac
    if [ -z "$command_text" ]; then
      emit_error "command is required"
      exit 0
    fi
    if [ "$match_mode" = "exact" ]; then
      pattern=$command_text
    fi
    if [ "$match_mode" = "regex" ] && [ -z "$pattern" ]; then
      pattern=$(command_text_to_rule_pattern_default "$command_text")
    fi

    append_command_rule "$workspace_id" "$scope" "$decision" "$match_mode" "$pattern"
    printf '{"success":true,"saved":true}\n'
    exit 0
