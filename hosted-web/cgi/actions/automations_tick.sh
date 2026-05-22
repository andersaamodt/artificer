# action: automations_tick
    tick_info=$(automations_tick_due_runs)
    if [ "$(kv_get "changed" "$tick_info")" = "1" ]; then
      state_light_cache_invalidate
    fi
    printf '{"success":true,"checked":"%s","triggered":"%s","errors":"%s","locked":"%s","automations":%s}\n' \
      "$(json_escape "$(kv_get "checked" "$tick_info")")" \
      "$(json_escape "$(kv_get "triggered" "$tick_info")")" \
      "$(json_escape "$(kv_get "errors" "$tick_info")")" \
      "$(json_escape "$(kv_get "locked" "$tick_info")")" \
      "$(automations_state_json)"
    exit 0
