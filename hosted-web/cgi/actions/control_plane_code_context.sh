# action: control_plane_code_context
    op=$(trim "$(param "op")")
    workspace_id=$(trim "$(param "workspace_id")")
    requested_path=$(trim "$(param "path")")
    case "$op" in
      ""|file)
        artificer_code_context_action_json "$workspace_id" "$requested_path"
        ;;
      *)
        emit_error "unsupported control_plane_code_context op"
        ;;
    esac
    exit 0
