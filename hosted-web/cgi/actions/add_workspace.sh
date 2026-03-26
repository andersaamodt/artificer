# action: add_workspace
    raw_path=$(trim "$(param "path")")
    raw_name=$(trim "$(param "name")")
    command_exec_mode_raw=$(trim "$(param "command_exec_mode")")

    if [ -z "$raw_path" ]; then
      emit_error "path is required"
      exit 0
    fi

    expanded_path=$raw_path
    case "$expanded_path" in
      "~")
        expanded_path=$HOME
        ;;
      "~/"*)
        expanded_path=$HOME/${expanded_path#~/}
        ;;
    esac

    case "$expanded_path" in
      /*) ;;
      *)
        emit_error "path must be absolute"
        exit 0
        ;;
    esac

    if [ ! -d "$expanded_path" ]; then
      emit_error "path does not exist or is not a directory"
      exit 0
    fi

    canonical_path=$(cd "$expanded_path" && pwd -P)
    workspace_name=$raw_name
    if [ -z "$workspace_name" ]; then
      workspace_name=$(basename "$canonical_path")
    fi

    for ws_dir in "$workspaces_dir"/*; do
      [ -d "$ws_dir" ] || continue
      existing_path=$(read_file_line "$ws_dir/path" "")
      if [ "$existing_path" = "$canonical_path" ]; then
        existing_id=$(basename "$ws_dir")
        existing_name=$(read_file_line "$ws_dir/name" "$existing_id")
        existing_id_json=$(json_escape "$existing_id")
        existing_name_json=$(json_escape "$existing_name")
        existing_path_json=$(json_escape "$canonical_path")
        printf '{"success":true,"workspace":{"id":"%s","name":"%s","path":"%s"},"existing":true}\n' \
          "$existing_id_json" "$existing_name_json" "$existing_path_json"
        exit 0
      fi
    done

    workspace_id=$(new_id)
    ws_dir=$(workspace_dir_for "$workspace_id")

    mkdir -p "$ws_dir/conversations"
    printf '%s\n' "$workspace_name" > "$ws_dir/name"
    printf '%s\n' "$canonical_path" > "$ws_dir/path"
    date +%s > "$ws_dir/created"
    workspace_command_mode=$(normalize_command_exec_mode_value "$command_exec_mode_raw")
    if [ -n "$workspace_command_mode" ]; then
      set_command_policy_mode_for_workspace "$workspace_id" "$workspace_command_mode"
    fi

    workspace_id_json=$(json_escape "$workspace_id")
    workspace_name_json=$(json_escape "$workspace_name")
    workspace_path_json=$(json_escape "$canonical_path")
    printf '{"success":true,"workspace":{"id":"%s","name":"%s","path":"%s"}}\n' \
      "$workspace_id_json" "$workspace_name_json" "$workspace_path_json"
    exit 0
