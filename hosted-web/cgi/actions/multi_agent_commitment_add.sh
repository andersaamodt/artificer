# action: multi_agent_commitment_add
    workspace_id=$(trim "$(param "workspace_id")")
    statement=$(trim "$(param "statement")")
    scope=$(trim "$(param "scope")")
    duration=$(trim "$(param "duration")")
    revocability=$(trim "$(param "revocability")")
    audience=$(trim "$(param "audience")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -z "$statement" ]; then
      emit_error "statement is required"
      exit 0
    fi
    [ -n "$scope" ] || scope="workspace"
    [ -n "$duration" ] || duration="unspecified"
    [ -n "$revocability" ] || revocability="revocable"
    [ -n "$audience" ] || audience="internal"
    entry_id=$(ma_add_commitment_entry "$workspace_id" "$statement" "$scope" "$duration" "$revocability" "$audience")
    printf '{"success":true,"entry_id":"%s","workspace_multi_agent":%s}\n' "$(json_escape "$entry_id")" "$(ma_workspace_state_json "$workspace_id")"
    exit 0
