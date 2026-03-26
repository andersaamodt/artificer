# action: pick_workspace
    picked_path=$(pick_workspace_path_macos 2>/dev/null || true)
    picked_path=$(trim "$picked_path")

    if [ -z "$picked_path" ]; then
      printf '{"success":true,"cancelled":true}\n'
      exit 0
    fi

    if [ ! -d "$picked_path" ]; then
      emit_error "picked path is not a directory"
      exit 0
    fi

    picked_path_json=$(json_escape "$picked_path")
    printf '{"success":true,"path":"%s"}\n' "$picked_path_json"
    exit 0
