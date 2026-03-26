# action: git_auth_status
    if command -v git >/dev/null 2>&1; then
      has_git=1
    else
      has_git=0
    fi

    git_bin=$(resolve_artificer_git_bin || true)
    if [ -z "$git_bin" ]; then
      ssh_pub_exists=0
      ssh_pub_path=""
      ssh_pub_key=""
      selected_pub_path=$(selected_ssh_pub_path)
      selected_pub_key=""
      if [ -n "$selected_pub_path" ] && [ ! -f "$selected_pub_path" ]; then
        selected_pub_path=""
        clear_selected_ssh_pub_path
      fi
      if [ -n "$selected_pub_path" ] && [ -f "$selected_pub_path" ]; then
        selected_pub_key=$(sed -n '1p' "$selected_pub_path")
        ssh_pub_exists=1
        ssh_pub_path=$selected_pub_path
        ssh_pub_key=$selected_pub_key
      fi
      if [ "$has_git" = "1" ]; then has_git_json=true; else has_git_json=false; fi
      if [ "$ssh_pub_exists" = "1" ]; then ssh_json=true; else ssh_json=false; fi
      ssh_pub_path_json=$(json_escape "$ssh_pub_path")
      ssh_pub_key_json=$(json_escape "$ssh_pub_key")
      selected_ssh_pub_path_json=$(json_escape "$selected_pub_path")
      selected_ssh_pub_key_json=$(json_escape "$selected_pub_key")
      printf '{"success":true,"has_git":%s,"has_gh":false,"gh_authenticated":false,"ssh_pub_exists":%s,"ssh_pub_path":"%s","ssh_pub_key":"%s","selected_ssh_pub_path":"%s","selected_ssh_pub_key":"%s"}\n' \
        "$has_git_json" "$ssh_json" "$ssh_pub_path_json" "$ssh_pub_key_json" "$selected_ssh_pub_path_json" "$selected_ssh_pub_key_json"
      exit 0
    fi
    set +e
    if command -v timeout >/dev/null 2>&1; then
      auth_raw=$(timeout 10 "$git_bin" auth-status 2>&1)
      auth_rc=$?
    elif command -v gtimeout >/dev/null 2>&1; then
      auth_raw=$(gtimeout 10 "$git_bin" auth-status 2>&1)
      auth_rc=$?
    else
      auth_raw=$("$git_bin" auth-status 2>&1)
      auth_rc=$?
    fi
    set -e
    if [ "$auth_rc" -ne 0 ]; then
      if [ "$auth_rc" -eq 124 ]; then
        emit_error "Timed out while checking Git/SSH status"
      else
        emit_error "$(strip_terminal_noise "$auth_raw")"
      fi
      exit 0
    fi

    has_gh=$(kv_get "has_gh" "$auth_raw")
    gh_authenticated=$(kv_get "gh_authenticated" "$auth_raw")
    ssh_pub_exists=$(kv_get "ssh_pub_exists" "$auth_raw")
    ssh_pub_path=$(kv_get "ssh_pub_path" "$auth_raw")
    ssh_pub_key=$(kv_get "ssh_pub_key" "$auth_raw")
    selected_pub_path=$(selected_ssh_pub_path)
    selected_pub_key=""

    [ -n "$has_gh" ] || has_gh=0
    [ -n "$gh_authenticated" ] || gh_authenticated=0
    [ -n "$ssh_pub_exists" ] || ssh_pub_exists=0

    if [ -n "$selected_pub_path" ] && [ ! -f "$selected_pub_path" ]; then
      selected_pub_path=""
      clear_selected_ssh_pub_path
    fi
    if [ -n "$selected_pub_path" ] && [ -f "$selected_pub_path" ]; then
      selected_pub_key=$(sed -n '1p' "$selected_pub_path")
    fi

    if [ "$has_gh" = "1" ]; then has_gh_json=true; else has_gh_json=false; fi
    if [ "$has_git" = "1" ]; then has_git_json=true; else has_git_json=false; fi
    if [ "$gh_authenticated" = "1" ]; then gh_auth_json=true; else gh_auth_json=false; fi
    if [ "$ssh_pub_exists" = "1" ]; then ssh_json=true; else ssh_json=false; fi

    ssh_pub_path_json=$(json_escape "$ssh_pub_path")
    ssh_pub_key_json=$(json_escape "$ssh_pub_key")
    selected_ssh_pub_path_json=$(json_escape "$selected_pub_path")
    selected_ssh_pub_key_json=$(json_escape "$selected_pub_key")

    printf '{"success":true,"has_git":%s,"has_gh":%s,"gh_authenticated":%s,"ssh_pub_exists":%s,"ssh_pub_path":"%s","ssh_pub_key":"%s","selected_ssh_pub_path":"%s","selected_ssh_pub_key":"%s"}\n' \
      "$has_git_json" "$has_gh_json" "$gh_auth_json" "$ssh_json" "$ssh_pub_path_json" "$ssh_pub_key_json" "$selected_ssh_pub_path_json" "$selected_ssh_pub_key_json"
    exit 0
