# action: multi_agent_commitment_update
    workspace_id=$(trim "$(param "workspace_id")")
    entry_id=$(trim "$(param "entry_id")")
    next_status=$(trim "$(param "status")")
    if ! command -v ma_update_commitment_status >/dev/null 2>&1; then
      emit_error "Multi-agent runtime is unavailable"
      exit 0
    fi
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$entry_id"; then
      emit_error "invalid entry_id"
      exit 0
    fi
    case "$next_status" in
      active|fulfilled|revoked) ;;
      *)
        emit_error "invalid status"
        exit 0
        ;;
    esac
    if ! ma_update_commitment_status "$workspace_id" "$entry_id" "$next_status"; then
      emit_error "commitment not found"
      exit 0
    fi
    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
