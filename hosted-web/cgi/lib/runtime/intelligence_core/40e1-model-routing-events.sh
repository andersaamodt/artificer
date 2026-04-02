model_is_text_generation_model() {
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *embed*|*embedding*|*nomic-embed*|*bge-*|*e5-*|*minilm*|*clip*|*whisper*)
      return 1
      ;;
  esac
  return 0
}

capability_family_model_bias_score() {
  model_name=$1
  family_id=$2
  lower=$(printf '%s' "$model_name" | tr '[:upper:]' '[:lower:]')
  score=0
  case "$family_id" in
    research_integration)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=14
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*|deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=12
          ;;
        mistral*|*mistral*|phi3*|*phi3*|phi4*|*phi4*|gemma2*|*gemma2*)
          score=8
          ;;
        deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*|codellama*|*codellama*|starcoder*|*starcoder*)
          score=-10
          ;;
      esac
      ;;
    planning_architecture)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*|deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=12
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*|mistral*|*mistral*)
          score=10
          ;;
        deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*|codellama*|*codellama*|starcoder*|*starcoder*)
          score=-8
          ;;
      esac
      ;;
    coding_mutation)
      case "$lower" in
        deepseek-coder*|*deepseek-coder*)
          score=16
          ;;
        qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*)
          score=14
          ;;
        starcoder*|*starcoder*|codellama*|*codellama*)
          score=12
          ;;
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=8
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*|mistral*|*mistral*)
          score=4
          ;;
      esac
      ;;
    review_document)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*|mistral*|*mistral*)
          score=10
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*|deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*)
          score=8
          ;;
        codellama*|*codellama*|starcoder*|*starcoder*|deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=6
          ;;
      esac
      ;;
    teaching_reassessment)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=14
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=12
          ;;
        phi3*|*phi3*|phi4*|*phi4*|gemma2*|*gemma2*|mistral*|*mistral*)
          score=10
          ;;
        deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*|codellama*|*codellama*|starcoder*|*starcoder*)
          score=-10
          ;;
      esac
      ;;
    admin_env_repair)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=10
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*|mistral*|*mistral*)
          score=8
          ;;
        deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*|codellama*|*codellama*|starcoder*|*starcoder*)
          score=6
          ;;
      esac
      ;;
  esac
  printf '%s' "$score"
}

capability_guidance_trace_family_ids() {
  trace_json=${1-}
  ARTIFICER_CAPABILITY_TRACE_JSON=$trace_json python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("ARTIFICER_CAPABILITY_TRACE_JSON", "") or "{}")
except Exception:
    payload = {}
if not isinstance(payload, dict):
    payload = {}
items = payload.get("items", [])
if not isinstance(items, list):
    items = []
for item in items[:6]:
    if not isinstance(item, dict):
        continue
    family_id = " ".join(str(item.get("id", "")).split()).strip()
    if family_id:
        print(family_id)
PY
}

model_preference_score_for_mode_with_capability_guidance() {
  model_name=$1
  mode_name=$2
  trace_json=${3-}
  base_score=$(model_preference_score_for_mode "$model_name" "$mode_name")
  case "$base_score" in
    ""|*[!0-9-]*)
      base_score=0
      ;;
  esac
  total_score=$base_score
  while IFS= read -r family_id; do
    family_id=$(trim "$family_id")
    [ -n "$family_id" ] || continue
    bias_score=$(capability_family_model_bias_score "$model_name" "$family_id")
    case "$bias_score" in
      ""|*[!0-9-]*)
        bias_score=0
        ;;
    esac
    total_score=$((total_score + bias_score))
  done <<EOF
$(capability_guidance_trace_family_ids "$trace_json")
EOF
  printf '%s' "$total_score"
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
    assistant|auto|report|teacher|text-perfecter|instant)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=122
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=116
          ;;
        mistral*|*mistral*)
          score=108
          ;;
        phi3*|*phi3*|phi4*|*phi4*|gemma2*|*gemma2*)
          score=104
          ;;
        deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=102
          ;;
        deepseek*|*deepseek*)
          score=92
          ;;
        codellama*|*codellama*|starcoder*|*starcoder*)
          score=74
          ;;
        *)
          score=82
          ;;
      esac
      case "$lower" in
        *coder*|*code*)
          score=$((score - 12))
          ;;
      esac
      case "$lower" in
        *instruct*|*chat*)
          score=$((score + 4))
          ;;
      esac
      ;;
    security-audit|pentest)
      case "$lower" in
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=120
          ;;
        deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*|mistral*|*mistral*)
          score=112
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=108
          ;;
        deepseek-coder*|*deepseek-coder*|qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*)
          score=104
          ;;
        codellama*|*codellama*|starcoder*|*starcoder*)
          score=94
          ;;
        *)
          score=84
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

best_model_for_mode_with_capability_guidance() {
  mode_name=$1
  trace_json=${2-}
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
    score=$(model_preference_score_for_mode_with_capability_guidance "$model_name" "$mode_name" "$trace_json")
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

capability_guidance_favors_general_reasoning() {
  trace_json=${1-}
  while IFS= read -r family_id; do
    case "$(trim "$family_id")" in
      research_integration|planning_architecture|review_document|teaching_reassessment|admin_env_repair)
        return 0
        ;;
    esac
  done <<EOF
$(capability_guidance_trace_family_ids "$trace_json")
EOF
  return 1
}

capability_guidance_favors_code_specialist() {
  trace_json=${1-}
  while IFS= read -r family_id; do
    case "$(trim "$family_id")" in
      coding_mutation)
        return 0
        ;;
    esac
  done <<EOF
$(capability_guidance_trace_family_ids "$trace_json")
EOF
  return 1
}

run_capability_autoroute_model() {
  current_model=$(trim "$1")
  mode_name=$(trim "$2")
  trace_json=${3-}
  [ -n "$current_model" ] || return 0
  [ -n "$(trim "$trace_json")" ] || return 0

  best_model=$(best_model_for_mode_with_capability_guidance "$mode_name" "$trace_json")
  [ -n "$best_model" ] || return 0
  if [ "$best_model" = "$current_model" ]; then
    return 0
  fi

  current_score=$(model_preference_score_for_mode_with_capability_guidance "$current_model" "$mode_name" "$trace_json")
  best_score=$(model_preference_score_for_mode_with_capability_guidance "$best_model" "$mode_name" "$trace_json")
  case "$current_score" in ""|*[!0-9-]*) current_score=0 ;; esac
  case "$best_score" in ""|*[!0-9-]*) best_score=0 ;; esac
  score_gap=$((best_score - current_score))

  current_lower=$(printf '%s' "$current_model" | tr '[:upper:]' '[:lower:]')
  best_lower=$(printf '%s' "$best_model" | tr '[:upper:]' '[:lower:]')
  current_coder_like=0
  best_coder_like=0
  case "$current_lower" in
    *coder*|*code*|starcoder*|*starcoder*|codellama*|*codellama*|deepseek-coder*|*deepseek-coder*)
      current_coder_like=1
      ;;
  esac
  case "$best_lower" in
    *coder*|*code*|starcoder*|*starcoder*|codellama*|*codellama*|deepseek-coder*|*deepseek-coder*)
      best_coder_like=1
      ;;
  esac

  if [ "$mode_name" = "programming" ] && capability_guidance_favors_code_specialist "$trace_json" && [ "$best_coder_like" -eq 1 ] && [ "$score_gap" -ge 8 ]; then
    printf '%s' "$best_model"
    return 0
  fi
  if [ "$mode_name" != "programming" ] && capability_guidance_favors_general_reasoning "$trace_json" && [ "$current_coder_like" -eq 1 ] && [ "$score_gap" -ge 8 ]; then
    printf '%s' "$best_model"
    return 0
  fi
  if [ "$score_gap" -ge 14 ]; then
    printf '%s' "$best_model"
    return 0
  fi
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
    "$assay_task_id" \
    "" \
    "")
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
  capability_guidance_json_override=${20-}

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
  capability_guidance_json=$(trim "$capability_guidance_json_override")
  if [ -z "$capability_guidance_json" ]; then
    capability_guidance_json='{"summary":"","items":[],"count":0}'
  fi
  case "$capability_guidance_json" in
    \{*\})
      ;;
    *)
      capability_guidance_json='{"summary":"","items":[],"count":0}'
      ;;
  esac
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

  printf '{"id":"%s","status":"%s","started_at":"%s","finished_at":"%s","model":"%s","plan":"%s","assistant":"%s","commands":%s,"stream_text":"%s","failures":"%s","session_log":"%s","state":"%s","git_status":"%s","git_diff":"%s","error":"%s","decision_hint":"%s","capability_guidance":%s%s,"task_status":%s}' \
    "$event_id_json" "$status_json" "$started_json" "$finished_json" "$model_json" "$plan_json" "$assistant_json" "$commands_json" "$stream_json" "$failures_json" "$session_json" "$state_json" "$git_status_json" "$git_diff_json" "$error_json" "$hint_json" "$capability_guidance_json" "$message_anchor_json" "$task_status_json"
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

artificer_appctl_strip_outer_quotes() {
  token=$1
  case "$token" in
    \"*\")
      token=${token#\"}
      token=${token%\"}
      ;;
    \'*\')
      token=${token#\'}
      token=${token%\'}
      ;;
  esac
  printf '%s' "$token"
}

artificer_appctl_id_valid() {
  token=$(artificer_appctl_strip_outer_quotes "$1")
  printf '%s\n' "$token" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

artificer_appctl_bool_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    0|1|true|false|yes|no|on|off|enabled|disabled)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_command_exec_mode_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    ask|none|ask-all|ask-some|all)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_permission_mode_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    default|workspace-write|read-only|full-access)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_schedule_kind_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    cron|interval|once)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_run_mode_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    instant|auto|chat|programming|pentest|security-audit|teacher|report|text-perfecter|gui-testing|assistant|team|teams)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_compute_budget_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    auto|quick|standard|long|until-complete)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_rounds_valid() {
  token=$(artificer_appctl_strip_outer_quotes "$1")
  case "$token" in
    1|2|3|4)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_epoch_valid() {
  token=$(artificer_appctl_strip_outer_quotes "$1")
  case "$token" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  return 0
}

artificer_appctl_value_token_valid() {
  token=$1
  case "$token" in
    ''|--*)
      return 1
      ;;
  esac
  return 0
}

artificer_appctl_consume_text_value() {
  # Consumes one or more non-flag tokens and returns remaining args on stdout.
  # shellcheck disable=SC2120
  if [ "$#" -lt 1 ]; then
    return 1
  fi
  saw=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --*)
        break
        ;;
      *)
        saw=1
        shift
        ;;
    esac
  done
  [ "$saw" -eq 1 ] || return 1
  printf '%s\n' "$*"
  return 0
}

validate_artificer_appctl_project_add_args() {
  seen_path=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --path|--name)
        flag=$1
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        # shellcheck disable=SC2086
        set -- $remaining
        if [ "$flag" = "--path" ]; then
          seen_path=1
        fi
        ;;
      --command-exec|--command-exec-mode)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_command_exec_mode_valid "$1" || return 1
        shift
        ;;
      *)
        return 1
        ;;
    esac
  done
  [ "$seen_path" -eq 1 ] || return 1
  return 0
}

validate_artificer_appctl_thread_new_args() {
  seen_workspace=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace-id)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_id_valid "$1" || return 1
        seen_workspace=1
        shift
        ;;
      --model)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_value_token_valid "$1" || return 1
        shift
        ;;
      --title)
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        # shellcheck disable=SC2086
        set -- $remaining
        ;;
      *)
        return 1
        ;;
    esac
  done
  [ "$seen_workspace" -eq 1 ] || return 1
  return 0
}

validate_artificer_appctl_automation_upsert_args() {
  seen_workspace=0
  seen_name=0
  seen_prompt=0
  seen_schedule_kind=0
  seen_schedule_value=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --automation-id|--conversation-id|--assistant-mode-id|--assay-task-id|--explicit-skill-ids)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_value_token_valid "$1" || return 1
        shift
        ;;
      --workspace-id)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_id_valid "$1" || return 1
        seen_workspace=1
        shift
        ;;
      --name)
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        seen_name=1
        # shellcheck disable=SC2086
        set -- $remaining
        ;;
      --prompt)
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        seen_prompt=1
        # shellcheck disable=SC2086
        set -- $remaining
        ;;
      --schedule-kind)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_schedule_kind_valid "$1" || return 1
        seen_schedule_kind=1
        shift
        ;;
      --schedule-value)
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        seen_schedule_value=1
        # shellcheck disable=SC2086
        set -- $remaining
        ;;
      --enabled|--allow-self-reschedule|--programmer-review)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_bool_valid "$1" || return 1
        shift
        ;;
      --run-mode)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_run_mode_valid "$1" || return 1
        shift
        ;;
      --compute-budget)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_compute_budget_valid "$1" || return 1
        shift
        ;;
      --command-exec|--command-exec-mode)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_command_exec_mode_valid "$1" || return 1
        shift
        ;;
      --permission-mode)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_permission_mode_valid "$1" || return 1
        shift
        ;;
      --programmer-review-rounds)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_rounds_valid "$1" || return 1
        shift
        ;;
      --next-run)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_epoch_valid "$1" || return 1
        shift
        ;;
      *)
        return 1
        ;;
    esac
  done
  [ "$seen_workspace" -eq 1 ] || return 1
  [ "$seen_name" -eq 1 ] || return 1
  [ "$seen_prompt" -eq 1 ] || return 1
  [ "$seen_schedule_kind" -eq 1 ] || return 1
  [ "$seen_schedule_value" -eq 1 ] || return 1
  return 0
}

artificer_appctl_self_actuation_operation_valid() {
  token=$(printf '%s' "$(artificer_appctl_strip_outer_quotes "$1")" | tr '[:upper:]' '[:lower:]')
  case "$token" in
    read_state|ensure_workspace|rename_workspace|delete_workspace|ensure_thread|archive_thread|ensure_automation|toggle_automation|run_automation_now|delete_automation|bootstrap_workspace_stack)
      return 0
      ;;
  esac
  return 1
}

artificer_appctl_idempotency_key_valid() {
  token=$(artificer_appctl_strip_outer_quotes "$1")
  printf '%s\n' "$token" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
}

artificer_appctl_uint_valid() {
  token=$(artificer_appctl_strip_outer_quotes "$1")
  case "$token" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  return 0
}

validate_artificer_appctl_self_actuation_orchestrate_args() {
  mode_name=$1
  shift
  seen_operation=0
  seen_confirm=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --operation)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_self_actuation_operation_valid "$1" || return 1
        seen_operation=1
        shift
        ;;
      --workspace-id|--conversation-id|--automation-id)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_id_valid "$1" || return 1
        shift
        ;;
      --path|--name|--title|--model|--prompt|--schedule-value)
        shift
        [ "$#" -gt 0 ] || return 1
        remaining=$(artificer_appctl_consume_text_value "$@") || return 1
        # shellcheck disable=SC2086
        set -- $remaining
        ;;
      --schedule-kind)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_schedule_kind_valid "$1" || return 1
        shift
        ;;
      --command-exec|--command-exec-mode)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_command_exec_mode_valid "$1" || return 1
        shift
        ;;
      --enabled|--allow-self-reschedule)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_bool_valid "$1" || return 1
        shift
        ;;
      --confirm-token)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_value_token_valid "$1" || return 1
        seen_confirm=1
        shift
        ;;
      --idempotency-key)
        shift
        [ "$#" -gt 0 ] || return 1
        artificer_appctl_idempotency_key_valid "$1" || return 1
        shift
        ;;
      --json)
        shift
        ;;
      *)
        return 1
        ;;
    esac
  done
  [ "$seen_operation" -eq 1 ] || return 1
  if [ "$mode_name" = "apply" ] && [ "$seen_confirm" -ne 1 ]; then
    return 1
  fi
  return 0
}

validate_artificer_appctl_command() {
  cmd_text=$1
  reflexive_gate=$2
  self_actuation_gate=$3

  (
    # shellcheck disable=SC2086
    set -- $cmd_text
    [ "$#" -ge 2 ] || exit 1
    [ "$1" = "artificer-appctl" ] || exit 1
    [ "$#" -ge 3 ] || exit 1
    kind=$2
    action=$3
    shift 3
    case "$kind:$action" in
      project:add)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        validate_artificer_appctl_project_add_args "$@" || exit 1
        exit 0
        ;;
      project:list)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        case "$#" in
          0) exit 0 ;;
          1) [ "$1" = "--json" ] && exit 0 ;;
        esac
        exit 1
        ;;
      project:rename)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        seen_workspace=0
        seen_name=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --workspace-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              seen_workspace=1
              shift
              ;;
            --name)
              shift
              [ "$#" -gt 0 ] || exit 1
              remaining=$(artificer_appctl_consume_text_value "$@") || exit 1
              seen_name=1
              # shellcheck disable=SC2086
              set -- $remaining
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_workspace" -eq 1 ] && [ "$seen_name" -eq 1 ] || exit 1
        exit 0
        ;;
      project:delete)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        [ "$#" -eq 2 ] || exit 1
        [ "$1" = "--workspace-id" ] || exit 1
        artificer_appctl_id_valid "$2" || exit 1
        exit 0
        ;;
      thread:new)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        validate_artificer_appctl_thread_new_args "$@" || exit 1
        exit 0
        ;;
      thread:list)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        seen_workspace=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --workspace-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              seen_workspace=1
              shift
              ;;
            --json)
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_workspace" -eq 1 ] || exit 1
        exit 0
        ;;
      thread:archive)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        seen_workspace=0
        seen_conversation=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --workspace-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              seen_workspace=1
              shift
              ;;
            --conversation-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              seen_conversation=1
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_workspace" -eq 1 ] && [ "$seen_conversation" -eq 1 ] || exit 1
        exit 0
        ;;
      knowledge:show)
        [ "$reflexive_gate" -eq 1 ] || exit 1
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json)
              shift
              ;;
            --topic)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_value_token_valid "$1" || exit 1
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        exit 0
        ;;
      knowledge:teach)
        [ "$reflexive_gate" -eq 1 ] || exit 1
        seen_topic=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json)
              shift
              ;;
            --topic)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_value_token_valid "$1" || exit 1
              seen_topic=1
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_topic" -eq 1 ] || exit 1
        exit 0
        ;;
      automation:list)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        case "$#" in
          0) exit 0 ;;
          1) [ "$1" = "--json" ] && exit 0 ;;
        esac
        exit 1
        ;;
      automation:toggle)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        seen_id=0
        seen_enabled=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --automation-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              seen_id=1
              shift
              ;;
            --enabled)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_bool_valid "$1" || exit 1
              seen_enabled=1
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_id" -eq 1 ] && [ "$seen_enabled" -eq 1 ] || exit 1
        exit 0
        ;;
      automation:run-now|automation:delete)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        [ "$#" -eq 2 ] || exit 1
        [ "$1" = "--automation-id" ] || exit 1
        artificer_appctl_id_valid "$2" || exit 1
        exit 0
        ;;
      automation:upsert)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        validate_artificer_appctl_automation_upsert_args "$@" || exit 1
        exit 0
        ;;
      self-actuation:preview)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        validate_artificer_appctl_self_actuation_orchestrate_args "preview" "$@" || exit 1
        exit 0
        ;;
      self-actuation:apply)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        validate_artificer_appctl_self_actuation_orchestrate_args "apply" "$@" || exit 1
        exit 0
        ;;
      self-actuation:policy-get)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --workspace-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              shift
              ;;
            --action)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_self_actuation_operation_valid "$1" || exit 1
              shift
              ;;
            --json)
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        exit 0
        ;;
      self-actuation:policy-set)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        seen_action=0
        seen_enabled=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --workspace-id)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_id_valid "$1" || exit 1
              shift
              ;;
            --action)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_self_actuation_operation_valid "$1" || exit 1
              seen_action=1
              shift
              ;;
            --enabled)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_bool_valid "$1" || exit 1
              seen_enabled=1
              shift
              ;;
            --json)
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        [ "$seen_action" -eq 1 ] && [ "$seen_enabled" -eq 1 ] || exit 1
        exit 0
        ;;
      self-actuation:audit)
        [ "$self_actuation_gate" -eq 1 ] || exit 1
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --limit)
              shift
              [ "$#" -gt 0 ] || exit 1
              artificer_appctl_uint_valid "$1" || exit 1
              shift
              ;;
            --json)
              shift
              ;;
            *)
              exit 1
              ;;
          esac
        done
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
  )
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
    artificer-appctl)
      reflexive_gate=0
      self_actuation_gate=0
      if [ "${REFLEXIVE_KNOWLEDGE:-0}" = "1" ] || [ "${ARTIFICER_REFLEXIVE_KNOWLEDGE:-0}" = "1" ]; then
        reflexive_gate=1
      fi
      if [ "${SELF_ACTUATION:-0}" = "1" ] || [ "${ARTIFICER_SELF_ACTUATION:-0}" = "1" ]; then
        self_actuation_gate=1
      fi
      case "$second_word" in
        help|--help|-h)
          if [ "$reflexive_gate" -ne 1 ] && [ "$self_actuation_gate" -ne 1 ]; then
            return 1
          fi
          [ "$word_count" -le 2 ] || return 1
          return 0
          ;;
      esac
      if validate_artificer_appctl_command "$cmd" "$reflexive_gate" "$self_actuation_gate"; then
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

  printf '%s\n' "$command_text" | WORKSPACE_ROOT="$workspace_root" ARTIFICER_ASSAY_REPORTS_DIR="$ARTIFICER_ASSAY_REPORTS_DIR" perl -pe '
    my $ws = $ENV{"WORKSPACE_ROOT"} // "";
    my $assay_reports = $ENV{"ARTIFICER_ASSAY_REPORTS_DIR"} // "";
    $ws =~ s{/\z}{};
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
