ui_state_key_canonical() {
  raw_key=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_key" in
    seen_conversation_updated|workspace_order|conversation_order_by_workspace)
      printf '%s' "$raw_key"
      return 0
      ;;
    *)
      printf '%s' ""
      return 1
      ;;
  esac
}

ui_state_default_value_for_key() {
  canonical_key=$(ui_state_key_canonical "$1" || true)
  case "$canonical_key" in
    workspace_order)
      printf '%s' "[]"
      ;;
    seen_conversation_updated|conversation_order_by_workspace)
      printf '%s' "{}"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

ui_state_file_for_key() {
  canonical_key=$(ui_state_key_canonical "$1" || true)
  case "$canonical_key" in
    seen_conversation_updated)
      printf '%s/seen-conversation-updated.json' "$ui_state_dir"
      ;;
    workspace_order)
      printf '%s/workspace-order.json' "$ui_state_dir"
      ;;
    conversation_order_by_workspace)
      printf '%s/conversation-order-by-workspace.json' "$ui_state_dir"
      ;;
    *)
      printf '%s' ""
      return 1
      ;;
  esac
}

ui_state_read_value_for_key() {
  canonical_key=$(ui_state_key_canonical "$1" || true)
  if [ -z "$canonical_key" ]; then
    printf '%s' ""
    return 1
  fi
  state_file=$(ui_state_file_for_key "$canonical_key")
  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    ui_state_default_value_for_key "$canonical_key"
    return 0
  fi
  state_value=$(cat "$state_file" 2>/dev/null || true)
  if [ -z "$(printf '%s' "$state_value" | tr -d '\r\n[:space:]')" ]; then
    ui_state_default_value_for_key "$canonical_key"
    return 0
  fi
  printf '%s' "$state_value"
}

ui_state_write_value_for_key() {
  canonical_key=$(ui_state_key_canonical "$1" || true)
  next_value=$2
  if [ -z "$canonical_key" ]; then
    return 1
  fi
  case "$next_value" in
    "")
      next_value=$(ui_state_default_value_for_key "$canonical_key")
      ;;
  esac
  value_len=$(printf '%s' "$next_value" | wc -c | tr -d ' ')
  case "$value_len" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  if [ "$value_len" -gt 2097152 ]; then
    return 1
  fi
  state_file=$(ui_state_file_for_key "$canonical_key")
  if [ -z "$state_file" ]; then
    return 1
  fi
  mkdir -p "$ui_state_dir"
  tmp_file="$state_file.tmp.$$"
  printf '%s' "$next_value" > "$tmp_file"
  mv "$tmp_file" "$state_file"
  return 0
}

