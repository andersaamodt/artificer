# action: self_actuation_policy_get
    workspace_id=$(trim "$(param "workspace_id")")
    action_name=$(trim "$(param "operation")")

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

    if [ -n "$action_name" ]; then
      if ! self_actuation_action_valid "$action_name"; then
        emit_error "invalid operation"
        exit 0
      fi
      effective_value=$(self_actuation_policy_effective_value "$action_name" "$workspace_id")
      enabled_value=0
      if [ "$effective_value" = "allow" ]; then
        enabled_value=1
      fi
      printf '{"success":true,"workspace_id":"%s","operation":"%s","enabled":"%s","policy":%s}\n' \
        "$(json_escape "$workspace_id")" \
        "$(json_escape "$action_name")" \
        "$(json_escape "$enabled_value")" \
        "$(self_actuation_policy_json "$workspace_id")"
      exit 0
    fi

    printf '{"success":true,"policy":%s}\n' "$(self_actuation_policy_json "$workspace_id")"
    exit 0
