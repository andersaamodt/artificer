new_id() {
  now=$(date +%s 2>/dev/null || printf '0')
  pid=$$
  rand=$(awk 'BEGIN {srand(); printf "%06d", rand()*1000000}')
  printf '%s-%s-%s' "$now" "$pid" "$rand"
}

valid_id() {
  id=$1
  case "$id" in
    ""|.|..|*[!a-zA-Z0-9._-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

reserved_workspace_id() {
  workspace_id_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$workspace_id_value" in
    null|undefined|none)
      return 0
      ;;
  esac
  return 1
}

valid_workspace_id() {
  workspace_id_value=$1
  if ! valid_id "$workspace_id_value"; then
    return 1
  fi
  if reserved_workspace_id "$workspace_id_value"; then
    return 1
  fi
  return 0
}

read_file_line() {
  file_path=$1
  fallback=${2:-}
  if [ -f "$file_path" ]; then
    sed -n '1p' "$file_path"
  else
    printf '%s' "$fallback"
  fi
}

workspace_dir_for() {
  workspace_id=$1
  printf '%s/%s' "$workspaces_dir" "$workspace_id"
}

conversation_dir_for() {
  workspace_id=$1
  conversation_id=$2
  printf '%s/%s/conversations/%s' "$workspaces_dir" "$workspace_id" "$conversation_id"
}

mode_runtime_lib_file="$ARTIFICER_SCRIPT_DIR/mode-runtime-lib.sh"
mode_runtime_lib_loaded=0
mode_runtime_bootstrapped=0
if [ -f "$mode_runtime_lib_file" ]; then
  . "$mode_runtime_lib_file"
  mode_runtime_lib_loaded=1
fi

ensure_mode_runtime_bootstrap() {
  if [ "$mode_runtime_bootstrapped" = "1" ]; then
    return 0
  fi
  if [ "$mode_runtime_lib_loaded" != "1" ]; then
    return 0
  fi
  if command -v mode_runtime_bootstrap >/dev/null 2>&1; then
    mode_runtime_bootstrap
  fi
  mode_runtime_bootstrapped=1
}

multi_agent_lib_file="$ARTIFICER_SCRIPT_DIR/multi-agent-lib.sh"
if [ ! -f "$multi_agent_lib_file" ]; then
  multi_agent_lib_file="$ARTIFICER_SCRIPT_DIR/multi_agent-lib.sh"
fi
if [ -f "$multi_agent_lib_file" ]; then
  . "$multi_agent_lib_file"
fi

command_policy_dir_for() {
  workspace_id=$1
  printf '%s/%s' "$command_policy_root" "$workspace_id"
}

command_policy_mode_file_for() {
  workspace_id=$1
  printf '%s/mode' "$(command_policy_dir_for "$workspace_id")"
}

command_policy_rules_file_for() {
  workspace_id=$1
  printf '%s/rules.txt' "$(command_policy_dir_for "$workspace_id")"
}

command_policy_once_rules_file_for() {
  workspace_id=$1
  printf '%s/once-rules.txt' "$(command_policy_dir_for "$workspace_id")"
}

ensure_command_policy_layout() {
  workspace_id=$1
  policy_dir=$(command_policy_dir_for "$workspace_id")
  mkdir -p "$policy_dir"
  mode_file=$(command_policy_mode_file_for "$workspace_id")
  [ -f "$mode_file" ] || printf '%s\n' "ask-some" > "$mode_file"
  rules_file=$(command_policy_rules_file_for "$workspace_id")
  [ -f "$rules_file" ] || : > "$rules_file"
  once_rules_file=$(command_policy_once_rules_file_for "$workspace_id")
  [ -f "$once_rules_file" ] || : > "$once_rules_file"
}

command_policy_mode_for_workspace() {
  workspace_id=$1
  ensure_command_policy_layout "$workspace_id"
  mode=$(read_file_line "$(command_policy_mode_file_for "$workspace_id")" "ask-some")
  case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
    ask)
      printf '%s' "ask-some"
      ;;
    none|ask-all|ask-some|all)
      printf '%s' "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
      ;;
    *)
      printf '%s' "ask-some"
      ;;
  esac
}

set_command_policy_mode_for_workspace() {
  workspace_id=$1
  mode=$2
  case "$mode" in
    ask) mode="ask-some" ;;
    none|ask-all|ask-some|all) ;;
    *) mode="ask-some" ;;
  esac
  ensure_command_policy_layout "$workspace_id"
  printf '%s\n' "$mode" > "$(command_policy_mode_file_for "$workspace_id")"
}

normalize_command_exec_mode_value() {
  raw_mode=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_mode" in
    ask)
      printf '%s' "ask-some"
      ;;
    none|ask-all|ask-some|all)
      printf '%s' "$raw_mode"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

normalize_permission_mode_value() {
  raw_mode=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_mode" in
    full-access)
      printf '%s' "default"
      ;;
    default|workspace-write|read-only)
      printf '%s' "$raw_mode"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

normalize_toggle_01_value() {
  raw_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_value" in
    1|true|yes|on|enabled)
      printf '%s' "1"
      ;;
    0|false|no|off|disabled)
      printf '%s' "0"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

normalize_reflexive_knowledge_value() {
  normalize_toggle_01_value "$1"
}

normalize_self_actuation_value() {
  normalize_toggle_01_value "$1"
}

normalize_programmer_review_enabled_value() {
  raw_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_value" in
    ""|1|true|yes|on|enabled)
      printf '%s' "1"
      ;;
    0|false|no|off|disabled)
      printf '%s' "0"
      ;;
    *)
      printf '%s' "1"
      ;;
  esac
}

normalize_programmer_review_rounds_value() {
  raw_value=$(trim "$1")
  default_value=${2:-2}
  case "$raw_value" in
    ""|*[!0-9]*)
      raw_value=$default_value
      ;;
  esac
  if [ "$raw_value" -lt 1 ]; then
    raw_value=1
  fi
  if [ "$raw_value" -gt 4 ]; then
    raw_value=4
  fi
  printf '%s' "$raw_value"
}

normalize_assay_task_id_value() {
  raw_value=$(trim "$1")
  if [ -z "$raw_value" ]; then
    printf '%s' ""
    return 0
  fi
  normalized=$(printf '%s' "$raw_value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9._-]/-/g;s/--\+/-/g;s/^-//;s/-$//')
  normalized=$(printf '%s' "$normalized" | cut -c1-64)
  case "$normalized" in
    ""|*..*)
      printf '%s' ""
      ;;
    *)
      printf '%s' "$normalized"
      ;;
  esac
}

normalize_automation_id_value() {
  raw_value=$(trim "$1")
  if [ -z "$raw_value" ]; then
    printf '%s' ""
    return 0
  fi
  if valid_id "$raw_value"; then
    printf '%s' "$raw_value"
    return 0
  fi
  printf '%s' ""
}

command_text_to_rule_pattern_default() {
  cmd=$1
  first_word=$(printf '%s\n' "$cmd" | awk '{print $1}')
  if [ -n "$first_word" ]; then
    printf '^%s([[:space:]].*)?$' "$(printf '%s' "$first_word" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  else
    printf '^%s$' "$(printf '%s' "$cmd" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
  fi
}

normalize_rule_field() {
  printf '%s' "$1" | tr '\n' ' ' | tr '\t' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//'
}

command_first_token() {
  cmd=$(normalize_rule_field "$1")
  printf '%s\n' "$cmd" | awk '{print $1}'
}

command_has_shell_meta() {
  cmd=$1
  case "$cmd" in
    *';'*|*'&&'*|*'||'*|*'|'*|*'>'*|*'<'*|*'`'*|*'$('*)
      return 0
      ;;
  esac
  return 1
}

global_safe_default_rules_json() {
  printf '['
  printf '{"id":"g1","label":"ls","match_mode":"regex","pattern":"^ls([[:space:]].*)?$"}'
  printf ',{"id":"g2","label":"pwd","match_mode":"regex","pattern":"^pwd([[:space:]].*)?$"}'
  printf ',{"id":"g3","label":"whoami","match_mode":"regex","pattern":"^whoami([[:space:]].*)?$"}'
  printf ',{"id":"g4","label":"uname","match_mode":"regex","pattern":"^uname([[:space:]].*)?$"}'
  printf ',{"id":"g5","label":"cat/head/tail/wc","match_mode":"regex","pattern":"^(cat|head|tail|wc)([[:space:]].*)?$"}'
  printf ',{"id":"g6","label":"grep/find/stat/file/realpath","match_mode":"regex","pattern":"^(grep|find|stat|file|realpath)([[:space:]].*)?$"}'
  printf ',{"id":"g7","label":"git read-only","match_mode":"regex","pattern":"^git[[:space:]]+(status|diff|log|show|branch|rev-parse)([[:space:]].*)?$"}'
  printf ',{"id":"g8","label":"rg search","match_mode":"regex","pattern":"^rg([[:space:]].*)?$"}'
  printf ',{"id":"g9","label":"tool lookup","match_mode":"regex","pattern":"^(which[[:space:]]+[A-Za-z0-9._+-]+|command[[:space:]]+-v[[:space:]]+[A-Za-z0-9._+-]+)$"}'
  printf ',{"id":"g10","label":"tool version checks","match_mode":"regex","pattern":"^((godot|godot4|python|python3|node|npm|pnpm|yarn|cargo|rustc)[[:space:]]+--version|go[[:space:]]+version)([[:space:]].*)?$"}'
  printf ',{"id":"g11","label":"godot headless smoke test","match_mode":"regex","pattern":"^(godot|godot4)[[:space:]]+--headless[[:space:]]+--path[[:space:]]+\\.[[:space:]]+--quit$"}'
  printf ',{"id":"g12","label":"shell syntax check","match_mode":"regex","pattern":"^(sh|bash)[[:space:]]+-n[[:space:]]+[A-Za-z0-9._/-]+$"}'
  printf ',{"id":"g13","label":"python compile check","match_mode":"regex","pattern":"^(python|python3)[[:space:]]+-m[[:space:]]+py_compile[[:space:]]+[A-Za-z0-9._/-]+$"}'
  printf ',{"id":"g14","label":"node syntax check","match_mode":"regex","pattern":"^node[[:space:]]+--check[[:space:]]+[A-Za-z0-9._/-]+$"}'
  printf ']'
}

command_matches_global_safe_default() {
  cmd=$(normalize_rule_field "$1")
  [ -n "$cmd" ] || return 1
  if command_has_shell_meta "$cmd"; then
    return 1
  fi
  case "$cmd" in
    ls|ls\ *|pwd|pwd\ *|whoami|whoami\ *|uname|uname\ *|cat\ *|head\ *|tail\ *|wc\ *|grep\ *|find\ *|stat\ *|file\ *|realpath\ *|rg\ *)
      return 0
      ;;
    git\ status|git\ status\ *|git\ diff|git\ diff\ *|git\ log|git\ log\ *|git\ show|git\ show\ *|git\ branch|git\ branch\ *|git\ rev-parse|git\ rev-parse\ *)
      return 0
      ;;
    which\ [A-Za-z0-9._+-][A-Za-z0-9._+-]*|command\ -v\ [A-Za-z0-9._+-][A-Za-z0-9._+-]*)
      return 0
      ;;
    godot\ --version|godot4\ --version|python\ --version|python3\ --version|node\ --version|npm\ --version|pnpm\ --version|yarn\ --version|cargo\ --version|rustc\ --version|go\ version)
      return 0
      ;;
    godot\ --headless\ --path\ .\ --quit|godot4\ --headless\ --path\ .\ --quit)
      return 0
      ;;
    sh\ -n\ *|bash\ -n\ *|python\ -m\ py_compile\ *|python3\ -m\ py_compile\ *|node\ --check\ *)
      return 0
      ;;
  esac
  return 1
}

rule_matches_command() {
  match_mode=$1
  pattern=$2
  cmd=$3
  case "$match_mode" in
    exact)
      cmd_norm=$(normalize_rule_field "$cmd")
      pattern_norm=$(normalize_rule_field "$pattern")
      [ "$cmd_norm" = "$pattern_norm" ]
      return $?
      ;;
    regex)
      if [ -z "$pattern" ]; then
        return 1
      fi
      printf '%s\n' "$cmd" | grep -Eq -- "$pattern"
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

append_command_rule() {
  workspace_id=$1
  scope=$2
  decision=$3
  match_mode=$4
  pattern=$5

  ensure_command_policy_layout "$workspace_id"
  case "$scope" in
    once)
      rules_file=$(command_policy_once_rules_file_for "$workspace_id")
      ;;
    *)
      rules_file=$(command_policy_rules_file_for "$workspace_id")
      ;;
  esac
  existing_match=$(awk -F'\t' -v d="$decision" -v m="$match_mode" -v p="$pattern" '
    NF >= 3 && $1 == d && $2 == m && $3 == p { found = 1; exit }
    END { if (found) print "1"; else print "0" }
  ' "$rules_file" 2>/dev/null || printf '0')
  if [ "$existing_match" = "1" ]; then
    return 0
  fi
  printf '%s\t%s\t%s\n' "$decision" "$match_mode" "$pattern" >> "$rules_file"
}

command_rules_json_for_workspace() {
  workspace_id=$1
  ensure_command_policy_layout "$workspace_id"
  remember_file=$(command_policy_rules_file_for "$workspace_id")
  once_file=$(command_policy_once_rules_file_for "$workspace_id")

  printf '{"success":true,"workspace_id":"%s","global_defaults":' "$(json_escape "$workspace_id")"
  global_safe_default_rules_json

  printf ',"remembered":['
  first=1
  idx=0
  if [ -f "$remember_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      idx=$((idx + 1))
      decision=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
      match_mode=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
      pattern=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
      [ -n "$decision" ] || continue
      [ -n "$match_mode" ] || match_mode="exact"
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"index":"%s","decision":"%s","match_mode":"%s","pattern":"%s"}' \
        "$(json_escape "$idx")" "$(json_escape "$decision")" "$(json_escape "$match_mode")" "$(json_escape "$pattern")"
    done < "$remember_file"
  fi
  printf ']'

  printf ',"once":['
  first=1
  idx=0
  if [ -f "$once_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      idx=$((idx + 1))
      decision=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
      match_mode=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
      pattern=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
      [ -n "$decision" ] || continue
      [ -n "$match_mode" ] || match_mode="exact"
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"index":"%s","decision":"%s","match_mode":"%s","pattern":"%s"}' \
        "$(json_escape "$idx")" "$(json_escape "$decision")" "$(json_escape "$match_mode")" "$(json_escape "$pattern")"
    done < "$once_file"
  fi
  printf ']'
  printf '}\n'
}

delete_command_rule_by_index() {
  workspace_id=$1
  scope=$2
  index_raw=$3
  index_num=$(printf '%s' "$index_raw" | awk '{print int($1)}')
  if [ "$index_num" -lt 1 ] 2>/dev/null; then
    return 1
  fi
  ensure_command_policy_layout "$workspace_id"
  case "$scope" in
    once)
      rules_file=$(command_policy_once_rules_file_for "$workspace_id")
      ;;
    remember)
      rules_file=$(command_policy_rules_file_for "$workspace_id")
      ;;
    *)
      return 1
      ;;
  esac
  tmp_file=$(mktemp)
  found=0
  i=0
  if [ -f "$rules_file" ]; then
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        i=$((i + 1))
      fi
      if [ "$i" -eq "$index_num" ] && [ "$found" -eq 0 ]; then
        found=1
        continue
      fi
      printf '%s\n' "$line" >> "$tmp_file"
    done < "$rules_file"
  fi
  mv "$tmp_file" "$rules_file"
  [ "$found" -eq 1 ]
}

command_policy_decision() {
  workspace_id=$1
  cmd=$2
  mode=$3
  decision_file=$4
  source_file=$5
  matched_pattern_file=$6
  matched_scope_file=$7

  printf '%s' "" > "$decision_file"
  printf '%s' "" > "$source_file"
  printf '%s' "" > "$matched_pattern_file"
  printf '%s' "" > "$matched_scope_file"

  case "$mode" in
    ask)
      mode="ask-some"
      ;;
    none|ask-all|ask-some|all)
      ;;
    *)
      mode="ask-some"
      ;;
  esac

  case "$mode" in
    none)
      printf '%s' "deny" > "$decision_file"
      printf '%s' "mode-none" > "$source_file"
      printf '%s' "none" > "$matched_scope_file"
      return 0
      ;;
    all)
      printf '%s' "allow" > "$decision_file"
      printf '%s' "mode-all" > "$source_file"
      printf '%s' "all" > "$matched_scope_file"
      return 0
      ;;
  esac

  ensure_command_policy_layout "$workspace_id"
  once_file=$(command_policy_once_rules_file_for "$workspace_id")
  temp_once=$(mktemp)
  matched_once=0

  if [ -f "$once_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      decision=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
      match_mode=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
      pattern=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
      if [ "$matched_once" -eq 0 ] && rule_matches_command "$match_mode" "$pattern" "$cmd"; then
        printf '%s' "$decision" > "$decision_file"
        printf '%s' "once-rule" > "$source_file"
        printf '%s' "$pattern" > "$matched_pattern_file"
        printf '%s' "once" > "$matched_scope_file"
        matched_once=1
        continue
      fi
      printf '%s\n' "$line" >> "$temp_once"
    done < "$once_file"
    mv "$temp_once" "$once_file"
  else
    rm -f "$temp_once"
  fi

  if [ "$matched_once" -eq 1 ]; then
    return 0
  fi

  rules_file=$(command_policy_rules_file_for "$workspace_id")
  if [ -f "$rules_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      decision=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
      match_mode=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
      pattern=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
      if rule_matches_command "$match_mode" "$pattern" "$cmd"; then
        printf '%s' "$decision" > "$decision_file"
        printf '%s' "rule" > "$source_file"
        printf '%s' "$pattern" > "$matched_pattern_file"
        printf '%s' "remember" > "$matched_scope_file"
        return 0
      fi
    done < "$rules_file"
  fi

  if [ "$mode" = "ask-some" ] && command_matches_global_safe_default "$cmd"; then
    printf '%s' "allow" > "$decision_file"
    printf '%s' "global-safe-default" > "$source_file"
    printf '%s' "$(command_first_token "$cmd")" > "$matched_pattern_file"
    printf '%s' "global" > "$matched_scope_file"
    return 0
  fi

  printf '%s' "prompt" > "$decision_file"
}

blocked_command_json_from_file() {
  blocked_file=$1
  printf '['
  first=1
  if [ -f "$blocked_file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      cmd=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
      reason=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"command":"%s","reason":"%s"}' "$(json_escape "$cmd")" "$(json_escape "$reason")"
    done < "$blocked_file"
  fi
  printf ']'
}

stream_session_dir_for() {
  conv_dir=$1
  stream_session=$2
  printf '%s/stream/%s' "$conv_dir" "$stream_session"
}

stream_tokens_file_for() {
  conv_dir=$1
  stream_session=$2
  printf '%s/tokens.txt' "$(stream_session_dir_for "$conv_dir" "$stream_session")"
}

stream_compact_programming_step_number() {
  printf '%s\n' "$1" | sed -n 's/.*[Ss]tep \([0-9][0-9]*\).*/\1/p' | sed -n '1p'
}

stream_compact_programming_command_counts() {
  line_text=$1
  ran_count=$(printf '%s\n' "$line_text" | sed -n 's/.*ran=\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  ok_count=$(printf '%s\n' "$line_text" | sed -n 's/.*ok=\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  [ -n "$ran_count" ] || ran_count="0"
  [ -n "$ok_count" ] || ok_count="0"
  printf '%s|%s\n' "$ran_count" "$ok_count"
}

stream_compact_programming_line() {
  line_text=$1
  step_no=$(stream_compact_programming_step_number "$line_text")
  case "$line_text" in
    "Run started.")
      printf '%s' "Preparing workspace and implementation plan."
      return 0
      ;;
    "Bounded programming start: using deterministic quick plan.")
      printf '%s' "Preparing a bounded first pass."
      return 0
      ;;
    "Run orchestration initialized."|"Initial checkpoints seeded."|"Run time budget:"*|"Controller variant:"*|"Current mode:"*|"Context compacted for model window"*|"Step "*controller\ prompt\ assembled.|"Step "*controller\ call\ started*|"Step "*controller\ response\ captured.|"Step "*control\ sections\ parsed*|"Step "*completion\ check:*|"Step "*checkpoint:*|"Step "*next:*|"Step "*confidence\ updated:*|"Step "*command\ *started:*|"Step "*command\ *status:*|"Programming final-output normalizer replaced verbose or generic summary with concise implementation summary."|"Run artifacts captured (state, failures, trace)."|"Controller retry produced a structured response."|"Controller format retry produced a non-empty response."|"Controller format retry returned empty output; continuing with recovery scaffolding."|"Completed partial controller output by filling missing required sections."|"Reasoning completion salvage fallback: "*|"Reasoning deterministic salvage emitted a complete fallback response; mode promoted to DONE."|"Step "*design\ gate\ context:*|"Step "*format-recovery\ guard:*|"Step "*completion\ guard:*|"Controller format-recovery pressure active; using reduced context profile."|"Focused implement step returned empty output; skipping retry and falling back immediately."|"Controller output was incomplete; using a safer fallback path."|"Controller output was incomplete; retrying once."|"Recovered from malformed controller output and continued with safer defaults."|"Step "*implementation\ summary:*)
      printf '%s' ""
      return 0
      ;;
    "Run mode: programming "*)
      printf '%s' ""
      return 0
      ;;
    "Step "*decision\ checkpoint:\ no\ user\ decision\ required.)
      printf '%s' ""
      return 0
      ;;
    "Step "*paused\ for\ user\ decision*)
      printf '%s' "Paused for a required user decision."
      return 0
      ;;
    "Step "*decision\ checkpoint:\ request\ prepared*)
      printf '%s' "Preparing a required user decision."
      return 0
      ;;
    "Iteration "*started.)
      printf '%s' ""
      return 0
      ;;
    "Step "*executing\ DESIGN\ command\ batch.)
      printf 'Step %s: inspecting the workspace and gathering evidence.' "${step_no:-1}"
      return 0
      ;;
    "Step "*executing\ INVESTIGATE\ command\ batch.)
      printf 'Step %s: inspecting the workspace and gathering evidence.' "${step_no:-1}"
      return 0
      ;;
    "Step "*executing\ VERIFY\ command\ batch.)
      printf 'Step %s: running verification checks.' "${step_no:-1}"
      return 0
      ;;
    "Step "*implementing\ patch\ candidate.)
      printf 'Step %s: applying code changes.' "${step_no:-1}"
      return 0
      ;;
    "Quick narrow-slice implement step: using focused context profile.")
      printf '%s' ""
      return 0
      ;;
    "Step "*quick-slice\ guard:*)
      printf '%s' ""
      return 0
      ;;
    "Step "*command\ summary:*)
      counts=$(stream_compact_programming_command_counts "$line_text")
      ran_count=$(printf '%s' "$counts" | cut -d'|' -f1)
      ok_count=$(printf '%s' "$counts" | cut -d'|' -f2)
      printf 'Step %s: completed %s of %s commands.' "${step_no:-1}" "$ok_count" "$ran_count"
      return 0
      ;;
    "Step "*self-correction\ check:\ failed\ assumptions\ detected*)
      printf 'Step %s: revising the plan after contradictory evidence.' "${step_no:-1}"
      return 0
      ;;
    "Step "*self-correction\ check:*)
      printf '%s' ""
      return 0
      ;;
    "Controller response missing required sections; skipping retry for bounded quick programming run."|"Controller response missing required sections; skipping retry under budget pressure and applying recovery scaffolding."|"Controller response missing required sections; retrying once with strict section-order contract."|"Recovered malformed controller output.")
      printf '%s' ""
      return 0
      ;;
    "Step "*:\ DESIGN\ \-\>\ IMPLEMENT*)
      printf 'Step %s: switching from investigation to code changes.' "${step_no:-1}"
      return 0
      ;;
    "Step "*:\ INVESTIGATE\ \-\>\ DESIGN*)
      printf 'Step %s: switching from inspection to planning.' "${step_no:-1}"
      return 0
      ;;
    "Step "*:\ IMPLEMENT\ \-\>\ VERIFY*)
      printf 'Step %s: switching from code changes to verification.' "${step_no:-1}"
      return 0
      ;;
    "Step "*:\ VERIFY\ \-\>\ DONE*)
      printf 'Step %s: verification complete; preparing the final summary.' "${step_no:-1}"
      return 0
      ;;
    "Run reached time budget of "*)
      printf '%s' "Time budget reached; preparing a partial summary."
      return 0
      ;;
    "Reasoning completion salvage:"*)
      printf '%s' "Preparing a best-effort summary from the collected work."
      return 0
      ;;
    "Step "*circuit-breaker:*)
      printf '%s' "Preparing a best-effort summary from the collected work."
      return 0
      ;;
    "Step "*:\ *\-\>\ DONE\ \(controller\ format\ instability\ circuit-breaker\))
      printf '%s' ""
      return 0
      ;;
    "Final response prepared for delivery.")
      printf '%s' "Final answer ready."
      return 0
      ;;
    "Worked for "*)
      printf '%s' "$line_text"
      return 0
      ;;
    "Run finalized with status:"*)
      printf '%s' "Run finished."
      return 0
      ;;
  esac
  printf '%s' "$line_text"
}

stream_compact_line() {
  line_text=$1
  case "${ARTIFICER_STREAM_PROFILE:-}" in
    programming)
      stream_compact_programming_line "$line_text"
      ;;
    *)
      printf '%s' "$line_text"
      ;;
  esac
}

stream_emit_line() {
  stream_file=$1
  shift
  line_text=$*
  if [ -z "$(trim "$stream_file")" ]; then
    return 0
  fi
  line_text=$(stream_compact_line "$line_text")
  if [ -z "$(trim "$line_text")" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$stream_file")" 2>/dev/null || true
  if [ ! -f "$stream_file" ]; then
    : > "$stream_file"
  fi
  last_body=$(tail -n 1 "$stream_file" 2>/dev/null | sed 's/^\[[^]]*\][[:space:]]*//')
  if [ "$(trim "$last_body")" = "$(trim "$line_text")" ]; then
    return 0
  fi
  ts=$(date +"%H:%M:%S")
  printf '[%s] %s\n' "$ts" "$line_text" >> "$stream_file"
}

iso_utc_from_epoch() {
  epoch_value=$1
  case "$epoch_value" in
    ""|*[!0-9]*)
      printf '%s' ""
      return 0
      ;;
  esac
  if [ "$epoch_value" -le 0 ]; then
    printf '%s' ""
    return 0
  fi
  iso_value=$(date -u -r "$epoch_value" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  if [ -n "$iso_value" ]; then
    printf '%s' "$iso_value"
    return 0
  fi
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' ""
}

attachment_root_dir_for() {
  conv_dir=$1
  printf '%s/attachments' "$conv_dir"
}

attachment_item_dir_for() {
  conv_dir=$1
  attachment_id=$2
  printf '%s/%s' "$(attachment_root_dir_for "$conv_dir")" "$attachment_id"
}

attachment_blob_for() {
  conv_dir=$1
  attachment_id=$2
  printf '%s/blob' "$(attachment_item_dir_for "$conv_dir" "$attachment_id")"
}

attachment_meta_file_for() {
  conv_dir=$1
  attachment_id=$2
  printf '%s/meta' "$(attachment_item_dir_for "$conv_dir" "$attachment_id")"
}

attachment_meta_get() {
  conv_dir=$1
  attachment_id=$2
  key=$3
  meta_file=$(attachment_meta_file_for "$conv_dir" "$attachment_id")
  if [ ! -f "$meta_file" ]; then
    printf '%s' ""
    return 0
  fi
  sed -n "s/^$key=//p" "$meta_file" | sed -n '1p'
}

base64_decode_to_file() {
  encoded_data=$1
  out_file=$2

  if command -v base64 >/dev/null 2>&1; then
    if printf '%s' "$encoded_data" | base64 -d >"$out_file" 2>/dev/null; then
      return 0
    fi
    if printf '%s' "$encoded_data" | base64 -D >"$out_file" 2>/dev/null; then
      return 0
    fi
  fi

  if command -v perl >/dev/null 2>&1; then
    if printf '%s' "$encoded_data" | perl -MMIME::Base64 -e '
      use strict;
      use warnings;
      local $/;
      my $raw = <STDIN>;
      my $decoded = eval { decode_base64($raw) };
      exit 1 if !defined($decoded);
      binmode STDOUT;
      print $decoded;
    ' >"$out_file" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}

base64_encode_file() {
  file_path=$1

  if command -v base64 >/dev/null 2>&1; then
    if base64 < "$file_path" 2>/dev/null | tr -d '\n'; then
      return 0
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    if openssl base64 -A -in "$file_path" 2>/dev/null; then
      return 0
    fi
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -MMIME::Base64 -e '
      use strict;
      use warnings;
      my $path = shift @ARGV;
      open(my $fh, "<", $path) or exit 1;
      binmode $fh;
      local $/;
      my $data = <$fh>;
      print encode_base64($data, "");
    ' "$file_path" 2>/dev/null && return 0
  fi

  return 1
}

attachment_ext_from_name() {
  file_name=$1
  printf '%s' "$file_name" | awk -F. '
    NF > 1 {print tolower($NF)}
  '
}

attachment_kind_from_name_mime() {
  file_name=$1
  mime_type=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  ext=$(attachment_ext_from_name "$file_name")

  case "$mime_type" in
    image/png|image/jpeg|image/jpg|image/gif|image/webp|image/bmp|image/tiff|image/x-icon|image/svg+xml)
      printf '%s' "image"
      return 0
      ;;
  esac

  case "$mime_type" in
    text/*|application/json|application/xml|application/yaml|application/x-yaml|application/toml|application/javascript|application/x-javascript|application/typescript|application/x-typescript|application/x-sh|application/x-shellscript)
      printf '%s' "text"
      return 0
      ;;
  esac

  case "$mime_type" in
    application/pdf)
      printf '%s' "document"
      return 0
      ;;
  esac

  case "$ext" in
    txt|md|markdown|rst|log|csv|tsv|json|xml|yaml|yml|toml|ini|conf|cfg|env|sh|bash|zsh|fish|py|js|jsx|ts|tsx|c|h|cpp|cc|cxx|hpp|java|go|rs|php|rb|swift|kt|scala|sql|html|htm|css|scss|less|vue|svelte|dockerfile|makefile|gradle)
      printf '%s' "text"
      return 0
      ;;
    pdf)
      printf '%s' "document"
      return 0
      ;;
  esac

  printf '%s' ""
  return 1
}

attachment_ids_to_file() {
  raw_ids=$1
  out_file=$2
  : > "$out_file"

  printf '%s' "$raw_ids" \
    | tr ',\r\t ' '\n' \
    | sed '/^$/d' \
    | awk '!seen[$0]++' \
    | while IFS= read -r attachment_id; do
      if valid_id "$attachment_id"; then
        printf '%s\n' "$attachment_id" >> "$out_file"
      fi
    done
}

skill_ids_to_file() {
  raw_ids=$1
  out_file=$2
  : > "$out_file"

  printf '%s' "$raw_ids" \
    | tr ',\r\t ' '\n' \
    | sed '/^$/d' \
    | while IFS= read -r skill_id; do
      skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
      case "$skill_id" in
        \$*)
          skill_id=${skill_id#\$}
          ;;
      esac
      if valid_id "$skill_id"; then
        printf '%s\n' "$skill_id" >> "$out_file"
      fi
    done

  dedup_file=$(mktemp)
  awk '!seen[$0]++' "$out_file" > "$dedup_file"
  mv "$dedup_file" "$out_file"
}

prompt_skill_tags_to_file() {
  prompt_text=$1
  out_file=$2
  : > "$out_file"

  printf '%s' "$prompt_text" | perl -CS -0777 -ne '
    while (/\$([A-Za-z][A-Za-z0-9_-]*)\b/g) {
      print lc($1), "\n";
    }
  ' 2>/dev/null \
    | sed '/^$/d' \
    | while IFS= read -r skill_id; do
        if valid_id "$skill_id"; then
          printf '%s\n' "$skill_id" >> "$out_file"
        fi
      done

  dedup_file=$(mktemp)
  awk '!seen[$0]++' "$out_file" > "$dedup_file"
  mv "$dedup_file" "$out_file"
}

merge_ids_files() {
  first_file=$1
  second_file=$2
  out_file=$3
  merged_file=$(mktemp)
  : > "$merged_file"
  if [ -f "$first_file" ]; then
    sed '/^$/d' "$first_file" >> "$merged_file"
  fi
  if [ -f "$second_file" ]; then
    sed '/^$/d' "$second_file" >> "$merged_file"
  fi
  dedup_file=$(mktemp)
  awk '!seen[$0]++' "$merged_file" > "$dedup_file"
  mv "$dedup_file" "$out_file"
  rm -f "$merged_file"
}

string_json_array_from_ids_file() {
  ids_file=$1
  printf '['
  first=1
  if [ -f "$ids_file" ]; then
    while IFS= read -r item_id; do
      item_id=$(trim "$item_id")
      [ -n "$item_id" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '"%s"' "$(json_escape "$item_id")"
    done < "$ids_file"
  fi
  printf ']'
}

attachment_exists_for_conversation() {
  conv_dir=$1
  attachment_id=$2
  attachment_item_dir=$(attachment_item_dir_for "$conv_dir" "$attachment_id")
  [ -d "$attachment_item_dir" ] && [ -f "$attachment_item_dir/blob" ] && [ -f "$attachment_item_dir/meta" ]
}

attachment_json_array_from_ids_file() {
  conv_dir=$1
  ids_file=$2
  printf '['
  first=1

  if [ -f "$ids_file" ]; then
    while IFS= read -r attachment_id; do
      [ -n "$attachment_id" ] || continue
      if ! attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
        continue
      fi

      name=$(attachment_meta_get "$conv_dir" "$attachment_id" "name")
      mime=$(attachment_meta_get "$conv_dir" "$attachment_id" "mime")
      kind=$(attachment_meta_get "$conv_dir" "$attachment_id" "kind")
      size=$(attachment_meta_get "$conv_dir" "$attachment_id" "size")
      [ -n "$size" ] || size=0

      id_json=$(json_escape "$attachment_id")
      name_json=$(json_escape "$name")
      mime_json=$(json_escape "$mime")
      kind_json=$(json_escape "$kind")

      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"id":"%s","name":"%s","mime":"%s","kind":"%s","size":%s}' \
        "$id_json" "$name_json" "$mime_json" "$kind_json" "$size"
    done < "$ids_file"
  fi

  printf ']'
}

attachment_context_from_ids_file() {
  conv_dir=$1
  ids_file=$2
  max_chars=6000
  total_chars=0

  [ -f "$ids_file" ] || return 0

  while IFS= read -r attachment_id; do
    [ -n "$attachment_id" ] || continue
    if ! attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
      continue
    fi

    name=$(attachment_meta_get "$conv_dir" "$attachment_id" "name")
    mime=$(attachment_meta_get "$conv_dir" "$attachment_id" "mime")
    kind=$(attachment_meta_get "$conv_dir" "$attachment_id" "kind")
    blob_path=$(attachment_blob_for "$conv_dir" "$attachment_id")
    size=$(attachment_meta_get "$conv_dir" "$attachment_id" "size")
    [ -n "$size" ] || size=$(wc -c < "$blob_path" | tr -d ' ')

    case "$kind" in
      text)
        excerpt=$(sed -n '1,180p' "$blob_path" 2>/dev/null || true)
        excerpt=$(printf '%s' "$excerpt" | sed 's/[[:cntrl:]]//g')
        if [ -z "$(trim "$excerpt")" ]; then
          excerpt="[text attachment contained no readable text]"
        fi
        ;;
      document)
        if command -v pdftotext >/dev/null 2>&1; then
          pdf_txt=$(mktemp)
          if pdftotext -q "$blob_path" "$pdf_txt" >/dev/null 2>&1; then
            excerpt=$(sed -n '1,180p' "$pdf_txt" 2>/dev/null || true)
          else
            excerpt=""
          fi
          rm -f "$pdf_txt"
        else
          excerpt=""
        fi
        if [ -z "$(trim "$excerpt")" ]; then
          excerpt="[PDF attached: no text extracted in this environment]"
        fi
        ;;
      image)
        excerpt="[image attachment]"
        ;;
      *)
        excerpt="[binary attachment]"
        ;;
    esac

    block=$(cat <<EOF
Attachment: $name
MIME: $mime
Size: $size bytes
$excerpt

EOF
)

    block_chars=$(printf '%s' "$block" | wc -c | tr -d ' ')
    if [ $((total_chars + block_chars)) -gt "$max_chars" ]; then
      printf '[Additional attachment content omitted for length]\n'
      break
    fi
    total_chars=$((total_chars + block_chars))
    printf '%s' "$block"
  done < "$ids_file"
}

attachment_image_base64_lines_from_ids_file() {
  conv_dir=$1
  ids_file=$2
  supports_vision=$3

  [ "$supports_vision" = "1" ] || return 0
  [ -f "$ids_file" ] || return 0

  max_images=4
  count=0

  while IFS= read -r attachment_id; do
    [ -n "$attachment_id" ] || continue
    if ! attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
      continue
    fi

    kind=$(attachment_meta_get "$conv_dir" "$attachment_id" "kind")
    [ "$kind" = "image" ] || continue
    blob_path=$(attachment_blob_for "$conv_dir" "$attachment_id")
    image_b64=$(base64_encode_file "$blob_path" 2>/dev/null || true)
    if [ -n "$image_b64" ]; then
      printf '%s\n' "$image_b64"
      count=$((count + 1))
      if [ "$count" -ge "$max_images" ]; then
        break
      fi
    fi
  done < "$ids_file"
}

attachment_image_ocr_text_from_blob() {
  blob_path=$1
  [ -f "$blob_path" ] || return 0
  if ! command -v swift >/dev/null 2>&1; then
    return 0
  fi

  ocr_script=${ARTIFICER_IMAGE_OCR_SWIFT_SCRIPT:-/tmp/artificer-image-ocr.swift}
  if [ ! -f "$ocr_script" ]; then
    cat > "$ocr_script" <<'EOF_SWIFT'
import Foundation
import Vision
import AppKit

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard let image = NSImage(contentsOf: url) else {
    exit(2)
}
var rect = CGRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    exit(3)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])
let results = (request.results ?? []).compactMap { observation in
    observation.topCandidates(1).first?.string
}
print(results.joined(separator: "\n"))
EOF_SWIFT
  fi

  swift "$ocr_script" "$blob_path" 2>/dev/null \
    | sed -n '1,80p' \
    | sed 's/[[:cntrl:]]//g'
}

attachment_image_ocr_context_from_ids_file() {
  conv_dir=$1
  ids_file=$2

  [ -f "$ids_file" ] || return 0

  max_images=2
  count=0

  while IFS= read -r attachment_id; do
    [ -n "$attachment_id" ] || continue
    if ! attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
      continue
    fi

    kind=$(attachment_meta_get "$conv_dir" "$attachment_id" "kind")
    [ "$kind" = "image" ] || continue
    blob_path=$(attachment_blob_for "$conv_dir" "$attachment_id")
    name=$(attachment_meta_get "$conv_dir" "$attachment_id" "name")
    ocr_text=$(attachment_image_ocr_text_from_blob "$blob_path")
    ocr_text=$(trim "$ocr_text")
    [ -n "$ocr_text" ] || continue

    printf 'Image OCR: %s\n%s\n\n' "$name" "$ocr_text"
    count=$((count + 1))
    if [ "$count" -ge "$max_images" ]; then
      break
    fi
  done < "$ids_file"
}

conversation_queue_dir_for() {
  conv_dir=$1
  printf '%s/queue' "$conv_dir"
}

queue_pending_dir_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/pending' "$queue_dir"
}

read_int_file() {
  file_path=$1
  fallback=${2:-0}
  value=""
  if [ -f "$file_path" ]; then
    value=$(sed -n '1p' "$file_path" 2>/dev/null || true)
  fi
  case "$value" in
    -[0-9]*|[0-9]*)
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
      ;;
  esac
  printf '%s' "$fallback"
}

ensure_queue_layout() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  pending_dir=$(queue_pending_dir_for "$conv_dir")
  mkdir -p "$pending_dir"
  [ -f "$queue_dir/head" ] || printf '0\n' > "$queue_dir/head"
  [ -f "$queue_dir/tail" ] || printf '0\n' > "$queue_dir/tail"
}

queue_allocate_order() {
  conv_dir=$1
  mode=${2:-tail}
  queue_dir=$(conversation_queue_dir_for "$conv_dir")

  ensure_queue_layout "$conv_dir"
  head=$(read_int_file "$queue_dir/head" 0)
  tail=$(read_int_file "$queue_dir/tail" 0)

  if [ "$mode" = "head" ]; then
    order=$((head - 1))
    printf '%s\n' "$order" > "$queue_dir/head"
  else
    order=$((tail + 1))
    printf '%s\n' "$order" > "$queue_dir/tail"
  fi

  printf '%s' "$order"
}

queue_item_file_for() {
  conv_dir=$1
  order=$2
  item_id=$3
  pending_dir=$(queue_pending_dir_for "$conv_dir")
  printf '%s/%s__%s.txt' "$pending_dir" "$order" "$item_id"
}

queue_item_meta_for_path() {
  item_path=$1
  printf '%s.meta' "${item_path%.txt}"
}

queue_meta_write() {
  meta_file=$1
  run_mode_value=$2
  assistant_mode_value=$3
  compute_budget_value=$4
  command_exec_mode_value=$5
  permission_mode_value=$6
  programmer_review_enabled_value=$7
  programmer_review_rounds_value=$8
  explicit_skill_ids_file=$9
  attachment_ids_file=${10}
  assay_task_id_value=${11}
  automation_id_value=${12:-}
  reflexive_knowledge_value=${13:-}
  self_actuation_value=${14:-}
  temp_meta=$(mktemp)
  : > "$temp_meta"

  normalized_mode=$(normalize_run_mode_name "$run_mode_value")
  if [ -n "$normalized_mode" ]; then
    printf 'run_mode=%s\n' "$normalized_mode" >> "$temp_meta"
  fi

  normalized_assistant_mode=$(normalize_assistant_mode_id "$assistant_mode_value")
  if [ -n "$normalized_assistant_mode" ]; then
    printf 'assistant_mode_id=%s\n' "$normalized_assistant_mode" >> "$temp_meta"
  fi

  normalized_compute_budget=$(normalize_compute_budget "$compute_budget_value")
  if [ -n "$normalized_compute_budget" ]; then
    printf 'compute_budget=%s\n' "$normalized_compute_budget" >> "$temp_meta"
  fi

  normalized_command_exec_mode=$(normalize_command_exec_mode_value "$command_exec_mode_value")
  if [ -n "$normalized_command_exec_mode" ]; then
    printf 'command_exec_mode=%s\n' "$normalized_command_exec_mode" >> "$temp_meta"
  fi

  normalized_permission_mode=$(normalize_permission_mode_value "$permission_mode_value")
  if [ -n "$normalized_permission_mode" ]; then
    printf 'permission_mode=%s\n' "$normalized_permission_mode" >> "$temp_meta"
  fi

  normalized_programmer_review_enabled=$(normalize_programmer_review_enabled_value "$programmer_review_enabled_value")
  printf 'programmer_review=%s\n' "$normalized_programmer_review_enabled" >> "$temp_meta"

  normalized_programmer_review_rounds=$(normalize_programmer_review_rounds_value "$programmer_review_rounds_value" 2)
  printf 'programmer_review_rounds=%s\n' "$normalized_programmer_review_rounds" >> "$temp_meta"

  normalized_assay_task_id=$(normalize_assay_task_id_value "$assay_task_id_value")
  if [ -n "$normalized_assay_task_id" ]; then
    printf 'assay_task_id=%s\n' "$normalized_assay_task_id" >> "$temp_meta"
  fi

  normalized_automation_id=$(normalize_automation_id_value "$automation_id_value")
  if [ -n "$normalized_automation_id" ]; then
    printf 'automation_id=%s\n' "$normalized_automation_id" >> "$temp_meta"
  fi

  normalized_reflexive_knowledge=$(normalize_reflexive_knowledge_value "$reflexive_knowledge_value")
  if [ -n "$normalized_reflexive_knowledge" ]; then
    printf 'reflexive_knowledge=%s\n' "$normalized_reflexive_knowledge" >> "$temp_meta"
  fi

  normalized_self_actuation=$(normalize_self_actuation_value "$self_actuation_value")
  if [ -n "$normalized_self_actuation" ]; then
    printf 'self_actuation=%s\n' "$normalized_self_actuation" >> "$temp_meta"
  fi

  if [ -f "$explicit_skill_ids_file" ]; then
    while IFS= read -r skill_id; do
      skill_id=$(trim "$skill_id")
      [ -n "$skill_id" ] || continue
      skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
      if valid_id "$skill_id"; then
        printf 'explicit_skill=%s\n' "$skill_id" >> "$temp_meta"
      fi
    done < "$explicit_skill_ids_file"
  fi

  if [ -f "$attachment_ids_file" ]; then
    while IFS= read -r attachment_id; do
      attachment_id=$(trim "$attachment_id")
      [ -n "$attachment_id" ] || continue
      if valid_id "$attachment_id"; then
        printf 'attachment=%s\n' "$attachment_id" >> "$temp_meta"
      fi
    done < "$attachment_ids_file"
  fi

  if [ -s "$temp_meta" ]; then
    mv "$temp_meta" "$meta_file"
  else
    rm -f "$temp_meta" "$meta_file"
  fi
}

queue_meta_attachment_ids_to_file() {
  meta_file=$1
  out_file=$2
  : > "$out_file"
  [ -f "$meta_file" ] || return 0

  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      run_mode=*)
        ;;
      assistant_mode_id=*)
        ;;
      compute_budget=*)
        ;;
      command_exec_mode=*)
        ;;
      permission_mode=*)
        ;;
      programmer_review=*)
        ;;
      programmer_review_rounds=*)
        ;;
      assay_task_id=*)
        ;;
      automation_id=*)
        ;;
      reflexive_knowledge=*)
        ;;
      self_actuation=*)
        ;;
      explicit_skill=*)
        ;;
      attachment=*)
        attachment_id=$(trim "${line_trimmed#attachment=}")
        if valid_id "$attachment_id"; then
          printf '%s\n' "$attachment_id" >> "$out_file"
        fi
        ;;
      *)
        if valid_id "$line_trimmed"; then
          printf '%s\n' "$line_trimmed" >> "$out_file"
        fi
        ;;
    esac
  done < "$meta_file"

  dedup_ids=$(mktemp)
  awk '!seen[$0]++' "$out_file" > "$dedup_ids"
  mv "$dedup_ids" "$out_file"
}

queue_meta_explicit_skills_to_file() {
  meta_file=$1
  out_file=$2
  : > "$out_file"
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      explicit_skill=*)
        skill_value=${line_trimmed#explicit_skill=}
        skill_value=$(printf '%s' "$skill_value" | tr '[:upper:]' '[:lower:]')
        if valid_id "$skill_value"; then
          printf '%s\n' "$skill_value" >> "$out_file"
        fi
        ;;
    esac
  done < "$meta_file"
  dedup_file=$(mktemp)
  awk '!seen[$0]++' "$out_file" > "$dedup_file"
  mv "$dedup_file" "$out_file"
}

queue_meta_run_mode_from_file() {
  meta_file=$1
  if [ ! -f "$meta_file" ]; then
    printf '%s' "auto"
    return 0
  fi
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      run_mode=*)
        mode_value=${line_trimmed#run_mode=}
        mode_value=$(normalize_run_mode_name "$mode_value")
        if [ -n "$mode_value" ]; then
          printf '%s' "$mode_value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
  printf '%s' "auto"
}

queue_running_meta_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.meta' "$queue_dir"
}

queue_meta_assistant_mode_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      assistant_mode_id=*)
        mode_value=${line_trimmed#assistant_mode_id=}
        mode_value=$(normalize_assistant_mode_id "$mode_value")
        if [ -n "$mode_value" ]; then
          printf '%s' "$mode_value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_compute_budget_from_file() {
  meta_file=$1
  if [ ! -f "$meta_file" ]; then
    printf '%s' "auto"
    return 0
  fi
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      compute_budget=*)
        budget_value=${line_trimmed#compute_budget=}
        budget_value=$(normalize_compute_budget "$budget_value")
        printf '%s' "$budget_value"
        return 0
        ;;
    esac
  done < "$meta_file"
  printf '%s' "auto"
}

queue_meta_command_exec_mode_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      command_exec_mode=*)
        mode_value=${line_trimmed#command_exec_mode=}
        mode_value=$(normalize_command_exec_mode_value "$mode_value")
        if [ -n "$mode_value" ]; then
          printf '%s' "$mode_value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_permission_mode_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      permission_mode=*)
        mode_value=${line_trimmed#permission_mode=}
        mode_value=$(normalize_permission_mode_value "$mode_value")
        if [ -n "$mode_value" ]; then
          printf '%s' "$mode_value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_reflexive_knowledge_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      reflexive_knowledge=*)
        value=${line_trimmed#reflexive_knowledge=}
        value=$(normalize_reflexive_knowledge_value "$value")
        if [ -n "$value" ]; then
          printf '%s' "$value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_self_actuation_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      self_actuation=*)
        value=${line_trimmed#self_actuation=}
        value=$(normalize_self_actuation_value "$value")
        if [ -n "$value" ]; then
          printf '%s' "$value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_programmer_review_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      programmer_review=*)
        value=${line_trimmed#programmer_review=}
        value=$(normalize_programmer_review_enabled_value "$value")
        printf '%s' "$value"
        return 0
        ;;
    esac
  done < "$meta_file"
}

queue_meta_programmer_review_rounds_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      programmer_review_rounds=*)
        value=${line_trimmed#programmer_review_rounds=}
        value=$(normalize_programmer_review_rounds_value "$value" 2)
        printf '%s' "$value"
        return 0
        ;;
    esac
  done < "$meta_file"
}

queue_meta_assay_task_id_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      assay_task_id=*)
        value=${line_trimmed#assay_task_id=}
        value=$(normalize_assay_task_id_value "$value")
        if [ -n "$value" ]; then
          printf '%s' "$value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_meta_automation_id_from_file() {
  meta_file=$1
  [ -f "$meta_file" ] || return 0
  while IFS= read -r meta_line || [ -n "$meta_line" ]; do
    line_trimmed=$(trim "$meta_line")
    [ -n "$line_trimmed" ] || continue
    case "$line_trimmed" in
      automation_id=*)
        value=${line_trimmed#automation_id=}
        value=$(normalize_automation_id_value "$value")
        if [ -n "$value" ]; then
          printf '%s' "$value"
          return 0
        fi
        ;;
    esac
  done < "$meta_file"
}

queue_last_mode_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_mode' "$queue_dir"
}

queue_last_assistant_mode_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_assistant_mode' "$queue_dir"
}

queue_last_compute_budget_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_compute_budget' "$queue_dir"
}

queue_last_command_exec_mode_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_command_exec_mode' "$queue_dir"
}

queue_last_permission_mode_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_permission_mode' "$queue_dir"
}

queue_last_programmer_review_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_programmer_review' "$queue_dir"
}

queue_last_programmer_review_rounds_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_programmer_review_rounds' "$queue_dir"
}

queue_last_assay_task_id_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_assay_task_id' "$queue_dir"
}

queue_last_reflexive_knowledge_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_reflexive_knowledge' "$queue_dir"
}

queue_last_self_actuation_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/last_self_actuation' "$queue_dir"
}

queue_item_id_from_path() {
  file_path=$1
  file_name=$(basename "$file_path")
  item_id=${file_name#*__}
  item_id=${item_id%.txt}
  printf '%s' "$item_id"
}

queue_item_order_from_path() {
  file_path=$1
  file_name=$(basename "$file_path")
  order_value=${file_name%%__*}
  case "$order_value" in
    -[0-9]*|[0-9]*)
      if [ -n "$order_value" ]; then
        printf '%s' "$order_value"
        return 0
      fi
      ;;
  esac
  printf '%s' "0"
}

queue_pending_paths_sorted() {
  pending_dir=$1
  find "$pending_dir" -maxdepth 1 -type f -name '*__*.txt' 2>/dev/null \
    | awk -F/ '
      {
        name = $NF
        split(name, parts, "__")
        order = parts[1]
        if (order ~ /^-?[0-9]+$/) {
          print order "\t" $0
        }
      }
    ' \
    | sort -n -k1,1 \
    | cut -f2-
}

queue_first_pending_path() {
  pending_dir=$1
  queue_pending_paths_sorted "$pending_dir" | sed -n '1p'
}

queue_find_pending_path_by_id() {
  pending_dir=$1
  item_id=$2
  find "$pending_dir" -maxdepth 1 -type f -name "*__${item_id}.txt" 2>/dev/null | sed -n '1p'
}

queue_item_ids_to_file() {
  raw_ids=$1
  out_file=$2
  : > "$out_file"
  printf '%s\n' "$raw_ids" \
    | tr ',[:space:]' '\n' \
    | while IFS= read -r item_id || [ -n "$item_id" ]; do
        item_id=$(trim "$item_id")
        [ -n "$item_id" ] || continue
        if valid_id "$item_id"; then
          printf '%s\n' "$item_id"
        fi
      done \
    | awk '!seen[$0]++' > "$out_file"
}

queue_pending_count() {
  pending_dir=$1
  find "$pending_dir" -maxdepth 1 -type f -name '*__*.txt' 2>/dev/null | wc -l | tr -d ' '
}

queue_running_active_for_dir() {
  queue_dir=$1
  running_file="$queue_dir/running.txt"
  running_pid_file="$queue_dir/running.pid"
  running_pid=$(read_file_line "$running_pid_file" "")
  if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    printf '%s' "1"
    return 0
  fi
  if [ ! -f "$running_file" ]; then
    printf '%s' "0"
    return 0
  fi

  running_started=$(read_file_line "$queue_dir/running.started" "0")
  case "$running_started" in
    ""|*[!0-9]*)
      running_started=0
      ;;
  esac
  if [ "$running_started" -le 0 ]; then
    printf '%s' "0"
    return 0
  fi

  running_now=$(date +%s 2>/dev/null || printf '0')
  case "$running_now" in
    ""|*[!0-9]*)
      running_now=0
      ;;
  esac
  if [ "$running_now" -le 0 ]; then
    printf '%s' "1"
    return 0
  fi

  running_age=$((running_now - running_started))
  if [ "$running_age" -lt 0 ]; then
    running_age=0
  fi
  missing_pid_grace=$(queue_missing_pid_grace_sec)
  if [ "$running_age" -le "$missing_pid_grace" ]; then
    printf '%s' "1"
    return 0
  fi
  printf '%s' "0"
}

queue_state_for_conversation() {
  conv_dir=$1
  ensure_queue_layout "$conv_dir"

  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  pending_dir=$(queue_pending_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  last_status=$(read_file_line "$queue_dir/last_status" "")
  first_pending_path=$(queue_first_pending_path "$pending_dir")
  first_id=""

  if [ -n "$first_pending_path" ]; then
    first_id=$(queue_item_id_from_path "$first_pending_path")
  fi

  pending_count=$(queue_pending_count "$pending_dir")
  running=$(queue_running_active_for_dir "$queue_dir")

  done=0
  if [ "$running" -eq 0 ] && [ "$pending_count" -eq 0 ] && [ "$last_status" = "done" ]; then
    done=1
  fi

  printf 'pending=%s\n' "$pending_count"
  printf 'running=%s\n' "$running"
  printf 'done=%s\n' "$done"
  printf 'last_status=%s\n' "$last_status"
  printf 'first_id=%s\n' "$first_id"
}

queue_state_for_conversation_light() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  last_status=$(read_file_line "$queue_dir/last_status" "")
  running_id=$(read_file_line "$queue_dir/running.id" "")

  running=$(queue_running_active_for_dir "$queue_dir")

  pending_count=0
  done=0
  if [ "$running" -eq 0 ] && [ "$pending_count" -eq 0 ] && [ "$last_status" = "done" ]; then
    done=1
  fi

  first_id=""
  if [ "$running" -eq 1 ] && [ -n "$running_id" ]; then
    first_id=$running_id
  fi

  printf 'pending=%s\n' "$pending_count"
  printf 'running=%s\n' "$running"
  printf 'done=%s\n' "$done"
  printf 'last_status=%s\n' "$last_status"
  printf 'first_id=%s\n' "$first_id"
}

queue_clear_running_state() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  rm -f "$queue_dir/running.txt" "$queue_dir/running.id" "$queue_dir/running.anchor" "$queue_dir/running.started" "$queue_dir/running.started_iso" "$queue_dir/running.stream_session" "$queue_dir/running.event_id" "$queue_dir/running.meta" "$queue_dir/running.pid" "$queue_dir/running.stop"
}

queue_requeue_running_state() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  running_id=$(read_file_line "$queue_dir/running.id" "")
  moved=0

  if [ -f "$running_file" ]; then
    if ! valid_id "$running_id"; then
      running_id=$(new_id)
    fi
    order=$(queue_allocate_order "$conv_dir" "head")
    requeued_path=$(queue_item_file_for "$conv_dir" "$order" "$running_id")
    if mv "$running_file" "$requeued_path" 2>/dev/null; then
      moved=1
      if [ -f "$running_meta_file" ]; then
        mv "$running_meta_file" "$(queue_item_meta_for_path "$requeued_path")" 2>/dev/null || true
      fi
    fi
  fi

  queue_clear_running_state "$conv_dir"
  printf '%s' "$moved"
}

latest_run_event_file_for_conversation() {
  conv_dir=$1
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  if [ ! -d "$events_dir" ]; then
    printf '%s' ""
    return 0
  fi
  ls "$events_dir"/*.json 2>/dev/null | sort | tail -n 1
}

run_event_field_from_file() {
  event_file=$1
  field_name=$2
  if [ ! -f "$event_file" ]; then
    printf '%s' ""
    return 0
  fi
  sed -n "s/.*\"$field_name\":\"\\([^\"]*\\)\".*/\\1/p" "$event_file" | sed -n '1p'
}

run_event_status_is_terminal() {
  status_value=$(trim "$1")
  case "$status_value" in
    done|error|cancelled|timeout|awaiting_decision|awaiting_approval)
      return 0
      ;;
  esac
  return 1
}

append_stale_error_run_event_for_conversation() {
  conv_dir=$1
  reason_text=$2
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_anchor=$(trim "$(read_file_line "$(queue_running_anchor_file_for "$conv_dir")" "")")
  running_started_epoch=$(trim "$(read_file_line "$queue_dir/running.started" "0")")
  case "$running_started_epoch" in
    ""|*[!0-9]*)
      running_started_epoch=0
      ;;
  esac
  started_iso=$(trim "$(read_file_line "$(queue_running_started_iso_file_for "$conv_dir")" "")")
  if [ -z "$started_iso" ] && [ "$running_started_epoch" -gt 0 ]; then
    started_iso=$(iso_utc_from_epoch "$running_started_epoch")
  fi
  if [ -z "$started_iso" ]; then
    started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
  fi
  finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")

  latest_event_file=$(latest_run_event_file_for_conversation "$conv_dir")
  latest_status=$(run_event_field_from_file "$latest_event_file" "status")
  latest_id=$(run_event_field_from_file "$latest_event_file" "id")
  if run_event_status_is_terminal "$latest_status"; then
    if [ -n "$running_event_id" ] && [ -n "$latest_id" ] && [ "$running_event_id" = "$latest_id" ]; then
      return 0
    fi
  fi

  reason_clean=$(trim "$reason_text")
  if [ -z "$reason_clean" ]; then
    reason_clean="run state became stale"
  fi
  stream_preview=$(running_stream_preview_for_conversation "$conv_dir")
  if [ -z "$(trim "$stream_preview")" ]; then
    ts_now=$(date +"%H:%M:%S" 2>/dev/null || printf '%s' "00:00:00")
    stream_preview=$(cat <<EOF
[$ts_now] Run ended unexpectedly before a terminal event was captured.
[$ts_now] Stale runtime lock recovered: $reason_clean.
EOF
)
  fi
  state_preview=$(sed -n '1,120p' "$conv_dir/agent/.state" 2>/dev/null || true)
  tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
  task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "error" "$state_preview")
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  assay_task_id=$(queue_meta_assay_task_id_from_file "$running_meta_file")
  model_name=$(read_file_line "$conv_dir/model" "$(default_model)")

  summary_text=$(cat <<EOF
Outcome: Run terminated unexpectedly before finalization.
Verification Evidence: Runtime lock recovery detected stale run state ($reason_clean).
Risks: Partial output may omit intended verification or synthesis.
Next Action: Re-run from the latest checkpoint and validate completion evidence.
Next Improvement: Investigate root cause of stale runtime lock and signal handling.
EOF
)

  event_json=$(build_run_event_json \
    "error" \
    "$started_iso" \
    "$finished_iso" \
    "$model_name" \
    "" \
    "[]" \
    "$stream_preview" \
    "$reason_clean" \
    "" \
    "$state_preview" \
    "" \
    "" \
    "$summary_text" \
    "$reason_clean" \
    "$running_event_id" \
    "$task_status_json" \
    "$running_anchor" \
    "$assay_task_id" \
    "" \
    "")
  append_run_event_json "$conv_dir" "$event_json"
}

queue_running_stale_reason_for_conversation() {
  conv_dir=$1
  ensure_queue_layout "$conv_dir"
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  pending_dir=$(queue_pending_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  running_pid=$(read_file_line "$queue_dir/running.pid" "")

  running_present=0
  if [ -f "$running_file" ]; then
    running_present=1
  elif [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    running_present=1
  fi
  if [ "$running_present" -ne 1 ]; then
    printf '%s' ""
    return 0
  fi

  running_started=$(read_file_line "$queue_dir/running.started" "0")
  case "$running_started" in
    ""|*[!0-9]*)
      running_started=0
      ;;
  esac
  run_budget_hint=${ARTIFICER_RUN_TIME_BUDGET_SEC:-900}
  case "$run_budget_hint" in
    ""|*[!0-9]*)
      run_budget_hint=900
      ;;
  esac
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  running_compute_budget=$(queue_meta_compute_budget_from_file "$running_meta_file")
  running_compute_budget=$(normalize_compute_budget "$running_compute_budget")
  stale_timeout_sec=$(compute_budget_stale_timeout_sec "$running_compute_budget" "$run_budget_hint")
  running_now=$(date +%s 2>/dev/null || printf '0')
  case "$running_now" in
    ""|*[!0-9]*)
      running_now=0
      ;;
  esac
  running_age=0
  if [ "$running_started" -gt 0 ] && [ "$running_now" -gt "$running_started" ]; then
    running_age=$((running_now - running_started))
  fi

  if [ -n "$running_pid" ] && ! kill -0 "$running_pid" 2>/dev/null; then
    printf '%s' "run process is no longer active"
    return 0
  fi
  if [ -z "$running_pid" ]; then
    if [ "$running_started" -le 0 ]; then
      printf '%s' "run lock has no worker pid"
      return 0
    fi
    missing_pid_grace=$(queue_missing_pid_grace_sec)
    if [ "$running_age" -gt "$missing_pid_grace" ]; then
      printf '%s' "run lock has no worker pid (>${missing_pid_grace}s)"
      return 0
    fi
  fi
  if [ "$running_started" -gt 0 ] && [ "$running_age" -gt "$stale_timeout_sec" ]; then
    printf '%s' "run exceeded stale timeout (${stale_timeout_sec}s)"
    return 0
  fi
  queue_last_status=$(trim "$(read_file_line "$queue_dir/last_status" "")")
  pending_count=$(queue_pending_count "$pending_dir")
  [ -n "$pending_count" ] || pending_count=0
  if [ "$queue_last_status" = "error" ] && [ "$pending_count" = "0" ]; then
    printf '%s' "run state became stale after error"
    return 0
  fi
  printf '%s' ""
}

queue_recover_stale_running_state_for_conversation() {
  conv_dir=$1
  reason_text=$2
  ensure_queue_layout "$conv_dir"
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  running_id=$(trim "$(read_file_line "$queue_dir/running.id" "")")
  reason_clean=$(trim "$reason_text")
  if [ -z "$reason_clean" ]; then
    reason_clean="run state became stale"
  fi

  if [ -f "$running_file" ] && [ -n "$running_id" ] && valid_id "$running_id"; then
    requeued_running=$(queue_requeue_running_state "$conv_dir")
    if [ "$requeued_running" = "1" ]; then
      printf '%s\n' "queued" > "$queue_dir/last_status"
      printf '%s\n' "stale run was requeued for retry" > "$queue_dir/last_error"
      date +%s > "$queue_dir/last_done"
      printf '%s' "requeued"
      return 0
    fi
  fi

  append_stale_error_run_event_for_conversation "$conv_dir" "$reason_clean"
  queue_clear_running_state "$conv_dir"
  printf '%s\n' "error" > "$queue_dir/last_status"
  printf '%s\n' "$reason_clean" > "$queue_dir/last_error"
  date +%s > "$queue_dir/last_done"
  printf '%s' "cleared"
}

queue_finalize_for_run_item() {
  conv_dir=$1
  item_id=$2
  finish_status=$3
  finish_error=$4

  [ -d "$conv_dir" ] || return 0
  if [ -z "$item_id" ] || ! valid_id "$item_id"; then
    return 0
  fi

  case "$finish_status" in
    done|error|cancelled|awaiting_decision|awaiting_approval) ;;
    *)
      finish_status="done"
      ;;
  esac

  ensure_queue_layout "$conv_dir"
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_file="$queue_dir/running.txt"
  running_id=$(read_file_line "$queue_dir/running.id" "")

  if [ ! -f "$running_file" ]; then
    return 0
  fi
  if [ -n "$running_id" ] && [ "$running_id" != "$item_id" ]; then
    return 0
  fi

  queue_clear_running_state "$conv_dir"
  printf '%s\n' "$finish_status" > "$queue_dir/last_status"
  if [ "$finish_status" = "error" ]; then
    printf '%s\n' "$finish_error" > "$queue_dir/last_error"
  else
    rm -f "$queue_dir/last_error"
  fi
  date +%s > "$queue_dir/last_done"
}
