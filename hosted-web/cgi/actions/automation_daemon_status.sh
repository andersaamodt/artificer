# action: automation_daemon_status
    daemon_script=$(automation_daemon_script_path)
    if [ -z "$daemon_script" ] || [ ! -x "$daemon_script" ]; then
      printf '{"success":true,"supported":false,"enabled":false,"active":false,"method":"none","label":"","detail":"automation script unavailable"}\n'
      exit 0
    fi
    daemon_status_kv=$(sh "$daemon_script" status-kv 2>/dev/null || true)
    if [ -z "$(trim "$daemon_status_kv")" ]; then
      printf '{"success":true,"supported":false,"enabled":false,"active":false,"method":"none","label":"","detail":"status unavailable"}\n'
      exit 0
    fi
    automation_daemon_status_json_from_kv "$daemon_status_kv"
    exit 0
