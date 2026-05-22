# action: git_diff
    workspace_id=$(trim "$(param "workspace_id")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi

    workspace_path=$(workspace_path_for_id "$workspace_id")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi

    set +e
    diff_raw=$(run_artificer_git diff "$workspace_path" 2>&1)
    diff_rc=$?
    set -e
    if [ "$diff_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$diff_raw")"
      exit 0
    fi

    info_raw=$(run_artificer_git repo-info "$workspace_path" 2>/dev/null || true)
    is_repo=$(kv_get "is_repo" "$info_raw")
    added=$(kv_get "added" "$info_raw")
    deleted=$(kv_get "deleted" "$info_raw")
    [ -n "$added" ] || added=0
    [ -n "$deleted" ] || deleted=0

    if [ "$is_repo" = "1" ]; then
      is_repo_json=true
    else
      is_repo_json=false
    fi

    diff_json=$(json_escape "$diff_raw")
    printf '{"success":true,"is_repo":%s,"added":%s,"deleted":%s,"diff":"%s"}\n' \
      "$is_repo_json" "$added" "$deleted" "$diff_json"
    exit 0
