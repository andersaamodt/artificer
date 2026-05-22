# action: git_checkout_branch
    workspace_id=$(trim "$(param "workspace_id")")
    branch_name=$(trim "$(param "branch")")
    create_raw=$(trim "$(param "create")")
    create_branch=0

    if [ "$create_raw" = "1" ] || [ "$create_raw" = "true" ]; then
      create_branch=1
    fi

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -z "$branch_name" ]; then
      emit_error "branch is required"
      exit 0
    fi
    case "$branch_name" in
      *[!a-zA-Z0-9._/-]*)
        emit_error "invalid branch name"
        exit 0
        ;;
    esac

    workspace_path=$(workspace_path_for_id "$workspace_id")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi

    set +e
    if [ "$create_branch" -eq 1 ]; then
      branch_raw=$(run_artificer_git create-branch "$workspace_path" "$branch_name" 2>&1)
    else
      branch_raw=$(run_artificer_git checkout "$workspace_path" "$branch_name" 2>&1)
    fi
    branch_rc=$?
    set -e
    if [ "$branch_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$branch_raw")"
      exit 0
    fi

    output_json=$(json_escape "$(strip_terminal_noise "$branch_raw")")
    branch_json=$(json_escape "$branch_name")
    printf '{"success":true,"branch":"%s","output":"%s"}\n' "$branch_json" "$output_json"
    exit 0
