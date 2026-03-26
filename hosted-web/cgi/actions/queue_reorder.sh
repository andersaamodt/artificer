# action: queue_reorder
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    item_ids_raw=$(param "item_ids")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    pending_dir=$(queue_pending_dir_for "$conv_dir")

    paths_file=$(mktemp)
    ordered_ids_file=$(mktemp)
    final_ids_file=$(mktemp)
    seen_ids_file=$(mktemp)
    trap 'rm -f "$paths_file" "$ordered_ids_file" "$final_ids_file" "$seen_ids_file"' EXIT HUP INT TERM

    queue_pending_paths_sorted "$pending_dir" > "$paths_file"
    if [ ! -s "$paths_file" ]; then
      emit_error "queue is empty"
      exit 0
    fi

    queue_item_ids_to_file "$item_ids_raw" "$ordered_ids_file"
    if [ ! -s "$ordered_ids_file" ]; then
      emit_error "item_ids is required"
      exit 0
    fi

    : > "$final_ids_file"
    : > "$seen_ids_file"

    while IFS= read -r listed_id || [ -n "$listed_id" ]; do
      [ -n "$listed_id" ] || continue
      listed_path=$(queue_find_pending_path_by_id "$pending_dir" "$listed_id")
      if [ -z "$listed_path" ] || [ ! -f "$listed_path" ]; then
        continue
      fi
      if grep -Fqx "$listed_id" "$seen_ids_file"; then
        continue
      fi
      printf '%s\n' "$listed_id" >> "$final_ids_file"
      printf '%s\n' "$listed_id" >> "$seen_ids_file"
    done < "$ordered_ids_file"

    while IFS= read -r pending_path || [ -n "$pending_path" ]; do
      [ -n "$pending_path" ] || continue
      pending_id=$(queue_item_id_from_path "$pending_path")
      [ -n "$pending_id" ] || continue
      if grep -Fqx "$pending_id" "$seen_ids_file"; then
        continue
      fi
      printf '%s\n' "$pending_id" >> "$final_ids_file"
      printf '%s\n' "$pending_id" >> "$seen_ids_file"
    done < "$paths_file"

    stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/queue-reorder.XXXXXX")
    trap 'rm -rf "$stage_dir"; rm -f "$paths_file" "$ordered_ids_file" "$final_ids_file" "$seen_ids_file"' EXIT HUP INT TERM

    while IFS= read -r pending_path || [ -n "$pending_path" ]; do
      [ -n "$pending_path" ] || continue
      [ -f "$pending_path" ] || continue
      pending_id=$(queue_item_id_from_path "$pending_path")
      [ -n "$pending_id" ] || continue
      mv "$pending_path" "$stage_dir/$pending_id.txt"
      pending_meta=$(queue_item_meta_for_path "$pending_path")
      if [ -f "$pending_meta" ]; then
        mv "$pending_meta" "$stage_dir/$pending_id.meta"
      fi
    done < "$paths_file"

    order_counter=0
    while IFS= read -r ordered_id || [ -n "$ordered_id" ]; do
      [ -n "$ordered_id" ] || continue
      staged_item="$stage_dir/$ordered_id.txt"
      [ -f "$staged_item" ] || continue
      order_counter=$((order_counter + 1))
      new_path=$(queue_item_file_for "$conv_dir" "$order_counter" "$ordered_id")
      mv "$staged_item" "$new_path"
      staged_meta="$stage_dir/$ordered_id.meta"
      if [ -f "$staged_meta" ]; then
        mv "$staged_meta" "$(queue_item_meta_for_path "$new_path")"
      fi
    done < "$final_ids_file"

    if [ "$order_counter" -gt 0 ]; then
      printf '%s\n' "1" > "$queue_dir/head"
      printf '%s\n' "$order_counter" > "$queue_dir/tail"
    else
      printf '%s\n' "0" > "$queue_dir/head"
      printf '%s\n' "0" > "$queue_dir/tail"
    fi

    queue_info=$(queue_state_for_conversation "$conv_dir")
    queue_pending=$(kv_get "pending" "$queue_info")
    queue_running=$(kv_get "running" "$queue_info")
    queue_done=$(kv_get "done" "$queue_info")
    queue_first_id=$(kv_get "first_id" "$queue_info")
    queue_last_status=$(kv_get "last_status" "$queue_info")
    [ -n "$queue_pending" ] || queue_pending=0
    [ -n "$queue_running" ] || queue_running=0
    [ -n "$queue_done" ] || queue_done=0

    printf '{"success":true,"queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$queue_pending" "$queue_running" "$queue_done" "$(json_escape "$queue_first_id")" "$(json_escape "$queue_last_status")"
    exit 0
