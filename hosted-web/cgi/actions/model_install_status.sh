# action: model_install_status
    job_id=$(trim "$(param "job_id")")
    if ! valid_id "$job_id"; then
      emit_error "invalid job_id"
      exit 0
    fi

    job_dir="$model_installs_dir/$job_id"
    if [ ! -d "$job_dir" ]; then
      emit_error "install job not found"
      exit 0
    fi

	    model_name=$(read_file_line "$job_dir/model" "")
	    status=$(read_file_line "$job_dir/status" "running")
	    started=$(read_file_line "$job_dir/started" "0")
	    finished=$(read_file_line "$job_dir/finished" "0")
	    install_pid=$(read_file_line "$job_dir/pid" "")
	    exit_code=$(read_file_line "$job_dir/exit_code" "")
	    resume_available=$(read_file_line "$job_dir/resume_available" "0")
	    resume_bytes=$(read_file_line "$job_dir/resume_bytes" "0")
	    stale_partial_files_removed=$(read_file_line "$job_dir/stale_partial_files_removed" "0")
	    if [ "$status" = "running" ] && [ -n "$install_pid" ]; then
	      if ! kill -0 "$install_pid" 2>/dev/null; then
	        status="failed"
	        case "$exit_code" in
	          0) status="done" ;;
	        esac
	      fi
	    fi
	    if [ "$status" != "running" ]; then
	      running_install_count=$(count_running_model_installs)
	      if [ "$running_install_count" -eq 0 ] 2>/dev/null; then
	        cleanup_summary=$(cleanup_ollama_partial_blobs "full" || printf '%s' "removed=0|kept=0|resume_bytes=0|canonicalized=0")
	        stale_partial_files_removed_now=$(printf '%s' "$cleanup_summary" | awk -F'|' '{for (i=1;i<=NF;i++) if ($i ~ /^removed=/) { sub(/^removed=/, "", $i); print $i; exit }}')
	        [ -n "$stale_partial_files_removed_now" ] || stale_partial_files_removed_now=0
	        if [ "$stale_partial_files_removed_now" -gt "$stale_partial_files_removed" ] 2>/dev/null; then
	          stale_partial_files_removed=$stale_partial_files_removed_now
	          printf '%s\n' "$stale_partial_files_removed" > "$job_dir/stale_partial_files_removed"
	        fi
	      fi
	    fi

	    if [ "$status" = "done" ] && ! voice_component_installed "$installed_component"; then
	      status="failed"
      if [ -z "$status_reason" ]; then
        status_reason="Dictation installer reported success, but backend files are missing."
      fi
    fi
    log_tail=$(tail -n 160 "$job_dir/log" 2>/dev/null || true)
    install_phase="running"
    install_progress=""
    if [ "$status" = "done" ]; then
      install_phase="done"
      install_progress="100"
    elif [ "$status" = "failed" ]; then
      install_phase="failed"
      install_progress=""
    else
      parse_result=$(infer_model_install_phase_progress "$log_tail")
      install_phase=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      install_progress=$(printf '%s\n' "$parse_result" | cut -d'|' -f2)
      [ -n "$install_phase" ] || install_phase="running"
    fi

	    printf '{"success":true,"job":{"id":"%s","model":"%s","status":"%s","phase":"%s","progress_pct":"%s","started":"%s","finished":"%s","exit_code":"%s","log":"%s","resume_available":%s,"resume_bytes":"%s","stale_partial_files_removed":"%s"}}\n' \
	      "$(json_escape "$job_id")" \
	      "$(json_escape "$model_name")" \
	      "$(json_escape "$status")" \
      "$(json_escape "$install_phase")" \
      "$(json_escape "$install_progress")" \
	      "$(json_escape "$started")" \
	      "$(json_escape "$finished")" \
	      "$(json_escape "$exit_code")" \
	      "$(json_escape "$log_tail")" \
	      "$([ "$resume_available" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
	      "$(json_escape "$resume_bytes")" \
	      "$(json_escape "$stale_partial_files_removed")"
	    exit 0
