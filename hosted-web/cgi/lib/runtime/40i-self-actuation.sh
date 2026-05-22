self_actuation_policy_root="$data_root/self-actuation-policy"
self_actuation_policy_workspaces_root="$self_actuation_policy_root/workspaces"
self_actuation_policy_global_file="$self_actuation_policy_root/global.rules"
self_actuation_audit_root="$data_root/self-actuation-audit"
self_actuation_audit_file="$self_actuation_audit_root/events.jsonl"
self_actuation_idempotency_root="$data_root/self-actuation-idempotency"

mkdir -p "$self_actuation_policy_root"
mkdir -p "$self_actuation_policy_workspaces_root"
mkdir -p "$self_actuation_audit_root"
mkdir -p "$self_actuation_idempotency_root"
[ -f "$self_actuation_policy_global_file" ] || : > "$self_actuation_policy_global_file"
[ -f "$self_actuation_audit_file" ] || : > "$self_actuation_audit_file"

self_actuation_operations_csv() {
  printf '%s' "read_state,ensure_workspace,rename_workspace,delete_workspace,ensure_thread,archive_thread,ensure_automation,toggle_automation,run_automation_now,delete_automation,bootstrap_workspace_stack"
}

self_actuation_action_valid() {
  action_name=$1
  case "$action_name" in
    read_state|ensure_workspace|rename_workspace|delete_workspace|ensure_thread|archive_thread|ensure_automation|toggle_automation|run_automation_now|delete_automation|bootstrap_workspace_stack)
      return 0
      ;;
  esac
  return 1
}

self_actuation_operation_is_destructive() {
  action_name=$1
  case "$action_name" in
    archive_thread|delete_workspace|delete_automation)
      return 0
      ;;
  esac
  return 1
}

self_actuation_policy_workspace_file_for() {
  workspace_id=$1
  printf '%s/%s.rules' "$self_actuation_policy_workspaces_root" "$workspace_id"
}

self_actuation_policy_file_for_scope() {
  workspace_id=$1
  if [ -n "$workspace_id" ] && valid_workspace_id "$workspace_id"; then
    printf '%s' "$(self_actuation_policy_workspace_file_for "$workspace_id")"
    return 0
  fi
  printf '%s' "$self_actuation_policy_global_file"
}

self_actuation_policy_read_value_from_file() {
  policy_file=$1
  action_name=$2
  if [ ! -f "$policy_file" ]; then
    printf '%s' ""
    return 0
  fi
  awk -F'=' -v action_name="$action_name" '
    BEGIN {
      value = ""
    }
    $1 == action_name {
      value = $2
    }
    END {
      print value
    }
  ' "$policy_file"
}

self_actuation_policy_effective_value() {
  action_name=$1
  workspace_id=${2:-}
  if ! self_actuation_action_valid "$action_name"; then
    printf '%s' "deny"
    return 0
  fi

  if [ -n "$workspace_id" ] && valid_workspace_id "$workspace_id"; then
    workspace_file=$(self_actuation_policy_workspace_file_for "$workspace_id")
    workspace_value=$(self_actuation_policy_read_value_from_file "$workspace_file" "$action_name")
    case "$workspace_value" in
      allow|deny)
        printf '%s' "$workspace_value"
        return 0
        ;;
    esac
  fi

  global_value=$(self_actuation_policy_read_value_from_file "$self_actuation_policy_global_file" "$action_name")
  case "$global_value" in
    allow|deny)
      printf '%s' "$global_value"
      return 0
      ;;
  esac

  # Default-open posture retains existing behavior unless policy is explicitly set.
  printf '%s' "allow"
}

self_actuation_policy_allows() {
  action_name=$1
  workspace_id=${2:-}
  effective_value=$(self_actuation_policy_effective_value "$action_name" "$workspace_id")
  [ "$effective_value" = "allow" ]
}

self_actuation_policy_set_value() {
  action_name=$1
  workspace_id=${2:-}
  enabled_value_raw=$3

  if ! self_actuation_action_valid "$action_name"; then
    return 1
  fi
  enabled_value=$(normalize_toggle_01_value "$enabled_value_raw")
  if [ -z "$enabled_value" ]; then
    return 1
  fi

  if [ -n "$workspace_id" ] && ! valid_workspace_id "$workspace_id"; then
    return 1
  fi

  policy_value="deny"
  if [ "$enabled_value" = "1" ]; then
    policy_value="allow"
  fi

  policy_file=$(self_actuation_policy_file_for_scope "$workspace_id")
  policy_dir=$(dirname "$policy_file")
  mkdir -p "$policy_dir"
  [ -f "$policy_file" ] || : > "$policy_file"

  updated_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-self-actuation-policy.XXXXXX")
  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$action_name="*)
        printf '%s=%s\n' "$action_name" "$policy_value" >> "$updated_tmp"
        found=1
        ;;
      *=*)
        printf '%s\n' "$line" >> "$updated_tmp"
        ;;
      *)
        ;;
    esac
  done < "$policy_file"
  if [ "$found" -ne 1 ]; then
    printf '%s=%s\n' "$action_name" "$policy_value" >> "$updated_tmp"
  fi
  mv "$updated_tmp" "$policy_file"
  return 0
}

self_actuation_policy_json() {
  workspace_id=${1:-}
  printf '{"workspace_id":"%s","operations":{' "$(json_escape "$workspace_id")"
  first=1
  OLD_IFS=$IFS
  IFS=,
  for action_name in $(self_actuation_operations_csv); do
    [ -n "$action_name" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    effective_value=$(self_actuation_policy_effective_value "$action_name" "$workspace_id")
    enabled_value=0
    if [ "$effective_value" = "allow" ]; then
      enabled_value=1
    fi
    printf '"%s":"%s"' "$(json_escape "$action_name")" "$(json_escape "$enabled_value")"
  done
  IFS=$OLD_IFS
  printf '}}'
}

self_actuation_hash_text() {
  input_text=$1
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input_text" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input_text" | sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$input_text" | openssl dgst -sha256 | awk '{print $NF}'
    return 0
  fi
  printf '%s' "$input_text" | cksum | awk '{print $1}'
}

self_actuation_confirm_token_for_payload() {
  payload=$1
  self_actuation_hash_text "$payload"
}

self_actuation_idempotency_key_valid() {
  key_value=$1
  printf '%s\n' "$key_value" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
}

self_actuation_idempotency_file_for() {
  key_value=$1
  printf '%s/%s.json' "$self_actuation_idempotency_root" "$key_value"
}

self_actuation_idempotency_get() {
  key_value=$1
  if ! self_actuation_idempotency_key_valid "$key_value"; then
    return 1
  fi
  idempotency_file=$(self_actuation_idempotency_file_for "$key_value")
  if [ ! -f "$idempotency_file" ]; then
    return 1
  fi
  cat "$idempotency_file"
  return 0
}

self_actuation_idempotency_put() {
  key_value=$1
  payload=$2
  if ! self_actuation_idempotency_key_valid "$key_value"; then
    return 1
  fi
  idempotency_file=$(self_actuation_idempotency_file_for "$key_value")
  printf '%s\n' "$payload" > "$idempotency_file"
  return 0
}

self_actuation_now_iso_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

self_actuation_audit_append() {
  event_name=$1
  action_name=$2
  workspace_id=${3:-}
  conversation_id=${4:-}
  automation_id=${5:-}
  status_value=${6:-}
  detail_text=${7:-}
  idempotency_key=${8:-}
  confirm_token=${9:-}

  detail_line=$(printf '%s' "$detail_text" | tr '\n' ' ' | tr '\r' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//')
  ts_epoch=$(date +%s 2>/dev/null || printf '0')
  ts_iso=$(self_actuation_now_iso_utc)
  printf '{"ts_epoch":"%s","ts_iso":"%s","event":"%s","action":"%s","workspace_id":"%s","conversation_id":"%s","automation_id":"%s","status":"%s","detail":"%s","idempotency_key":"%s","confirm_token":"%s"}\n' \
    "$(json_escape "$ts_epoch")" \
    "$(json_escape "$ts_iso")" \
    "$(json_escape "$event_name")" \
    "$(json_escape "$action_name")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$conversation_id")" \
    "$(json_escape "$automation_id")" \
    "$(json_escape "$status_value")" \
    "$(json_escape "$detail_line")" \
    "$(json_escape "$idempotency_key")" \
    "$(json_escape "$confirm_token")" >> "$self_actuation_audit_file"
}

self_actuation_audit_entries_json() {
  limit_raw=${1:-50}
  case "$limit_raw" in
    ""|*[!0-9]*)
      limit_raw=50
      ;;
  esac
  if [ "$limit_raw" -lt 1 ]; then
    limit_raw=1
  fi
  if [ "$limit_raw" -gt 500 ]; then
    limit_raw=500
  fi
  if [ ! -f "$self_actuation_audit_file" ]; then
    printf '[]'
    return 0
  fi

  tail_file=$(mktemp "${TMPDIR:-/tmp}/artificer-self-actuation-audit-tail.XXXXXX")
  tail -n "$limit_raw" "$self_actuation_audit_file" > "$tail_file" 2>/dev/null || true
  printf '['
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "$line")
    [ -n "$line" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '%s' "$line"
  done < "$tail_file"
  printf ']'
  rm -f "$tail_file"
}

self_actuation_decode_path_input() {
  raw_path=$(trim "$1")
  case "$raw_path" in
    %7E*)
      raw_path="~${raw_path#%7E}"
      ;;
    %7e*)
      raw_path="~${raw_path#%7e}"
      ;;
  esac
  case "$raw_path" in
    "~")
      raw_path=$HOME
      ;;
    "~/"*)
      raw_path="$HOME/${raw_path#~/}"
      ;;
  esac
  printf '%s' "$raw_path"
}

self_actuation_normalize_workspace_path() {
  raw_path=$1
  expanded_path=$(self_actuation_decode_path_input "$raw_path")
  if [ -d "$expanded_path" ]; then
    (cd "$expanded_path" 2>/dev/null && pwd -P) || printf '%s' "$expanded_path"
    return 0
  fi
  printf '%s' "$expanded_path"
}

self_actuation_workspace_id_for_path() {
  raw_path=$1
  target_path=$(self_actuation_normalize_workspace_path "$raw_path")
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    ws_id=$(basename "$ws_dir")
    ws_path=$(read_file_line "$ws_dir/path" "")
    [ -n "$ws_path" ] || continue
    ws_path_norm=$(self_actuation_normalize_workspace_path "$ws_path")
    if [ "$ws_path_norm" = "$target_path" ]; then
      printf '%s' "$ws_id"
      return 0
    fi
  done
  printf '%s' ""
}

self_actuation_thread_id_for_title() {
  workspace_id=$1
  thread_title=$2
  ws_dir=$(workspace_dir_for "$workspace_id")
  conv_parent="$ws_dir/conversations"
  if [ ! -d "$conv_parent" ]; then
    printf '%s' ""
    return 0
  fi
  for conv_dir in "$conv_parent"/*; do
    [ -d "$conv_dir" ] || continue
    conv_id=$(basename "$conv_dir")
    conv_title=$(read_file_line "$conv_dir/title" "")
    if [ "$conv_title" = "$thread_title" ]; then
      printf '%s' "$conv_id"
      return 0
    fi
  done
  printf '%s' ""
}

self_actuation_automation_id_for_workspace_name() {
  workspace_id=$1
  automation_name=$2
  for automation_dir in "$automations_root"/*; do
    [ -d "$automation_dir" ] || continue
    automation_id=$(basename "$automation_dir")
    automation_workspace_id=$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")
    automation_name_value=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "")
    if [ "$automation_workspace_id" = "$workspace_id" ] && [ "$automation_name_value" = "$automation_name" ]; then
      printf '%s' "$automation_id"
      return 0
    fi
  done
  printf '%s' ""
}

self_actuation_workspace_id_for_automation() {
  automation_id=$1
  if ! valid_id "$automation_id"; then
    printf '%s' ""
    return 0
  fi
  automation_dir=$(automation_dir_for "$automation_id")
  if [ ! -d "$automation_dir" ]; then
    printf '%s' ""
    return 0
  fi
  read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" ""
}
