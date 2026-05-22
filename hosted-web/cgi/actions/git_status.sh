# action: git_status
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
    info_raw=$(run_artificer_git repo-info "$workspace_path" 2>&1)
    info_rc=$?
    set -e
    if [ "$info_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$info_raw")"
      exit 0
    fi

    is_repo=$(kv_get "is_repo" "$info_raw")
    branch=$(kv_get "branch" "$info_raw")
    ahead=$(kv_get "ahead" "$info_raw")
    behind=$(kv_get "behind" "$info_raw")
    added=$(kv_get "added" "$info_raw")
    deleted=$(kv_get "deleted" "$info_raw")
    changes=$(kv_get "changes" "$info_raw")
    staged_changes=$(kv_get "staged_changes" "$info_raw")
    unstaged_changes=$(kv_get "unstaged_changes" "$info_raw")

    [ -n "$ahead" ] || ahead=0
    [ -n "$behind" ] || behind=0
    [ -n "$added" ] || added=0
    [ -n "$deleted" ] || deleted=0
    [ -n "$changes" ] || changes=0
    [ -n "$staged_changes" ] || staged_changes=0
    [ -n "$unstaged_changes" ] || unstaged_changes=0

    if [ "$is_repo" = "1" ]; then
      is_repo_json=true
    else
      is_repo_json=false
    fi

    branch_json=$(json_escape "$branch")
    printf '{"success":true,"is_repo":%s,"branch":"%s","ahead":%s,"behind":%s,"added":%s,"deleted":%s,"changes":%s,"staged_changes":%s,"unstaged_changes":%s}\n' \
      "$is_repo_json" "$branch_json" "$ahead" "$behind" "$added" "$deleted" "$changes" "$staged_changes" "$unstaged_changes"
    exit 0
