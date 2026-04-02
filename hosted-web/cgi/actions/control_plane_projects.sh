# action: control_plane_projects
    op=$(trim "$(param "op")")
    workspace_id=$(trim "$(param "workspace_id")")
    workspace_name=$(trim "$(param "name")")
    workspace_path=$(trim "$(param "path")")
    command_exec_mode=$(trim "$(param "command_exec_mode")")

    case "$op" in
      ""|list)
        control_plane_projects_list_json
        ;;
      get)
        control_plane_project_get_json "$workspace_id"
        ;;
      add)
        control_plane_call_action_post_json "add_workspace" "path" "$workspace_path" "name" "$workspace_name" "command_exec_mode" "$command_exec_mode"
        ;;
      rename)
        control_plane_call_action_post_json "rename_workspace" "workspace_id" "$workspace_id" "name" "$workspace_name"
        ;;
      delete)
        control_plane_call_action_post_json "delete_workspace" "workspace_id" "$workspace_id"
        ;;
      *)
        emit_error "unsupported control_plane_projects op"
        ;;
    esac
    exit 0
