# action: dictation_language_set
    next_language=$(normalize_dictation_language_value "$(param "language")")
    if [ -z "$next_language" ]; then
      emit_error "invalid language"
      exit 0
    fi
    language_backend=$(dictation_language_backend_for_settings)
    if ! dictation_language_allowed_for_backend "$language_backend" "$next_language"; then
      emit_error "invalid language"
      exit 0
    fi
    set_dictation_language_value "$next_language"
    dictation_language_get_json "$language_backend"
    exit 0
