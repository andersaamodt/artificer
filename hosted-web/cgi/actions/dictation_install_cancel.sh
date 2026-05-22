# action: dictation_install_cancel
    if ! acquire_dictation_job_lock "2000"; then
      emit_error "Dictation install is busy. Try again."
      exit 0
    fi
    job_id=$(trim "$(param "job_id")")
    if ! valid_id "$job_id"; then
      release_dictation_job_lock
      emit_error "invalid job_id"
      exit 0
    fi

    job_dir="$dictation_installs_dir/$job_id"
    if [ ! -d "$job_dir" ]; then
      release_dictation_job_lock
      emit_error "dictation install job not found"
      exit 0
    fi

    status=$(read_file_line "$job_dir/status" "")
    install_pid=$(read_file_line "$job_dir/pid" "")
    component=$(read_file_line "$job_dir/component" "")
    fallback_component=$(read_file_line "$job_dir/fallback_component" "ctranslate2-whisper")

    if [ "$status" = "done" ] || [ "$status" = "failed" ] || [ "$status" = "cancelled" ]; then
      release_dictation_job_lock
      printf '{"success":true,"job":{"id":"%s","status":"%s","action":"install"}}\n' \
        "$(json_escape "$job_id")" \
        "$(json_escape "$status")"
      exit 0
    fi

    # Mark cancelled immediately so new installs never reattach to this job.
    printf '%s\n' "130" > "$job_dir/exit_code"
    printf '%s\n' "cancelled" > "$job_dir/status"
    [ -f "$job_dir/finished" ] || date +%s > "$job_dir/finished"

    if [ -n "$install_pid" ] && ! stop_process_tree_by_pid "$install_pid"; then
      release_dictation_job_lock
      emit_error "Could not cancel dictation install process."
      exit 0
    fi

    if [ -n "$component" ] && ! remove_voice_component_artifacts "$component"; then
      release_dictation_job_lock
      emit_error "Cancelled install, but could not remove partial dictation files."
      exit 0
    fi
    if [ -n "$fallback_component" ] && [ "$fallback_component" != "$component" ]; then
      if ! remove_voice_component_artifacts "$fallback_component"; then
        release_dictation_job_lock
        emit_error "Cancelled install, but could not remove fallback dictation files."
        exit 0
      fi
    fi
    if ! remove_voice_download_cache; then
      release_dictation_job_lock
      emit_error "Cancelled install, but could not remove dictation download cache."
      exit 0
    fi
    printf '%s\n' "voice-recognition: install cancelled" >> "$job_dir/log"

    release_dictation_job_lock
    printf '{"success":true,"job":{"id":"%s","status":"cancelled","action":"install"}}\n' \
      "$(json_escape "$job_id")"
    exit 0
