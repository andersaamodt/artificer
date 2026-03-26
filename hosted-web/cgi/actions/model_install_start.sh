# action: model_install_start
    model_name=$(trim "$(param "model")")
    if ! safe_model_name "$model_name"; then
      emit_error "invalid model name"
      exit 0
    fi

    for existing_job in "$model_installs_dir"/*; do
      [ -d "$existing_job" ] || continue
      running_model=$(read_file_line "$existing_job/model" "")
      running_status=$(read_file_line "$existing_job/status" "")
      running_pid=$(read_file_line "$existing_job/pid" "")
      if [ "$running_model" = "$model_name" ] && [ "$running_status" = "running" ] && [ -n "$running_pid" ]; then
        if kill -0 "$running_pid" 2>/dev/null; then
          printf '{"success":true,"job":{"id":"%s","model":"%s","status":"running"}}\n' \
            "$(json_escape "$(basename "$existing_job")")" \
            "$(json_escape "$model_name")"
          exit 0
        fi
      fi
    done

	    job_id=$(new_id)
	    job_dir="$model_installs_dir/$job_id"
	    mkdir -p "$job_dir"
	    log_file="$job_dir/log"
	    running_install_count=$(count_running_model_installs)
	    cleanup_mode="full"
	    if [ "$running_install_count" -gt 0 ]; then
	      cleanup_mode="stubs"
	    fi
	    cleanup_summary=$(cleanup_ollama_partial_blobs "$cleanup_mode" || printf '%s' "removed=0|kept=0|resume_bytes=0|canonicalized=0")
	    stale_partial_files_removed=$(printf '%s' "$cleanup_summary" | awk -F'|' '{for (i=1;i<=NF;i++) if ($i ~ /^removed=/) { sub(/^removed=/, "", $i); print $i; exit }}')
	    resume_bytes=$(printf '%s' "$cleanup_summary" | awk -F'|' '{for (i=1;i<=NF;i++) if ($i ~ /^resume_bytes=/) { sub(/^resume_bytes=/, "", $i); print $i; exit }}')
	    canonicalized_partial_file=$(printf '%s' "$cleanup_summary" | awk -F'|' '{for (i=1;i<=NF;i++) if ($i ~ /^canonicalized=/) { sub(/^canonicalized=/, "", $i); print $i; exit }}')
	    [ -n "$stale_partial_files_removed" ] || stale_partial_files_removed=0
	    [ -n "$resume_bytes" ] || resume_bytes=0
	    [ -n "$canonicalized_partial_file" ] || canonicalized_partial_file=0
	    resume_available=0
	    if [ "$resume_bytes" -gt 0 ] 2>/dev/null; then
	      resume_available=1
	    fi

	    printf '%s\n' "$model_name" > "$job_dir/model"
	    printf '%s\n' "running" > "$job_dir/status"
	    date +%s > "$job_dir/started"
	    printf '%s\n' "$resume_available" > "$job_dir/resume_available"
	    printf '%s\n' "$resume_bytes" > "$job_dir/resume_bytes"
	    printf '%s\n' "$stale_partial_files_removed" > "$job_dir/stale_partial_files_removed"
	    printf '%s\n' "$canonicalized_partial_file" > "$job_dir/canonicalized_partial_file"

	    runner_script="$job_dir/run-install.sh"
	    cat >"$runner_script" <<'EOF_RUNNER'
#!/bin/sh
set -eu
job_dir=$1
model_name=$2
log_file=$3

run_ai_dev_script_path=$4

resume_available=${5:-0}
resume_bytes=${6:-0}
stale_partial_files_removed=${7:-0}
canonicalized_partial_file=${8:-0}

if [ "$stale_partial_files_removed" -gt 0 ] 2>/dev/null; then
  printf '%s\n' "Removed $stale_partial_files_removed stale partial model download file(s) before starting." >>"$log_file"
fi
if [ "$canonicalized_partial_file" -gt 0 ] 2>/dev/null; then
  printf '%s\n' "Normalized resumable model download state to one canonical partial file." >>"$log_file"
fi
if [ "$resume_available" = "1" ] && [ "$resume_bytes" -gt 0 ] 2>/dev/null; then
  printf '%s\n' "Resuming model download from $resume_bytes byte(s) of existing partial data." >>"$log_file"
fi

set +e
"$run_ai_dev_script_path" install-llm "$model_name" >>"$log_file" 2>&1
install_rc=$?
set -e
if [ "$install_rc" -ne 0 ]; then
  ollama_bin=""
  if command -v ollama >/dev/null 2>&1; then
    ollama_bin=$(command -v ollama)
  elif [ -x "$HOME/.local/bin/ollama" ]; then
    ollama_bin="$HOME/.local/bin/ollama"
  elif [ -x "/opt/homebrew/bin/ollama" ]; then
    ollama_bin="/opt/homebrew/bin/ollama"
  elif [ -x "/usr/local/bin/ollama" ]; then
    ollama_bin="/usr/local/bin/ollama"
  fi

  if [ -n "$ollama_bin" ]; then
    printf '%s\n' "install-llm failed; retrying with direct ollama pull for $model_name" >>"$log_file"
    set +e
    "$ollama_bin" pull "$model_name" >>"$log_file" 2>&1
    install_rc=$?
    set -e
  fi
fi
printf '%s\n' "$install_rc" > "$job_dir/exit_code"
if [ "$install_rc" -eq 0 ]; then
  printf '%s\n' "done" > "$job_dir/status"
else
  printf '%s\n' "failed" > "$job_dir/status"
fi
date +%s > "$job_dir/finished"
EOF_RUNNER
    chmod +x "$runner_script"

    run_ai_dev_wrapper="$job_dir/run-ai-dev-wrapper"
    cat >"$run_ai_dev_wrapper" <<EOF_WRAPPER
#!/bin/sh
set -eu
AI_DEV_DIR=$(printf '%s\n' "$AI_DEV_DIR")
script_name=\$1
shift
script_path="\$AI_DEV_DIR/\$script_name"
if [ ! -x "\$script_path" ]; then
  exit 1
fi
"\$script_path" "\$@"
EOF_WRAPPER
    chmod +x "$run_ai_dev_wrapper"

	    install_pid=$(spawn_detached_job "$runner_script" "$job_dir" "$model_name" "$log_file" "$run_ai_dev_wrapper" "$resume_available" "$resume_bytes" "$stale_partial_files_removed" "$canonicalized_partial_file")
	    printf '%s\n' "$install_pid" > "$job_dir/pid"

	    printf '{"success":true,"job":{"id":"%s","model":"%s","status":"running","resume_available":%s,"resume_bytes":"%s","stale_partial_files_removed":"%s"}}\n' \
	      "$(json_escape "$job_id")" \
	      "$(json_escape "$model_name")" \
	      "$([ "$resume_available" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
	      "$(json_escape "$resume_bytes")" \
	      "$(json_escape "$stale_partial_files_removed")"
	    exit 0
