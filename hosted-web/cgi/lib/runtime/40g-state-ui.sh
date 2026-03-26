refresh_context_memory_file() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  failures_file=$4
  assumptions_file=$5
  compliance_file=$6
  architecture_file=$7
  tasks_index_file=$8
  snapshot_text=$9
  run_mode=${10}
  memory_file=${11}

  [ -n "$memory_file" ] || return 0
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  goal_block=$(plan_section_text "$plan_file" "Goal" "Subgoals" 10)
  subgoals_block=$(plan_section_text "$plan_file" "Subgoals" "Constraints" 16)
  constraints_block=$(plan_section_text "$plan_file" "Constraints" "Unknowns" 12)
  unknowns_block=$(plan_section_text "$plan_file" "Unknowns" "Next Action" 12)
  next_action_block=$(plan_section_text "$plan_file" "Next Action" "Completion Criteria" 10)
  completion_block=$(plan_section_text "$plan_file" "Completion Criteria" "" 10)

  if [ -f "$contract_file" ]; then
    contract_block=$(sed -n '1,120p' "$contract_file")
  else
    contract_block=""
  fi
  session_signals=$(grep -E '^## ' "$session_file" 2>/dev/null | tail -n 8)
  failure_signals=$(grep -E '^(Action|Error|Next Attempt):' "$failures_file" 2>/dev/null | tail -n 12)
  assumption_signals=$(grep -E '^(Assumption|Unchecked|Constraint Risk):' "$assumptions_file" 2>/dev/null | tail -n 12)
  compliance_signals=$(grep -E 'status=|Checks:|Findings:|Required Gate:' "$compliance_file" 2>/dev/null | tail -n 14)
  hotspots=$(extract_file_hotspots "$plan_file" "$contract_file" "$session_file")
  architecture_signals=$(sed -n '1,100p' "$architecture_file" 2>/dev/null || true)
  tasks_signals=$(grep -E '^- \\[' "$tasks_index_file" 2>/dev/null | sed -n '1,16p')
  snapshot_focus=$(printf '%s\n' "$snapshot_text" | sed -n '1,80p')

  [ -n "$(trim "$goal_block")" ] || goal_block="- (pending)"
  [ -n "$(trim "$subgoals_block")" ] || subgoals_block="- (pending)"
  [ -n "$(trim "$constraints_block")" ] || constraints_block="- (none recorded)"
  [ -n "$(trim "$unknowns_block")" ] || unknowns_block="- (none recorded)"
  [ -n "$(trim "$next_action_block")" ] || next_action_block="- (pending)"
  [ -n "$(trim "$completion_block")" ] || completion_block="- (pending)"
  [ -n "$(trim "$contract_block")" ] || contract_block="(no contract captured yet)"
  [ -n "$(trim "$session_signals")" ] || session_signals="- (none yet)"
  [ -n "$(trim "$failure_signals")" ] || failure_signals="- (none yet)"
  [ -n "$(trim "$assumption_signals")" ] || assumption_signals="- (none yet)"
  [ -n "$(trim "$compliance_signals")" ] || compliance_signals="- (none yet)"
  [ -n "$(trim "$hotspots")" ] || hotspots="- (none yet)"
  [ -n "$(trim "$architecture_signals")" ] || architecture_signals="- (none yet)"
  [ -n "$(trim "$tasks_signals")" ] || tasks_signals="- (none yet)"
  [ -n "$(trim "$snapshot_focus")" ] || snapshot_focus="(snapshot unavailable)"

  case "$run_mode" in
    programming)
      mode_focus="- Preserve architecture quality and verify each step on large codebases."
      ;;
    pentest)
      mode_focus="- Drive adversarial testing with explicit exploit-path evidence and mitigation closure."
      ;;
    security-audit)
      mode_focus="- Audit security posture systematically and convert findings into verified hardening actions."
      ;;
    report)
      mode_focus="- Gather evidence, synthesize findings, and keep claims auditable."
      ;;
    text-perfecter)
      mode_focus="- Iteratively improve text and factual substance using broad evidence, contradiction checks, and convergence-based stopping."
      ;;
    gui-testing)
      mode_focus="- Execute hands-on, cross-platform GUI automation and close every UX/state-flow defect with repro-backed verification."
      ;;
    teacher)
      mode_focus="- Build learner understanding over time with adaptive teaching and spaced review cues."
      ;;
    assistant)
      mode_focus="- Drive autonomous progress with legal/ethical compliance and real-value outcomes."
      ;;
    *)
      mode_focus="- Maintain forward progress while preserving safety and correctness."
      ;;
  esac

  cat > "$memory_file" <<EOF
# Context Memory

Updated: $timestamp
Run Mode: $run_mode
Mode Focus:
$mode_focus

## Project Core
Goal:
$goal_block

Subgoals:
$subgoals_block

Constraints:
$constraints_block

Unknowns:
$unknowns_block

Next Action:
$next_action_block

Completion Criteria:
$completion_block

## Architecture Contract (Compressed)
$contract_block

## File Hotspots
$hotspots

## Recent Execution Signals
Session:
$session_signals

Failures:
$failure_signals

Assumptions:
$assumption_signals

Compliance:
$compliance_signals

## Architecture and Task Artifacts
Architecture:
$architecture_signals

Tasks:
$tasks_signals

## Snapshot Focus
$snapshot_focus
EOF
}

sanitize_state_value() {
  value=$1
  printf '%s' "$value" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

state_get() {
  state_file=$1
  key=$2
  fallback=${3:-}

  if [ ! -f "$state_file" ]; then
    printf '%s' "$fallback"
    return 0
  fi

  value=$(awk -F= -v wanted="$key" '
    $1 == wanted {
      sub(/^[^=]*=/, "")
      print
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$state_file" 2>/dev/null || true)

  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

state_set() {
  state_file=$1
  key=$2
  value=$(sanitize_state_value "$3")
  temp_file=$(mktemp)
  found=0

  if [ -f "$state_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$key="*)
          printf '%s=%s\n' "$key" "$value" >> "$temp_file"
          found=1
          ;;
        *)
          printf '%s\n' "$line" >> "$temp_file"
          ;;
      esac
    done < "$state_file"
  fi

  if [ "$found" -eq 0 ]; then
    printf '%s=%s\n' "$key" "$value" >> "$temp_file"
  fi

  mv "$temp_file" "$state_file"
}

normalize_mode() {
  mode_value=$(printf '%s' "$1" | tr 'a-z' 'A-Z')
  case "$mode_value" in
    INVESTIGATE|DESIGN|IMPLEMENT|VERIFY|DONE)
      printf '%s' "$mode_value"
      ;;
    *)
      printf '%s' "INVESTIGATE"
      ;;
  esac
}

initialize_state_file() {
  state_file=$1
  prompt_text=$2
  target_seed=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-80)
  [ -n "$target_seed" ] || target_seed="workspace"

  state_set "$state_file" "mode" "INVESTIGATE"
  state_set "$state_file" "target" "$target_seed"
  state_set "$state_file" "blocking" "none"
  state_set "$state_file" "confidence" "0.20"
  state_set "$state_file" "transition_reason" "new run"
}

mode_instructions() {
  current_mode=$1
  case "$current_mode" in
    INVESTIGATE)
      cat <<'EOF'
Mode objective:
- inspect the workspace and identify relevant files.

Mode constraints:
- do not patch files.
- run at most 3 read-only commands.
- focus on concrete evidence from tool output.
EOF
      ;;
    DESIGN)
      cat <<'EOF'
Mode objective:
- define the implementation contract before editing.

Mode constraints:
- contract must include Inputs, Outputs, Side Effects, Dependencies, Exit Codes, Invariants.
- do not patch files in this mode.
- run read-only commands only when needed.
EOF
      ;;
    IMPLEMENT)
      cat <<'EOF'
Mode objective:
- implement the contract with minimal scoped edits.

Mode constraints:
- provide a unified diff in PATCH.
- touch at most 5 files.
- keep changes focused on the requested task.
EOF
      ;;
    VERIFY)
      cat <<'EOF'
Mode objective:
- verify the implementation and determine completion.

Mode constraints:
- run verification commands only.
- if verification fails, indicate DONE_CLAIM no.
- if verification passes, indicate DONE_CLAIM yes.
EOF
      ;;
    DONE)
      cat <<'EOF'
Mode objective:
- provide final response only.
EOF
      ;;
    *)
      cat <<'EOF'
Mode objective:
- investigate safely.
EOF
      ;;
  esac
}

emit_default_verify_commands() {
  workspace_path=$1
  prompt_text=$2

  verify_script_name=$(printf '%s' "$prompt_text" | sed -n "s/.*named[[:space:]]\\([A-Za-z0-9._-]\\+\\.sh\\).*/\\1/p" | sed -n '1p')
  if [ -z "$verify_script_name" ]; then
    verify_script_name=$(printf '%s' "$prompt_text" | sed -n "s/.*file[[:space:]]\\([A-Za-z0-9._-]\\+\\.sh\\).*/\\1/p" | sed -n '1p')
  fi
  if [ -n "$verify_script_name" ] && is_safe_relative_path "$verify_script_name"; then
    printf '%s\n%s\n%s\n' "test -f $verify_script_name" "chmod +x $verify_script_name" "./$verify_script_name"
    return 0
  fi

  candidate_file=$(mktemp)
  : > "$candidate_file"
  changed_files=$(mktemp)
  : > "$changed_files"

  (cd "$workspace_path" && git diff --name-only --no-color 2>/dev/null || true) > "$changed_files"
  if [ ! -s "$changed_files" ] && [ -n "$(trim "${ARTIFICER_PROGRAMMING_CHANGED_PATHS:-}")" ]; then
    printf '%s\n' "$ARTIFICER_PROGRAMMING_CHANGED_PATHS" | sed '/^[[:space:]]*$/d' > "$changed_files"
  fi

  godot_project_file=""
  if [ -f "$workspace_path/project.godot" ]; then
    godot_project_file="project.godot"
  else
    nested_project=$(cd "$workspace_path" && find . -maxdepth 3 -type f -name 'project.godot' 2>/dev/null | sed -n '1p' | sed 's#^\./##')
    if [ -n "$nested_project" ]; then
      godot_project_file=$nested_project
    fi
  fi

  if [ -n "$godot_project_file" ]; then
    godot_project_dir=$(dirname "$godot_project_file")
    case "$godot_project_dir" in
      ""|.) godot_project_dir="." ;;
    esac
    printf '%s\n' "test -f $godot_project_file" >> "$candidate_file"
    if command -v godot >/dev/null 2>&1; then
      printf '%s\n' "godot --version" >> "$candidate_file"
      printf '%s\n' "godot --headless --path $godot_project_dir --quit" >> "$candidate_file"
    elif command -v godot4 >/dev/null 2>&1; then
      printf '%s\n' "godot4 --version" >> "$candidate_file"
      printf '%s\n' "godot4 --headless --path $godot_project_dir --quit" >> "$candidate_file"
    fi
  else
    case "$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')" in
      *godot*)
        printf '%s\n' "test -f project.godot" >> "$candidate_file"
      ;;
    esac
  fi

  prioritized_shell_test=""
  while IFS= read -r changed_rel; do
    changed_rel=$(trim "$changed_rel")
    [ -n "$changed_rel" ] || continue
    if ! is_safe_relative_path "$changed_rel"; then
      continue
    fi
    lower_changed_rel=$(printf '%s' "$changed_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_changed_rel" in
      tests/*.sh|*/tests/*.sh|*.test.sh|*_test.sh)
        prioritized_shell_test=$changed_rel
        break
        ;;
    esac
  done < "$changed_files"
  if [ -n "$prioritized_shell_test" ]; then
    printf '%s\n%s\n%s\n' \
      "test -f $prioritized_shell_test" \
      "chmod +x $prioritized_shell_test" \
      "./$prioritized_shell_test"
    rm -f "$candidate_file" "$changed_files"
    return 0
  fi

  while IFS= read -r changed_rel; do
    changed_rel=$(trim "$changed_rel")
    [ -n "$changed_rel" ] || continue
    if ! is_safe_relative_path "$changed_rel"; then
      continue
    fi

    case "$changed_rel" in
      *.sh)
        printf '%s\n' "sh -n $changed_rel" >> "$candidate_file"
        ;;
      *.py)
        if command -v python3 >/dev/null 2>&1; then
          printf '%s\n' "python3 -m py_compile $changed_rel" >> "$candidate_file"
        elif command -v python >/dev/null 2>&1; then
          printf '%s\n' "python -m py_compile $changed_rel" >> "$candidate_file"
        fi
        ;;
      *.js|*.mjs|*.cjs)
        if command -v node >/dev/null 2>&1; then
          printf '%s\n' "node --check $changed_rel" >> "$candidate_file"
        fi
        ;;
    esac
  done < "$changed_files"
  rm -f "$changed_files"

  dedup_file=$(mktemp)
  awk '!seen[$0]++' "$candidate_file" > "$dedup_file"
  count=0
  while IFS= read -r candidate; do
    candidate=$(trim "$candidate")
    [ -n "$candidate" ] || continue
    if allowed_command "$candidate"; then
      printf '%s\n' "$candidate"
      count=$((count + 1))
      if [ "$count" -ge 3 ]; then
        break
      fi
    fi
  done < "$dedup_file"
  rm -f "$candidate_file" "$dedup_file" "$changed_files"

  if [ "$count" -eq 0 ]; then
    printf '%s\n%s\n' "git status --short" "git diff --no-color"
  fi
}

auto_verify_after_patch_for_prompt() {
  workspace_id=$1
  workspace_path=$2
  prompt_text=$3
  command_mode=$4
  blocked_file=$5
  report_file=$6
  auto_verify_command_mode="all"

  : > "$report_file"
  printf 'Auto verify after patch:\n' >> "$report_file"

  command_lines_file=$(mktemp)
  emit_default_verify_commands "$workspace_path" "$prompt_text" > "$command_lines_file"
  if [ ! -s "$command_lines_file" ]; then
    printf 'No verify commands available.\n' >> "$report_file"
    rm -f "$command_lines_file"
    return 1
  fi

  ran=0
  pass=1
  while IFS= read -r command_line; do
    command_line=$(trim "$command_line")
    [ -n "$command_line" ] || continue
    ran=$((ran + 1))
    if [ "$ran" -gt 3 ]; then
      break
    fi

    tool_out=$(mktemp)
    tool_status_file=$(mktemp)
    execute_mediated_command "$workspace_id" "$workspace_path" "$command_line" "$tool_out" "$tool_status_file" "$auto_verify_command_mode" "$blocked_file"
    command_status=$(cat "$tool_status_file" 2>/dev/null || printf '%s' "failed")
    command_output=$(sed -n '1,220p' "$tool_out")

    printf 'Command: %s\nStatus: %s\nOutput:\n%s\n\n' "$command_line" "$command_status" "$command_output" >> "$report_file"
    if [ "$command_status" != "ok" ]; then
      pass=0
    fi

    rm -f "$tool_out" "$tool_status_file"
  done < "$command_lines_file"

  rm -f "$command_lines_file"

  if [ "$ran" -eq 0 ]; then
    pass=0
  fi
  [ "$pass" -eq 1 ]
}

prepare_scratch_files() {
  workspace_path=$1
  scratch_dir=$2
  files_list_file=$3

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue

    dst="$scratch_dir/$rel"
    src="$workspace_path/$rel"

    mkdir -p "$(dirname "$dst")"
    if [ -f "$src" ]; then
      cp "$src" "$dst"
    fi
  done < "$files_list_file"
}

apply_patch_with_strip_level() {
  scratch_dir=$1
  patch_file=$2
  output_file=$3
  strip_level=$4

  if command -v timeout >/dev/null 2>&1; then
    (cd "$scratch_dir" && timeout 20 patch --batch --forward -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    (cd "$scratch_dir" && gtimeout 20 patch --batch --forward -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
    return $?
  fi
  (cd "$scratch_dir" && patch --batch --forward -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
  return $?
}

apply_patch_to_scratch() {
  scratch_dir=$1
  patch_file=$2
  output_file=$3

  patch_preview=$(sed -n '1,280p' "$patch_file")
  if patch_uses_ab_prefix_paths "$patch_preview"; then
    if apply_patch_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "1"; then
      return 0
    fi
    return 1
  fi

  if apply_patch_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "0"; then
    return 0
  fi
  if apply_patch_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "1"; then
    return 0
  fi

  return 1
}

reverse_patch_dry_run_with_strip_level() {
  scratch_dir=$1
  patch_file=$2
  output_file=$3
  strip_level=$4

  if command -v timeout >/dev/null 2>&1; then
    (cd "$scratch_dir" && timeout 20 patch --batch --forward --dry-run -R -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    (cd "$scratch_dir" && gtimeout 20 patch --batch --forward --dry-run -R -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
    return $?
  fi
  (cd "$scratch_dir" && patch --batch --forward --dry-run -R -p"$strip_level" < "$patch_file") >"$output_file" 2>&1
  return $?
}

patch_already_present_in_scratch() {
  scratch_dir=$1
  patch_file=$2
  output_file=$3

  patch_preview=$(sed -n '1,280p' "$patch_file")
  if patch_uses_ab_prefix_paths "$patch_preview"; then
    reverse_patch_dry_run_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "1"
    return $?
  fi

  if reverse_patch_dry_run_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "0"; then
    return 0
  fi
  reverse_patch_dry_run_with_strip_level "$scratch_dir" "$patch_file" "$output_file" "1"
}

run_gate_checks() {
  scratch_dir=$1
  files_list_file=$2
  report_file=$3
  prompt_text=${4:-}
  workspace_path=${5:-}
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  require_godot_files=0
  has_godot_files=0
  has_godot_project=0

  case "$prompt_lower" in
    *godot*)
      require_godot_files=1
      ;;
  esac

  pass=1
  : > "$report_file"

  printf 'Gate checks:\n' >> "$report_file"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    candidate="$scratch_dir/$rel"

    if [ ! -f "$candidate" ]; then
      printf -- '- %s: missing in scratch workspace\n' "$rel" >> "$report_file"
      pass=0
      continue
    fi

    if [ ! -s "$candidate" ]; then
      printf -- '- %s: file is empty\n' "$rel" >> "$report_file"
      pass=0
      continue
    fi

    case "$rel" in
      new_file.txt|example.txt|sample.txt)
        printf -- '- %s: placeholder filename rejected\n' "$rel" >> "$report_file"
        pass=0
        continue
        ;;
    esac

    normalized_candidate=$(tr -d '\r' < "$candidate" 2>/dev/null || cat "$candidate")
    if printf '%s' "$normalized_candidate" | grep -Eq '^line 1[[:space:]]*line 2[[:space:]]*$'; then
      printf -- '- %s: placeholder content rejected\n' "$rel" >> "$report_file"
      pass=0
      continue
    fi

    case "$rel" in
      *.sh)
        syntax_err=$(mktemp)
        if sh -n "$candidate" > /dev/null 2>"$syntax_err"; then
          printf -- '- %s: sh -n passed\n' "$rel" >> "$report_file"
        else
          first_err=$(sed -n '1,4p' "$syntax_err" | tr '\n' ' ')
          printf -- '- %s: sh -n failed (%s)\n' "$rel" "$first_err" >> "$report_file"
          pass=0
        fi
        rm -f "$syntax_err"
        ;;
      *.js)
        if command -v node >/dev/null 2>&1; then
          syntax_err=$(mktemp)
          if node --check "$candidate" > /dev/null 2>"$syntax_err"; then
            printf -- '- %s: node --check passed\n' "$rel" >> "$report_file"
          else
            first_err=$(sed -n '1,4p' "$syntax_err" | tr '\n' ' ')
            printf -- '- %s: node --check failed (%s)\n' "$rel" "$first_err" >> "$report_file"
            pass=0
          fi
          rm -f "$syntax_err"
        else
          printf -- '- %s: node not available, skipped JS syntax check\n' "$rel" >> "$report_file"
        fi
        ;;
      *.py)
        if command -v python3 >/dev/null 2>&1; then
          py_cache=$(mktemp -d)
          py_err=$(mktemp)
          if PYTHONPYCACHEPREFIX="$py_cache" python3 -m py_compile "$candidate" > /dev/null 2>"$py_err"; then
            printf -- '- %s: python3 -m py_compile passed\n' "$rel" >> "$report_file"
          else
            first_err=$(sed -n '1,4p' "$py_err" | tr '\n' ' ')
            printf -- '- %s: py_compile failed (%s)\n' "$rel" "$first_err" >> "$report_file"
            pass=0
          fi
          rm -rf "$py_cache"
          rm -f "$py_err"
        else
          printf -- '- %s: python3 not available, skipped Python syntax check\n' "$rel" >> "$report_file"
        fi
        ;;
      *.gd)
        has_godot_files=1
        if grep -Eq '^[[:space:]]*(extends|class_name|func|@tool)[[:space:]]*' "$candidate"; then
          printf -- '- %s: basic GDScript structure detected\n' "$rel" >> "$report_file"
        else
          printf -- '- %s: missing basic GDScript structure (expected extends/class_name/func)\n' "$rel" >> "$report_file"
          pass=0
        fi
        ;;
      *.tscn)
        has_godot_files=1
        first_non_empty=$(sed -n '/[^[:space:]]/p' "$candidate" | sed -n '1p')
        if printf '%s\n' "$first_non_empty" | grep -q '^\[gd_scene'; then
          printf -- '- %s: valid scene header detected\n' "$rel" >> "$report_file"
        else
          printf -- '- %s: missing [gd_scene] header\n' "$rel" >> "$report_file"
          pass=0
        fi
        ;;
      */project.godot|project.godot)
        has_godot_files=1
        has_godot_project=1
        if grep -q '^\[application\]' "$candidate"; then
          printf -- '- %s: application section detected\n' "$rel" >> "$report_file"
        else
          printf -- '- %s: missing [application] section\n' "$rel" >> "$report_file"
          pass=0
        fi
        if grep -Eq '^run/main_scene[[:space:]]*=' "$candidate"; then
          printf -- '- %s: run/main_scene detected\n' "$rel" >> "$report_file"
        else
          printf -- '- %s: missing run/main_scene setting\n' "$rel" >> "$report_file"
          pass=0
        fi
        if grep -Eq '^config_version[[:space:]]*=' "$candidate"; then
          printf -- '- %s: config_version detected\n' "$rel" >> "$report_file"
        else
          printf -- '- %s: missing config_version setting\n' "$rel" >> "$report_file"
          pass=0
        fi
        ;;
      *)
        printf -- '- %s: no static rule, skipped\n' "$rel" >> "$report_file"
        ;;
    esac

    if grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$candidate" >/dev/null 2>&1; then
      printf -- '- %s: conflict markers detected\n' "$rel" >> "$report_file"
      pass=0
    fi
  done < "$files_list_file"

  if [ "$require_godot_files" -eq 1 ] && [ "$has_godot_files" -eq 0 ]; then
    printf -- '- task requires Godot artifacts, but patch touched no .gd/.tscn/project.godot files\n' >> "$report_file"
    pass=0
  fi
  if [ "$require_godot_files" -eq 1 ] && [ "$has_godot_project" -eq 0 ]; then
    workspace_has_project=0
    if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
      if find "$workspace_path" -maxdepth 3 -type f -name 'project.godot' 2>/dev/null | sed -n '1p' | grep -q '.'; then
        workspace_has_project=1
      fi
    fi
    if [ "$workspace_has_project" -ne 1 ]; then
      printf -- '- task requires a Godot project.godot file, but none was produced\n' >> "$report_file"
      pass=0
    fi
  fi

  if [ "$require_godot_files" -eq 1 ]; then
    gd_bundle_file=$(mktemp)
    : > "$gd_bundle_file"
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "$rel" in
        *.gd)
          if [ -f "$scratch_dir/$rel" ]; then
            cat "$scratch_dir/$rel" >> "$gd_bundle_file"
            printf '\n' >> "$gd_bundle_file"
          fi
          ;;
      esac
    done < "$files_list_file"
    gd_lower=$(tr '[:upper:]' '[:lower:]' < "$gd_bundle_file" 2>/dev/null || true)
    rm -f "$gd_bundle_file"

    if printf '%s' "$prompt_lower" | grep -Eq 'pause|resume|reset|slider|time scale|gravitational constant|sandbox'; then
      if printf '%s' "$gd_lower" | grep -Eq 'pause|resume|reset|slider|hslider|time_scale|gravity_constant'; then
        printf -- '- godot semantic check: ui controls detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested ui controls (pause/resume/reset/sliders)\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'collision|merge'; then
      if printf '%s' "$gd_lower" | grep -Eq 'collision|merge'; then
        printf -- '- godot semantic check: collision/merge logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested collision/merge logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'camera|pan|zoom'; then
      if printf '%s' "$gd_lower" | grep -Eq 'camera2d|camera|pan|zoom'; then
        printf -- '- godot semantic check: camera pan/zoom controls detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested camera pan/zoom controls\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'hud|fps|energy'; then
      if printf '%s' "$gd_lower" | grep -Eq 'hud|fps|energy'; then
        printf -- '- godot semantic check: hud/fps/energy logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested hud/fps/energy logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '5\\+|at least[[:space:]]+5([^0-9]|$)|(^|[^[:alpha:]])five([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([5-9]|1[0-9])|start_planets[[:space:]]*=[[:space:]]*([5-9]|1[0-9])'; then
        printf -- '- godot semantic check: 5+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 5+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '8\\+|at least[[:space:]]+8([^0-9]|$)|(^|[^[:alpha:]])eight([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(8|9|1[0-9])|start_planets[[:space:]]*=[[:space:]]*(8|9|1[0-9])'; then
        printf -- '- godot semantic check: 8+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 8+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '10\\+|at least[[:space:]]+10([^0-9]|$)|(^|[^[:alpha:]])ten([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(10|1[1-9])|start_planets[[:space:]]*=[[:space:]]*(10|1[1-9])'; then
        printf -- '- godot semantic check: 10+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 10+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '14\\+|at least[[:space:]]+14([^0-9]|$)|14[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])fourteen([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(1[4-9]|[2-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(1[4-9]|[2-9][0-9])'; then
        printf -- '- godot semantic check: 14+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 14+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '20\\+|at least[[:space:]]+20([^0-9]|$)|20[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])twenty([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(2[0-9]|[3-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(2[0-9]|[3-9][0-9])'; then
        printf -- '- godot semantic check: 20+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 20+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '30\\+|at least[[:space:]]+30([^0-9]|$)|30[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])thirty([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(3[0-9]|[4-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(3[0-9]|[4-9][0-9])'; then
        printf -- '- godot semantic check: 30+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 30+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '40\\+|at least[[:space:]]+40([^0-9]|$)|40[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])forty([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(4[0-9]|[5-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(4[0-9]|[5-9][0-9])'; then
        printf -- '- godot semantic check: 40+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 40+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '60\\+|at least[[:space:]]+60([^0-9]|$)|60[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])sixty([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])'; then
        printf -- '- godot semantic check: 60+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 60+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq '80\\+|at least[[:space:]]+80([^0-9]|$)|80[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])eighty([^[:alpha:]]|$)'; then
      if printf '%s' "$gd_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])'; then
        printf -- '- godot semantic check: 80+ planet setup detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing explicit 80+ planet setup\n' >> "$report_file"
        pass=0
      fi
    fi

    requested_planet_min=$(godot_requested_planet_min_from_prompt "$prompt_lower")
    if [ -n "$requested_planet_min" ] && [ "$requested_planet_min" -ge 5 ]; then
      actual_start_planets=$(godot_start_planets_value_from_text "$gd_lower")
      if [ -n "$actual_start_planets" ] && [ "$actual_start_planets" -ge "$requested_planet_min" ]; then
        printf -- '- godot semantic check: dynamic planet threshold met (%s requested, %s found)\n' "$requested_planet_min" "$actual_start_planets" >> "$report_file"
      else
        printf -- '- godot semantic check: dynamic planet threshold not met (%s requested, %s found)\n' "$requested_planet_min" "${actual_start_planets:-none}" >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'click|spawn'; then
      if printf '%s' "$gd_lower" | grep -Eq 'spawn|mouse_button_left|inputeventmousebutton'; then
        printf -- '- godot semantic check: click-to-spawn logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested click/spawn logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'gameplay|fun|interactiv|challenge|objective|score|combo|win|lose'; then
      if printf '%s' "$gd_lower" | grep -Eq 'gameplay_mode|challenge_active|challenge_score|challenge_label|_sample_challenge_score|set_gameplay_mode'; then
        printf -- '- godot semantic check: gameplay/challenge objective systems detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested gameplay/challenge objective systems\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'ability|abilities|power[- ]?up|special move|shockwave|cooldown'; then
      if printf '%s' "$gd_lower" | grep -Eq 'shockwave|cooldown|_trigger_shockwave|on_shockwave_pressed'; then
        printf -- '- godot semantic check: interactive ability/cooldown systems detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested interactive ability/cooldown systems\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'polish|juic|juice|feel|visual feedback|fx|effects|presentation'; then
      if printf '%s' "$gd_lower" | grep -Eq 'background_stars|draw_background|draw_arc|challenge_message|visual_time|autowrap'; then
        printf -- '- godot semantic check: visual/polish feedback systems detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested visual/polish feedback systems\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'right[- ]click|delete|remove planet'; then
      if printf '%s' "$gd_lower" | grep -Eq 'mouse_button_right' && printf '%s' "$gd_lower" | grep -Eq 'delete|remove_at|erase'; then
        printf -- '- godot semantic check: right-click delete logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested right-click delete logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'adaptive|time[ -]?step|timestep'; then
      if printf '%s' "$gd_lower" | grep -Eq 'adaptive|effective_step|step_seconds'; then
        printf -- '- godot semantic check: adaptive timestep logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested adaptive timestep logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'deterministic|seed'; then
      if printf '%s' "$gd_lower" | grep -Eq 'seed|randomnumbergenerator|rng|lineedit|apply_seed'; then
        printf -- '- godot semantic check: deterministic seed control detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested deterministic seed control\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'step once|single step|advance one tick|one tick'; then
      if printf '%s' "$gd_lower" | grep -Eq 'step_once|step once|step_once_delta'; then
        printf -- '- godot semantic check: step-once control detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested step-once control\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'merge toggle|collision/merge toggle|collision toggle|toggle merge'; then
      if printf '%s' "$gd_lower" | grep -Eq 'merge_enabled|toggle_merge|merge:'; then
        printf -- '- godot semantic check: merge toggle detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested merge toggle\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'velocity[- ]vectors?|vectors toggle|velocity arrows?'; then
      if printf '%s' "$gd_lower" | grep -Eq 'show_velocity_vectors|toggle_vectors|velocity_vector|vectors:'; then
        printf -- '- godot semantic check: velocity vector toggle detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested velocity vector toggle\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'center of mass|centre of mass|com marker'; then
      if printf '%s' "$gd_lower" | grep -Eq 'center_of_mass' && printf '%s' "$gd_lower" | grep -Eq 'draw_circle|draw_line'; then
        printf -- '- godot semantic check: center-of-mass marker logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested center-of-mass marker logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'total momentum|momentum.*(readout|display|hud|on-screen|onscreen)'; then
      if printf '%s' "$gd_lower" | grep -Eq '_total_system_momentum|momentum:'; then
        printf -- '- godot semantic check: momentum readout logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested momentum readout logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'trail|toggle'; then
      if printf '%s' "$gd_lower" | grep -Eq 'trail'; then
        printf -- '- godot semantic check: trail controls detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested trail controls\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'clear[- ]?trails?|clear trails button'; then
      if printf '%s' "$gd_lower" | grep -Eq 'clear_trails|clear trails'; then
        printf -- '- godot semantic check: clear-trails control detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested clear-trails control\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'integrator|leapfrog|euler|symplectic'; then
      if printf '%s' "$gd_lower" | grep -Eq 'integrator|leapfrog|euler|optionbutton|item_selected'; then
        printf -- '- godot semantic check: integrator selection logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested integrator selection logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'rk4|runge-kutta'; then
      if printf '%s' "$gd_lower" | grep -Eq 'rk4|runge|integratormode'; then
        printf -- '- godot semantic check: RK4 integrator support detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested RK4 integrator support\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'softening'; then
      if printf '%s' "$gd_lower" | grep -Eq 'softening' && printf '%s' "$gd_lower" | grep -Eq 'slider|hslider|on_softening'; then
        printf -- '- godot semantic check: adjustable softening control detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested adjustable softening control\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'click[- ]drag|drag[- ]spawn|velocity preview|drag.*preview|click and drag'; then
      if printf '%s' "$gd_lower" | grep -Eq 'drag_spawn|inputeventmousemotion|mousemotion|draw_drag|preview_velocity|drag_current'; then
        printf -- '- godot semantic check: click-drag spawn preview logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested click-drag spawn preview logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'angular momentum|\\blz\\b'; then
      if printf '%s' "$gd_lower" | grep -Eq 'angular_momentum|_total_system_angular_momentum|\\blz\\b'; then
        printf -- '- godot semantic check: angular momentum readout detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested angular momentum readout\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'energy drift|drift from initial|delta energy|\\bde\\b'; then
      if printf '%s' "$gd_lower" | grep -Eq 'energy_drift|initial_total_energy|drift_pct|drift'; then
        printf -- '- godot semantic check: energy drift readout detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested energy drift readout\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'telemetry|export csv|csv export|continuous telemetry|time, energy'; then
      if printf '%s' "$gd_lower" | grep -Eq 'telemetry|csv|export_telemetry|store_line|fileaccess'; then
        printf -- '- godot semantic check: telemetry capture/csv export logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested telemetry capture/csv export logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'record|replay|input events|event log|deterministic replay'; then
      if printf '%s' "$gd_lower" | grep -Eq 'record|replay|replay_events|record_events|replay_path|_start_replay|_toggle_recording' && printf '%s' "$gd_lower" | grep -Eq 'json|fileaccess'; then
        printf -- '- godot semantic check: record/replay event-log logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested record/replay event-log logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'benchmark|benchmark integrators|benchmark_results|energy drift percent|simulated_seconds'; then
      if printf '%s' "$gd_lower" | grep -Eq 'benchmark|benchmark_results|run_benchmark|benchmark_path|_run_integrator_benchmark' && printf '%s' "$gd_lower" | grep -Eq 'csv|store_line|fileaccess'; then
        printf -- '- godot semantic check: benchmark csv export logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested benchmark csv export logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'barnes[- ]?hut|theta|approximation mode|n[[:space:]]*log[[:space:]]*n|quadtree'; then
      if printf '%s' "$gd_lower" | grep -Eq 'barnes|bhnode|quadtree|theta|force_mode|_accelerations_barnes_hut'; then
        printf -- '- godot semantic check: Barnes-Hut/theta approximation logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested Barnes-Hut/theta approximation logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'checksum|hash|digest'; then
      if printf '%s' "$gd_lower" | grep -Eq 'checksum|sha256|mismatch|replay_checksum|validate' && printf '%s' "$gd_lower" | grep -Eq 'json|fileaccess'; then
        printf -- '- godot semantic check: checksum validation logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested checksum validation logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'final[ -]?state checksum|end[ -]?state checksum|state checksum'; then
      if printf '%s' "$gd_lower" | grep -Eq 'final_state_checksum|state_checksum_for_snapshot|final-mismatch|ok\\+final'; then
        printf -- '- godot semantic check: final-state checksum replay validation logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested final-state checksum replay validation logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'self[- ]?tests?|regression|regression_report|validation suite'; then
      if printf '%s' "$gd_lower" | grep -Eq 'self_test|run_self_tests|regression_report|report_path' && printf '%s' "$gd_lower" | grep -Eq 'json|fileaccess'; then
        printf -- '- godot semantic check: built-in regression self-test/report logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested regression self-test/report logic\n' >> "$report_file"
        pass=0
      fi
    fi

    if printf '%s' "$prompt_lower" | grep -Eq 'save|load|json|preset'; then
      if printf '%s' "$gd_lower" | grep -Eq 'save|load|json|fileaccess|preset'; then
        printf -- '- godot semantic check: save/load preset logic detected\n' >> "$report_file"
      else
        printf -- '- godot semantic check: missing requested save/load preset logic\n' >> "$report_file"
        pass=0
      fi
    fi
  fi

  [ "$pass" -eq 1 ]
}

diff_scratch_vs_workspace() {
  workspace_path=$1
  scratch_dir=$2
  files_list_file=$3
  diff_file=$4

  : > "$diff_file"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue

    src="$workspace_path/$rel"
    patched="$scratch_dir/$rel"

    left="$src"
    right="$patched"

    if [ ! -f "$left" ]; then
      left="/dev/null"
    fi
    if [ ! -f "$right" ]; then
      right="/dev/null"
    fi

    diff -u "$left" "$right" >> "$diff_file" 2>/dev/null || true
  done < "$files_list_file"
}

promote_scratch_files() {
  scratch_dir=$1
  workspace_path=$2
  files_list_file=$3
  report_file=$4

  : > "$report_file"
  printf 'Promotion:\n' >> "$report_file"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue

    src="$scratch_dir/$rel"
    dst="$workspace_path/$rel"

    if [ ! -f "$src" ]; then
      printf -- '- %s: missing scratch file (cannot promote)\n' "$rel" >> "$report_file"
      return 1
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    if [ -f "$dst" ] && sed -n '1p' "$src" | grep -q '^#!'; then
      chmod +x "$dst" 2>/dev/null || true
    fi
    printf -- '- %s: promoted\n' "$rel" >> "$report_file"
  done < "$files_list_file"

  return 0
}

state_light_cache_ttl_sec() {
  ttl_raw=${ARTIFICER_STATE_LIGHT_CACHE_TTL_SEC:-6}
  case "$ttl_raw" in
    ""|*[!0-9]*)
      ttl_raw=6
      ;;
  esac
  if [ "$ttl_raw" -lt 1 ]; then
    ttl_raw=1
  fi
  if [ "$ttl_raw" -gt 120 ]; then
    ttl_raw=120
  fi
  printf '%s' "$ttl_raw"
}

state_light_current_revision() {
  revision=$(read_file_line "$state_revision_file" "0")
  case "$revision" in
    ""|*[!0-9]*)
      revision=0
      ;;
  esac
  printf '%s' "$revision"
}

state_light_cache_invalidate() {
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  previous_revision=$(state_light_current_revision)
  if [ "$now_epoch" -le "$previous_revision" ]; then
    now_epoch=$((previous_revision + 1))
  fi
  printf '%s\n' "$now_epoch" > "$state_revision_file"
  rm -f "$state_light_cache_file" "$state_light_cache_revision_file" 2>/dev/null || true
}

state_light_cache_valid_for_revision() {
  expected_revision=$1
  [ -s "$state_light_cache_file" ] || return 1
  [ -f "$state_light_cache_revision_file" ] || return 1
  if ! grep -q '"state_revision":"' "$state_light_cache_file" 2>/dev/null; then
    return 1
  fi

  cached_revision=$(read_file_line "$state_light_cache_revision_file" "")
  case "$cached_revision" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  case "$expected_revision" in
    ""|*[!0-9]*)
      expected_revision=0
      ;;
  esac
  if [ "$cached_revision" != "$expected_revision" ]; then
    return 1
  fi

  cache_mtime=$(file_mtime_epoch "$state_light_cache_file")
  case "$cache_mtime" in
    ""|*[!0-9]*)
      cache_mtime=0
      ;;
  esac
  if [ "$cache_mtime" -le 0 ]; then
    return 1
  fi

  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  cache_age=$((now_epoch - cache_mtime))
  if [ "$cache_age" -lt 0 ]; then
    cache_age=0
  fi
  cache_ttl=$(state_light_cache_ttl_sec)
  if [ "$cache_age" -gt "$cache_ttl" ]; then
    return 1
  fi
  return 0
}

state_action_mutates_light_state() {
  case "$1" in
    add_workspace|delete_workspace|rename_workspace|archive_conversation|new_conversation|set_model|save_draft|queue_enqueue|queue_update|queue_reorder|queue_take|queue_finish|queue_cancel|queue_stop|queue_steer|approval_answer|decision_answer|run|automation_upsert|automation_delete|automation_toggle|automation_run_now|automations_tick|automation_daemon_tick)
      return 0
      ;;
  esac
  return 1
}

emit_state() {
  # Keep the primary state endpoint fast; mode runtime has dedicated endpoints.
  state_level=$(trim "$(param "level")")
  cached_pref=$(trim "$(param "cached")")
  case "$cached_pref" in
    ""|*[!0-9]*)
      cached_pref=1
      ;;
  esac
  state_light=0
  if [ "$state_level" = "light" ]; then
    state_light=1
  fi
  automations_tick_info=$(automations_tick_due_runs)
  if [ "$(kv_get "changed" "$automations_tick_info")" = "1" ]; then
    state_light_cache_invalidate
  fi
  cache_revision_snapshot=$(state_light_current_revision)
  state_revision_json=$(json_escape "$cache_revision_snapshot")
  if [ "$state_light" = "1" ] && [ "$cached_pref" -ne 0 ] && state_light_cache_valid_for_revision "$cache_revision_snapshot"; then
    cat "$state_light_cache_file"
    return
  fi

  state_cache_tmp=""
  if [ "$state_light" = "1" ]; then
    state_cache_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-state-light.XXXXXX")
    exec 3>&1
    exec > "$state_cache_tmp"
  fi

  printf '{"success":true,"state_revision":"%s","workspaces":[' "$state_revision_json"
  first_ws=1

  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    ws_id=$(basename "$ws_dir")
    ws_name=$(read_file_line "$ws_dir/name" "$ws_id")
    ws_path=$(read_file_line "$ws_dir/path" "")
    ws_path_exists=0
    if [ -n "$ws_path" ] && [ -d "$ws_path" ]; then
      ws_path_exists=1
    fi
    draft_file="$ws_dir/draft-first-message.txt"
    draft_exists=0
    if [ -s "$draft_file" ]; then
      draft_exists=1
    fi

    ws_id_json=$(json_escape "$ws_id")
    ws_name_json=$(json_escape "$ws_name")
    ws_path_json=$(json_escape "$ws_path")
    ws_path_exists_json=$(json_escape "$ws_path_exists")
    draft_exists_json=$(json_escape "$draft_exists")

    if [ "$first_ws" -eq 0 ]; then
      printf ','
    fi
    first_ws=0

    ws_bg_residents=0
    ws_residents_json='[]'
    ws_unratified_json='[]'
    ws_toggles_json='{"context_sharing":1,"dilemma_surfacing":1,"amendments":1,"interpretation_log":1,"commitments":1,"attention_policies":1}'
    if [ "$state_light" != "1" ] && command -v ma_workspace_init >/dev/null 2>&1; then
      ma_workspace_init "$ws_id"
      ws_bg_residents=$(ma_workspace_background_resident_count "$ws_id")
      ws_residents_json=$(ma_residents_json_for_workspace "$ws_id")
      ws_unratified_json=$(ma_workspace_unratified_amendments_json "$ws_id")
      ws_toggles_json=$(cat <<EOF_TOG
{"context_sharing":$(ma_toggle_value "$ws_id" "context_sharing" 1),"dilemma_surfacing":$(ma_toggle_value "$ws_id" "dilemma_surfacing" 1),"amendments":$(ma_toggle_value "$ws_id" "amendments" 1),"interpretation_log":$(ma_toggle_value "$ws_id" "interpretation_log" 1),"commitments":$(ma_toggle_value "$ws_id" "commitments" 1),"attention_policies":$(ma_toggle_value "$ws_id" "attention_policies" 1)}
EOF_TOG
)
    fi

    printf '{"id":"%s","name":"%s","path":"%s","path_exists":"%s","draft_exists":"%s","multi_agent_background_residents":"%s","multi_agent_residents":%s,"multi_agent_unratified_amendments":%s,"multi_agent_toggles":%s,"conversations":[' \
      "$ws_id_json" "$ws_name_json" "$ws_path_json" "$ws_path_exists_json" "$draft_exists_json" "$(json_escape "$ws_bg_residents")" "$ws_residents_json" "$ws_unratified_json" "$ws_toggles_json"

    first_conv=1
    conv_parent="$ws_dir/conversations"
    if [ -d "$conv_parent" ]; then
      for conv_dir in "$conv_parent"/*; do
        [ -d "$conv_dir" ] || continue
        conv_id=$(basename "$conv_dir")
        conv_title=$(read_file_line "$conv_dir/title" "Conversation")
        conv_model=$(read_file_line "$conv_dir/model" "")
        conv_created=$(read_file_line "$conv_dir/created" "0")
        conv_updated=$(read_file_line "$conv_dir/updated" "0")
        if [ "$state_light" = "1" ]; then
          queue_info=$(queue_state_for_conversation_light "$conv_dir")
          queue_pending=$(kv_get "pending" "$queue_info")
          queue_running=$(kv_get "running" "$queue_info")
          queue_done=$(kv_get "done" "$queue_info")
          queue_last_status=$(kv_get "last_status" "$queue_info")
          queue_first_id=$(kv_get "first_id" "$queue_info")
          [ -n "$queue_pending" ] || queue_pending=0
          [ -n "$queue_running" ] || queue_running=0
          [ -n "$queue_done" ] || queue_done=0
          decision_request_json='null'
          approval_request_json='null'
        else
          queue_info=$(queue_state_for_conversation "$conv_dir")
          queue_pending=$(kv_get "pending" "$queue_info")
          queue_running=$(kv_get "running" "$queue_info")
          queue_done=$(kv_get "done" "$queue_info")
          queue_last_status=$(kv_get "last_status" "$queue_info")
          queue_first_id=$(kv_get "first_id" "$queue_info")
          stale_error_message=""
          if [ "$queue_running" = "1" ]; then
            stale_error_message=$(queue_running_stale_reason_for_conversation "$conv_dir")
          fi
          if [ "$ws_path_exists" != "1" ] && [ "$queue_running" = "1" ]; then
            stale_error_message="workspace path is missing or unavailable"
          fi
          if [ -n "$stale_error_message" ]; then
            queue_recover_stale_running_state_for_conversation "$conv_dir" "$stale_error_message" >/dev/null 2>&1 || true
            queue_info=$(queue_state_for_conversation "$conv_dir")
            queue_pending=$(kv_get "pending" "$queue_info")
            queue_running=$(kv_get "running" "$queue_info")
            queue_done=$(kv_get "done" "$queue_info")
            queue_last_status=$(kv_get "last_status" "$queue_info")
            queue_first_id=$(kv_get "first_id" "$queue_info")
          fi
          decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
          approval_request_json=$(approval_request_json_for_conversation "$conv_dir")

          [ -n "$queue_pending" ] || queue_pending=0
          [ -n "$queue_running" ] || queue_running=0
          [ -n "$queue_done" ] || queue_done=0
        fi

        conv_id_json=$(json_escape "$conv_id")
        conv_title_json=$(json_escape "$conv_title")
        conv_model_json=$(json_escape "$conv_model")
        conv_created_json=$(json_escape "$conv_created")
        conv_updated_json=$(json_escape "$conv_updated")
        queue_pending_json=$(json_escape "$queue_pending")
        queue_running_json=$(json_escape "$queue_running")
        queue_done_json=$(json_escape "$queue_done")
        queue_last_status_json=$(json_escape "$queue_last_status")
        queue_first_id_json=$(json_escape "$queue_first_id")

        if [ "$first_conv" -eq 0 ]; then
          printf ','
        fi
        first_conv=0
        printf '{"id":"%s","title":"%s","model":"%s","created":"%s","updated":"%s","queue_pending":"%s","queue_running":"%s","queue_done":"%s","queue_last_status":"%s","queue_first_id":"%s","decision_request":%s,"approval_request":%s}' \
          "$conv_id_json" "$conv_title_json" "$conv_model_json" "$conv_created_json" "$conv_updated_json" "$queue_pending_json" "$queue_running_json" "$queue_done_json" "$queue_last_status_json" "$queue_first_id_json" "$decision_request_json" "$approval_request_json"
      done
    fi

    printf ']}'
  done

  printf ']'
  if [ "$state_light" = "1" ]; then
    printf ',"triage":{"count":"0","cards":[]}'
    printf ',"multi_agent_catalog":{"curated_residents":[],"target_types":[],"escalation_classes":[]}'
  elif command -v ma_triage_cards_json >/dev/null 2>&1; then
    triage_cards_json=$(ma_triage_cards_json)
    triage_count=$(printf '%s\n' "$triage_cards_json" | perl -MJSON::PP -e 'use strict; use warnings; local $/; my $raw=<STDIN>; my $data = eval { decode_json($raw) }; if ($@ || ref($data) ne "ARRAY") { print 0; exit 0; } print scalar(@$data);' 2>/dev/null || printf '0')
    printf ',"triage":{"count":"%s","cards":%s}' "$(json_escape "$triage_count")" "$triage_cards_json"
    printf ',"multi_agent_catalog":{"curated_residents":%s,"target_types":%s,"escalation_classes":%s}' \
      "$(ma_curated_residents_json)" \
      "$(ma_target_type_enum_json)" \
      "$(ma_escalation_class_enum_json)"
  fi
  printf ',"automations":%s' "$(automations_state_json)"
  printf '}\n'

  if [ "$state_light" = "1" ] && [ -n "$state_cache_tmp" ]; then
    exec >&3
    exec 3>&-
    cat "$state_cache_tmp"
    cache_revision_end=$(state_light_current_revision)
    if [ "$cache_revision_snapshot" = "$cache_revision_end" ]; then
      mv "$state_cache_tmp" "$state_light_cache_file" 2>/dev/null || {
        cp "$state_cache_tmp" "$state_light_cache_file" 2>/dev/null || true
        rm -f "$state_cache_tmp"
      }
      printf '%s\n' "$cache_revision_snapshot" > "$state_light_cache_revision_file"
    else
      rm -f "$state_cache_tmp"
    fi
  fi
}

emit_models() {
  models=$(list_models_raw)
  if [ -z "$(trim "$models")" ]; then
    models=$(list_models_from_workspace_data)
  fi

  printf '{"success":true,"models":['
  first=1
  if [ -n "$models" ]; then
    while IFS= read -r model; do
      [ -n "$model" ] || continue
      model_json=$(json_escape "$model")
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '"%s"' "$model_json"
    done <<EOF
$models
EOF
  fi
  printf ']}\n'
}

artificer_curated_available_models() {
  cat <<'EOF'
deepseek-r1:70b|DeepSeek-R1 70B reasoning model for strongest general-purpose quality (high RAM/VRAM required)|43|128
EOF
}

merge_available_model_entries() {
  curated_entries=$1
  upstream_entries=$2
  printf '%s\n%s\n' "$curated_entries" "$upstream_entries" | awk -F'|' '
    {
      line = $0
      if (line ~ /^[[:space:]]*$/) {
        next
      }
      name = $1
      gsub(/^[[:space:]]+/, "", name)
      gsub(/[[:space:]]+$/, "", name)
      if (name == "" || seen[name]) {
        next
      }
      seen[name] = 1
      print line
    }
  '
}

emit_model_catalog() {
  installed=$(run_ai_dev_script list-installed-llms 2>/dev/null || true)
  available=$(run_ai_dev_script list-available-llms 2>/dev/null || true)
  curated_available=$(artificer_curated_available_models)
  available=$(merge_available_model_entries "$curated_available" "$available")

  if [ -z "$(trim "$installed")" ]; then
    installed=$(list_models_raw || true)
  fi

  printf '{"success":true,"installed":['
  first=1
  if [ -n "$installed" ]; then
    while IFS= read -r model; do
      [ -n "$model" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '"%s"' "$(json_escape "$model")"
    done <<EOF
$installed
EOF
  fi
  printf '],"available":['

  first=1
  if [ -n "$available" ]; then
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      model_name=$(printf '%s' "$entry" | awk -F'|' '{print $1}')
      description=$(printf '%s' "$entry" | awk -F'|' '{print $2}')
      size_gb=$(printf '%s' "$entry" | awk -F'|' '{print $3}')
      context_k=$(printf '%s' "$entry" | awk -F'|' '{print $4}')
      case "$size_gb" in
        ""|*[!0-9.]*)
          size_gb=""
          ;;
      esac
      case "$context_k" in
        ""|*[!0-9]*)
          context_k=""
          ;;
      esac
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"name":"%s","description":"%s","size_gb":"%s","context_k":"%s"}' \
        "$(json_escape "$model_name")" \
        "$(json_escape "$description")" \
        "$(json_escape "$size_gb")" \
        "$(json_escape "$context_k")"
    done <<EOF
$available
EOF
  fi
  printf '],"installs":'
  emit_model_installs_json
  printf '}\n'
}

emit_themes() {
  app_theme_dir="$ARTIFICER_SCRIPT_DIR/../static/themes"
  repo_theme_root=""
  global_theme_root=""
  wizardry_theme_root=""
  themes=""

  if repo_root=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/../../.." 2>/dev/null && pwd); then
    repo_theme_root="$repo_root/web/.themes"
  fi

  if [ -n "${WIZARDRY_APPS_ROOT-}" ] && [ -d "$WIZARDRY_APPS_ROOT/web/.themes" ]; then
    global_theme_root="$WIZARDRY_APPS_ROOT/web/.themes"
  fi

  wizardry_theme_root="$WIZARDRY_DIR/web/.themes"

  mkdir -p "$app_theme_dir"
  for theme_root in "$global_theme_root" "$repo_theme_root" "$wizardry_theme_root"; do
    [ -n "$theme_root" ] || continue
    [ -d "$theme_root" ] || continue
    cp -f "$theme_root"/*.css "$app_theme_dir/" 2>/dev/null || true
  done

  if [ -d "$app_theme_dir" ]; then
    themes=$(find "$app_theme_dir" -maxdepth 1 -type f -name '*.css' 2>/dev/null \
      | awk -F/ '{ print $NF }' \
      | sed 's/\.css$//' \
      | awk '/^[a-z0-9_-]+$/' \
      | sort -u)
  fi

  printf '{"success":true,"themes":['
  first=1
  if [ -n "$themes" ]; then
    while IFS= read -r theme; do
      [ -n "$theme" ] || continue
      theme_json=$(json_escape "$theme")
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '"%s"' "$theme_json"
    done <<EOF
$themes
EOF
  fi
  printf ']}\n'
}

icon_data_uri_from_icns() {
  icon_path=$1
  [ -f "$icon_path" ] || return 1
  if ! command -v sips >/dev/null 2>&1; then
    return 1
  fi

  tmp_png=$(mktemp "/tmp/artificer-icon.XXXXXX.png")
  if ! sips -s format png "$icon_path" --out "$tmp_png" >/dev/null 2>&1; then
    rm -f "$tmp_png"
    return 1
  fi

  icon_b64=$(base64_encode_file "$tmp_png" 2>/dev/null || true)
  rm -f "$tmp_png"
  [ -n "$icon_b64" ] || return 1
  printf 'data:image/png;base64,%s' "$icon_b64"
}

find_app_icon_icns() {
  app_key=$1
  case "$app_key" in
    finder)
      for candidate in \
        "/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns" \
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FinderIcon.icns"
      do
        if [ -f "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
      done
      ;;
    textmate)
      for candidate in \
        "/Applications/TextMate.app/Contents/Resources/TextMate.icns" \
        "$HOME/Applications/TextMate.app/Contents/Resources/TextMate.icns"
      do
        if [ -f "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
      done
      ;;
  esac
  return 1
}

emit_app_icons() {
  finder_icon=""
  textmate_icon=""

  finder_icns=$(find_app_icon_icns "finder" 2>/dev/null || true)
  if [ -n "$finder_icns" ]; then
    finder_icon=$(icon_data_uri_from_icns "$finder_icns" 2>/dev/null || true)
  fi

  textmate_icns=$(find_app_icon_icns "textmate" 2>/dev/null || true)
  if [ -n "$textmate_icns" ]; then
    textmate_icon=$(icon_data_uri_from_icns "$textmate_icns" 2>/dev/null || true)
  fi

  printf '{"success":true,"finder":"%s","textmate":"%s"}\n' \
    "$(json_escape "$finder_icon")" \
    "$(json_escape "$textmate_icon")"
}

