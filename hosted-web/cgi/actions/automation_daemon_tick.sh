# action: automation_daemon_tick
    daemon_script=$(automation_daemon_script_path)
    if [ -z "$daemon_script" ] || [ ! -x "$daemon_script" ]; then
      emit_error "automation script unavailable"
      exit 0
    fi
    tick_kv=$(sh "$daemon_script" tick 2>/dev/null || true)
    if [ -z "$(trim "$tick_kv")" ]; then
      emit_error "automation daemon tick failed"
      exit 0
    fi

    checked=$(trim "$(kv_get "checked" "$tick_kv")")
    triggered=$(trim "$(kv_get "triggered" "$tick_kv")")
    errors=$(trim "$(kv_get "errors" "$tick_kv")")
    attempted=$(trim "$(kv_get "attempted" "$tick_kv")")
    processed=$(trim "$(kv_get "processed" "$tick_kv")")
    failures=$(trim "$(kv_get "failures" "$tick_kv")")
    busy=$(trim "$(kv_get "busy" "$tick_kv")")
    message=$(trim "$(kv_get "message" "$tick_kv")")

    case "$triggered" in
      ''|*[!0-9]*) triggered=0 ;;
    esac
    case "$processed" in
      ''|*[!0-9]*) processed=0 ;;
    esac
    case "$errors" in
      ''|*[!0-9]*) errors=0 ;;
    esac
    case "$failures" in
      ''|*[!0-9]*) failures=0 ;;
    esac

    if [ "$triggered" -gt 0 ] || [ "$processed" -gt 0 ] || [ "$errors" -gt 0 ] || [ "$failures" -gt 0 ]; then
      state_light_cache_invalidate
    fi

    printf '{"success":true,"busy":"%s","checked":"%s","triggered":"%s","errors":"%s","attempted":"%s","processed":"%s","failures":"%s","message":"%s","automations":%s}\n' \
      "$(json_escape "${busy:-0}")" \
      "$(json_escape "${checked:-0}")" \
      "$(json_escape "${triggered:-0}")" \
      "$(json_escape "${errors:-0}")" \
      "$(json_escape "${attempted:-0}")" \
      "$(json_escape "${processed:-0}")" \
      "$(json_escape "${failures:-0}")" \
      "$(json_escape "$message")" \
      "$(automations_state_json)"
    exit 0
