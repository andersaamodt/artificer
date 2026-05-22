# action: dictate_disarm
    if ! dictation_live_has_active_capture; then
      printf '{"success":true,"disarmed":false}\n'
      exit 0
    fi
    session_status=$(dictation_live_status)
    if [ "$session_status" != "prepared" ]; then
      printf '{"success":true,"disarmed":false}\n'
      exit 0
    fi
    capture_pid=$(dictation_live_session_value "pid")
    stop_capture_pid_gracefully "$capture_pid" >/dev/null 2>&1 || true
    clear_dictation_live_session
    printf '{"success":true,"disarmed":true}\n'
    exit 0
