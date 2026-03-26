# action: multi_agent_resident_spawn
    workspace_id=$(trim "$(param "workspace_id")")
    resident_id=$(trim "$(param "resident_id")")
    visible=$(trim "$(param "visible")")
    background=$(trim "$(param "background")")
    reserve_compute=$(trim "$(param "reserve_compute")")
    resident_model=$(trim "$(param "model")")

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
    [ "$visible" = "1" ] || visible=0
    [ "$background" = "0" ] || background=1
    [ "$reserve_compute" = "1" ] || reserve_compute=0

    ma_spawn_resident "$workspace_id" "$resident_id" "$visible" "$background" "$reserve_compute" "$resident_model"
    # Seed one structured proposal so agent-role flow is visible immediately.
    ma_new_proposal "$workspace_id" "" "$resident_id" "Agent role activated: review mandate and governance stance." "Resident" "CognitiveEnvironment" "New agent role may alter attention and escalation pressure." "1" "$resident_id" >/dev/null 2>&1 || true

    printf '{"success":true,"workspace_multi_agent":%s}\n' "$(ma_workspace_state_json "$workspace_id")"
    exit 0
