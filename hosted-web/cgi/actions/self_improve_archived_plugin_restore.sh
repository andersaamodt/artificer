# action: self_improve_archived_plugin_restore
    archive_entry_id=$(trim "$(param "archive_entry_id")")
    if [ -z "$archive_entry_id" ]; then
      emit_error "archive_entry_id is required"
      exit 0
    fi
    self_improve_archived_plugin_restore_json "$archive_entry_id"
    exit 0
