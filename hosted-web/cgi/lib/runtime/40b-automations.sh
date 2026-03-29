automation_dir_for() {
  automation_id=$1
  printf '%s/%s' "$automations_root" "$automation_id"
}

automation_runtime_dir_for() {
  automation_id=$1
  printf '%s/%s' "$automations_runtime_root" "$automation_id"
}

automation_field_file_for() {
  automation_dir=$1
  field_name=$2
  printf '%s/%s' "$automation_dir" "$field_name"
}

automation_now_epoch() {
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  if [ "$now_epoch" -lt 0 ]; then
    now_epoch=0
  fi
  printf '%s' "$now_epoch"
}

automation_epoch_or_zero() {
  raw_value=$(trim "$1")
  case "$raw_value" in
    ""|*[!0-9]*)
      printf '%s' "0"
      return 0
      ;;
  esac
  if [ "$raw_value" -lt 0 ]; then
    printf '%s' "0"
    return 0
  fi
  printf '%s' "$raw_value"
}

automation_enabled_value() {
  raw_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_value" in
    1|true|yes|on|enabled)
      printf '%s' "1"
      ;;
    *)
      printf '%s' "0"
      ;;
  esac
}

automation_schedule_kind_value() {
  raw_kind=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_kind" in
    cron|interval|once)
      printf '%s' "$raw_kind"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

automation_schedule_normalize_and_next() {
  schedule_kind_raw=$1
  schedule_value_raw=$2
  from_epoch_raw=${3:-0}
  python3 - "$schedule_kind_raw" "$schedule_value_raw" "$from_epoch_raw" <<'PY'
import datetime
import re
import sys
import time

kind = (sys.argv[1] or "").strip().lower()
value_raw = (sys.argv[2] or "").strip()
try:
    from_epoch = int(float(sys.argv[3]))
except Exception:
    from_epoch = 0
if from_epoch <= 0:
    from_epoch = int(time.time())


def emit(status, kind_value="", normalized_value="", next_epoch=0, text="", error=""):
    safe_text = " ".join(str(text or "").split())
    safe_error = " ".join(str(error or "").split())
    try:
        next_int = int(next_epoch)
    except Exception:
        next_int = 0
    if next_int < 0:
        next_int = 0
    print(f"status={status}")
    print(f"kind={kind_value}")
    print(f"value={normalized_value}")
    print(f"next={next_int}")
    print(f"text={safe_text}")
    print(f"error={safe_error}")


def parse_interval_seconds(raw):
    token = re.sub(r"\s+", "", raw.lower())
    m = re.fullmatch(r"([0-9]+)(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks)?", token)
    if not m:
        return None
    amount = int(m.group(1))
    if amount <= 0:
        return None
    unit = (m.group(2) or "s").lower()
    mult = 1
    if unit in {"m", "min", "mins", "minute", "minutes"}:
        mult = 60
    elif unit in {"h", "hr", "hrs", "hour", "hours"}:
        mult = 3600
    elif unit in {"d", "day", "days"}:
        mult = 86400
    elif unit in {"w", "week", "weeks"}:
        mult = 604800
    return amount * mult


def local_iso(epoch):
    return datetime.datetime.fromtimestamp(epoch).isoformat(timespec="minutes")


def parse_once_epoch(raw):
    token = raw.strip()
    if not token:
        return None
    if re.fullmatch(r"[0-9]+", token):
        return int(token)
    iso_token = token
    if iso_token.endswith("Z"):
        iso_token = iso_token[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(iso_token)
        if dt.tzinfo is None:
            return int(dt.timestamp())
        return int(dt.astimezone().timestamp())
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.datetime.strptime(token, fmt)
            return int(dt.timestamp())
        except Exception:
            continue
    return None


def parse_number_token(token, min_v, max_v):
    value = int(token)
    if value < min_v or value > max_v:
        raise ValueError("out of range")
    return value


def parse_cron_field(token, min_v, max_v, allow_seven_sunday=False):
    token = token.strip()
    if not token:
        raise ValueError("empty field")
    all_values = set()
    for part in token.split(","):
        piece = part.strip()
        if not piece:
            raise ValueError("empty list item")
        if "/" in piece:
            base, step_text = piece.split("/", 1)
            if not step_text or not re.fullmatch(r"[0-9]+", step_text):
                raise ValueError("invalid step")
            step = int(step_text)
            if step <= 0:
                raise ValueError("invalid step")
        else:
            base = piece
            step = 1

        if base == "*":
            start = min_v
            end = max_v
        elif "-" in base:
            left, right = base.split("-", 1)
            if not re.fullmatch(r"[0-9]+", left or "") or not re.fullmatch(r"[0-9]+", right or ""):
                raise ValueError("invalid range")
            start = int(left)
            end = int(right)
        else:
            if not re.fullmatch(r"[0-9]+", base):
                raise ValueError("invalid number")
            start = int(base)
            end = int(base)

        if allow_seven_sunday:
            if start == 7:
                start = 0
            if end == 7:
                end = 0
            if start < min_v or start > max_v or end < min_v or end > max_v:
                raise ValueError("out of range")
            if start == 0 and end == 0:
                all_values.add(0)
                continue
            if start > end:
                raise ValueError("reverse range")
            for value in range(start, end + 1, step):
                if value == 7:
                    value = 0
                all_values.add(value)
            continue

        if start < min_v or start > max_v or end < min_v or end > max_v:
            raise ValueError("out of range")
        if start > end:
            raise ValueError("reverse range")
        for value in range(start, end + 1, step):
            all_values.add(value)

    if not all_values:
        raise ValueError("empty set")
    return all_values


def cron_next_epoch(expr, start_epoch):
    fields = expr.split()
    if len(fields) != 5:
        raise ValueError("cron must contain 5 fields")
    minute_field, hour_field, dom_field, month_field, dow_field = fields
    minutes = parse_cron_field(minute_field, 0, 59)
    hours = parse_cron_field(hour_field, 0, 23)
    dom = parse_cron_field(dom_field, 1, 31)
    months = parse_cron_field(month_field, 1, 12)
    dow = parse_cron_field(dow_field, 0, 6, allow_seven_sunday=True)

    dom_any = dom_field.strip() == "*"
    dow_any = dow_field.strip() == "*"

    dt = datetime.datetime.fromtimestamp(start_epoch).replace(second=0, microsecond=0) + datetime.timedelta(minutes=1)
    limit = dt + datetime.timedelta(days=548)
    while dt <= limit:
        if dt.month in months and dt.hour in hours and dt.minute in minutes:
            dom_match = dt.day in dom
            cron_dow = (dt.weekday() + 1) % 7
            dow_match = cron_dow in dow
            if dom_any and dow_any:
                dom_dow_match = True
            elif dom_any:
                dom_dow_match = dow_match
            elif dow_any:
                dom_dow_match = dom_match
            else:
                dom_dow_match = dom_match or dow_match
            if dom_dow_match:
                return int(dt.timestamp())
        dt += datetime.timedelta(minutes=1)
    return 0


if kind == "interval":
    interval_seconds = parse_interval_seconds(value_raw)
    if interval_seconds is None:
        emit("error", error="invalid interval schedule")
        sys.exit(0)
    next_epoch = from_epoch + interval_seconds
    emit(
        "ok",
        kind_value="interval",
        normalized_value=str(interval_seconds),
        next_epoch=next_epoch,
        text=f"Every {interval_seconds} seconds",
    )
    sys.exit(0)

if kind == "once":
    target_epoch = parse_once_epoch(value_raw)
    if target_epoch is None:
        emit("error", error="invalid once timestamp")
        sys.exit(0)
    if target_epoch <= from_epoch:
        emit("error", error="once timestamp must be in the future")
        sys.exit(0)
    emit(
        "ok",
        kind_value="once",
        normalized_value=str(target_epoch),
        next_epoch=target_epoch,
        text=f"Once at {local_iso(target_epoch)}",
    )
    sys.exit(0)

if kind == "cron":
    normalized_expr = " ".join(value_raw.split())
    if not normalized_expr:
        emit("error", error="cron expression is required")
        sys.exit(0)
    try:
        next_epoch = cron_next_epoch(normalized_expr, from_epoch)
    except Exception:
        emit("error", error="invalid cron schedule")
        sys.exit(0)
    if next_epoch <= 0:
        emit("error", error="cron schedule has no future run")
        sys.exit(0)
    emit(
        "ok",
        kind_value="cron",
        normalized_value=normalized_expr,
        next_epoch=next_epoch,
        text=f"Cron {normalized_expr}",
    )
    sys.exit(0)

emit("error", error="invalid schedule kind")
PY
}

automation_schedule_label() {
  schedule_kind=$(automation_schedule_kind_value "$1")
  schedule_value=$(trim "$2")
  case "$schedule_kind" in
    interval)
      case "$schedule_value" in
        ""|*[!0-9]*)
          printf '%s' "Every interval"
          ;;
        *)
          if [ "$schedule_value" -ge 86400 ] && [ $((schedule_value % 86400)) -eq 0 ]; then
            printf 'Every %sd' $((schedule_value / 86400))
          elif [ "$schedule_value" -ge 3600 ] && [ $((schedule_value % 3600)) -eq 0 ]; then
            printf 'Every %sh' $((schedule_value / 3600))
          elif [ "$schedule_value" -ge 60 ] && [ $((schedule_value % 60)) -eq 0 ]; then
            printf 'Every %sm' $((schedule_value / 60))
          else
            printf 'Every %ss' "$schedule_value"
          fi
          ;;
      esac
      ;;
    once)
      once_iso=$(iso_utc_from_epoch "$schedule_value")
      if [ -n "$once_iso" ]; then
        printf 'Once (%s)' "$once_iso"
      else
        printf '%s' "Once"
      fi
      ;;
    cron)
      if [ -n "$schedule_value" ]; then
        printf 'Cron %s' "$schedule_value"
      else
        printf '%s' "Cron"
      fi
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

automation_ids_sorted() {
  for automation_dir in "$automations_root"/*; do
    [ -d "$automation_dir" ] || continue
    automation_id=$(basename "$automation_dir")
    if ! valid_id "$automation_id"; then
      continue
    fi
    printf '%s\n' "$automation_id"
  done | sort
}

automation_workspace_name_for_id() {
  workspace_id=$1
  if ! valid_id "$workspace_id"; then
    printf '%s' ""
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 0
  fi
  read_file_line "$ws_dir/name" "$workspace_id"
}

automation_conversation_title_for_ids() {
  workspace_id=$1
  conversation_id=$2
  if ! valid_id "$workspace_id" || ! valid_id "$conversation_id"; then
    printf '%s' ""
    return 0
  fi
  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  if [ ! -d "$conv_dir" ]; then
    printf '%s' ""
    return 0
  fi
  read_file_line "$conv_dir/title" "Conversation"
}

automation_explicit_skills_file_for() {
  automation_dir=$1
  printf '%s/explicit_skill_ids' "$automation_dir"
}

automation_write_common_fields() {
  automation_dir=$1
  automation_name=$2
  workspace_id=$3
  conversation_id=$4
  prompt_text=$5
  schedule_kind=$6
  schedule_value=$7
  schedule_text=$8
  enabled_value=$9
  allow_self_reschedule_value=${10}
  run_mode_value=${11}
  assistant_mode_value=${12}
  compute_budget_value=${13}
  command_exec_mode_value=${14}
  permission_mode_value=${15}
  programmer_review_value=${16}
  programmer_review_rounds_value=${17}
  assay_task_id_value=${18}

  printf '%s\n' "$automation_name" > "$(automation_field_file_for "$automation_dir" "name")"
  printf '%s\n' "$workspace_id" > "$(automation_field_file_for "$automation_dir" "workspace_id")"
  printf '%s\n' "$conversation_id" > "$(automation_field_file_for "$automation_dir" "conversation_id")"
  printf '%s' "$prompt_text" > "$(automation_field_file_for "$automation_dir" "prompt")"
  printf '%s\n' "$schedule_kind" > "$(automation_field_file_for "$automation_dir" "schedule_kind")"
  printf '%s\n' "$schedule_value" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
  printf '%s\n' "$schedule_text" > "$(automation_field_file_for "$automation_dir" "schedule_text")"
  printf '%s\n' "$enabled_value" > "$(automation_field_file_for "$automation_dir" "enabled")"
  printf '%s\n' "$allow_self_reschedule_value" > "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")"
  printf '%s\n' "$run_mode_value" > "$(automation_field_file_for "$automation_dir" "run_mode")"
  printf '%s\n' "$assistant_mode_value" > "$(automation_field_file_for "$automation_dir" "assistant_mode_id")"
  printf '%s\n' "$compute_budget_value" > "$(automation_field_file_for "$automation_dir" "compute_budget")"
  printf '%s\n' "$command_exec_mode_value" > "$(automation_field_file_for "$automation_dir" "command_exec_mode")"
  printf '%s\n' "$permission_mode_value" > "$(automation_field_file_for "$automation_dir" "permission_mode")"
  printf '%s\n' "$programmer_review_value" > "$(automation_field_file_for "$automation_dir" "programmer_review")"
  printf '%s\n' "$programmer_review_rounds_value" > "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")"
  printf '%s\n' "$assay_task_id_value" > "$(automation_field_file_for "$automation_dir" "assay_task_id")"
}

automation_json_for_id() {
  automation_id=$1
  if ! valid_id "$automation_id"; then
    return 1
  fi
  automation_dir=$(automation_dir_for "$automation_id")
  [ -d "$automation_dir" ] || return 1

  automation_name=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "Automation")
  workspace_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")")
  conversation_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "conversation_id")" "")")
  prompt_text=$(cat "$(automation_field_file_for "$automation_dir" "prompt")" 2>/dev/null || true)
  schedule_kind=$(automation_schedule_kind_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")")
  schedule_value=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")")
  schedule_text=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_text")" "")")
  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  allow_self_reschedule_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")" "0")")
  next_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "next_run")" "0")")
  last_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_run")" "0")")
  created_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "created")" "0")")
  updated_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "updated")" "0")")
  last_status=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_status")" "")")
  last_error=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_error")" "")")
  run_mode_value=$(normalize_run_mode_name "$(read_file_line "$(automation_field_file_for "$automation_dir" "run_mode")" "assistant")")
  assistant_mode_value=$(normalize_assistant_mode_id "$(read_file_line "$(automation_field_file_for "$automation_dir" "assistant_mode_id")" "")")
  compute_budget_value=$(normalize_compute_budget "$(read_file_line "$(automation_field_file_for "$automation_dir" "compute_budget")" "auto")")
  command_exec_mode_value=$(normalize_command_exec_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "command_exec_mode")" "")")
  permission_mode_value=$(normalize_permission_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "permission_mode")" "")")
  programmer_review_value=$(normalize_programmer_review_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review")" "1")")
  programmer_review_rounds_value=$(normalize_programmer_review_rounds_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")" "2")" 2)
  assay_task_id_value=$(normalize_assay_task_id_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "assay_task_id")" "")")
  if [ "$run_mode_value" != "assistant" ]; then
    assistant_mode_value=""
  fi
  [ -n "$schedule_text" ] || schedule_text=$(automation_schedule_label "$schedule_kind" "$schedule_value")
  workspace_name=$(automation_workspace_name_for_id "$workspace_id")
  conversation_title=$(automation_conversation_title_for_ids "$workspace_id" "$conversation_id")
  explicit_skills_file=$(automation_explicit_skills_file_for "$automation_dir")
  explicit_skills_json=$(string_json_array_from_ids_file "$explicit_skills_file")
  next_run_iso=$(iso_utc_from_epoch "$next_run_epoch")
  last_run_iso=$(iso_utc_from_epoch "$last_run_epoch")
  created_iso=$(iso_utc_from_epoch "$created_epoch")
  updated_iso=$(iso_utc_from_epoch "$updated_epoch")

  printf '{"id":"%s","name":"%s","workspace_id":"%s","workspace_name":"%s","conversation_id":"%s","conversation_title":"%s","prompt":"%s","schedule_kind":"%s","schedule_value":"%s","schedule_text":"%s","enabled":"%s","allow_self_reschedule":"%s","next_run":"%s","next_run_iso":"%s","last_run":"%s","last_run_iso":"%s","last_status":"%s","last_error":"%s","created":"%s","created_iso":"%s","updated":"%s","updated_iso":"%s","run_mode":"%s","assistant_mode_id":"%s","compute_budget":"%s","command_exec_mode":"%s","permission_mode":"%s","programmer_review":"%s","programmer_review_rounds":"%s","assay_task_id":"%s","explicit_skill_ids":%s}' \
    "$(json_escape "$automation_id")" \
    "$(json_escape "$automation_name")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$workspace_name")" \
    "$(json_escape "$conversation_id")" \
    "$(json_escape "$conversation_title")" \
    "$(json_escape "$prompt_text")" \
    "$(json_escape "$schedule_kind")" \
    "$(json_escape "$schedule_value")" \
    "$(json_escape "$schedule_text")" \
    "$(json_escape "$enabled_value")" \
    "$(json_escape "$allow_self_reschedule_value")" \
    "$(json_escape "$next_run_epoch")" \
    "$(json_escape "$next_run_iso")" \
    "$(json_escape "$last_run_epoch")" \
    "$(json_escape "$last_run_iso")" \
    "$(json_escape "$last_status")" \
    "$(json_escape "$last_error")" \
    "$(json_escape "$created_epoch")" \
    "$(json_escape "$created_iso")" \
    "$(json_escape "$updated_epoch")" \
    "$(json_escape "$updated_iso")" \
    "$(json_escape "$run_mode_value")" \
    "$(json_escape "$assistant_mode_value")" \
    "$(json_escape "$compute_budget_value")" \
    "$(json_escape "$command_exec_mode_value")" \
    "$(json_escape "$permission_mode_value")" \
    "$(json_escape "$programmer_review_value")" \
    "$(json_escape "$programmer_review_rounds_value")" \
    "$(json_escape "$assay_task_id_value")" \
    "$explicit_skills_json"
}

automations_state_json() {
  items_json=""
  item_count=0
  while IFS= read -r automation_id || [ -n "$automation_id" ]; do
    [ -n "$automation_id" ] || continue
    automation_json=$(automation_json_for_id "$automation_id" 2>/dev/null || true)
    [ -n "$automation_json" ] || continue
    if [ "$item_count" -gt 0 ]; then
      items_json="${items_json},"
    fi
    items_json="${items_json}${automation_json}"
    item_count=$((item_count + 1))
  done <<EOF
$(automation_ids_sorted)
EOF
  printf '{"count":"%s","items":[%s]}' "$(json_escape "$item_count")" "$items_json"
}

automation_ensure_conversation_for_run() {
  automation_dir=$1
  workspace_id=$2
  conversation_id=$3
  automation_name=$4
  if valid_id "$workspace_id" && valid_id "$conversation_id"; then
    existing_conv=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ -d "$existing_conv" ]; then
      printf '%s' "$conversation_id"
      return 0
    fi
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 1
  fi
  if [ -z "$automation_name" ]; then
    automation_name="Automation"
  fi
  next_conversation_id=$(new_id)
  next_conv_dir=$(conversation_dir_for "$workspace_id" "$next_conversation_id")
  mkdir -p "$next_conv_dir/messages"
  printf 'Automation: %s\n' "$automation_name" > "$next_conv_dir/title"
  printf '%s\n' "$(default_model)" > "$next_conv_dir/model"
  now_epoch=$(automation_now_epoch)
  printf '%s\n' "$now_epoch" > "$next_conv_dir/created"
  printf '%s\n' "$now_epoch" > "$next_conv_dir/updated"
  printf '%s\n' "$next_conversation_id" > "$(automation_field_file_for "$automation_dir" "conversation_id")"
  printf '%s' "$next_conversation_id"
}

automation_update_next_run_for_schedule() {
  automation_dir=$1
  from_epoch=$2
  schedule_kind=$(automation_schedule_kind_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")")
  schedule_value=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")")
  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")

  if [ "$enabled_value" != "1" ]; then
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi

  schedule_info=$(automation_schedule_normalize_and_next "$schedule_kind" "$schedule_value" "$from_epoch")
  if [ "$(kv_get "status" "$schedule_info")" != "ok" ]; then
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi
  next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")
  normalized_kind=$(automation_schedule_kind_value "$(kv_get "kind" "$schedule_info")")
  normalized_value=$(trim "$(kv_get "value" "$schedule_info")")
  schedule_text=$(trim "$(kv_get "text" "$schedule_info")")
  if [ -n "$normalized_kind" ]; then
    printf '%s\n' "$normalized_kind" > "$(automation_field_file_for "$automation_dir" "schedule_kind")"
  fi
  printf '%s\n' "$normalized_value" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
  printf '%s\n' "$schedule_text" > "$(automation_field_file_for "$automation_dir" "schedule_text")"

  if [ "$normalized_kind" = "once" ]; then
    # A one-time schedule disables itself after queueing a run.
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi
  printf 'next_run=%s\nenabled=1\n' "$next_run_epoch"
}

automation_enqueue_prompt_for_run() {
  automation_id=$1
  manual_trigger=${2:-0}
  automation_dir=$(automation_dir_for "$automation_id")
  if [ ! -d "$automation_dir" ]; then
    printf 'success=0\nerror=automation not found\n'
    return 0
  fi

  workspace_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")")
  if ! valid_id "$workspace_id"; then
    printf 'success=0\nerror=invalid workspace_id\n'
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf 'success=0\nerror=workspace not found\n'
    return 0
  fi

  prompt_text=$(cat "$(automation_field_file_for "$automation_dir" "prompt")" 2>/dev/null || true)
  if [ -z "$(trim "$prompt_text")" ]; then
    printf 'success=0\nerror=prompt is required\n'
    return 0
  fi

  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  if [ "$manual_trigger" != "1" ] && [ "$enabled_value" != "1" ]; then
    printf 'success=0\nerror=automation is disabled\n'
    return 0
  fi

  automation_name=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "Automation")
  conversation_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "conversation_id")" "")")
  conversation_id=$(automation_ensure_conversation_for_run "$automation_dir" "$workspace_id" "$conversation_id" "$automation_name" || true)
  if ! valid_id "$conversation_id"; then
    printf 'success=0\nerror=could not resolve conversation\n'
    return 0
  fi
  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  if [ ! -d "$conv_dir" ]; then
    printf 'success=0\nerror=conversation not found\n'
    return 0
  fi

  run_mode_value=$(normalize_run_mode_name "$(read_file_line "$(automation_field_file_for "$automation_dir" "run_mode")" "assistant")")
  assistant_mode_value=$(normalize_assistant_mode_id "$(read_file_line "$(automation_field_file_for "$automation_dir" "assistant_mode_id")" "")")
  compute_budget_value=$(normalize_compute_budget "$(read_file_line "$(automation_field_file_for "$automation_dir" "compute_budget")" "auto")")
  command_exec_mode_value=$(normalize_command_exec_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "command_exec_mode")" "")")
  permission_mode_value=$(normalize_permission_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "permission_mode")" "")")
  programmer_review_value=$(normalize_programmer_review_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review")" "1")")
  programmer_review_rounds_value=$(normalize_programmer_review_rounds_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")" "2")" 2)
  assay_task_id_value=$(normalize_assay_task_id_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "assay_task_id")" "")")
  if [ "$run_mode_value" != "assistant" ]; then
    assistant_mode_value=""
  fi

  ensure_queue_layout "$conv_dir"
  item_id=$(new_id)
  order=$(queue_allocate_order "$conv_dir" "tail")
  queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
  queue_item_meta=$(queue_item_meta_for_path "$queue_item_file")
  printf '%s' "$prompt_text" > "$queue_item_file"

  empty_attachment_ids=$(mktemp)
  : > "$empty_attachment_ids"
  explicit_skills_file=$(automation_explicit_skills_file_for "$automation_dir")
  if [ ! -f "$explicit_skills_file" ]; then
    : > "$explicit_skills_file"
  fi
  queue_meta_write "$queue_item_meta" "$run_mode_value" "$assistant_mode_value" "$compute_budget_value" "$command_exec_mode_value" "$permission_mode_value" "$programmer_review_value" "$programmer_review_rounds_value" "$explicit_skills_file" "$empty_attachment_ids" "$assay_task_id_value" "$automation_id" "0" "0"
  rm -f "$empty_attachment_ids"

  append_message "$conv_dir" "user" "$prompt_text"

  now_epoch=$(automation_now_epoch)
  if [ "$enabled_value" = "1" ]; then
    schedule_update=$(automation_update_next_run_for_schedule "$automation_dir" "$now_epoch")
    next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next_run" "$schedule_update")")
    next_enabled=$(automation_enabled_value "$(kv_get "enabled" "$schedule_update")")
    printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
    printf '%s\n' "$next_enabled" > "$(automation_field_file_for "$automation_dir" "enabled")"
  fi
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "last_run")"
  printf '%s\n' "queued" > "$(automation_field_file_for "$automation_dir" "last_status")"
  printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"

  printf 'success=1\nworkspace_id=%s\nconversation_id=%s\nitem_id=%s\n' "$workspace_id" "$conversation_id" "$item_id"
}

automation_next_run_directive_from_text() {
  assistant_text=$1
  now_epoch=$2
  printf '%s' "$assistant_text" | python3 - "$now_epoch" <<'PY'
import datetime
import re
import sys

try:
    now_epoch = int(float(sys.argv[1]))
except Exception:
    now_epoch = 0
if now_epoch <= 0:
    now_epoch = int(datetime.datetime.now().timestamp())

text = sys.stdin.read()
matches = re.findall(r"(?im)^\s*NEXT_RUN\s*:\s*(.+?)\s*$", text or "")
if not matches:
    print("0")
    sys.exit(0)

raw = matches[-1].strip()
raw_lower = raw.lower()
if raw_lower in {"none", "disable", "disabled", "off", "never"}:
    print("-1")
    sys.exit(0)

relative = re.fullmatch(r"\+([0-9]+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks)", raw_lower)
if relative:
    amount = int(relative.group(1))
    unit = relative.group(2)
    mult = 1
    if unit.startswith("m"):
        mult = 60
    elif unit.startswith("h"):
        mult = 3600
    elif unit.startswith("d"):
        mult = 86400
    elif unit.startswith("w"):
        mult = 604800
    next_epoch = now_epoch + amount * mult
    print(str(next_epoch if next_epoch > now_epoch else 0))
    sys.exit(0)

if re.fullmatch(r"[0-9]+", raw):
    target = int(raw)
    print(str(target if target > now_epoch else 0))
    sys.exit(0)

iso_token = raw
if iso_token.endswith("Z"):
    iso_token = iso_token[:-1] + "+00:00"
for parser in ("iso",):
    try:
        dt = datetime.datetime.fromisoformat(iso_token)
        target = int(dt.timestamp()) if dt.tzinfo is None else int(dt.astimezone().timestamp())
        print(str(target if target > now_epoch else 0))
        sys.exit(0)
    except Exception:
        pass

for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"):
    try:
        dt = datetime.datetime.strptime(raw, fmt)
        target = int(dt.timestamp())
        print(str(target if target > now_epoch else 0))
        sys.exit(0)
    except Exception:
        continue

print("0")
PY
}

automation_apply_self_reschedule_for_conversation() {
  automation_id=$1
  conv_dir=$2
  if ! valid_id "$automation_id"; then
    return 0
  fi
  automation_dir=$(automation_dir_for "$automation_id")
  [ -d "$automation_dir" ] || return 0

  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  allow_self_reschedule_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")" "0")")
  if [ "$enabled_value" != "1" ] || [ "$allow_self_reschedule_value" != "1" ]; then
    return 0
  fi

  last_assistant=$(conversation_last_message_for_role "$conv_dir" "assistant")
  [ -n "$(trim "$last_assistant")" ] || return 0
  now_epoch=$(automation_now_epoch)
  directive_epoch=$(automation_next_run_directive_from_text "$last_assistant" "$now_epoch")
  case "$directive_epoch" in
    -1)
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "enabled")"
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "next_run")"
      printf '%s\n' "disabled" > "$(automation_field_file_for "$automation_dir" "last_status")"
      printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
      printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
      return 0
      ;;
    ""|*[!0-9]*)
      return 0
      ;;
  esac
  if [ "$directive_epoch" -le "$now_epoch" ]; then
    return 0
  fi
  printf '%s\n' "$directive_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
  printf '%s\n' "scheduled" > "$(automation_field_file_for "$automation_dir" "last_status")"
  printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
}

automations_tick_due_runs() {
  now_epoch=$(automation_now_epoch)
  checked=0
  triggered=0
  errors=0
  locked=1

  lock_dir="$automations_runtime_root/tick.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    locked=0
    lock_started=$(automation_epoch_or_zero "$(read_file_line "$lock_dir/started" "0")")
    if [ "$lock_started" -gt 0 ] && [ "$now_epoch" -gt "$lock_started" ] && [ $((now_epoch - lock_started)) -gt 180 ]; then
      rm -rf "$lock_dir" 2>/dev/null || true
      if mkdir "$lock_dir" 2>/dev/null; then
        locked=1
      fi
    fi
  fi

  if [ "$locked" = "1" ]; then
    printf '%s\n' "$now_epoch" > "$lock_dir/started"
    while IFS= read -r automation_id || [ -n "$automation_id" ]; do
      [ -n "$automation_id" ] || continue
      checked=$((checked + 1))
      automation_dir=$(automation_dir_for "$automation_id")
      [ -d "$automation_dir" ] || continue
      enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
      if [ "$enabled_value" != "1" ]; then
        continue
      fi
      next_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "next_run")" "0")")
      if [ "$next_run_epoch" -le 0 ]; then
        schedule_info=$(automation_schedule_normalize_and_next "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")" "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")" "$now_epoch")
        if [ "$(kv_get "status" "$schedule_info")" = "ok" ]; then
          next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")
          printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
          printf '%s\n' "$(trim "$(kv_get "value" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
          printf '%s\n' "$(trim "$(kv_get "text" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_text")"
          printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
        else
          printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "enabled")"
          printf '%s\n' "error" > "$(automation_field_file_for "$automation_dir" "last_status")"
          printf '%s\n' "$(trim "$(kv_get "error" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "last_error")"
          printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
          errors=$((errors + 1))
          continue
        fi
      fi
      if [ "$next_run_epoch" -le 0 ] || [ "$next_run_epoch" -gt "$now_epoch" ]; then
        continue
      fi
      enqueue_result=$(automation_enqueue_prompt_for_run "$automation_id" "0")
      if [ "$(kv_get "success" "$enqueue_result")" = "1" ]; then
        triggered=$((triggered + 1))
      else
        printf '%s\n' "error" > "$(automation_field_file_for "$automation_dir" "last_status")"
        printf '%s\n' "$(trim "$(kv_get "error" "$enqueue_result")")" > "$(automation_field_file_for "$automation_dir" "last_error")"
        printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
        errors=$((errors + 1))
      fi
    done <<EOF
$(automation_ids_sorted)
EOF
    rm -rf "$lock_dir" 2>/dev/null || true
  fi

  changed=0
  if [ "$triggered" -gt 0 ] || [ "$errors" -gt 0 ]; then
    changed=1
  fi
  printf 'checked=%s\ntriggered=%s\nerrors=%s\nlocked=%s\nchanged=%s\n' "$checked" "$triggered" "$errors" "$locked" "$changed"
}

artificer_runtime_site_root() {
  site_root=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/.." && pwd -P 2>/dev/null || true)
  printf '%s' "$site_root"
}

artificer_app_root_for_runtime() {
  configured_root=$(trim "${ARTIFICER_APP_ROOT:-}")
  if [ -n "$configured_root" ] && [ -d "$configured_root" ] && [ -x "$configured_root/scripts/artificer-automations.sh" ]; then
    printf '%s' "$configured_root"
    return 0
  fi

  local_root_candidate=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/../.." && pwd -P 2>/dev/null || true)
  if [ -n "$local_root_candidate" ] && [ -d "$local_root_candidate" ] && [ -x "$local_root_candidate/scripts/artificer-automations.sh" ]; then
    printf '%s' "$local_root_candidate"
    return 0
  fi

  site_root=$(artificer_runtime_site_root)
  marker_file="$site_root/.artificer-app-root"
  if [ -f "$marker_file" ]; then
    marker_root=$(trim "$(read_file_line "$marker_file" "")")
    if [ -n "$marker_root" ] && [ -d "$marker_root" ] && [ -x "$marker_root/scripts/artificer-automations.sh" ]; then
      printf '%s' "$marker_root"
      return 0
    fi
  fi

  printf ''
}

automation_daemon_script_path() {
  app_root=$(artificer_app_root_for_runtime)
  if [ -n "$app_root" ]; then
    script_path="$app_root/scripts/artificer-automations.sh"
    if [ -x "$script_path" ]; then
      printf '%s' "$script_path"
      return 0
    fi
  fi
  printf ''
}

automation_daemon_status_json_from_kv() {
  status_kv=$1
  supported_value=$(automation_enabled_value "$(kv_get "supported" "$status_kv")")
  enabled_value=$(automation_enabled_value "$(kv_get "enabled" "$status_kv")")
  active_value=$(automation_enabled_value "$(kv_get "active" "$status_kv")")
  method_value=$(trim "$(kv_get "method" "$status_kv")")
  label_value=$(trim "$(kv_get "label" "$status_kv")")
  detail_value=$(trim "$(kv_get "detail" "$status_kv")")
  [ -n "$method_value" ] || method_value="none"
  printf '{"success":true,"supported":%s,"enabled":%s,"active":%s,"method":"%s","label":"%s","detail":"%s"}\n' \
    "$([ "$supported_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$([ "$enabled_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$([ "$active_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$(json_escape "$method_value")" \
    "$(json_escape "$label_value")" \
    "$(json_escape "$detail_value")"
}
