# action: dictation_install_status
    job_id=$(trim "$(param "job_id")")
    if ! valid_id "$job_id"; then
      emit_error "invalid job_id"
      exit 0
    fi

    job_dir="$dictation_installs_dir/$job_id"
    if [ ! -d "$job_dir" ]; then
      emit_error "dictation install job not found"
      exit 0
    fi

    status=$(read_file_line "$job_dir/status" "running")
    started=$(read_file_line "$job_dir/started" "0")
    finished=$(read_file_line "$job_dir/finished" "0")
    install_pid=$(read_file_line "$job_dir/pid" "")
    exit_code=$(read_file_line "$job_dir/exit_code" "")
    component=$(read_file_line "$job_dir/component" "")
    fallback_component=$(read_file_line "$job_dir/fallback_component" "ctranslate2-whisper")
    installed_component=$(read_file_line "$job_dir/installed_component" "$component")
    selected_backend=$(read_file_line "$job_dir/backend" "$installed_component")
    fallback_used=$(read_file_line "$job_dir/fallback_used" "0")
    download_size_bytes=$(read_file_line "$job_dir/download_size_bytes" "")
    download_bytes_start=$(read_file_line "$job_dir/download_bytes_start" "")
    phase_previous=$(read_file_line "$job_dir/phase_last" "")
    progress_pct_previous=$(read_file_line "$job_dir/progress_pct_last" "")
    downloaded_bytes_previous=$(read_file_line "$job_dir/downloaded_bytes_last" "")
    if [ -z "$download_bytes_start" ]; then
      download_bytes_start=$(read_file_line "$job_dir/runtime_bytes_start" "0")
    fi
    downloaded_bytes=""
    status_reason=""

    if [ "$status" = "running" ] && [ -n "$install_pid" ]; then
      if ! kill -0 "$install_pid" 2>/dev/null; then
        status="failed"
        case "$exit_code" in
          0) status="done" ;;
          130|143) status="cancelled" ;;
          "") status_reason="Dictation installer stopped before producing output." ;;
        esac
      fi
    fi

    log_tail=$(tail -n 220 "$job_dir/log" 2>/dev/null || true)
    if [ "$status" = "failed" ] && [ -z "$log_tail" ] && [ -n "$status_reason" ]; then
      log_tail=$status_reason
    fi

    download_bytes_now=$(voice_component_download_usage_bytes "$component")
    case "$download_bytes_now" in
      *[!0-9]*|"")
        download_bytes_now=""
        ;;
    esac
    case "$download_bytes_start:$download_bytes_now" in
      *[!0-9]*:*|*:*[!0-9]*)
        downloaded_bytes=""
        ;;
      *)
        downloaded_bytes=$((download_bytes_now - download_bytes_start))
        if [ "$downloaded_bytes" -lt 0 ] 2>/dev/null; then
          downloaded_bytes=0
        fi
        ;;
    esac

    phase="downloading"
    progress_pct="0"
    if [ "$status" = "done" ]; then
      phase="done"
      progress_pct="100"
    elif [ "$status" = "cancelled" ]; then
      phase="cancelled"
      progress_pct=""
    elif [ "$status" = "failed" ]; then
      phase="failed"
      progress_pct=""
    else
      parse_result=$(infer_dictation_install_phase_progress "$log_tail")
      phase_candidate=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      [ -n "$phase_candidate" ] || phase_candidate="downloading"
      phase=$(dictation_phase_progressive "$phase_previous" "$phase_candidate")
      case "$download_size_bytes:$downloaded_bytes" in
        *[!0-9]*:*|*:*[!0-9]*|*:)
          progress_pct=""
          ;;
        *)
          if [ "$download_size_bytes" -gt 0 ] 2>/dev/null; then
            progress_pct=$(progress_pct_from_bytes "$downloaded_bytes" "$download_size_bytes")
          else
            progress_pct=""
          fi
          ;;
      esac
    fi

    if [ "$status" = "running" ]; then
      case "$downloaded_bytes_previous:$downloaded_bytes" in
        *[!0-9]*:*|*:*[!0-9]*|:)
          :
          ;;
        *)
          if [ "$downloaded_bytes" -lt "$downloaded_bytes_previous" ] 2>/dev/null; then
            downloaded_bytes=$downloaded_bytes_previous
          fi
          ;;
      esac
      case "$progress_pct_previous:$progress_pct" in
        :*|*:)
          :
          ;;
        *)
          progress_pct=$(awk -v prev="$progress_pct_previous" -v cur="$progress_pct" '
            BEGIN {
              p = prev + 0
              c = cur + 0
              if (c < p) c = p
              if (c < 0) c = 0
              if (c > 99.9) c = 99.9
              printf "%.1f", c
            }
          ')
          ;;
      esac
    fi

    printf '%s\n' "$phase" > "$job_dir/phase_last"
    if [ -n "$progress_pct" ]; then
      printf '%s\n' "$progress_pct" > "$job_dir/progress_pct_last"
    fi
    if [ -n "$downloaded_bytes" ]; then
      printf '%s\n' "$downloaded_bytes" > "$job_dir/downloaded_bytes_last"
    fi

    fallback_json=false
    if [ "$fallback_used" = "1" ]; then
      fallback_json=true
    fi

    printf '{"success":true,"job":{"id":"%s","status":"%s","action":"install","phase":"%s","progress_pct":"%s","downloaded_bytes":"%s","component":"%s","component_label":"%s","installed":"%s","backend":"%s","fallback_component":"%s","fallback":%s,"download_size_bytes":"%s","started":"%s","finished":"%s","exit_code":"%s","log":"%s"}}\n' \
      "$(json_escape "$job_id")" \
      "$(json_escape "$status")" \
      "$(json_escape "$phase")" \
      "$(json_escape "$progress_pct")" \
      "$(json_escape "$downloaded_bytes")" \
      "$(json_escape "$component")" \
      "$(json_escape "$(voice_component_label "$component")")" \
      "$(json_escape "$installed_component")" \
      "$(json_escape "$selected_backend")" \
      "$(json_escape "$fallback_component")" \
      "$fallback_json" \
      "$(json_escape "$download_size_bytes")" \
      "$(json_escape "$started")" \
      "$(json_escape "$finished")" \
      "$(json_escape "$exit_code")" \
      "$(json_escape "$(strip_terminal_noise "$log_tail")")"
    exit 0
