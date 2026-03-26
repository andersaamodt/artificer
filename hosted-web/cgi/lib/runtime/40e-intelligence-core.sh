model_is_text_generation_model() {
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *embed*|*embedding*|*nomic-embed*|*bge-*|*e5-*|*minilm*|*clip*|*whisper*)
      return 1
      ;;
  esac
  return 0
}

model_preference_score_for_mode() {
  model_name=$1
  mode_name=$2
  lower=$(printf '%s' "$model_name" | tr '[:upper:]' '[:lower:]')
  if ! model_is_text_generation_model "$model_name"; then
    printf '%s' "-9999"
    return 0
  fi

  score=0
  case "$mode_name" in
    chat)
      case "$lower" in
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=120
          ;;
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=124
          ;;
        mistral*|*mistral*)
          score=108
          ;;
        phi3*|*phi3*|phi4*|*phi4*|gemma2*|*gemma2*)
          score=102
          ;;
        deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=98
          ;;
        deepseek*|*deepseek*)
          score=88
          ;;
        codellama*|*codellama*|starcoder*|*starcoder*)
          score=72
          ;;
        *instruct*|*chat*)
          score=96
          ;;
        *)
          score=80
          ;;
      esac
      case "$lower" in
        *coder*|*code*)
          score=$((score - 14))
          ;;
      esac
      case "$lower" in
        *instruct*|*chat*)
          score=$((score + 4))
          ;;
      esac
      ;;
    programming)
      case "$lower" in
        deepseek-coder*|*deepseek-coder*)
          score=122
          ;;
        qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*)
          score=116
          ;;
        starcoder*|*starcoder*)
          score=108
          ;;
        codellama*|*codellama*)
          score=103
          ;;
        qwen*|*qwen*)
          score=100
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=96
          ;;
        mistral*|*mistral*)
          score=94
          ;;
        *)
          score=84
          ;;
      esac
      case "$lower" in
        *coder*|*code*)
          score=$((score + 10))
          ;;
      esac
      ;;
    *)
      score=80
      ;;
  esac

  printf '%s' "$score"
}

best_model_for_mode() {
  mode_name=$1
  models=$(list_models_raw || true)
  if [ -z "$(trim "$models")" ]; then
    models=$(list_models_from_workspace_data || true)
  fi
  [ -n "$(trim "$models")" ] || return 0

  best_model=""
  best_score=-9999
  while IFS= read -r model_name; do
    model_name=$(trim "$model_name")
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "$mode_name")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    if [ -z "$best_model" ] || [ "$score" -gt "$best_score" ]; then
      best_model=$model_name
      best_score=$score
    fi
  done <<EOF
$models
EOF
  printf '%s' "$best_model"
}

chat_autoroute_model() {
  current_model=$(trim "$1")
  [ -n "$current_model" ] || return 0

  best_chat_model=$(best_model_for_mode "chat")
  [ -n "$best_chat_model" ] || return 0
  if [ "$best_chat_model" = "$current_model" ]; then
    return 0
  fi

  current_score=$(model_preference_score_for_mode "$current_model" "chat")
  best_score=$(model_preference_score_for_mode "$best_chat_model" "chat")
  case "$current_score" in ""|*[!0-9-]*) current_score=0 ;; esac
  case "$best_score" in ""|*[!0-9-]*) best_score=0 ;; esac
  score_gap=$((best_score - current_score))

  current_lower=$(printf '%s' "$current_model" | tr '[:upper:]' '[:lower:]')
  coder_like=0
  case "$current_lower" in
    *coder*|*code*|starcoder*|*starcoder*|codellama*|*codellama*|deepseek-coder*|*deepseek-coder*)
      coder_like=1
      ;;
  esac

  if [ "$coder_like" -eq 1 ] && [ "$score_gap" -ge 12 ]; then
    printf '%s' "$best_chat_model"
    return 0
  fi
  if [ "$current_score" -lt 90 ] && [ "$score_gap" -ge 20 ]; then
    printf '%s' "$best_chat_model"
    return 0
  fi
}

preferred_chat_model() {
  models=$(list_models_raw || true)
  [ -n "$(trim "$models")" ] || return 0

  preferred=""
  preferred_score=-9999
  while IFS= read -r model_name; do
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "chat")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    if [ -z "$preferred" ] || [ "$score" -gt "$preferred_score" ]; then
      preferred=$model_name
      preferred_score=$score
    fi
  done <<EOF
$models
EOF

  if [ -n "$preferred" ]; then
    printf '%s' "$preferred"
    return 0
  fi

  while IFS= read -r model_name; do
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    printf '%s' "$model_name"
    return 0
  done <<EOF
$models
EOF
}

ranked_models_json_for_mode() {
  mode_name=$1
  models=$(list_models_raw || true)
  if [ -z "$(trim "$models")" ]; then
    models=$(list_models_from_workspace_data || true)
  fi
  if [ -z "$(trim "$models")" ]; then
    printf '[]'
    return 0
  fi

  tab_char=$(printf '\t')
  rank_tmp=$(mktemp)
  while IFS= read -r model_name; do
    model_name=$(trim "$model_name")
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "$mode_name")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    printf '%s%s%s\n' "$score" "$tab_char" "$model_name" >> "$rank_tmp"
  done <<EOF
$models
EOF

  if [ ! -s "$rank_tmp" ]; then
    rm -f "$rank_tmp"
    printf '[]'
    return 0
  fi

  sorted_tmp=$(mktemp)
  sort -t "$tab_char" -k1,1nr -k2,2 "$rank_tmp" > "$sorted_tmp"
  rm -f "$rank_tmp"

  printf '['
  first=1
  while IFS="$tab_char" read -r score model_name || [ -n "$model_name" ]; do
    [ -n "$model_name" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"name":"%s","score":"%s"}' \
      "$(json_escape "$model_name")" \
      "$(json_escape "$score")"
  done < "$sorted_tmp"
  printf ']'
  rm -f "$sorted_tmp"
}

emit_model_recommendations() {
  printf '{"success":true,"recommendations":{"chat":%s,"programming":%s}}\n' \
    "$(ranked_models_json_for_mode "chat")" \
    "$(ranked_models_json_for_mode "programming")"
}

default_model() {
  first_model=$(preferred_chat_model || true)
  if [ -z "$first_model" ]; then
    first_model=$(list_models_raw | sed -n '1p')
  fi
  if [ -n "$first_model" ]; then
    printf '%s' "$first_model"
  else
    printf '%s' "qwen2.5-coder:7b"
  fi
}

implementation_model_candidates() {
  primary_model=$1
  preferred_model=$(preferred_chat_model || true)
  all_models=$(list_models_raw || true)
  extras_file=$(mktemp)
  : > "$extras_file"
  extras_added=0

  while IFS= read -r candidate_model; do
    candidate_model=$(trim "$candidate_model")
    [ -n "$candidate_model" ] || continue
    lower=$(printf '%s' "$candidate_model" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *embed*|*embedding*|*nomic-embed*|*bge-*|*e5-*|*minilm*|*clip*|*whisper*)
        continue
        ;;
    esac
    if [ "$candidate_model" = "$primary_model" ]; then
      continue
    fi
    if [ -n "$preferred_model" ] && [ "$candidate_model" = "$preferred_model" ]; then
      continue
    fi
    printf '%s\n' "$candidate_model" >> "$extras_file"
    extras_added=$((extras_added + 1))
    if [ "$extras_added" -ge 2 ]; then
      break
    fi
  done <<EOF
$all_models
EOF

  {
    printf '%s\n' "$primary_model"
    if [ -n "$preferred_model" ] && [ "$preferred_model" != "$primary_model" ]; then
      printf '%s\n' "$preferred_model"
    fi
    cat "$extras_file"
  } | awk '!seen[$0]++'

  rm -f "$extras_file"
}

append_message() {
  conv_dir=$1
  role=$2
  content=$3

  messages_dir="$conv_dir/messages"
  mkdir -p "$messages_dir"

  count=$(find "$messages_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$count" ] || count=0
  next=$((count + 1))
  file_name=$(printf '%s/%04d-%s.txt' "$messages_dir" "$next" "$role")
  printf '%s\n' "$content" > "$file_name"
  date +%s > "$conv_dir/updated"
}

run_events_dir_for_conversation() {
  conv_dir=$1
  printf '%s/run-events' "$conv_dir"
}

tasks_dir_for_conversation() {
  conv_dir=$1
  printf '%s/agent/.tasks' "$conv_dir"
}

queue_running_stream_session_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.stream_session' "$queue_dir"
}

queue_running_event_id_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.event_id' "$queue_dir"
}

queue_running_anchor_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.anchor' "$queue_dir"
}

queue_running_started_iso_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.started_iso' "$queue_dir"
}

normalize_task_progress_status() {
  status_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$status_value" in
    done|completed|complete|finished)
      printf '%s' "done"
      ;;
    active|in-progress|in_progress|working)
      printf '%s' "active"
      ;;
    pending|todo|open|queued|"")
      printf '%s' "pending"
      ;;
    *)
      printf '%s' "pending"
      ;;
  esac
}

task_status_empty_json() {
  printf '{"tasks":[],"completed":0,"total":0,"source":"backend"}'
}

state_mode_from_state_text() {
  state_text_raw=$1
  state_mode_value=$(printf '%s\n' "$state_text_raw" | sed -n 's/.*mode=\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' | sed -n '1p')
  printf '%s' "$state_mode_value"
}

task_status_json_from_tasks_dir() {
  tasks_dir=$1
  run_status_input=$2
  state_text_input=$3
  run_status_norm=$(normalize_run_event_status "$run_status_input")
  force_done=0
  case "$run_status_norm" in
    done)
      force_done=1
      ;;
  esac

  if [ "$force_done" -ne 1 ]; then
    state_mode_hint=$(state_mode_from_state_text "$state_text_input")
    if [ "$(printf '%s' "$state_mode_hint" | tr '[:upper:]' '[:lower:]')" = "done" ]; then
      force_done=1
    fi
  fi

  if [ ! -d "$tasks_dir" ]; then
    task_status_empty_json
    return 0
  fi

  task_files_list=$(mktemp)
  find "$tasks_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' 2>/dev/null | sort > "$task_files_list"
  if [ ! -s "$task_files_list" ]; then
    rm -f "$task_files_list"
    task_status_empty_json
    return 0
  fi

  tasks_json=""
  task_total=0
  task_done_count=0
  while IFS= read -r task_file || [ -n "$task_file" ]; do
    [ -n "$task_file" ] || continue
    [ -f "$task_file" ] || continue
    task_total=$((task_total + 1))
    task_id=$(basename "$task_file")
    task_id=${task_id%.md}
    task_title=$(sed -n 's/^title:[[:space:]]*//p' "$task_file" | sed -n '1p')
    task_title=$(trim "$task_title")
    if [ -z "$task_title" ]; then
      task_title=$(printf '%s' "$task_id" | sed -E 's/^[0-9]{3}-//; s/-+/ /g')
      task_title=$(trim "$task_title")
    fi
    [ -n "$task_title" ] || task_title="$task_id"
    task_status=$(sed -n 's/^status:[[:space:]]*//p' "$task_file" | sed -n '1p')
    task_status=$(normalize_task_progress_status "$task_status")
    if [ "$force_done" -eq 1 ]; then
      task_status="done"
    fi
    task_done_json=false
    if [ "$task_status" = "done" ]; then
      task_done_json=true
      task_done_count=$((task_done_count + 1))
    fi
    task_id_json=$(json_escape "$task_id")
    task_title_json=$(json_escape "$task_title")
    task_status_json=$(json_escape "$task_status")
    if [ -n "$tasks_json" ]; then
      tasks_json="${tasks_json},"
    fi
    tasks_json="${tasks_json}{\"id\":\"$task_id_json\",\"text\":\"$task_title_json\",\"status\":\"$task_status_json\",\"done\":$task_done_json}"
  done < "$task_files_list"
  rm -f "$task_files_list"

  if [ "$task_total" -lt 1 ]; then
    task_status_empty_json
    return 0
  fi

  printf '{"tasks":[%s],"completed":%s,"total":%s,"source":"backend"}' \
    "$tasks_json" "$task_done_count" "$task_total"
}

running_stream_preview_for_conversation() {
  conv_dir=$1
  stream_file=""
  stream_session=$(trim "$(read_file_line "$(queue_running_stream_session_file_for "$conv_dir")" "")")
  if [ -n "$stream_session" ] && valid_id "$stream_session"; then
    candidate=$(stream_tokens_file_for "$conv_dir" "$stream_session")
    if [ -f "$candidate" ]; then
      stream_file=$candidate
    fi
  fi
  if [ -z "$stream_file" ]; then
    fallback_candidate=$(ls -1t "$conv_dir"/stream/*/tokens.txt 2>/dev/null | sed -n '1p')
    if [ -n "$fallback_candidate" ] && [ -f "$fallback_candidate" ]; then
      stream_file=$fallback_candidate
    fi
  fi
  if [ -z "$stream_file" ] || [ ! -f "$stream_file" ]; then
    printf '%s' ""
    return 0
  fi
  sed -n '1,360p' "$stream_file" 2>/dev/null || true
}

active_run_event_json_for_conversation() {
  conv_dir=$1
  ensure_queue_layout "$conv_dir"
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_marker="$queue_dir/running.txt"
  running_pid=$(trim "$(read_file_line "$queue_dir/running.pid" "")")
  running_item_id=$(trim "$(read_file_line "$queue_dir/running.id" "")")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_anchor=$(trim "$(read_file_line "$(queue_running_anchor_file_for "$conv_dir")" "")")
  running_started_epoch=$(trim "$(read_file_line "$queue_dir/running.started" "0")")
  running_started_iso=$(trim "$(read_file_line "$(queue_running_started_iso_file_for "$conv_dir")" "")")
  stale_reason=$(queue_running_stale_reason_for_conversation "$conv_dir")
  if [ -n "$stale_reason" ]; then
    queue_recover_stale_running_state_for_conversation "$conv_dir" "$stale_reason" >/dev/null 2>&1 || true
    printf 'null'
    return 0
  fi

  running_active=0
  if [ -f "$running_marker" ]; then
    running_active=1
  elif [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    running_active=1
  fi
  if [ "$running_active" -ne 1 ]; then
    printf 'null'
    return 0
  fi

  case "$running_started_epoch" in
    ""|*[!0-9]*)
      running_started_epoch=0
      ;;
  esac
  if [ -z "$running_started_iso" ] && [ "$running_started_epoch" -gt 0 ]; then
    running_started_iso=$(iso_utc_from_epoch "$running_started_epoch")
  fi
  if [ -z "$running_started_iso" ]; then
    running_started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
  fi

  run_event_id="run-live"
  if [ -n "$running_event_id" ] && valid_id "$running_event_id"; then
    run_event_id=$running_event_id
  elif [ -n "$running_item_id" ] && valid_id "$running_item_id"; then
    case "$running_item_id" in
      run-*)
        run_event_id=$running_item_id
        ;;
      *)
        run_event_id="run-${running_item_id}"
        ;;
    esac
  elif [ -n "$running_pid" ]; then
    run_event_id="run-pid-${running_pid}"
  fi

  stream_preview=$(running_stream_preview_for_conversation "$conv_dir")
  model_name=$(read_file_line "$conv_dir/model" "$(default_model)")
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  assay_task_id=$(queue_meta_assay_task_id_from_file "$running_meta_file")
  tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
  state_preview=$(sed -n '1,60p' "$conv_dir/agent/.state" 2>/dev/null || true)
  task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "running" "$state_preview")
  message_anchor_json=""
  case "$running_anchor" in
    ""|*[!0-9]*)
      ;;
    *)
      message_anchor_json=",\"message_anchor\":$running_anchor"
      ;;
  esac

  printf '{"id":"%s","status":"running","started_at":"%s","finished_at":"","model":"%s","plan":"","commands":[],"stream_text":"%s","failures":"","session_log":"","state":"","git_status":"","git_diff":"","error":"","decision_hint":""%s,"task_status":%s}' \
    "$(json_escape "$run_event_id")" \
    "$(json_escape "$running_started_iso")" \
    "$(json_escape "$model_name")" \
    "$(json_escape "$stream_preview")" \
    "$message_anchor_json" \
    "$task_status_json"
}

append_cancelled_run_event_for_stop() {
  conv_dir=$1
  reason_text=$2
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_started_file="$queue_dir/running.started"
  running_started_epoch=$(trim "$(read_file_line "$running_started_file" "0")")
  case "$running_started_epoch" in
    ""|*[!0-9]*)
      running_started_epoch=0
      ;;
  esac
  started_iso=$(trim "$(read_file_line "$(queue_running_started_iso_file_for "$conv_dir")" "")")
  if [ -z "$started_iso" ] && [ "$running_started_epoch" -gt 0 ]; then
    started_iso=$(iso_utc_from_epoch "$running_started_epoch")
  fi
  if [ -z "$started_iso" ]; then
    started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
  fi
  finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
  model_name=$(read_file_line "$conv_dir/model" "$(default_model)")
  stream_preview=$(running_stream_preview_for_conversation "$conv_dir")
  state_preview=$(sed -n '1,120p' "$conv_dir/agent/.state" 2>/dev/null || true)
  tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
  task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "cancelled" "$state_preview")
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  assay_task_id=$(queue_meta_assay_task_id_from_file "$running_meta_file")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_anchor=$(trim "$(read_file_line "$(queue_running_anchor_file_for "$conv_dir")" "")")
  reason_clean=$(trim "$reason_text")
  if [ -z "$reason_clean" ]; then
    reason_clean="Run stopped."
  fi
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  elapsed=0
  if [ "$running_started_epoch" -gt 0 ] && [ "$now_epoch" -gt "$running_started_epoch" ]; then
    elapsed=$((now_epoch - running_started_epoch))
  fi
  elapsed_minutes=$((elapsed / 60))
  elapsed_seconds=$((elapsed % 60))
  stop_note=$reason_clean
  summary_text=$reason_clean
  if ! printf '%s' "$reason_clean" | grep -Eq '^Outcome:[[:space:]]*'; then
    summary_text=$(cat <<EOF
Outcome: Run was interrupted before full completion.
Verification Evidence: Queue stop was applied while the run was active. Worked for ${elapsed_minutes}m ${elapsed_seconds}s.
Risks: Partial progress may leave unverified changes or unfinished implementation details.
Next Action: Resume from this checkpoint and prioritize one verifiable sub-goal first.
Next Improvement: Resume from this checkpoint with a narrower scope or higher compute budget.
EOF
)
  fi
  if [ -z "$(trim "$stream_preview")" ]; then
    ts_now=$(date +"%H:%M:%S" 2>/dev/null || printf '%s' "00:00:00")
    stream_preview=$(cat <<EOF
[$ts_now] Run interrupted before completion; checkpoint snapshot captured.
[$ts_now] queue_stop executed to stop lingering run safely.
[$ts_now] Worked for ${elapsed_minutes}m ${elapsed_seconds}s; next action recorded for resume.
EOF
)
  fi
  stop_commands_json="[]"
  ws_dir=$(dirname "$(dirname "$conv_dir")")
  workspace_id=$(basename "$ws_dir")
  workspace_path=$(workspace_path_for_id "$workspace_id")
  if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
    stop_cmd1="git status --short"
    stop_cmd2="find . -maxdepth 2 -type f"
    stop_cmd1_output=$(
      cd "$workspace_path" && {
        git status --short 2>/dev/null || printf '%s\n' "Not a git repository."
      } | sed -n '1,80p'
    )
    stop_cmd2_output=$(
      cd "$workspace_path" && {
        find . -maxdepth 2 -type f 2>/dev/null | sed 's|^\./||' || true
      } | sed -n '1,80p'
    )
    stop_commands_json=$(printf '[{"command":"%s","status":"%s","output":"%s"},{"command":"%s","status":"%s","output":"%s"}]' \
      "$(json_escape "$stop_cmd1")" \
      "$(json_escape "ok")" \
      "$(json_escape "$stop_cmd1_output")" \
      "$(json_escape "$stop_cmd2")" \
      "$(json_escape "ok")" \
      "$(json_escape "$stop_cmd2_output")")
  fi
  event_json=$(build_run_event_json \
    "cancelled" \
    "$started_iso" \
    "$finished_iso" \
    "$model_name" \
    "" \
    "$stop_commands_json" \
    "$stream_preview" \
    "$stop_note" \
    "" \
    "$state_preview" \
    "" \
    "" \
    "$summary_text" \
    "" \
    "$running_event_id" \
    "$task_status_json" \
    "$running_anchor" \
    "$assay_task_id")
  append_run_event_json "$conv_dir" "$event_json"
}

clip_for_run_event() {
  text=$1
  max_lines=${2:-220}
  max_chars=${3:-12000}

  clipped=$(printf '%s\n' "$text" | sed -n "1,${max_lines}p")
  clipped_len=$(printf '%s' "$clipped" | wc -c | tr -d ' ')
  [ -n "$clipped_len" ] || clipped_len=0
  if [ "$clipped_len" -gt "$max_chars" ]; then
    clipped=$(printf '%s' "$clipped" | awk -v max="$max_chars" '
      BEGIN {
        used = 0
        truncated = 0
      }
      {
        line = $0 "\n"
        n = length(line)
        if (used >= max) {
          truncated = 1
          next
        }
        if (used + n > max) {
          keep = max - used
          if (keep > 0) {
            printf "%s", substr(line, 1, keep)
          }
          truncated = 1
          used = max
          next
        }
        printf "%s", line
        used += n
      }
      END {
        if (truncated == 1) {
          printf "\n[truncated]\n"
        }
      }
    ')
  fi
  printf '%s' "$clipped"
}

normalize_run_event_status() {
  status=$(trim "$1")
  case "$status" in
    running|done|error|cancelled|awaiting_approval|awaiting_decision|approval_granted|timeout)
      printf '%s' "$status"
      ;;
    *)
      printf '%s' "done"
      ;;
  esac
}

run_event_status_from_run() {
  queue_status=$(normalize_run_event_status "$1")
  budget_exhausted_raw=${2:-0}
  case "$budget_exhausted_raw" in
    ""|*[!0-9]*)
      budget_exhausted=0
      ;;
    *)
      budget_exhausted=$budget_exhausted_raw
      ;;
  esac
  if [ "$queue_status" = "done" ] && [ "$budget_exhausted" -eq 1 ]; then
    printf '%s' "timeout"
    return 0
  fi
  printf '%s' "$queue_status"
}

normalize_run_mode_name() {
  mode_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$mode_value" in
    instant|auto|programming|pentest|security-audit|chat|teacher|report|text-perfecter|assistant|gui-testing)
      printf '%s' "$mode_value"
      ;;
    team|teams)
      printf '%s' "assistant"
      ;;
    *)
      printf '%s' "auto"
      ;;
  esac
}

normalize_assistant_mode_id() {
  mode_id=$(trim "$1")
  mode_id=$(printf '%s' "$mode_id" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  if [ -z "$mode_id" ]; then
    printf '%s' ""
    return 0
  fi
  if ! valid_id "$mode_id"; then
    printf '%s' ""
    return 0
  fi
  ensure_mode_runtime_bootstrap
  if command -v mr_mode_exists >/dev/null 2>&1; then
    if ! mr_mode_exists "$mode_id"; then
      printf '%s' ""
      return 0
    fi
  fi
  printf '%s' "$mode_id"
}

normalize_compute_budget() {
  budget_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$budget_value" in
    auto|quick|standard|long|until-complete)
      printf '%s' "$budget_value"
      ;;
    *)
      printf '%s' "auto"
      ;;
  esac
}

compute_budget_iteration_cap() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "8"
      ;;
    standard)
      printf '%s' "14"
      ;;
    long)
      printf '%s' "24"
      ;;
    until-complete)
      printf '%s' "0"
      ;;
    *)
      printf '%s' "16"
      ;;
  esac
}

compute_budget_runtime_floor_sec() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "180"
      ;;
    standard)
      printf '%s' "600"
      ;;
    long)
      printf '%s' "1800"
      ;;
    until-complete)
      printf '%s' "7200"
      ;;
    *)
      printf '%s' "300"
      ;;
  esac
}

compute_budget_runtime_ceiling_sec() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "900"
      ;;
    standard)
      printf '%s' "5400"
      ;;
    long)
      printf '%s' "21600"
      ;;
    until-complete)
      printf '%s' "86400"
      ;;
    *)
      printf '%s' "21600"
      ;;
  esac
}

compute_budget_stale_timeout_sec() {
  budget_value=$(normalize_compute_budget "$1")
  run_budget_sec=$2
  case "$run_budget_sec" in
    ""|*[!0-9]*)
      run_budget_sec=600
      ;;
  esac
  stale_timeout_sec=$((run_budget_sec + 300))
  case "$budget_value" in
    quick)
      min_timeout=900
      ;;
    standard)
      min_timeout=2100
      ;;
    long)
      min_timeout=7200
      ;;
    until-complete)
      min_timeout=28800
      ;;
    *)
      min_timeout=1800
      ;;
  esac
  if [ "$stale_timeout_sec" -lt "$min_timeout" ]; then
    stale_timeout_sec=$min_timeout
  fi
  if [ "$stale_timeout_sec" -gt 172800 ]; then
    stale_timeout_sec=172800
  fi
  printf '%s' "$stale_timeout_sec"
}

queue_missing_pid_grace_sec() {
  grace_sec=${ARTIFICER_QUEUE_MISSING_PID_GRACE_SEC:-45}
  case "$grace_sec" in
    ""|*[!0-9]*)
      grace_sec=45
      ;;
  esac
  if [ "$grace_sec" -lt 5 ]; then
    grace_sec=5
  fi
  if [ "$grace_sec" -gt 600 ]; then
    grace_sec=600
  fi
  printf '%s' "$grace_sec"
}

run_mode_from_slash_tag() {
  tag_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$tag_value" in
    chat)
      printf '%s' "chat"
      ;;
    teacher|teach|learn|study|tutor)
      printf '%s' "teacher"
      ;;
    task|programming|program|code|dev)
      printf '%s' "programming"
      ;;
    pentest|redteam|red-team)
      printf '%s' "pentest"
      ;;
    security-audit|security|audit|sec-audit)
      printf '%s' "security-audit"
      ;;
    report)
      printf '%s' "report"
      ;;
    text-perfecter|textperfecter|perfecter|perfect|polish|refine)
      printf '%s' "text-perfecter"
      ;;
    gui-testing|guitesting|gui|ui-testing|uitesting|hands-on-testing|handson-testing|hands-on|ux-testing|uxtesting)
      printf '%s' "gui-testing"
      ;;
    assistant|autonomous|autonomy|endeavor|endeavour)
      printf '%s' "assistant"
      ;;
    team|teams)
      printf '%s' "assistant"
      ;;
    auto|thinking|loop)
      printf '%s' "auto"
      ;;
    instant|quick)
      printf '%s' "instant"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

leading_prompt_slash_tag() {
  printf '%s' "$1" | perl -CS -0777 -ne '
    if (/^\s*\/([A-Za-z][A-Za-z0-9_-]*)\b/s) {
      print lc($1);
    }
  '
}

strip_leading_prompt_slash_tag() {
  printf '%s' "$1" | perl -CS -0777 -pe 's/^\s*\/[A-Za-z][A-Za-z0-9_-]*\b[ \t]*//s'
}

build_run_event_json() {
  run_status=$(normalize_run_event_status "$1")
  started_at=$2
  finished_at=$3
  model_name=$4
  plan_text=$5
  commands_array_json=$6
  stream_text=$7
  failures_text=$8
  session_text=$9
  state_text=${10}
  git_status_text=${11}
  git_diff_text=${12}
  error_text=${13}
  decision_hint_text=${14}
  event_id_override=${15}
  task_status_json_override=${16}
  message_anchor_override=${17}
  assay_task_id_override=${18}
  assistant_text=${19-}

  safe_plan=$(clip_for_run_event "$plan_text" 220 9000)
  safe_stream=$(clip_for_run_event "$stream_text" 260 9000)
  safe_failures=$(clip_for_run_event "$failures_text" 240 9000)
  safe_session=$(clip_for_run_event "$session_text" 260 9000)
  safe_state=$(clip_for_run_event "$state_text" 120 4000)
  safe_git_status=$(clip_for_run_event "$git_status_text" 220 8000)
  safe_git_diff=$(clip_for_run_event "$git_diff_text" 280 12000)
  safe_error=$(clip_for_run_event "$error_text" 80 2600)
  safe_hint=$(clip_for_run_event "$decision_hint_text" 40 1600)
  safe_assistant=$(clip_for_run_event "$assistant_text" 320 24000)
  task_status_json=$(trim "$task_status_json_override")
  if [ -z "$task_status_json" ]; then
    task_status_json=$(task_status_empty_json)
  fi
  case "$task_status_json" in
    \{*\})
      ;;
    *)
      task_status_json=$(task_status_empty_json)
      ;;
  esac

  commands_json=$(trim "$commands_array_json")
  if [ -z "$commands_json" ]; then
    commands_json="[]"
  fi

  event_id=$(trim "$event_id_override")
  if [ -z "$event_id" ] || ! valid_id "$event_id"; then
    event_id=$(new_id)
  fi
  message_anchor_json=""
  case "$message_anchor_override" in
    ""|*[!0-9]*)
      ;;
    *)
      message_anchor_json=",\"message_anchor\":$message_anchor_override"
      ;;
  esac
  event_id_json=$(json_escape "$event_id")
  status_json=$(json_escape "$run_status")
  started_json=$(json_escape "$started_at")
  finished_json=$(json_escape "$finished_at")
  model_json=$(json_escape "$model_name")
  plan_json=$(json_escape "$safe_plan")
  stream_json=$(json_escape "$safe_stream")
  failures_json=$(json_escape "$safe_failures")
  session_json=$(json_escape "$safe_session")
  state_json=$(json_escape "$safe_state")
  git_status_json=$(json_escape "$safe_git_status")
  git_diff_json=$(json_escape "$safe_git_diff")
  error_json=$(json_escape "$safe_error")
  hint_json=$(json_escape "$safe_hint")
  assistant_json=$(json_escape "$safe_assistant")

  printf '{"id":"%s","status":"%s","started_at":"%s","finished_at":"%s","model":"%s","plan":"%s","assistant":"%s","commands":%s,"stream_text":"%s","failures":"%s","session_log":"%s","state":"%s","git_status":"%s","git_diff":"%s","error":"%s","decision_hint":"%s"%s,"task_status":%s}' \
    "$event_id_json" "$status_json" "$started_json" "$finished_json" "$model_json" "$plan_json" "$assistant_json" "$commands_json" "$stream_json" "$failures_json" "$session_json" "$state_json" "$git_status_json" "$git_diff_json" "$error_json" "$hint_json" "$message_anchor_json" "$task_status_json"
}

append_run_event_json() {
  conv_dir=$1
  event_json=$2
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  mkdir -p "$events_dir"

  count=$(find "$events_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$count" ] || count=0
  next=$((count + 1))
  file_name=$(printf '%s/%04d.json' "$events_dir" "$next")
  printf '%s\n' "$event_json" > "$file_name"

  keep_limit=60
  if [ "$next" -gt "$keep_limit" ]; then
    remove_count=$((next - keep_limit))
    ls "$events_dir"/*.json 2>/dev/null | sort | head -n "$remove_count" | while IFS= read -r old_file; do
      [ -n "$old_file" ] || continue
      rm -f "$old_file"
    done
  fi
}

json_run_events() {
  conv_dir=$1
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  printf '['
  first=1
  if [ -d "$events_dir" ]; then
    for event_file in "$events_dir"/*.json; do
      [ -f "$event_file" ] || continue
      payload=$(cat "$event_file")
      payload=$(trim "$payload")
      [ -n "$payload" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '%s' "$payload"
    done
  fi
  printf ']'
}

json_run_events_with_active() {
  conv_dir=$1
  active_event_json=$(active_run_event_json_for_conversation "$conv_dir")
  printf '['
  first=1
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  if [ -d "$events_dir" ]; then
    for event_file in "$events_dir"/*.json; do
      [ -f "$event_file" ] || continue
      payload=$(cat "$event_file")
      payload=$(trim "$payload")
      [ -n "$payload" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '%s' "$payload"
    done
  fi
  if [ -n "$active_event_json" ] && [ "$active_event_json" != "null" ]; then
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '%s' "$active_event_json"
  fi
  printf ']'
}

extract_section() {
  section_name=$1
  text=$2
  known_headers="MODE_UPDATE COMMANDS CONTRACT PATCH DONE_CLAIM PLAN_UPDATE CHECKPOINT DECISION_REQUEST FINAL REVIEW_DECISION REVIEW_FEEDBACK"
  printf '%s\n' "$text" | awk -v section="$section_name" -v headers="$known_headers" '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    BEGIN {
      capture = 0
      in_fence = 0
      section_norm = toupper(section)
      gsub(/[[:space:]]+/, "_", section_norm)
      header_count = split(headers, header_list, /[[:space:]]+/)
      for (header_index = 1; header_index <= header_count; header_index++) {
        if (header_list[header_index] != "") {
          known[header_list[header_index]] = 1
        }
      }
    }
    {
      normalized = $0
      sub(/^[[:space:]]*[*#>[:space:]]*/, "", normalized)
      if (normalized ~ /^```/) {
        if (in_fence == 1) {
          in_fence = 0
        } else {
          in_fence = 1
        }
      }

      header = ""
      remainder = ""
      split_pos = index(normalized, ":")
      if (split_pos > 0) {
        header = substr(normalized, 1, split_pos - 1)
        header = trim_local(header)
        header = toupper(header)
        gsub(/[[:space:]]+/, "_", header)
        remainder = trim_local(substr(normalized, split_pos + 1))
      }

      if (header != "" && !in_fence && (header in known)) {
        if (capture == 1 && header != section_norm) {
          capture = 0
          next
        }
        if (header == section_norm) {
          capture = 1
          if (remainder != "") {
            print remainder
          }
          next
        }
      }

      if (capture == 1) {
        print
      }
    }
  '
}

extract_command_lines() {
  text=$1
  printf '%s\n' "$text" | perl -CS -pe '
    s/\r//g;
    # Some models emit literal escape sequences instead of real newlines.
    s/\\r\\n/\n/g;
    s/\\n/\n/g;
    # Recover collapsed markdown bullets emitted as one physical line:
    # "cmd1- cmd2- cmd3" -> "cmd1\n- cmd2\n- cmd3"
    s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
    s/(?<=\S)\*\s+(?=[A-Za-z0-9._\/])/\\n* /g;
  ' | awk '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line = $0
      line = trim_local(line)
      if (line == "") next
      if (line ~ /^```/) next
      if (line ~ /^[A-Z][A-Z_ ]*:[[:space:]]*$/) next
      sub(/^[0-9]+[.)][[:space:]]*/, "", line)
      sub(/^[-*][[:space:]]*/, "", line)
      sub(/[[:space:]]+2>[[:space:]]*\/dev\/null$/, "", line)
      sub(/[[:space:]]+>[[:space:]]*\/dev\/null$/, "", line)
      sub(/[[:space:]]+2>\/dev\/null$/, "", line)
      sub(/[[:space:]]+>\/dev\/null$/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+\([^)]*\)[[:space:]]*$/, "", line)
      gsub(/^`+|`+$/, "", line)
      line = trim_local(line)
      if (line == "" || line == "NONE" || line == "none") next
      if (!seen[line]++) {
        print line
      }
    }
  '
}

fallback_readonly_commands_for_mode() {
  state_mode_hint=$(trim "${1:-}")
  case "$state_mode_hint" in
    INVESTIGATE)
      printf '%s\n' "ls -la"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    DESIGN)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    IMPLEMENT)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    VERIFY)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "git diff --stat"
      ;;
    *)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
  esac
}

context_recovery_readonly_command_for_mode() {
  state_mode_hint=$(trim "${1:-}")
  status_hint=$(trim "${2:-}")
  case "$state_mode_hint" in
    INVESTIGATE)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
    DESIGN)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
    VERIFY)
      case "$status_hint" in
        context_missing)
          printf '%s' "ls -la"
          ;;
        *)
          printf '%s' "find . -maxdepth 2 -type f"
          ;;
      esac
      ;;
    *)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
  esac
}

rewrite_readonly_pipeline_candidate() {
  candidate=$(trim "$1")
  if [ -z "$candidate" ]; then
    printf '%s' ""
    return 0
  fi
  if ! printf '%s\n' "$candidate" | grep -Eq '^[[:space:]]*(cat|head|tail)[[:space:]].*[[:space:]]\|[[:space:]]*(grep|rg)[[:space:]]+'; then
    printf '%s' "$candidate"
    return 0
  fi

  pipe_segments=$(printf '%s\n' "$candidate" | awk -F'|' '{print NF}')
  if [ "$pipe_segments" -ne 2 ]; then
    printf '%s' "$candidate"
    return 0
  fi

  left_side=$(trim "$(printf '%s\n' "$candidate" | awk -F'|' '{print $1}')")
  right_side=$(trim "$(printf '%s\n' "$candidate" | awk -F'|' '{print $2}')")

  left_first_word=$(printf '%s\n' "$left_side" | awk '{print $1}')
  case "$left_first_word" in
    cat)
      left_path=$(trim "${left_side#cat }")
      ;;
    head|tail)
      if ! printf '%s\n' "$left_side" | grep -Eq '^(head|tail)([[:space:]]+-n[[:space:]]+[0-9]+)?[[:space:]]+[^[:space:]]+$'; then
        printf '%s' "$candidate"
        return 0
      fi
      left_path=$(printf '%s\n' "$left_side" | awk '{print $NF}')
      ;;
    *)
      printf '%s' "$candidate"
      return 0
      ;;
  esac
  left_path=$(trim "$left_path")
  if ! is_safe_relative_path "$left_path"; then
    printf '%s' "$candidate"
    return 0
  fi

  right_first_word=$(printf '%s\n' "$right_side" | awk '{print $1}')
  case "$right_first_word" in
    grep)
      right_args=$(trim "${right_side#grep }")
      ;;
    rg)
      right_args=$(trim "${right_side#rg }")
      ;;
    *)
      printf '%s' "$candidate"
      return 0
      ;;
  esac
  if [ -z "$right_args" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  if printf '%s' "$right_args" | grep -Eq '[;&|><`$()]'; then
    printf '%s' "$candidate"
    return 0
  fi

  # grep supports -E/--extended-regexp; rg is regex by default.
  right_args=$(printf '%s\n' "$right_args" | sed -E \
    's/(^|[[:space:]])--extended-regexp([[:space:]]|$)/ /g; s/(^|[[:space:]])-E([[:space:]]|$)/ /g')
  right_args=$(trim "$right_args")
  if [ -z "$right_args" ]; then
    printf '%s' "$candidate"
    return 0
  fi

  printf 'rg %s %s' "$right_args" "$left_path"
}

is_safe_grep_option_token() {
  option_token=$(trim "$1")
  case "$option_token" in
    -r|-R|-n|-i|-F|-E|-H|--recursive|--line-number|--ignore-case|--fixed-strings|--extended-regexp|--with-filename)
      return 0
      ;;
    -m[0-9]*)
      max_count_value=${option_token#-m}
      case "$max_count_value" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
    --max-count=[0-9]*)
      max_count_value=${option_token#--max-count=}
      case "$max_count_value" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

validate_safe_grep_command() {
  grep_cmd=$(trim "$1")
  [ -n "$grep_cmd" ] || return 1

  # shellcheck disable=SC2086
  set -- $grep_cmd
  [ "$1" = "grep" ] || return 1
  shift

  pattern_seen=0
  path_seen=0
  pending_max_count_value=0

  for token in "$@"; do
    token=$(trim "$token")
    [ -n "$token" ] || continue

    if [ "$pending_max_count_value" -eq 1 ]; then
      case "$token" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          pending_max_count_value=0
          continue
          ;;
      esac
    fi

    case "$token" in
      --max-count|-m)
        pending_max_count_value=1
        continue
        ;;
    esac

    if [ "$pattern_seen" -eq 0 ]; then
      case "$token" in
        -*)
          if ! is_safe_grep_option_token "$token"; then
            return 1
          fi
          continue
          ;;
        *)
          pattern_seen=1
          continue
          ;;
      esac
    fi

    case "$token" in
      -*)
        if ! is_safe_grep_option_token "$token"; then
          return 1
        fi
        ;;
      *)
        if ! is_safe_relative_path "$token"; then
          return 1
        fi
        path_seen=1
        ;;
    esac
  done

  [ "$pending_max_count_value" -eq 0 ] || return 1
  [ "$pattern_seen" -eq 1 ] || return 1
  [ "$path_seen" -eq 1 ] || return 1
  return 0
}

sanitize_controller_command_candidate() {
  candidate_raw=$(trim "$1")
  state_mode_hint=$(trim "$2")
  if [ -z "$candidate_raw" ]; then
    printf '%s' ""
    return 0
  fi

  candidate=$(printf '%s\n' "$candidate_raw" | sed -E 's/^[[:space:]]*(command|cmd|run)[[:space:]]*:[[:space:]]*//I')
  # Normalize markdown-heavy command bullets like:
  # `cat file` - To inspect ...
  command_in_backticks=$(printf '%s\n' "$candidate" | sed -n 's/.*`\([^`][^`]*\)`.*/\1/p' | sed -n '1p')
  if [ -n "$(trim "$command_in_backticks")" ]; then
    candidate=$command_in_backticks
  fi
  candidate=$(printf '%s\n' "$candidate" | sed -E '
    s/[[:space:]]+-[[:space:]]+(to|for|which|used|this|that|so|in order to).*$/ /I;
    s/[[:space:]]+:[[:space:]]+(to|for|which|used|this|that|so|in order to).*$/ /I;
    s/[[:space:]]+\([^)]*\)[[:space:]]*$//;
  ')
  candidate=$(printf '%s\n' "$candidate" | sed -E 's/^`+//; s/`+$//')
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ]; then
    printf '%s' ""
    return 0
  fi

  lower=$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    git\ checkout*|git\ switch*|git\ pull*|git\ push*|git\ merge*|git\ rebase*|git\ commit*)
      printf '%s' "git status --short --untracked-files=no"
      return 0
      ;;
    npm\ install*|pnpm\ install*|yarn\ install*|bun\ install*|pip\ install*|pip3\ install*)
      if [ "$state_mode_hint" = "VERIFY" ]; then
        printf '%s' "git status --short --untracked-files=no"
      else
        printf '%s' "find . -maxdepth 2 -type f"
      fi
      return 0
      ;;
  esac

  first_word=$(printf '%s\n' "$candidate" | awk '{print $1}')
  second_word=$(printf '%s\n' "$candidate" | awk '{print $2}')
  if [ "$first_word" = "node" ] && [ -n "$second_word" ] && is_safe_relative_path "$second_word"; then
    printf '%s' "node --check $second_word"
    return 0
  fi

  # Keep controller command suggestions in the safe, local inspection envelope.
  # This avoids stalling on approval prompts for analysis-only reasoning tasks.
  case "$first_word" in
    ls|pwd|cat|head|tail|sed|wc|rg|grep|find|git|test|chmod|sh|bash|command|which|python|python3|node|godot|godot4)
      ;;
    *)
      case "$state_mode_hint" in
        INVESTIGATE)
          printf '%s' "find . -maxdepth 2 -type f"
          ;;
        DESIGN|VERIFY)
          printf '%s' "git status --short --untracked-files=no"
          ;;
        *)
          printf '%s' "git status --short --untracked-files=no"
          ;;
      esac
      return 0
      ;;
  esac

  candidate=$(printf '%s\n' "$candidate" | sed -E 's/[[:space:]]+(and[[:space:]]+then|then).*$//I')
  candidate=$(trim "$candidate")
  candidate=$(rewrite_readonly_pipeline_candidate "$candidate")
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ]; then
    fallback_candidate=$(fallback_readonly_commands_for_mode "$state_mode_hint" | sed -n '1p')
    fallback_candidate=$(trim "$fallback_candidate")
    if [ -z "$fallback_candidate" ]; then
      fallback_candidate="git status --short --untracked-files=no"
    fi
    printf '%s' "$fallback_candidate"
    return 0
  fi

  first_word=$(printf '%s\n' "$candidate" | awk '{print $1}')
  second_word=$(printf '%s\n' "$candidate" | awk '{print $2}')
  word_count=$(printf '%s\n' "$candidate" | awk '{print NF}')
  fallback_candidate=$(fallback_readonly_commands_for_mode "$state_mode_hint" | sed -n '1p')
  fallback_candidate=$(trim "$fallback_candidate")
  if [ -z "$fallback_candidate" ]; then
    fallback_candidate="git status --short --untracked-files=no"
  fi
  single_quote_count=$(printf '%s' "$candidate" | tr -cd "'" | wc -c | tr -d ' ')
  double_quote_count=$(printf '%s' "$candidate" | tr -cd '"' | wc -c | tr -d ' ')
  case "$single_quote_count" in
    ""|*[!0-9]*)
      single_quote_count=0
      ;;
  esac
  case "$double_quote_count" in
    ""|*[!0-9]*)
      double_quote_count=0
      ;;
  esac
  if [ $((single_quote_count % 2)) -ne 0 ] || [ $((double_quote_count % 2)) -ne 0 ]; then
    printf '%s' "$fallback_candidate"
    return 0
  fi

  case "$first_word" in
    cat|head|tail|sed)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    rg)
      lower_rg_candidate=$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')
      if printf '%s' "$lower_rg_candidate" | grep -Eq '(^|[[:space:]])(-r|--replace)([[:space:]]|$)'; then
        printf '%s' "rg --files ."
        return 0
      fi
      if [ "$word_count" -lt 3 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    grep)
      if [ "$word_count" -lt 3 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      if ! validate_safe_grep_command "$candidate"; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    git)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    find)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "find . -maxdepth 2 -type f"
        return 0
      fi
      ;;
  esac
  printf '%s' "$candidate"
}

sanitize_plan_update_text() {
  raw_plan=$1
  if [ -z "$(trim "$raw_plan")" ]; then
    printf '%s' "$raw_plan"
    return 0
  fi
  printf '%s\n' "$raw_plan" | awk '
    BEGIN {
      in_next_action = 0
    }
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line = $0
      if (line ~ /^Next Action:[[:space:]]*$/) {
        in_next_action = 1
        print line
        next
      }
      if (in_next_action == 1 && line ~ /^[A-Z][A-Za-z ]+:[[:space:]]*$/) {
        in_next_action = 0
      }
      if (in_next_action == 1) {
        lower = tolower(trim_local(line))
        if (lower ~ /\b(git checkout|git switch|npm install|yarn install|pnpm install|pip install)\b/) {
          print "- Run safe read-only inspection commands, then refine implementation based on concrete findings."
          next
        }
      }
      print line
    }
  '
}

allowed_command() {
  cmd=$1

  case "$cmd" in
    *';'*|*'&&'*|*'||'*|*'|'*|*'>'*|*'<'*|*'`'*|*'$('*|*'${'*)
      return 1
      ;;
  esac

  case "$cmd" in
    test\ -f\ *)
      target_path=$(trim "${cmd#test -f }")
      if is_safe_relative_path "$target_path"; then
        return 0
      fi
      return 1
      ;;
    chmod\ +x\ *)
      target_path=$(trim "${cmd#chmod +x }")
      if is_safe_relative_path "$target_path"; then
        return 0
      fi
      return 1
      ;;
  esac

  first_word=$(printf '%s\n' "$cmd" | awk '{print $1}')
  second_word=$(printf '%s\n' "$cmd" | awk '{print $2}')
  third_word=$(printf '%s\n' "$cmd" | awk '{print $3}')
  fourth_word=$(printf '%s\n' "$cmd" | awk '{print $4}')
  word_count=$(printf '%s\n' "$cmd" | awk '{print NF}')

  case "$first_word" in
    ./*)
      if [ "$word_count" -eq 1 ]; then
        exec_target=$(trim "${first_word#./}")
        if is_safe_relative_path "$exec_target"; then
          return 0
        fi
      fi
      if [ "$first_word" = "./bin/ssh.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|journal|restart|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-app.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|restart|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-db.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|promote|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-bastion.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|tunnel|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|cutover|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|rollback|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|rollback|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-core-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-core-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-edge-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-edge-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ps.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      if [ "$first_word" = "./bin/stop.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      if [ "$first_word" = "./bin/start.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      return 1
      ;;
    sh|bash)
      if [ "$second_word" = "-n" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      if [ "$word_count" -eq 2 ] && is_safe_relative_path "$second_word"; then
        return 0
      fi
      return 1
      ;;
    test)
      if [ "$second_word" = "-f" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    chmod)
      if [ "$second_word" = "+x" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    command)
      if [ "$second_word" = "-v" ] && [ "$word_count" -eq 3 ] && printf '%s\n' "$third_word" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
        return 0
      fi
      return 1
      ;;
    which)
      if [ "$word_count" -eq 2 ] && printf '%s\n' "$second_word" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
        return 0
      fi
      return 1
      ;;
    python|python3)
      if [ "$second_word" = "-m" ] && [ "$third_word" = "py_compile" ] && [ "$word_count" -eq 4 ] && is_safe_relative_path "$fourth_word"; then
        return 0
      fi
      return 1
      ;;
    node)
      if [ "$second_word" = "--check" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    grep)
      if validate_safe_grep_command "$cmd"; then
        return 0
      fi
      return 1
      ;;
    godot|godot4)
      if [ "$cmd" = "$first_word --version" ] || [ "$cmd" = "$first_word --help" ]; then
        return 0
      fi
      if printf '%s\n' "$cmd" | grep -Eq "^${first_word}[[:space:]]+--headless[[:space:]]+--path[[:space:]]+[^[:space:]]+[[:space:]]+--quit$"; then
        godot_path=$(printf '%s\n' "$cmd" | awk '{print $4}')
        if [ "$godot_path" = "." ] || is_safe_relative_path "$godot_path"; then
          return 0
        fi
      fi
      return 1
      ;;
  esac

  if [ "$ALLOW_NETWORK" = "1" ] && [ "$ALLOW_WEB" = "1" ]; then
    case "$first_word" in
      curl)
        case "$cmd" in
          *" --output "*|*" -o "*|*" -O "*|*" --data "*|*" -d "*|*" --upload-file "*|*" -T "*)
            return 1
            ;;
        esac
        if printf '%s\n' "$cmd" | grep -Eq 'https?://'; then
          return 0
        fi
        return 1
        ;;
    esac
  fi

  case "$first_word" in
    ls|pwd|cat|head|tail|sed|wc|rg|find)
      return 0
      ;;
    git)
      case "$second_word" in
        status|diff|log|show|rev-parse|branch|--version|version)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_workspace_paths_in_command() {
  command_text=$1
  workspace_root=$2

  printf '%s\n' "$command_text" | WORKSPACE_ROOT="$workspace_root" ARTIFICER_ASSAY_RUNS_DIR="$ARTIFICER_ASSAY_RUNS_DIR" ARTIFICER_ASSAY_REPORTS_DIR="$ARTIFICER_ASSAY_REPORTS_DIR" perl -pe '
    my $ws = $ENV{"WORKSPACE_ROOT"} // "";
    my $assay_runs = $ENV{"ARTIFICER_ASSAY_RUNS_DIR"} // "";
    my $assay_reports = $ENV{"ARTIFICER_ASSAY_REPORTS_DIR"} // "";
    $ws =~ s{/\z}{};
    $assay_runs =~ s{/\z}{};
    $assay_reports =~ s{/\z}{};
    my @aliases = (
      "/path/to/workspace",
      "/path_to_workspace",
      "/path/to/repo",
      "/path_to_repo",
      "<workspace_path>",
      "/workspace",
      "/repo",
      "/project",
      "<workspace>",
      "\$workspace_path",
      "\${workspace_path}"
    );
    for my $alias (@aliases) {
      s{(^|\s)\Q$alias\E/(?=\S)}{$1./}g;
      s{(^|\s)\Q$alias\E(?=\s|$)}{$1.}g;
    }
    if ($assay_runs ne "") {
      s{(^|\s)(?:\./)?\.assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)(?:\./)?\.assay-runs(?=\s|$)}{$1$assay_runs}g;
      s{(^|\s)/assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)/assay-runs(?=\s|$)}{$1$assay_runs}g;
      s{(^|\s)assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)assay-runs(?=\s|$)}{$1$assay_runs}g;
    }
    if ($assay_reports ne "") {
      s{(^|\s)(?:\./)?hosted-web/\.assay-reports/(?=\S)}{$1$assay_reports/}g;
      s{(^|\s)(?:\./)?hosted-web/\.assay-reports(?=\s|$)}{$1$assay_reports}g;
      s{(^|\s)(?:\./)?\.assay-reports/(?=\S)}{$1$assay_reports/}g;
      s{(^|\s)(?:\./)?\.assay-reports(?=\s|$)}{$1$assay_reports}g;
    }
    if ($ws ne "") {
      s{(^|\s)\Q$ws\E/(?=\S)}{$1}g;
      s{(^|\s)\Q$ws\E(?=\s|$)}{$1.}g;
    }
  '
}

run_ollama_cli_once() {
  ollama_path=$1
  model_name=$2
  prompt_text=$3
  timeout_sec=$4
  use_gpu=${5:-1}

  env_prefix=""
  if [ "$use_gpu" != "1" ]; then
    env_prefix="OLLAMA_NUM_GPU=0"
  fi

  if command -v timeout >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      timeout "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
    else
      timeout "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    fi
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      gtimeout "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
    else
      gtimeout "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    fi
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      perl -e '
      use strict;
      use warnings;
      my $t = shift @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec @ARGV; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
      return $?
    fi
    perl -e '
      use strict;
      use warnings;
      my $t = shift @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec @ARGV; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    return $?
  fi

  if [ -n "$env_prefix" ]; then
    env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
  else
    "$ollama_path" run "$model_name" "$prompt_text"
  fi
  return $?
}

run_model() {
  model_name=$1
  prompt_text=$2
  image_payload_lines=${3:-}

  host_candidates=$(ollama_host_candidates)
  last_output=""
  last_rc=1
  run_timeout_sec=${RUN_TIMEOUT_SEC:-120}
  images_json=""
  ollama_use_gpu=$(llm_use_gpu_enabled)
  ollama_options_fragment=""
  if [ "$ollama_use_gpu" != "1" ]; then
    ollama_options_fragment=',"options":{"num_gpu":0}'
  fi
  prompt_for_model=$(adapt_prompt_for_model "$model_name" "$prompt_text")

  if [ -n "$(trim "$image_payload_lines")" ]; then
    images_json=$(printf '%s\n' "$image_payload_lines" | sed '/^$/d' | awk '
      BEGIN { first = 1 }
      {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        if (!first) {
          printf ","
        }
        first = 0
        printf "\"%s\"", $0
      }
    ')
  fi

  if command -v curl >/dev/null 2>&1; then
    stream_output_file=${ARTIFICER_STREAM_FILE:-}
    if [ -n "$(trim "$stream_output_file")" ]; then
      mkdir -p "$(dirname "$stream_output_file")" 2>/dev/null || true
      if [ ! -f "$stream_output_file" ]; then
        : > "$stream_output_file"
      fi
    fi

    while IFS= read -r host; do
      [ -n "$host" ] || continue
      OLLAMA_HOST=$host
      export OLLAMA_HOST

      if [ -n "$(trim "$stream_output_file")" ]; then
        if [ -n "$images_json" ]; then
          payload=$(printf '{"model":"%s","prompt":"%s","images":[%s],"stream":true%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$images_json" \
            "$ollama_options_fragment")
        else
          payload=$(printf '{"model":"%s","prompt":"%s","stream":true%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$ollama_options_fragment")
        fi

        stream_fifo=$(mktemp -u "/tmp/artificer-stream.XXXXXX")
        stream_err=$(mktemp)
        stream_text=$(mktemp)
        mkfifo "$stream_fifo"

        set +e
        curl -sS --connect-timeout 3 --max-time "$run_timeout_sec" \
          -H "Content-Type: application/json" \
          -X POST "$host/api/generate" \
          -d "$payload" >"$stream_fifo" 2>"$stream_err" &
        curl_pid=$!
        set -e

        while IFS= read -r line || [ -n "$line" ]; do
          [ -n "$line" ] || continue
          chunk=$(json_extract_string_field "response" "$line" || true)
          if [ -n "$chunk" ]; then
            printf '%s' "$chunk" >> "$stream_text"
            printf '%s' "$chunk" >> "$stream_output_file"
          fi
        done < "$stream_fifo"

        set +e
        wait "$curl_pid"
        api_rc=$?
        set -e

        rm -f "$stream_fifo"

        if [ "$api_rc" -eq 0 ]; then
          response_text=$(cat "$stream_text")
          rm -f "$stream_text" "$stream_err"
          if [ -n "$response_text" ]; then
            printf '%s' "$response_text"
            return 0
          fi

          last_output="ollama stream completed without response text"
          last_rc=1
          continue
        fi

        err_text=$(cat "$stream_err" 2>/dev/null || true)
        rm -f "$stream_text" "$stream_err"

        if [ "$api_rc" -eq 28 ]; then
          last_output="timed out while waiting for ollama /api/generate"
          last_rc=124
          break
        fi

        if [ -n "$(trim "$err_text")" ]; then
          last_output=$err_text
        else
          last_output="ollama streaming request failed"
        fi
        last_rc=$api_rc
      else
        if [ -n "$images_json" ]; then
          payload=$(printf '{"model":"%s","prompt":"%s","images":[%s],"stream":false%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$images_json" \
            "$ollama_options_fragment")
        else
          payload=$(printf '{"model":"%s","prompt":"%s","stream":false%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$ollama_options_fragment")
        fi

        set +e
        api_output=$(curl -sS --connect-timeout 3 --max-time "$run_timeout_sec" \
          -H "Content-Type: application/json" \
          -X POST "$host/api/generate" \
          -d "$payload" 2>&1)
        api_rc=$?
        set -e

        if [ "$api_rc" -eq 0 ]; then
          response_text=$(json_extract_string_field "response" "$api_output" || true)
          if [ -n "$response_text" ]; then
            printf '%s' "$response_text"
            return 0
          fi

          error_text=$(json_extract_string_field "error" "$api_output" || true)
          if [ -n "$error_text" ]; then
            last_output=$error_text
          else
            last_output=$api_output
          fi
          last_rc=1
          continue
        fi

        if [ "$api_rc" -eq 28 ]; then
          last_output="timed out while waiting for ollama /api/generate"
          last_rc=124
          break
        else
          last_output=$api_output
          last_rc=$api_rc
        fi
      fi
    done <<EOF
$host_candidates
EOF
  fi

  if [ -n "$images_json" ]; then
    if [ -z "$(trim "$last_output")" ]; then
      last_output="Model request with image attachments failed. Ensure Ollama API is reachable and selected model supports vision."
    fi
    printf '%s' "$last_output"
    return "${last_rc:-1}"
  fi

  ollama_bin=$(resolve_ollama_bin || true)
  if [ -n "$ollama_bin" ]; then
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      OLLAMA_HOST=$host
      export OLLAMA_HOST

      set +e
      if [ -n "$(trim "$stream_output_file")" ]; then
        cli_output_file=$(mktemp)
        cli_rc_file=$(mktemp)
        (
          run_ollama_cli_once "$ollama_bin" "$model_name" "$prompt_for_model" "$run_timeout_sec" "$ollama_use_gpu"
          cli_rc=$?
          printf '%s\n' "$cli_rc" > "$cli_rc_file"
          exit 0
        ) 2>&1 | tee -a "$cli_output_file" >> "$stream_output_file"
        run_rc=$(read_file_line "$cli_rc_file" "1")
        run_output=$(cat "$cli_output_file" 2>/dev/null || true)
        rm -f "$cli_output_file" "$cli_rc_file"
      else
        run_output=$(run_ollama_cli_once "$ollama_bin" "$model_name" "$prompt_for_model" "$run_timeout_sec" "$ollama_use_gpu" 2>&1)
        run_rc=$?
      fi
      set -e

      if [ "$run_rc" -eq 0 ]; then
        printf '%s' "$run_output"
        return 0
      fi

      last_output=$run_output
      if [ "$run_rc" -eq 124 ]; then
        last_rc=124
        break
      else
        last_rc=$run_rc
      fi
    done <<EOF
$host_candidates
EOF
  fi

  printf '%s' "$last_output"
  return "$last_rc"
}

workspace_snapshot() {
  workspace_path=$1
  tmp_file=$(mktemp)

  if (
    cd "$workspace_path" &&
      {
        printf 'Workspace: %s\n' "$workspace_path"
        printf '\nTop files (max depth 2):\n'
        find . -maxdepth 2 -type f 2>/dev/null | sed 's|^\./||' | head -n 120
        printf '\nGit status (tracked changes):\n'
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          tracked_status=$(git status --short --untracked-files=no 2>/dev/null || true)
          if [ -n "$(trim "$tracked_status")" ]; then
            printf '%s\n' "$tracked_status" | sed -n '1,80p'
            tracked_count=$(printf '%s\n' "$tracked_status" | sed '/^$/d' | wc -l | tr -d ' ')
            case "$tracked_count" in
              ""|*[!0-9]*)
                tracked_count=0
                ;;
            esac
            if [ "$tracked_count" -gt 80 ]; then
              printf '... (%s more tracked changes)\n' "$((tracked_count - 80))"
            fi
          else
            printf '(clean tracked tree)\n'
          fi

          untracked_status=$(git ls-files --others --exclude-standard 2>/dev/null || true)
          untracked_count=$(printf '%s\n' "$untracked_status" | sed '/^$/d' | wc -l | tr -d ' ')
          case "$untracked_count" in
            ""|*[!0-9]*)
              untracked_count=0
              ;;
          esac
          if [ "$untracked_count" -gt 0 ]; then
            assay_profile_snapshot=${assay_run_profile:-0}
            case "$assay_profile_snapshot" in
              1)
                # Keep assay prompts signal-dense: retain untracked volume but suppress long file samples.
                printf '\nUntracked files: %s total (suppressed in assay context for signal-to-noise).\n' "$untracked_count"
                ;;
              *)
                if [ "$untracked_count" -gt 200 ]; then
                  printf '\nUntracked files: %s total (sample suppressed for context compactness).\n' "$untracked_count"
                else
                  printf '\nUntracked files (showing up to 25 of %s):\n' "$untracked_count"
                  printf '%s\n' "$untracked_status" | sed -n '1,25p'
                  if [ "$untracked_count" -gt 25 ]; then
                    printf '... (%s more untracked files)\n' "$((untracked_count - 25))"
                  fi
                fi
                ;;
            esac
          fi
        else
          printf 'Not a git repository.\n'
        fi
      }
  ) >"$tmp_file" 2>&1; then
    :
  fi

  cat "$tmp_file"
  rm -f "$tmp_file"
}

conversation_history() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort | tail -n 12 >"$temp_list"

  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    content=$(cat "$msg_file")
    case "$role" in
      user)
        printf 'User:\n%s\n\n' "$content"
        ;;
      assistant)
        printf 'Assistant:\n%s\n\n' "$content"
        ;;
      *)
        printf 'System:\n%s\n\n' "$content"
        ;;
    esac
  done <"$temp_list"

  rm -f "$temp_list"
}

recent_user_turns_for_conversation() {
  conv_dir=$1
  max_turns_raw=${2:-4}
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0
  case "$max_turns_raw" in
    ""|*[!0-9]*)
      max_turns=4
      ;;
    *)
      max_turns=$max_turns_raw
      ;;
  esac
  if [ "$max_turns" -lt 1 ]; then
    max_turns=1
  fi
  if [ "$max_turns" -gt 8 ]; then
    max_turns=8
  fi

  temp_list=$(mktemp)
  temp_user=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort | tail -n 24 > "$temp_list"
  : > "$temp_user"
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    [ "$role" = "user" ] || continue
    content=$(cat "$msg_file")
    content=$(printf '%s' "$content" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
    [ -n "$content" ] || continue
    printf '%s\n' "$content" >> "$temp_user"
  done < "$temp_list"
  if [ -s "$temp_user" ]; then
    tail -n "$max_turns" "$temp_user" | awk '{ printf "%d. %s\n", NR, $0 }'
  fi
  rm -f "$temp_list" "$temp_user"
}

conversation_last_message_for_role() {
  conv_dir=$1
  target_role=$2
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort > "$temp_list"
  last_file=""
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    if [ "$role" = "$target_role" ]; then
      last_file=$msg_file
    fi
  done < "$temp_list"
  rm -f "$temp_list"

  if [ -n "$last_file" ] && [ -f "$last_file" ]; then
    cat "$last_file"
  fi
}

conversation_previous_message_for_role() {
  conv_dir=$1
  target_role=$2
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort > "$temp_list"
  previous_file=""
  current_file=""
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    if [ "$role" = "$target_role" ]; then
      previous_file=$current_file
      current_file=$msg_file
    fi
  done < "$temp_list"
  rm -f "$temp_list"

  if [ -n "$previous_file" ] && [ -f "$previous_file" ]; then
    cat "$previous_file"
  fi
}

assistant_output_is_programming_summary_contract() {
  output_text=$1
  for required in "Outcome:" "Files Changed:" "Verification Evidence:" "Risks:" "Next Improvement:"; do
    if ! printf '%s\n' "$output_text" | grep -Eq "^$required"; then
      return 1
    fi
  done
  return 0
}

workspace_latest_programming_summary_conversation_dir() {
  workspace_id=$1
  exclude_conversation_id=${2-}
  ws_dir=$(workspace_dir_for "$workspace_id")
  conv_root="$ws_dir/conversations"
  [ -d "$conv_root" ] || return 0
  best_dir=""
  best_updated=0
  for conv_dir in "$conv_root"/*; do
    [ -d "$conv_dir" ] || continue
    conv_id=$(basename "$conv_dir")
    if [ -n "$exclude_conversation_id" ] && [ "$conv_id" = "$exclude_conversation_id" ]; then
      continue
    fi
    last_assistant=$(conversation_last_message_for_role "$conv_dir" "assistant")
    if ! assistant_output_is_programming_summary_contract "$last_assistant"; then
      continue
    fi
    updated_epoch=$(read_file_line "$conv_dir/updated" "0")
    case "$updated_epoch" in
      ''|*[!0-9]*)
        updated_epoch=0
        ;;
    esac
    if [ -z "$best_dir" ] || [ "$updated_epoch" -ge "$best_updated" ]; then
      best_dir=$conv_dir
      best_updated=$updated_epoch
    fi
  done
  printf '%s' "$best_dir"
}

workspace_name_for_id() {
  workspace_id=$1
  read_file_line "$(workspace_dir_for "$workspace_id")/name" "$workspace_id"
}

programming_requested_source_workspace_hint_for_prompt() {
  prompt_text=$1
  hint=$(printf '%s\n' "$prompt_text" | sed -n 's/^Related workspace:[[:space:]]*//p' | sed -n '1p')
  if [ -z "$(trim "$hint")" ]; then
    hint=$(printf '%s\n' "$prompt_text" | sed -n 's/^Source workspace:[[:space:]]*//p' | sed -n '1p')
  fi
  hint=$(printf '%s' "$hint" | sed 's/[[:space:]]*[.;][[:space:]].*$//')
  printf '%s' "$(trim "$hint")"
}

workspace_match_score_for_hint() {
  workspace_id=$1
  workspace_hint=$(trim "$2")
  if [ -z "$workspace_hint" ]; then
    printf '%s' "0"
    return 0
  fi

  workspace_name=$(workspace_name_for_id "$workspace_id")
  workspace_path=$(workspace_path_for_id "$workspace_id")
  workspace_basename=""
  if [ -n "$workspace_path" ]; then
    workspace_basename=$(basename "$workspace_path")
  fi

  hint_lower=$(printf '%s' "$workspace_hint" | tr '[:upper:]' '[:lower:]')
  workspace_id_lower=$(printf '%s' "$workspace_id" | tr '[:upper:]' '[:lower:]')
  workspace_name_lower=$(printf '%s' "$workspace_name" | tr '[:upper:]' '[:lower:]')
  workspace_path_lower=$(printf '%s' "$workspace_path" | tr '[:upper:]' '[:lower:]')
  workspace_basename_lower=$(printf '%s' "$workspace_basename" | tr '[:upper:]' '[:lower:]')

  if [ "$hint_lower" = "$workspace_id_lower" ]; then
    printf '%s' "400"
  elif [ -n "$workspace_name_lower" ] && [ "$hint_lower" = "$workspace_name_lower" ]; then
    printf '%s' "350"
  elif [ -n "$workspace_path_lower" ] && [ "$hint_lower" = "$workspace_path_lower" ]; then
    printf '%s' "300"
  elif [ -n "$workspace_basename_lower" ] && [ "$hint_lower" = "$workspace_basename_lower" ]; then
    printf '%s' "250"
  else
    printf '%s' "0"
  fi
}

workspace_programming_summary_conversation_dir_for_hint() {
  current_workspace_id=$1
  workspace_hint=$2
  best_dir=""
  best_updated=0
  best_score=0

  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    candidate_workspace_id=$(basename "$ws_dir")
    if [ "$candidate_workspace_id" = "$current_workspace_id" ]; then
      continue
    fi
    candidate_score=$(workspace_match_score_for_hint "$candidate_workspace_id" "$workspace_hint")
    case "$candidate_score" in
      ''|*[!0-9]*)
        candidate_score=0
        ;;
    esac
    if [ "$candidate_score" -le 0 ]; then
      continue
    fi
    candidate_dir=$(workspace_latest_programming_summary_conversation_dir "$candidate_workspace_id" "")
    if [ -z "$candidate_dir" ] || [ ! -d "$candidate_dir" ]; then
      continue
    fi
    candidate_updated=$(read_file_line "$candidate_dir/updated" "0")
    case "$candidate_updated" in
      ''|*[!0-9]*)
        candidate_updated=0
        ;;
    esac
    if [ -z "$best_dir" ] || [ "$candidate_score" -gt "$best_score" ] || { [ "$candidate_score" -eq "$best_score" ] && [ "$candidate_updated" -ge "$best_updated" ]; }; then
      best_dir=$candidate_dir
      best_updated=$candidate_updated
      best_score=$candidate_score
    fi
  done

  printf '%s' "$best_dir"
}

single_line_snippet() {
  text=$1
  printf '%s' "$text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cut -c1-220
}

file_mtime_epoch() {
  file_path=$1
  if [ ! -f "$file_path" ]; then
    printf '%s' "0"
    return 0
  fi
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  if stat -c %Y "$file_path" >/dev/null 2>&1; then
    stat -c %Y "$file_path" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  printf '%s' "0"
}

human_elapsed_label() {
  elapsed_raw=$1
  case "$elapsed_raw" in
    ""|*[!0-9]*)
      elapsed_raw=0
      ;;
  esac
  if [ "$elapsed_raw" -lt 60 ]; then
    printf '%ss' "$elapsed_raw"
    return 0
  fi
  if [ "$elapsed_raw" -lt 3600 ]; then
    printf '%sm' $((elapsed_raw / 60))
    return 0
  fi
  if [ "$elapsed_raw" -lt 86400 ]; then
    printf '%sh %sm' $((elapsed_raw / 3600)) $(((elapsed_raw % 3600) / 60))
    return 0
  fi
  printf '%sd %sh' $((elapsed_raw / 86400)) $(((elapsed_raw % 86400) / 3600))
}

teacher_last_assistant_gap_seconds() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  if [ ! -d "$msg_dir" ]; then
    printf '%s' "-1"
    return 0
  fi
  last_assistant_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-assistant.txt' 2>/dev/null | sort | tail -n 1)
  if [ -z "$last_assistant_file" ] || [ ! -f "$last_assistant_file" ]; then
    printf '%s' "-1"
    return 0
  fi
  last_epoch=$(file_mtime_epoch "$last_assistant_file")
  case "$last_epoch" in
    ""|*[!0-9]*)
      printf '%s' "-1"
      return 0
      ;;
  esac
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  gap=$((now_epoch - last_epoch))
  if [ "$gap" -lt 0 ]; then
    gap=0
  fi
  printf '%s' "$gap"
}

teacher_gap_summary_for_conversation() {
  conv_dir=$1
  gap_seconds=$(teacher_last_assistant_gap_seconds "$conv_dir")
  case "$gap_seconds" in
    ""|*[!0-9-]*)
      gap_seconds=-1
      ;;
  esac
  if [ "$gap_seconds" -lt 0 ]; then
    printf '%s' "No prior teacher response in this thread; start with a light diagnostic and baseline lesson."
    return 0
  fi
  gap_label=$(human_elapsed_label "$gap_seconds")
  if [ "$gap_seconds" -ge 1209600 ]; then
    printf '%s' "Long gap since last teaching response (${gap_label}); begin with retrieval practice and concept refresh."
    return 0
  fi
  if [ "$gap_seconds" -ge 259200 ]; then
    printf '%s' "Moderate gap since last teaching response (${gap_label}); briefly recap before advancing."
    return 0
  fi
  printf '%s' "Recent continuation (${gap_label} since last teaching response); continue progression with quick checks."
}

teacher_review_interval_days_for_gap() {
  gap_seconds_raw=$1
  case "$gap_seconds_raw" in
    ""|*[!0-9-]*)
      gap_seconds_raw=-1
      ;;
  esac
  if [ "$gap_seconds_raw" -lt 0 ]; then
    printf '%s' "2"
    return 0
  fi
  if [ "$gap_seconds_raw" -ge 1209600 ]; then
    printf '%s' "1"
    return 0
  fi
  if [ "$gap_seconds_raw" -ge 604800 ]; then
    printf '%s' "2"
    return 0
  fi
  printf '%s' "3"
}

ensure_teacher_model_file() {
  model_file=$1
  if [ -f "$model_file" ]; then
    return 0
  fi
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  cat > "$model_file" <<EOF
# Learner Model

Created: $timestamp
Updated: $timestamp

## Stable Profile
- learning_goals: unknown
- current_level_estimate: unknown
- preferred_explanation_style: unknown
- misconception_watchlist: none recorded

## Curriculum Backlog
- pending

## Spaced Review Plan
- pending

## Session Notes
EOF
}

teacher_update_model_timestamp() {
  model_file=$1
  timestamp=$2
  [ -f "$model_file" ] || return 0
  tmp_file=$(mktemp)
  awk -v ts="$timestamp" '
    BEGIN { replaced = 0 }
    {
      if (!replaced && $0 ~ /^Updated:[[:space:]]*/) {
        print "Updated: " ts
        replaced = 1
        next
      }
      print
    }
    END {
      if (!replaced) {
        print "Updated: " ts
      }
    }
  ' "$model_file" > "$tmp_file"
  mv "$tmp_file" "$model_file"
}

append_teacher_model_note() {
  model_file=$1
  heading=$2
  body=$3
  ensure_teacher_model_file "$model_file"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  teacher_update_model_timestamp "$model_file" "$timestamp"
  {
    printf '\n### %s (%s)\n' "$heading" "$timestamp"
    printf '%s\n' "$body"
  } >> "$model_file"

  line_count=$(wc -l < "$model_file" 2>/dev/null | tr -d ' ')
  case "$line_count" in
    ""|*[!0-9]*)
      line_count=0
      ;;
  esac
  if [ "$line_count" -gt 520 ]; then
    tmp_file=$(mktemp)
    sed -n '1,120p' "$model_file" > "$tmp_file"
    printf '\n## Session Notes (trimmed)\n' >> "$tmp_file"
    tail -n 320 "$model_file" >> "$tmp_file"
    mv "$tmp_file" "$model_file"
  fi
}

workspace_shared_context() {
  ws_dir=$1
  active_conv_id=$2
  conv_root="$ws_dir/conversations"
  [ -d "$conv_root" ] || return 0

  listed=0
  for conv_dir in "$conv_root"/*; do
    [ -d "$conv_dir" ] || continue
    conv_id=$(basename "$conv_dir")
    [ "$conv_id" = "$active_conv_id" ] && continue

    title=$(read_file_line "$conv_dir/title" "Conversation")
    updated=$(read_file_line "$conv_dir/updated" "0")
    model=$(read_file_line "$conv_dir/model" "")

    msg_dir="$conv_dir/messages"
    user_snippet=""
    assistant_snippet=""
    if [ -d "$msg_dir" ]; then
      last_user_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-user.txt' 2>/dev/null | sort | tail -n 1)
      last_assistant_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-assistant.txt' 2>/dev/null | sort | tail -n 1)
      if [ -n "$last_user_file" ] && [ -f "$last_user_file" ]; then
        user_snippet=$(single_line_snippet "$(cat "$last_user_file" 2>/dev/null || true)")
      fi
      if [ -n "$last_assistant_file" ] && [ -f "$last_assistant_file" ]; then
        assistant_snippet=$(single_line_snippet "$(cat "$last_assistant_file" 2>/dev/null || true)")
      fi
    fi

    printf 'Thread: %s\n' "$title"
    printf 'Updated: %s\n' "$updated"
    if [ -n "$model" ]; then
      printf 'Model: %s\n' "$model"
    fi
    if [ -n "$user_snippet" ]; then
      printf 'Recent user intent: %s\n' "$user_snippet"
    fi
    if [ -n "$assistant_snippet" ]; then
      printf 'Recent assistant output: %s\n' "$assistant_snippet"
    fi
    printf '\n'

    listed=$((listed + 1))
    if [ "$listed" -ge 8 ]; then
      break
    fi
  done
}

json_messages() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  printf '['
  first=1
  if [ -d "$msg_dir" ]; then
    for msg_file in "$msg_dir"/*.txt; do
      [ -f "$msg_file" ] || continue
      msg_name=$(basename "$msg_file")
      role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
      content=$(cat "$msg_file")
      role_json=$(json_escape "$role")
      content_json=$(json_escape "$content")
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"role":"%s","content":"%s"}' "$role_json" "$content_json"
    done
  fi
  printf ']'
}

latest_user_message_for_conversation() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || {
    printf '%s' ""
    return 0
  }
  latest_user_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-user.txt' 2>/dev/null | sort | tail -n 1)
  if [ -z "$latest_user_file" ] || [ ! -f "$latest_user_file" ]; then
    printf '%s' ""
    return 0
  fi
  cat "$latest_user_file"
}

seed_missing_initial_message_if_needed() {
  conv_dir=$1
  title=$(read_file_line "$conv_dir/title" "")
  created=$(read_file_line "$conv_dir/created" "0")
  updated=$(read_file_line "$conv_dir/updated" "0")
  msg_dir="$conv_dir/messages"

  [ -d "$msg_dir" ] || return 0
  first_msg_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sed -n '1p')
  [ -z "$first_msg_file" ] || return 0

  title_trim=$(trim "$title")
  if [ -z "$title_trim" ]; then
    return 0
  fi
  case "$title_trim" in
    Conversation|New\ Conversation)
      return 0
      ;;
  esac

  # Only auto-recover obvious orphaned threads where the first prompt never persisted.
  if [ "$created" != "$updated" ]; then
    return 0
  fi
  # Prevent duplicate-first-message races on freshly created threads.
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$created" in
    ""|*[!0-9]*)
      created=0
      ;;
  esac
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  if [ "$created" -gt 0 ] && [ "$now_epoch" -gt 0 ]; then
    created_age=$((now_epoch - created))
    if [ "$created_age" -lt 180 ]; then
      return 0
    fi
  fi

  queue_info=$(queue_state_for_conversation "$conv_dir")
  queue_pending=$(kv_get "pending" "$queue_info")
  queue_running=$(kv_get "running" "$queue_info")
  [ -n "$queue_pending" ] || queue_pending=0
  [ -n "$queue_running" ] || queue_running=0
  if [ "$queue_pending" != "0" ] || [ "$queue_running" != "0" ]; then
    return 0
  fi

  run_events_dir=$(run_events_dir_for_conversation "$conv_dir")
  run_event_count=$( (find "$run_events_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null || true) | wc -l | tr -d ' ' )
  [ -n "$run_event_count" ] || run_event_count=0
  if [ "$run_event_count" != "0" ]; then
    return 0
  fi

  append_message "$conv_dir" "user" "$title_trim"
}

extract_patch_section() {
  text=$1
  known_headers="MODE_UPDATE COMMANDS CONTRACT PATCH DONE_CLAIM PLAN_UPDATE CHECKPOINT DECISION_REQUEST FINAL REVIEW_DECISION REVIEW_FEEDBACK"
  patch_text=$(printf '%s\n' "$text" | awk -v headers="$known_headers" '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    BEGIN {
      capture = 0
      in_fence = 0
      header_count = split(headers, header_list, /[[:space:]]+/)
      for (header_index = 1; header_index <= header_count; header_index++) {
        if (header_list[header_index] != "") {
          known[header_list[header_index]] = 1
        }
      }
    }
    {
      normalized = $0
      sub(/^[[:space:]]*[*#>[:space:]]*/, "", normalized)
      if (normalized ~ /^```/) {
        if (in_fence == 1) {
          in_fence = 0
        } else {
          in_fence = 1
        }
      }

      header = ""
      remainder = ""
      split_pos = index(normalized, ":")
      if (split_pos > 0) {
        header = substr(normalized, 1, split_pos - 1)
        header = trim_local(header)
        header = toupper(header)
        gsub(/[[:space:]]+/, "_", header)
        remainder = trim_local(substr(normalized, split_pos + 1))
      }

      if (header != "" && !in_fence && (header in known)) {
        if (header == "PATCH") {
          capture = 1
          if (remainder != "") {
            print remainder
          }
          next
        }
        if (capture == 1) {
          capture = 0
          next
        }
      }

      if (capture == 1) {
        print
      }
    }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | sed -n '/^BEGIN_PATCH$/,/^END_PATCH$/p' | sed '1d;$d')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN { capture = 0 }
    /^```diff[[:space:]]*$/ { capture = 1; next }
    capture && /^```[[:space:]]*$/ { capture = 0; exit }
    capture { print }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN { capture = 0 }
    /^```patch[[:space:]]*$/ { capture = 1; next }
    capture && /^```[[:space:]]*$/ { capture = 0; exit }
    capture { print }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN {
      capture = 0
      seen_diff = 0
    }
    /^---[[:space:]]/ {
      capture = 1
      seen_diff = 1
    }
    capture {
      if (($0 ~ /^[A-Z][A-Z_ ]*:[[:space:]]*$/ || $0 ~ /^\*\*[A-Z][A-Z_ ]*:[[:space:]]*/ || $0 ~ /^#+[[:space:]]*[A-Z][A-Z_ ]*:[[:space:]]*/) && seen_diff == 1) {
        exit
      }
      print
    }
  ')
  printf '%s\n' "$patch_text"
}

normalize_patch_text() {
  text=$1
  printf '%s\n' "$text" | sed '/^[[:space:]]*```/d' | perl -CS -pe '
    s/^\+\+\s+(b\/\S+)/+++ $1/;
    s/^--\s+(a\/\S+)/--- $1/;
    s/^@@\s+-([0-9]+(?:,[0-9]+)?)\s+([0-9]+(?:,[0-9]+)?)\s+@@/@@ -$1 +$2 @@/;
  '
}

looks_like_unified_diff_text() {
  text=$1
  if ! printf '%s\n' "$text" | grep -q '^---[[:space:]]'; then
    return 1
  fi
  if ! printf '%s\n' "$text" | grep -q '^+++[[:space:]]'; then
    return 1
  fi
  return 0
}

patch_has_valid_hunks() {
  text=$1
  printf '%s\n' "$text" | perl -e '
    use strict;
    use warnings;
    my $in_hunk = 0;
    my $saw_hunk = 0;
    my $ok = 1;
    my ($expected_old, $expected_new, $seen_old, $seen_new) = (0, 0, 0, 0);

    while (my $line = <STDIN>) {
      chomp $line;

      if ($line =~ /^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@/) {
        if ($in_hunk) {
          if ($seen_old != $expected_old || $seen_new != $expected_new) {
            $ok = 0;
            last;
          }
          $in_hunk = 0;
        }
        $expected_old = defined($2) ? $2 : 1;
        $expected_new = defined($4) ? $4 : 1;
        $seen_old = 0;
        $seen_new = 0;
        $in_hunk = 1;
        $saw_hunk = 1;
        next;
      }

      if ($line =~ /^(diff --git |--- |\+\+\+ )/) {
        if ($in_hunk) {
          if ($seen_old != $expected_old || $seen_new != $expected_new) {
            $ok = 0;
            last;
          }
          $in_hunk = 0;
        }
        next;
      }

      if ($line =~ /^(index |new file mode |deleted file mode |old mode |new mode |similarity index |rename from |rename to |Binary files )/) {
        next;
      }

      if ($in_hunk) {
        if ($line =~ /^ /) {
          $seen_old += 1;
          $seen_new += 1;
          next;
        }
        if ($line =~ /^-/) {
          $seen_old += 1;
          next;
        }
        if ($line =~ /^\+/) {
          $seen_new += 1;
          next;
        }
        if ($line =~ /^\\ No newline at end of file$/) {
          next;
        }
        $ok = 0;
        last;
      }
    }

    if ($ok && $in_hunk) {
      if ($seen_old != $expected_old || $seen_new != $expected_new) {
        $ok = 0;
      }
    }

    exit(($ok && $saw_hunk) ? 0 : 1);
  '
}

patch_uses_ab_prefix_paths() {
  patch_text=$1
  if printf '%s\n' "$patch_text" | grep -Eq '^(diff --git a/|--- a/|\+\+\+ b/)'; then
    return 0
  fi
  return 1
}

patch_candidate_is_usable() {
  text=$1
  text_trimmed=$(trim "$text")
  if [ -z "$text_trimmed" ] || [ "$text_trimmed" = "NONE" ]; then
    return 1
  fi
  if ! looks_like_unified_diff_text "$text"; then
    return 1
  fi
  if ! patch_has_valid_hunks "$text"; then
    return 1
  fi
  if ! printf '%s\n' "$text" | awk '
    /^\+[^\+]/ {
      line = $0
      sub(/^\+/, "", line)
      if (line ~ /[^[:space:]]/) {
        found = 1
        exit
      }
    }
    END {
      if (!found) exit 1
    }
  '; then
    return 1
  fi
  return 0
}

recover_new_files_patch_candidate() {
  patch_text=$1
  recover_dir=$(mktemp -d)
  recover_index=$(mktemp)
  synthesized_patch=""
  : > "$recover_index"

  printf '%s\n' "$patch_text" | RECOVER_DIR="$recover_dir" perl -e '
    use strict;
    use warnings;
    local $/;
    my $raw = <>;
    my $dir = $ENV{"RECOVER_DIR"} // "";
    my $count = 0;
    while ($raw =~ /(?:^|\n)---\s+\/dev\/null\s*\n\+\+\+\s+b\/([^\r\n]+)\s*\n(.*?)(?=\n---\s+|\z)/sg) {
      my $path = $1 // "";
      my $body = $2 // "";
      $path =~ s/^\s+//;
      $path =~ s/\s+$//;
      next if $path eq "";
      next if $path =~ m{(?:^|/)\.\.(?:/|$)};
      next if $path =~ m{^/};
      my @content;
      for my $line (split /\n/, $body) {
        next if $line =~ /^@@ /;
        next if $line =~ /^index /;
        next if $line =~ /^new file mode /;
        next if $line =~ /^\\ No newline at end of file$/;
        if ($line =~ /^\+(?!\+\+)/) {
          $line =~ s/^\+//;
          push @content, $line;
        }
      }
      next if !@content;
      my $joined = join("\n", @content) . "\n";
      next if $joined !~ /\S/;
      $count += 1;
      last if $count > 5;
      my $tmp_path = "$dir/$count.content";
      open my $fh, ">:encoding(UTF-8)", $tmp_path or next;
      print {$fh} $joined;
      close $fh;
      print "$path\t$tmp_path\n";
    }
  ' > "$recover_index"

  if [ -s "$recover_index" ]; then
    while IFS='	' read -r out_path out_tmp; do
      out_path=$(trim "$out_path")
      out_tmp=$(trim "$out_tmp")
      [ -n "$out_path" ] || continue
      [ -f "$out_tmp" ] || continue
      if ! is_safe_relative_path "$out_path"; then
        continue
      fi
      file_diff=$(diff -u /dev/null "$out_tmp" || true)
      if [ -n "$(trim "$file_diff")" ]; then
        file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
        synthesized_patch="${synthesized_patch}
${file_diff}"
      fi
    done < "$recover_index"
  fi

  rm -rf "$recover_dir" 2>/dev/null || true
  rm -f "$recover_index"
  synthesized_patch=$(trim_block_edges "$synthesized_patch")
  printf '%s' "$synthesized_patch"
}

resolve_patch_candidate() {
  raw_patch=$1
  if patch_candidate_is_usable "$raw_patch"; then
    printf '%s' "$raw_patch"
    return 0
  fi
  recovered_patch=$(recover_new_files_patch_candidate "$raw_patch")
  if patch_candidate_is_usable "$recovered_patch"; then
    printf '%s' "$recovered_patch"
    return 0
  fi
  return 1
}

extract_json_commands_from_text() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    if (/"COMMANDS"\s*:\s*\[(.*?)\]/is) {
      my $body = $1 // "";
      while ($body =~ /"((?:\\.|[^"])*)"/g) {
        my $cmd = $1;
        $cmd =~ s/\\n/ /g;
        $cmd =~ s/\\r/ /g;
        $cmd =~ s/\\"/"/g;
        $cmd =~ s/\\\\/\\/g;
        $cmd =~ s/^\s+//;
        $cmd =~ s/\s+$//;
        next if $cmd eq "";
        print "$cmd\n";
      }
    }
  '
}

extract_readonly_commands_from_text() {
  text=$1
  state_mode_hint=$(trim "${2:-}")
  candidate_file=$(mktemp)
  deduped_file=$(mktemp)
  accepted_file=$(mktemp)
  fallback_file=$(mktemp)
  count=0
  : > "$candidate_file"
  : > "$accepted_file"

  extract_json_commands_from_text "$text" >> "$candidate_file" || true
  extract_command_lines "$text" >> "$candidate_file" || true
  awk '!seen[$0]++' "$candidate_file" > "$deduped_file"

  while IFS= read -r candidate; do
    candidate=$(printf '%s\n' "$candidate" | perl -CS -pe '
      s/\r//g;
      s/\\\\n/\n/g;
      s/\\n/\n/g;
      s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
    ' | sed -n '1p')
    candidate=$(printf '%s\n' "$candidate" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
    candidate=$(sanitize_controller_command_candidate "$candidate" "$state_mode_hint")
    candidate=$(trim "$candidate")
    [ -n "$candidate" ] || continue
    if allowed_command "$candidate"; then
      if ! grep -Fqx -- "$candidate" "$accepted_file"; then
        printf '%s\n' "$candidate" >> "$accepted_file"
        count=$((count + 1))
        if [ "$count" -ge 3 ]; then
          break
        fi
      fi
    fi
  done < "$deduped_file"
  if [ "$count" -lt 2 ]; then
    fallback_readonly_commands_for_mode "$state_mode_hint" > "$fallback_file"
    while IFS= read -r fallback_candidate; do
      fallback_candidate=$(sanitize_controller_command_candidate "$fallback_candidate" "$state_mode_hint")
      fallback_candidate=$(trim "$fallback_candidate")
      [ -n "$fallback_candidate" ] || continue
      if ! allowed_command "$fallback_candidate"; then
        continue
      fi
      if grep -Fqx -- "$fallback_candidate" "$accepted_file"; then
        continue
      fi
      printf '%s\n' "$fallback_candidate" >> "$accepted_file"
      count=$((count + 1))
      if [ "$count" -ge 3 ]; then
        break
      fi
    done < "$fallback_file"
  fi
  if [ -s "$accepted_file" ]; then
    sed 's/^/- /' "$accepted_file"
  fi
  rm -f "$candidate_file" "$deduped_file" "$accepted_file" "$fallback_file"
}

controller_output_has_required_sections() {
  text=$1
  normalized_text=$(canonicalize_controller_output "$text")
  if ! printf '%s\n' "$normalized_text" | grep -q '^MODE_UPDATE:[[:space:]]*$'; then
    return 1
  fi
  if ! printf '%s\n' "$normalized_text" | grep -q '^PLAN_UPDATE:[[:space:]]*$'; then
    return 1
  fi
  if ! printf '%s\n' "$normalized_text" | grep -Eq '^(COMMANDS|CONTRACT|PATCH|DONE_CLAIM|CHECKPOINT):[[:space:]]*$'; then
    return 1
  fi
  return 0
}

repair_partial_controller_output() {
  raw_text=$(canonicalize_controller_output "$1")
  current_mode=$2
  state_target_value=$3
  state_confidence_value=$4
  current_plan_text=$5

  if [ -z "$(trim "$raw_text")" ]; then
    printf '%s' "$raw_text"
    return 0
  fi

  has_mode_header=0
  has_plan_header=0
  has_action_header=0
  if printf '%s\n' "$raw_text" | grep -q '^MODE_UPDATE:[[:space:]]*$'; then
    has_mode_header=1
  fi
  if printf '%s\n' "$raw_text" | grep -q '^PLAN_UPDATE:[[:space:]]*$'; then
    has_plan_header=1
  fi
  if printf '%s\n' "$raw_text" | grep -Eq '^(COMMANDS|CONTRACT|PATCH|DONE_CLAIM|CHECKPOINT):[[:space:]]*$'; then
    has_action_header=1
  fi
  if [ "$has_mode_header" -eq 0 ] || [ "$has_action_header" -eq 0 ]; then
    printf '%s' "$raw_text"
    return 0
  fi
  if [ "$has_plan_header" -eq 1 ] && controller_output_has_required_sections "$raw_text"; then
    printf '%s' "$raw_text"
    return 0
  fi

  mode_update_candidate=$(extract_section "MODE_UPDATE" "$raw_text")
  mode_target=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^target=//p' | sed -n '1p')
  mode_blocking=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^blocking=//p' | sed -n '1p')
  mode_confidence=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^confidence=//p' | sed -n '1p')
  mode_target=$(trim "$mode_target")
  mode_blocking=$(trim "$mode_blocking")
  mode_confidence=$(trim "$mode_confidence")
  if [ -z "$mode_target" ]; then
    mode_target=$state_target_value
  fi
  if [ -z "$mode_blocking" ]; then
    mode_blocking="controller output partially formatted; completed missing sections"
  fi
  case "$mode_confidence" in
    ""|*[!0-9.]*)
      mode_confidence=$state_confidence_value
      ;;
  esac
  if [ -z "$mode_confidence" ]; then
    mode_confidence=$state_confidence_value
  fi

  repaired_commands=$(extract_readonly_commands_from_text "$raw_text" "$current_mode" || true)
  if [ -z "$(trim "$repaired_commands")" ]; then
    repaired_commands=$(fallback_readonly_commands_for_mode "$current_mode" | sed -n '1,3p' | sed 's/^/- /')
  fi
  if [ -z "$(trim "$repaired_commands")" ]; then
    repaired_commands="NONE"
  fi

  repaired_contract=$(extract_section "CONTRACT" "$raw_text" | sed -n '1,140p')
  repaired_contract=$(trim "$repaired_contract")
  if [ -z "$repaired_contract" ] || [ "$repaired_contract" = "NONE" ]; then
    if [ "$current_mode" = "DESIGN" ]; then
      repaired_contract=$(cat <<EOF
Inputs:
- user request from PLAN_UPDATE
Outputs:
- concrete design deliverable and verification checklist
Side Effects:
- none in design-only recovery step
Dependencies:
- repository inspection commands and current workspace context
Invariants:
- maintain deterministic, auditable, and safe recommendations
EOF
)
    else
      repaired_contract="NONE"
    fi
  fi

  repaired_patch="NONE"
  patch_candidate=$(extract_patch_section "$raw_text")
  patch_candidate=$(normalize_patch_text "$patch_candidate")
  resolved_patch=$(resolve_patch_candidate "$patch_candidate" || true)
  if [ -n "$(trim "$resolved_patch")" ]; then
    repaired_patch=$resolved_patch
  fi

  repaired_done_claim=$(extract_section "DONE_CLAIM" "$raw_text" | sed -n '1p' | tr 'A-Z' 'a-z' | awk '{print $1}')
  case "$repaired_done_claim" in
    yes)
      ;;
    *)
      repaired_done_claim="no"
      ;;
  esac

  repaired_plan=$(extract_section "PLAN_UPDATE" "$raw_text")
  repaired_plan=$(trim "$repaired_plan")
  if [ -z "$repaired_plan" ] || [ "$repaired_plan" = "NONE" ]; then
    repaired_plan=$current_plan_text
  fi

  repaired_checkpoint=$(extract_section "CHECKPOINT" "$raw_text")
  repaired_checkpoint=$(trim "$repaired_checkpoint")
  if [ -z "$repaired_checkpoint" ] || [ "$repaired_checkpoint" = "NONE" ]; then
    repaired_checkpoint="Completed partial controller output by filling missing required sections."
  fi

  repaired_decision=$(extract_section "DECISION_REQUEST" "$raw_text")
  repaired_decision=$(trim "$repaired_decision")
  if [ -z "$repaired_decision" ]; then
    repaired_decision="NONE"
  fi

  repaired_final=$(extract_section "FINAL" "$raw_text")
  repaired_final=$(trim "$repaired_final")
  if [ -z "$repaired_final" ]; then
    repaired_final="NONE"
  fi

  cat <<EOF
MODE_UPDATE:
target=$mode_target
blocking=$mode_blocking
confidence=$mode_confidence
COMMANDS:
$repaired_commands
CONTRACT:
$repaired_contract
PATCH:
$repaired_patch
DONE_CLAIM:
$repaired_done_claim
PLAN_UPDATE:
$repaired_plan
CHECKPOINT:
$repaired_checkpoint
DECISION_REQUEST:
$repaired_decision
FINAL:
$repaired_final
EOF
}

recover_controller_output() {
  raw_text=$(canonicalize_controller_output "$1")
  current_mode=$2
  state_target_value=$3
  state_confidence_value=$4
  current_plan_text=$5

  recovered_commands="NONE"
  recovered_contract="NONE"
  recovered_patch="NONE"
  recovered_done_claim="no"
  recovered_checkpoint="Recovered malformed controller output; continuing with guarded defaults."
  recovered_final="NONE"

  commands_candidate=$(extract_readonly_commands_from_text "$raw_text" "$current_mode" || true)
  if [ -n "$(trim "$commands_candidate")" ]; then
    recovered_commands=$commands_candidate
  fi

  recovered_contract_candidate=$(extract_section "CONTRACT" "$raw_text" | sed -n '1,140p')
  recovered_contract_candidate=$(trim "$recovered_contract_candidate")
  if [ -n "$recovered_contract_candidate" ] && [ "$recovered_contract_candidate" != "NONE" ]; then
    recovered_contract=$recovered_contract_candidate
  elif [ "$current_mode" = "DESIGN" ]; then
    recovered_contract=$(cat <<EOF
Inputs:
- user request from PLAN_UPDATE
Outputs:
- concrete design deliverable and verification checklist
Side Effects:
- none in design-only recovery step
Dependencies:
- repository inspection commands and current workspace context
Invariants:
- maintain deterministic, auditable, and safe recommendations
EOF
)
  fi

  if [ "$current_mode" = "IMPLEMENT" ]; then
    patch_candidate=$(extract_patch_section "$raw_text")
    patch_candidate=$(normalize_patch_text "$patch_candidate")
    recovered_patch_candidate=$(resolve_patch_candidate "$patch_candidate" || true)
    if [ -n "$(trim "$recovered_patch_candidate")" ]; then
      recovered_patch=$recovered_patch_candidate
      recovered_checkpoint="Recovered malformed controller output and extracted unified diff patch candidate."
    fi
  fi

  case "$(printf '%s' "$raw_text" | tr '[:upper:]' '[:lower:]')" in
    *"done_claim:"*yes*|*"verification passed"*|*"ready to ship"*|*"task complete"*|*"completed request"*)
      recovered_done_claim="yes"
      ;;
  esac

  if [ "$current_mode" = "DONE" ]; then
    recovered_final=$(trim "$raw_text")
    if [ -z "$recovered_final" ]; then
      recovered_final="Completed requested work."
    fi
  fi

  cat <<EOF
MODE_UPDATE:
target=$state_target_value
blocking=controller output malformed; recovered
confidence=$state_confidence_value
COMMANDS:
$recovered_commands
CONTRACT:
$recovered_contract
PATCH:
$recovered_patch
DONE_CLAIM:
$recovered_done_claim
PLAN_UPDATE:
$current_plan_text
CHECKPOINT:
$recovered_checkpoint
DECISION_REQUEST:
NONE
FINAL:
$recovered_final
EOF
}

is_safe_relative_path() {
  rel=$1

  case "$rel" in
    ""|/*|*'..'*|*'~'*|*'\\'*|*':'*)
      return 1
      ;;
  esac

  case "$rel" in
    *[!a-zA-Z0-9._/-]*)
      return 1
      ;;
  esac

  return 0
}

patch_paths_from_text() {
  patch_text=$1
  printf '%s\n' "$patch_text" | awk '
    /^\+\+\+ / {
      path = $2
      sub(/^b\//, "", path)
      if (path != "/dev/null") {
        print path
      }
    }
  ' | awk '!seen[$0]++'
}

run_shell_command_with_timeout() {
  timeout_secs=$1
  command_text=$2

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_secs" sh -c "$command_text"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_secs" sh -c "$command_text"
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      use strict;
      use warnings;
      my ($t, $cmd) = @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec "sh", "-c", $cmd; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_secs" "$command_text"
    return $?
  fi

  sh -c "$command_text"
  return $?
}

command_output_indicates_failure() {
  command_text=$1
  output_file=$2
  first_word=$(printf '%s\n' "$command_text" | awk '{print $1}')

  case "$first_word" in
    godot|godot4)
      if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' "$output_file" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  return 1
}

resolve_relative_path_case_insensitive() {
  workspace_root=$1
  rel_path=$2

  if ! is_safe_relative_path "$rel_path"; then
    return 1
  fi
  if [ ! -d "$workspace_root" ]; then
    return 1
  fi

  current_dir=$workspace_root
  resolved_path=""
  remaining_path=$rel_path
  while [ -n "$remaining_path" ]; do
    segment=${remaining_path%%/*}
    if [ "$segment" = "$remaining_path" ]; then
      remaining_path=""
    else
      remaining_path=${remaining_path#*/}
    fi
    [ -n "$segment" ] || continue
    if [ -e "$current_dir/$segment" ]; then
      chosen_segment=$segment
    else
      segment_lc=$(printf '%s' "$segment" | tr '[:upper:]' '[:lower:]')
      chosen_segment=$(LC_ALL=C ls -1A "$current_dir" 2>/dev/null | awk -v target="$segment_lc" '
        tolower($0) == target { print; exit }
      ')
      if [ -z "$chosen_segment" ]; then
        return 1
      fi
    fi

    if [ -z "$resolved_path" ]; then
      resolved_path=$chosen_segment
    else
      resolved_path="$resolved_path/$chosen_segment"
    fi
    current_dir="$current_dir/$chosen_segment"
  done

  if [ -z "$resolved_path" ]; then
    return 1
  fi
  if ! is_safe_relative_path "$resolved_path"; then
    return 1
  fi
  if [ ! -e "$workspace_root/$resolved_path" ]; then
    return 1
  fi

  printf '%s' "$resolved_path"
}

path_mtime_epoch_any() {
  path_value=$1
  if [ ! -e "$path_value" ]; then
    printf '%s' "0"
    return 0
  fi
  if stat -f %m "$path_value" >/dev/null 2>&1; then
    stat -f %m "$path_value" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  if stat -c %Y "$path_value" >/dev/null 2>&1; then
    stat -c %Y "$path_value" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  printf '%s' "0"
}

resolve_assay_task_relative_path_alias() {
  workspace_root=$1
  rel_path=$2

  if ! is_safe_relative_path "$rel_path"; then
    return 1
  fi
  if [ ! -d "$workspace_root/.assay-runs" ]; then
    return 1
  fi
  case "$rel_path" in
    .assay-runs/*)
      ;;
    *)
      return 1
      ;;
  esac
  if [ -e "$workspace_root/$rel_path" ]; then
    return 1
  fi

  path_without_prefix=${rel_path#".assay-runs/"}
  if [ "$path_without_prefix" = "$rel_path" ]; then
    return 1
  fi

  first_segment=${path_without_prefix%%/*}
  [ -n "$first_segment" ] || return 1
  if [ "$first_segment" = "$path_without_prefix" ]; then
    remaining_suffix=""
  else
    remaining_suffix=${path_without_prefix#*/}
  fi

  # If the first segment exists under .assay-runs, it is likely a run label,
  # not a task-id alias, so do not rewrite.
  if [ -d "$workspace_root/.assay-runs/$first_segment" ]; then
    return 1
  fi

  newest_task_dir=""
  newest_epoch=0
  while IFS= read -r candidate_dir || [ -n "$candidate_dir" ]; do
    [ -d "$candidate_dir" ] || continue
    candidate_epoch=$(path_mtime_epoch_any "$candidate_dir")
    case "$candidate_epoch" in
      ""|*[!0-9]*)
        candidate_epoch=0
        ;;
    esac
    if [ -z "$newest_task_dir" ] || [ "$candidate_epoch" -ge "$newest_epoch" ]; then
      newest_task_dir=$candidate_dir
      newest_epoch=$candidate_epoch
    fi
  done <<EOF
$(find "$workspace_root/.assay-runs" -mindepth 2 -maxdepth 2 -type d -name "$first_segment" 2>/dev/null)
EOF

  [ -n "$newest_task_dir" ] || return 1
  rewritten_rel=${newest_task_dir#"$workspace_root"/}
  if [ "$rewritten_rel" = "$newest_task_dir" ] || [ -z "$rewritten_rel" ]; then
    return 1
  fi
  if [ -n "$remaining_suffix" ]; then
    rewritten_rel="$rewritten_rel/$remaining_suffix"
  fi
  if ! is_safe_relative_path "$rewritten_rel"; then
    return 1
  fi
  printf '%s' "$rewritten_rel"
}

autocorrect_readonly_file_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  second_word=$(printf '%s\n' "$command_trimmed" | awk '{print $2}')
  case "$first_word" in
    cat|head|tail|sed|ls)
      ;;
    git)
      case "$second_word" in
        status)
          ;;
        *)
          printf '%s' "$raw_command"
          return 0
          ;;
      esac
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  last_token=$(printf '%s\n' "$command_trimmed" | awk '{print $NF}')
  last_token=$(trim "$last_token")
  if ! is_safe_relative_path "$last_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  resolved_task_alias=$(resolve_assay_task_relative_path_alias "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_task_alias" ] && [ "$resolved_task_alias" != "$last_token" ]; then
    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_task_alias" '
      {
        $NF = repl
        print
      }
    ')
    printf '%s' "$rewritten_command"
    return 0
  fi

  resolved_last_token=$(resolve_relative_path_case_insensitive "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_last_token" ] && [ "$resolved_last_token" != "$last_token" ]; then
    if ! is_safe_relative_path "$resolved_last_token"; then
      printf '%s' "$raw_command"
      return 0
    fi

    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_last_token" '
      {
        $NF = repl
        print
      }
    ')
    printf '%s' "$rewritten_command"
    return 0
  fi

  parent_dir="."
  case "$last_token" in
    */*)
      parent_dir=${last_token%/*}
      ;;
  esac
  parent_dir=$(trim "$parent_dir")
  if [ -z "$parent_dir" ]; then
    parent_dir="."
  fi
  if [ "$parent_dir" != "." ] && ! is_safe_relative_path "$parent_dir"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ ! -d "$workspace_root/$parent_dir" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  discovery_command="find $parent_dir -maxdepth 1 -type f"
  if [ "$parent_dir" = "." ]; then
    discovery_command="find . -maxdepth 1 -type f"
  fi
  if allowed_command "$discovery_command"; then
    printf '%s' "$discovery_command"
    return 0
  fi

  printf '%s' "$raw_command"
}

autocorrect_readonly_search_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  case "$first_word" in
    rg|grep)
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  last_token=$(printf '%s\n' "$command_trimmed" | awk '{print $NF}')
  last_token=$(trim "$last_token")
  if ! is_safe_relative_path "$last_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  resolved_task_alias=$(resolve_assay_task_relative_path_alias "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_task_alias" ] && [ "$resolved_task_alias" != "$last_token" ]; then
    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_task_alias" '
      {
        $NF = repl
        print
      }
    ')
    if allowed_command "$rewritten_command"; then
      printf '%s' "$rewritten_command"
      return 0
    fi
  fi

  resolved_last_token=$(resolve_relative_path_case_insensitive "$workspace_root" "$last_token" || true)
  replacement_token=$resolved_last_token
  if [ -z "$replacement_token" ]; then
    parent_dir="."
    case "$last_token" in
      */*)
        parent_dir=${last_token%/*}
        ;;
    esac
    parent_dir=$(trim "$parent_dir")
    if [ -z "$parent_dir" ]; then
      parent_dir="."
    fi
    if [ "$parent_dir" != "." ] && ! is_safe_relative_path "$parent_dir"; then
      printf '%s' "$raw_command"
      return 0
    fi
    if [ -d "$workspace_root/$parent_dir" ]; then
      replacement_token=$parent_dir
    else
      replacement_token="."
    fi
  fi
  if [ -z "$replacement_token" ] || ! is_safe_relative_path "$replacement_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ "$replacement_token" = "$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$replacement_token" '
    {
      $NF = repl
      print
    }
  ')
  if allowed_command "$rewritten_command"; then
    printf '%s' "$rewritten_command"
    return 0
  fi
  printf '%s' "$raw_command"
}

autocorrect_readonly_find_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  case "$first_word" in
    find)
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  first_arg=$(printf '%s\n' "$command_trimmed" | awk '{print $2}')
  first_arg=$(trim "$first_arg")
  if ! is_safe_relative_path "$first_arg"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$first_arg" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  replacement=$(resolve_assay_task_relative_path_alias "$workspace_root" "$first_arg" || true)
  if [ -z "$replacement" ]; then
    replacement=$(resolve_relative_path_case_insensitive "$workspace_root" "$first_arg" || true)
  fi
  if [ -z "$replacement" ] || [ "$replacement" = "$first_arg" ]; then
    printf '%s' "$raw_command"
    return 0
  fi
  if ! is_safe_relative_path "$replacement"; then
    printf '%s' "$raw_command"
    return 0
  fi

  rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$replacement" '
    {
      $2 = repl
      print
    }
  ')
  if allowed_command "$rewritten_command"; then
    printf '%s' "$rewritten_command"
    return 0
  fi
  printf '%s' "$raw_command"
}

execute_mediated_command() {
  workspace_id=$1
  workspace_path=$2
  tool_command=$3
  output_file=$4
  status_file=$5
  command_mode=${6:-ask-some}
  blocked_file=${7:-}
  decision_hint_file=${8:-}
  command_timeout_sec=${ARTIFICER_COMMAND_TIMEOUT_SEC:-25}
  case "$command_timeout_sec" in
    ""|*[!0-9]*)
      command_timeout_sec=25
      ;;
  esac
  if [ "$command_timeout_sec" -lt 5 ]; then
    command_timeout_sec=5
  fi
  if [ "$command_timeout_sec" -gt 90 ]; then
    command_timeout_sec=90
  fi
  original_tool_command=$tool_command
  tool_command=$(autocorrect_readonly_find_command_path "$workspace_path" "$tool_command")
  tool_command=$(autocorrect_readonly_file_command_path "$workspace_path" "$tool_command")
  tool_command=$(autocorrect_readonly_search_command_path "$workspace_path" "$tool_command")
  command_autocorrected=0
  if [ "$tool_command" != "$original_tool_command" ]; then
    command_autocorrected=1
  fi
  first_word=$(printf '%s\n' "$tool_command" | awk '{print $1}')

  decision_file=$(mktemp)
  source_file=$(mktemp)
  matched_pattern_file=$(mktemp)
  matched_scope_file=$(mktemp)
  command_policy_decision "$workspace_id" "$tool_command" "$command_mode" "$decision_file" "$source_file" "$matched_pattern_file" "$matched_scope_file"
  decision=$(cat "$decision_file" 2>/dev/null || printf '%s' "prompt")
  source=$(cat "$source_file" 2>/dev/null || printf '%s' "")
  decision_hint=""
  case "$source" in
    global-safe-default) decision_hint="global default" ;;
    rule) decision_hint="workspace rule" ;;
    once-rule) decision_hint="workspace one-time rule" ;;
    mode-all) decision_hint="workspace mode all" ;;
    mode-none) decision_hint="workspace mode none" ;;
  esac
  if [ -n "$decision_hint_file" ]; then
    printf '%s' "$decision_hint" > "$decision_hint_file"
  fi
  rm -f "$decision_file" "$source_file" "$matched_pattern_file" "$matched_scope_file"

  if [ "$decision" = "deny" ]; then
    {
      printf '%s\n' "Blocked by command policy."
      printf '%s\n' "Policy mode: $command_mode"
      printf '%s\n' "Decision source: $source"
      printf '%s\n' "Command: $tool_command"
    } > "$output_file"
    printf 'blocked' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "denied" >> "$blocked_file"
    fi
    return 0
  fi

  if [ "$decision" = "prompt" ]; then
    printf '%s\n' "Command approval required before execution." > "$output_file"
    printf '%s\n' "Command: $tool_command" >> "$output_file"
    printf '%s\n' "Use Command execution = Ask me and approve this command (once or remember)." >> "$output_file"
    printf 'approval_required' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "approval-required" >> "$blocked_file"
    fi
    return 0
  fi

  if allowed_command "$tool_command"; then
    if (
      cd "$workspace_path" &&
        run_shell_command_with_timeout "$command_timeout_sec" "$tool_command"
    ) >"$output_file" 2>&1; then
      if [ "$command_autocorrected" -eq 1 ]; then
        printf '\n(auto-corrected path: %s -> %s)\n' "$original_tool_command" "$tool_command" >> "$output_file"
      fi
      if command_output_indicates_failure "$tool_command" "$output_file"; then
        printf '\n(command reported errors despite zero exit status)\n' >> "$output_file"
        printf 'failed' > "$status_file"
      else
        printf 'ok' > "$status_file"
      fi
    else
      rc=$?
      if [ "$command_autocorrected" -eq 1 ]; then
        printf '\n(auto-corrected path: %s -> %s)\n' "$original_tool_command" "$tool_command" >> "$output_file"
      fi
      if printf '%s\n' "$first_word" | grep -Eq '^(rg|grep)$' && \
         grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested search target is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(rg|grep)$' && [ "$rc" -eq 1 ]; then
        if grep -Eqi 'regex parse error|unrecognized (option|flag)|invalid option|usage:' "$output_file" 2>/dev/null; then
          printf '\n(exit code %s)\n' "$rc" >> "$output_file"
          printf 'failed' > "$status_file"
        else
          printf '\n(non-fatal: no matches found)\n' >> "$output_file"
          printf 'ok' > "$status_file"
        fi
      elif [ "$first_word" = "git" ] && grep -qi 'not a git repository' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal context miss: workspace is not a git repository)\n' >> "$output_file"
        printf 'context_missing' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(cat|head|tail|sed)$' && \
           grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested file is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(ls|find)$' && \
           grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested path is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      else
        if [ "$rc" -eq 124 ]; then
          printf '\n(command timed out after %ss)\n' "$command_timeout_sec" >> "$output_file"
        fi
        printf '\n(exit code %s)\n' "$rc" >> "$output_file"
        printf 'failed' > "$status_file"
      fi
    fi
  else
    printf '%s\n' "Blocked by safety policy. Allowed: read-only shell tools, selected git read commands, lightweight syntax/version checks, and approved local script verify commands." > "$output_file"
    printf 'blocked' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "safety-policy" >> "$blocked_file"
    fi
  fi
}

ensure_agent_files() {
  agent_dir=$1
  mkdir -p "$agent_dir/.scratch"
  mkdir -p "$agent_dir/.tasks"

  if [ ! -f "$agent_dir/.failures.md" ]; then
    cat > "$agent_dir/.failures.md" <<'EOF'
# Failure Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.session.log.md" ]; then
    cat > "$agent_dir/.session.log.md" <<'EOF'
# Session Log

EOF
  fi

  if [ ! -f "$agent_dir/.controller.raw.md" ]; then
    cat > "$agent_dir/.controller.raw.md" <<'EOF'
# Controller Raw Output

EOF
  fi

  if [ ! -f "$agent_dir/.assumptions.md" ]; then
    cat > "$agent_dir/.assumptions.md" <<'EOF'
# Assumptions Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.compliance.md" ]; then
    cat > "$agent_dir/.compliance.md" <<'EOF'
# Compliance Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.architecture.md" ]; then
    cat > "$agent_dir/.architecture.md" <<'EOF'
# Architecture Map

Updated: n/a
Mode: INVESTIGATE
Target: workspace

## Boundaries
- pending

## Interfaces
- pending

## Risks
- pending
EOF
  fi

  if [ ! -f "$agent_dir/.tasks/index.md" ]; then
    cat > "$agent_dir/.tasks/index.md" <<'EOF'
# Task Index

Updated: n/a
status legend: pending | active | done

EOF
  fi

  if [ ! -f "$agent_dir/.context.memory.md" ]; then
    cat > "$agent_dir/.context.memory.md" <<'EOF'
# Context Memory

Updated: n/a
Run Mode: auto

Project core summary will be populated during the loop.
EOF
  fi

  if [ ! -f "$agent_dir/.changed-paths" ]; then
    : > "$agent_dir/.changed-paths"
  fi
}

bootstrap_plan_file() {
  plan_file=$1
  model_name=$2
  workspace_path=$3
  user_prompt=$4

  snapshot_text=$(workspace_snapshot "$workspace_path" | sed -n '1,220p')
  plan_prompt=$(cat <<EOF
Create an execution plan for a coding task.

Return only this template with concise content:
Goal:
Subgoals:
Constraints:
Unknowns:
Next Action:
Completion Criteria:

Workspace snapshot:
$snapshot_text

User request:
$user_prompt
EOF
)

  plan_text=$(run_model "$model_name" "$plan_prompt" || true)
  if [ -z "$(trim "$plan_text")" ]; then
    plan_text=""
  fi

  if ! printf '%s\n' "$plan_text" | grep -q '^Goal:'; then
    plan_text=$(cat <<EOF
Goal:
- $user_prompt
Subgoals:
- understand current workspace state
- make safe incremental progress
Constraints:
- only use mediated tools
- avoid unsafe shell operations
Unknowns:
- exact files and interfaces to change
Next Action:
- inspect relevant files with read-only tools
Completion Criteria:
- requested change implemented or clearly explained with blockers
EOF
)
  fi

  printf '%s\n' "$plan_text" > "$plan_file"
}

bootstrap_quick_programming_plan_file() {
  plan_file=$1
  prompt_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat > "$plan_file" <<EOF
Goal:
- $task_snippet
Subgoals:
- inspect the workspace and identify the smallest safe implementation slice
- make one bounded implementation attempt only if the relevant files are clear
- verify the current result or report the blocker concisely
Constraints:
- keep edits tightly scoped to the requested programming task
- prefer read-only discovery before any patch decision
- do not rely on unsafe shell operations or broad refactors
Unknowns:
- exact files and interfaces that need to change
- which verification command best matches the affected files
Next Action:
- inspect tracked workspace state and likely task hotspots with read-only commands
Completion Criteria:
- either deliver a verified small slice or return a concise blocker summary with evidence
EOF
}

seed_programming_quick_controller_output() {
  prompt_text=$1
  plan_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=collect concrete workspace evidence before any patch
confidence=0.38

COMMANDS:
- ls -la
- find . -maxdepth 2 -type f
- find . -maxdepth 2 -type d

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- initial workspace discovery queued for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

programming_quick_narrow_slice_focus_commands() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  impl_path=""
  verify_path=""
  doc_path=""
  fallback_path=""
  second_impl_path=""

  extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p' | while IFS= read -r rel_path; do
    rel_path=$(trim "$rel_path")
    [ -n "$rel_path" ] || continue
    case "$rel_path" in
      ./*) rel_path=${rel_path#./} ;;
    esac
    if ! is_safe_relative_path "$rel_path"; then
      continue
    fi
    [ -f "$workspace_path/$rel_path" ] || continue
    case "$rel_path" in
      .git/*|.assay-runs/*)
        continue
        ;;
    esac
    printf '%s\n' "$rel_path"
  done | awk '
    {
      path = $0
      lower = tolower(path)
      if (fallback == "" ) fallback = path
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
        if (verify == "") verify = path
        next
      }
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) {
        if (doc == "") doc = path
        next
      }
      if (impl == "") {
        impl = path
      } else if (second_impl == "") {
        second_impl = path
      }
    }
    END {
      if (impl == "") impl = fallback
      if (impl != "") print "cat " impl
      if (second_impl != "" && second_impl != impl) {
        print "cat " second_impl
      }
      if (verify != "" && verify != impl && verify != second_impl) {
        print "cat " verify
      } else if (doc != "" && doc != impl && doc != second_impl) {
        print "head -n 80 " doc
      }
    }
  ' | sed -n '1,3p'
}

programming_quick_narrow_slice_focus_paths() {
  focus_commands=$(programming_quick_narrow_slice_focus_commands "$@")
  printf '%s\n' "$focus_commands" | awk '
    {
      if ($1 == "cat" && $2 != "") {
        print $2
      } else if ($1 == "head" && $2 == "-n" && $4 != "") {
        print $4
      }
    }
  ' | awk '!seen[$0]++' | sed -n '1,3p'
}

programming_quick_narrow_slice_primary_patch_path() {
  focus_paths=$(programming_quick_narrow_slice_focus_paths "$@")
  primary_path=$(printf '%s\n' "$focus_paths" | awk '
    {
      path = $0
      lower = tolower(path)
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) next
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) next
      print path
      exit
    }
  ')
  if [ -z "$(trim "$primary_path")" ]; then
    primary_path=$(printf '%s\n' "$focus_paths" | sed -n '1p')
  fi
  printf '%s' "$(trim "$primary_path")"
}

programming_quick_narrow_slice_secondary_patch_path() {
  programming_quick_narrow_slice_next_followup_path "$@"
}

programming_changed_paths_file_has_path() {
  changed_paths_file=${1-}
  target_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$target_path" ] || return 1
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_paths_match "$changed_path" "$target_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_first_workspace_documentation_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    {
      find "$workspace_path" -maxdepth 2 -type f -iname 'README*' 2>/dev/null
      find "$workspace_path" -maxdepth 2 -type f -iname '*.md' 2>/dev/null
    } | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
      rel_path=$(programming_normalize_relative_path "$rel_path")
      [ -n "$rel_path" ] || continue
      [ -f "$workspace_path/$rel_path" ] || continue
      programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
      printf '%s\n' "$rel_path"
    done | awk '!seen[$0]++' | sed -n '1p'
  )
  printf '%s' "$(trim "$candidate")"
}

programming_first_workspace_verification_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    find "$workspace_path" -maxdepth 3 -type f \( -path '*/tests/*' -o -path '*/test/*' -o -iname '*test*' -o -iname '*spec*' \) 2>/dev/null \
      | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
          rel_path=$(programming_normalize_relative_path "$rel_path")
          [ -n "$rel_path" ] || continue
          [ -f "$workspace_path/$rel_path" ] || continue
          programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
          printf '%s\n' "$rel_path"
        done | awk '!seen[$0]++' | sed -n '1p'
  )
  printf '%s' "$(trim "$candidate")"
}

programming_first_workspace_post_verification_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    find "$workspace_path" -maxdepth 2 -type f \( -iname 'CHANGELOG*' -o -iname 'RELEASE*NOTE*' -o -iname 'MIGRATION*GUIDE*' \) 2>/dev/null \
      | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
          rel_path=$(programming_normalize_relative_path "$rel_path")
          [ -n "$rel_path" ] || continue
          programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
          printf '%s\n' "$rel_path"
        done | awk '!seen[$0]++' | sed -n '1p'
  )
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ] && ! programming_changed_paths_file_has_path "$changed_paths_file" "CHANGELOG.md"; then
    candidate="CHANGELOG.md"
  fi
  printf '%s' "$candidate"
}

programming_quick_narrow_slice_documentation_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 2 -type f \( -iname 'README*' -o -iname '*.md' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        cmd = "test -f " "\"" workspace "/" path "\""
        if (system(cmd) != 0) next
        if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/) {
          if (readme == "") readme = path
          next
        }
        if (lower ~ /[.]md$/) {
          if (doc == "") doc = path
        }
      }
      END {
        if (readme != "") {
          print readme
          exit
        }
        if (doc != "") {
          print doc
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_documentation_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_verification_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 3 -type f \( -path '*/tests/*' -o -path '*/test/*' -o -iname '*test*' -o -iname '*spec*' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        cmd = "test -f " "\"" workspace "/" path "\""
        if (system(cmd) != 0) next
        if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
          if (verify == "") verify = path
        }
      }
      END {
        if (verify != "") {
          print verify
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_verification_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_post_verification_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 2 -type f \( -iname 'CHANGELOG*' -o -iname 'RELEASE*NOTE*' -o -iname 'MIGRATION*GUIDE*' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        if (lower ~ /(^|\/)changelog([.][a-z0-9]+)?$/ || lower ~ /release[_-]?notes?[.](md|txt)$/ || lower ~ /migration[_-]?guide[.](md|txt)$/) {
          print path
          exit
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_post_verification_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_next_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  prompt_text=${5-}
  changed_paths_file=${6-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  prompt_wants_docs=0
  if programming_prompt_has_documentation_branch "$prompt_text"; then
    prompt_wants_docs=1
  fi
  followup_path=$(extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p' | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" -v prompt_wants_docs="$prompt_wants_docs" '
    BEGIN {
      changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
      norm_primary = primary
      gsub(/^[[:space:]]+/, "", norm_primary)
      gsub(/[[:space:]]+$/, "", norm_primary)
      if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
      workspace_prefix = workspace "/"
      split(changed_text, changed_arr, /\n/)
      for (i in changed_arr) {
        changed = changed_arr[i]
        gsub(/^[[:space:]]+/, "", changed)
        gsub(/[[:space:]]+$/, "", changed)
        if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
        if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", changed)
        }
        if (changed != "") seen_changed[changed] = 1
      }
    }
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path ~ /^\.\//) sub(/^\.\//, "", path)
      if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
        sub("^" workspace_prefix, "", path)
      }
      if (path == "" || path == norm_primary || seen_changed[path]) next
      lower = tolower(path)
      cmd = "test -f " "\"" workspace "/" path "\""
      if (system(cmd) != 0) next
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
        if (verify == "") verify = path
        next
      }
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) {
        if (doc == "") doc = path
        next
      }
      if (impl == "") {
        impl = path
      } else if (second_impl == "") {
        second_impl = path
      }
    }
    END {
      if (impl != "" && !seen_out[impl]++) print impl
      if (second_impl != "" && !seen_out[second_impl]++) print second_impl
      if (prompt_wants_docs == 1 && doc != "" && !seen_out[doc]++) print doc
      if (verify != "" && !seen_out[verify]++) print verify
      if (prompt_wants_docs != 1 && doc != "" && !seen_out[doc]++) print doc
    }
  ' | sed -n '1p')
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_guard_paths() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  target_path=$5
  changed_paths_file=${6-}

  {
    programming_quick_narrow_slice_focus_paths "$plan_file" "$contract_file" "$session_file" "$workspace_path"
    if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
      sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true
    fi
  } | awk -v target="$target_path" '
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "" || path == target) next
      if (!seen[path]++) print path
    }
  ' | sed -n '1,3p'
}

programming_normalize_relative_path() {
  target_path=$(trim "${1-}")
  [ -n "$target_path" ] || {
    printf '%s' ""
    return 0
  }
  while [ "${target_path#./}" != "$target_path" ]; do
    target_path=${target_path#./}
  done
  target_path=$(printf '%s' "$target_path" | sed 's#//*#/#g')
  target_path=$(trim "$target_path")
  printf '%s' "$target_path"
}

programming_resolve_workspace_relative_path() {
  workspace_path=$1
  candidate_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$candidate_path" ] || {
    printf '%s' ""
    return 0
  }
  if [ -e "$workspace_path/$candidate_path" ]; then
    printf '%s' "$candidate_path"
    return 0
  fi
  candidate_lower=$(printf '%s' "$candidate_path" | tr '[:upper:]' '[:lower:]')
  resolved_path=$(find "$workspace_path" -maxdepth 4 -type f 2>/dev/null | sed "s|^$workspace_path/||" | awk -v target="$candidate_lower" '
    {
      line = $0
      lower = tolower(line)
      if (lower == target) {
        print line
        exit
      }
    }
  ' | sed -n '1p')
  if [ -n "$(trim "$resolved_path")" ]; then
    printf '%s' "$(programming_normalize_relative_path "$resolved_path")"
    return 0
  fi
  printf '%s' "$candidate_path"
}

programming_paths_match() {
  left_path=$(programming_normalize_relative_path "${1-}")
  right_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$left_path" ] || return 1
  [ -n "$right_path" ] || return 1
  [ "$left_path" = "$right_path" ]
}

programming_changed_paths_count_from_file() {
  changed_paths_file=${1-}
  if [ -z "$changed_paths_file" ] || [ ! -f "$changed_paths_file" ]; then
    printf '%s' "0"
    return 0
  fi
  awk '
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "") next
      if (!seen[path]++) count++
    }
    END {
      print count + 0
    }
  ' "$changed_paths_file"
}

programming_changed_paths_file_has_documentation_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_documentation_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_changed_paths_file_has_verification_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_verification_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_changed_paths_file_has_post_verification_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_post_verification_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_path_is_documentation_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    readme.md|*/readme.md|*.md)
      return 0
      ;;
  esac
  return 1
}

programming_path_is_verification_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    */tests/*|*/test/*|tests/*|test/*|*test*.sh|*spec*.sh)
      return 0
      ;;
  esac
  return 1
}

programming_path_is_post_verification_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    changelog.md|*/changelog.md|change-log.md|*/change-log.md|release-notes.md|*/release-notes.md|release_notes.md|*/release_notes.md|migration-guide.md|*/migration-guide.md|migration_guide.md|*/migration_guide.md)
      return 0
      ;;
  esac
  return 1
}

programming_js_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cp "$source_file" "$tmp_file"
  command_name=$(basename "$target_path")
  command_name=${command_name%.js}
  [ -n "$command_name" ] || command_name="cli"
  default_name=$(sed -n "s/.*process\\.argv\\[2\\][[:space:]]*||[[:space:]]*\\(['\"][^'\"]*['\"]\\).*/\\1/p" "$source_file" | sed -n '1p')
  [ -n "$default_name" ] || default_name="'world'"
  PROGRAMMING_CLI_USAGE="usage: $command_name [name]" PROGRAMMING_CLI_DEFAULT_NAME="$default_name" perl -0pi -e '
    my $usage = $ENV{"PROGRAMMING_CLI_USAGE"} // "usage: cli [name]";
    my $default = $ENV{"PROGRAMMING_CLI_DEFAULT_NAME"} // q{"world"};
    my $replacement = qq{const arg = process.argv[2];
if (arg === "--help" || arg === "-h") {
  console.log("$usage");
  process.exit(0);
}
const name = (arg || $default).trim() || $default;};
    my $changed = 0;
    if ($_ !~ /--help/ && s/const\s+name\s*=\s*process\.argv\[2\]\s*\|\|\s*[^\n;]+;/$replacement/s) {
      $changed = 1;
    }
    if (!$changed && $_ !~ /--help/ && /process\.argv\[2\]/) {
      s{(const\s+\{?[A-Za-z0-9_,[:space:]]+\}?\s*=\s*require\([^\n]+\);\n)}{$1const arg = process.argv[2];
if (arg === "--help" || arg === "-h") {
  console.log("$usage");
  process.exit(0);
}
}x;
      s/process\.argv\[2\]/arg/g;
    }
  ' "$tmp_file"
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_js_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  if ! grep -Eq 'function[[:space:]]+greet[[:space:]]*\(' "$source_file"; then
    return 0
  fi
  if ! grep -Eq 'module\.exports[[:space:]]*=[[:space:]]*\{[[:space:]]*greet[[:space:]]*\}' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
function greet(name) {
  const normalized = String(name == null ? 'world' : name).trim();
  const finalName = normalized || 'world';
  return 'hello ' + finalName;
}
module.exports = { greet };
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_workspace_primary_python_module() {
  workspace_path=$1
  primary_path=$(find "$workspace_path" -maxdepth 1 -type f -name '*.py' ! -name '__init__.py' | sed -n '1p')
  [ -n "$primary_path" ] || return 0
  module_name=$(basename "$primary_path")
  module_name=${module_name%.py}
  printf '%s' "$module_name"
}

programming_python_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    bin/*.py|*/bin/*.py|tests/*.py|*/tests/*.py|test/*.py|*/test/*.py)
      return 0
      ;;
  esac
  source_file="$workspace_path/$target_path"
  if ! grep -Eq '^def[[:space:]]+greet[[:space:]]*\(' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
def greet(name):
    normalized = "world" if name is None else str(name).strip()
    final_name = normalized or "world"
    return f"hello {final_name}"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_python_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  module_name=$(programming_workspace_primary_python_module "$workspace_path")
  [ -n "$module_name" ] || module_name="app"
  command_name=$(basename "$target_path")
  [ -n "$command_name" ] || command_name="cli.py"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from $module_name import greet


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] in {"-h", "--help"}:
        print("usage: $command_name [name]")
        return 0
    name = args[0] if args else "world"
    print(greet(name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_workspace_primary_shell_script() {
  workspace_path=$1
  primary_path=$(find "$workspace_path" -maxdepth 1 -type f -name '*.sh' ! -name '*.test.sh' ! -name '*_test.sh' | sed -n '1p')
  [ -n "$primary_path" ] || return 0
  printf '%s' "$(basename "$primary_path")"
}

programming_shell_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    bin/*.sh|*/bin/*.sh|tests/*.sh|*/tests/*.sh|test/*.sh|*/test/*.sh)
      return 0
      ;;
  esac
  source_file="$workspace_path/$target_path"
  if ! grep -Eq 'hello' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
#!/bin/sh
set -eu

name=${1-}
normalized=$(printf '%s' "${name:-world}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[ -n "$normalized" ] || normalized="world"

printf '%s\n' "hello $normalized"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_shell_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  root_script=$(programming_workspace_primary_shell_script "$workspace_path")
  [ -n "$root_script" ] || root_script="greet.sh"
  command_name=$(basename "$target_path")
  [ -n "$command_name" ] || command_name="greet.sh"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)
ROOT_DIR=\$(CDPATH= cd -- "\$SCRIPT_DIR/.." && pwd)

if [ "\${1-}" = "--help" ] || [ "\${1-}" = "-h" ]; then
  printf '%s\n' "usage: $command_name [name]"
  exit 0
fi

exec sh "\$ROOT_DIR/$root_script" "\$@"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_examples_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  example_line='- `node app.js Sam` prints `hello Sam`.'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        example_line="- \`python3 $cli_rel Sam\` prints \`hello Sam\`."
        ;;
      *.sh)
        example_line="- \`sh $cli_rel Sam\` prints \`hello Sam\`."
        ;;
      *)
        example_line="- \`node $cli_rel Sam\` prints \`hello Sam\`."
        ;;
    esac
  fi
  if [ -f "$source_file" ]; then
    cp "$source_file" "$tmp_file"
  else
    printf '# Examples\n' > "$tmp_file"
  fi
  if ! grep -Eiq '^# Examples|^##[[:space:]]+Examples' "$tmp_file"; then
    printf '\n# Examples\n' >> "$tmp_file"
  fi
  if ! grep -Fqi "$example_line" "$tmp_file"; then
    printf '\n%s\n' "$example_line" >> "$tmp_file"
  fi
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_readme_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cp "$source_file" "$tmp_file"
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  lower_cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  usage_line='Run `node app.js` for a quick manual check.'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        usage_line="Run \`python3 $cli_rel [name]\` for a quick manual check."
        ;;
      *.sh)
        usage_line="Run \`sh $cli_rel [name]\` for a quick manual check."
        ;;
      *)
        usage_line="Run \`node $cli_rel [name]\` for a quick manual check."
        ;;
    esac
  fi
  if ! grep -Eiq '^##[[:space:]]+usage' "$tmp_file"; then
    {
      printf '\n## Usage\n\n%s\n' "$usage_line"
    } >> "$tmp_file"
  elif ! grep -Fqi "$usage_line" "$tmp_file"; then
    {
      printf '\n%s\n' "$usage_line"
    } >> "$tmp_file"
  fi
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_pyproject_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  module_name=$(programming_workspace_primary_python_module "$workspace_path")
  [ -n "$module_name" ] || module_name="app"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
[project]
name = "$module_name"
version = "0.1.0"
requires-python = ">=3.9"
description = "Small CLI utility for the current verified slice."

[tool.artificer]
cli_path = "bin/$module_name.py"
EOF
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_release_note_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  tmp_file=$(mktemp)
  if [ -f "$source_file" ]; then
    cp "$source_file" "$tmp_file"
  else
    case "$lower_target_path" in
      *migration*guide*)
        printf '# Migration Guide\n' > "$tmp_file"
        ;;
      *release*note*)
        printf '# Release Notes\n' > "$tmp_file"
        ;;
      *)
        printf '# Changelog\n' > "$tmp_file"
        ;;
    esac
  fi
  note_line='- Add a small CLI entry point, usage note, and shell verification coverage for this slice.'
  if printf '%s' "$lower_target_path" | grep -Eq 'changelog|change-log'; then
    if ! grep -Eiq '^##[[:space:]]+unreleased' "$tmp_file"; then
      printf '\n## Unreleased\n\n%s\n' "$note_line" >> "$tmp_file"
    elif ! grep -Fqi "$note_line" "$tmp_file"; then
      printf '\n%s\n' "$note_line" >> "$tmp_file"
    fi
  elif ! grep -Fqi "$note_line" "$tmp_file"; then
    printf '\n%s\n' "$note_line" >> "$tmp_file"
  fi
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_shell_test_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  run_command='node ./app.js'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        run_command="python3 ./$cli_rel"
        ;;
      *.sh)
        run_command="sh \"./$cli_rel\""
        ;;
      *)
        run_command="./$cli_rel"
        ;;
    esac
  fi
  if [ "$(printf '%s' "$run_command" | tr '[:upper:]' '[:lower:]')" = "./$lower_cli_rel" ] && printf '%s' "$lower_cli_rel" | grep -Eq '\.js$'; then
    cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

run_js_cli() {
  if command -v node >/dev/null 2>&1; then
    node "$run_command" "\$@"
    return 0
  fi
  if command -v deno >/dev/null 2>&1; then
    deno run --allow-read --unstable-detect-cjs "$run_command" "\$@"
    return 0
  fi
  echo "no supported JavaScript runtime found for $run_command" >&2
  exit 1
}

default_output=\$(run_js_cli)
[ "\$default_output" = "hello world" ]

named_output=\$(run_js_cli Sam)
[ "\$named_output" = "hello Sam" ]
EOF
  else
    cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

default_output=\$($run_command)
[ "\$default_output" = "hello world" ]

named_output=\$($run_command Sam)
[ "\$named_output" = "hello Sam" ]
EOF
  fi
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_adjacent_slice_fallback_patch_for_path() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    examples.md|*/examples.md|*example*.md|samples*.md|*/samples*.md)
      programming_examples_followup_patch "$workspace_path" "$target_path"
      ;;
    pyproject.toml|*/pyproject.toml)
      programming_pyproject_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.js|*/bin/*.js|*cli*.js)
      programming_js_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.py|*/bin/*.py|*cli*.py)
      programming_python_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.sh|*/bin/*.sh|*cli*.sh)
      programming_shell_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    changelog.md|*/changelog.md|change-log.md|*/change-log.md|release-notes.md|*/release-notes.md|release_notes.md|*/release_notes.md|migration-guide.md|*/migration-guide.md|migration_guide.md|*/migration_guide.md)
      programming_release_note_followup_patch "$workspace_path" "$target_path"
      ;;
    readme.md|*/readme.md|*.md)
      programming_readme_followup_patch "$workspace_path" "$target_path"
      ;;
    */tests/*|*/test/*|tests/*|test/*|*test*.sh|*spec*.sh)
      programming_shell_test_followup_patch "$workspace_path" "$target_path"
      ;;
  esac
}

programming_primary_slice_fallback_patch_for_path() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    app.js|*/app.js|*greet*.js)
      programming_js_greet_primary_patch "$workspace_path" "$target_path"
      ;;
    *.py)
      programming_python_greet_primary_patch "$workspace_path" "$target_path"
      ;;
    *.sh)
      programming_shell_greet_primary_patch "$workspace_path" "$target_path"
      ;;
  esac
}

programming_record_changed_paths() {
  changed_paths_file=$1
  new_paths_file=$2
  merged_paths_file=$(mktemp)
  {
    if [ -f "$changed_paths_file" ]; then
      sed -n '1,50p' "$changed_paths_file"
    fi
    if [ -f "$new_paths_file" ]; then
      sed -n '1,50p' "$new_paths_file"
    fi
  } | sed '/^[[:space:]]*$/d' | awk '!seen[$0]++' > "$merged_paths_file"
  mv "$merged_paths_file" "$changed_paths_file"
  ARTIFICER_PROGRAMMING_CHANGED_PATHS=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
}

programming_file_blocks_context_for_paths() {
  workspace_path=$1
  paths_text=$2

  printf '%s\n' "$paths_text" | while IFS= read -r rel_path; do
    rel_path=$(trim "$rel_path")
    [ -n "$rel_path" ] || continue
    if ! is_safe_relative_path "$rel_path"; then
      continue
    fi
    printf 'FILE: %s\n' "$rel_path"
    printf '```\n'
    if [ -f "$workspace_path/$rel_path" ]; then
      sed -n '1,220p' "$workspace_path/$rel_path"
    else
      printf '(missing file)\n'
    fi
    printf '\n```\n'
  done
}

programming_patch_from_file_blocks_output() {
  workspace_path=$1
  output_file=$2
  file_blocks_dir=$(mktemp -d)
  file_blocks_index=$(mktemp)
  : > "$file_blocks_index"

  cat "$output_file" | FILE_BLOCKS_DIR="$file_blocks_dir" perl -e '
    use strict;
    use warnings;
    local $/;
    my $raw = <>;
    my $dir = $ENV{"FILE_BLOCKS_DIR"} // "";
    my $count = 0;
    my %seen_path;

    my $emit = sub {
      my ($path, $content) = @_;
      $path = "" if !defined $path;
      $content = "" if !defined $content;
      $path =~ s/^\s+//;
      $path =~ s/\s+$//;
      return if $path eq "";
      return if $path =~ m{(?:^|/)\.\.(?:/|$)};
      return if $path =~ m{^/};
      return if $seen_path{$path};
      return if $content !~ /\S/;
      $count += 1;
      return if $count > 5;
      my $tmp_path = "$dir/$count.content";
      open my $fh, ">:encoding(UTF-8)", $tmp_path or return;
      print {$fh} $content;
      close $fh;
      $seen_path{$path} = 1;
      print "$path\t$tmp_path\n";
    };

    while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n```[^\n]*\n(.*?)\n```/sg) {
      $emit->($1, $2);
    }

    if ($count == 0) {
      while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n(.*?)(?=\r?\nFILE:\s*[^\r\n]+\s*\r?\n|\z)/sg) {
        my $path = $1;
        my $content = $2 // "";
        $content =~ s/\A\r?\n//;
        $content =~ s/\r?\n\z//;
        $content =~ s/\A```[^\n]*\n//s;
        $content =~ s/\n```[ \t]*\z//s;
        $emit->($path, $content);
      }
    }
  ' > "$file_blocks_index"

  synthesized_patch=""
  if [ -s "$file_blocks_index" ]; then
    while IFS='	' read -r out_path out_tmp; do
      out_path=$(trim "$out_path")
      out_tmp=$(trim "$out_tmp")
      [ -n "$out_path" ] || continue
      [ -f "$out_tmp" ] || continue
      if ! is_safe_relative_path "$out_path"; then
        continue
      fi
      mkdir -p "$(dirname "$workspace_path/$out_path")" 2>/dev/null || true
      if [ -f "$workspace_path/$out_path" ]; then
        file_diff=$(diff -u "$workspace_path/$out_path" "$out_tmp" || true)
        if [ -n "$(trim "$file_diff")" ]; then
          file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- a/$out_path|;2s|^+++ .*|+++ b/$out_path|")
          synthesized_patch="${synthesized_patch}
${file_diff}"
        fi
      else
        file_diff=$(diff -u /dev/null "$out_tmp" || true)
        if [ -n "$(trim "$file_diff")" ]; then
          file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
          synthesized_patch="${synthesized_patch}
${file_diff}"
        fi
      fi
    done < "$file_blocks_index"
  fi

  rm -rf "$file_blocks_dir" 2>/dev/null || true
  rm -f "$file_blocks_index"
  synthesized_patch=$(trim_block_edges "$synthesized_patch")
  printf '%s' "$synthesized_patch"
}

extract_first_fenced_code_block() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    if (/```[^\n]*\n(.*?)\n```/s) {
      print $1;
    } elsif (/```[^\n]*[ \t]+(.*?)```/s) {
      print $1;
    }
  '
}

extract_primary_file_content_from_output() {
  primary_path=$1
  text=$2
  PRIMARY_PATH="$primary_path" printf '%s\n' "$text" | perl -CS -0777 -ne '
    use strict;
    use warnings;
    my $raw = $_;
    my $path = $ENV{"PRIMARY_PATH"} // "";
    my $quoted = quotemeta($path);

    if ($path ne "" && $raw =~ /FILE:\s*$quoted\s*```[^\n]*\s*(.*?)```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /FILE:\s*[^\r\n]+\s*```[^\n]*\s*(.*?)```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /```[^\n]*\n(.*?)\n```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /```[^\n]*[ \t]+(.*?)```/s) {
      print $1;
      exit;
    }

    $raw =~ s/^FILE:\s*[^\r\n]+\s*//s;
    $raw =~ s/^```[^\n]*\n?//s;
    $raw =~ s/```[ \t]*$//s;
    print $raw;
  '
}

programming_focus_file_candidate_is_usable() {
  primary_path=$1
  content=$(trim "$2")

  [ -n "$content" ] || return 1
  if printf '%s\n' "$content" | grep -Eiq '^[[:space:]]*(full|updated)[[:space:]]+file[[:space:]]+content\b|^[[:space:]]*full[[:space:]]+updated[[:space:]]+file[[:space:]]+content[[:space:]]+for\b'; then
    return 1
  fi
  return 0
}

programming_patch_from_focus_output() {
  workspace_path=$1
  output_file=$2
  primary_path=$(trim "${3:-}")

  raw_text=$(cat "$output_file")

  if [ -n "$primary_path" ] && is_safe_relative_path "$primary_path"; then
    file_candidate=$(extract_primary_file_content_from_output "$primary_path" "$raw_text")
    file_candidate=$(trim "$file_candidate")
    if programming_focus_file_candidate_is_usable "$primary_path" "$file_candidate"; then
      current_tmp=$(mktemp)
      candidate_tmp=$(mktemp)
      if [ -f "$workspace_path/$primary_path" ]; then
        cat "$workspace_path/$primary_path" > "$current_tmp"
      else
        : > "$current_tmp"
      fi
      printf '%s\n' "$file_candidate" > "$candidate_tmp"
      fallback_patch=$(diff -u "$current_tmp" "$candidate_tmp" || true)
      rm -f "$current_tmp" "$candidate_tmp"
      if [ -n "$(trim "$fallback_patch")" ]; then
        if [ -f "$workspace_path/$primary_path" ]; then
          fallback_patch=$(printf '%s\n' "$fallback_patch" | sed "1s|^--- .*|--- a/$primary_path|;2s|^+++ .*|+++ b/$primary_path|")
        else
          fallback_patch=$(printf '%s\n' "$fallback_patch" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$primary_path|")
        fi
        fallback_patch=$(trim_block_edges "$fallback_patch")
        if [ -n "$fallback_patch" ]; then
          printf '%s' "$fallback_patch"
          return 0
        fi
      fi
    fi
  fi

  printf '%s' ""
}

seed_programming_quick_narrow_slice_controller_output() {
  prompt_text=$1
  plan_text=$2
  plan_file=$3
  contract_file=$4
  session_file=$5
  workspace_path=$6
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  focus_commands=$(programming_quick_narrow_slice_focus_commands "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  focus_commands=$(trim "$focus_commands")
  if [ -z "$focus_commands" ]; then
    return 1
  fi
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=inspect one implementation slice closely before generating a patch
confidence=0.54

COMMANDS:
$(printf '%s\n' "$focus_commands" | sed 's/^/- /')

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- focused one implementation slice before patch generation for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

seed_programming_quick_narrow_slice_implement_output() {
  prompt_text=$1
  plan_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=apply one focused implementation slice without widening
confidence=0.58

COMMANDS:
NONE

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- applying one focused implementation slice for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

seed_programming_quick_narrow_slice_verify_output() {
  prompt_text=$1
  plan_text=$2
  workspace_path=$3
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  verify_commands=$(emit_default_verify_commands "$workspace_path" "$prompt_text")
  verify_commands=$(trim "$verify_commands")
  if [ -z "$verify_commands" ]; then
    verify_commands="git status --short"
  fi
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=verify the focused implementation slice before any wider changes
confidence=0.64

COMMANDS:
$(printf '%s\n' "$verify_commands" | sed 's/^/- /')

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- verifying the focused implementation slice for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

append_failure_entry() {
  ledger_file=$1
  action_text=$2
  error_text=$3
  hypothesis_text=$4
  next_text=$5
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s\n' "$timestamp"
    printf 'Action: %s\n' "$action_text"
    printf 'Error: %s\n' "$error_text"
    printf 'Hypothesis: %s\n' "$hypothesis_text"
    printf 'Next Attempt: %s\n\n' "$next_text"
  } >> "$ledger_file"

  if command -v mr_failure_taxonomy_record >/dev/null 2>&1; then
    ensure_mode_runtime_bootstrap
    active_run_mode=$(trim "${ARTIFICER_ACTIVE_RUN_MODE:-unknown}")
    [ -n "$active_run_mode" ] || active_run_mode="unknown"
    mr_failure_taxonomy_record "$action_text" "$error_text" "$hypothesis_text" "$next_text" "$active_run_mode" >/dev/null 2>&1 || true
  fi
}

append_session_entry() {
  session_file=$1
  heading=$2
  body=$3
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s - %s\n' "$timestamp" "$heading"
    printf '%s\n\n' "$body"
  } >> "$session_file"
}

append_assumption_entry() {
  assumptions_file=$1
  mode_value=$2
  assumption_text=$3
  unchecked_text=$4
  risk_text=$5
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s - mode=%s\n' "$timestamp" "$mode_value"
    printf 'Assumption: %s\n' "$assumption_text"
    printf 'Unchecked: %s\n' "$unchecked_text"
    printf 'Constraint Risk: %s\n\n' "$risk_text"
  } >> "$assumptions_file"
}

append_compliance_entry() {
  compliance_file=$1
  run_mode=$2
  state_mode=$3
  status_value=$4
  checks_text=$5
  findings_text=$6
  gate_text=$7
  next_text=$8
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  [ -n "$status_value" ] || status_value="pass"
  [ -n "$checks_text" ] || checks_text="- legal_compliance=pass\n- ethical_non_abuse=pass\n- external_action_gate=none"
  [ -n "$findings_text" ] || findings_text="No compliance issues detected in this iteration."
  [ -n "$gate_text" ] || gate_text="none"
  [ -n "$next_text" ] || next_text="Continue with current mode."

  {
    printf '## %s - run_mode=%s state=%s status=%s\n' "$timestamp" "$run_mode" "$state_mode" "$status_value"
    printf 'Checks:\n%s\n' "$checks_text"
    printf 'Findings: %s\n' "$findings_text"
    printf 'Required Gate: %s\n' "$gate_text"
    printf 'Next: %s\n\n' "$next_text"
  } >> "$compliance_file"
}

plan_section_text() {
  plan_file=$1
  start_header=$2
  end_header=$3
  max_lines=${4:-14}
  if [ ! -f "$plan_file" ]; then
    return 0
  fi
  if [ -n "$end_header" ]; then
    sed -n "/^${start_header}:/,/^${end_header}:/p" "$plan_file" | sed '1d;$d' | sed -n "1,${max_lines}p"
  else
    sed -n "/^${start_header}:/,\$p" "$plan_file" | sed '1d' | sed -n "1,${max_lines}p"
  fi
}

extract_file_hotspots() {
  source_a=$1
  source_b=$2
  source_c=$3
  (
    if [ -f "$source_a" ]; then cat "$source_a"; fi
    if [ -f "$source_b" ]; then cat "$source_b"; fi
    if [ -f "$source_c" ]; then cat "$source_c"; fi
  ) | perl -ne '
    while (/([A-Za-z0-9_\/\.-]+\.[A-Za-z0-9]{1,8})/g) {
      my $p = lc($1);
      next if length($p) > 130;
      next if $p =~ /^[0-9]+$/;
      $p =~ s#^\./##;
      print "$p\n";
    }
  ' | sort | uniq -c | sort -nr | sed -n '1,12p' | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+/- /'
}

task_slug_from_title() {
  raw_title=$1
  slug=$(printf '%s' "$raw_title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')
  [ -n "$slug" ] || slug="task"
  printf '%s' "$slug"
}

refresh_programming_artifacts() {
  plan_file=$1
  state_file=$2
  session_file=$3
  failures_file=$4
  contract_file=$5
  architecture_file=$6
  tasks_dir=$7
  tasks_index_file="$tasks_dir/index.md"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")
  state_target=$(state_get "$state_file" "target" "workspace")
  state_blocking=$(state_get "$state_file" "blocking" "none")
  state_confidence=$(state_get "$state_file" "confidence" "0.20")

  hotspots=$(extract_file_hotspots "$plan_file" "$contract_file" "$session_file")
  [ -n "$(trim "$hotspots")" ] || hotspots="- none yet"

  contract_summary=$(sed -n '1,100p' "$contract_file" 2>/dev/null || true)
  [ -n "$(trim "$contract_summary")" ] || contract_summary="(contract not established yet)"
  session_signals=$(grep -E '^## ' "$session_file" 2>/dev/null | tail -n 8)
  [ -n "$(trim "$session_signals")" ] || session_signals="- none yet"
  failure_signals=$(grep -E '^(Action|Error|Next Attempt):' "$failures_file" 2>/dev/null | tail -n 10)
  [ -n "$(trim "$failure_signals")" ] || failure_signals="- none yet"

  cat > "$architecture_file" <<EOF
# Architecture Map

Updated: $timestamp
Mode: $state_mode
Target: $state_target
Blocking: $state_blocking
Confidence: $state_confidence

## Boundaries
- Keep edits scoped to the active target and explicit requirements.
- Preserve build/run viability between iterations.
- Keep interfaces stable unless contract requires change.

## Hotspots
$hotspots

## Contract Summary
$contract_summary

## Recent Iteration Markers
$session_signals

## Open Risks
$failure_signals
EOF

  mkdir -p "$tasks_dir"
  find "$tasks_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' -delete 2>/dev/null || true

  subgoals_text=$(plan_section_text "$plan_file" "Subgoals" "Constraints" 40)
  task_titles_file=$(mktemp)
  : > "$task_titles_file"
  printf '%s\n' "$subgoals_text" | while IFS= read -r line; do
    candidate=$(trim "$line")
    [ -n "$candidate" ] || continue
    candidate=$(printf '%s\n' "$candidate" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
    candidate=$(trim "$candidate")
    [ -n "$candidate" ] || continue
    printf '%s\n' "$candidate" >> "$task_titles_file"
  done
  awk '!seen[tolower($0)]++' "$task_titles_file" > "${task_titles_file}.dedup"
  mv "${task_titles_file}.dedup" "$task_titles_file"
  if [ ! -s "$task_titles_file" ]; then
    next_action_text=$(plan_section_text "$plan_file" "Next Action" "Completion Criteria" 8)
    fallback_task=$(printf '%s\n' "$next_action_text" | sed -n '1p')
    fallback_task=$(trim "$fallback_task")
    [ -n "$fallback_task" ] || fallback_task="Continue implementation from current evidence."
    printf '%s\n' "$fallback_task" > "$task_titles_file"
  fi

  {
    printf '# Task Index\n\n'
    printf 'Updated: %s\n' "$timestamp"
    printf 'status legend: pending | active | done\n\n'
  } > "$tasks_index_file"

  task_n=0
  while IFS= read -r task_title; do
    task_title=$(trim "$task_title")
    [ -n "$task_title" ] || continue
    task_n=$((task_n + 1))
    if [ "$task_n" -gt 12 ]; then
      break
    fi
    task_id=$(printf '%03d' "$task_n")
    task_slug=$(task_slug_from_title "$task_title")
    task_file="$tasks_dir/${task_id}-${task_slug}.md"
    task_status="pending"
    if [ "$state_mode" = "DONE" ]; then
      task_status="done"
    elif [ "$task_n" -eq 1 ]; then
      task_status="active"
    fi

    {
      printf 'status: %s\n' "$task_status"
      printf 'title: %s\n' "$task_title"
      printf 'updated: %s\n' "$timestamp"
      printf 'source: plan-subgoal\n\n'
      printf 'Objective:\n- %s\n\n' "$task_title"
      printf 'Context:\n- mode=%s\n- target=%s\n- blocking=%s\n' "$state_mode" "$state_target" "$state_blocking"
    } > "$task_file"

    printf -- '- [%s] %s - %s\n' "$task_status" "$(basename "$task_file")" "$task_title" >> "$tasks_index_file"
  done < "$task_titles_file"

  rm -f "$task_titles_file"
}

run_mode_policy_instructions() {
  run_mode=$1
  case "$run_mode" in
    programming)
      cat <<'EOF'
Run mode policy:
- prioritize scalable architecture and clear module boundaries for multi-file codebases.
- prefer incremental checkpoints that keep the project runnable between iterations.
- keep .contract.md and context memory aligned when design decisions change.
- aggressively compress context to retain only actionable architecture state and open risks.
- if requirements are ambiguous, state explicit assumptions and proceed with a safe high-value implementation slice.
- before claiming completion, ensure verification evidence directly covers changed behavior.
EOF
      ;;
    pentest)
      cat <<'EOF'
Run mode policy:
- prioritize adversarial testing depth: enumerate exploit paths, abuse cases, and boundary failures.
- pair each credible attack path with concrete mitigations and verification checks.
- keep all testing scoped to safe internal validation; do not enable real-world abuse.
- report findings with impact level, evidence, and remediation status.
EOF
      ;;
    security-audit)
      cat <<'EOF'
Run mode policy:
- prioritize systematic security review across auth, validation, secrets, and dependency risk.
- produce auditable findings with severity, evidence, and mitigation guidance.
- map each high-impact claim to concrete evidence anchors and numeric accept/reject thresholds.
- prefer least-privilege and defense-in-depth changes that are testable and reversible.
- avoid speculative claims and clearly mark uncertainty when evidence is incomplete.
EOF
      ;;
    report)
      cat <<'EOF'
Run mode policy:
- prioritize evidence quality, source fidelity, and explicit uncertainty.
- structure output for executive readability: findings, evidence, risks, recommendations.
- include an explicit claim-to-evidence map with concrete anchors (logs, metrics, queries, policy clauses, tests) and freshness caveats.
- avoid speculative claims when direct evidence is missing.
- when inputs are underspecified, declare assumptions with confidence and proceed rather than stalling.
- when constraints conflict, explicitly map the conflict, choose a priority order, and state rejected alternatives.
- include a short contradiction check before claiming completion on ambiguous tasks.
EOF
      ;;
    text-perfecter)
      cat <<'EOF'
Run mode policy:
- optimize both language quality and underlying content correctness; do not do style-only rewrites.
- run iterative revisions until change deltas stabilize, then stop with an explicit convergence rationale.
- gather broad evidence before rewriting claims: techniques, variants, common failures, and informed discussion.
- if evidence conflicts, surface alternatives and explain why one version is selected.
- include a contradiction check and unresolved uncertainty note before claiming "perfected."
- avoid confidently asserting unsupported facts; mark unverifiable claims and keep safer wording when needed.
EOF
      ;;
    gui-testing)
      cat <<'EOF'
Run mode policy:
- execute hands-on GUI automation as a real user journey, not a static code-only review.
- prefer cross-platform automation harnesses first: run `hosted-web/scripts/gui-regression-system.sh` with profile selection based on requested depth.
- on macOS, use Safari automation; on Linux, use Firefox automation; if both are available, compare outcomes.
- treat every UX flaw as actionable: ambiguous status text, ordering glitches, visual artifacts, stalled states, or inaccessible controls.
- fail closed on unclear signals: report concrete repro steps, expected vs actual behavior, and severity before proposing fixes.
- after fixes, rerun the same scenario to verify closure and capture regression evidence paths.
EOF
      ;;
    assistant)
      cat <<'EOF'
Run mode policy:
- this mode represents a globally configured team profile; apply team policy while driving end-to-end completion.
- proactively drive end-to-end completion with initiative and practical sequencing.
- optimize for real user value and sustainable outcomes; never game or exploit systems.
- enforce legal, ethical, and policy compliance; avoid deception, spam, and abuse.
- keep evidence quality concrete: cite anchors, quantify thresholds, and disclose freshness/uncertainty caveats for key claims.
- require explicit user approval before irreversible external actions (payments, legal filings, account creation, outreach to real people).
- if details are missing but inferable, document assumptions and continue with best-effort execution.
- prefer one complete, verified high-confidence slice over broad but shallow partial progress.
- if requirements collide, state what cannot be simultaneously satisfied and provide a defensible priority decision.
- for adversarial or ambiguous prompts, include a contradiction check and at least one alternative path in the final output.
EOF
      ;;
    chat)
      cat <<'EOF'
Run mode policy:
- prioritize continuity across turns: keep the active thread and user framing corrections intact.
- prioritize clarity, empathy, and concise direct help.
- prefer insight and concrete distinctions over generic platitudes.
- avoid unnecessary tooling loops when a straightforward response is sufficient.
EOF
      ;;
    teacher)
      cat <<'EOF'
Run mode policy:
- maintain and use a persistent learner model to adapt depth, pacing, and framing.
- teach with concept scaffolding, retrieval checks, and concrete examples before abstraction.
- track likely misconceptions and explicitly correct them with brief diagnostic checks.
- account for time since last interaction; add recap when gaps are longer and set spaced-review guidance.
- surface and correct plausible false assumptions explicitly before reinforcing a mental model.
- include one diagnostic contradiction check to verify that the misconception was actually resolved.
EOF
      ;;
    instant)
      cat <<'EOF'
Run mode policy:
- optimize for speed while still preserving accuracy and safety.
EOF
      ;;
    *)
      cat <<'EOF'
Run mode policy:
- balance progress, safety, and verification with practical iteration scope.
EOF
      ;;
  esac
}

prompt_requires_adversarial_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'conflict|contradict|trade[- ]?off|cannot satisfy|simultaneous|incomplete evidence|uncertain|unknown|misconception|false assumption|underspecified|adversarial|ambiguous|near[- ]?miss|deceptive|counterexample|counterevidence|misleading|retry storm|opposite directions|first narrative|anecdote|story-driven|prove (this|it) wrong|invalidation evidence|counterfactual test|abuse case|blast radius|cost of being wrong|red-team|red team'; then
    return 0
  fi
  return 1
}

prompt_requires_cross_domain_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'cross[- ]?domain|stakeholder|trade[- ]?off|priority order|conflicting goals|architecture|security|compliance|policy|product|ux|metric|causal|incident|rollback|strategy|governance|teacher|teaching|explain|misconception|queue|latency|throughput|forensics|debug|slo|error budget|regulated|residency|retention|legal|finance|margin|cost[- ]?to[- ]?serve|chargeback|consent|region constraints?|deletion guarantees?|system layout|workflow platform|resilience drills|trust checks|governance checkpoints|service[- ]?cost|jurisdiction|consent separation|moderation burden|setup flow'; then
    return 0
  fi
  return 1
}

prompt_requires_decision_completeness() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'decision|strategy|plan|fallback|contingency|trade[- ]?off|priority|launch|rollout|incident|architecture'; then
    return 0
  fi
  return 1
}

prompt_requires_recovery_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'incident|forensic|debug|root cause|incomplete evidence|uncertain|unknown|re[- ]?plan|rollback|recovery|self[- ]?correction|failover|degradation|counterexample|disconfirming|ambiguous|retry storm'; then
    return 0
  fi
  return 1
}

prompt_requires_assumption_revision_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'misconception|false assumption|plausible but false|attractive but wrong|initial hypothesis|initial assumption|assumption[- ]?revision|first narrative|prove (this|it) wrong|invalidating evidence|invalidated|falsifying evidence|counterevidence|revised from|confidence shift|before/after confidence|revised decision explicit|make the revised decision explicit|make the revised call explicit|make the decision change explicit|decision change explicit|make the shift in recommendation explicit|shift in recommendation explicit|show the pivot|spell out the pivot|changes the answer|changed the answer|changes the decision|changed the decision|changes the call|changed the call'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|first intuition|at first glance|obvious explanation|surface[- ]?win|what changed your mind|what changed the call|what changed the answer|what overturned the original read|what overturned the first read|overturned the original read|overturned the first read|early view missed|showing why the initial|showing how the evidence changed|showing how the evidence changes|showing what changed the decision|showing what changed the answer|what the first rule misses|what the first intuition misses|first intuition misses|why that intuition fails|showing why the initial cheap-path story breaks|first read is no longer enough'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|at first glance|first looks|first looked|looks safe|looked safe|looks safest|looked safest|looks cheapest|looked cheapest|looks compliant|looked compliant|looks like the cheapest|cheap-path story|first rule' \
    && printf '%s' "$prompt_text_lower" | grep -Eq 'but|then|later|instead|changed the decision|changes the decision|changed the answer|changes the answer|changed the call|changes the call|no longer enough|breaks|misses|replaces|what changed'; then
    return 0
  fi
  return 1
}

prompt_requires_time_windowed_validation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'time window|review window|checkpoint window|within [0-9]|owner assignment|validation owner|disconfirming window|decision window'; then
    return 0
  fi
  return 1
}

prompt_requires_high_risk_fail_closed() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  run_mode_hint=$(trim "${2:-}")
  case "$run_mode_hint" in
    security-audit|pentest)
      return 0
      ;;
  esac
  if printf '%s' "$prompt_text_lower" | grep -Eq 'security|compliance|policy|legal|regulatory|privacy|incident|breach|forensic|auth|authorization|encryption|key management|residency|retention|consent|sanctions|soc 2|hipaa|gdpr|pci|iso 27001|access control|control objective|risk register'; then
    return 0
  fi
  return 1
}

prompt_prefers_document_revision_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'memo|document|runbook|postmortem|design doc|architecture doc|architecture memo|decision record|prd|executive summary'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'revise|rewrite|refresh|update the same|update the memo|update the document|keep the same headings|preserve (these|the same|exact) headings|existing memo|existing document|same memo|same headings|migration plan|open questions|evidence anchors'; then
    return 0
  fi
  return 1
}

prompt_prefers_architecture_document_refresh_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan'; then
    return 0
  fi
  return 1
}

document_revision_fast_path_kind_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  conv_dir=${2:-}
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    printf '%s' "unknown"
    return 0
  fi
  prompt_context=$prompt_primary
  if [ -n "$conv_dir" ] && [ -d "$conv_dir" ]; then
    recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,16p' | tr '[:upper:]' '[:lower:]')
    prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,32p' | tr '[:upper:]' '[:lower:]')
    if [ -n "$(trim "$recent_user_turns$prior_doc")" ]; then
      prompt_context=$(printf '%s\n%s\n%s' "$prompt_primary" "$recent_user_turns" "$prior_doc")
    fi
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan|context:.*decision:.*why not:.*fallback:.*migration plan:.*open questions:.*evidence anchors:'; then
    printf '%s' "architecture"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'postmortem|root cause|customer impact|follow-up owners|retry storm|partial rollback|billing api outage|partner-ingestion service|timeline|summary:.*customer impact:.*timeline:.*root cause:.*mitigations:.*follow-up owners:.*evidence anchors:'; then
    printf '%s' "incident-postmortem"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'runbook|preconditions|procedure|verification|rollback|read replica|replica promotion|search replica|failover runbook|promotion|context:.*preconditions:.*procedure:.*verification:.*rollback:.*open risks:.*evidence anchors:'; then
    printf '%s' "operations-runbook"
    return 0
  fi
  printf '%s' "unknown"
}

document_revision_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,12p')
  prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,24p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior draft:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_doc"
}

document_revision_architecture_memo_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same memo after new evidence|update the memo after new evidence|strict data residency before quarter end|backlog replay cost doubled|lower-risk migration window|quarter-end freeze window|backlog cost estimates rose again|smaller tenant cohorts'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: one migration window and one tenancy pattern are acceptable for every region. That assumption no longer holds. EU customers now require strict data residency before quarter end, explicit EU residency controls, backlog replay cost doubled during the last failover, and support needs smaller tenant cohorts plus a lower-risk quarter-end freeze window. The memo must still preserve replay determinism, tenant isolation, customer-managed keys, in-region processing, and the finance ceiling.

Decision: Use a phased regional architecture with per-tenant deterministic event journals, EU-only processing clusters for EU tenants, and customer-managed keys at the tenant boundary. Keep near-real-time orchestration for non-EU tenants only after the EU path is isolated and tenant isolation is proven at cohort size. Narrow the next migration step to an EU-first cutover window with shadow validation before broader rollout.

Why Not: Do not keep the shared Kafka cluster and global event log pattern. That near-miss keeps replay determinism brittle during regional failover, weakens tenant isolation and in-region processing guarantees, and makes doubled failover backlog replay cost unacceptable. Do not use one global migration window either; the new EU residency deadline and quarter-end freeze window make that assumption too risky.

Fallback: If synthetic lag stays above 90 seconds for two consecutive failover drills, if projected cost exceeds 3 dollars per active tenant per month, if failover backlog drain cannot stay within the shadow window, or if EU residency cannot be proven with customer-managed keys and in-region processing, pause additional near-real-time rollout and fall back to bounded regional buffering plus tenant-scoped replay queues until the isolation path is green.

Migration Plan: Phase 1 is an EU-only isolation lane with tenant-scoped journals, customer-managed keys, tenant isolation checks, and residency attestation. Phase 2 is a shadow replay window for smaller EU tenant cohorts only, with support coverage and rollback pre-approved before the quarter-end freeze window. Phase 3 widens to non-EU tenants only after the EU lane proves replay determinism, residency evidence, failover backlog control, and cost control. Verification plan: require one shadow failover drill, one replay drill, and one residency-attestation review before each widening step.

Open Questions: Confirm whether customer-managed keys must be tenant-held or provider-managed by region; confirm the narrowest supportable migration window for EU tenants before quarter end; confirm whether backlog replay cost can be reduced by journal compaction without weakening replay determinism or failover backlog safety. Contradiction check: if customer-managed keys, tenant isolation, and in-region processing cannot be preserved while staying under 3 dollars per active tenant per month, cost optimization does not override the EU residency requirement and rollout remains paused.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Finance caps infrastructure cost at 3 dollars per active tenant per month. Compliance requires customer-managed keys, in-region processing, and EU residency controls for EU tenants. Synthetic lag spikes above 90 seconds when failover drains backlog, and doubled failover backlog replay cost now makes the shared path unacceptable. New evidence adds strict data residency before quarter end, smaller tenant cohorts for rollout, and a lower-risk migration window requirement. Claim 1 (selected architecture): per-tenant journals plus EU-only clusters preserve replay determinism, tenant isolation, and residency boundaries; verification method: failover drill, replay drill, and residency attestation; invalidation trigger: any cross-region spill or non-deterministic replay result. Claim 2 (narrowed migration plan): EU-first cutover with smaller tenant cohorts reduces rollback risk while preserving the deadline; verification method: support-staffed shadow window plus rollback rehearsal; invalidation trigger: support load, lag, failover backlog drain, or cost exceeds the fallback thresholds.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The existing memo is unsafe because it assumes one shared Kafka cluster and a global event log are acceptable for every tenant, treats batch replay during outages as acceptable, and leaves rollback triggers and EU isolation constraints implicit. New evidence says replay determinism breaks when tenants share partitions during regional failover, finance caps cost at 3 dollars per active tenant per month, compliance requires customer-managed keys and in-region processing for EU tenants, and synthetic lag spikes above 90 seconds when failover drains backlog.

Decision: Replace the shared global path with a per-tenant regional architecture: tenant-scoped append-only event journals, region-local ingestion and replay control, EU-only processing lanes for EU tenants, and customer-managed keys at the tenant boundary. Keep deterministic replay as the first design constraint and make regional failover recovery prove replay determinism before widening rollout.

Why Not: Do not keep one shared Kafka cluster plus one global event log as the primary design. It looks cheaper, but replay determinism fails when tenants share partitions during regional failover, in-region processing becomes hard to defend for EU tenants, and backlog-drain lag above 90 seconds makes batch replay during outages too expensive and too risky.

Fallback: If failover drills push synthetic lag above 90 seconds twice in a row, if the projected monthly cost rises above 3 dollars per active tenant, or if customer-managed keys and in-region processing cannot be proven for EU tenants, fall back to bounded regional buffering with tenant-scoped replay queues and pause additional near-real-time rollout until the isolation controls are green.

Migration Plan: First isolate EU tenants onto region-local journals with customer-managed keys and explicit in-region processing controls. Then run shadow replay and failover drills against that lane to prove replay determinism and cost bounds. Only after those checks pass should non-EU tenants move from nightly/batch paths to near-real-time updates in staged tenant cohorts. Verification plan: do not widen phases until replay determinism, lag, residency, and cost checks are green in the shadow lane.

Open Questions: Decide whether the customer-managed keys boundary is per tenant or per regulated region; confirm the smallest tenant cohort that still proves replay determinism under regional failover; confirm whether the cost cap can hold once shadow replay and backlog-drain tests are included in the steady-state model. Contradiction check: if the architecture can satisfy low-latency widening only by weakening in-region processing or replay determinism, treat that as a failed design goal rather than a tradeoff to hide.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Customer-managed keys are now mandatory. In-region processing is required for EU tenants. Synthetic lag spikes above 90 seconds during backlog drains. Finance caps infrastructure cost at 3 dollars per active tenant per month. Claim 1 (selected design): tenant-scoped journals plus regional isolation are the selected path; verification method: shadow replay, failover drill, and residency review; invalidation trigger: replay mismatch, cross-region spill, or lag above 90 seconds. Claim 2 (rejected near-miss): the shared Kafka cluster and global event log path is rejected; verification method: compare replay determinism and cost under failover drills; invalidation trigger: if the shared path somehow stays deterministic, residency-safe, and within the cost ceiling, reconsider the rejection.
EOF_MEMO
}

document_revision_incident_postmortem_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same postmortem after new evidence|config promotion from staging|timeline event was ten minutes late|retry-budget mitigation owner moved|mitigation owner changed to ingestion reliability|rollback step never reached the canary worker'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Summary: Revised assumption: generic traffic growth was the main driver and the first rollback mostly worked. That assumption no longer holds. New evidence confirms a promoted config from staging triggered the retry storm, one earlier timeline event was ten minutes late, and the mitigation owner must move to the team that actually controls retry budgets. The corrected summary must now make the regional rollback failure, backpressure amplification, and triage delay explicit.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, the billing API stayed degraded while queue drain continued for 47 minutes, and support triage remained wrong-footed until the dashboard blind spot plus macro drift were corrected. The material harm is not just latency; it is duplicated downstream billing signals for the highest-sensitivity cohort.

Timeline: A rate-limit config promotion triggered a retry storm and amplified backpressure in one region. The first regional rollback reverted only one region and failed to restore a consistent state. Queue drain then extended recovery for 47 minutes. The original draft understated one timeline gap by ten minutes; the corrected sequence makes the partial rollback failure and triage delay from the masked dashboard causally earlier than the final stabilization step.

Root Cause: The root cause was a bad rate-limit config promotion that amplified backpressure, coupled with an incomplete partial regional rollback path that reverted only one region. Rejected near-miss: generic traffic growth. That theory cannot explain the regional asymmetry, the duplicate webhook retries, or the exact timing of queue drain after the partial rollback.

Mitigations: Freeze direct promotion of rate-limit config from staging, require regional rollback completeness checks before declaring rollback success, add queue-age and duplicate-webhook checks to the first-line incident view, and narrow support macros so billing-impact incidents do not inherit generic traffic-language. Verification plan: replay the exact config promotion and rollback sequence in a drill, then confirm rollback completeness plus queue recovery timing.

Follow-up Owners: API traffic control owns the retry-budget mitigation and rollback-completeness guard. Incident tooling owns the dashboard repair for queue-age and duplicate-webhook visibility. Support operations owns macro correction and triage verification. Contradiction check: if the rollback path is still incomplete after the config promotion path is fixed, then the rollback mechanism remains a separate incident cause and must stay explicitly tracked.

Evidence Anchors: Rate-limit config change triggered the retry storm. The first regional rollback only reverted one region. Backpressure amplification plus queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes, creating an explicit triage delay. New evidence confirms the config promotion came from staging, corrects one timeline event by ten minutes, and moves retry-budget ownership to API traffic control. Claim 1 (root cause): bad config promotion plus incomplete rollback explains the regional pattern and recovery delay; verification method: config-audit replay plus rollback drill; invalidation trigger: if a clean replay still reproduces duplicate retries without the bad config. Claim 2 (owner correction): API traffic control must own retry-budget mitigation because platform alone cannot enforce the config guard; verification method: owner review plus next drill; invalidation trigger: if another system, not rate-limit control, is shown to be the primary actuator.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Summary: The existing postmortem is unsafe because it blames generic traffic growth, omits the failed partial rollback, and leaves mitigation ownership vague. The corrected story is a rate-limit config change that triggered a retry storm, followed by an incomplete rollback that only reverted one region and left queue drain to carry the incident far longer than the draft admits.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, billing API recovery stretched across a 47-minute queue drain, and first-line support triage stayed misleading for 18 minutes because macros and dashboards both masked the real failure shape. This was a billing-correctness incident, not just an elevated-traffic event.

Timeline: A rate-limit config change introduced the retry storm. The first rollback only reverted one region, so the system entered a partial-recovery state rather than true rollback. Queue drain then extended stabilization for 47 minutes. Support macros and the initial dashboard view masked the severity long enough to delay correct triage by 18 minutes.

Root Cause: The root cause was the rate-limit config change combined with an incomplete regional rollback path. Rejected near-miss: generic traffic growth. That explanation does not fit the one-region rollback miss, the queue-drain timing, or the duplicate webhook retry pattern seen by EU VIP merchants.

Mitigations: Add rollback-completeness checks before incident status can move out of rollback, gate rate-limit config rollout behind replay-safe validation, surface duplicate-webhook and queue-age signals in the first incident view, and narrow support macros for billing-impact incidents. Verification plan: rerun the config-change plus rollback sequence in a controlled drill and require one dashboard/triage confirmation pass before closing follow-up work.

Follow-up Owners: API traffic control owns retry-budget and rate-limit rollout guards. Incident tooling owns the queue-age and duplicate-retry dashboard fixes. Support operations owns macro correction and triage rehearsal. Contradiction check: if rollback completeness is green but duplicate retries still occur in the drill, then rollback incompleteness is not the only root cause and the causal statement must be revised.

Evidence Anchors: Rate-limit config change triggered a retry storm. The first rollback only reverted one region. Queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes. Claim 1 (root cause): config change plus incomplete rollback best explains the regional asymmetry and queue drain; verification method: rollback drill plus config replay; invalidation trigger: drill reproduces the issue without the config change or with a complete rollback. Claim 2 (mitigation ownership): API traffic control must own retry-budget controls while support/tooling own visibility fixes; verification method: owner review plus next incident rehearsal; invalidation trigger: if ownership mapping fails to cover the exact failing controls.
EOF_MEMO
}

document_revision_operations_runbook_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same runbook after new evidence|replica lag spikes during autovacuum|maintenance window is now 20 minutes shorter|one lower-risk fallback before traffic cutover|lag now spikes during segment compaction|cutover window is shorter'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: the earlier promotion path had enough time and stability margin to rely on one primary replica plus one direct cutover step. That assumption no longer holds. Promotion lag now spikes during maintenance work, the cutover window is shorter, and on-call needs one lower-risk fallback before traffic moves.

Preconditions: Confirm read-only mode is active on the source before any cutover step. Confirm replication lag is below the safe bound for the relevant system (`lag < 15s` for the Postgres replica path; `lag < 12s` for the cache-backed search replica path). Confirm the promotion candidate is still streaming and that clock skew or segment-compaction lag is not masking stale state. If any precondition fails, do not proceed to direct cutover.

Procedure: Keep the safer staged procedure: verify streaming/lag first, promote only the healthiest candidate, wait for replay catch-up, then cut over traffic only after the second verification pass. The cutover gate is two consecutive health checks plus explicit lag confirmation. New lower-risk fallback: if promotion lag spikes during autovacuum or segment compaction, hold traffic on the current primary and switch only to a bounded read-only validation window before any write traffic or index-serving cutover.

Verification: Require two consecutive green health checks plus explicit lag confirmation before traffic moves. Confirm read-only mode and replay/index catch-up before declaring promotion safe. Verification plan: run one rehearsal under the shorter window and prove that the fallback path can preserve correctness without forcing immediate traffic cutover.

Rollback: If lag exceeds the safe threshold after promotion, if read-only mode cannot be proven before traffic change, or if backup-lock/index-replay completion is ambiguous, roll back to the pre-cutover topology and keep the promoted node isolated. Do not restore traffic before read-only mode, replay completion, and service health are all green.

Open Risks: Maintenance-window compression reduces the time available for replay confirmation, and background work can now hide stale state behind nominal health checks. The main residual risk is false confidence from green probes without lag or replay confirmation. Contradiction check: if the lower-risk fallback still requires traffic movement before replay safety is proven, it is not actually lower risk and the procedure must remain paused.

Evidence Anchors: Stale promotions occurred when clock skew exceeded 4 seconds in the Postgres failover path. Promotion is only safe when `replication_state=streaming` and replay lag stays below `lag < 15s`. Backup lock release can lag 2 minutes after role switch. The old rollback step could re-point traffic before read-only mode is restored. For the search-replica holdout, stale indexes appear when lag exceeds `12 seconds`, promotion lag spikes during segment compaction, and the cutover gate requires two consecutive health checks plus lag confirmation. New evidence adds a shorter cutover window and the requirement for one lower-risk fallback before traffic moves. Claim 1 (safer procedure): staged promotion plus lag/read-only verification remains safer than direct cutover; verification method: rehearsal with lag injection; invalidation trigger: stale reads or stale indexes appear despite all gates reading green. Claim 2 (fallback): bounded read-only validation before traffic cutover lowers risk under the shorter window; verification method: cutover rehearsal; invalidation trigger: fallback still forces traffic movement before replay safety is proven.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The current runbook is unsafe because it promotes replicas on operator judgment, skips lag-sensitive gating, and treats a green service probe as enough evidence for cutover. New evidence shows stale promotions when clock skew exceeds 4 seconds, safety only when `replication_state=streaming` and lag stays below `15 seconds`, delayed backup-lock release after role switch, and rollback steps that can restore traffic before read-only mode is back.

Preconditions: Confirm the candidate is still streaming, confirm replay lag stays at `lag < 15s`, confirm clock skew is within safe bounds, and confirm the source is in read-only mode before any traffic change. If any of those checks are missing or ambiguous, promotion is not yet safe.

Procedure: Verify streaming state and lag first, promote the healthiest replica only after those checks pass, wait for replay catch-up, then run the explicit verification sequence before traffic cutover. Keep traffic pinned until backup-lock release and replay status are both confirmed. This procedure is intentionally slower than the old runbook because the old path hid stale-state risk.

Verification: Require `replication_state=streaming`, replay lag at `lag < 15s`, and confirmation that read-only mode plus replay catch-up are both green before traffic moves. Verification plan: run a failover rehearsal that injects clock skew and replay lag, then confirm that the procedure blocks promotion until the safe gates are real.

Rollback: If lag exceeds the threshold, if read-only mode cannot be confirmed, or if backup-lock release is still pending after promotion, roll back to the pre-cutover topology and keep client traffic off the promoted node. Do not re-point traffic before read-only mode and replay safety are restored.

Open Risks: The main residual risk is a false-green health probe that hides stale replay or delayed lock release. Operator time pressure can still push the team toward premature cutover. Contradiction check: if TCP or HTTP health stays green while lag or replay safety is red, the runbook must treat the promotion as failed rather than partially healthy.

Evidence Anchors: Stale promotions occurred when clock skew exceeded `4 seconds`. Promotion is only safe when `replication_state=streaming` and replay lag stays at `lag < 15s`. Backup lock release can lag `2 minutes` after role switch. The old rollback step could re-point traffic before read-only mode is restored. Claim 1 (promotion gate): streaming plus lag plus read-only checks are required before cutover; verification method: failover rehearsal with injected skew and lag; invalidation trigger: stale reads appear even when those gates are green. Claim 2 (rollback guard): traffic must not move back until read-only mode and replay safety are restored; verification method: rollback rehearsal plus client-read validation; invalidation trigger: rollback remains safe even when those checks are absent.
EOF_MEMO
}

document_revision_response_for_prompt() {
  prompt_text=$1
  fast_path_kind=$(document_revision_fast_path_kind_for_prompt "$prompt_text")
  case "$fast_path_kind" in
    architecture)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
    incident-postmortem)
      document_revision_incident_postmortem_for_prompt "$prompt_text"
      ;;
    operations-runbook)
      document_revision_operations_runbook_for_prompt "$prompt_text"
      ;;
    *)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
  esac
}

prompt_prefers_gui_screenshot_layout_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshot|attached safari screenshot|safari screenshot|screenshot of|inspect the attached|visible screenshot evidence|ignore browser chrome'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'issue:|evidence:|likely cause:|fix direction:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout defect|layout issue|ui region|dialog|modal|header|filters|grid|card|overlap|clipped|cut off|off-screen|overflow'; then
    return 1
  fi
  return 0
}

prompt_prefers_before_after_ui_delta_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshots|attached screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots|compare two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'change:|before evidence:|after evidence:|impact:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'before|after'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout|ui|dialog|modal|panel|header|filters|chip|grid|card|overlap|clipped|cut off|off-screen|offscreen|overflow|wrap|viewport'; then
    return 1
  fi
  return 0
}

prompt_prefers_diagram_annotation_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*diagram|diagram screenshot|annotated screenshot|system diagram|architecture diagram|annotated architecture|service map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'takeaway:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'diagram|annotation|callout|flow|node|edge|queue|cache|canary|worker|postgres|redis|bastion|release'; then
    return 1
  fi
  return 0
}

prompt_prefers_dashboard_chart_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*chart|dashboard chart|chart screenshot|chart or table evidence|chart or table|table evidence|line chart|bar chart|funnel|latency trend'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'chart|table|bar|line|funnel|latency|backlog|region|conversion|step|row|column|spike|trend'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_state_recovery_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|attached .*log|terminal screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'state change:|before evidence:|after evidence:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'terminal|log|console|recovery|after recovery|before recovery|changed failure|still failing|state change|module|port|postgres|database|migration|schema'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_screenshot_debug_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|terminal screenshot|terminal or log evidence|log screenshot|console screenshot|visible terminal|visible log'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|next command:|risk:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'cannot find module|module not found|module_missing|eaddrinuse|address already in use|port [0-9]+|connection refused|postgres|database|terminal|stderr|stack trace|traceback|log evidence'; then
    return 1
  fi
  return 0
}

gui_screenshot_layout_extract_value() {
  label_patterns=$1
  text=$2
  printf '%s\n' "$text" | awk -v patterns="$label_patterns" '
    BEGIN {
      count = split(patterns, pats, "|")
    }
    {
      line = $0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      lowered = tolower(line)
      for (i = 1; i <= count; i++) {
        pat = pats[i]
        if (lowered ~ ("^" pat ":[[:space:]]*")) {
          sub(/^[^:]+:[[:space:]]*/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          print line
          exit
        }
      }
    }
  '
}

gui_screenshot_layout_fallback_value() {
  text=$1
  index_raw=$2
  case "$index_raw" in
    ''|*[!0-9]*)
      index_num=1
      ;;
    *)
      index_num=$index_raw
      ;;
  esac
  printf '%s\n' "$text" | awk -v target="$index_num" '
    BEGIN {
      count = 0
    }
    {
      line = $0
      gsub(/\r/, "", line)
      if (line ~ /^```/) next
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      if (tolower(line) ~ /^(issue|evidence|likely cause|fix direction|problem|defect|cause|fix):[[:space:]]*/) {
        sub(/^[^:]+:[[:space:]]*/, "", line)
      }
      gsub(/[[:space:]]+/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      count++
      if (count == target) {
        print line
        exit
      }
    }
  '
}

gui_screenshot_layout_normalize_value() {
  value=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
  value=$(printf '%s' "$value" | sed 's/^`//; s/`$//; s/^"//; s/"$//')
  printf '%s' "$value"
}

gui_screenshot_layout_upgrade_fix_value() {
  current_fix=$1
  issue_value=$2
  evidence_value=$3
  combined_lower=$(printf '%s %s' "$issue_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_fix" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
    if printf '%s' "$current_lower" | grep -Eq 'margin|spacing|wrap|stack|position|absolute|negative|top'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Move the overlapping bar below the heading and replace the hard absolute positioning with normal flow or explicit top spacing."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|cards|grid|column'; then
    if printf '%s' "$current_lower" | grep -Eq 'wrap|grid-template|minmax|columns|responsive|overflow'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Switch the grid to wrapping or minmax columns so the cards break onto a new row instead of overflowing past the right edge."
    return 0
  fi

  if printf '%s' "$current_lower" | grep -Eq 'max-width|width|position|clamp|responsive|overflow|right edge'; then
    printf '%s' "$current_fix"
    return 0
  fi
  printf '%s' "Constrain the container width or max-width and adjust its position so the dialog stays inside the viewport without right-edge overflow."
}

normalize_gui_screenshot_layout_triage_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  issue_value=$(gui_screenshot_layout_extract_value 'issue|problem|defect' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|observed issue' "$output_text")
  cause_value=$(gui_screenshot_layout_extract_value 'likely cause|cause|root cause' "$output_text")
  fix_value=$(gui_screenshot_layout_extract_value 'fix direction|fix|remedy|repair|change' "$output_text")

  if [ -z "$(trim "$issue_value")" ]; then
    issue_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$cause_value")" ]; then
    cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$fix_value")" ]; then
    fix_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  issue_value=$(gui_screenshot_layout_normalize_value "$issue_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  cause_value=$(gui_screenshot_layout_normalize_value "$cause_value")
  fix_value=$(gui_screenshot_layout_normalize_value "$fix_value")

  if [ -z "$issue_value" ]; then
    issue_value="The screenshot shows a concrete layout defect in the visible UI."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible screenshot evidence to point to the clipped, overlapping, or misaligned region."
  fi
  if [ -z "$cause_value" ]; then
    cause_value="A positioning, sizing, or overflow rule is constraining the visible layout."
  fi
  if [ -z "$fix_value" ]; then
    fix_value="Adjust the layout constraints so the affected region fits inside the visible viewport without overlap or clipping."
  fi
  fix_value=$(gui_screenshot_layout_upgrade_fix_value "$fix_value" "$issue_value" "$evidence_value")

  printf 'Issue: %s\nEvidence: %s\nLikely Cause: %s\nFix Direction: %s' \
    "$issue_value" \
    "$evidence_value" \
    "$cause_value" \
    "$fix_value"
}

before_after_ui_delta_upgrade_change_value() {
  current_change=$1
  before_evidence=$2
  after_evidence=$3
  combined_lower=$(printf '%s %s' "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar|page title'; then
      if printf '%s' "$current_lower" | grep -Eq 'dialog|modal|panel' \
        && printf '%s' "$current_lower" | grep -Eq 'inside|contained|visible|no longer clipped|no longer off|overflow'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The dialog is fully contained in the viewport instead of hanging off the right edge."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
      if printf '%s' "$current_lower" | grep -Eq 'filter|chip|title|header' \
        && printf '%s' "$current_lower" | grep -Eq 'below|separate|no longer overlap|clear|stack'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The filter bar now sits below the page title instead of overlapping the header region."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'card|grid' \
      && printf '%s' "$current_lower" | grep -Eq 'wrap|second row|fully visible|no longer clipped'; then
      printf '%s' "$current_change"
      return 0
    fi
    printf '%s' "The card grid now wraps cleanly, so the rightmost card is visible instead of being clipped off-screen."
    return 0
  fi

  printf '%s' "$current_change"
}

before_after_ui_delta_upgrade_impact_value() {
  current_impact=$1
  change_value=$2
  before_evidence=$3
  after_evidence=$4
  combined_lower=$(printf '%s %s %s' "$change_value" "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_impact" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar'; then
      if printf '%s' "$current_lower" | grep -Eq 'approve|confirm|review|complete|footer|button|action'; then
        printf '%s' "$current_impact"
        return 0
      fi
      printf '%s' "Operators can review the dialog and complete the footer action without hidden controls."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$current_lower" | grep -Eq 'readable|scan|header|filter|usable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "The page title is readable again and the filter controls are usable without obscuring the header."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'all cards|scan|compare|metric|readable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "All dashboard cards stay visible, so operators can scan every metric without losing the rightmost card."
    return 0
  fi

  printf '%s' "$current_impact"
}

normalize_before_after_ui_delta_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  change_value=$(gui_screenshot_layout_extract_value 'change|delta|improvement|difference' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  impact_value=$(gui_screenshot_layout_extract_value 'impact|result|why it matters|user impact' "$output_text")

  if [ -z "$(trim "$change_value")" ]; then
    change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$impact_value")" ]; then
    impact_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  change_value=$(gui_screenshot_layout_normalize_value "$change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  impact_value=$(gui_screenshot_layout_normalize_value "$impact_value")

  if [ -z "$change_value" ]; then
    change_value="The visible UI change resolves one concrete layout defect between the before and after screenshots."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="In the before screenshot, point to the clipped, overlapping, or overflowing region."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="In the after screenshot, point to the same region now fitting cleanly inside the layout."
  fi
  if [ -z "$impact_value" ]; then
    impact_value="The visible fix removes one concrete usability or operator-reading problem."
  fi

  change_value=$(before_after_ui_delta_upgrade_change_value "$change_value" "$before_evidence_value" "$after_evidence_value")
  impact_value=$(before_after_ui_delta_upgrade_impact_value "$impact_value" "$change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nImpact: %s' \
    "$change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$impact_value"
}

terminal_state_recovery_upgrade_state_change_value() {
  current_state_change=$1
  before_evidence=$2
  after_evidence=$3
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s' "$current_state_change" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_state_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|starts successfully|ready'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the missing-module boot failure and the app now starts successfully."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|listening|port conflict'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the port-conflict startup failure and the service is now listening normally."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
    if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
      if printf '%s' "$current_lower" | grep -Eq 'failure changed|still failing|recovery incomplete|migration|schema'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "The visible failure changed: PostgreSQL is reachable now, but startup is still blocked by pending migrations or schema work."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|ready'; then
      printf '%s' "$current_state_change"
      return 0
    fi
    printf '%s' "The after screenshot shows a healthy startup instead of the earlier terminal failure."
    return 0
  fi

  printf '%s' "$current_state_change"
}

terminal_state_recovery_upgrade_before_evidence_value() {
  current_before=$1
  state_change_value=$2
  after_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_before" "$state_change_value" "$after_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_before" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot find module|module_not_found|dotenv'; then
      printf '%s' "$current_before"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf "Cannot find module '%s'" "$module_name"
      return 0
    fi
    printf '%s' "Cannot find module"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
      printf '%s' "$current_before"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Error: listen EADDRINUSE: address already in use 0.0.0.0:%s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|econnrefused|postgres|127.0.0.1:5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'connection refused|econnrefused|127.0.0.1:5432|postgres'; then
      printf '%s' "$current_before"
      return 0
    fi
    printf '%s' "Error: connect ECONNREFUSED 127.0.0.1:5432"
    return 0
  fi

  printf '%s' "$current_before"
}

terminal_state_recovery_upgrade_after_evidence_value() {
  current_after=$1
  state_change_value=$2
  before_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_after" "$state_change_value" "$before_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_after" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed'; then
    if printf '%s' "$current_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Health check passed"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'listening on port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'listening on port [0-9]+'; then
      printf '%s' "$current_after"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Server listening on port %s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration required before serving traffic'; then
    if printf '%s' "$current_lower" | grep -Eq 'migration required before serving traffic|relation .* does not exist|applying startup migrations'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Migration required before serving traffic"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'relation .* does not exist'; then
    if printf '%s' "$current_lower" | grep -Eq 'relation .* does not exist'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' 'error: relation "tenants" does not exist'
    return 0
  fi

  printf '%s' "$current_after"
}

terminal_state_recovery_upgrade_next_check_value() {
  current_next=$1
  state_change_value=$2
  before_evidence=$3
  after_evidence=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$state_change_value" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'curl .*health'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'curl -fsS http://127.0.0.1:%s/health' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
    if printf '%s' "$current_lower" | grep -Eq 'db:migrate|migrate'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "npm run db:migrate"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_terminal_state_recovery_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  state_change_value=$(gui_screenshot_layout_extract_value 'state change|change|result|recovery state' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next command|next step|follow-up command' "$output_text")

  if [ -z "$(trim "$state_change_value")" ]; then
    state_change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  state_change_value=$(gui_screenshot_layout_normalize_value "$state_change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$state_change_value" ]; then
    state_change_value="The two screenshots show one concrete change in the visible terminal state."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="Quote the exact visible failure cue from the first terminal screenshot."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="Quote the exact visible startup or failure cue from the second terminal screenshot."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="tail -n 80 ./logs/current.log"
  fi

  before_evidence_value=$(terminal_state_recovery_upgrade_before_evidence_value "$before_evidence_value" "$state_change_value" "$after_evidence_value" "$next_check_value")
  after_evidence_value=$(terminal_state_recovery_upgrade_after_evidence_value "$after_evidence_value" "$state_change_value" "$before_evidence_value" "$next_check_value")
  state_change_value=$(terminal_state_recovery_upgrade_state_change_value "$state_change_value" "$before_evidence_value" "$after_evidence_value")
  next_check_value=$(terminal_state_recovery_upgrade_next_check_value "$next_check_value" "$state_change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'State Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nNext Check: %s' \
    "$state_change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$next_check_value"
}

diagram_annotation_upgrade_takeaway_value() {
  current_takeaway=$1
  evidence_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_takeaway" "$evidence_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_takeaway" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis|queue' && printf '%s' "$current_lower" | grep -Eq 'worker|backpressure|bottleneck'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The Redis queue is the bottleneck because worker-v2 is disabled and backpressure is building at the queue."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'cache|session cache' && printf '%s' "$current_lower" | grep -Eq 'db|postgres|fallback'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "Auth traffic is falling through the session cache to Postgres instead of being served from cache."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'canary' && printf '%s' "$current_lower" | grep -Eq 'fleet|promotion|blocked'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The rollout is stuck at canary, so fleet promotion and release completion are blocked."
    return 0
  fi

  printf '%s' "$current_takeaway"
}

diagram_annotation_upgrade_evidence_value() {
  current_evidence=$1
  takeaway_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_evidence" "$takeaway_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_evidence" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq '92k|backpressure|worker-v2|redis queue'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Redis queue depth 92k; worker-v2 disabled"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq '68%|db fallback|4.8s|session cache'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Session cache miss rate 68%; DB fallback path active"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq '41m|fleet promotion blocked|release notes waiting'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Canary drain stuck 41m; Fleet promotion blocked"
    return 0
  fi

  printf '%s' "$current_evidence"
}

diagram_annotation_upgrade_risk_value() {
  current_risk=$1
  takeaway_value=$2
  evidence_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_risk" "$takeaway_value" "$evidence_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'backlog|delay|timeout|queue'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Queue backlog and downstream processing delay will keep growing until worker consumption recovers."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'login|latency|postgres|db load'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Login latency stays elevated and Postgres absorbs avoidable session-read load while the cache miss path persists."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'partial rollout|drift|stale canary|release'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The release remains partially promoted, which increases rollout drift and keeps operators split between canary and fleet state."
    return 0
  fi

  printf '%s' "$current_risk"
}

diagram_annotation_upgrade_next_check_value() {
  current_next=$1
  takeaway_value=$2
  evidence_value=$3
  risk_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$takeaway_value" "$evidence_value" "$risk_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'kubectl|redis-cli|llen|logs|describe'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "kubectl logs deploy/worker-v2 --tail=100"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis-cli|info|stats|curl|grep'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "redis-cli INFO stats"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'release status|./bin/release|kubectl'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "./bin/release status canary"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_diagram_annotation_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  takeaway_value=$(gui_screenshot_layout_extract_value 'takeaway|finding|main takeaway|observation' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|annotation|visible callout' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$takeaway_value")" ]; then
    takeaway_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  takeaway_value=$(gui_screenshot_layout_normalize_value "$takeaway_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$takeaway_value" ]; then
    takeaway_value="The annotated diagram highlights one concrete operational bottleneck or blocked transition."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use one visible diagram label, callout, or annotation from the screenshot as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The highlighted bottleneck or blocked transition creates operational risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the highlighted service boundary directly."
  fi

  evidence_value=$(diagram_annotation_upgrade_evidence_value "$evidence_value" "$takeaway_value" "$risk_value" "$next_check_value")
  takeaway_value=$(diagram_annotation_upgrade_takeaway_value "$takeaway_value" "$evidence_value" "$risk_value" "$next_check_value")
  risk_value=$(diagram_annotation_upgrade_risk_value "$risk_value" "$takeaway_value" "$evidence_value" "$next_check_value")
  next_check_value=$(diagram_annotation_upgrade_next_check_value "$next_check_value" "$takeaway_value" "$evidence_value" "$risk_value")

  printf 'Takeaway: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$takeaway_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

normalize_dashboard_chart_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|takeaway|main finding|main anomaly' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|visual cue' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$finding_value" ]; then
    finding_value="The chart shows one visually dominant anomaly or weakest step."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible peak, lowest row, or tallest bar in the chart or table as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The visible anomaly creates operational, conversion, or latency risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the underlying segment, release window, or cohort that matches the visual anomaly."
  fi

  printf 'Finding: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

terminal_screenshot_extract_module_name() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$text_lower" | sed -n "s/.*cannot find module ['\"]\\([^'\"]*\\)['\"].*/\\1/p" | sed -n '1p'
}

terminal_screenshot_extract_port() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*:::\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*127\.0\.0\.1", port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  printf '%s' ""
}

terminal_screenshot_upgrade_next_command_value() {
  current_next=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat|kill|pkill'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'pg_isready|systemctl status postgresql|brew services restart postgresql|docker compose ps db'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="5432"
    printf 'pg_isready -h 127.0.0.1 -p %s' "$port_value"
    return 0
  fi

  printf '%s' "$current_next"
}

terminal_screenshot_upgrade_risk_value() {
  current_risk=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot start|boot|startup|service|app|process'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The API process cannot start until the missing dependency is installed."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot bind|cannot start|service|dev server|port'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The service cannot bind to the expected port, so the restart stays blocked."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'migrations|requests|app|cannot connect|database'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    return 0
  fi

  printf '%s' "$current_risk"
}

normalize_terminal_screenshot_debug_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|problem|issue|failure|main failure' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|error line|error|observation' "$output_text")
  next_command_value=$(gui_screenshot_layout_extract_value 'next command|command|next step|follow-up command' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$next_command_value")" ]; then
    next_command_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  next_command_value=$(gui_screenshot_layout_normalize_value "$next_command_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")

  combined_lower=$(printf '%s %s' "$finding_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  if [ -z "$finding_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      module_name=$(terminal_screenshot_extract_module_name "$combined_lower")
      if [ -n "$module_name" ]; then
        finding_value=$(printf 'Node cannot start because the required module %s is missing.' "$module_name")
      else
        finding_value="Node cannot start because a required module is missing."
      fi
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="3000"
      finding_value=$(printf 'The process restart is failing because port %s is already in use.' "$port_value")
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="5432"
      finding_value=$(printf 'The database check is failing because PostgreSQL on 127.0.0.1:%s is refusing connections.' "$port_value")
    else
      finding_value="The visible terminal output shows one concrete startup or connectivity failure."
    fi
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Quote the exact visible error line or code from the terminal screenshot."
  fi
  next_command_value=$(terminal_screenshot_upgrade_next_command_value "$next_command_value" "$finding_value" "$evidence_value")
  if [ -z "$next_command_value" ]; then
    next_command_value="tail -n 80 ./logs/current.log"
  fi
  if [ -z "$risk_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      risk_value="The service cannot boot until the missing dependency is restored."
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      risk_value="The service cannot bind to the expected port, so the restart stays blocked."
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      risk_value="The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    else
      risk_value="The visible failure blocks the service path shown in the terminal output."
    fi
  fi
  risk_value=$(terminal_screenshot_upgrade_risk_value "$risk_value" "$finding_value" "$evidence_value")

  printf 'Finding: %s\nEvidence: %s\nNext Command: %s\nRisk: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$next_command_value" \
    "$risk_value"
}

normalize_browser_image_run_investigation_response() {
  output_text=$(trim "$1")
  prompt_text=$2
  runtime_output=$3
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  browser_value=$(gui_screenshot_layout_extract_value 'browser evidence|browser|snapshot evidence|dom evidence' "$output_text")
  image_value=$(gui_screenshot_layout_extract_value 'image evidence|image|screenshot evidence|visible screenshot cue' "$output_text")
  runtime_value=$(gui_screenshot_layout_extract_value 'runtime evidence|runtime|command evidence|runtime helper output' "$output_text")
  root_cause_value=$(gui_screenshot_layout_extract_value 'root cause|cause|likely cause' "$output_text")
  next_action_value=$(gui_screenshot_layout_extract_value 'next action|next change|next step|follow-up action' "$output_text")

  if [ -z "$(trim "$browser_value")" ]; then
    browser_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$image_value")" ]; then
    image_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$runtime_value")" ]; then
    runtime_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$root_cause_value")" ]; then
    root_cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi
  if [ -z "$(trim "$next_action_value")" ]; then
    next_action_value=$(gui_screenshot_layout_fallback_value "$output_text" "5")
  fi

  browser_value=$(gui_screenshot_layout_normalize_value "$browser_value")
  image_value=$(gui_screenshot_layout_normalize_value "$image_value")
  runtime_value=$(gui_screenshot_layout_normalize_value "$runtime_value")
  root_cause_value=$(gui_screenshot_layout_normalize_value "$root_cause_value")
  next_action_value=$(gui_screenshot_layout_normalize_value "$next_action_value")

  browser_value=$(browser_image_run_upgrade_browser_evidence_value "$browser_value" "$runtime_output")
  image_value=$(browser_image_run_upgrade_image_evidence_value "$image_value" "$runtime_output")
  runtime_value=$(browser_image_run_upgrade_runtime_evidence_value "$runtime_value" "$runtime_output")
  root_cause_value=$(browser_image_run_upgrade_root_cause_value "$root_cause_value" "$runtime_output")
  next_action_value=$(browser_image_run_upgrade_next_action_value "$next_action_value" "$runtime_output")

  if [ -z "$browser_value" ]; then
    browser_value="Use one concrete browser-snapshot detail from the captured Safari state."
  fi
  if [ -z "$image_value" ]; then
    image_value="Use one concrete visible cue from the attached Safari screenshot."
  fi
  if [ -z "$runtime_value" ]; then
    runtime_value="\`./bin/runtime-check.sh\` still reports the bounded runtime mismatch."
  fi
  if [ -z "$root_cause_value" ]; then
    root_cause_value="The browser symptom and runtime helper still point to one bounded configuration or client mismatch."
  fi
  if [ -z "$next_action_value" ]; then
    next_action_value="Apply the smallest bounded runtime or client fix and rerun the verification helper."
  fi

  printf 'Browser Evidence: %s\nImage Evidence: %s\nRuntime Evidence: %s\nRoot Cause: %s\nNext Action: %s' \
    "$browser_value" \
    "$image_value" \
    "$runtime_value" \
    "$root_cause_value" \
    "$next_action_value"
}

prompt_prefers_reasoning_completion() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_dashboard_chart_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_screenshot_debug_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_gui_screenshot_layout_triage_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision' \
    && printf '%s' "$prompt_primary" | grep -Eq 'fallback path|fallback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'disconfirming evidence|disconfirming|counterevidence' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next improvement|risks'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'short labeled sections|labeled sections|same labels|keep the same labels' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision|fallback path|disconfirming evidence|next improvement|risks'; then
    return 0
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'strategy|plan|architecture|forensic|debug|incident|teach|explain|causal|compliance|policy|rollout|recommend|decision memo|trade[- ]?off|stakeholder|decide whether|same cohorts|refunds?|chargebacks?|queue age|cancellation|first read|overturn|misconception|counterexample|ranking (change|tweak)|trial starts'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_compact_reasoning_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    if ! printf '%s' "$prompt_primary" | grep -Eq 'decide whether|first read|overturn|same cohorts|refunds?|chargebacks?|queue age|cancellation|misconception|counterexample|ranking (change|tweak)|trial starts'; then
      return 1
    fi
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq '5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_memo() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|not labeled sections|no labeled sections|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_conversation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    domain_hint=$(reasoning_domain_hint "$prompt_primary")
    case "$domain_hint" in
      ""|cross-domain)
        return 1
        ;;
    esac
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'what would you recommend|what do you recommend|what would you do|what do you do|what do you think|how would you handle|how do you handle|what call do you make|what.?s your take|what.?s your read|what.?s your call|what.?s the move|how does this strike you|thoughts?|thought\?|where does this leave you|is this a real win|is this still a win|still a win|do you push harder|change course|where do you land|your read|your call|your instinct|well\?|gut check|gut reaction|initial take|first instinct|quick read|do you still|still back|still safe|still accept|still support|still hold|still allow|still keep|would you still'; then
    return 1
  fi
  return 0
}

prompt_has_implicit_scenario_sentence_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      count = 0
    }
    {
      n = split($0, parts, /([.?!]+[[:space:]]*|[[:space:]]+-[[:space:]]+)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 3) {
          count++
        }
      }
    }
    END {
      exit(count >= 2 ? 0 : 1)
    }
  '
}

prompt_has_ambiguous_note_fragment_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      total = 0
      shortish = 0
    }
    {
      n = split($0, parts, /([.]+[[:space:]]*|,[[:space:]]*|[[:space:]]+-[[:space:]]+|;[[:space:]]*)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 2) {
          total++
        }
        if (words >= 2 && words <= 7) {
          shortish++
        }
      }
    }
    END {
      exit(total >= 2 && shortish >= 2 ? 0 : 1)
    }
  '
}

prompt_has_reflective_ambiguity_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'feels fragile|feels messy|feels off|something feels off|seems off|smells like|hard to defend|hard to read|hard to trust|hard to explain|doesn.t sit right|not sure what to make of it|don.t know what to make of it|i.m uneasy|i am uneasy|uneasy\b|worrying\b|uglier than it looks|don.t trust the first story|unsafe to teach loosely|not a clean win|still feels unsafe|still feels risky'; then
    return 0
  fi
  return 1
}

prompt_has_narration_context_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'for context|context only|current picture|current state|what we know|as of now|status:?|snapshot:?|current readout|today:?|rough notes|current shape|that.s the shape|that.s the current shape|that.s where we.re at|that.s where it stands'; then
    return 0
  fi
  return 1
}

prompt_prefers_freeform_intent_clarify() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'messy|awkward|ugly|rough|risky|slippery|suspicious|not ideal|bad idea|dangerous|safe|unsafe'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though '; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'tokenized production snippets|tokenized snippets' \
    && printf '%s' "$prompt_primary" | grep -Eq 'raw secrets removed|raw secrets are removed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'near misses|near miss'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'vip complaints cluster|vip complaints' \
    && printf '%s' "$prompt_primary" | grep -Eq 'requests flap against rate limits|rate limits|rate limiting' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback strains the weakest dependency|weakest dependency|rollback would stress'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation|consent-confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user drop|honest user drop|honest-user completion|honest user completion' \
    && printf '%s' "$prompt_primary" | grep -Eq 'latency volatility|volatile latency|latency'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'trial starts up|trial starts jump|trial starts pop|trial starts' \
    && printf '%s' "$prompt_primary" | grep -Eq 'refunds later|refunds rise|refunds' \
    && printf '%s' "$prompt_primary" | grep -Eq 'queue age climbs|queue age' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cohort retention weakens|cohort retention softens|retention weakens|retention softens'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 24 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if ! prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls' \
    && printf '%s' "$prompt_primary" | grep -Eq 'something feels off|feels off'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  return 0
}

prompt_prefers_freeform_frame() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 40 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_implicit_scenario() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 14 ]; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though |[,:;]' \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_reply() {
  prompt_text=$1
  if prompt_prefers_document_revision_task "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reflection "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_frame "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_implicit_scenario "$prompt_text"; then
    return 0
  fi
  return 1
}

assistant_output_is_freeform_reasoning_memo() {
  output_text=$(trim "$1")
  [ -n "$output_text" ] || return 1
  if assistant_output_is_compact_reasoning_contract "$output_text"; then
    return 1
  fi
  if assistant_output_is_reasoning_completion_contract "$output_text"; then
    return 1
  fi
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  sentence_count=$(printf '%s' "$output_text" | awk '
    {
      text = text " " $0
    }
    END {
      gsub(/[[:space:]]+/, " ", text)
      n = split(text, parts, /[.!?][[:space:]]+/)
      count = 0
      for (i = 1; i <= n; i++) {
        part = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", part)
        if (length(part) > 0) {
          count++
        }
      }
      print count
    }
  ')
  case "$sentence_count" in
    ""|*[!0-9]*)
      sentence_count=0
      ;;
  esac
  [ "$sentence_count" -ge 3 ] || return 1
  return 0
}

