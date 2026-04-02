# action: control_plane_attention
    op=$(trim "$(param "op")")
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    decision=$(trim "$(param "decision")")
    scope=$(trim "$(param "scope")")
    match_mode=$(trim "$(param "match_mode")")
    pattern=$(param "pattern")
    command_text=$(param "command")
    answer_text=$(param "answer")

    case "$op" in
      ""|list)
        control_plane_attention_list_json
        ;;
      approval-answer)
        approval_json=$(control_plane_call_action_post_json "approval_answer" \
          "workspace_id" "$workspace_id" \
          "conversation_id" "$conversation_id" \
          "decision" "$decision" \
          "scope" "$scope" \
          "match_mode" "$match_mode" \
          "pattern" "$pattern" \
          "command" "$command_text")
        if ! control_plane_json_success "$approval_json"; then
          printf '%s\n' "$approval_json"
          exit 0
        fi
        session_json=$(control_plane_session_object_json "$workspace_id" "$conversation_id" 1 1 || true)
        printf '{"success":true,"api_version":"%s","result":%s,"session":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" "$approval_json" "$session_json"
        ;;
      decision-answer)
        decision_json=$(control_plane_call_action_post_json "decision_answer" "workspace_id" "$workspace_id" "conversation_id" "$conversation_id" "answer" "$answer_text")
        if ! control_plane_json_success "$decision_json"; then
          printf '%s\n' "$decision_json"
          exit 0
        fi
        session_json=$(control_plane_session_object_json "$workspace_id" "$conversation_id" 1 1 || true)
        printf '{"success":true,"api_version":"%s","result":%s,"session":%s}\n' \
          "$(json_escape "$(control_plane_api_version)")" "$decision_json" "$session_json"
        ;;
      *)
        emit_error "unsupported control_plane_attention op"
        ;;
    esac
    exit 0
