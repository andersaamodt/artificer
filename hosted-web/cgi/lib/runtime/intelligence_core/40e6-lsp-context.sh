artificer_lsp_probe_script_path() {
  printf '%s' "$ARTIFICER_SCRIPT_DIR/../scripts/artificer-lsp-probe.py"
}

artificer_lsp_probe_available() {
  [ -x "$(artificer_lsp_probe_script_path)" ]
}

artificer_extract_existing_paths_from_text() {
  workspace_path=$1
  prompt_text=$2
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  WORKSPACE_PATH=$workspace_path PROMPT_TEXT=$prompt_text python3 - <<'PY'
import os
import re
from pathlib import Path

workspace = Path(os.environ.get("WORKSPACE_PATH", "")).expanduser().resolve()
prompt = os.environ.get("PROMPT_TEXT", "")
seen = set()
for token in re.findall(r"[A-Za-z0-9_./~-]{3,}", prompt):
    candidate = token.strip(".,:;()[]{}<>'\"`")
    if not candidate or candidate in seen:
        continue
    seen.add(candidate)
    if candidate.startswith("~/"):
        resolved = Path(candidate).expanduser()
    elif candidate.startswith("/"):
        resolved = Path(candidate)
    else:
        resolved = workspace / candidate
    try:
        resolved = resolved.resolve()
    except Exception:
        continue
    if workspace not in resolved.parents and resolved != workspace:
        if not str(resolved).startswith(str(workspace) + os.sep):
            continue
    if resolved.exists() and resolved.is_file():
        print(os.path.relpath(resolved, workspace))
PY
}

artificer_lsp_candidate_paths() {
  workspace_path=$1
  prompt_text=$2
  changed_paths_file=${3:-}
  candidate_tmp=$(mktemp)
  if [ -n "$(trim "$prompt_text")" ]; then
    artificer_extract_existing_paths_from_text "$workspace_path" "$prompt_text" > "$candidate_tmp" 2>/dev/null || true
  else
    : > "$candidate_tmp"
  fi
  if [ ! -s "$candidate_tmp" ] && [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    sed -n '1,8p' "$changed_paths_file" | while IFS= read -r rel_path; do
      rel_path=$(trim "$rel_path")
      [ -n "$rel_path" ] || continue
      [ -f "$workspace_path/$rel_path" ] || continue
      printf '%s\n' "$rel_path"
    done >> "$candidate_tmp"
  fi
  if [ ! -s "$candidate_tmp" ] && [ -d "$workspace_path/.git" ]; then
    (cd "$workspace_path" && git status --short --untracked-files=no 2>/dev/null || true) | awk '{print $2}' | sed -n '1,6p' | while IFS= read -r rel_path; do
      rel_path=$(trim "$rel_path")
      [ -n "$rel_path" ] || continue
      [ -f "$workspace_path/$rel_path" ] || continue
      printf '%s\n' "$rel_path"
    done >> "$candidate_tmp"
  fi
  awk '!seen[$0]++' "$candidate_tmp" | sed -n '1,3p'
  rm -f "$candidate_tmp"
}

artificer_lsp_probe_json_for_file() {
  workspace_path=$1
  relative_path=$2
  probe_script=$(artificer_lsp_probe_script_path)
  if [ ! -x "$probe_script" ]; then
    printf '%s' '{"success":false,"reason":"probe-unavailable"}'
    return 0
  fi
  if [ -z "$relative_path" ] || [ ! -f "$workspace_path/$relative_path" ]; then
    printf '%s' '{"success":false,"reason":"missing-file"}'
    return 0
  fi
  python3 "$probe_script" "$workspace_path" "$workspace_path/$relative_path" 2>/dev/null || printf '%s' '{"success":false,"reason":"probe-failed"}'
}

artificer_lsp_context_block() {
  workspace_path=$1
  prompt_text=$2
  changed_paths_file=${3:-}
  if ! artificer_lsp_probe_available; then
    printf '%s' 'NONE'
    return 0
  fi
  candidate_paths=$(artificer_lsp_candidate_paths "$workspace_path" "$prompt_text" "$changed_paths_file")
  [ -n "$(trim "$candidate_paths")" ] || {
    printf '%s' 'NONE'
    return 0
  }
  summary_lines=""
  while IFS= read -r relative_path; do
    relative_path=$(trim "$relative_path")
    [ -n "$relative_path" ] || continue
    probe_json=$(artificer_lsp_probe_json_for_file "$workspace_path" "$relative_path")
    summary_line=$(JSON_PAYLOAD=$probe_json python3 - <<'PY'
import json
import os
payload = os.environ.get("JSON_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)
if not data.get("success"):
    print("")
    raise SystemExit(0)
print(str(data.get("summary", "")).strip())
PY
)
    [ -n "$(trim "$summary_line")" ] || continue
    if [ -n "$summary_lines" ]; then
      summary_lines="${summary_lines}
- ${summary_line}"
    else
      summary_lines="- ${summary_line}"
    fi
  done <<EOF
$candidate_paths
EOF
  if [ -z "$(trim "$summary_lines")" ]; then
    printf '%s' 'NONE'
    return 0
  fi
  printf '%s' "$summary_lines"
}

artificer_structured_prompt_evidence_block() {
  workspace_path=$1
  prompt_text=$2
  changed_paths_file=${3:-}
  run_mode=${4:-auto}

  evidence=""
  git_status_summary=""
  if [ -d "$workspace_path/.git" ]; then
    git_status_summary=$(cd "$workspace_path" && git status --short --untracked-files=no 2>/dev/null | sed -n '1,8p' || true)
  fi
  lsp_block=$(artificer_lsp_context_block "$workspace_path" "$prompt_text" "$changed_paths_file")

  case "$run_mode" in
    programming|security-audit|pentest|report|assistant|auto)
      ;;
    *)
      if [ "$lsp_block" = "NONE" ]; then
        printf '%s' 'NONE'
        return 0
      fi
      ;;
  esac

  if [ -n "$(trim "$git_status_summary")" ]; then
    evidence="Git status snapshot:
$git_status_summary"
  fi
  if [ "$lsp_block" != "NONE" ]; then
    if [ -n "$evidence" ]; then
      evidence="${evidence}

LSP coding context:
$lsp_block"
    else
      evidence="LSP coding context:
$lsp_block"
    fi
  fi
  if [ -z "$(trim "$evidence")" ]; then
    printf '%s' 'NONE'
    return 0
  fi
  printf '%s' "$evidence"
}

artificer_code_context_action_json() {
  workspace_id=$1
  requested_path=$2
  if ! valid_workspace_id "$workspace_id"; then
    emit_error "invalid workspace_id"
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    emit_error "workspace not found"
    return 0
  fi
  workspace_path=$(read_file_line "$ws_dir/path" "")
  if [ ! -d "$workspace_path" ]; then
    emit_error "workspace path missing"
    return 0
  fi
  case "$requested_path" in
    /*)
      target_path=$requested_path
      ;;
    *)
      target_path="$workspace_path/$requested_path"
      ;;
  esac
  target_dir=$(dirname "$target_path")
  if [ ! -d "$target_dir" ]; then
    emit_error "file not found"
    return 0
  fi
  target_path=$(cd "$target_dir" && pwd -P)/$(basename "$target_path")
  case "$target_path" in
    "$workspace_path"/*)
      ;;
    *)
      emit_error "path must stay inside workspace"
      return 0
      ;;
  esac
  if [ ! -f "$target_path" ]; then
    emit_error "file not found"
    return 0
  fi
  relative_path=${target_path#"$workspace_path"/}
  probe_json=$(artificer_lsp_probe_json_for_file "$workspace_path" "$relative_path")
  printf '{"success":true,"api_version":"%s","workspace_id":"%s","path":"%s","context":%s}\n' \
    "$(json_escape "$(control_plane_api_version)")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$relative_path")" \
    "$probe_json"
}
