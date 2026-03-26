# action: git_choose_ssh_key
    if ! command -v osascript >/dev/null 2>&1; then
      emit_error "SSH key picker is available on macOS only."
      exit 0
    fi
    chosen_path=$(trim "$(pick_ssh_pub_path_macos 2>/dev/null || true)")
    if [ -z "$chosen_path" ]; then
      printf '{"success":true,"cancelled":true}\n'
      exit 0
    fi
    if [ ! -f "$chosen_path" ]; then
      emit_error "Selected SSH key file was not found"
      exit 0
    fi
    case "$chosen_path" in
      *.pub) ;;
      *)
        emit_error "Select an SSH public key file ending in .pub"
        exit 0
        ;;
    esac

    set_selected_ssh_pub_path "$chosen_path"
    selected_key=$(sed -n '1p' "$chosen_path")
    selected_path_json=$(json_escape "$chosen_path")
    selected_key_json=$(json_escape "$selected_key")
    printf '{"success":true,"cancelled":false,"selected_ssh_pub_path":"%s","selected_ssh_pub_key":"%s"}\n' \
      "$selected_path_json" "$selected_key_json"
    exit 0
