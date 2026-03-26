# action: multi_agent_workspace_update
    workspace_id=$(trim "$(param "workspace_id")")
    if ! valid_workspace_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    if ! command -v ma_workspace_state_json >/dev/null 2>&1; then
      emit_error "Multi-agent runtime is unavailable"
      exit 0
    fi
    ma_workspace_init "$workspace_id"
    charter_text=$(param "charter")
    charter_present=$(trim "$(param "charter_present")")
    ontology_link=$(trim "$(param "ontology_link")")
    shared_context_workspace_ids=$(trim "$(param "shared_context_workspace_ids")")
    toggles_file=$(ma_workspace_toggles_file "$workspace_id")
    meta_file=$(ma_workspace_meta_file "$workspace_id")

    if [ "$charter_present" = "1" ]; then
      printf '%s\n' "$charter_text" > "$(ma_workspace_charter_file "$workspace_id")"
    fi
    if [ -n "$ontology_link" ]; then
      ma_meta_set "$meta_file" "ontology_link" "$ontology_link"
    fi
    if [ -n "$shared_context_workspace_ids" ]; then
      ma_meta_set "$meta_file" "shared_context_workspace_ids" "$shared_context_workspace_ids"
    fi

    for toggle_key in context_sharing dilemma_surfacing amendments interpretation_log commitments attention_policies; do
      toggle_value=$(trim "$(param "$toggle_key")")
      case "$toggle_value" in
        0|1)
          ma_meta_set "$toggles_file" "$toggle_key" "$toggle_value"
          ;;
      esac
    done

    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
