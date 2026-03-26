# action: git_commit
    workspace_id=$(trim "$(param "workspace_id")")
    include_unstaged=$(trim "$(param "include_unstaged")")
    commit_message=$(param "message")
    push_after=$(trim "$(param "push")")
    [ -n "$include_unstaged" ] || include_unstaged=1
    [ -n "$push_after" ] || push_after=0

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ "$include_unstaged" != "0" ] && [ "$include_unstaged" != "1" ]; then
      include_unstaged=1
    fi
    if [ "$push_after" != "0" ] && [ "$push_after" != "1" ]; then
      push_after=0
    fi

    workspace_path=$(workspace_path_for_id "$workspace_id")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi

    set +e
    if [ "$push_after" = "1" ]; then
      commit_raw=$(run_artificer_git commit-push "$workspace_path" "$include_unstaged" "$commit_message" 2>&1)
    else
      commit_raw=$(run_artificer_git commit "$workspace_path" "$include_unstaged" "$commit_message" 2>&1)
    fi
    commit_rc=$?
    set -e
    if [ "$commit_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$commit_raw")"
      exit 0
    fi

    output_json=$(json_escape "$(strip_terminal_noise "$commit_raw")")
    printf '{"success":true,"output":"%s"}\n' "$output_json"
    exit 0
