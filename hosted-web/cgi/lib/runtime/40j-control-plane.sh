control_plane_api_version() {
  printf '%s' 'v1'
}

control_plane_url_encode() {
  input=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$input" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
    return 0
  fi
  printf '%s' "$input" | sed 's/%/%25/g;s/ /%20/g;s/\t/%09/g;s/\n/%0A/g;s/\r/%0D/g;s/&/%26/g;s/=/%3D/g;s/?/%3F/g;s/#/%23/g'
}

control_plane_strip_headers() {
  awk '
    BEGIN { body = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (body == 1) {
        print line
        next
      }
      if (line == "") {
        body = 1
      }
    }
  '
}

control_plane_call_action_get_json() {
  action_name=$1
  shift
  query="action=$(control_plane_url_encode "$action_name")"
  while [ "$#" -gt 0 ]; do
    key=$1
    value=$2
    shift 2
    query="${query}&$(control_plane_url_encode "$key")=$(control_plane_url_encode "$value")"
  done
  response=$(REQUEST_METHOD=GET QUERY_STRING="$query" "$ARTIFICER_API_SCRIPT" 2>&1 || true)
  json_payload=$(printf '%s\n' "$response" | control_plane_strip_headers)
  if [ -n "$(trim "$json_payload")" ]; then
    printf '%s\n' "$json_payload"
    return 0
  fi
  printf '%s\n' "$response"
}

control_plane_call_action_post_json() {
  action_name=$1
  shift
  body="action=$(control_plane_url_encode "$action_name")"
  while [ "$#" -gt 0 ]; do
    key=$1
    value=$2
    shift 2
    body="${body}&$(control_plane_url_encode "$key")=$(control_plane_url_encode "$value")"
  done
  content_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
  response=$(printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_TYPE='application/x-www-form-urlencoded' CONTENT_LENGTH="$content_length" "$ARTIFICER_API_SCRIPT" 2>&1 || true)
  json_payload=$(printf '%s\n' "$response" | control_plane_strip_headers)
  if [ -n "$(trim "$json_payload")" ]; then
    printf '%s\n' "$json_payload"
    return 0
  fi
  printf '%s\n' "$response"
}

control_plane_json_success() {
  payload=$1
  case "$payload" in
    *'"success":true'*)
      return 0
      ;;
  esac
  return 1
}

control_plane_json_extract_scalar() {
  payload=$1
  expression=$2
  if command -v python3 >/dev/null 2>&1; then
    JSON_PAYLOAD=$payload JSON_EXPR=$expression python3 - <<'PY'
import json
import os
payload = os.environ.get("JSON_PAYLOAD", "")
expr = os.environ.get("JSON_EXPR", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)
try:
    value = eval(expr, {"__builtins__": {"len": len}}, {"data": data})
except Exception:
    print("")
    raise SystemExit(0)
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
else:
    print(str(value))
PY
    return 0
  fi
  printf '%s' "$payload" | sed -n 's/.*"'"$expression"'":"\([^"]*\)".*/\1/p' | sed -n '1p'
}

control_plane_json_array_csv() {
  payload=$1
  expression=$2
  if command -v python3 >/dev/null 2>&1; then
    JSON_PAYLOAD=$payload JSON_EXPR=$expression python3 - <<'PY'
import json
import os

payload = os.environ.get("JSON_PAYLOAD", "")
expr = os.environ.get("JSON_EXPR", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)
try:
    value = eval(expr, {"__builtins__": {"len": len}}, {"data": data})
except Exception:
    print("")
    raise SystemExit(0)
if value is None:
    print("")
elif isinstance(value, list):
    print(",".join(str(item).strip() for item in value if str(item).strip()))
else:
    print(str(value))
PY
    return 0
  fi
  printf '%s' ''
}

control_plane_stream_session_id() {
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  nanos=$(date +%N 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  case "$nanos" in
    ""|*[!0-9]*)
      nanos=0
      ;;
  esac
  printf '%s-%s-%s' "$now_epoch" "$$" "$nanos"
}

control_plane_session_run_finalize_if_stuck() {
  workspace_id=$1
  conversation_id=$2
  item_id=$3
  error_text=$4

  if ! valid_workspace_id "$workspace_id" || ! valid_id "$conversation_id"; then
    return 0
  fi

  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  if [ ! -d "$conv_dir" ]; then
    return 0
  fi

  queue_info=$(queue_state_for_conversation "$conv_dir")
  queue_running=$(kv_get "running" "$queue_info")
  queue_last_status=$(kv_get "last_status" "$queue_info")
  [ -n "$queue_running" ] || queue_running=0
  case "$queue_last_status" in
    done|error|cancelled|awaiting_decision|awaiting_approval)
      return 0
      ;;
  esac
  if [ "$queue_running" != "1" ]; then
    return 0
  fi
  if [ -z "$(trim "$error_text")" ]; then
    error_text="headless control-plane run-next failed before queue finalization"
  fi
  control_plane_call_action_post_json "queue_finish" \
    "workspace_id" "$workspace_id" \
    "conversation_id" "$conversation_id" \
    "item_id" "$item_id" \
    "status" "error" \
    "error" "$error_text" >/dev/null
}

control_plane_queue_json_for_conversation() {
  conv_dir=$1
  queue_info=$(queue_state_for_conversation "$conv_dir")
  queue_pending=$(kv_get "pending" "$queue_info")
  queue_running=$(kv_get "running" "$queue_info")
  queue_done=$(kv_get "done" "$queue_info")
  queue_first_id=$(kv_get "first_id" "$queue_info")
  queue_last_status=$(kv_get "last_status" "$queue_info")
  [ -n "$queue_pending" ] || queue_pending=0
  [ -n "$queue_running" ] || queue_running=0
  [ -n "$queue_done" ] || queue_done=0
  printf '{"pending":%s,"running":%s,"done":%s,"first_id":"%s","last_status":"%s"}' \
    "$queue_pending" "$queue_running" "$queue_done" "$(json_escape "$queue_first_id")" "$(json_escape "$queue_last_status")"
}

control_plane_trace_json_for_conversation() {
  conv_dir=$1
  include_events=${2:-1}
  active_stream_session=$(trim "$(read_file_line "$(queue_running_stream_session_file_for "$conv_dir")" "")")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_started_at=$(trim "$(read_file_line "$(queue_running_started_iso_file_for "$conv_dir")" "")")
  state_preview=$(sed -n '1,60p' "$conv_dir/agent/.state" 2>/dev/null || true)
  task_status_json=$(task_status_json_from_tasks_dir "$(tasks_dir_for_conversation "$conv_dir")" "running" "$state_preview")
  events_json='[]'
  tool_hooks_json='[]'
  if [ "$include_events" = "1" ]; then
    events_json=$(json_run_events_with_active "$conv_dir")
    tool_hook_log="$conv_dir/agent/.tool-hooks.jsonl"
    if [ -f "$tool_hook_log" ]; then
      tool_hooks_json=$(awk '
        BEGIN { first = 1; printf "[" }
        {
          line = $0
          sub(/\r$/, "", line)
          if (line == "") {
            next
          }
          if (first == 0) {
            printf ","
          }
          first = 0
          printf "%s", line
        }
        END { printf "]" }
      ' "$tool_hook_log")
    fi
  fi
  printf '{"active_stream_session":"%s","running_event_id":"%s","running_started_at":"%s","task_status":%s,"events":%s,"tool_hooks":%s}' \
    "$(json_escape "$active_stream_session")" "$(json_escape "$running_event_id")" "$(json_escape "$running_started_at")" "$task_status_json" "$events_json" "$tool_hooks_json"
}

control_plane_session_object_json() {
  workspace_id=$1
  conversation_id=$2
  include_messages=${3:-1}
  include_events=${4:-1}

  if ! valid_workspace_id "$workspace_id"; then
    printf '%s' ''
    return 1
  fi
  if ! valid_id "$conversation_id"; then
    printf '%s' ''
    return 1
  fi

  ws_dir=$(workspace_dir_for "$workspace_id")
  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  [ -d "$ws_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1

  seed_missing_initial_message_if_needed "$conv_dir"

  workspace_name=$(read_file_line "$ws_dir/name" "$workspace_id")
  workspace_path=$(read_file_line "$ws_dir/path" "")
  title=$(read_file_line "$conv_dir/title" "Conversation")
  model=$(read_file_line "$conv_dir/model" "$(default_model)")
  created=$(read_file_line "$conv_dir/created" "0")
  updated=$(read_file_line "$conv_dir/updated" "0")
  draft_file=$(conversation_draft_file_for "$workspace_id" "$conversation_id")
  draft_text=$(cat "$draft_file" 2>/dev/null || true)
  queue_json=$(control_plane_queue_json_for_conversation "$conv_dir")
  decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
  approval_request_json=$(approval_request_json_for_conversation "$conv_dir")
  messages_json='[]'
  if [ "$include_messages" = "1" ]; then
    messages_json=$(json_messages "$conv_dir")
  fi
  trace_json=$(control_plane_trace_json_for_conversation "$conv_dir" "$include_events")

  printf '{"id":"%s","workspace_id":"%s","workspace_name":"%s","workspace_path":"%s","title":"%s","model":"%s","created":"%s","updated":"%s","draft":"%s","queue":%s,"decision_request":%s,"approval_request":%s,"trace":%s,"messages":%s}' \
    "$(json_escape "$conversation_id")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$workspace_name")" \
    "$(json_escape "$workspace_path")" \
    "$(json_escape "$title")" \
    "$(json_escape "$model")" \
    "$(json_escape "$created")" \
    "$(json_escape "$updated")" \
    "$(json_escape "$draft_text")" \
    "$queue_json" \
    "$decision_request_json" \
    "$approval_request_json" \
    "$trace_json" \
    "$messages_json"
}

control_plane_projects_list_json() {
  printf '{"success":true,"api_version":"%s","projects":[' "$(json_escape "$(control_plane_api_version)")"
  first=1
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    workspace_id=$(basename "$ws_dir")
    workspace_name=$(read_file_line "$ws_dir/name" "$workspace_id")
    workspace_path=$(read_file_line "$ws_dir/path" "")
    path_exists=0
    if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
      path_exists=1
    fi
    session_count=0
    if [ -d "$ws_dir/conversations" ]; then
      session_count=$(find "$ws_dir/conversations" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"id":"%s","name":"%s","path":"%s","path_exists":%s,"session_count":%s}' \
      "$(json_escape "$workspace_id")" \
      "$(json_escape "$workspace_name")" \
      "$(json_escape "$workspace_path")" \
      "$path_exists" \
      "$session_count"
  done
  printf ']}'
}

control_plane_project_get_json() {
  workspace_id=$1
  if ! valid_workspace_id "$workspace_id"; then
    emit_error "invalid workspace_id"
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    emit_error "workspace not found"
    return 0
  fi
  workspace_name=$(read_file_line "$ws_dir/name" "$workspace_id")
  workspace_path=$(read_file_line "$ws_dir/path" "")
  path_exists=0
  if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
    path_exists=1
  fi
  sessions_json=$(control_plane_sessions_list_array_json "$workspace_id")
  printf '{"success":true,"api_version":"%s","project":{"id":"%s","name":"%s","path":"%s","path_exists":%s,"sessions":%s}}' \
    "$(json_escape "$(control_plane_api_version)")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$workspace_name")" \
    "$(json_escape "$workspace_path")" \
    "$path_exists" \
    "$sessions_json"
}

control_plane_sessions_list_array_json() {
  workspace_filter=${1:-}
  printf '['
  first=1
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    workspace_id=$(basename "$ws_dir")
    if [ -n "$workspace_filter" ] && [ "$workspace_id" != "$workspace_filter" ]; then
      continue
    fi
    conv_parent="$ws_dir/conversations"
    [ -d "$conv_parent" ] || continue
    for conv_dir in "$conv_parent"/*; do
      [ -d "$conv_dir" ] || continue
      conversation_id=$(basename "$conv_dir")
      session_json=$(control_plane_session_object_json "$workspace_id" "$conversation_id" 0 0 || true)
      [ -n "$session_json" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '%s' "$session_json"
    done
  done
  printf ']'
}

control_plane_sessions_list_json() {
  workspace_filter=${1:-}
  printf '{"success":true,"api_version":"%s","sessions":%s}' \
    "$(json_escape "$(control_plane_api_version)")" \
    "$(control_plane_sessions_list_array_json "$workspace_filter")"
}

control_plane_attention_list_json() {
  printf '{"success":true,"api_version":"%s","items":[' "$(json_escape "$(control_plane_api_version)")"
  first=1
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    workspace_id=$(basename "$ws_dir")
    workspace_name=$(read_file_line "$ws_dir/name" "$workspace_id")
    conv_parent="$ws_dir/conversations"
    [ -d "$conv_parent" ] || continue
    for conv_dir in "$conv_parent"/*; do
      [ -d "$conv_dir" ] || continue
      conversation_id=$(basename "$conv_dir")
      title=$(read_file_line "$conv_dir/title" "Conversation")
      decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
      approval_request_json=$(approval_request_json_for_conversation "$conv_dir")
      case "$decision_request_json" in
        null|'')
          ;;
        *)
          if [ "$first" -eq 0 ]; then printf ','; fi
          first=0
          printf '{"kind":"decision","workspace_id":"%s","workspace_name":"%s","conversation_id":"%s","session_title":"%s","request":%s}' \
            "$(json_escape "$workspace_id")" "$(json_escape "$workspace_name")" "$(json_escape "$conversation_id")" "$(json_escape "$title")" "$decision_request_json"
          ;;
      esac
      case "$approval_request_json" in
        null|'')
          ;;
        *)
          if [ "$first" -eq 0 ]; then printf ','; fi
          first=0
          printf '{"kind":"approval","workspace_id":"%s","workspace_name":"%s","conversation_id":"%s","session_title":"%s","request":%s}' \
            "$(json_escape "$workspace_id")" "$(json_escape "$workspace_name")" "$(json_escape "$conversation_id")" "$(json_escape "$title")" "$approval_request_json"
          ;;
      esac
    done
  done
  printf ']}'
}

control_plane_health_json() {
  models_raw=$(list_models_raw)
  model_count=0
  if [ -n "$(trim "$models_raw")" ]; then
    model_count=$(printf '%s\n' "$models_raw" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  fi
  lsp_support=0
  if [ -x "$ARTIFICER_SCRIPT_DIR/../scripts/artificer-lsp-probe.py" ]; then
    lsp_support=1
  fi
  runtime_client_path="$ARTIFICER_SCRIPT_DIR/../scripts/artificer-runtime-client"
  runtime_client_exists=0
  if [ -x "$runtime_client_path" ]; then
    runtime_client_exists=1
  fi
  printf '{"success":true,"api_version":"%s","runtime":{"api_script":"%s","runtime_client":"%s","runtime_client_exists":%s,"default_model":"%s","installed_model_count":%s,"lsp_probe_available":%s}}' \
    "$(json_escape "$(control_plane_api_version)")" \
    "$(json_escape "$ARTIFICER_API_SCRIPT")" \
    "$(json_escape "$runtime_client_path")" \
    "$runtime_client_exists" \
    "$(json_escape "$(default_model)")" \
    "$model_count" \
    "$lsp_support"
}

control_plane_describe_json() {
  printf '{"success":true,"api_version":"%s","resources":[' "$(json_escape "$(control_plane_api_version)")"
  printf '{"name":"projects","action":"control_plane_projects","operations":["list","get","add","rename","delete"]},'
  printf '{"name":"sessions","action":"control_plane_sessions","operations":["list","get","create","archive","message","run-next","events","stream"]},'
  printf '{"name":"attention","action":"control_plane_attention","operations":["list","approval-answer","decision-answer"]},'
  printf '{"name":"automations","action":"control_plane_automations","operations":["list","get","upsert","toggle","run-now","delete"]},'
  printf '{"name":"self_actuation","action":"control_plane_self_actuation","operations":["preview","apply","policy-get","policy-set","audit"]},'
  printf '{"name":"health","action":"control_plane_health","operations":["get"]},'
  printf '{"name":"code_context","action":"control_plane_code_context","operations":["file"]}'
  printf '],"embedding":{"client_script":"%s","transport":"local-cgi-json","streaming":"polling","approval_workflow":"durable-session-attention"}}' \
    "$(json_escape "$ARTIFICER_SCRIPT_DIR/../scripts/artificer-runtime-client")"
}
