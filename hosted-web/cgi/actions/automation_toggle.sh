# action: automation_toggle
    automation_id=$(trim "$(param "automation_id")")
    enabled_raw=$(trim "$(param "enabled")")
    if ! valid_id "$automation_id"; then
      emit_error "invalid automation_id"
      exit 0
    fi
    case "$(printf '%s' "$enabled_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on|enabled|0|false|no|off|disabled)
        ;;
      *)
        emit_error "invalid enabled value"
        exit 0
        ;;
    esac
    automation_dir=$(automation_dir_for "$automation_id")
    if [ ! -d "$automation_dir" ]; then
      emit_error "automation not found"
      exit 0
    fi
    now_epoch=$(automation_now_epoch)
    enabled_value=$(automation_enabled_value "$enabled_raw")
    if [ "$enabled_value" = "1" ]; then
      schedule_info=$(automation_schedule_normalize_and_next "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")" "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")" "$now_epoch")
      if [ "$(kv_get "status" "$schedule_info")" != "ok" ]; then
        emit_error "$(kv_get "error" "$schedule_info")"
        exit 0
      fi
      next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")
      printf '%s\n' "$(trim "$(kv_get "value" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
      printf '%s\n' "$(trim "$(kv_get "text" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_text")"
      printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
    else
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "next_run")"
    fi
    printf '%s\n' "$enabled_value" > "$(automation_field_file_for "$automation_dir" "enabled")"
    printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
    printf '{"success":true,"automation":%s,"automations":%s}\n' "$(automation_json_for_id "$automation_id")" "$(automations_state_json)"
    exit 0
