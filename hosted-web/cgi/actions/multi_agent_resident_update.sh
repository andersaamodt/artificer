# action: multi_agent_resident_update
    workspace_id=$(trim "$(param "workspace_id")")
    resident_id=$(trim "$(param "resident_id")")
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$resident_id"; then
      emit_error "invalid resident_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    ma_workspace_init "$workspace_id"
    resident_meta_path="$(ma_workspace_residents_dir "$workspace_id")/$resident_id/meta"
    if [ ! -f "$resident_meta_path" ]; then
      seed_enabled=$(trim "$(param "enabled")")
      seed_visible=$(trim "$(param "visible")")
      seed_background=$(trim "$(param "background")")
      seed_reserve_compute=$(trim "$(param "reserve_compute")")
      seed_model=$(trim "$(param "model")")
      [ "$seed_visible" = "1" ] || seed_visible=0
      [ "$seed_background" = "0" ] || seed_background=1
      [ "$seed_reserve_compute" = "1" ] || seed_reserve_compute=0
      ma_spawn_resident "$workspace_id" "$resident_id" "$seed_visible" "$seed_background" "$seed_reserve_compute" "$seed_model"
      if [ "$seed_enabled" = "0" ]; then
        ma_update_resident_field "$workspace_id" "$resident_id" "enabled" "0" >/dev/null 2>&1 || true
      fi
    fi
    for resident_key in enabled visible background reserve_compute; do
      resident_value=$(trim "$(param "$resident_key")")
      case "$resident_value" in
        0|1)
          ma_update_resident_field "$workspace_id" "$resident_id" "$resident_key" "$resident_value" >/dev/null 2>&1 || true
          ;;
      esac
    done
    resident_model_present=$(trim "$(param "model_present")")
    resident_model=$(trim "$(param "model")")
    if [ "$resident_model_present" = "1" ] || [ -n "$resident_model" ]; then
      ma_update_resident_field "$workspace_id" "$resident_id" "model" "$resident_model" >/dev/null 2>&1 || true
    fi
    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
