# action: self_improve_plugin_set
    plugin_id=$(trim "$(param "plugin_id")")
    enabled=$(trim "$(param "enabled")")
    operator_policy=$(trim "$(param "operator_policy")")
    operator_lock=$(trim "$(param "operator_lock")")
    if [ -z "$plugin_id" ]; then
      emit_error "plugin_id is required"
      exit 0
    fi
    self_improve_plugin_set_json "$plugin_id" "$enabled" "$operator_policy" "$operator_lock"
    exit 0
