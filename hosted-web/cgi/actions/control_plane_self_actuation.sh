# action: control_plane_self_actuation
    op=$(trim "$(param "op")")
    case "$op" in
      preview)
        control_plane_call_action_post_json "self_actuation_orchestrate" \
          "operation" "$(trim "$(param "operation")")" \
          "workspace_id" "$(trim "$(param "workspace_id")")" \
          "conversation_id" "$(trim "$(param "conversation_id")")" \
          "automation_id" "$(trim "$(param "automation_id")")" \
          "path" "$(trim "$(param "path")")" \
          "name" "$(trim "$(param "name")")" \
          "title" "$(trim "$(param "title")")" \
          "model" "$(trim "$(param "model")")" \
          "prompt" "$(param "prompt")" \
          "schedule_kind" "$(trim "$(param "schedule_kind")")" \
          "schedule_value" "$(trim "$(param "schedule_value")")" \
          "command_exec_mode" "$(trim "$(param "command_exec_mode")")" \
          "enabled" "$(trim "$(param "enabled")")" \
          "allow_self_reschedule" "$(trim "$(param "allow_self_reschedule")")" \
          "dry_run" "1"
        ;;
      apply)
        control_plane_call_action_post_json "self_actuation_orchestrate" \
          "operation" "$(trim "$(param "operation")")" \
          "workspace_id" "$(trim "$(param "workspace_id")")" \
          "conversation_id" "$(trim "$(param "conversation_id")")" \
          "automation_id" "$(trim "$(param "automation_id")")" \
          "path" "$(trim "$(param "path")")" \
          "name" "$(trim "$(param "name")")" \
          "title" "$(trim "$(param "title")")" \
          "model" "$(trim "$(param "model")")" \
          "prompt" "$(param "prompt")" \
          "schedule_kind" "$(trim "$(param "schedule_kind")")" \
          "schedule_value" "$(trim "$(param "schedule_value")")" \
          "command_exec_mode" "$(trim "$(param "command_exec_mode")")" \
          "enabled" "$(trim "$(param "enabled")")" \
          "allow_self_reschedule" "$(trim "$(param "allow_self_reschedule")")" \
          "confirm_token" "$(trim "$(param "confirm_token")")" \
          "idempotency_key" "$(trim "$(param "idempotency_key")")"
        ;;
      policy-get)
        control_plane_call_action_get_json "self_actuation_policy_get" "workspace_id" "$(trim "$(param "workspace_id")")" "action" "$(trim "$(param "action")")"
        ;;
      policy-set)
        control_plane_call_action_post_json "self_actuation_policy_set" "workspace_id" "$(trim "$(param "workspace_id")")" "action" "$(trim "$(param "action")")" "enabled" "$(trim "$(param "enabled")")"
        ;;
      audit)
        control_plane_call_action_get_json "self_actuation_audit_state" "limit" "$(trim "$(param "limit")")"
        ;;
      *)
        emit_error "unsupported control_plane_self_actuation op"
        ;;
    esac
    exit 0
