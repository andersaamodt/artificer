# action: upload_attachment
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    attachment_name=$(trim "$(param "name")")
    attachment_mime=$(trim "$(param "mime")")
    attachment_data=$(param "data")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -z "$attachment_name" ]; then
      emit_error "attachment name is required"
      exit 0
    fi
    if [ -z "$attachment_data" ]; then
      emit_error "attachment data is required"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    attachment_kind=$(attachment_kind_from_name_mime "$attachment_name" "$attachment_mime" || true)
    if [ -z "$attachment_kind" ]; then
      emit_error "unsupported attachment type"
      exit 0
    fi

    attachment_id=$(new_id)
    attachment_item_dir=$(attachment_item_dir_for "$conv_dir" "$attachment_id")
    attachment_blob="$attachment_item_dir/blob"
    attachment_meta="$attachment_item_dir/meta"
    mkdir -p "$attachment_item_dir"

    if ! base64_decode_to_file "$attachment_data" "$attachment_blob"; then
      rm -rf "$attachment_item_dir"
      emit_error "invalid attachment encoding"
      exit 0
    fi

    attachment_size=$(wc -c < "$attachment_blob" | tr -d ' ')
    [ -n "$attachment_size" ] || attachment_size=0
    max_attachment_size=$((15 * 1024 * 1024))
    if [ "$attachment_size" -gt "$max_attachment_size" ]; then
      rm -rf "$attachment_item_dir"
      emit_error "attachment exceeds 15 MB limit"
      exit 0
    fi

    {
      printf 'name=%s\n' "$attachment_name"
      printf 'mime=%s\n' "$attachment_mime"
      printf 'kind=%s\n' "$attachment_kind"
      printf 'size=%s\n' "$attachment_size"
      printf 'created=%s\n' "$(date +%s 2>/dev/null || printf '0')"
    } > "$attachment_meta"

    attachment_id_json=$(json_escape "$attachment_id")
    attachment_name_json=$(json_escape "$attachment_name")
    attachment_mime_json=$(json_escape "$attachment_mime")
    attachment_kind_json=$(json_escape "$attachment_kind")
    printf '{"success":true,"attachment":{"id":"%s","name":"%s","mime":"%s","kind":"%s","size":%s}}\n' \
      "$attachment_id_json" "$attachment_name_json" "$attachment_mime_json" "$attachment_kind_json" "$attachment_size"
    exit 0
