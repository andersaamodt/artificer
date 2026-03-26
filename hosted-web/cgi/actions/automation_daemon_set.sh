# action: automation_daemon_set
    enabled_raw=$(trim "$(param "enabled")")
    case "$(printf '%s' "$enabled_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on|enabled|0|false|no|off|disabled)
        ;;
      *)
        emit_error "invalid enabled value"
        exit 0
        ;;
    esac

    daemon_script=$(automation_daemon_script_path)
    if [ -z "$daemon_script" ] || [ ! -x "$daemon_script" ]; then
      emit_error "automation script unavailable"
      exit 0
    fi

    daemon_enabled=$(automation_enabled_value "$enabled_raw")
    daemon_cmd="disable"
    if [ "$daemon_enabled" = "1" ]; then
      daemon_cmd="enable"
    fi

    daemon_status_kv=$(sh "$daemon_script" "$daemon_cmd" 2>/dev/null || true)
    if [ -z "$(trim "$daemon_status_kv")" ]; then
      emit_error "automation daemon $daemon_cmd failed"
      exit 0
    fi
    automation_daemon_status_json_from_kv "$daemon_status_kv"
    exit 0
