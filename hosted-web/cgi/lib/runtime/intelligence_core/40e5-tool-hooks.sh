artificer_tool_hook_log_file_path() {
  printf '%s' "${ARTIFICER_TOOL_HOOK_LOG_FILE:-}"
}

artificer_tool_hook_append_json() {
  hook_json=$1
  log_file=$(artificer_tool_hook_log_file_path)
  if [ -n "$log_file" ]; then
    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir"
    printf '%s\n' "$hook_json" >> "$log_file"
  fi
}

artificer_tool_hook_context_json() {
  workspace_path=$1
  tool_command=$2
  candidate_paths=$(artificer_lsp_candidate_paths "$workspace_path" "$tool_command" "")
  contexts_json=""
  while IFS= read -r relative_path; do
    relative_path=$(trim "$relative_path")
    [ -n "$relative_path" ] || continue
    probe_json=$(artificer_lsp_probe_json_for_file "$workspace_path" "$relative_path")
    case "$(printf '%s' "$probe_json" | sed -n 's/.*"success":\([^,}]*\).*/\1/p' | sed -n '1p')" in
      true)
        if [ -n "$contexts_json" ]; then
          contexts_json="${contexts_json},"
        fi
        contexts_json="${contexts_json}${probe_json}"
        ;;
    esac
  done <<EOF
$candidate_paths
EOF
  printf '[%s]' "$contexts_json"
}

artificer_tool_hook_pre_json() {
  workspace_id=$1
  workspace_path=$2
  original_command=$3
  normalized_command=$4
  command_mode=$5
  policy_decision=$6
  policy_source=$7
  focus_context_json=$(artificer_tool_hook_context_json "$workspace_path" "$normalized_command")
  printf '{"phase":"pre","workspace_id":"%s","command_mode":"%s","policy_decision":"%s","policy_source":"%s","original_command":"%s","normalized_command":"%s","code_context":%s}' \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$command_mode")" \
    "$(json_escape "$policy_decision")" \
    "$(json_escape "$policy_source")" \
    "$(json_escape "$original_command")" \
    "$(json_escape "$normalized_command")" \
    "$focus_context_json"
}

artificer_tool_hook_post_json() {
  workspace_id=$1
  normalized_command=$2
  status_value=$3
  output_file=$4
  output_preview=$(sed -n '1,40p' "$output_file" 2>/dev/null || true)
  printf '{"phase":"post","workspace_id":"%s","command":"%s","status":"%s","output_preview":"%s"}' \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$normalized_command")" \
    "$(json_escape "$status_value")" \
    "$(json_escape "$output_preview")"
}
