# action: dictation_status
    preferred_component=$(preferred_voice_component_for_host)
    selected_backend=$(installed_voice_backend_for_host || true)
    language_backend=$selected_backend
    if [ -z "$language_backend" ]; then
      language_backend=$preferred_component
    fi
    selected_language=$(dictation_language_value_for_backend "$language_backend")
    language_options_json=$(dictation_languages_json_for_backend "$language_backend")

    installed_json=false
    if [ -n "$selected_backend" ]; then
      installed_json=true
    fi

    printf '{"success":true,"installed":%s,"backend":"%s","backend_label":"%s","preferred":"%s","preferred_label":"%s","language":"%s","languages":%s}\n' \
      "$installed_json" \
      "$(json_escape "$selected_backend")" \
      "$(json_escape "$(voice_component_label "$selected_backend")")" \
      "$(json_escape "$preferred_component")" \
      "$(json_escape "$(voice_component_label "$preferred_component")")" \
      "$(json_escape "$selected_language")" \
      "$language_options_json"
    exit 0
