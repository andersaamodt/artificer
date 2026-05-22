# action: git_branches
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

    info_raw=$(run_artificer_git repo-info "$workspace_path" 2>/dev/null || true)
    is_repo=$(kv_get "is_repo" "$info_raw")
    if [ "$is_repo" != "1" ]; then
      printf '{"success":true,"is_repo":false,"branches":[]}\n'
      exit 0
    fi

    set +e
    branches_raw=$(run_artificer_git branches "$workspace_path" 2>&1)
    branches_rc=$?
    set -e
    if [ "$branches_rc" -ne 0 ]; then
      emit_error "$(strip_terminal_noise "$branches_raw")"
      exit 0
    fi

    printf '{"success":true,"is_repo":true,"branches":['
    first_branch=1
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      current=false
      case "$line" in
        CURRENT\|*)
          branch_name=${line#CURRENT|}
          current=true
          ;;
        BRANCH\|*)
          branch_name=${line#BRANCH|}
          current=false
          ;;
        *)
          continue
          ;;
      esac

      branch_json=$(json_escape "$branch_name")
      if [ "$first_branch" -eq 0 ]; then
        printf ','
      fi
      first_branch=0
      printf '{"name":"%s","current":%s}' "$branch_json" "$current"
    done <<EOF
$branches_raw
EOF
    printf ']}\n'
    exit 0
