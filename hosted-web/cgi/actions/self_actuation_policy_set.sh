# action: self_actuation_policy_set
    workspace_id=$(trim "$(param "workspace_id")")
    action_name=$(trim "$(param "operation")")
    enabled_raw=$(trim "$(param "enabled")")

    if ! self_actuation_action_valid "$action_name"; then
      emit_error "invalid operation"
      exit 0
    fi
    enabled_value=$(normalize_toggle_01_value "$enabled_raw")
    if [ -z "$enabled_value" ]; then
      emit_error "invalid enabled value"
      exit 0
    fi
    if [ -n "$workspace_id" ]; then
      if ! valid_workspace_id "$workspace_id"; then
        emit_error "invalid workspace_id"
        exit 0
      fi
      ws_dir=$(workspace_dir_for "$workspace_id")
      if [ ! -d "$ws_dir" ]; then
        emit_error "workspace not found"
        exit 0
      fi
    fi

    if ! self_actuation_policy_set_value "$action_name" "$workspace_id" "$enabled_value"; then
      emit_error "failed to set self-actuation policy"
      exit 0
    fi

    effective_value=$(self_actuation_policy_effective_value "$action_name" "$workspace_id")
    effective_enabled=0
    if [ "$effective_value" = "allow" ]; then
      effective_enabled=1
    fi
    self_actuation_audit_append "policy-set" "$action_name" "$workspace_id" "" "" "ok" "policy updated" "" ""
    printf '{"success":true,"workspace_id":"%s","operation":"%s","enabled":"%s","policy":%s}\n' \
      "$(json_escape "$workspace_id")" \
      "$(json_escape "$action_name")" \
      "$(json_escape "$effective_enabled")" \
      "$(self_actuation_policy_json "$workspace_id")"
    exit 0
