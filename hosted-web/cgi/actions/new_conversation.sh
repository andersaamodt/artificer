# action: new_conversation
    workspace_id=$(trim "$(param "workspace_id")")
    title=$(trim "$(param "title")")
    model=$(trim "$(param "model")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi

    if [ -z "$title" ]; then
      title="New Conversation"
    fi

    if [ -z "$model" ]; then
      model=$(default_model)
    fi

    conversation_id=$(new_id)
    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")

    mkdir -p "$conv_dir/messages"
    printf '%s\n' "$title" > "$conv_dir/title"
    printf '%s\n' "$model" > "$conv_dir/model"
    date +%s > "$conv_dir/created"
    date +%s > "$conv_dir/updated"

    conversation_id_json=$(json_escape "$conversation_id")
    title_json=$(json_escape "$title")
    model_json=$(json_escape "$model")

    printf '{"success":true,"conversation":{"id":"%s","title":"%s","model":"%s"}}\n' \
      "$conversation_id_json" "$title_json" "$model_json"
    exit 0
