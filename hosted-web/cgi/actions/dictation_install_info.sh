# action: dictation_install_info
    preferred_component=$(preferred_voice_component_for_host)
    fallback_component="ctranslate2-whisper"
    install_component=$preferred_component
    install_bin=$(resolve_voice_recognition_install_bin "$install_component" || true)
    if [ -z "$install_bin" ]; then
      install_component=$fallback_component
      install_bin=$(resolve_voice_recognition_install_bin "$install_component" || true)
    fi
    if [ -z "$install_bin" ]; then
      emit_error "Voice recognition installer is unavailable."
      exit 0
    fi

    installed_json=false
    if voice_component_installed "$install_component"; then
      installed_json=true
    fi

    fallback_json=false
    if [ "$install_component" != "$preferred_component" ]; then
      fallback_json=true
    fi

    selected_backend=$(installed_voice_backend_for_host || true)

    printf '{"success":true,"preferred":"%s","preferred_label":"%s","install_target":"%s","install_target_label":"%s","fallback_component":"%s","fallback":%s,"download_size_bytes":"%s","already_installed":%s,"backend":"%s"}\n' \
      "$(json_escape "$preferred_component")" \
      "$(json_escape "$(voice_component_label "$preferred_component")")" \
      "$(json_escape "$install_component")" \
      "$(json_escape "$(voice_component_label "$install_component")")" \
      "$(json_escape "$fallback_component")" \
      "$fallback_json" \
      "$(json_escape "$(voice_component_download_size_bytes "$install_component")")" \
      "$installed_json" \
      "$(json_escape "$selected_backend")"
    exit 0
