# action: git_generate_ssh
    email=$(trim "$(param "email")")
    set +e
    key_raw=$(run_artificer_git ensure-ssh "$email" 2>&1)
    key_rc=$?
    set -e
    if [ "$key_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$key_raw")"
      exit 0
    fi

    ssh_pub_path=$(kv_get "ssh_pub_path" "$key_raw")
    ssh_pub_key=$(kv_get "ssh_pub_key" "$key_raw")
    if [ -n "$ssh_pub_path" ] && [ -f "$ssh_pub_path" ]; then
      set_selected_ssh_pub_path "$ssh_pub_path"
    fi
    ssh_pub_path_json=$(json_escape "$ssh_pub_path")
    ssh_pub_key_json=$(json_escape "$ssh_pub_key")
    printf '{"success":true,"ssh_pub_path":"%s","ssh_pub_key":"%s"}\n' \
      "$ssh_pub_path_json" "$ssh_pub_key_json"
    exit 0
