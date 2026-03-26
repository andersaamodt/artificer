# action: self_improve_plugin_set
    plugin_id=$(trim "$(param "plugin_id")")
    enabled=$(trim "$(param "enabled")")
    if [ -z "$plugin_id" ]; then
      emit_error "plugin_id is required"
      exit 0
    fi
    self_improve_plugin_set_enabled_json "$plugin_id" "$enabled"
    exit 0
