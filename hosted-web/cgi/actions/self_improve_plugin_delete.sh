# action: self_improve_plugin_delete
    plugin_id=$(trim "$(param "plugin_id")")
    if [ -z "$plugin_id" ]; then
      emit_error "plugin_id is required"
      exit 0
    fi
    self_improve_plugin_delete_json "$plugin_id"
    exit 0
