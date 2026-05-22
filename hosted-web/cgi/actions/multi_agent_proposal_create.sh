# action: multi_agent_proposal_create
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    resident_id=$(trim "$(param "resident_id")")
    summary=$(trim "$(param "summary")")
    target_type=$(trim "$(param "target_type")")
    target=$(trim "$(param "target")")
    escalation_class=$(trim "$(param "escalation_class")")
    rationale=$(trim "$(param "rationale")")
    impact_threshold=$(trim "$(param "impact_threshold")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -z "$summary" ]; then
      emit_error "summary is required"
      exit 0
    fi
    if [ -z "$target_type" ]; then
      target_type="Workspace"
    fi
    if [ -z "$escalation_class" ]; then
      escalation_class="PolicyTradeoff"
    fi
    if [ -z "$resident_id" ]; then
      resident_id="manual"
    fi
    proposal_id=$(ma_new_proposal "$workspace_id" "$conversation_id" "$resident_id" "$summary" "$target_type" "$escalation_class" "$rationale" "$impact_threshold" "$target")
    printf '{"success":true,"proposal_id":"%s","triage":{"cards":%s}}\n' "$(json_escape "$proposal_id")" "$(ma_triage_cards_json)"
    exit 0
