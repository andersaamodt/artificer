# action: dictation_install
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

    fallback_bin=""
    if [ "$install_component" != "$fallback_component" ]; then
      fallback_bin=$(resolve_voice_recognition_install_bin "$fallback_component" || true)
    fi

    installed_component=$install_component
    install_output=""
    fallback_used=false

    set +e
    if [ "$install_component" = "mlx-whisper" ]; then
      if voice_needs_macos_arm64_uname_override && voice_can_run_arch_arm64; then
        install_output=$(run_with_timeout 1800 arch -arm64 "$install_bin" 2>&1)
      elif voice_needs_macos_arm64_uname_override; then
        install_output="voice-recognition: native arm64 execution is unavailable"
        install_rc=126
      else
        install_output=$(run_with_timeout 1800 "$install_bin" 2>&1)
      fi
    else
      install_output=$(run_with_timeout 1800 "$install_bin" 2>&1)
    fi
    if [ "${install_rc-}" != "126" ]; then
      install_rc=$?
    fi

    if [ "$install_rc" -ne 0 ] && [ "$install_component" != "$fallback_component" ] && [ -n "$fallback_bin" ] && [ -x "$fallback_bin" ]; then
      fallback_output=$(run_with_timeout 1800 "$fallback_bin" 2>&1)
      fallback_rc=$?
      if [ -n "$install_output" ]; then
        install_output="$install_output
voice-recognition: falling back to $fallback_component
$fallback_output"
      else
        install_output="voice-recognition: falling back to $fallback_component
$fallback_output"
      fi
      if [ "$fallback_rc" -eq 0 ]; then
        install_rc=0
        installed_component=$fallback_component
        fallback_used=true
      else
        install_rc=$fallback_rc
      fi
    fi
    set -e

    if [ "$install_rc" -ne 0 ]; then
      install_output=$(strip_terminal_noise "$install_output")
      if [ "$install_rc" -eq 124 ]; then
        emit_error "Dictation install timed out."
      elif [ -n "$install_output" ]; then
        emit_error "$install_output"
      else
        emit_error "Dictation install failed."
      fi
      exit 0
    fi

    selected_backend=$installed_component

    install_output=$(strip_terminal_noise "$install_output")
    printf '{"success":true,"installed":"%s","backend":"%s","fallback":%s,"output":"%s"}\n' \
      "$(json_escape "$installed_component")" \
      "$(json_escape "$selected_backend")" \
      "$fallback_used" \
      "$(json_escape "$install_output")"
    exit 0
