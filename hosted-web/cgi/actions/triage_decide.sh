# action: triage_decide
    proposal_id=$(trim "$(param "proposal_id")")
    decision=$(trim "$(param "decision")")
    if ! valid_id "$proposal_id"; then
      emit_error "invalid proposal_id"
      exit 0
    fi
    [ -n "$decision" ] || decision="accepted"
    proposal_meta=$(ma_find_proposal_meta "$proposal_id")
    if [ -z "$proposal_meta" ] || [ ! -f "$proposal_meta" ]; then
      emit_error "proposal not found"
      exit 0
    fi
    ma_mark_proposal_decision "$proposal_meta" "decided" "$decision"
    printf '{"success":true,"cards":%s}\n' "$(ma_triage_cards_json)"
    exit 0
