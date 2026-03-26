# action: triage_suppress
    proposal_id=$(trim "$(param "proposal_id")")
    scope=$(trim "$(param "scope")")
    if ! valid_id "$proposal_id"; then
      emit_error "invalid proposal_id"
      exit 0
    fi
    case "$scope" in
      global|workspace) ;;
      *) scope="workspace" ;;
    esac
    proposal_meta=$(ma_find_proposal_meta "$proposal_id")
    if [ -z "$proposal_meta" ] || [ ! -f "$proposal_meta" ]; then
      emit_error "proposal not found"
      exit 0
    fi
    policy_id=$(ma_create_policy_from_proposal "$proposal_meta" "$scope")
    ma_mark_proposal_decision "$proposal_meta" "decided" "suppressed:$scope:$policy_id"
    printf '{"success":true,"policy_id":"%s","cards":%s}\n' "$(json_escape "$policy_id")" "$(ma_triage_cards_json)"
    exit 0
