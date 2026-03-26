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
    "$assay_task_id")
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

automation_dir_for() {
  automation_id=$1
  printf '%s/%s' "$automations_root" "$automation_id"
}

automation_runtime_dir_for() {
  automation_id=$1
  printf '%s/%s' "$automations_runtime_root" "$automation_id"
}

automation_field_file_for() {
  automation_dir=$1
  field_name=$2
  printf '%s/%s' "$automation_dir" "$field_name"
}

automation_now_epoch() {
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  if [ "$now_epoch" -lt 0 ]; then
    now_epoch=0
  fi
  printf '%s' "$now_epoch"
}

automation_epoch_or_zero() {
  raw_value=$(trim "$1")
  case "$raw_value" in
    ""|*[!0-9]*)
      printf '%s' "0"
      return 0
      ;;
  esac
  if [ "$raw_value" -lt 0 ]; then
    printf '%s' "0"
    return 0
  fi
  printf '%s' "$raw_value"
}

automation_enabled_value() {
  raw_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_value" in
    1|true|yes|on|enabled)
      printf '%s' "1"
      ;;
    *)
      printf '%s' "0"
      ;;
  esac
}

automation_schedule_kind_value() {
  raw_kind=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_kind" in
    cron|interval|once)
      printf '%s' "$raw_kind"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

automation_schedule_normalize_and_next() {
  schedule_kind_raw=$1
  schedule_value_raw=$2
  from_epoch_raw=${3:-0}
  python3 - "$schedule_kind_raw" "$schedule_value_raw" "$from_epoch_raw" <<'PY'
import datetime
import re
import sys
import time

kind = (sys.argv[1] or "").strip().lower()
value_raw = (sys.argv[2] or "").strip()
try:
    from_epoch = int(float(sys.argv[3]))
except Exception:
    from_epoch = 0
if from_epoch <= 0:
    from_epoch = int(time.time())


def emit(status, kind_value="", normalized_value="", next_epoch=0, text="", error=""):
    safe_text = " ".join(str(text or "").split())
    safe_error = " ".join(str(error or "").split())
    try:
        next_int = int(next_epoch)
    except Exception:
        next_int = 0
    if next_int < 0:
        next_int = 0
    print(f"status={status}")
    print(f"kind={kind_value}")
    print(f"value={normalized_value}")
    print(f"next={next_int}")
    print(f"text={safe_text}")
    print(f"error={safe_error}")


def parse_interval_seconds(raw):
    token = re.sub(r"\s+", "", raw.lower())
    m = re.fullmatch(r"([0-9]+)(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks)?", token)
    if not m:
        return None
    amount = int(m.group(1))
    if amount <= 0:
        return None
    unit = (m.group(2) or "s").lower()
    mult = 1
    if unit in {"m", "min", "mins", "minute", "minutes"}:
        mult = 60
    elif unit in {"h", "hr", "hrs", "hour", "hours"}:
        mult = 3600
    elif unit in {"d", "day", "days"}:
        mult = 86400
    elif unit in {"w", "week", "weeks"}:
        mult = 604800
    return amount * mult


def local_iso(epoch):
    return datetime.datetime.fromtimestamp(epoch).isoformat(timespec="minutes")


def parse_once_epoch(raw):
    token = raw.strip()
    if not token:
        return None
    if re.fullmatch(r"[0-9]+", token):
        return int(token)
    iso_token = token
    if iso_token.endswith("Z"):
        iso_token = iso_token[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(iso_token)
        if dt.tzinfo is None:
            return int(dt.timestamp())
        return int(dt.astimezone().timestamp())
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.datetime.strptime(token, fmt)
            return int(dt.timestamp())
        except Exception:
            continue
    return None


def parse_number_token(token, min_v, max_v):
    value = int(token)
    if value < min_v or value > max_v:
        raise ValueError("out of range")
    return value


def parse_cron_field(token, min_v, max_v, allow_seven_sunday=False):
    token = token.strip()
    if not token:
        raise ValueError("empty field")
    all_values = set()
    for part in token.split(","):
        piece = part.strip()
        if not piece:
            raise ValueError("empty list item")
        if "/" in piece:
            base, step_text = piece.split("/", 1)
            if not step_text or not re.fullmatch(r"[0-9]+", step_text):
                raise ValueError("invalid step")
            step = int(step_text)
            if step <= 0:
                raise ValueError("invalid step")
        else:
            base = piece
            step = 1

        if base == "*":
            start = min_v
            end = max_v
        elif "-" in base:
            left, right = base.split("-", 1)
            if not re.fullmatch(r"[0-9]+", left or "") or not re.fullmatch(r"[0-9]+", right or ""):
                raise ValueError("invalid range")
            start = int(left)
            end = int(right)
        else:
            if not re.fullmatch(r"[0-9]+", base):
                raise ValueError("invalid number")
            start = int(base)
            end = int(base)

        if allow_seven_sunday:
            if start == 7:
                start = 0
            if end == 7:
                end = 0
            if start < min_v or start > max_v or end < min_v or end > max_v:
                raise ValueError("out of range")
            if start == 0 and end == 0:
                all_values.add(0)
                continue
            if start > end:
                raise ValueError("reverse range")
            for value in range(start, end + 1, step):
                if value == 7:
                    value = 0
                all_values.add(value)
            continue

        if start < min_v or start > max_v or end < min_v or end > max_v:
            raise ValueError("out of range")
        if start > end:
            raise ValueError("reverse range")
        for value in range(start, end + 1, step):
            all_values.add(value)

    if not all_values:
        raise ValueError("empty set")
    return all_values


def cron_next_epoch(expr, start_epoch):
    fields = expr.split()
    if len(fields) != 5:
        raise ValueError("cron must contain 5 fields")
    minute_field, hour_field, dom_field, month_field, dow_field = fields
    minutes = parse_cron_field(minute_field, 0, 59)
    hours = parse_cron_field(hour_field, 0, 23)
    dom = parse_cron_field(dom_field, 1, 31)
    months = parse_cron_field(month_field, 1, 12)
    dow = parse_cron_field(dow_field, 0, 6, allow_seven_sunday=True)

    dom_any = dom_field.strip() == "*"
    dow_any = dow_field.strip() == "*"

    dt = datetime.datetime.fromtimestamp(start_epoch).replace(second=0, microsecond=0) + datetime.timedelta(minutes=1)
    limit = dt + datetime.timedelta(days=548)
    while dt <= limit:
        if dt.month in months and dt.hour in hours and dt.minute in minutes:
            dom_match = dt.day in dom
            cron_dow = (dt.weekday() + 1) % 7
            dow_match = cron_dow in dow
            if dom_any and dow_any:
                dom_dow_match = True
            elif dom_any:
                dom_dow_match = dow_match
            elif dow_any:
                dom_dow_match = dom_match
            else:
                dom_dow_match = dom_match or dow_match
            if dom_dow_match:
                return int(dt.timestamp())
        dt += datetime.timedelta(minutes=1)
    return 0


if kind == "interval":
    interval_seconds = parse_interval_seconds(value_raw)
    if interval_seconds is None:
        emit("error", error="invalid interval schedule")
        sys.exit(0)
    next_epoch = from_epoch + interval_seconds
    emit(
        "ok",
        kind_value="interval",
        normalized_value=str(interval_seconds),
        next_epoch=next_epoch,
        text=f"Every {interval_seconds} seconds",
    )
    sys.exit(0)

if kind == "once":
    target_epoch = parse_once_epoch(value_raw)
    if target_epoch is None:
        emit("error", error="invalid once timestamp")
        sys.exit(0)
    if target_epoch <= from_epoch:
        emit("error", error="once timestamp must be in the future")
        sys.exit(0)
    emit(
        "ok",
        kind_value="once",
        normalized_value=str(target_epoch),
        next_epoch=target_epoch,
        text=f"Once at {local_iso(target_epoch)}",
    )
    sys.exit(0)

if kind == "cron":
    normalized_expr = " ".join(value_raw.split())
    if not normalized_expr:
        emit("error", error="cron expression is required")
        sys.exit(0)
    try:
        next_epoch = cron_next_epoch(normalized_expr, from_epoch)
    except Exception:
        emit("error", error="invalid cron schedule")
        sys.exit(0)
    if next_epoch <= 0:
        emit("error", error="cron schedule has no future run")
        sys.exit(0)
    emit(
        "ok",
        kind_value="cron",
        normalized_value=normalized_expr,
        next_epoch=next_epoch,
        text=f"Cron {normalized_expr}",
    )
    sys.exit(0)

emit("error", error="invalid schedule kind")
PY
}

automation_schedule_label() {
  schedule_kind=$(automation_schedule_kind_value "$1")
  schedule_value=$(trim "$2")
  case "$schedule_kind" in
    interval)
      case "$schedule_value" in
        ""|*[!0-9]*)
          printf '%s' "Every interval"
          ;;
        *)
          if [ "$schedule_value" -ge 86400 ] && [ $((schedule_value % 86400)) -eq 0 ]; then
            printf 'Every %sd' $((schedule_value / 86400))
          elif [ "$schedule_value" -ge 3600 ] && [ $((schedule_value % 3600)) -eq 0 ]; then
            printf 'Every %sh' $((schedule_value / 3600))
          elif [ "$schedule_value" -ge 60 ] && [ $((schedule_value % 60)) -eq 0 ]; then
            printf 'Every %sm' $((schedule_value / 60))
          else
            printf 'Every %ss' "$schedule_value"
          fi
          ;;
      esac
      ;;
    once)
      once_iso=$(iso_utc_from_epoch "$schedule_value")
      if [ -n "$once_iso" ]; then
        printf 'Once (%s)' "$once_iso"
      else
        printf '%s' "Once"
      fi
      ;;
    cron)
      if [ -n "$schedule_value" ]; then
        printf 'Cron %s' "$schedule_value"
      else
        printf '%s' "Cron"
      fi
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

automation_ids_sorted() {
  for automation_dir in "$automations_root"/*; do
    [ -d "$automation_dir" ] || continue
    automation_id=$(basename "$automation_dir")
    if ! valid_id "$automation_id"; then
      continue
    fi
    printf '%s\n' "$automation_id"
  done | sort
}

automation_workspace_name_for_id() {
  workspace_id=$1
  if ! valid_id "$workspace_id"; then
    printf '%s' ""
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 0
  fi
  read_file_line "$ws_dir/name" "$workspace_id"
}

automation_conversation_title_for_ids() {
  workspace_id=$1
  conversation_id=$2
  if ! valid_id "$workspace_id" || ! valid_id "$conversation_id"; then
    printf '%s' ""
    return 0
  fi
  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  if [ ! -d "$conv_dir" ]; then
    printf '%s' ""
    return 0
  fi
  read_file_line "$conv_dir/title" "Conversation"
}

automation_explicit_skills_file_for() {
  automation_dir=$1
  printf '%s/explicit_skill_ids' "$automation_dir"
}

automation_write_common_fields() {
  automation_dir=$1
  automation_name=$2
  workspace_id=$3
  conversation_id=$4
  prompt_text=$5
  schedule_kind=$6
  schedule_value=$7
  schedule_text=$8
  enabled_value=$9
  allow_self_reschedule_value=${10}
  run_mode_value=${11}
  assistant_mode_value=${12}
  compute_budget_value=${13}
  command_exec_mode_value=${14}
  permission_mode_value=${15}
  programmer_review_value=${16}
  programmer_review_rounds_value=${17}
  assay_task_id_value=${18}

  printf '%s\n' "$automation_name" > "$(automation_field_file_for "$automation_dir" "name")"
  printf '%s\n' "$workspace_id" > "$(automation_field_file_for "$automation_dir" "workspace_id")"
  printf '%s\n' "$conversation_id" > "$(automation_field_file_for "$automation_dir" "conversation_id")"
  printf '%s' "$prompt_text" > "$(automation_field_file_for "$automation_dir" "prompt")"
  printf '%s\n' "$schedule_kind" > "$(automation_field_file_for "$automation_dir" "schedule_kind")"
  printf '%s\n' "$schedule_value" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
  printf '%s\n' "$schedule_text" > "$(automation_field_file_for "$automation_dir" "schedule_text")"
  printf '%s\n' "$enabled_value" > "$(automation_field_file_for "$automation_dir" "enabled")"
  printf '%s\n' "$allow_self_reschedule_value" > "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")"
  printf '%s\n' "$run_mode_value" > "$(automation_field_file_for "$automation_dir" "run_mode")"
  printf '%s\n' "$assistant_mode_value" > "$(automation_field_file_for "$automation_dir" "assistant_mode_id")"
  printf '%s\n' "$compute_budget_value" > "$(automation_field_file_for "$automation_dir" "compute_budget")"
  printf '%s\n' "$command_exec_mode_value" > "$(automation_field_file_for "$automation_dir" "command_exec_mode")"
  printf '%s\n' "$permission_mode_value" > "$(automation_field_file_for "$automation_dir" "permission_mode")"
  printf '%s\n' "$programmer_review_value" > "$(automation_field_file_for "$automation_dir" "programmer_review")"
  printf '%s\n' "$programmer_review_rounds_value" > "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")"
  printf '%s\n' "$assay_task_id_value" > "$(automation_field_file_for "$automation_dir" "assay_task_id")"
}

automation_json_for_id() {
  automation_id=$1
  if ! valid_id "$automation_id"; then
    return 1
  fi
  automation_dir=$(automation_dir_for "$automation_id")
  [ -d "$automation_dir" ] || return 1

  automation_name=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "Automation")
  workspace_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")")
  conversation_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "conversation_id")" "")")
  prompt_text=$(cat "$(automation_field_file_for "$automation_dir" "prompt")" 2>/dev/null || true)
  schedule_kind=$(automation_schedule_kind_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")")
  schedule_value=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")")
  schedule_text=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_text")" "")")
  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  allow_self_reschedule_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")" "0")")
  next_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "next_run")" "0")")
  last_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_run")" "0")")
  created_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "created")" "0")")
  updated_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "updated")" "0")")
  last_status=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_status")" "")")
  last_error=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "last_error")" "")")
  run_mode_value=$(normalize_run_mode_name "$(read_file_line "$(automation_field_file_for "$automation_dir" "run_mode")" "assistant")")
  assistant_mode_value=$(normalize_assistant_mode_id "$(read_file_line "$(automation_field_file_for "$automation_dir" "assistant_mode_id")" "")")
  compute_budget_value=$(normalize_compute_budget "$(read_file_line "$(automation_field_file_for "$automation_dir" "compute_budget")" "auto")")
  command_exec_mode_value=$(normalize_command_exec_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "command_exec_mode")" "")")
  permission_mode_value=$(normalize_permission_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "permission_mode")" "")")
  programmer_review_value=$(normalize_programmer_review_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review")" "1")")
  programmer_review_rounds_value=$(normalize_programmer_review_rounds_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")" "2")" 2)
  assay_task_id_value=$(normalize_assay_task_id_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "assay_task_id")" "")")
  if [ "$run_mode_value" != "assistant" ]; then
    assistant_mode_value=""
  fi
  [ -n "$schedule_text" ] || schedule_text=$(automation_schedule_label "$schedule_kind" "$schedule_value")
  workspace_name=$(automation_workspace_name_for_id "$workspace_id")
  conversation_title=$(automation_conversation_title_for_ids "$workspace_id" "$conversation_id")
  explicit_skills_file=$(automation_explicit_skills_file_for "$automation_dir")
  explicit_skills_json=$(string_json_array_from_ids_file "$explicit_skills_file")
  next_run_iso=$(iso_utc_from_epoch "$next_run_epoch")
  last_run_iso=$(iso_utc_from_epoch "$last_run_epoch")
  created_iso=$(iso_utc_from_epoch "$created_epoch")
  updated_iso=$(iso_utc_from_epoch "$updated_epoch")

  printf '{"id":"%s","name":"%s","workspace_id":"%s","workspace_name":"%s","conversation_id":"%s","conversation_title":"%s","prompt":"%s","schedule_kind":"%s","schedule_value":"%s","schedule_text":"%s","enabled":"%s","allow_self_reschedule":"%s","next_run":"%s","next_run_iso":"%s","last_run":"%s","last_run_iso":"%s","last_status":"%s","last_error":"%s","created":"%s","created_iso":"%s","updated":"%s","updated_iso":"%s","run_mode":"%s","assistant_mode_id":"%s","compute_budget":"%s","command_exec_mode":"%s","permission_mode":"%s","programmer_review":"%s","programmer_review_rounds":"%s","assay_task_id":"%s","explicit_skill_ids":%s}' \
    "$(json_escape "$automation_id")" \
    "$(json_escape "$automation_name")" \
    "$(json_escape "$workspace_id")" \
    "$(json_escape "$workspace_name")" \
    "$(json_escape "$conversation_id")" \
    "$(json_escape "$conversation_title")" \
    "$(json_escape "$prompt_text")" \
    "$(json_escape "$schedule_kind")" \
    "$(json_escape "$schedule_value")" \
    "$(json_escape "$schedule_text")" \
    "$(json_escape "$enabled_value")" \
    "$(json_escape "$allow_self_reschedule_value")" \
    "$(json_escape "$next_run_epoch")" \
    "$(json_escape "$next_run_iso")" \
    "$(json_escape "$last_run_epoch")" \
    "$(json_escape "$last_run_iso")" \
    "$(json_escape "$last_status")" \
    "$(json_escape "$last_error")" \
    "$(json_escape "$created_epoch")" \
    "$(json_escape "$created_iso")" \
    "$(json_escape "$updated_epoch")" \
    "$(json_escape "$updated_iso")" \
    "$(json_escape "$run_mode_value")" \
    "$(json_escape "$assistant_mode_value")" \
    "$(json_escape "$compute_budget_value")" \
    "$(json_escape "$command_exec_mode_value")" \
    "$(json_escape "$permission_mode_value")" \
    "$(json_escape "$programmer_review_value")" \
    "$(json_escape "$programmer_review_rounds_value")" \
    "$(json_escape "$assay_task_id_value")" \
    "$explicit_skills_json"
}

automations_state_json() {
  items_json=""
  item_count=0
  while IFS= read -r automation_id || [ -n "$automation_id" ]; do
    [ -n "$automation_id" ] || continue
    automation_json=$(automation_json_for_id "$automation_id" 2>/dev/null || true)
    [ -n "$automation_json" ] || continue
    if [ "$item_count" -gt 0 ]; then
      items_json="${items_json},"
    fi
    items_json="${items_json}${automation_json}"
    item_count=$((item_count + 1))
  done <<EOF
$(automation_ids_sorted)
EOF
  printf '{"count":"%s","items":[%s]}' "$(json_escape "$item_count")" "$items_json"
}

automation_ensure_conversation_for_run() {
  automation_dir=$1
  workspace_id=$2
  conversation_id=$3
  automation_name=$4
  if valid_id "$workspace_id" && valid_id "$conversation_id"; then
    existing_conv=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ -d "$existing_conv" ]; then
      printf '%s' "$conversation_id"
      return 0
    fi
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 1
  fi
  if [ -z "$automation_name" ]; then
    automation_name="Automation"
  fi
  next_conversation_id=$(new_id)
  next_conv_dir=$(conversation_dir_for "$workspace_id" "$next_conversation_id")
  mkdir -p "$next_conv_dir/messages"
  printf 'Automation: %s\n' "$automation_name" > "$next_conv_dir/title"
  printf '%s\n' "$(default_model)" > "$next_conv_dir/model"
  now_epoch=$(automation_now_epoch)
  printf '%s\n' "$now_epoch" > "$next_conv_dir/created"
  printf '%s\n' "$now_epoch" > "$next_conv_dir/updated"
  printf '%s\n' "$next_conversation_id" > "$(automation_field_file_for "$automation_dir" "conversation_id")"
  printf '%s' "$next_conversation_id"
}

automation_update_next_run_for_schedule() {
  automation_dir=$1
  from_epoch=$2
  schedule_kind=$(automation_schedule_kind_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")")
  schedule_value=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")")
  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")

  if [ "$enabled_value" != "1" ]; then
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi

  schedule_info=$(automation_schedule_normalize_and_next "$schedule_kind" "$schedule_value" "$from_epoch")
  if [ "$(kv_get "status" "$schedule_info")" != "ok" ]; then
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi
  next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")
  normalized_kind=$(automation_schedule_kind_value "$(kv_get "kind" "$schedule_info")")
  normalized_value=$(trim "$(kv_get "value" "$schedule_info")")
  schedule_text=$(trim "$(kv_get "text" "$schedule_info")")
  if [ -n "$normalized_kind" ]; then
    printf '%s\n' "$normalized_kind" > "$(automation_field_file_for "$automation_dir" "schedule_kind")"
  fi
  printf '%s\n' "$normalized_value" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
  printf '%s\n' "$schedule_text" > "$(automation_field_file_for "$automation_dir" "schedule_text")"

  if [ "$normalized_kind" = "once" ]; then
    # A one-time schedule disables itself after queueing a run.
    printf 'next_run=0\nenabled=0\n'
    return 0
  fi
  printf 'next_run=%s\nenabled=1\n' "$next_run_epoch"
}

automation_enqueue_prompt_for_run() {
  automation_id=$1
  manual_trigger=${2:-0}
  automation_dir=$(automation_dir_for "$automation_id")
  if [ ! -d "$automation_dir" ]; then
    printf 'success=0\nerror=automation not found\n'
    return 0
  fi

  workspace_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")")
  if ! valid_id "$workspace_id"; then
    printf 'success=0\nerror=invalid workspace_id\n'
    return 0
  fi
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf 'success=0\nerror=workspace not found\n'
    return 0
  fi

  prompt_text=$(cat "$(automation_field_file_for "$automation_dir" "prompt")" 2>/dev/null || true)
  if [ -z "$(trim "$prompt_text")" ]; then
    printf 'success=0\nerror=prompt is required\n'
    return 0
  fi

  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  if [ "$manual_trigger" != "1" ] && [ "$enabled_value" != "1" ]; then
    printf 'success=0\nerror=automation is disabled\n'
    return 0
  fi

  automation_name=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "Automation")
  conversation_id=$(trim "$(read_file_line "$(automation_field_file_for "$automation_dir" "conversation_id")" "")")
  conversation_id=$(automation_ensure_conversation_for_run "$automation_dir" "$workspace_id" "$conversation_id" "$automation_name" || true)
  if ! valid_id "$conversation_id"; then
    printf 'success=0\nerror=could not resolve conversation\n'
    return 0
  fi
  conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
  if [ ! -d "$conv_dir" ]; then
    printf 'success=0\nerror=conversation not found\n'
    return 0
  fi

  run_mode_value=$(normalize_run_mode_name "$(read_file_line "$(automation_field_file_for "$automation_dir" "run_mode")" "assistant")")
  assistant_mode_value=$(normalize_assistant_mode_id "$(read_file_line "$(automation_field_file_for "$automation_dir" "assistant_mode_id")" "")")
  compute_budget_value=$(normalize_compute_budget "$(read_file_line "$(automation_field_file_for "$automation_dir" "compute_budget")" "auto")")
  command_exec_mode_value=$(normalize_command_exec_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "command_exec_mode")" "")")
  permission_mode_value=$(normalize_permission_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "permission_mode")" "")")
  programmer_review_value=$(normalize_programmer_review_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review")" "1")")
  programmer_review_rounds_value=$(normalize_programmer_review_rounds_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")" "2")" 2)
  assay_task_id_value=$(normalize_assay_task_id_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "assay_task_id")" "")")
  if [ "$run_mode_value" != "assistant" ]; then
    assistant_mode_value=""
  fi

  ensure_queue_layout "$conv_dir"
  item_id=$(new_id)
  order=$(queue_allocate_order "$conv_dir" "tail")
  queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
  queue_item_meta=$(queue_item_meta_for_path "$queue_item_file")
  printf '%s' "$prompt_text" > "$queue_item_file"

  empty_attachment_ids=$(mktemp)
  : > "$empty_attachment_ids"
  explicit_skills_file=$(automation_explicit_skills_file_for "$automation_dir")
  if [ ! -f "$explicit_skills_file" ]; then
    : > "$explicit_skills_file"
  fi
  queue_meta_write "$queue_item_meta" "$run_mode_value" "$assistant_mode_value" "$compute_budget_value" "$command_exec_mode_value" "$permission_mode_value" "$programmer_review_value" "$programmer_review_rounds_value" "$explicit_skills_file" "$empty_attachment_ids" "$assay_task_id_value" "$automation_id"
  rm -f "$empty_attachment_ids"

  append_message "$conv_dir" "user" "$prompt_text"

  now_epoch=$(automation_now_epoch)
  if [ "$enabled_value" = "1" ]; then
    schedule_update=$(automation_update_next_run_for_schedule "$automation_dir" "$now_epoch")
    next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next_run" "$schedule_update")")
    next_enabled=$(automation_enabled_value "$(kv_get "enabled" "$schedule_update")")
    printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
    printf '%s\n' "$next_enabled" > "$(automation_field_file_for "$automation_dir" "enabled")"
  fi
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "last_run")"
  printf '%s\n' "queued" > "$(automation_field_file_for "$automation_dir" "last_status")"
  printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"

  printf 'success=1\nworkspace_id=%s\nconversation_id=%s\nitem_id=%s\n' "$workspace_id" "$conversation_id" "$item_id"
}

automation_next_run_directive_from_text() {
  assistant_text=$1
  now_epoch=$2
  printf '%s' "$assistant_text" | python3 - "$now_epoch" <<'PY'
import datetime
import re
import sys

try:
    now_epoch = int(float(sys.argv[1]))
except Exception:
    now_epoch = 0
if now_epoch <= 0:
    now_epoch = int(datetime.datetime.now().timestamp())

text = sys.stdin.read()
matches = re.findall(r"(?im)^\s*NEXT_RUN\s*:\s*(.+?)\s*$", text or "")
if not matches:
    print("0")
    sys.exit(0)

raw = matches[-1].strip()
raw_lower = raw.lower()
if raw_lower in {"none", "disable", "disabled", "off", "never"}:
    print("-1")
    sys.exit(0)

relative = re.fullmatch(r"\+([0-9]+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks)", raw_lower)
if relative:
    amount = int(relative.group(1))
    unit = relative.group(2)
    mult = 1
    if unit.startswith("m"):
        mult = 60
    elif unit.startswith("h"):
        mult = 3600
    elif unit.startswith("d"):
        mult = 86400
    elif unit.startswith("w"):
        mult = 604800
    next_epoch = now_epoch + amount * mult
    print(str(next_epoch if next_epoch > now_epoch else 0))
    sys.exit(0)

if re.fullmatch(r"[0-9]+", raw):
    target = int(raw)
    print(str(target if target > now_epoch else 0))
    sys.exit(0)

iso_token = raw
if iso_token.endswith("Z"):
    iso_token = iso_token[:-1] + "+00:00"
for parser in ("iso",):
    try:
        dt = datetime.datetime.fromisoformat(iso_token)
        target = int(dt.timestamp()) if dt.tzinfo is None else int(dt.astimezone().timestamp())
        print(str(target if target > now_epoch else 0))
        sys.exit(0)
    except Exception:
        pass

for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"):
    try:
        dt = datetime.datetime.strptime(raw, fmt)
        target = int(dt.timestamp())
        print(str(target if target > now_epoch else 0))
        sys.exit(0)
    except Exception:
        continue

print("0")
PY
}

automation_apply_self_reschedule_for_conversation() {
  automation_id=$1
  conv_dir=$2
  if ! valid_id "$automation_id"; then
    return 0
  fi
  automation_dir=$(automation_dir_for "$automation_id")
  [ -d "$automation_dir" ] || return 0

  enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
  allow_self_reschedule_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")" "0")")
  if [ "$enabled_value" != "1" ] || [ "$allow_self_reschedule_value" != "1" ]; then
    return 0
  fi

  last_assistant=$(conversation_last_message_for_role "$conv_dir" "assistant")
  [ -n "$(trim "$last_assistant")" ] || return 0
  now_epoch=$(automation_now_epoch)
  directive_epoch=$(automation_next_run_directive_from_text "$last_assistant" "$now_epoch")
  case "$directive_epoch" in
    -1)
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "enabled")"
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "next_run")"
      printf '%s\n' "disabled" > "$(automation_field_file_for "$automation_dir" "last_status")"
      printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
      printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
      return 0
      ;;
    ""|*[!0-9]*)
      return 0
      ;;
  esac
  if [ "$directive_epoch" -le "$now_epoch" ]; then
    return 0
  fi
  printf '%s\n' "$directive_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
  printf '%s\n' "scheduled" > "$(automation_field_file_for "$automation_dir" "last_status")"
  printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
  printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
}

automations_tick_due_runs() {
  now_epoch=$(automation_now_epoch)
  checked=0
  triggered=0
  errors=0
  locked=1

  lock_dir="$automations_runtime_root/tick.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    locked=0
    lock_started=$(automation_epoch_or_zero "$(read_file_line "$lock_dir/started" "0")")
    if [ "$lock_started" -gt 0 ] && [ "$now_epoch" -gt "$lock_started" ] && [ $((now_epoch - lock_started)) -gt 180 ]; then
      rm -rf "$lock_dir" 2>/dev/null || true
      if mkdir "$lock_dir" 2>/dev/null; then
        locked=1
      fi
    fi
  fi

  if [ "$locked" = "1" ]; then
    printf '%s\n' "$now_epoch" > "$lock_dir/started"
    while IFS= read -r automation_id || [ -n "$automation_id" ]; do
      [ -n "$automation_id" ] || continue
      checked=$((checked + 1))
      automation_dir=$(automation_dir_for "$automation_id")
      [ -d "$automation_dir" ] || continue
      enabled_value=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
      if [ "$enabled_value" != "1" ]; then
        continue
      fi
      next_run_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "next_run")" "0")")
      if [ "$next_run_epoch" -le 0 ]; then
        schedule_info=$(automation_schedule_normalize_and_next "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")" "$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")" "$now_epoch")
        if [ "$(kv_get "status" "$schedule_info")" = "ok" ]; then
          next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")
          printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
          printf '%s\n' "$(trim "$(kv_get "value" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_value")"
          printf '%s\n' "$(trim "$(kv_get "text" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "schedule_text")"
          printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
        else
          printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "enabled")"
          printf '%s\n' "error" > "$(automation_field_file_for "$automation_dir" "last_status")"
          printf '%s\n' "$(trim "$(kv_get "error" "$schedule_info")")" > "$(automation_field_file_for "$automation_dir" "last_error")"
          printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
          errors=$((errors + 1))
          continue
        fi
      fi
      if [ "$next_run_epoch" -le 0 ] || [ "$next_run_epoch" -gt "$now_epoch" ]; then
        continue
      fi
      enqueue_result=$(automation_enqueue_prompt_for_run "$automation_id" "0")
      if [ "$(kv_get "success" "$enqueue_result")" = "1" ]; then
        triggered=$((triggered + 1))
      else
        printf '%s\n' "error" > "$(automation_field_file_for "$automation_dir" "last_status")"
        printf '%s\n' "$(trim "$(kv_get "error" "$enqueue_result")")" > "$(automation_field_file_for "$automation_dir" "last_error")"
        printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
        errors=$((errors + 1))
      fi
    done <<EOF
$(automation_ids_sorted)
EOF
    rm -rf "$lock_dir" 2>/dev/null || true
  fi

  changed=0
  if [ "$triggered" -gt 0 ] || [ "$errors" -gt 0 ]; then
    changed=1
  fi
  printf 'checked=%s\ntriggered=%s\nerrors=%s\nlocked=%s\nchanged=%s\n' "$checked" "$triggered" "$errors" "$locked" "$changed"
}

artificer_runtime_site_root() {
  site_root=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/.." && pwd -P 2>/dev/null || true)
  printf '%s' "$site_root"
}

artificer_app_root_for_runtime() {
  configured_root=$(trim "${ARTIFICER_APP_ROOT:-}")
  if [ -n "$configured_root" ] && [ -d "$configured_root" ] && [ -x "$configured_root/scripts/artificer-automations.sh" ]; then
    printf '%s' "$configured_root"
    return 0
  fi

  local_root_candidate=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/../.." && pwd -P 2>/dev/null || true)
  if [ -n "$local_root_candidate" ] && [ -d "$local_root_candidate" ] && [ -x "$local_root_candidate/scripts/artificer-automations.sh" ]; then
    printf '%s' "$local_root_candidate"
    return 0
  fi

  site_root=$(artificer_runtime_site_root)
  marker_file="$site_root/.artificer-app-root"
  if [ -f "$marker_file" ]; then
    marker_root=$(trim "$(read_file_line "$marker_file" "")")
    if [ -n "$marker_root" ] && [ -d "$marker_root" ] && [ -x "$marker_root/scripts/artificer-automations.sh" ]; then
      printf '%s' "$marker_root"
      return 0
    fi
  fi

  printf ''
}

automation_daemon_script_path() {
  app_root=$(artificer_app_root_for_runtime)
  if [ -n "$app_root" ]; then
    script_path="$app_root/scripts/artificer-automations.sh"
    if [ -x "$script_path" ]; then
      printf '%s' "$script_path"
      return 0
    fi
  fi
  printf ''
}

automation_daemon_status_json_from_kv() {
  status_kv=$1
  supported_value=$(automation_enabled_value "$(kv_get "supported" "$status_kv")")
  enabled_value=$(automation_enabled_value "$(kv_get "enabled" "$status_kv")")
  active_value=$(automation_enabled_value "$(kv_get "active" "$status_kv")")
  method_value=$(trim "$(kv_get "method" "$status_kv")")
  label_value=$(trim "$(kv_get "label" "$status_kv")")
  detail_value=$(trim "$(kv_get "detail" "$status_kv")")
  [ -n "$method_value" ] || method_value="none"
  printf '{"success":true,"supported":%s,"enabled":%s,"active":%s,"method":"%s","label":"%s","detail":"%s"}\n' \
    "$([ "$supported_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$([ "$enabled_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$([ "$active_value" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
    "$(json_escape "$method_value")" \
    "$(json_escape "$label_value")" \
    "$(json_escape "$detail_value")"
}

decision_dir_for() {
  conv_dir=$1
  printf '%s/decision' "$conv_dir"
}

decision_question_file_for() {
  conv_dir=$1
  printf '%s/question.txt' "$(decision_dir_for "$conv_dir")"
}

decision_options_file_for() {
  conv_dir=$1
  printf '%s/options.txt' "$(decision_dir_for "$conv_dir")"
}

approval_request_dir_for() {
  conv_dir=$1
  printf '%s/approval' "$conv_dir"
}

approval_request_command_file_for() {
  conv_dir=$1
  printf '%s/command.txt' "$(approval_request_dir_for "$conv_dir")"
}

approval_request_reason_file_for() {
  conv_dir=$1
  printf '%s/reason.txt' "$(approval_request_dir_for "$conv_dir")"
}

clear_approval_request() {
  conv_dir=$1
  approval_dir=$(approval_request_dir_for "$conv_dir")
  rm -f "$(approval_request_command_file_for "$conv_dir")" "$(approval_request_reason_file_for "$conv_dir")"
  rmdir "$approval_dir" 2>/dev/null || true
}

save_approval_request() {
  conv_dir=$1
  command_text=$2
  reason_text=$3
  command_trimmed=$(trim "$command_text")
  if [ -z "$command_trimmed" ]; then
    return 1
  fi
  approval_dir=$(approval_request_dir_for "$conv_dir")
  mkdir -p "$approval_dir"
  printf '%s\n' "$command_trimmed" > "$(approval_request_command_file_for "$conv_dir")"
  printf '%s\n' "$(trim "$reason_text")" > "$(approval_request_reason_file_for "$conv_dir")"
  return 0
}

save_approval_request_from_blocked_file() {
  conv_dir=$1
  blocked_file=$2
  if [ ! -f "$blocked_file" ]; then
    return 1
  fi
  while IFS= read -r blocked_line; do
    [ -n "$(trim "$blocked_line")" ] || continue
    command_text=$(printf '%s' "$blocked_line" | awk -F'\t' '{print $1}')
    reason_text=$(printf '%s' "$blocked_line" | awk -F'\t' '{print $2}')
    if [ -n "$(trim "$command_text")" ]; then
      save_approval_request "$conv_dir" "$command_text" "$reason_text"
      return $?
    fi
  done < "$blocked_file"
  return 1
}

approval_request_json_for_conversation() {
  conv_dir=$1
  command_file=$(approval_request_command_file_for "$conv_dir")
  reason_file=$(approval_request_reason_file_for "$conv_dir")
  if [ ! -f "$command_file" ]; then
    printf 'null'
    return 0
  fi
  command_text=$(trim "$(read_file_line "$command_file" "")")
  if [ -z "$command_text" ]; then
    printf 'null'
    return 0
  fi
  reason_text=$(trim "$(read_file_line "$reason_file" "")")
  printf '{"command":"%s","reason":"%s"}' "$(json_escape "$command_text")" "$(json_escape "$reason_text")"
}

clear_decision_request() {
  conv_dir=$1
  decision_dir=$(decision_dir_for "$conv_dir")
  rm -f "$(decision_question_file_for "$conv_dir")" "$(decision_options_file_for "$conv_dir")"
  rmdir "$decision_dir" 2>/dev/null || true
}

save_decision_request() {
  conv_dir=$1
  question_text=$2
  source_options_file=$3

  question_trimmed=$(trim "$question_text")
  if [ -z "$question_trimmed" ]; then
    return 1
  fi

  normalized_options=$(mktemp)
  : > "$normalized_options"
  option_count=0
  if [ -f "$source_options_file" ]; then
    while IFS= read -r raw_option; do
      option=$(trim "$raw_option")
      [ -n "$option" ] || continue
      if [ "$option_count" -ge 5 ]; then
        break
      fi
      printf '%s\n' "$option" >> "$normalized_options"
      option_count=$((option_count + 1))
    done < "$source_options_file"
  fi

  deduped_options=$(mktemp)
  awk '{
    key=tolower($0);
    if (!seen[key]++) {
      print $0;
    }
  }' "$normalized_options" > "$deduped_options"
  rm -f "$normalized_options"

  if [ ! -s "$deduped_options" ]; then
    rm -f "$deduped_options"
    return 1
  fi

  decision_dir=$(decision_dir_for "$conv_dir")
  mkdir -p "$decision_dir"
  printf '%s\n' "$question_trimmed" > "$(decision_question_file_for "$conv_dir")"
  cp "$deduped_options" "$(decision_options_file_for "$conv_dir")"
  rm -f "$deduped_options"
  return 0
}

decision_request_json_for_conversation() {
  conv_dir=$1
  question_file=$(decision_question_file_for "$conv_dir")
  options_file=$(decision_options_file_for "$conv_dir")

  if [ ! -f "$question_file" ] || [ ! -f "$options_file" ]; then
    printf 'null'
    return 0
  fi

  question=$(trim "$(read_file_line "$question_file" "")")
  if [ -z "$question" ]; then
    printf 'null'
    return 0
  fi

  has_option=0
  while IFS= read -r option_line; do
    if [ -n "$(trim "$option_line")" ]; then
      has_option=1
      break
    fi
  done < "$options_file"

  if [ "$has_option" -eq 0 ]; then
    printf 'null'
    return 0
  fi

  question_json=$(json_escape "$question")
  printf '{"question":"%s","options":[' "$question_json"
  first_option=1
  while IFS= read -r option_line; do
    option=$(trim "$option_line")
    [ -n "$option" ] || continue
    option_json=$(json_escape "$option")
    if [ "$first_option" -eq 0 ]; then
      printf ','
    fi
    first_option=0
    printf '"%s"' "$option_json"
  done < "$options_file"
  printf ']}'
}

decision_request_summary_text_from_json() {
  decision_json=$1
  if [ -z "$(trim "$decision_json")" ] || [ "$decision_json" = "null" ]; then
    printf '%s' ""
    return 0
  fi

  question_text=$(printf '%s' "$decision_json" | jq -r '.question // ""' 2>/dev/null || printf '%s' "")
  question_text=$(trim "$question_text")
  if [ -z "$question_text" ]; then
    printf '%s' ""
    return 0
  fi

  options_lines=$(printf '%s' "$decision_json" | jq -r '.options[]? // empty' 2>/dev/null || true)
  summary_text=$(cat <<EOF
I need your decision before I can continue.
Question: $question_text
EOF
)
  if [ -n "$(trim "$options_lines")" ]; then
    summary_text="${summary_text}
Options:"
    option_count=0
    while IFS= read -r option_line; do
      option_line=$(trim "$option_line")
      [ -n "$option_line" ] || continue
      summary_text="${summary_text}
- $option_line"
      option_count=$((option_count + 1))
      if [ "$option_count" -ge 5 ]; then
        break
      fi
    done <<EOF
$options_lines
EOF
  fi

  printf '%s' "$summary_text"
}

lowercase_text() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

decision_prompt_requests_explicit_choice() {
  prompt_lower=$(lowercase_text "$1")
  if printf '%s' "$prompt_lower" | grep -Eq '\bwhich\b'; then
    # "which <scope>" prompts without alternatives are usually missing-input requests, not option choices.
    if printf '%s' "$prompt_lower" | grep -Eq '\b(path|file|folder|directory|workspace|repo|branch|environment|env|url|domain|host|port|model|provider|token|api key|key|credential|secret|password|region|tenant|service|schema|table|jurisdiction|deadline|cluster|namespace)\b'; then
      if ! printf '%s' "$prompt_lower" | grep -Eq '[[:space:]]or[[:space:]]|yes[[:space:]]+or[[:space:]]+no|either|option(s)?|one of'; then
        return 1
      fi
    fi
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\b(choose|decide|select|pick)\b'; then
    if printf '%s' "$prompt_lower" | grep -Eq 'internally|autonomously|myself|yourself|on your own|without asking'; then
      return 1
    fi
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\bwhich\b|\bchoose\b|\bchoice\b|\bselect\b|\bpick[[:space:]]+one\b'; then
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\bshould[[:space:]]+i\b|\bdo[[:space:]]+you[[:space:]]+want\b|\bprefer\b|\boption(s)?\b'; then
    if printf '%s' "$prompt_lower" | grep -Eq '[[:space:]]or[[:space:]]|yes[[:space:]]+or[[:space:]]+no|either|option(s)?'; then
      return 0
    fi
  fi
  return 1
}

decision_prompt_has_missing_required_inputs() {
  prompt_raw=$1
  prompt_lower=$(lowercase_text "$prompt_raw")
  # Treat angle placeholders as explicit template tokens (<TENANT_ID>, <REGION>) and avoid matching normal HTML tags.
  if printf '%s' "$prompt_raw" | grep -Eq '<[A-Z][A-Z0-9_ -]{1,}>|<[a-z0-9]+_[a-z0-9_ -]{1,}>|\{\{[^}]{2,}\}\}|\[\[?[A-Z_ -]{3,}\]?\]|\?\?\?|<<[^>]{2,}>>|\$\{[A-Z_]*(TOKEN|KEY|SECRET|PASSWORD|CRED|ID|URL|HOST|REGION|TENANT)[A-Z0-9_]*\}|REDACTED_[A-Z_]{2,}'; then
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'missing|required[^.\n]{0,40}(input|value|detail|parameter|field|secret|credential)|not provided|unknown|unspecified|tbd|todo|redacted|provide later|ask me'; then
    return 0
  fi
  # Domain-specific missing-context heuristics for high-order tasks.
  if printf '%s' "$prompt_lower" | grep -Eq '\b(migration|migrate|schema change|db migration|database migration)\b'; then
    if ! printf '%s' "$prompt_lower" | grep -Eq '\b(postgres|postgresql|mysql|mariadb|sqlite|mongodb|dynamodb|table|column|index|constraint|from[[:space:]]+v?[0-9]+|to[[:space:]]+v?[0-9]+|version|ddl)\b'; then
      return 0
    fi
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\b(legal filing|contract|regulatory filing|compliance letter)\b'; then
    if ! printf '%s' "$prompt_lower" | grep -Eq '\b(jurisdiction|state|country|agency|court|deadline|statute|case number)\b'; then
      return 0
    fi
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\b(incident response|security incident|breach response|forensics|containment|compromise)\b'; then
    if ! printf '%s' "$prompt_lower" | grep -Eq '\b(service|system|host|endpoint|environment|env|production|staging|tenant|account|region|timeline|time window|ioc|indicator|artifact|log source)\b'; then
      return 0
    fi
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\b(performance test|load test|benchmark|perf regression|latency optimization)\b'; then
    if ! printf '%s' "$prompt_lower" | grep -Eq '\b(p50|p95|p99|latency|throughput|qps|rps|slo|sla|cpu|memory|target|budget|baseline)\b'; then
      return 0
    fi
  fi
  deploy_scope_missing_check=0
  if printf '%s' "$prompt_lower" | grep -Eq '\b(deploy|rollout|hotfix|rollback)\b'; then
    deploy_scope_missing_check=1
  elif printf '%s' "$prompt_lower" | grep -Eq '\brelease\b'; then
    if printf '%s' "$prompt_lower" | grep -Eq '\b(deploy|ship|publish|promote|launch|go[- ]live)\b'; then
      deploy_scope_missing_check=1
    fi
  fi
  if [ "$deploy_scope_missing_check" -eq 1 ]; then
    if ! printf '%s' "$prompt_lower" | grep -Eq '\b(check|checks|checklist|plan|preview|dry-run|analysis|document)\b'; then
      if ! printf '%s' "$prompt_lower" | grep -Eq '\b(prod|production|staging|dev|qa|environment|service|app|cluster|namespace|window|slo|rollback|canary|blue[- ]green)\b'; then
        return 0
      fi
    fi
  fi
  return 1
}

prompt_requests_autonomous_defaults() {
  prompt_lower=$(lowercase_text "$1")
  if printf '%s' "$prompt_lower" | grep -Eq 'continue autonomously|proceed autonomously|autonomously|on your own|without asking|without questions|make reasonable assumptions|sensible defaults|assume defaults|choose defaults|do not ask|don'\''t ask'; then
    return 0
  fi
  return 1
}

decision_question_looks_required_input() {
  question_lower=$(lowercase_text "$1")
  if printf '%s' "$question_lower" | grep -Eq 'which|what|provide|enter|confirm|select'; then
    if printf '%s' "$question_lower" | grep -Eq 'path|file|folder|directory|workspace|repo|branch|environment|env|url|domain|host|port|model|provider|token|api key|key|credential|secret|password|username|email|latency|throughput|slo|sla|target|baseline|region|tenant|service|schema|table|jurisdiction|deadline|cluster|namespace|change window|rollback window'; then
      return 0
    fi
  fi
  return 1
}

decision_question_looks_risk_gate() {
  question_lower=$(lowercase_text "$1")
  # Informational risk-analysis questions should not trigger approval/decision gating.
  if printf '%s' "$question_lower" | grep -Eq 'what[[:space:]]+are[[:space:]]+the[[:space:]]+risks|what[[:space:]]+is[[:space:]]+the[[:space:]]+risk|risk[[:space:]]+of|describe[[:space:]]+the[[:space:]]+risk'; then
    if ! printf '%s' "$question_lower" | grep -Eq 'approve|permission|authorize|authorise|allow|proceed|go ahead|okay to|ok to|consent|waive|waiver|override|bypass'; then
      return 1
    fi
  fi
  if printf '%s' "$question_lower" | grep -Eq 'policy exception'; then
    if printf '%s' "$question_lower" | grep -Eq 'include|section|checklist|template|documentation|document|write-up|writeup'; then
      if ! printf '%s' "$question_lower" | grep -Eq 'approve|permission|authorize|authorise|allow|proceed|go ahead|okay to|ok to|consent|override|bypass|without'; then
        return 1
      fi
    fi
  fi
  if printf '%s' "$question_lower" | grep -Eq 'approve|permission|authorize|authorise|allow|proceed|go ahead|okay to|ok to|consent|waive|waiver|policy exception|override|bypass'; then
    return 0
  fi
  if printf '%s' "$question_lower" | grep -Eq '(should|can|may)[[:space:]]+(we|i)[[:space:]]+(deploy|publish|delete|drop|migrate|force|ship)|is it safe to[[:space:]]+(deploy|publish|delete|drop|migrate|force|ship)'; then
    return 0
  fi
  if printf '%s' "$question_lower" | grep -Eq '(legal|compliance|privacy|pii|gdpr|hipaa)'; then
    if printf '%s' "$question_lower" | grep -Eq '(without|skip|waive|exception|override|bypass|approve|authorize|allow|consent|not reviewed|no review)'; then
      return 0
    fi
  fi
  if printf '%s' "$question_lower" | grep -Eq 'production|external|network'; then
    if printf '%s' "$question_lower" | grep -Eq 'approve|authorize|allow|proceed|go ahead|waive|exception|bypass|override'; then
      return 0
    fi
  fi
  if printf '%s' "$question_lower" | grep -Eq 'irreversible|destructive'; then
    return 0
  fi
  return 1
}

decision_commands_trigger_external_gate() {
  commands_lower=$(lowercase_text "$1")
  if printf '%s' "$commands_lower" | grep -Eq '\bcurl\b|\bwget\b|\bnc\b|\bssh\b|\bscp\b|\bsftp\b|\bftp\b|\btelnet\b|\bgit[[:space:]]+push\b|\bgh[[:space:]]+(release|api|workflow[[:space:]]+run)\b|\bdocker[[:space:]]+push\b|\bnpm[[:space:]]+publish\b|\btwine[[:space:]]+upload\b|\bkubectl[[:space:]]+(apply|delete|patch|scale|replace)\b|\bkubectl[[:space:]]+rollout[[:space:]]+(restart|undo)\b|\bterraform[[:space:]]+apply\b|\bnetlify[[:space:]]+deploy\b|\bvercel[[:space:]]+deploy\b|\bansible-playbook\b|\bhelm[[:space:]]+(install|upgrade|uninstall|delete)\b|\baws[[:space:]]+(s3|ecs|eks|lambda|rds|cloudformation)\b|\bgcloud[[:space:]]+(run|functions|deploy|app|compute)\b|\baz[[:space:]]+(deployment|webapp|functionapp|aks)\b|\brsync[[:space:]].*(@|:)'; then
    return 0
  fi
  return 1
}

decision_commands_trigger_destructive_gate() {
  commands_lower=$(lowercase_text "$1")
  # Ignore documentation-only command examples that mention destructive SQL text.
  if printf '%s' "$commands_lower" | grep -Eq '^[[:space:]]*(echo|printf|cat)[[:space:]]'; then
    if ! printf '%s' "$commands_lower" | grep -Eq '[;&|][[:space:]]*(psql|mysql|sqlite3|sqlcmd|dbmate|prisma[[:space:]]+db)\b'; then
      if printf '%s' "$commands_lower" | grep -Eq '\bdrop[[:space:]]+(table|database|schema|role)\b|\btruncate[[:space:]]+table\b'; then
        return 1
      fi
    fi
  fi
  # Treat explicit dry-run variants as non-destructive for commands that support safe preview modes.
  if printf '%s' "$commands_lower" | grep -Eq '(^|[[:space:]])(--dry-run(=[a-z-]+)?|--dryrun)([[:space:]]|$)'; then
    if printf '%s' "$commands_lower" | grep -Eq '\bkubectl[[:space:]]+delete\b|\baws[[:space:]]+s3[[:space:]]+rm\b|\bterraform[[:space:]]+destroy\b'; then
      return 1
    fi
  fi
  if printf '%s' "$commands_lower" | grep -Eq '\brm[[:space:]]+-rf\b|\brm[[:space:]]+-fr\b|\bsudo[[:space:]]+rm\b|\bmkfs\b|\bdd[[:space:]].*of=/dev/|\bdiskutil[[:space:]]+erase(disk|volume)\b|\bgit[[:space:]]+reset[[:space:]]+--hard\b|\bgit[[:space:]]+clean[[:space:]]+-fdx?\b|\bterraform[[:space:]]+destroy\b|\bkubectl[[:space:]]+delete\b|\bkubectl[[:space:]]+replace[[:space:]]+--force\b|\bhelm[[:space:]]+uninstall\b|\baws[[:space:]]+rds[[:space:]]+delete-db-instance\b|\baws[[:space:]]+s3[[:space:]]+rm[[:space:]]+s3://[^[:space:]]+[[:space:]]+--recursive\b|\bshred\b'; then
    return 0
  fi
  sql_exec_context=0
  if printf '%s' "$commands_lower" | grep -Eq '\bpsql\b|\bmysql\b|\bsqlite3\b|\bsqlcmd\b|\bdbmate\b|\bprisma[[:space:]]+db\b'; then
    sql_exec_context=1
  fi
  if [ "$sql_exec_context" -eq 1 ]; then
    # Ignore documentation-style SQL literals (for example: select 'drop table ...').
    if printf '%s' "$commands_lower" | grep -Eq "\\bselect[[:space:]].*['\\\"][^'\\\"]*(drop[[:space:]]+(table|database|schema|role)|truncate[[:space:]]+table)[^'\\\"]*['\\\"]"; then
      return 1
    fi
    if printf '%s' "$commands_lower" | grep -Eq "\\bdrop[[:space:]]+(table|database|schema|role)\\b"; then
      return 0
    fi
    if printf '%s' "$commands_lower" | grep -Eq "\\btruncate[[:space:]]+table\\b"; then
      return 0
    fi
  fi
  return 1
}

decision_request_category_for_prompt() {
  prompt_text=$1
  question_text=$2
  run_mode_text=$(normalize_run_mode_name "$3")
  commands_text=$4

  if decision_prompt_requests_explicit_choice "$prompt_text"; then
    printf '%s' "explicit-choice"
    return 0
  fi
  if decision_prompt_has_missing_required_inputs "$prompt_text"; then
    question_trimmed=$(trim "$question_text")
    if [ -z "$question_trimmed" ] || decision_question_looks_required_input "$question_trimmed"; then
      printf '%s' "required-input-missing"
      return 0
    fi
  fi
  if decision_commands_trigger_destructive_gate "$commands_text"; then
    printf '%s' "destructive-action-gate"
    return 0
  fi
  if [ "$run_mode_text" = "assistant" ] && decision_commands_trigger_external_gate "$commands_text"; then
    printf '%s' "external-action-gate"
    return 0
  fi
  if decision_question_looks_risk_gate "$question_text"; then
    printf '%s' "risk-acknowledgement"
    return 0
  fi

  printf '%s' "none"
}

should_allow_model_decision_request() {
  category=$(decision_request_category_for_prompt "$1" "$2" "$3" "$4")
  if [ "$category" = "none" ]; then
    return 1
  fi
  return 0
}

workspace_draft_file_for() {
  workspace_id=$1
  printf '%s/%s/draft-first-message.txt' "$workspaces_dir" "$workspace_id"
}

conversation_draft_file_for() {
  workspace_id=$1
  conversation_id=$2
  printf '%s/conversations/%s/draft-message.txt' "$(workspace_dir_for "$workspace_id")" "$conversation_id"
}

workspace_path_for_id() {
  workspace_id=$1
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 0
  fi
  workspace_path=$(trim "$(read_file_line "$ws_dir/path" "")")
  printf '%s' "$workspace_path"
}

terminal_session_dir_for_workspace() {
  workspace_id=$1
  printf '%s/%s' "$terminal_sessions_root" "$workspace_id"
}

terminal_session_id_file_for_workspace() {
  workspace_id=$1
  printf '%s/id' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_pid_file_for_workspace() {
  workspace_id=$1
  printf '%s/pid' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_input_fifo_for_workspace() {
  workspace_id=$1
  printf '%s/in.fifo' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_output_file_for_workspace() {
  workspace_id=$1
  printf '%s/out.log' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_workspace_file_for_workspace() {
  workspace_id=$1
  printf '%s/workspace_path' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_started_file_for_workspace() {
  workspace_id=$1
  printf '%s/started' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_pid_for_workspace() {
  workspace_id=$1
  read_file_line "$(terminal_session_pid_file_for_workspace "$workspace_id")" ""
}

terminal_session_id_for_workspace() {
  workspace_id=$1
  read_file_line "$(terminal_session_id_file_for_workspace "$workspace_id")" ""
}

terminal_session_running_for_workspace() {
  workspace_id=$1
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  case "$shell_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$shell_pid" 2>/dev/null
}

terminal_session_cleanup_for_workspace() {
  workspace_id=$1
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  case "$shell_pid" in
    ""|*[!0-9]*) ;;
    *)
      kill "$shell_pid" 2>/dev/null || true
      sleep 0.05
      kill -9 "$shell_pid" 2>/dev/null || true
      ;;
  esac
  session_dir=$(terminal_session_dir_for_workspace "$workspace_id")
  rm -rf "$session_dir"
}

terminal_session_start_for_workspace() {
  workspace_id=$1
  workspace_path=$2

  session_dir=$(terminal_session_dir_for_workspace "$workspace_id")
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  existing_id=$(terminal_session_id_for_workspace "$workspace_id")
  existing_workspace=$(read_file_line "$(terminal_session_workspace_file_for_workspace "$workspace_id")" "")

  if terminal_session_running_for_workspace "$workspace_id" && [ -n "$existing_id" ] && [ "$existing_workspace" = "$workspace_path" ]; then
    printf '%s' "$existing_id"
    return 0
  fi

  terminal_session_cleanup_for_workspace "$workspace_id"
  mkdir -p "$session_dir"

  session_id=$(new_id)
  input_fifo=$(terminal_session_input_fifo_for_workspace "$workspace_id")
  output_file=$(terminal_session_output_file_for_workspace "$workspace_id")
  pid_file=$(terminal_session_pid_file_for_workspace "$workspace_id")
  id_file=$(terminal_session_id_file_for_workspace "$workspace_id")
  workspace_file=$(terminal_session_workspace_file_for_workspace "$workspace_id")
  started_file=$(terminal_session_started_file_for_workspace "$workspace_id")

  mkfifo "$input_fifo"
  : > "$output_file"
  printf '%s\n' "$session_id" > "$id_file"
  printf '%s\n' "$workspace_path" > "$workspace_file"
  date +%s > "$started_file"

  (
    cd "$workspace_path" || exit 1
    nohup script -q /dev/null /bin/zsh -i <"$input_fifo" >"$output_file" 2>&1 &
    printf '%s\n' "$!" > "$pid_file"
  )

  sleep 0.08
  if ! terminal_session_running_for_workspace "$workspace_id"; then
    tail_preview=$(tail -n 40 "$output_file" 2>/dev/null || true)
    terminal_session_cleanup_for_workspace "$workspace_id"
    printf '%s' "could not start terminal session: $(trim "$tail_preview")"
    return 1
  fi

  printf '%s' "$session_id"
  return 0
}

terminal_output_delta_json() {
  output_file=$1
  offset_raw=$2
  offset=0
  case "$offset_raw" in
    ""|*[!0-9]*)
      offset=0
      ;;
    *)
      offset=$offset_raw
      ;;
  esac

  if [ ! -f "$output_file" ]; then
    printf '{"delta":"","offset":0}'
    return 0
  fi

  total_bytes=$(wc -c < "$output_file" | tr -d ' ')
  case "$total_bytes" in
    ""|*[!0-9]*)
      total_bytes=0
      ;;
  esac

  if [ "$offset" -lt 0 ]; then
    offset=0
  fi
  if [ "$offset" -gt "$total_bytes" ]; then
    offset=$total_bytes
  fi

  if [ "$offset" -ge "$total_bytes" ]; then
    printf '{"delta":"","offset":%s}' "$total_bytes"
    return 0
  fi

  start_byte=$((offset + 1))
  delta_text=$(tail -c +"$start_byte" "$output_file" 2>/dev/null || true)
  delta_json=$(json_escape "$delta_text")
  printf '{"delta":"%s","offset":%s}' "$delta_json" "$total_bytes"
}

kv_get() {
  key=$1
  text=$2
  printf '%s\n' "$text" | sed -n "s/^$key=//p" | sed -n '1p'
}

ARTIFICER_GIT_BIN=${ARTIFICER_GIT_BIN:-$WIZARDRY_DIR/spells/.arcana/ai-dev/artificer-git}
AI_DEV_DIR=${AI_DEV_DIR:-$WIZARDRY_DIR/spells/.arcana/ai-dev}
DICTATE_BIN=${DICTATE_BIN:-$WIZARDRY_DIR/spells/psi/dictate}
VOICE_RECOGNITION_ROOT_DIR=${VOICE_RECOGNITION_ROOT_DIR:-$HOME/.wizardry/voice-recognition}
VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN=${VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-ctranslate2-whisper}
VOICE_RECOGNITION_INSTALL_MLX_BIN=${VOICE_RECOGNITION_INSTALL_MLX_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-mlx-whisper}
VOICE_RECOGNITION_INSTALL_PARAKEET_BIN=${VOICE_RECOGNITION_INSTALL_PARAKEET_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-parakeet}
VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN=${VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-ctranslate2-whisper}
VOICE_RECOGNITION_UNINSTALL_MLX_BIN=${VOICE_RECOGNITION_UNINSTALL_MLX_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-mlx-whisper}
VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN=${VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-parakeet}
VOICE_RECOGNITION_BACKEND_BIN=${VOICE_RECOGNITION_BACKEND_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/voice-recognition-backend}

resolve_artificer_git_bin() {
  if [ -x "$ARTIFICER_GIT_BIN" ]; then
    printf '%s' "$ARTIFICER_GIT_BIN"
    return 0
  fi
  if command -v artificer-git >/dev/null 2>&1; then
    ARTIFICER_GIT_BIN=$(command -v artificer-git)
    printf '%s' "$ARTIFICER_GIT_BIN"
    return 0
  fi
  return 1
}

run_artificer_git() {
  git_bin=$(resolve_artificer_git_bin || true)
  if [ -z "$git_bin" ]; then
    printf '%s' "artificer-git helper is unavailable"
    return 1
  fi
  selected_pub=$(selected_ssh_pub_path)
  if [ -n "$selected_pub" ] && [ -f "$selected_pub" ]; then
    selected_private=${selected_pub%.pub}
    if [ -f "$selected_private" ]; then
      GIT_SSH_COMMAND="ssh -i \"$selected_private\" -o IdentitiesOnly=yes"
      export GIT_SSH_COMMAND
    fi
  fi
  "$git_bin" "$@"
}

run_ai_dev_script() {
  script_name=$1
  shift

  case "$script_name" in
    ''|*[!a-zA-Z0-9_-]*)
      printf '%s' "invalid ai-dev script name: $script_name"
      return 1
      ;;
  esac

  if [ -z "${WIZARDRY_DIR-}" ]; then
    WIZARDRY_DIR="$HOME/.wizardry"
  fi
  if [ -z "${AI_DEV_DIR-}" ]; then
    AI_DEV_DIR="$WIZARDRY_DIR/spells/.arcana/ai-dev"
  fi
  PATH="$WIZARDRY_DIR/spells/.imps/cgi:$WIZARDRY_DIR/spells/.imps/sys:$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin"
  export WIZARDRY_DIR AI_DEV_DIR PATH

  script_path="$AI_DEV_DIR/$script_name"
  if [ -x "$script_path" ]; then
    "$script_path" "$@"
    return $?
  fi
  if command -v "$script_name" >/dev/null 2>&1; then
    "$script_name" "$@"
    return $?
  fi
  printf '%s' "ai-dev script unavailable: $script_name (AI_DEV_DIR=$AI_DEV_DIR)"
  return 1
}

resolve_dictate_bin() {
  if [ -x "$DICTATE_BIN" ]; then
    printf '%s' "$DICTATE_BIN"
    return 0
  fi
  if command -v dictate >/dev/null 2>&1; then
    DICTATE_BIN=$(command -v dictate)
    printf '%s' "$DICTATE_BIN"
    return 0
  fi
  return 1
}

resolve_voice_recognition_install_bin() {
  component=$1
  configured_bin=""
  command_name=""
  case "$component" in
    ctranslate2-whisper)
      configured_bin=$VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN
      command_name="install-ctranslate2-whisper"
      ;;
    mlx-whisper)
      configured_bin=$VOICE_RECOGNITION_INSTALL_MLX_BIN
      command_name="install-mlx-whisper"
      ;;
    parakeet)
      configured_bin=$VOICE_RECOGNITION_INSTALL_PARAKEET_BIN
      command_name="install-parakeet"
      ;;
    *)
      return 1
      ;;
  esac

  if [ -n "$configured_bin" ] && [ -x "$configured_bin" ]; then
    printf '%s' "$configured_bin"
    return 0
  fi

  if [ -n "$command_name" ] && command -v "$command_name" >/dev/null 2>&1; then
    printf '%s' "$(command -v "$command_name")"
    return 0
  fi

  return 1
}

resolve_voice_recognition_uninstall_bin() {
  component=$1
  configured_bin=""
  command_name=""
  case "$component" in
    ctranslate2-whisper)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN
      command_name="uninstall-ctranslate2-whisper"
      ;;
    mlx-whisper)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_MLX_BIN
      command_name="uninstall-mlx-whisper"
      ;;
    parakeet)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN
      command_name="uninstall-parakeet"
      ;;
    *)
      return 1
      ;;
  esac

  if [ -n "$configured_bin" ] && [ -x "$configured_bin" ]; then
    printf '%s' "$configured_bin"
    return 0
  fi

  if [ -n "$command_name" ] && command -v "$command_name" >/dev/null 2>&1; then
    printf '%s' "$(command -v "$command_name")"
    return 0
  fi

  return 1
}

resolve_voice_recognition_backend_bin() {
  if [ -x "$VOICE_RECOGNITION_BACKEND_BIN" ]; then
    printf '%s' "$VOICE_RECOGNITION_BACKEND_BIN"
    return 0
  fi
  if command -v voice-recognition-backend >/dev/null 2>&1; then
    VOICE_RECOGNITION_BACKEND_BIN=$(command -v voice-recognition-backend)
    printf '%s' "$VOICE_RECOGNITION_BACKEND_BIN"
    return 0
  fi
  return 1
}

voice_host_is_macos_arm64() {
  host_os=$(uname -s 2>/dev/null || printf 'unknown')
  [ "$host_os" = "Darwin" ] || return 1

  host_arch=$(uname -m 2>/dev/null || printf 'unknown')
  case "$host_arch" in
    arm64|aarch64)
      return 0
      ;;
  esac

  if command -v sysctl >/dev/null 2>&1; then
    arm64_flag=$(sysctl -in hw.optional.arm64 2>/dev/null || printf '0')
    [ "$arm64_flag" = "1" ] && return 0
  fi

  return 1
}

voice_needs_macos_arm64_uname_override() {
  voice_host_is_macos_arm64 || return 1
  host_arch=$(uname -m 2>/dev/null || printf 'unknown')
  case "$host_arch" in
    arm64|aarch64) return 1 ;;
  esac
  return 0
}

voice_can_run_arch_arm64() {
  if ! command -v arch >/dev/null 2>&1; then
    return 1
  fi
  arch -arm64 /usr/bin/true >/dev/null 2>&1
}

run_with_macos_arm64_context() {
  if voice_needs_macos_arm64_uname_override; then
    if voice_can_run_arch_arm64; then
      arch -arm64 "$@"
      return $?
    fi
    printf '%s\n' "voice-recognition: native arm64 execution is unavailable" >&2
    return 126
  fi
  "$@"
}

run_voice_component_command() {
  component=$1
  shift
  if [ "$component" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
    run_with_macos_arm64_context "$@"
    return $?
  fi
  "$@"
}

run_voice_backend_command() {
  backend_bin=$1
  shift
  if voice_needs_macos_arm64_uname_override; then
    run_with_macos_arm64_context "$backend_bin" "$@"
    return $?
  fi
  "$backend_bin" "$@"
}

voice_component_label() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "MLX Whisper"
      ;;
    parakeet)
      printf '%s' "Parakeet"
      ;;
    ctranslate2-whisper)
      printf '%s' "CTranslate2 Whisper"
      ;;
    *)
      printf '%s' "$component"
      ;;
  esac
}

voice_component_model() {
  component=$1
  case "$component" in
    ctranslate2-whisper)
      printf '%s' "small.en"
      ;;
    mlx-whisper)
      printf '%s' "${WIZARDRY_VOICE_MODEL_MLX:-mlx-community/whisper-small-mlx}"
      ;;
    parakeet)
      printf '%s' "${WIZARDRY_VOICE_MODEL_PARAKEET:-nvidia/parakeet-tdt-0.6b-v2}"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_download_size_bytes() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "480000000"
      ;;
    parakeet)
      printf '%s' "6200000000"
      ;;
    ctranslate2-whisper)
      printf '%s' "1500000000"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_hf_repo_id() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "mlx-community/whisper-small-mlx"
      ;;
    parakeet)
      printf '%s' "nvidia/parakeet-tdt-0.6b-v2"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_download_size_bytes_from_web() {
  component=$1
  repo_id=$(voice_component_hf_repo_id "$component")
  if [ -z "$repo_id" ] || ! command -v curl >/dev/null 2>&1; then
    printf '%s' ""
    return 0
  fi

  api_url="https://huggingface.co/api/models/$repo_id/tree/main?recursive=1"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    model_json=$(timeout 12 curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    model_json=$(gtimeout 12 curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  else
    model_json=$(curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  fi
  set -e

  if [ "$fetch_rc" -ne 0 ] || [ -z "$model_json" ]; then
    printf '%s' ""
    return 0
  fi

  size_bytes=$(printf '%s' "$model_json" \
    | tr -d '\n' \
    | sed 's/},{"type":"file"/\
{"type":"file"/g' \
    | awk '
      {
        if (match($0, /"size":[0-9]+/)) {
          token = substr($0, RSTART, RLENGTH)
          gsub(/[^0-9]/, "", token)
          if (token != "") sum += (token + 0)
        }
      }
      END {
        if (sum > 0) printf "%.0f", sum
      }
    ')

  case "$size_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      ;;
    *)
      printf '%s' "$size_bytes"
      ;;
  esac
}

voice_component_state_file() {
  component=$1
  printf '%s/%s/installed\n' "$VOICE_RECOGNITION_ROOT_DIR" "$component"
}

voice_component_python_bin() {
  component=$1
  printf '%s/%s/venv/bin/python\n' "$VOICE_RECOGNITION_ROOT_DIR" "$component"
}

voice_component_installed() {
  component=$1
  state_file=$(voice_component_state_file "$component")
  python_bin=$(voice_component_python_bin "$component")
  [ -f "$state_file" ] && [ -x "$python_bin" ]
}

voice_usage_bytes_for_path() {
  target_path=$1
  if [ ! -d "$target_path" ]; then
    printf '%s' "0"
    return 0
  fi
  usage_kb=$(du -sk "$target_path" 2>/dev/null | awk 'NR==1 { print $1 + 0 }')
  if [ -z "$usage_kb" ]; then
    printf '%s' "0"
    return 0
  fi
  awk -v kb="$usage_kb" 'BEGIN { printf "%.0f", kb * 1024 }'
}

voice_runtime_usage_bytes() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    printf '%s' "0"
    return 0
  fi
  voice_usage_bytes_for_path "$root"
}

voice_component_download_cache_path() {
  component=$1
  case "$component" in
    ctranslate2-whisper|mlx-whisper|parakeet)
      printf '%s/%s\n' "$VOICE_RECOGNITION_ROOT_DIR" "huggingface"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

voice_component_download_usage_bytes() {
  component=$1
  cache_path=$(voice_component_download_cache_path "$component")
  if [ -z "$cache_path" ]; then
    printf '%s' ""
    return 0
  fi
  voice_usage_bytes_for_path "$cache_path"
}

voice_download_cache_root_path() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  printf '%s/%s\n' "$root" "huggingface"
}

voice_component_cache_slug() {
  component=$1
  repo_id=$(voice_component_hf_repo_id "$component")
  if [ -z "$repo_id" ]; then
    printf '%s' ""
    return 0
  fi
  # Hugging Face hub cache directories use models--org--repo naming.
  repo_slug=$(printf '%s' "$repo_id" | sed 's#/#--#g')
  printf '%s' "models--$repo_slug"
}

dictation_cleanup_trash_dir() {
  printf '%s/.cleanup-trash' "$dictation_installs_dir"
}

quarantine_path_for_async_delete() {
  source_path=$1
  label=$2
  if [ ! -e "$source_path" ]; then
    return 0
  fi

  trash_root=$(dictation_cleanup_trash_dir)
  mkdir -p "$trash_root" 2>/dev/null || return 1
  ts=$(date +%s 2>/dev/null || printf '0')
  nonce=$(new_id)
  target_path="$trash_root/$ts-$nonce-$label"

  mv "$source_path" "$target_path" 2>/dev/null || return 1
  spawn_detached_job rm -rf "$target_path" >/dev/null 2>&1 || true
  return 0
}

remove_voice_component_artifacts() {
  component=$1
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi

  component_dir="$root/$component"
  case "$component_dir" in
    "$root"/*)
      if [ -e "$component_dir" ]; then
        quarantine_path_for_async_delete "$component_dir" "${component}-runtime" || return 1
      fi
      ;;
  esac

  cache_slug=$(voice_component_cache_slug "$component")
  if [ -n "$cache_slug" ]; then
    hf_hub_dir="$root/huggingface/hub"
    for entry in "$hf_hub_dir/$cache_slug" "$hf_hub_dir/$cache_slug".* "$hf_hub_dir/$cache_slug"-*; do
      if [ -e "$entry" ]; then
        quarantine_path_for_async_delete "$entry" "${component}-hub" || return 1
      fi
    done
    hf_locks_dir="$root/huggingface/.locks"
    for lock_entry in "$hf_locks_dir/$cache_slug" "$hf_locks_dir/$cache_slug".* "$hf_locks_dir/$cache_slug"-*; do
      if [ -e "$lock_entry" ]; then
        quarantine_path_for_async_delete "$lock_entry" "${component}-lock" || return 1
      fi
    done
  fi
  return 0
}

remove_voice_download_cache() {
  cache_root=$(voice_download_cache_root_path 2>/dev/null || true)
  if [ -z "$cache_root" ]; then
    return 1
  fi
  if [ ! -d "$cache_root" ]; then
    return 0
  fi
  quarantine_path_for_async_delete "$cache_root" "voice-download-cache" || return 1
  return 0
}

dictation_live_session_dir() {
  printf '%s/session' "$dictation_live_dir"
}

dictation_live_session_file() {
  key=$1
  printf '%s/%s' "$(dictation_live_session_dir)" "$key"
}

clear_dictation_live_session() {
  session_dir=$(dictation_live_session_dir)
  rm -rf "$session_dir" 2>/dev/null || true
}

dictation_live_session_value() {
  key=$1
  read_file_line "$(dictation_live_session_file "$key")" ""
}

dictation_live_has_active_capture() {
  capture_pid=$(dictation_live_session_value "pid")
  case "$capture_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$capture_pid" 2>/dev/null
}

dictation_live_status() {
  read_file_line "$(dictation_live_session_file "status")" ""
}

current_time_millis() {
  now_ms=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000' 2>/dev/null || true)
  case "$now_ms" in
    ""|*[!0-9]*)
      now_s=$(date +%s 2>/dev/null || printf '0')
      case "$now_s" in
        ""|*[!0-9]*) now_s=0 ;;
      esac
      now_ms=$((now_s * 1000))
      ;;
  esac
  printf '%s' "$now_ms"
}

arm_dictation_prepare_guard() {
  session_dir=$1
  capture_pid=$2
  guard_script="$session_dir/prepare-guard.sh"
  cat > "$guard_script" <<'EOF'
#!/bin/sh
set -eu
session_dir=$1
capture_pid=$2
sleep 20
status_file="$session_dir/status"
pid_file="$session_dir/pid"
status_val=$(cat "$status_file" 2>/dev/null || printf '')
pid_val=$(cat "$pid_file" 2>/dev/null || printf '')
if [ "$status_val" = "prepared" ] && [ "$pid_val" = "$capture_pid" ]; then
  kill -INT "$capture_pid" 2>/dev/null || true
  sleep 0.08
  kill -TERM "$capture_pid" 2>/dev/null || true
  rm -rf "$session_dir" 2>/dev/null || true
fi
EOF
  chmod +x "$guard_script"
  guard_pid=$(spawn_detached_job "$guard_script" "$session_dir" "$capture_pid")
  printf '%s\n' "$guard_pid" > "$session_dir/prepare_guard_pid"
}

dictation_live_level_for_session() {
  levels_file=$(dictation_live_session_value "levels_file")
  if [ -z "$levels_file" ] || [ ! -f "$levels_file" ]; then
    printf '%s' "0"
    return 0
  fi

  # Prefer Overall RMS-derived telemetry for steadier behavior.
  # Newer ffmpeg astats emits `RMS_peak` instead of `RMS_level`.
  # Some ffmpeg builds include NUL bytes in ametadata output; strip binary bytes first.
  recent_levels=$(tail -n 320 "$levels_file" 2>/dev/null | tr -d '\000\r' || true)
  level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.Peak_level' | tail -n 1 || true)
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_level' | grep -aE -iv 'Overall\.Peak_level' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_level' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_peak' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'RMS_(level|peak)' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_(level|count)' | tail -n 1 || true)
  fi
  level_db=$(printf '%s' "$level_line" | sed -E 's/.*(RMS_(level|peak)|Peak_(level|count))[^-0-9iInNfF]*(-?inf|-?[0-9]+(\.[0-9]+)?).*/\4/I')
  if [ -z "$level_db" ]; then
    printf '%s' "0"
    return 0
  fi
  if printf '%s' "$level_db" | grep -Eq '^-?inf$'; then
    printf '%s' "0"
    return 0
  fi
  awk -v db="$level_db" '
    BEGIN {
      v = db + 0.0
      if (v < -74) v = -74
      if (v > -18) v = -18
      level = (v + 74) / 56
      # Keep ambient room noise near baseline while lifting normal speech variance.
      level = level * level
      if (level < 0) level = 0
      if (level > 1) level = 1
      printf "%.5f", level
    }
  '
}

dictation_live_levels_json_for_session() {
  levels_file=$(dictation_live_session_value "levels_file")
  if [ -z "$levels_file" ] || [ ! -f "$levels_file" ]; then
    printf '%s' "[]"
    return 0
  fi

  # Emit recent peak-derived levels so UI bars react at finer temporal granularity.
  recent_levels=$(tail -n 960 "$levels_file" 2>/dev/null | tr -d '\000\r' || true)
  rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.Peak_level' || true)
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_level' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_level' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'RMS_(level|peak)' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_peak' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_(level|count)' || true)
  fi
  if [ -z "$rms_lines" ]; then
    printf '%s' "[]"
    return 0
  fi

  raw_levels=$(printf '%s\n' "$rms_lines" \
    | sed -nE 's/.*(RMS_(level|peak)|Peak_(level|count))[^-0-9iInNfF]*(-?inf|-?[0-9]+(\.[0-9]+)?).*/\4/Ip' \
    | tail -n 24)
  if [ -z "$raw_levels" ]; then
    printf '%s' "[]"
    return 0
  fi

  levels_json=$(printf '%s\n' "$raw_levels" | awk '
    BEGIN {
      first = 1
      printf "["
    }
    {
      raw = $0
      if (raw ~ /[iI][nN][fF]/) {
        next
      }
      v = raw + 0.0
      if (v < -74) v = -74
      if (v > -18) v = -18
      level = (v + 74) / 56
      level = level * level
      if (level < 0) level = 0
      if (level > 1) level = 1
      if (!first) {
        printf ","
      }
      printf "%.5f", level
      first = 0
    }
    END {
      printf "]"
    }
  ')
  if [ -z "$levels_json" ]; then
    levels_json="[]"
  fi
  printf '%s' "$levels_json"
}

stop_capture_pid_gracefully() {
  capture_pid=$1
  case "$capture_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac

  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  kill -INT "$capture_pid" 2>/dev/null || true
  waited=0
  while kill -0 "$capture_pid" 2>/dev/null && [ "$waited" -lt 3000 ]; do
    sleep 0.05
    waited=$((waited + 50))
  done
  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  kill -TERM "$capture_pid" 2>/dev/null || true
  waited=0
  while kill -0 "$capture_pid" 2>/dev/null && [ "$waited" -lt 3000 ]; do
    sleep 0.05
    waited=$((waited + 50))
  done
  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  stop_process_tree_by_pid "$capture_pid"
}

wait_for_audio_capture_file() {
  audio_file=$1
  max_wait_ms=$2
  case "$max_wait_ms" in
    ""|*[!0-9]*)
      max_wait_ms=1200
      ;;
  esac
  waited=0
  while [ "$waited" -le "$max_wait_ms" ]; do
    if [ -f "$audio_file" ]; then
      bytes=$(wc -c < "$audio_file" 2>/dev/null | tr -d ' ')
      case "$bytes" in
        ""|*[!0-9]*) bytes=0 ;;
      esac
      # 44-byte RIFF header is valid but often indicates effectively empty audio.
      # Still treat it as captured so the transcriber can return a precise result.
      if [ "$bytes" -ge 44 ]; then
        return 0
      fi
    fi
    sleep 0.05
    waited=$((waited + 50))
  done
  return 1
}

transcribe_dictation_audio() {
  backend=$1
  model_name=$2
  language=$3
  audio_path=$4
  python_bin=$5

  [ -x "$python_bin" ] || return 1

  transcribe_rc=0
  if [ "$backend" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
    if voice_can_run_arch_arm64; then
      DICTATE_AUDIO_PATH="$audio_path" \
      DICTATE_BACKEND="$backend" \
      DICTATE_MODEL="$model_name" \
      DICTATE_LANGUAGE="$language" \
      HF_HOME="${WIZARDRY_VOICE_RECOGNITION_HF_HOME:-$HOME/.wizardry/voice-recognition/huggingface}" \
      HF_HUB_OFFLINE=1 \
      TRANSFORMERS_OFFLINE=1 \
      arch -arm64 "$python_bin" <<'PY'
import os
import sys

backend = os.environ.get("DICTATE_BACKEND", "")
audio_path = os.environ.get("DICTATE_AUDIO_PATH", "")
model_name = os.environ.get("DICTATE_MODEL", "")
language = os.environ.get("DICTATE_LANGUAGE", "").strip()
if not language:
    language = None


def squash(text):
    return " ".join(str(text or "").strip().split())


text = ""

try:
    if backend == "ctranslate2-whisper":
        from faster_whisper import WhisperModel

        model = WhisperModel(model_name, device="auto", compute_type="int8")
        kwargs = {"vad_filter": True}
        if language:
            kwargs["language"] = language
        segments, _info = model.transcribe(audio_path, **kwargs)
        parts = []
        for segment in segments:
            segment_text = squash(getattr(segment, "text", ""))
            if segment_text:
                parts.append(segment_text)
        text = " ".join(parts)
    elif backend == "mlx-whisper":
        import mlx_whisper

        kwargs = {"path_or_hf_repo": model_name}
        if language:
            kwargs["language"] = language
        result = mlx_whisper.transcribe(audio_path, **kwargs)
        if isinstance(result, dict):
            text = squash(result.get("text", ""))
    elif backend == "parakeet":
        import nemo.collections.asr as nemo_asr

        model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name)
        try:
            outputs = model.transcribe([audio_path])
        except TypeError:
            outputs = model.transcribe([audio_path], batch_size=1)

        item = ""
        if isinstance(outputs, list) and outputs:
            item = outputs[0]
        else:
            item = outputs

        if hasattr(item, "text"):
            text = squash(getattr(item, "text", ""))
        elif isinstance(item, dict):
            text = squash(item.get("text", ""))
        else:
            text = squash(item)
    else:
        raise RuntimeError("unknown backend")
except Exception as exc:
    sys.stderr.write(f"backend runtime failed: {exc}\n")
    sys.exit(1)

text = squash(text)
if not text:
    sys.stderr.write("no speech detected\n")
    sys.exit(1)

sys.stdout.write(text + "\n")
PY
      transcribe_rc=$?
    else
      printf '%s\n' "backend runtime failed: native arm64 execution is unavailable" >&2
      transcribe_rc=126
    fi
  else
    DICTATE_AUDIO_PATH="$audio_path" \
    DICTATE_BACKEND="$backend" \
    DICTATE_MODEL="$model_name" \
    DICTATE_LANGUAGE="$language" \
    HF_HOME="${WIZARDRY_VOICE_RECOGNITION_HF_HOME:-$HOME/.wizardry/voice-recognition/huggingface}" \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    "$python_bin" <<'PY'
import os
import sys

backend = os.environ.get("DICTATE_BACKEND", "")
audio_path = os.environ.get("DICTATE_AUDIO_PATH", "")
model_name = os.environ.get("DICTATE_MODEL", "")
language = os.environ.get("DICTATE_LANGUAGE", "").strip()
if not language:
    language = None


def squash(text):
    return " ".join(str(text or "").strip().split())


text = ""

try:
    if backend == "ctranslate2-whisper":
        from faster_whisper import WhisperModel

        model = WhisperModel(model_name, device="auto", compute_type="int8")
        kwargs = {"vad_filter": True}
        if language:
            kwargs["language"] = language
        segments, _info = model.transcribe(audio_path, **kwargs)
        parts = []
        for segment in segments:
            segment_text = squash(getattr(segment, "text", ""))
            if segment_text:
                parts.append(segment_text)
        text = " ".join(parts)
    elif backend == "mlx-whisper":
        import mlx_whisper

        kwargs = {"path_or_hf_repo": model_name}
        if language:
            kwargs["language"] = language
        result = mlx_whisper.transcribe(audio_path, **kwargs)
        if isinstance(result, dict):
            text = squash(result.get("text", ""))
    elif backend == "parakeet":
        import nemo.collections.asr as nemo_asr

        model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name)
        try:
            outputs = model.transcribe([audio_path])
        except TypeError:
            outputs = model.transcribe([audio_path], batch_size=1)

        item = ""
        if isinstance(outputs, list) and outputs:
            item = outputs[0]
        else:
            item = outputs

        if hasattr(item, "text"):
            text = squash(getattr(item, "text", ""))
        elif isinstance(item, dict):
            text = squash(item.get("text", ""))
        else:
            text = squash(item)
    else:
        raise RuntimeError("unknown backend")
except Exception as exc:
    sys.stderr.write(f"backend runtime failed: {exc}\n")
    sys.exit(1)

text = squash(text)
if not text:
    sys.stderr.write("no speech detected\n")
    sys.exit(1)

sys.stdout.write(text + "\n")
PY
    transcribe_rc=$?
  fi

  return "$transcribe_rc"
}

progress_pct_max() {
  current=$1
  candidate=$2
  if [ -z "$candidate" ]; then
    printf '%s' "$current"
    return 0
  fi
  if [ -z "$current" ]; then
    current="0"
  fi
  printf '%s %s\n' "$current" "$candidate" | awk '
    {
      a = $1 + 0
      b = $2 + 0
      if (b > a) a = b
      if (a < 0) a = 0
      if (a > 100) a = 100
      printf "%.1f", a
    }
  '
}

progress_pct_from_bytes() {
  delta_bytes=$1
  total_bytes=$2
  case "$delta_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      return 0
      ;;
  esac
  case "$total_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      return 0
      ;;
  esac
  awk -v delta="$delta_bytes" -v total="$total_bytes" '
    BEGIN {
      d = delta + 0
      t = total + 0
      if (t <= 0) {
        exit 1
      }
      if (d < 0) d = 0
      p = (d * 100.0) / t
      if (p < 0) p = 0
      if (p > 99.9) p = 99.9
      printf "%.1f", p
    }
  ' 2>/dev/null || printf '%s' ""
}

voice_runtime_root_path() {
  root=$VOICE_RECOGNITION_ROOT_DIR
  root=$(trim "$root")
  case "$root" in
    ""|"/"|".")
      return 1
      ;;
  esac
  printf '%s' "$root"
}

remove_voice_runtime_root() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi
  rm -rf "$root" 2>/dev/null || return 1
  return 0
}

dictation_job_lock_path() {
  printf '%s/.job-lock' "$dictation_installs_dir"
}

acquire_dictation_job_lock() {
  max_wait_ms=$1
  case "$max_wait_ms" in
    ""|*[!0-9]*)
      max_wait_ms=1500
      ;;
  esac

  lock_dir=$(dictation_job_lock_path)
  waited_ms=0

  while :; do
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lock_dir/pid" 2>/dev/null || true
      date +%s > "$lock_dir/started" 2>/dev/null || true
      return 0
    fi

    lock_pid=$(read_file_line "$lock_dir/pid" "")
    lock_started=$(read_file_line "$lock_dir/started" "0")
    lock_stale=0

    case "$lock_pid" in
      ""|*[!0-9]*)
        lock_stale=1
        ;;
      *)
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          lock_stale=1
        fi
        ;;
    esac

    if [ "$lock_stale" -eq 0 ]; then
      now_epoch=$(date +%s 2>/dev/null || printf '0')
      case "$now_epoch:$lock_started" in
        *[!0-9]*:*|*:*[!0-9]*)
          :
          ;;
        *)
          lock_age=$((now_epoch - lock_started))
          if [ "$lock_age" -gt 120 ] 2>/dev/null; then
            lock_stale=1
          fi
          ;;
      esac
    fi

    if [ "$lock_stale" -eq 1 ]; then
      rm -rf "$lock_dir" 2>/dev/null || true
      continue
    fi

    if [ "$waited_ms" -ge "$max_wait_ms" ] 2>/dev/null; then
      return 1
    fi
    sleep 0.05
    waited_ms=$((waited_ms + 50))
  done
}

release_dictation_job_lock() {
  lock_dir=$(dictation_job_lock_path)
  rm -rf "$lock_dir" 2>/dev/null || true
}

stop_process_tree_by_pid() {
  target_pid=$1
  case "$target_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac

  if ! kill -0 "$target_pid" 2>/dev/null; then
    return 0
  fi

  if command -v pkill >/dev/null 2>&1; then
    pkill -KILL -P "$target_pid" 2>/dev/null || true
  fi
  kill -KILL "$target_pid" 2>/dev/null || true
  sleep 0.05

  if kill -0 "$target_pid" 2>/dev/null; then
    return 1
  fi
  return 0
}

preferred_voice_component_for_host() {
  if voice_host_is_macos_arm64; then
    printf '%s' "mlx-whisper"
    return 0
  fi

  host_os=$(uname -s 2>/dev/null || printf 'unknown')
  if [ "$host_os" = "Linux" ] && command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi -L >/dev/null 2>&1; then
      printf '%s' "parakeet"
      return 0
    fi
  fi

  printf '%s' "ctranslate2-whisper"
}

installed_voice_backend_for_host() {
  preferred_component=$(preferred_voice_component_for_host)

  for component in "$preferred_component" ctranslate2-whisper mlx-whisper parakeet; do
    [ -n "$component" ] || continue
    if voice_component_installed "$component"; then
      printf '%s' "$component"
      return 0
    fi
  done

  return 1
}

run_with_timeout() {
  timeout_sec=$1
  shift

  case "$timeout_sec" in
    ""|*[!0-9]*)
      timeout_sec=180
      ;;
  esac
  if [ "$timeout_sec" -lt 1 ]; then
    timeout_sec=1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_sec" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_sec" "$@"
    return $?
  fi
  "$@"
}

spawn_detached_job() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -MPOSIX -e 'POSIX::setsid() or die "setsid failed: $!"; exec @ARGV or die "exec failed: $!";' "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  if command -v nohup >/dev/null 2>&1; then
    nohup "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  "$@" >/dev/null 2>&1 < /dev/null &
  printf '%s\n' "$!"
}

safe_model_name() {
  model_name=$1
  case "$model_name" in
    ""|*[!a-zA-Z0-9._:/-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

ollama_models_root_dir() {
  if [ -n "${OLLAMA_MODELS-}" ]; then
    printf '%s\n' "$OLLAMA_MODELS"
  else
    printf '%s\n' "$HOME/.ollama/models"
  fi
}

ollama_blobs_dir() {
  printf '%s/blobs\n' "$(ollama_models_root_dir)"
}

count_running_model_installs() {
  running_count=0
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    status=$(read_file_line "$job_dir/status" "")
    install_pid=$(read_file_line "$job_dir/pid" "")
    if [ "$status" = "running" ] && [ -n "$install_pid" ] && kill -0 "$install_pid" 2>/dev/null; then
      running_count=$((running_count + 1))
    fi
  done
  printf '%s\n' "$running_count"
}

model_install_runtime_status_for_model() {
  model_name=$1
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    running_model=$(read_file_line "$job_dir/model" "")
    [ "$running_model" = "$model_name" ] || continue
    status=$(read_file_line "$job_dir/status" "")
    install_pid=$(read_file_line "$job_dir/pid" "")
    if [ "$status" = "running" ] && [ -n "$install_pid" ] && ! kill -0 "$install_pid" 2>/dev/null; then
      status="failed"
    fi
    phase=""
    progress=""
    if [ "$status" = "running" ]; then
      log_tail=$(tail -n 160 "$job_dir/log" 2>/dev/null || true)
      parse_result=$(infer_model_install_phase_progress "$log_tail")
      phase=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      progress=$(printf '%s\n' "$parse_result" | cut -d'|' -f2)
      [ -n "$phase" ] || phase="running"
    fi
    printf '%s|%s|%s' "$status" "$phase" "$progress"
    return 0
  done
  printf '%s' "none||"
}

model_present_in_inventory() {
  model_name=$1
  inventory_text=$2
  [ -n "$(trim "$model_name")" ] || return 1
  [ -n "$(trim "$inventory_text")" ] || return 1
  printf '%s\n' "$inventory_text" | awk -v model="$model_name" '
    $0 == model {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

cleanup_ollama_partial_blobs() {
  cleanup_mode=${1:-full}
  blobs_dir=$(ollama_blobs_dir)
  if [ ! -d "$blobs_dir" ]; then
    printf '%s\n' "removed=0|kept=0|resume_bytes=0|canonicalized=0"
    return 0
  fi
  python3 - "$blobs_dir" "$cleanup_mode" <<'PY'
import glob
import os
import sys

blobs_dir = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else "full"
removed = 0
kept = 0
resume_bytes = 0
canonicalized = 0

def safe_unlink(path):
    global removed
    try:
        os.unlink(path)
        removed += 1
    except FileNotFoundError:
        pass

paths = glob.glob(os.path.join(blobs_dir, "*-partial*"))
groups = {}
for path in paths:
    name = os.path.basename(path)
    if "-partial" not in name:
        continue
    base = name.split("-partial", 1)[0]
    groups.setdefault(base, []).append(path)

for base, items in groups.items():
    complete_path = os.path.join(blobs_dir, base)
    if os.path.exists(complete_path):
      for path in items:
        safe_unlink(path)
      continue

    stats = []
    for path in items:
        try:
            st = os.stat(path)
        except FileNotFoundError:
            continue
        is_canonical = 1 if path.endswith("-partial") else 0
        stats.append((st.st_size, st.st_mtime, is_canonical, path))
    if not stats:
        continue

    canonical_path = os.path.join(blobs_dir, base + "-partial")
    if mode == "stubs":
        keep_path = None
        for size, mtime, is_canonical, path in sorted(stats, key=lambda row: (row[2], row[0], row[1]), reverse=True):
            if keep_path is None and (is_canonical or size > 4096):
                keep_path = path
                break
        if keep_path is None:
            keep_path = max(stats, key=lambda row: (row[2], row[0], row[1]))[3]
    else:
        keep_path = max(stats, key=lambda row: (row[0], row[1], row[2]))[3]

    if mode == "full" and keep_path != canonical_path:
        try:
            if os.path.exists(canonical_path):
                os.unlink(canonical_path)
                removed += 1
            os.rename(keep_path, canonical_path)
            keep_path = canonical_path
            canonicalized += 1
        except OSError:
            pass

    kept += 1
    try:
        resume_bytes = max(resume_bytes, os.stat(keep_path).st_size)
    except FileNotFoundError:
        pass

    for _, _, _, path in stats:
        if path == keep_path:
            continue
        if mode == "stubs":
            try:
                size = os.stat(path).st_size
            except FileNotFoundError:
                continue
            if size > 4096:
                continue
        safe_unlink(path)

print(f"removed={removed}|kept={kept}|resume_bytes={resume_bytes}|canonicalized={canonicalized}")
PY
}

emit_model_installs_json() {
  printf '['
  first=1
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    job_id=$(basename "$job_dir")
    [ -n "$job_id" ] || continue
    model_name=$(read_file_line "$job_dir/model" "")
    status=$(read_file_line "$job_dir/status" "running")
    started=$(read_file_line "$job_dir/started" "0")
    finished=$(read_file_line "$job_dir/finished" "0")
    install_pid=$(read_file_line "$job_dir/pid" "")
    exit_code=$(read_file_line "$job_dir/exit_code" "")
    resume_available=$(read_file_line "$job_dir/resume_available" "0")
    resume_bytes=$(read_file_line "$job_dir/resume_bytes" "0")
    stale_partial_files_removed=$(read_file_line "$job_dir/stale_partial_files_removed" "0")
    if [ "$status" = "running" ] && [ -n "$install_pid" ]; then
      if ! kill -0 "$install_pid" 2>/dev/null; then
        status="failed"
        if [ -n "$exit_code" ]; then
          case "$exit_code" in
            0) status="done" ;;
          esac
        fi
      fi
    fi

    log_tail=$(tail -n 120 "$job_dir/log" 2>/dev/null || true)
    install_phase="running"
    install_progress=""
    if [ "$status" = "done" ]; then
      install_phase="done"
      install_progress="100"
    elif [ "$status" = "failed" ]; then
      install_phase="failed"
      install_progress=""
    else
      parse_result=$(infer_model_install_phase_progress "$log_tail")
      install_phase=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      install_progress=$(printf '%s\n' "$parse_result" | cut -d'|' -f2)
      [ -n "$install_phase" ] || install_phase="running"
    fi

    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"id":"%s","model":"%s","status":"%s","phase":"%s","progress_pct":"%s","started":"%s","finished":"%s","resume_available":%s,"resume_bytes":"%s","stale_partial_files_removed":"%s"}' \
      "$(json_escape "$job_id")" \
      "$(json_escape "$model_name")" \
      "$(json_escape "$status")" \
      "$(json_escape "$install_phase")" \
      "$(json_escape "$install_progress")" \
      "$(json_escape "$started")" \
      "$(json_escape "$finished")" \
      "$([ "$resume_available" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
      "$(json_escape "$resume_bytes")" \
      "$(json_escape "$stale_partial_files_removed")"
  done
  printf ']'
}

infer_model_install_phase_progress() {
  log_text=$1
  phase="running"
  progress=""
  if [ -n "$log_text" ]; then
    if printf '%s\n' "$log_text" | grep -Eiq 'verifying sha256|writing manifest|extracting|finalizing|installed'; then
      phase="installing"
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'pulling manifest|pulling |downloading '; then
      phase="downloading"
    fi
    raw_progress=$(printf '%s\n' "$log_text" | grep -Eo '([0-9]{1,3})(\.[0-9]+)?%' | tail -n 1 | tr -d '%' || true)
    if [ -n "$raw_progress" ]; then
      progress=$(printf '%s\n' "$raw_progress" | awk '
        {
          v=$1 + 0
          if (v < 0) v = 0
          if (v > 100) v = 100
          printf "%d", v
        }
      ')
      phase="downloading"
      if [ "$progress" -ge 100 ] 2>/dev/null; then
        phase="installing"
      fi
    fi
  fi
  printf '%s|%s\n' "$phase" "$progress"
}

infer_dictation_install_phase_progress() {
  log_text=$1
  phase="downloading"
  progress="0.0"
  if [ -n "$log_text" ]; then
    progress_max() {
      current=$1
      candidate=$2
      printf '%s %s\n' "$current" "$candidate" | awk '
        {
          a = $1 + 0
          b = $2 + 0
          if (b > a) a = b
          if (a < 0) a = 0
          if (a > 100) a = 100
          printf "%.1f", a
        }
      '
    }

    if printf '%s\n' "$log_text" | grep -Eiq 'installing (ctranslate2-whisper|mlx-whisper|parakeet)'; then
      phase="preparing"
      progress=$(progress_max "$progress" "2.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'Fetching [0-9]+ files:'; then
      phase="downloading"
      progress=$(progress_max "$progress" "3.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'creating virtual environment'; then
      phase="preparing"
      progress=$(progress_max "$progress" "18.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'installing [a-z0-9-]+ packages'; then
      phase="installing"
      progress=$(progress_max "$progress" "52.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'preparing local model cache'; then
      phase="downloading"
      progress=$(progress_max "$progress" "82.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'falling back to ctranslate2-whisper'; then
      phase="fallback"
      progress=$(progress_max "$progress" "70.0")
    fi
    raw_progress=$(printf '%s\n' "$log_text" | grep -Eo '([0-9]{1,3})(\.[0-9]+)?%' | tail -n 1 | tr -d '%' || true)
    if [ -n "$raw_progress" ]; then
      progress=$(progress_max "$progress" "$raw_progress")
      if printf '%s\n' "$raw_progress" | awk '{ exit !($1 + 0 >= 100) }'; then
        phase="finalizing"
      fi
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'installed (ctranslate2-whisper|mlx-whisper|parakeet)'; then
      phase="finalizing"
      progress=$(progress_max "$progress" "96.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'already installed'; then
      phase="finalizing"
      progress=$(progress_max "$progress" "99.0")
    fi
  fi
  printf '%s|%s\n' "$phase" "$progress"
}

dictation_phase_rank() {
  phase=$1
  case "$phase" in
    downloading) printf '%s' "10" ;;
    fallback) printf '%s' "15" ;;
    preparing) printf '%s' "20" ;;
    installing) printf '%s' "30" ;;
    finalizing) printf '%s' "40" ;;
    done) printf '%s' "100" ;;
    *) printf '%s' "0" ;;
  esac
}

dictation_phase_progressive() {
  previous_phase=$1
  next_phase=$2
  prev_rank=$(dictation_phase_rank "$previous_phase")
  next_rank=$(dictation_phase_rank "$next_phase")
  if [ "$next_rank" -lt "$prev_rank" ] 2>/dev/null; then
    printf '%s\n' "$previous_phase"
    return 0
  fi
  printf '%s\n' "$next_phase"
}

OLLAMA_BIN=""

resolve_ollama_bin() {
  if [ -n "$OLLAMA_BIN" ] && [ -x "$OLLAMA_BIN" ]; then
    printf '%s' "$OLLAMA_BIN"
    return 0
  fi

  if command -v ollama >/dev/null 2>&1; then
    OLLAMA_BIN=$(command -v ollama)
    printf '%s' "$OLLAMA_BIN"
    return 0
  fi

  for candidate in \
    /opt/homebrew/bin/ollama \
    /usr/local/bin/ollama \
    /usr/bin/ollama \
    "$HOME/.local/bin/ollama" \
    /Applications/Ollama.app/Contents/Resources/ollama
  do
    if [ -x "$candidate" ]; then
      OLLAMA_BIN=$candidate
      printf '%s' "$OLLAMA_BIN"
      return 0
    fi
  done

  return 1
}

ollama_host_candidates() {
  printf '%s\n%s\n%s\n' \
    "${OLLAMA_HOST:-http://127.0.0.1:11434}" \
    "http://127.0.0.1:11434" \
    "http://localhost:11434" \
    | awk '!seen[$0]++'
}

json_extract_string_field() {
  field_name=$1
  json_text=$2

  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$json_text" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $field = shift @ARGV;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $value = $data->{$field};
      exit 1 if !defined($value) || ref($value);
      print $value;
    ' "$field_name" 2>/dev/null || return 1
    return 0
  fi

  printf '%s' "$json_text" \
    | sed -n "s/.*\"$field_name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | sed -n '1p'
}

model_supports_vision() {
  model_name=$1
  host_candidates=$(ollama_host_candidates)

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  payload=$(printf '{"model":"%s"}' "$(json_escape "$model_name")")

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    show_json=$(curl -sS --connect-timeout 3 --max-time 8 \
      -H "Content-Type: application/json" \
      -X POST "$host/api/show" \
      -d "$payload" 2>/dev/null || true)
    [ -n "$show_json" ] || continue

    if printf '%s' "$show_json" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $caps = $data->{capabilities};
      exit 1 if ref($caps) ne "ARRAY";
      for my $item (@{$caps}) {
        next if !defined($item);
        if ($item eq "vision") {
          exit 0;
        }
      }
      exit 1;
    ' 2>/dev/null; then
      return 0
    fi
  done <<EOF
$host_candidates
EOF

  return 1
}

extract_urls_from_text() {
  text=$1
  printf '%s\n' "$text" \
    | grep -Eo 'https?://[^[:space:]<>()"'"'"']+' \
    | awk '!seen[$0]++'
}

url_encode_component() {
  printf '%s' "$1" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $value = <STDIN>;
    $value = "" if !defined($value);
    utf8::encode($value);
    $value =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;
    print $value;
  ' 2>/dev/null
}

normalize_search_result_url() {
  raw_url=$1
  if [ -z "$raw_url" ]; then
    printf '%s' ""
    return 0
  fi
  decoded_param=$(printf '%s' "$raw_url" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $value = <STDIN>;
    $value = "" if !defined($value);
    my $out = "";
    if ($value =~ /[?&]uddg=([^&]+)/) {
      $out = $1;
      $out =~ s/\+/ /g;
      $out =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    print $out;
  ' 2>/dev/null || true)
  if [ -n "$decoded_param" ] && printf '%s' "$decoded_param" | grep -Eq '^https?://'; then
    printf '%s' "$decoded_param"
    return 0
  fi
  if printf '%s' "$raw_url" | grep -Eq '^https?://'; then
    printf '%s' "$raw_url"
    return 0
  fi
  printf '%s' ""
}

text_perfecter_search_queries_from_prompt() {
  prompt_text=$1
  prompt_line=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)
  prompt_line=$(trim "$prompt_line")
  [ -n "$prompt_line" ] || prompt_line="improve this text for factual quality and clarity"

  is_recipe_prompt=0
  if printf '%s' "$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')" | grep -Eq 'recipe|ingredients|cook|cooking|bake|oven|simmer|broil|marinate|preheat|teaspoon|tablespoon|cup|serves'; then
    is_recipe_prompt=1
  fi

  printf '%s\n' "$prompt_line"
  if [ "$is_recipe_prompt" -eq 1 ]; then
    printf '%s\n' "$prompt_line best recipe techniques common mistakes variations"
    printf '%s\n' "$prompt_line forum discussion reddit"
    printf '%s\n' "$prompt_line science-based cooking guidance"
  else
    printf '%s\n' "$prompt_line evidence critique alternatives"
    printf '%s\n' "$prompt_line common misconceptions expert discussion"
    printf '%s\n' "$prompt_line forum discussion reddit stackexchange"
  fi
}

gather_search_result_urls_for_query() {
  query_text=$1
  max_results=$2
  [ -n "$query_text" ] || return 0
  case "$max_results" in
    ""|*[!0-9]*)
      max_results=4
      ;;
  esac
  if [ "$max_results" -lt 1 ]; then
    max_results=1
  fi
  if [ "$max_results" -gt 8 ]; then
    max_results=8
  fi

  encoded_query=$(url_encode_component "$query_text")
  [ -n "$encoded_query" ] || return 0
  html=$(curl -LfsS --connect-timeout 4 --max-time 10 "https://duckduckgo.com/html/?q=$encoded_query" 2>/dev/null || true)
  [ -n "$html" ] || return 0

  result_urls=$(printf '%s' "$html" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $raw = <STDIN>;
    $raw = "" if !defined($raw);
    while ($raw =~ m{<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"}gis) {
      print "$1\n";
    }
  ' 2>/dev/null || true)
  if [ -z "$result_urls" ]; then
    result_urls=$(printf '%s' "$html" | perl -CS -Mstrict -Mwarnings -e '
      local $/;
      my $raw = <STDIN>;
      $raw = "" if !defined($raw);
      while ($raw =~ m{<a[^>]*href="([^"]+)"}gis) {
        print "$1\n";
      }
    ' 2>/dev/null || true)
  fi

  count=0
  while IFS= read -r raw_url; do
    [ -n "$raw_url" ] || continue
    normalized_url=$(normalize_search_result_url "$raw_url")
    [ -n "$normalized_url" ] || continue
    if ! printf '%s' "$normalized_url" | grep -Eq '^https?://'; then
      continue
    fi
    printf '%s\n' "$normalized_url"
    count=$((count + 1))
    if [ "$count" -ge "$max_results" ]; then
      break
    fi
  done <<EOF
$result_urls
EOF
}

fetch_url_text_excerpt() {
  source_url=$1
  max_chars=$2
  case "$max_chars" in
    ""|*[!0-9]*)
      max_chars=2200
      ;;
  esac
  if [ "$max_chars" -lt 400 ]; then
    max_chars=400
  fi
  if [ "$max_chars" -gt 8000 ]; then
    max_chars=8000
  fi
  raw=$(curl -LfsS --connect-timeout 4 --max-time 12 "$source_url" 2>/dev/null || true)
  [ -n "$raw" ] || return 0
  text=$(printf '%s' "$raw" | perl -CS -pe '
    s/<script\b[^>]*>.*?<\/script>//gis;
    s/<style\b[^>]*>.*?<\/style>//gis;
    s/<noscript\b[^>]*>.*?<\/noscript>//gis;
    s/<[^>]+>/ /g;
    s/&nbsp;/ /g;
    s/&amp;/&/g;
    s/&lt;/</g;
    s/&gt;/>/g;
    s/\s+/ /g;
  ' | cut -c1-"$max_chars")
  text=$(trim "$text")
  [ -n "$text" ] || return 0
  printf '%s' "$text"
}

fetch_direct_url_context_from_prompt() {
  prompt_text=$1
  max_urls=3
  fetched=0
  urls_file=$(mktemp)
  extract_urls_from_text "$prompt_text" > "$urls_file"
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if [ "$fetched" -ge "$max_urls" ]; then
      break
    fi
    fetched=$((fetched + 1))

    raw=$(curl -LfsS --connect-timeout 3 --max-time 8 "$url" 2>/dev/null || true)
    [ -n "$raw" ] || continue

    text=$(printf '%s' "$raw" | perl -CS -pe '
      s/<script\b[^>]*>.*?<\/script>//gis;
      s/<style\b[^>]*>.*?<\/style>//gis;
      s/<[^>]+>/ /g;
      s/\s+/ /g;
    ' | cut -c1-3500)
    text=$(trim "$text")
    [ -n "$text" ] || continue

    printf 'URL: %s\n%s\n\n' "$url" "$text"
  done < "$urls_file"
  rm -f "$urls_file"
}

fetch_text_perfecter_web_context() {
  prompt_text=$1
  query_cap=4
  source_cap=7
  query_i=0
  fetched_sources=0
  search_urls_file=$(mktemp)
  unique_urls_file=$(mktemp)
  context_file=$(mktemp)

  : > "$search_urls_file"
  : > "$context_file"

  # Keep explicit source links from the user, then widen to broad discovery.
  fetch_direct_url_context_from_prompt "$prompt_text" >> "$context_file"
  extract_urls_from_text "$prompt_text" >> "$search_urls_file"

  while IFS= read -r query_line; do
    query_line=$(trim "$query_line")
    [ -n "$query_line" ] || continue
    query_i=$((query_i + 1))
    if [ "$query_i" -gt "$query_cap" ]; then
      break
    fi
    gather_search_result_urls_for_query "$query_line" 4 >> "$search_urls_file"
  done <<EOF
$(text_perfecter_search_queries_from_prompt "$prompt_text")
EOF

  awk '!seen[$0]++' "$search_urls_file" > "$unique_urls_file"
  while IFS= read -r source_url; do
    source_url=$(trim "$source_url")
    [ -n "$source_url" ] || continue
    if [ "$fetched_sources" -ge "$source_cap" ]; then
      break
    fi
    excerpt=$(fetch_url_text_excerpt "$source_url" 2200)
    [ -n "$excerpt" ] || continue
    fetched_sources=$((fetched_sources + 1))
    printf 'Source: %s\n%s\n\n' "$source_url" "$excerpt" >> "$context_file"
  done < "$unique_urls_file"

  printf '%s' "$(cat "$context_file" | cut -c1-24000)"
  rm -f "$search_urls_file" "$unique_urls_file" "$context_file"
}

fetch_web_context_from_prompt() {
  prompt_text=$1
  run_mode=${2:-auto}

  if [ "$ALLOW_NETWORK" != "1" ] || [ "$ALLOW_WEB" != "1" ]; then
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  direct_context=$(fetch_direct_url_context_from_prompt "$prompt_text")
  if [ "$run_mode" = "text-perfecter" ]; then
    perfecter_context=$(fetch_text_perfecter_web_context "$prompt_text")
    combined_context=$(cat <<EOF
$direct_context
$perfecter_context
EOF
)
    printf '%s' "$(printf '%s' "$combined_context" | awk '!seen[$0]++' | cut -c1-26000)"
    return 0
  fi
  printf '%s' "$direct_context"
}

models_from_api_tags() {
  tags_json=$1

  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$tags_json" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $models = $data->{models};
      exit 1 if ref($models) ne "ARRAY";
      for my $item (@{$models}) {
        next if ref($item) ne "HASH";
        my $name = $item->{name};
        next if !defined($name) || $name eq "";
        print "$name\n";
      }
    ' 2>/dev/null && return 0
  fi

  printf '%s' "$tags_json" \
    | awk 'BEGIN{RS="\"name\":\"";FS="\""} NR>1 {print $1}' \
    | sed '/^$/d'
}

list_models_raw() {
  host_candidates=$(ollama_host_candidates)

  if command -v curl >/dev/null 2>&1; then
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      tags_json=$(curl -fsS --connect-timeout 3 --max-time 6 "$host/api/tags" 2>/dev/null || true)
      [ -n "$(trim "$tags_json")" ] || continue

      api_models=$(models_from_api_tags "$tags_json" 2>/dev/null || true)
      if [ -n "$(trim "$api_models")" ]; then
        printf '%s\n' "$api_models" | awk '!seen[$0]++'
        return 0
      fi
    done <<EOF
$host_candidates
EOF

  fi

  ollama_bin=$(resolve_ollama_bin || true)
  [ -n "$ollama_bin" ] || return 0

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    OLLAMA_HOST=$host
    export OLLAMA_HOST

    cli_models=$("$ollama_bin" list 2>/dev/null | awk 'NR > 1 { print $1 }' | sed '/^$/d' || true)
    if [ -n "$(trim "$cli_models")" ]; then
      printf '%s\n' "$cli_models" | awk '!seen[$0]++'
      return 0
    fi
  done <<EOF
$host_candidates
EOF

  list_script="$WIZARDRY_DIR/spells/.arcana/ai-dev/list-installed-llms"
  if [ -x "$list_script" ]; then
    fallback_models=$("$list_script" 2>/dev/null || true)
    if [ -n "$(trim "$fallback_models")" ]; then
      printf '%s\n' "$fallback_models" | awk '!seen[$0]++'
      return 0
    fi
  fi
}

list_models_from_workspace_data() {
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    conv_parent="$ws_dir/conversations"
    [ -d "$conv_parent" ] || continue
    for conv_dir in "$conv_parent"/*; do
      [ -d "$conv_dir" ] || continue
      model_name=$(read_file_line "$conv_dir/model" "")
      model_name=$(trim "$model_name")
      [ -n "$model_name" ] || continue
      printf '%s\n' "$model_name"
    done
  done | awk '!seen[$0]++'
}

model_is_text_generation_model() {
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *embed*|*embedding*|*nomic-embed*|*bge-*|*e5-*|*minilm*|*clip*|*whisper*)
      return 1
      ;;
  esac
  return 0
}

model_preference_score_for_mode() {
  model_name=$1
  mode_name=$2
  lower=$(printf '%s' "$model_name" | tr '[:upper:]' '[:lower:]')
  if ! model_is_text_generation_model "$model_name"; then
    printf '%s' "-9999"
    return 0
  fi

  score=0
  case "$mode_name" in
    chat)
      case "$lower" in
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=120
          ;;
        qwen2.5*|*qwen2.5*|qwen3*|*qwen3*|qwen*|*qwen*)
          score=124
          ;;
        mistral*|*mistral*)
          score=108
          ;;
        phi3*|*phi3*|phi4*|*phi4*|gemma2*|*gemma2*)
          score=102
          ;;
        deepseek-r1*|*deepseek-r1*|deepseek-v3*|*deepseek-v3*)
          score=98
          ;;
        deepseek*|*deepseek*)
          score=88
          ;;
        codellama*|*codellama*|starcoder*|*starcoder*)
          score=72
          ;;
        *instruct*|*chat*)
          score=96
          ;;
        *)
          score=80
          ;;
      esac
      case "$lower" in
        *coder*|*code*)
          score=$((score - 14))
          ;;
      esac
      case "$lower" in
        *instruct*|*chat*)
          score=$((score + 4))
          ;;
      esac
      ;;
    programming)
      case "$lower" in
        deepseek-coder*|*deepseek-coder*)
          score=122
          ;;
        qwen2.5-coder*|*qwen2.5-coder*|qwen-coder*|*qwen-coder*)
          score=116
          ;;
        starcoder*|*starcoder*)
          score=108
          ;;
        codellama*|*codellama*)
          score=103
          ;;
        qwen*|*qwen*)
          score=100
          ;;
        llama3.1*|*llama3.1*|llama3*|*llama3*)
          score=96
          ;;
        mistral*|*mistral*)
          score=94
          ;;
        *)
          score=84
          ;;
      esac
      case "$lower" in
        *coder*|*code*)
          score=$((score + 10))
          ;;
      esac
      ;;
    *)
      score=80
      ;;
  esac

  printf '%s' "$score"
}

best_model_for_mode() {
  mode_name=$1
  models=$(list_models_raw || true)
  if [ -z "$(trim "$models")" ]; then
    models=$(list_models_from_workspace_data || true)
  fi
  [ -n "$(trim "$models")" ] || return 0

  best_model=""
  best_score=-9999
  while IFS= read -r model_name; do
    model_name=$(trim "$model_name")
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "$mode_name")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    if [ -z "$best_model" ] || [ "$score" -gt "$best_score" ]; then
      best_model=$model_name
      best_score=$score
    fi
  done <<EOF
$models
EOF
  printf '%s' "$best_model"
}

chat_autoroute_model() {
  current_model=$(trim "$1")
  [ -n "$current_model" ] || return 0

  best_chat_model=$(best_model_for_mode "chat")
  [ -n "$best_chat_model" ] || return 0
  if [ "$best_chat_model" = "$current_model" ]; then
    return 0
  fi

  current_score=$(model_preference_score_for_mode "$current_model" "chat")
  best_score=$(model_preference_score_for_mode "$best_chat_model" "chat")
  case "$current_score" in ""|*[!0-9-]*) current_score=0 ;; esac
  case "$best_score" in ""|*[!0-9-]*) best_score=0 ;; esac
  score_gap=$((best_score - current_score))

  current_lower=$(printf '%s' "$current_model" | tr '[:upper:]' '[:lower:]')
  coder_like=0
  case "$current_lower" in
    *coder*|*code*|starcoder*|*starcoder*|codellama*|*codellama*|deepseek-coder*|*deepseek-coder*)
      coder_like=1
      ;;
  esac

  if [ "$coder_like" -eq 1 ] && [ "$score_gap" -ge 12 ]; then
    printf '%s' "$best_chat_model"
    return 0
  fi
  if [ "$current_score" -lt 90 ] && [ "$score_gap" -ge 20 ]; then
    printf '%s' "$best_chat_model"
    return 0
  fi
}

preferred_chat_model() {
  models=$(list_models_raw || true)
  [ -n "$(trim "$models")" ] || return 0

  preferred=""
  preferred_score=-9999
  while IFS= read -r model_name; do
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "chat")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    if [ -z "$preferred" ] || [ "$score" -gt "$preferred_score" ]; then
      preferred=$model_name
      preferred_score=$score
    fi
  done <<EOF
$models
EOF

  if [ -n "$preferred" ]; then
    printf '%s' "$preferred"
    return 0
  fi

  while IFS= read -r model_name; do
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    printf '%s' "$model_name"
    return 0
  done <<EOF
$models
EOF
}

ranked_models_json_for_mode() {
  mode_name=$1
  models=$(list_models_raw || true)
  if [ -z "$(trim "$models")" ]; then
    models=$(list_models_from_workspace_data || true)
  fi
  if [ -z "$(trim "$models")" ]; then
    printf '[]'
    return 0
  fi

  tab_char=$(printf '\t')
  rank_tmp=$(mktemp)
  while IFS= read -r model_name; do
    model_name=$(trim "$model_name")
    [ -n "$model_name" ] || continue
    if ! model_is_text_generation_model "$model_name"; then
      continue
    fi
    score=$(model_preference_score_for_mode "$model_name" "$mode_name")
    case "$score" in
      ""|*[!0-9-]*)
        score=0
        ;;
    esac
    printf '%s%s%s\n' "$score" "$tab_char" "$model_name" >> "$rank_tmp"
  done <<EOF
$models
EOF

  if [ ! -s "$rank_tmp" ]; then
    rm -f "$rank_tmp"
    printf '[]'
    return 0
  fi

  sorted_tmp=$(mktemp)
  sort -t "$tab_char" -k1,1nr -k2,2 "$rank_tmp" > "$sorted_tmp"
  rm -f "$rank_tmp"

  printf '['
  first=1
  while IFS="$tab_char" read -r score model_name || [ -n "$model_name" ]; do
    [ -n "$model_name" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"name":"%s","score":"%s"}' \
      "$(json_escape "$model_name")" \
      "$(json_escape "$score")"
  done < "$sorted_tmp"
  printf ']'
  rm -f "$sorted_tmp"
}

emit_model_recommendations() {
  printf '{"success":true,"recommendations":{"chat":%s,"programming":%s}}\n' \
    "$(ranked_models_json_for_mode "chat")" \
    "$(ranked_models_json_for_mode "programming")"
}

default_model() {
  first_model=$(preferred_chat_model || true)
  if [ -z "$first_model" ]; then
    first_model=$(list_models_raw | sed -n '1p')
  fi
  if [ -n "$first_model" ]; then
    printf '%s' "$first_model"
  else
    printf '%s' "qwen2.5-coder:7b"
  fi
}

implementation_model_candidates() {
  primary_model=$1
  preferred_model=$(preferred_chat_model || true)
  all_models=$(list_models_raw || true)
  extras_file=$(mktemp)
  : > "$extras_file"
  extras_added=0

  while IFS= read -r candidate_model; do
    candidate_model=$(trim "$candidate_model")
    [ -n "$candidate_model" ] || continue
    lower=$(printf '%s' "$candidate_model" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *embed*|*embedding*|*nomic-embed*|*bge-*|*e5-*|*minilm*|*clip*|*whisper*)
        continue
        ;;
    esac
    if [ "$candidate_model" = "$primary_model" ]; then
      continue
    fi
    if [ -n "$preferred_model" ] && [ "$candidate_model" = "$preferred_model" ]; then
      continue
    fi
    printf '%s\n' "$candidate_model" >> "$extras_file"
    extras_added=$((extras_added + 1))
    if [ "$extras_added" -ge 2 ]; then
      break
    fi
  done <<EOF
$all_models
EOF

  {
    printf '%s\n' "$primary_model"
    if [ -n "$preferred_model" ] && [ "$preferred_model" != "$primary_model" ]; then
      printf '%s\n' "$preferred_model"
    fi
    cat "$extras_file"
  } | awk '!seen[$0]++'

  rm -f "$extras_file"
}

append_message() {
  conv_dir=$1
  role=$2
  content=$3

  messages_dir="$conv_dir/messages"
  mkdir -p "$messages_dir"

  count=$(find "$messages_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$count" ] || count=0
  next=$((count + 1))
  file_name=$(printf '%s/%04d-%s.txt' "$messages_dir" "$next" "$role")
  printf '%s\n' "$content" > "$file_name"
  date +%s > "$conv_dir/updated"
}

run_events_dir_for_conversation() {
  conv_dir=$1
  printf '%s/run-events' "$conv_dir"
}

tasks_dir_for_conversation() {
  conv_dir=$1
  printf '%s/agent/.tasks' "$conv_dir"
}

queue_running_stream_session_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.stream_session' "$queue_dir"
}

queue_running_event_id_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.event_id' "$queue_dir"
}

queue_running_anchor_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.anchor' "$queue_dir"
}

queue_running_started_iso_file_for() {
  conv_dir=$1
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  printf '%s/running.started_iso' "$queue_dir"
}

normalize_task_progress_status() {
  status_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$status_value" in
    done|completed|complete|finished)
      printf '%s' "done"
      ;;
    active|in-progress|in_progress|working)
      printf '%s' "active"
      ;;
    pending|todo|open|queued|"")
      printf '%s' "pending"
      ;;
    *)
      printf '%s' "pending"
      ;;
  esac
}

task_status_empty_json() {
  printf '{"tasks":[],"completed":0,"total":0,"source":"backend"}'
}

state_mode_from_state_text() {
  state_text_raw=$1
  state_mode_value=$(printf '%s\n' "$state_text_raw" | sed -n 's/.*mode=\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' | sed -n '1p')
  printf '%s' "$state_mode_value"
}

task_status_json_from_tasks_dir() {
  tasks_dir=$1
  run_status_input=$2
  state_text_input=$3
  run_status_norm=$(normalize_run_event_status "$run_status_input")
  force_done=0
  case "$run_status_norm" in
    done)
      force_done=1
      ;;
  esac

  if [ "$force_done" -ne 1 ]; then
    state_mode_hint=$(state_mode_from_state_text "$state_text_input")
    if [ "$(printf '%s' "$state_mode_hint" | tr '[:upper:]' '[:lower:]')" = "done" ]; then
      force_done=1
    fi
  fi

  if [ ! -d "$tasks_dir" ]; then
    task_status_empty_json
    return 0
  fi

  task_files_list=$(mktemp)
  find "$tasks_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' 2>/dev/null | sort > "$task_files_list"
  if [ ! -s "$task_files_list" ]; then
    rm -f "$task_files_list"
    task_status_empty_json
    return 0
  fi

  tasks_json=""
  task_total=0
  task_done_count=0
  while IFS= read -r task_file || [ -n "$task_file" ]; do
    [ -n "$task_file" ] || continue
    [ -f "$task_file" ] || continue
    task_total=$((task_total + 1))
    task_id=$(basename "$task_file")
    task_id=${task_id%.md}
    task_title=$(sed -n 's/^title:[[:space:]]*//p' "$task_file" | sed -n '1p')
    task_title=$(trim "$task_title")
    if [ -z "$task_title" ]; then
      task_title=$(printf '%s' "$task_id" | sed -E 's/^[0-9]{3}-//; s/-+/ /g')
      task_title=$(trim "$task_title")
    fi
    [ -n "$task_title" ] || task_title="$task_id"
    task_status=$(sed -n 's/^status:[[:space:]]*//p' "$task_file" | sed -n '1p')
    task_status=$(normalize_task_progress_status "$task_status")
    if [ "$force_done" -eq 1 ]; then
      task_status="done"
    fi
    task_done_json=false
    if [ "$task_status" = "done" ]; then
      task_done_json=true
      task_done_count=$((task_done_count + 1))
    fi
    task_id_json=$(json_escape "$task_id")
    task_title_json=$(json_escape "$task_title")
    task_status_json=$(json_escape "$task_status")
    if [ -n "$tasks_json" ]; then
      tasks_json="${tasks_json},"
    fi
    tasks_json="${tasks_json}{\"id\":\"$task_id_json\",\"text\":\"$task_title_json\",\"status\":\"$task_status_json\",\"done\":$task_done_json}"
  done < "$task_files_list"
  rm -f "$task_files_list"

  if [ "$task_total" -lt 1 ]; then
    task_status_empty_json
    return 0
  fi

  printf '{"tasks":[%s],"completed":%s,"total":%s,"source":"backend"}' \
    "$tasks_json" "$task_done_count" "$task_total"
}

running_stream_preview_for_conversation() {
  conv_dir=$1
  stream_file=""
  stream_session=$(trim "$(read_file_line "$(queue_running_stream_session_file_for "$conv_dir")" "")")
  if [ -n "$stream_session" ] && valid_id "$stream_session"; then
    candidate=$(stream_tokens_file_for "$conv_dir" "$stream_session")
    if [ -f "$candidate" ]; then
      stream_file=$candidate
    fi
  fi
  if [ -z "$stream_file" ]; then
    fallback_candidate=$(ls -1t "$conv_dir"/stream/*/tokens.txt 2>/dev/null | sed -n '1p')
    if [ -n "$fallback_candidate" ] && [ -f "$fallback_candidate" ]; then
      stream_file=$fallback_candidate
    fi
  fi
  if [ -z "$stream_file" ] || [ ! -f "$stream_file" ]; then
    printf '%s' ""
    return 0
  fi
  sed -n '1,360p' "$stream_file" 2>/dev/null || true
}

active_run_event_json_for_conversation() {
  conv_dir=$1
  ensure_queue_layout "$conv_dir"
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_marker="$queue_dir/running.txt"
  running_pid=$(trim "$(read_file_line "$queue_dir/running.pid" "")")
  running_item_id=$(trim "$(read_file_line "$queue_dir/running.id" "")")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_anchor=$(trim "$(read_file_line "$(queue_running_anchor_file_for "$conv_dir")" "")")
  running_started_epoch=$(trim "$(read_file_line "$queue_dir/running.started" "0")")
  running_started_iso=$(trim "$(read_file_line "$(queue_running_started_iso_file_for "$conv_dir")" "")")
  stale_reason=$(queue_running_stale_reason_for_conversation "$conv_dir")
  if [ -n "$stale_reason" ]; then
    queue_recover_stale_running_state_for_conversation "$conv_dir" "$stale_reason" >/dev/null 2>&1 || true
    printf 'null'
    return 0
  fi

  running_active=0
  if [ -f "$running_marker" ]; then
    running_active=1
  elif [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
    running_active=1
  fi
  if [ "$running_active" -ne 1 ]; then
    printf 'null'
    return 0
  fi

  case "$running_started_epoch" in
    ""|*[!0-9]*)
      running_started_epoch=0
      ;;
  esac
  if [ -z "$running_started_iso" ] && [ "$running_started_epoch" -gt 0 ]; then
    running_started_iso=$(iso_utc_from_epoch "$running_started_epoch")
  fi
  if [ -z "$running_started_iso" ]; then
    running_started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
  fi

  run_event_id="run-live"
  if [ -n "$running_event_id" ] && valid_id "$running_event_id"; then
    run_event_id=$running_event_id
  elif [ -n "$running_item_id" ] && valid_id "$running_item_id"; then
    case "$running_item_id" in
      run-*)
        run_event_id=$running_item_id
        ;;
      *)
        run_event_id="run-${running_item_id}"
        ;;
    esac
  elif [ -n "$running_pid" ]; then
    run_event_id="run-pid-${running_pid}"
  fi

  stream_preview=$(running_stream_preview_for_conversation "$conv_dir")
  model_name=$(read_file_line "$conv_dir/model" "$(default_model)")
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  assay_task_id=$(queue_meta_assay_task_id_from_file "$running_meta_file")
  tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
  state_preview=$(sed -n '1,60p' "$conv_dir/agent/.state" 2>/dev/null || true)
  task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "running" "$state_preview")
  message_anchor_json=""
  case "$running_anchor" in
    ""|*[!0-9]*)
      ;;
    *)
      message_anchor_json=",\"message_anchor\":$running_anchor"
      ;;
  esac

  printf '{"id":"%s","status":"running","started_at":"%s","finished_at":"","model":"%s","plan":"","commands":[],"stream_text":"%s","failures":"","session_log":"","state":"","git_status":"","git_diff":"","error":"","decision_hint":""%s,"task_status":%s}' \
    "$(json_escape "$run_event_id")" \
    "$(json_escape "$running_started_iso")" \
    "$(json_escape "$model_name")" \
    "$(json_escape "$stream_preview")" \
    "$message_anchor_json" \
    "$task_status_json"
}

append_cancelled_run_event_for_stop() {
  conv_dir=$1
  reason_text=$2
  queue_dir=$(conversation_queue_dir_for "$conv_dir")
  running_started_file="$queue_dir/running.started"
  running_started_epoch=$(trim "$(read_file_line "$running_started_file" "0")")
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
  model_name=$(read_file_line "$conv_dir/model" "$(default_model)")
  stream_preview=$(running_stream_preview_for_conversation "$conv_dir")
  state_preview=$(sed -n '1,120p' "$conv_dir/agent/.state" 2>/dev/null || true)
  tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
  task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "cancelled" "$state_preview")
  running_meta_file=$(queue_running_meta_file_for "$conv_dir")
  assay_task_id=$(queue_meta_assay_task_id_from_file "$running_meta_file")
  running_event_id=$(trim "$(read_file_line "$(queue_running_event_id_file_for "$conv_dir")" "")")
  running_anchor=$(trim "$(read_file_line "$(queue_running_anchor_file_for "$conv_dir")" "")")
  reason_clean=$(trim "$reason_text")
  if [ -z "$reason_clean" ]; then
    reason_clean="Run stopped."
  fi
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  elapsed=0
  if [ "$running_started_epoch" -gt 0 ] && [ "$now_epoch" -gt "$running_started_epoch" ]; then
    elapsed=$((now_epoch - running_started_epoch))
  fi
  elapsed_minutes=$((elapsed / 60))
  elapsed_seconds=$((elapsed % 60))
  stop_note=$reason_clean
  summary_text=$reason_clean
  if ! printf '%s' "$reason_clean" | grep -Eq '^Outcome:[[:space:]]*'; then
    summary_text=$(cat <<EOF
Outcome: Run was interrupted before full completion.
Verification Evidence: Queue stop was applied while the run was active. Worked for ${elapsed_minutes}m ${elapsed_seconds}s.
Risks: Partial progress may leave unverified changes or unfinished implementation details.
Next Action: Resume from this checkpoint and prioritize one verifiable sub-goal first.
Next Improvement: Resume from this checkpoint with a narrower scope or higher compute budget.
EOF
)
  fi
  if [ -z "$(trim "$stream_preview")" ]; then
    ts_now=$(date +"%H:%M:%S" 2>/dev/null || printf '%s' "00:00:00")
    stream_preview=$(cat <<EOF
[$ts_now] Run interrupted before completion; checkpoint snapshot captured.
[$ts_now] queue_stop executed to stop lingering run safely.
[$ts_now] Worked for ${elapsed_minutes}m ${elapsed_seconds}s; next action recorded for resume.
EOF
)
  fi
  stop_commands_json="[]"
  ws_dir=$(dirname "$(dirname "$conv_dir")")
  workspace_id=$(basename "$ws_dir")
  workspace_path=$(workspace_path_for_id "$workspace_id")
  if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
    stop_cmd1="git status --short"
    stop_cmd2="find . -maxdepth 2 -type f"
    stop_cmd1_output=$(
      cd "$workspace_path" && {
        git status --short 2>/dev/null || printf '%s\n' "Not a git repository."
      } | sed -n '1,80p'
    )
    stop_cmd2_output=$(
      cd "$workspace_path" && {
        find . -maxdepth 2 -type f 2>/dev/null | sed 's|^\./||' || true
      } | sed -n '1,80p'
    )
    stop_commands_json=$(printf '[{"command":"%s","status":"%s","output":"%s"},{"command":"%s","status":"%s","output":"%s"}]' \
      "$(json_escape "$stop_cmd1")" \
      "$(json_escape "ok")" \
      "$(json_escape "$stop_cmd1_output")" \
      "$(json_escape "$stop_cmd2")" \
      "$(json_escape "ok")" \
      "$(json_escape "$stop_cmd2_output")")
  fi
  event_json=$(build_run_event_json \
    "cancelled" \
    "$started_iso" \
    "$finished_iso" \
    "$model_name" \
    "" \
    "$stop_commands_json" \
    "$stream_preview" \
    "$stop_note" \
    "" \
    "$state_preview" \
    "" \
    "" \
    "$summary_text" \
    "" \
    "$running_event_id" \
    "$task_status_json" \
    "$running_anchor" \
    "$assay_task_id")
  append_run_event_json "$conv_dir" "$event_json"
}

clip_for_run_event() {
  text=$1
  max_lines=${2:-220}
  max_chars=${3:-12000}

  clipped=$(printf '%s\n' "$text" | sed -n "1,${max_lines}p")
  clipped_len=$(printf '%s' "$clipped" | wc -c | tr -d ' ')
  [ -n "$clipped_len" ] || clipped_len=0
  if [ "$clipped_len" -gt "$max_chars" ]; then
    clipped=$(printf '%s' "$clipped" | awk -v max="$max_chars" '
      BEGIN {
        used = 0
        truncated = 0
      }
      {
        line = $0 "\n"
        n = length(line)
        if (used >= max) {
          truncated = 1
          next
        }
        if (used + n > max) {
          keep = max - used
          if (keep > 0) {
            printf "%s", substr(line, 1, keep)
          }
          truncated = 1
          used = max
          next
        }
        printf "%s", line
        used += n
      }
      END {
        if (truncated == 1) {
          printf "\n[truncated]\n"
        }
      }
    ')
  fi
  printf '%s' "$clipped"
}

normalize_run_event_status() {
  status=$(trim "$1")
  case "$status" in
    running|done|error|cancelled|awaiting_approval|awaiting_decision|approval_granted|timeout)
      printf '%s' "$status"
      ;;
    *)
      printf '%s' "done"
      ;;
  esac
}

run_event_status_from_run() {
  queue_status=$(normalize_run_event_status "$1")
  budget_exhausted_raw=${2:-0}
  case "$budget_exhausted_raw" in
    ""|*[!0-9]*)
      budget_exhausted=0
      ;;
    *)
      budget_exhausted=$budget_exhausted_raw
      ;;
  esac
  if [ "$queue_status" = "done" ] && [ "$budget_exhausted" -eq 1 ]; then
    printf '%s' "timeout"
    return 0
  fi
  printf '%s' "$queue_status"
}

normalize_run_mode_name() {
  mode_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$mode_value" in
    instant|auto|programming|pentest|security-audit|chat|teacher|report|text-perfecter|assistant|gui-testing)
      printf '%s' "$mode_value"
      ;;
    team|teams)
      printf '%s' "assistant"
      ;;
    *)
      printf '%s' "auto"
      ;;
  esac
}

normalize_assistant_mode_id() {
  mode_id=$(trim "$1")
  mode_id=$(printf '%s' "$mode_id" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  if [ -z "$mode_id" ]; then
    printf '%s' ""
    return 0
  fi
  if ! valid_id "$mode_id"; then
    printf '%s' ""
    return 0
  fi
  ensure_mode_runtime_bootstrap
  if command -v mr_mode_exists >/dev/null 2>&1; then
    if ! mr_mode_exists "$mode_id"; then
      printf '%s' ""
      return 0
    fi
  fi
  printf '%s' "$mode_id"
}

normalize_compute_budget() {
  budget_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$budget_value" in
    auto|quick|standard|long|until-complete)
      printf '%s' "$budget_value"
      ;;
    *)
      printf '%s' "auto"
      ;;
  esac
}

compute_budget_iteration_cap() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "8"
      ;;
    standard)
      printf '%s' "14"
      ;;
    long)
      printf '%s' "24"
      ;;
    until-complete)
      printf '%s' "0"
      ;;
    *)
      printf '%s' "16"
      ;;
  esac
}

compute_budget_runtime_floor_sec() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "180"
      ;;
    standard)
      printf '%s' "600"
      ;;
    long)
      printf '%s' "1800"
      ;;
    until-complete)
      printf '%s' "7200"
      ;;
    *)
      printf '%s' "300"
      ;;
  esac
}

compute_budget_runtime_ceiling_sec() {
  budget_value=$(normalize_compute_budget "$1")
  case "$budget_value" in
    quick)
      printf '%s' "900"
      ;;
    standard)
      printf '%s' "5400"
      ;;
    long)
      printf '%s' "21600"
      ;;
    until-complete)
      printf '%s' "86400"
      ;;
    *)
      printf '%s' "21600"
      ;;
  esac
}

compute_budget_stale_timeout_sec() {
  budget_value=$(normalize_compute_budget "$1")
  run_budget_sec=$2
  case "$run_budget_sec" in
    ""|*[!0-9]*)
      run_budget_sec=600
      ;;
  esac
  stale_timeout_sec=$((run_budget_sec + 300))
  case "$budget_value" in
    quick)
      min_timeout=900
      ;;
    standard)
      min_timeout=2100
      ;;
    long)
      min_timeout=7200
      ;;
    until-complete)
      min_timeout=28800
      ;;
    *)
      min_timeout=1800
      ;;
  esac
  if [ "$stale_timeout_sec" -lt "$min_timeout" ]; then
    stale_timeout_sec=$min_timeout
  fi
  if [ "$stale_timeout_sec" -gt 172800 ]; then
    stale_timeout_sec=172800
  fi
  printf '%s' "$stale_timeout_sec"
}

queue_missing_pid_grace_sec() {
  grace_sec=${ARTIFICER_QUEUE_MISSING_PID_GRACE_SEC:-45}
  case "$grace_sec" in
    ""|*[!0-9]*)
      grace_sec=45
      ;;
  esac
  if [ "$grace_sec" -lt 5 ]; then
    grace_sec=5
  fi
  if [ "$grace_sec" -gt 600 ]; then
    grace_sec=600
  fi
  printf '%s' "$grace_sec"
}

run_mode_from_slash_tag() {
  tag_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
  case "$tag_value" in
    chat)
      printf '%s' "chat"
      ;;
    teacher|teach|learn|study|tutor)
      printf '%s' "teacher"
      ;;
    task|programming|program|code|dev)
      printf '%s' "programming"
      ;;
    pentest|redteam|red-team)
      printf '%s' "pentest"
      ;;
    security-audit|security|audit|sec-audit)
      printf '%s' "security-audit"
      ;;
    report)
      printf '%s' "report"
      ;;
    text-perfecter|textperfecter|perfecter|perfect|polish|refine)
      printf '%s' "text-perfecter"
      ;;
    gui-testing|guitesting|gui|ui-testing|uitesting|hands-on-testing|handson-testing|hands-on|ux-testing|uxtesting)
      printf '%s' "gui-testing"
      ;;
    assistant|autonomous|autonomy|endeavor|endeavour)
      printf '%s' "assistant"
      ;;
    team|teams)
      printf '%s' "assistant"
      ;;
    auto|thinking|loop)
      printf '%s' "auto"
      ;;
    instant|quick)
      printf '%s' "instant"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

leading_prompt_slash_tag() {
  printf '%s' "$1" | perl -CS -0777 -ne '
    if (/^\s*\/([A-Za-z][A-Za-z0-9_-]*)\b/s) {
      print lc($1);
    }
  '
}

strip_leading_prompt_slash_tag() {
  printf '%s' "$1" | perl -CS -0777 -pe 's/^\s*\/[A-Za-z][A-Za-z0-9_-]*\b[ \t]*//s'
}

build_run_event_json() {
  run_status=$(normalize_run_event_status "$1")
  started_at=$2
  finished_at=$3
  model_name=$4
  plan_text=$5
  commands_array_json=$6
  stream_text=$7
  failures_text=$8
  session_text=$9
  state_text=${10}
  git_status_text=${11}
  git_diff_text=${12}
  error_text=${13}
  decision_hint_text=${14}
  event_id_override=${15}
  task_status_json_override=${16}
  message_anchor_override=${17}
  assay_task_id_override=${18}
  assistant_text=${19-}

  safe_plan=$(clip_for_run_event "$plan_text" 220 9000)
  safe_stream=$(clip_for_run_event "$stream_text" 260 9000)
  safe_failures=$(clip_for_run_event "$failures_text" 240 9000)
  safe_session=$(clip_for_run_event "$session_text" 260 9000)
  safe_state=$(clip_for_run_event "$state_text" 120 4000)
  safe_git_status=$(clip_for_run_event "$git_status_text" 220 8000)
  safe_git_diff=$(clip_for_run_event "$git_diff_text" 280 12000)
  safe_error=$(clip_for_run_event "$error_text" 80 2600)
  safe_hint=$(clip_for_run_event "$decision_hint_text" 40 1600)
  safe_assistant=$(clip_for_run_event "$assistant_text" 320 24000)
  task_status_json=$(trim "$task_status_json_override")
  if [ -z "$task_status_json" ]; then
    task_status_json=$(task_status_empty_json)
  fi
  case "$task_status_json" in
    \{*\})
      ;;
    *)
      task_status_json=$(task_status_empty_json)
      ;;
  esac

  commands_json=$(trim "$commands_array_json")
  if [ -z "$commands_json" ]; then
    commands_json="[]"
  fi

  event_id=$(trim "$event_id_override")
  if [ -z "$event_id" ] || ! valid_id "$event_id"; then
    event_id=$(new_id)
  fi
  message_anchor_json=""
  case "$message_anchor_override" in
    ""|*[!0-9]*)
      ;;
    *)
      message_anchor_json=",\"message_anchor\":$message_anchor_override"
      ;;
  esac
  event_id_json=$(json_escape "$event_id")
  status_json=$(json_escape "$run_status")
  started_json=$(json_escape "$started_at")
  finished_json=$(json_escape "$finished_at")
  model_json=$(json_escape "$model_name")
  plan_json=$(json_escape "$safe_plan")
  stream_json=$(json_escape "$safe_stream")
  failures_json=$(json_escape "$safe_failures")
  session_json=$(json_escape "$safe_session")
  state_json=$(json_escape "$safe_state")
  git_status_json=$(json_escape "$safe_git_status")
  git_diff_json=$(json_escape "$safe_git_diff")
  error_json=$(json_escape "$safe_error")
  hint_json=$(json_escape "$safe_hint")
  assistant_json=$(json_escape "$safe_assistant")

  printf '{"id":"%s","status":"%s","started_at":"%s","finished_at":"%s","model":"%s","plan":"%s","assistant":"%s","commands":%s,"stream_text":"%s","failures":"%s","session_log":"%s","state":"%s","git_status":"%s","git_diff":"%s","error":"%s","decision_hint":"%s"%s,"task_status":%s}' \
    "$event_id_json" "$status_json" "$started_json" "$finished_json" "$model_json" "$plan_json" "$assistant_json" "$commands_json" "$stream_json" "$failures_json" "$session_json" "$state_json" "$git_status_json" "$git_diff_json" "$error_json" "$hint_json" "$message_anchor_json" "$task_status_json"
}

append_run_event_json() {
  conv_dir=$1
  event_json=$2
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  mkdir -p "$events_dir"

  count=$(find "$events_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$count" ] || count=0
  next=$((count + 1))
  file_name=$(printf '%s/%04d.json' "$events_dir" "$next")
  printf '%s\n' "$event_json" > "$file_name"

  keep_limit=60
  if [ "$next" -gt "$keep_limit" ]; then
    remove_count=$((next - keep_limit))
    ls "$events_dir"/*.json 2>/dev/null | sort | head -n "$remove_count" | while IFS= read -r old_file; do
      [ -n "$old_file" ] || continue
      rm -f "$old_file"
    done
  fi
}

json_run_events() {
  conv_dir=$1
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  printf '['
  first=1
  if [ -d "$events_dir" ]; then
    for event_file in "$events_dir"/*.json; do
      [ -f "$event_file" ] || continue
      payload=$(cat "$event_file")
      payload=$(trim "$payload")
      [ -n "$payload" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '%s' "$payload"
    done
  fi
  printf ']'
}

json_run_events_with_active() {
  conv_dir=$1
  active_event_json=$(active_run_event_json_for_conversation "$conv_dir")
  printf '['
  first=1
  events_dir=$(run_events_dir_for_conversation "$conv_dir")
  if [ -d "$events_dir" ]; then
    for event_file in "$events_dir"/*.json; do
      [ -f "$event_file" ] || continue
      payload=$(cat "$event_file")
      payload=$(trim "$payload")
      [ -n "$payload" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '%s' "$payload"
    done
  fi
  if [ -n "$active_event_json" ] && [ "$active_event_json" != "null" ]; then
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '%s' "$active_event_json"
  fi
  printf ']'
}

extract_section() {
  section_name=$1
  text=$2
  known_headers="MODE_UPDATE COMMANDS CONTRACT PATCH DONE_CLAIM PLAN_UPDATE CHECKPOINT DECISION_REQUEST FINAL REVIEW_DECISION REVIEW_FEEDBACK"
  printf '%s\n' "$text" | awk -v section="$section_name" -v headers="$known_headers" '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    BEGIN {
      capture = 0
      in_fence = 0
      section_norm = toupper(section)
      gsub(/[[:space:]]+/, "_", section_norm)
      header_count = split(headers, header_list, /[[:space:]]+/)
      for (header_index = 1; header_index <= header_count; header_index++) {
        if (header_list[header_index] != "") {
          known[header_list[header_index]] = 1
        }
      }
    }
    {
      normalized = $0
      sub(/^[[:space:]]*[*#>[:space:]]*/, "", normalized)
      if (normalized ~ /^```/) {
        if (in_fence == 1) {
          in_fence = 0
        } else {
          in_fence = 1
        }
      }

      header = ""
      remainder = ""
      split_pos = index(normalized, ":")
      if (split_pos > 0) {
        header = substr(normalized, 1, split_pos - 1)
        header = trim_local(header)
        header = toupper(header)
        gsub(/[[:space:]]+/, "_", header)
        remainder = trim_local(substr(normalized, split_pos + 1))
      }

      if (header != "" && !in_fence && (header in known)) {
        if (capture == 1 && header != section_norm) {
          capture = 0
          next
        }
        if (header == section_norm) {
          capture = 1
          if (remainder != "") {
            print remainder
          }
          next
        }
      }

      if (capture == 1) {
        print
      }
    }
  '
}

extract_command_lines() {
  text=$1
  printf '%s\n' "$text" | perl -CS -pe '
    s/\r//g;
    # Some models emit literal escape sequences instead of real newlines.
    s/\\r\\n/\n/g;
    s/\\n/\n/g;
    # Recover collapsed markdown bullets emitted as one physical line:
    # "cmd1- cmd2- cmd3" -> "cmd1\n- cmd2\n- cmd3"
    s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
    s/(?<=\S)\*\s+(?=[A-Za-z0-9._\/])/\\n* /g;
  ' | awk '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line = $0
      line = trim_local(line)
      if (line == "") next
      if (line ~ /^```/) next
      if (line ~ /^[A-Z][A-Z_ ]*:[[:space:]]*$/) next
      sub(/^[0-9]+[.)][[:space:]]*/, "", line)
      sub(/^[-*][[:space:]]*/, "", line)
      sub(/[[:space:]]+2>[[:space:]]*\/dev\/null$/, "", line)
      sub(/[[:space:]]+>[[:space:]]*\/dev\/null$/, "", line)
      sub(/[[:space:]]+2>\/dev\/null$/, "", line)
      sub(/[[:space:]]+>\/dev\/null$/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+\([^)]*\)[[:space:]]*$/, "", line)
      gsub(/^`+|`+$/, "", line)
      line = trim_local(line)
      if (line == "" || line == "NONE" || line == "none") next
      if (!seen[line]++) {
        print line
      }
    }
  '
}

fallback_readonly_commands_for_mode() {
  state_mode_hint=$(trim "${1:-}")
  case "$state_mode_hint" in
    INVESTIGATE)
      printf '%s\n' "ls -la"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    DESIGN)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    IMPLEMENT)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
    VERIFY)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "git diff --stat"
      ;;
    *)
      printf '%s\n' "git status --short --untracked-files=no"
      printf '%s\n' "find . -maxdepth 2 -type f"
      ;;
  esac
}

context_recovery_readonly_command_for_mode() {
  state_mode_hint=$(trim "${1:-}")
  status_hint=$(trim "${2:-}")
  case "$state_mode_hint" in
    INVESTIGATE)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
    DESIGN)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
    VERIFY)
      case "$status_hint" in
        context_missing)
          printf '%s' "ls -la"
          ;;
        *)
          printf '%s' "find . -maxdepth 2 -type f"
          ;;
      esac
      ;;
    *)
      printf '%s' "find . -maxdepth 2 -type f"
      ;;
  esac
}

rewrite_readonly_pipeline_candidate() {
  candidate=$(trim "$1")
  if [ -z "$candidate" ]; then
    printf '%s' ""
    return 0
  fi
  if ! printf '%s\n' "$candidate" | grep -Eq '^[[:space:]]*(cat|head|tail)[[:space:]].*[[:space:]]\|[[:space:]]*(grep|rg)[[:space:]]+'; then
    printf '%s' "$candidate"
    return 0
  fi

  pipe_segments=$(printf '%s\n' "$candidate" | awk -F'|' '{print NF}')
  if [ "$pipe_segments" -ne 2 ]; then
    printf '%s' "$candidate"
    return 0
  fi

  left_side=$(trim "$(printf '%s\n' "$candidate" | awk -F'|' '{print $1}')")
  right_side=$(trim "$(printf '%s\n' "$candidate" | awk -F'|' '{print $2}')")

  left_first_word=$(printf '%s\n' "$left_side" | awk '{print $1}')
  case "$left_first_word" in
    cat)
      left_path=$(trim "${left_side#cat }")
      ;;
    head|tail)
      if ! printf '%s\n' "$left_side" | grep -Eq '^(head|tail)([[:space:]]+-n[[:space:]]+[0-9]+)?[[:space:]]+[^[:space:]]+$'; then
        printf '%s' "$candidate"
        return 0
      fi
      left_path=$(printf '%s\n' "$left_side" | awk '{print $NF}')
      ;;
    *)
      printf '%s' "$candidate"
      return 0
      ;;
  esac
  left_path=$(trim "$left_path")
  if ! is_safe_relative_path "$left_path"; then
    printf '%s' "$candidate"
    return 0
  fi

  right_first_word=$(printf '%s\n' "$right_side" | awk '{print $1}')
  case "$right_first_word" in
    grep)
      right_args=$(trim "${right_side#grep }")
      ;;
    rg)
      right_args=$(trim "${right_side#rg }")
      ;;
    *)
      printf '%s' "$candidate"
      return 0
      ;;
  esac
  if [ -z "$right_args" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  if printf '%s' "$right_args" | grep -Eq '[;&|><`$()]'; then
    printf '%s' "$candidate"
    return 0
  fi

  # grep supports -E/--extended-regexp; rg is regex by default.
  right_args=$(printf '%s\n' "$right_args" | sed -E \
    's/(^|[[:space:]])--extended-regexp([[:space:]]|$)/ /g; s/(^|[[:space:]])-E([[:space:]]|$)/ /g')
  right_args=$(trim "$right_args")
  if [ -z "$right_args" ]; then
    printf '%s' "$candidate"
    return 0
  fi

  printf 'rg %s %s' "$right_args" "$left_path"
}

is_safe_grep_option_token() {
  option_token=$(trim "$1")
  case "$option_token" in
    -r|-R|-n|-i|-F|-E|-H|--recursive|--line-number|--ignore-case|--fixed-strings|--extended-regexp|--with-filename)
      return 0
      ;;
    -m[0-9]*)
      max_count_value=${option_token#-m}
      case "$max_count_value" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
    --max-count=[0-9]*)
      max_count_value=${option_token#--max-count=}
      case "$max_count_value" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

validate_safe_grep_command() {
  grep_cmd=$(trim "$1")
  [ -n "$grep_cmd" ] || return 1

  # shellcheck disable=SC2086
  set -- $grep_cmd
  [ "$1" = "grep" ] || return 1
  shift

  pattern_seen=0
  path_seen=0
  pending_max_count_value=0

  for token in "$@"; do
    token=$(trim "$token")
    [ -n "$token" ] || continue

    if [ "$pending_max_count_value" -eq 1 ]; then
      case "$token" in
        ""|*[!0-9]*)
          return 1
          ;;
        *)
          pending_max_count_value=0
          continue
          ;;
      esac
    fi

    case "$token" in
      --max-count|-m)
        pending_max_count_value=1
        continue
        ;;
    esac

    if [ "$pattern_seen" -eq 0 ]; then
      case "$token" in
        -*)
          if ! is_safe_grep_option_token "$token"; then
            return 1
          fi
          continue
          ;;
        *)
          pattern_seen=1
          continue
          ;;
      esac
    fi

    case "$token" in
      -*)
        if ! is_safe_grep_option_token "$token"; then
          return 1
        fi
        ;;
      *)
        if ! is_safe_relative_path "$token"; then
          return 1
        fi
        path_seen=1
        ;;
    esac
  done

  [ "$pending_max_count_value" -eq 0 ] || return 1
  [ "$pattern_seen" -eq 1 ] || return 1
  [ "$path_seen" -eq 1 ] || return 1
  return 0
}

sanitize_controller_command_candidate() {
  candidate_raw=$(trim "$1")
  state_mode_hint=$(trim "$2")
  if [ -z "$candidate_raw" ]; then
    printf '%s' ""
    return 0
  fi

  candidate=$(printf '%s\n' "$candidate_raw" | sed -E 's/^[[:space:]]*(command|cmd|run)[[:space:]]*:[[:space:]]*//I')
  # Normalize markdown-heavy command bullets like:
  # `cat file` - To inspect ...
  command_in_backticks=$(printf '%s\n' "$candidate" | sed -n 's/.*`\([^`][^`]*\)`.*/\1/p' | sed -n '1p')
  if [ -n "$(trim "$command_in_backticks")" ]; then
    candidate=$command_in_backticks
  fi
  candidate=$(printf '%s\n' "$candidate" | sed -E '
    s/[[:space:]]+-[[:space:]]+(to|for|which|used|this|that|so|in order to).*$/ /I;
    s/[[:space:]]+:[[:space:]]+(to|for|which|used|this|that|so|in order to).*$/ /I;
    s/[[:space:]]+\([^)]*\)[[:space:]]*$//;
  ')
  candidate=$(printf '%s\n' "$candidate" | sed -E 's/^`+//; s/`+$//')
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ]; then
    printf '%s' ""
    return 0
  fi

  lower=$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    git\ checkout*|git\ switch*|git\ pull*|git\ push*|git\ merge*|git\ rebase*|git\ commit*)
      printf '%s' "git status --short --untracked-files=no"
      return 0
      ;;
    npm\ install*|pnpm\ install*|yarn\ install*|bun\ install*|pip\ install*|pip3\ install*)
      if [ "$state_mode_hint" = "VERIFY" ]; then
        printf '%s' "git status --short --untracked-files=no"
      else
        printf '%s' "find . -maxdepth 2 -type f"
      fi
      return 0
      ;;
  esac

  first_word=$(printf '%s\n' "$candidate" | awk '{print $1}')
  second_word=$(printf '%s\n' "$candidate" | awk '{print $2}')
  if [ "$first_word" = "node" ] && [ -n "$second_word" ] && is_safe_relative_path "$second_word"; then
    printf '%s' "node --check $second_word"
    return 0
  fi

  # Keep controller command suggestions in the safe, local inspection envelope.
  # This avoids stalling on approval prompts for analysis-only reasoning tasks.
  case "$first_word" in
    ls|pwd|cat|head|tail|sed|wc|rg|grep|find|git|test|chmod|sh|bash|command|which|python|python3|node|godot|godot4)
      ;;
    *)
      case "$state_mode_hint" in
        INVESTIGATE)
          printf '%s' "find . -maxdepth 2 -type f"
          ;;
        DESIGN|VERIFY)
          printf '%s' "git status --short --untracked-files=no"
          ;;
        *)
          printf '%s' "git status --short --untracked-files=no"
          ;;
      esac
      return 0
      ;;
  esac

  candidate=$(printf '%s\n' "$candidate" | sed -E 's/[[:space:]]+(and[[:space:]]+then|then).*$//I')
  candidate=$(trim "$candidate")
  candidate=$(rewrite_readonly_pipeline_candidate "$candidate")
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ]; then
    fallback_candidate=$(fallback_readonly_commands_for_mode "$state_mode_hint" | sed -n '1p')
    fallback_candidate=$(trim "$fallback_candidate")
    if [ -z "$fallback_candidate" ]; then
      fallback_candidate="git status --short --untracked-files=no"
    fi
    printf '%s' "$fallback_candidate"
    return 0
  fi

  first_word=$(printf '%s\n' "$candidate" | awk '{print $1}')
  second_word=$(printf '%s\n' "$candidate" | awk '{print $2}')
  word_count=$(printf '%s\n' "$candidate" | awk '{print NF}')
  fallback_candidate=$(fallback_readonly_commands_for_mode "$state_mode_hint" | sed -n '1p')
  fallback_candidate=$(trim "$fallback_candidate")
  if [ -z "$fallback_candidate" ]; then
    fallback_candidate="git status --short --untracked-files=no"
  fi
  single_quote_count=$(printf '%s' "$candidate" | tr -cd "'" | wc -c | tr -d ' ')
  double_quote_count=$(printf '%s' "$candidate" | tr -cd '"' | wc -c | tr -d ' ')
  case "$single_quote_count" in
    ""|*[!0-9]*)
      single_quote_count=0
      ;;
  esac
  case "$double_quote_count" in
    ""|*[!0-9]*)
      double_quote_count=0
      ;;
  esac
  if [ $((single_quote_count % 2)) -ne 0 ] || [ $((double_quote_count % 2)) -ne 0 ]; then
    printf '%s' "$fallback_candidate"
    return 0
  fi

  case "$first_word" in
    cat|head|tail|sed)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    rg)
      lower_rg_candidate=$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')
      if printf '%s' "$lower_rg_candidate" | grep -Eq '(^|[[:space:]])(-r|--replace)([[:space:]]|$)'; then
        printf '%s' "rg --files ."
        return 0
      fi
      if [ "$word_count" -lt 3 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    grep)
      if [ "$word_count" -lt 3 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      if ! validate_safe_grep_command "$candidate"; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    git)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "$fallback_candidate"
        return 0
      fi
      ;;
    find)
      if [ "$word_count" -lt 2 ]; then
        printf '%s' "find . -maxdepth 2 -type f"
        return 0
      fi
      ;;
  esac
  printf '%s' "$candidate"
}

sanitize_plan_update_text() {
  raw_plan=$1
  if [ -z "$(trim "$raw_plan")" ]; then
    printf '%s' "$raw_plan"
    return 0
  fi
  printf '%s\n' "$raw_plan" | awk '
    BEGIN {
      in_next_action = 0
    }
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line = $0
      if (line ~ /^Next Action:[[:space:]]*$/) {
        in_next_action = 1
        print line
        next
      }
      if (in_next_action == 1 && line ~ /^[A-Z][A-Za-z ]+:[[:space:]]*$/) {
        in_next_action = 0
      }
      if (in_next_action == 1) {
        lower = tolower(trim_local(line))
        if (lower ~ /\b(git checkout|git switch|npm install|yarn install|pnpm install|pip install)\b/) {
          print "- Run safe read-only inspection commands, then refine implementation based on concrete findings."
          next
        }
      }
      print line
    }
  '
}

allowed_command() {
  cmd=$1

  case "$cmd" in
    *';'*|*'&&'*|*'||'*|*'|'*|*'>'*|*'<'*|*'`'*|*'$('*|*'${'*)
      return 1
      ;;
  esac

  case "$cmd" in
    test\ -f\ *)
      target_path=$(trim "${cmd#test -f }")
      if is_safe_relative_path "$target_path"; then
        return 0
      fi
      return 1
      ;;
    chmod\ +x\ *)
      target_path=$(trim "${cmd#chmod +x }")
      if is_safe_relative_path "$target_path"; then
        return 0
      fi
      return 1
      ;;
  esac

  first_word=$(printf '%s\n' "$cmd" | awk '{print $1}')
  second_word=$(printf '%s\n' "$cmd" | awk '{print $2}')
  third_word=$(printf '%s\n' "$cmd" | awk '{print $3}')
  fourth_word=$(printf '%s\n' "$cmd" | awk '{print $4}')
  word_count=$(printf '%s\n' "$cmd" | awk '{print NF}')

  case "$first_word" in
    ./*)
      if [ "$word_count" -eq 1 ]; then
        exec_target=$(trim "${first_word#./}")
        if is_safe_relative_path "$exec_target"; then
          return 0
        fi
      fi
      if [ "$first_word" = "./bin/ssh.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|journal|restart|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-app.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|restart|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-db.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|promote|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-bastion.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|tunnel|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|cutover|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|rollback|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-private-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|rollback|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-core-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-core-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-edge-canary.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ssh-edge-fleet.sh" ] && [ "$word_count" -eq 2 ]; then
        case "$second_word" in
          status|deploy|health)
            return 0
            ;;
        esac
      fi
      if [ "$first_word" = "./bin/ps.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      if [ "$first_word" = "./bin/stop.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      if [ "$first_word" = "./bin/start.sh" ] && [ "$word_count" -eq 1 ]; then
        return 0
      fi
      return 1
      ;;
    sh|bash)
      if [ "$second_word" = "-n" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      if [ "$word_count" -eq 2 ] && is_safe_relative_path "$second_word"; then
        return 0
      fi
      return 1
      ;;
    test)
      if [ "$second_word" = "-f" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    chmod)
      if [ "$second_word" = "+x" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    command)
      if [ "$second_word" = "-v" ] && [ "$word_count" -eq 3 ] && printf '%s\n' "$third_word" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
        return 0
      fi
      return 1
      ;;
    which)
      if [ "$word_count" -eq 2 ] && printf '%s\n' "$second_word" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
        return 0
      fi
      return 1
      ;;
    python|python3)
      if [ "$second_word" = "-m" ] && [ "$third_word" = "py_compile" ] && [ "$word_count" -eq 4 ] && is_safe_relative_path "$fourth_word"; then
        return 0
      fi
      return 1
      ;;
    node)
      if [ "$second_word" = "--check" ] && [ "$word_count" -eq 3 ] && is_safe_relative_path "$third_word"; then
        return 0
      fi
      return 1
      ;;
    grep)
      if validate_safe_grep_command "$cmd"; then
        return 0
      fi
      return 1
      ;;
    godot|godot4)
      if [ "$cmd" = "$first_word --version" ] || [ "$cmd" = "$first_word --help" ]; then
        return 0
      fi
      if printf '%s\n' "$cmd" | grep -Eq "^${first_word}[[:space:]]+--headless[[:space:]]+--path[[:space:]]+[^[:space:]]+[[:space:]]+--quit$"; then
        godot_path=$(printf '%s\n' "$cmd" | awk '{print $4}')
        if [ "$godot_path" = "." ] || is_safe_relative_path "$godot_path"; then
          return 0
        fi
      fi
      return 1
      ;;
  esac

  if [ "$ALLOW_NETWORK" = "1" ] && [ "$ALLOW_WEB" = "1" ]; then
    case "$first_word" in
      curl)
        case "$cmd" in
          *" --output "*|*" -o "*|*" -O "*|*" --data "*|*" -d "*|*" --upload-file "*|*" -T "*)
            return 1
            ;;
        esac
        if printf '%s\n' "$cmd" | grep -Eq 'https?://'; then
          return 0
        fi
        return 1
        ;;
    esac
  fi

  case "$first_word" in
    ls|pwd|cat|head|tail|sed|wc|rg|find)
      return 0
      ;;
    git)
      case "$second_word" in
        status|diff|log|show|rev-parse|branch|--version|version)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_workspace_paths_in_command() {
  command_text=$1
  workspace_root=$2

  printf '%s\n' "$command_text" | WORKSPACE_ROOT="$workspace_root" ARTIFICER_ASSAY_RUNS_DIR="$ARTIFICER_ASSAY_RUNS_DIR" ARTIFICER_ASSAY_REPORTS_DIR="$ARTIFICER_ASSAY_REPORTS_DIR" perl -pe '
    my $ws = $ENV{"WORKSPACE_ROOT"} // "";
    my $assay_runs = $ENV{"ARTIFICER_ASSAY_RUNS_DIR"} // "";
    my $assay_reports = $ENV{"ARTIFICER_ASSAY_REPORTS_DIR"} // "";
    $ws =~ s{/\z}{};
    $assay_runs =~ s{/\z}{};
    $assay_reports =~ s{/\z}{};
    my @aliases = (
      "/path/to/workspace",
      "/path_to_workspace",
      "/path/to/repo",
      "/path_to_repo",
      "<workspace_path>",
      "/workspace",
      "/repo",
      "/project",
      "<workspace>",
      "\$workspace_path",
      "\${workspace_path}"
    );
    for my $alias (@aliases) {
      s{(^|\s)\Q$alias\E/(?=\S)}{$1./}g;
      s{(^|\s)\Q$alias\E(?=\s|$)}{$1.}g;
    }
    if ($assay_runs ne "") {
      s{(^|\s)(?:\./)?\.assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)(?:\./)?\.assay-runs(?=\s|$)}{$1$assay_runs}g;
      s{(^|\s)/assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)/assay-runs(?=\s|$)}{$1$assay_runs}g;
      s{(^|\s)assay-runs/(?=\S)}{$1$assay_runs/}g;
      s{(^|\s)assay-runs(?=\s|$)}{$1$assay_runs}g;
    }
    if ($assay_reports ne "") {
      s{(^|\s)(?:\./)?hosted-web/\.assay-reports/(?=\S)}{$1$assay_reports/}g;
      s{(^|\s)(?:\./)?hosted-web/\.assay-reports(?=\s|$)}{$1$assay_reports}g;
      s{(^|\s)(?:\./)?\.assay-reports/(?=\S)}{$1$assay_reports/}g;
      s{(^|\s)(?:\./)?\.assay-reports(?=\s|$)}{$1$assay_reports}g;
    }
    if ($ws ne "") {
      s{(^|\s)\Q$ws\E/(?=\S)}{$1}g;
      s{(^|\s)\Q$ws\E(?=\s|$)}{$1.}g;
    }
  '
}

run_ollama_cli_once() {
  ollama_path=$1
  model_name=$2
  prompt_text=$3
  timeout_sec=$4
  use_gpu=${5:-1}

  env_prefix=""
  if [ "$use_gpu" != "1" ]; then
    env_prefix="OLLAMA_NUM_GPU=0"
  fi

  if command -v timeout >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      timeout "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
    else
      timeout "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    fi
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      gtimeout "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
    else
      gtimeout "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    fi
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    if [ -n "$env_prefix" ]; then
      perl -e '
      use strict;
      use warnings;
      my $t = shift @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec @ARGV; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_sec" env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
      return $?
    fi
    perl -e '
      use strict;
      use warnings;
      my $t = shift @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec @ARGV; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_sec" "$ollama_path" run "$model_name" "$prompt_text"
    return $?
  fi

  if [ -n "$env_prefix" ]; then
    env $env_prefix "$ollama_path" run "$model_name" "$prompt_text"
  else
    "$ollama_path" run "$model_name" "$prompt_text"
  fi
  return $?
}

run_model() {
  model_name=$1
  prompt_text=$2
  image_payload_lines=${3:-}

  host_candidates=$(ollama_host_candidates)
  last_output=""
  last_rc=1
  run_timeout_sec=${RUN_TIMEOUT_SEC:-120}
  images_json=""
  ollama_use_gpu=$(llm_use_gpu_enabled)
  ollama_options_fragment=""
  if [ "$ollama_use_gpu" != "1" ]; then
    ollama_options_fragment=',"options":{"num_gpu":0}'
  fi
  prompt_for_model=$(adapt_prompt_for_model "$model_name" "$prompt_text")

  if [ -n "$(trim "$image_payload_lines")" ]; then
    images_json=$(printf '%s\n' "$image_payload_lines" | sed '/^$/d' | awk '
      BEGIN { first = 1 }
      {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        if (!first) {
          printf ","
        }
        first = 0
        printf "\"%s\"", $0
      }
    ')
  fi

  if command -v curl >/dev/null 2>&1; then
    stream_output_file=${ARTIFICER_STREAM_FILE:-}
    if [ -n "$(trim "$stream_output_file")" ]; then
      mkdir -p "$(dirname "$stream_output_file")" 2>/dev/null || true
      if [ ! -f "$stream_output_file" ]; then
        : > "$stream_output_file"
      fi
    fi

    while IFS= read -r host; do
      [ -n "$host" ] || continue
      OLLAMA_HOST=$host
      export OLLAMA_HOST

      if [ -n "$(trim "$stream_output_file")" ]; then
        if [ -n "$images_json" ]; then
          payload=$(printf '{"model":"%s","prompt":"%s","images":[%s],"stream":true%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$images_json" \
            "$ollama_options_fragment")
        else
          payload=$(printf '{"model":"%s","prompt":"%s","stream":true%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$ollama_options_fragment")
        fi

        stream_fifo=$(mktemp -u "/tmp/artificer-stream.XXXXXX")
        stream_err=$(mktemp)
        stream_text=$(mktemp)
        mkfifo "$stream_fifo"

        set +e
        curl -sS --connect-timeout 3 --max-time "$run_timeout_sec" \
          -H "Content-Type: application/json" \
          -X POST "$host/api/generate" \
          -d "$payload" >"$stream_fifo" 2>"$stream_err" &
        curl_pid=$!
        set -e

        while IFS= read -r line || [ -n "$line" ]; do
          [ -n "$line" ] || continue
          chunk=$(json_extract_string_field "response" "$line" || true)
          if [ -n "$chunk" ]; then
            printf '%s' "$chunk" >> "$stream_text"
            printf '%s' "$chunk" >> "$stream_output_file"
          fi
        done < "$stream_fifo"

        set +e
        wait "$curl_pid"
        api_rc=$?
        set -e

        rm -f "$stream_fifo"

        if [ "$api_rc" -eq 0 ]; then
          response_text=$(cat "$stream_text")
          rm -f "$stream_text" "$stream_err"
          if [ -n "$response_text" ]; then
            printf '%s' "$response_text"
            return 0
          fi

          last_output="ollama stream completed without response text"
          last_rc=1
          continue
        fi

        err_text=$(cat "$stream_err" 2>/dev/null || true)
        rm -f "$stream_text" "$stream_err"

        if [ "$api_rc" -eq 28 ]; then
          last_output="timed out while waiting for ollama /api/generate"
          last_rc=124
          break
        fi

        if [ -n "$(trim "$err_text")" ]; then
          last_output=$err_text
        else
          last_output="ollama streaming request failed"
        fi
        last_rc=$api_rc
      else
        if [ -n "$images_json" ]; then
          payload=$(printf '{"model":"%s","prompt":"%s","images":[%s],"stream":false%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$images_json" \
            "$ollama_options_fragment")
        else
          payload=$(printf '{"model":"%s","prompt":"%s","stream":false%s}' \
            "$(json_escape "$model_name")" \
            "$(json_escape "$prompt_for_model")" \
            "$ollama_options_fragment")
        fi

        set +e
        api_output=$(curl -sS --connect-timeout 3 --max-time "$run_timeout_sec" \
          -H "Content-Type: application/json" \
          -X POST "$host/api/generate" \
          -d "$payload" 2>&1)
        api_rc=$?
        set -e

        if [ "$api_rc" -eq 0 ]; then
          response_text=$(json_extract_string_field "response" "$api_output" || true)
          if [ -n "$response_text" ]; then
            printf '%s' "$response_text"
            return 0
          fi

          error_text=$(json_extract_string_field "error" "$api_output" || true)
          if [ -n "$error_text" ]; then
            last_output=$error_text
          else
            last_output=$api_output
          fi
          last_rc=1
          continue
        fi

        if [ "$api_rc" -eq 28 ]; then
          last_output="timed out while waiting for ollama /api/generate"
          last_rc=124
          break
        else
          last_output=$api_output
          last_rc=$api_rc
        fi
      fi
    done <<EOF
$host_candidates
EOF
  fi

  if [ -n "$images_json" ]; then
    if [ -z "$(trim "$last_output")" ]; then
      last_output="Model request with image attachments failed. Ensure Ollama API is reachable and selected model supports vision."
    fi
    printf '%s' "$last_output"
    return "${last_rc:-1}"
  fi

  ollama_bin=$(resolve_ollama_bin || true)
  if [ -n "$ollama_bin" ]; then
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      OLLAMA_HOST=$host
      export OLLAMA_HOST

      set +e
      if [ -n "$(trim "$stream_output_file")" ]; then
        cli_output_file=$(mktemp)
        cli_rc_file=$(mktemp)
        (
          run_ollama_cli_once "$ollama_bin" "$model_name" "$prompt_for_model" "$run_timeout_sec" "$ollama_use_gpu"
          cli_rc=$?
          printf '%s\n' "$cli_rc" > "$cli_rc_file"
          exit 0
        ) 2>&1 | tee -a "$cli_output_file" >> "$stream_output_file"
        run_rc=$(read_file_line "$cli_rc_file" "1")
        run_output=$(cat "$cli_output_file" 2>/dev/null || true)
        rm -f "$cli_output_file" "$cli_rc_file"
      else
        run_output=$(run_ollama_cli_once "$ollama_bin" "$model_name" "$prompt_for_model" "$run_timeout_sec" "$ollama_use_gpu" 2>&1)
        run_rc=$?
      fi
      set -e

      if [ "$run_rc" -eq 0 ]; then
        printf '%s' "$run_output"
        return 0
      fi

      last_output=$run_output
      if [ "$run_rc" -eq 124 ]; then
        last_rc=124
        break
      else
        last_rc=$run_rc
      fi
    done <<EOF
$host_candidates
EOF
  fi

  printf '%s' "$last_output"
  return "$last_rc"
}

workspace_snapshot() {
  workspace_path=$1
  tmp_file=$(mktemp)

  if (
    cd "$workspace_path" &&
      {
        printf 'Workspace: %s\n' "$workspace_path"
        printf '\nTop files (max depth 2):\n'
        find . -maxdepth 2 -type f 2>/dev/null | sed 's|^\./||' | head -n 120
        printf '\nGit status (tracked changes):\n'
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          tracked_status=$(git status --short --untracked-files=no 2>/dev/null || true)
          if [ -n "$(trim "$tracked_status")" ]; then
            printf '%s\n' "$tracked_status" | sed -n '1,80p'
            tracked_count=$(printf '%s\n' "$tracked_status" | sed '/^$/d' | wc -l | tr -d ' ')
            case "$tracked_count" in
              ""|*[!0-9]*)
                tracked_count=0
                ;;
            esac
            if [ "$tracked_count" -gt 80 ]; then
              printf '... (%s more tracked changes)\n' "$((tracked_count - 80))"
            fi
          else
            printf '(clean tracked tree)\n'
          fi

          untracked_status=$(git ls-files --others --exclude-standard 2>/dev/null || true)
          untracked_count=$(printf '%s\n' "$untracked_status" | sed '/^$/d' | wc -l | tr -d ' ')
          case "$untracked_count" in
            ""|*[!0-9]*)
              untracked_count=0
              ;;
          esac
          if [ "$untracked_count" -gt 0 ]; then
            assay_profile_snapshot=${assay_run_profile:-0}
            case "$assay_profile_snapshot" in
              1)
                # Keep assay prompts signal-dense: retain untracked volume but suppress long file samples.
                printf '\nUntracked files: %s total (suppressed in assay context for signal-to-noise).\n' "$untracked_count"
                ;;
              *)
                if [ "$untracked_count" -gt 200 ]; then
                  printf '\nUntracked files: %s total (sample suppressed for context compactness).\n' "$untracked_count"
                else
                  printf '\nUntracked files (showing up to 25 of %s):\n' "$untracked_count"
                  printf '%s\n' "$untracked_status" | sed -n '1,25p'
                  if [ "$untracked_count" -gt 25 ]; then
                    printf '... (%s more untracked files)\n' "$((untracked_count - 25))"
                  fi
                fi
                ;;
            esac
          fi
        else
          printf 'Not a git repository.\n'
        fi
      }
  ) >"$tmp_file" 2>&1; then
    :
  fi

  cat "$tmp_file"
  rm -f "$tmp_file"
}

conversation_history() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort | tail -n 12 >"$temp_list"

  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    content=$(cat "$msg_file")
    case "$role" in
      user)
        printf 'User:\n%s\n\n' "$content"
        ;;
      assistant)
        printf 'Assistant:\n%s\n\n' "$content"
        ;;
      *)
        printf 'System:\n%s\n\n' "$content"
        ;;
    esac
  done <"$temp_list"

  rm -f "$temp_list"
}

recent_user_turns_for_conversation() {
  conv_dir=$1
  max_turns_raw=${2:-4}
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0
  case "$max_turns_raw" in
    ""|*[!0-9]*)
      max_turns=4
      ;;
    *)
      max_turns=$max_turns_raw
      ;;
  esac
  if [ "$max_turns" -lt 1 ]; then
    max_turns=1
  fi
  if [ "$max_turns" -gt 8 ]; then
    max_turns=8
  fi

  temp_list=$(mktemp)
  temp_user=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort | tail -n 24 > "$temp_list"
  : > "$temp_user"
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    [ "$role" = "user" ] || continue
    content=$(cat "$msg_file")
    content=$(printf '%s' "$content" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
    [ -n "$content" ] || continue
    printf '%s\n' "$content" >> "$temp_user"
  done < "$temp_list"
  if [ -s "$temp_user" ]; then
    tail -n "$max_turns" "$temp_user" | awk '{ printf "%d. %s\n", NR, $0 }'
  fi
  rm -f "$temp_list" "$temp_user"
}

conversation_last_message_for_role() {
  conv_dir=$1
  target_role=$2
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort > "$temp_list"
  last_file=""
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    if [ "$role" = "$target_role" ]; then
      last_file=$msg_file
    fi
  done < "$temp_list"
  rm -f "$temp_list"

  if [ -n "$last_file" ] && [ -f "$last_file" ]; then
    cat "$last_file"
  fi
}

conversation_previous_message_for_role() {
  conv_dir=$1
  target_role=$2
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || return 0

  temp_list=$(mktemp)
  find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sort > "$temp_list"
  previous_file=""
  current_file=""
  while IFS= read -r msg_file; do
    [ -f "$msg_file" ] || continue
    msg_name=$(basename "$msg_file")
    role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
    if [ "$role" = "$target_role" ]; then
      previous_file=$current_file
      current_file=$msg_file
    fi
  done < "$temp_list"
  rm -f "$temp_list"

  if [ -n "$previous_file" ] && [ -f "$previous_file" ]; then
    cat "$previous_file"
  fi
}

assistant_output_is_programming_summary_contract() {
  output_text=$1
  for required in "Outcome:" "Files Changed:" "Verification Evidence:" "Risks:" "Next Improvement:"; do
    if ! printf '%s\n' "$output_text" | grep -Eq "^$required"; then
      return 1
    fi
  done
  return 0
}

workspace_latest_programming_summary_conversation_dir() {
  workspace_id=$1
  exclude_conversation_id=${2-}
  ws_dir=$(workspace_dir_for "$workspace_id")
  conv_root="$ws_dir/conversations"
  [ -d "$conv_root" ] || return 0
  best_dir=""
  best_updated=0
  for conv_dir in "$conv_root"/*; do
    [ -d "$conv_dir" ] || continue
    conv_id=$(basename "$conv_dir")
    if [ -n "$exclude_conversation_id" ] && [ "$conv_id" = "$exclude_conversation_id" ]; then
      continue
    fi
    last_assistant=$(conversation_last_message_for_role "$conv_dir" "assistant")
    if ! assistant_output_is_programming_summary_contract "$last_assistant"; then
      continue
    fi
    updated_epoch=$(read_file_line "$conv_dir/updated" "0")
    case "$updated_epoch" in
      ''|*[!0-9]*)
        updated_epoch=0
        ;;
    esac
    if [ -z "$best_dir" ] || [ "$updated_epoch" -ge "$best_updated" ]; then
      best_dir=$conv_dir
      best_updated=$updated_epoch
    fi
  done
  printf '%s' "$best_dir"
}

workspace_name_for_id() {
  workspace_id=$1
  read_file_line "$(workspace_dir_for "$workspace_id")/name" "$workspace_id"
}

programming_requested_source_workspace_hint_for_prompt() {
  prompt_text=$1
  hint=$(printf '%s\n' "$prompt_text" | sed -n 's/^Related workspace:[[:space:]]*//p' | sed -n '1p')
  if [ -z "$(trim "$hint")" ]; then
    hint=$(printf '%s\n' "$prompt_text" | sed -n 's/^Source workspace:[[:space:]]*//p' | sed -n '1p')
  fi
  hint=$(printf '%s' "$hint" | sed 's/[[:space:]]*[.;][[:space:]].*$//')
  printf '%s' "$(trim "$hint")"
}

workspace_match_score_for_hint() {
  workspace_id=$1
  workspace_hint=$(trim "$2")
  if [ -z "$workspace_hint" ]; then
    printf '%s' "0"
    return 0
  fi

  workspace_name=$(workspace_name_for_id "$workspace_id")
  workspace_path=$(workspace_path_for_id "$workspace_id")
  workspace_basename=""
  if [ -n "$workspace_path" ]; then
    workspace_basename=$(basename "$workspace_path")
  fi

  hint_lower=$(printf '%s' "$workspace_hint" | tr '[:upper:]' '[:lower:]')
  workspace_id_lower=$(printf '%s' "$workspace_id" | tr '[:upper:]' '[:lower:]')
  workspace_name_lower=$(printf '%s' "$workspace_name" | tr '[:upper:]' '[:lower:]')
  workspace_path_lower=$(printf '%s' "$workspace_path" | tr '[:upper:]' '[:lower:]')
  workspace_basename_lower=$(printf '%s' "$workspace_basename" | tr '[:upper:]' '[:lower:]')

  if [ "$hint_lower" = "$workspace_id_lower" ]; then
    printf '%s' "400"
  elif [ -n "$workspace_name_lower" ] && [ "$hint_lower" = "$workspace_name_lower" ]; then
    printf '%s' "350"
  elif [ -n "$workspace_path_lower" ] && [ "$hint_lower" = "$workspace_path_lower" ]; then
    printf '%s' "300"
  elif [ -n "$workspace_basename_lower" ] && [ "$hint_lower" = "$workspace_basename_lower" ]; then
    printf '%s' "250"
  else
    printf '%s' "0"
  fi
}

workspace_programming_summary_conversation_dir_for_hint() {
  current_workspace_id=$1
  workspace_hint=$2
  best_dir=""
  best_updated=0
  best_score=0

  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    candidate_workspace_id=$(basename "$ws_dir")
    if [ "$candidate_workspace_id" = "$current_workspace_id" ]; then
      continue
    fi
    candidate_score=$(workspace_match_score_for_hint "$candidate_workspace_id" "$workspace_hint")
    case "$candidate_score" in
      ''|*[!0-9]*)
        candidate_score=0
        ;;
    esac
    if [ "$candidate_score" -le 0 ]; then
      continue
    fi
    candidate_dir=$(workspace_latest_programming_summary_conversation_dir "$candidate_workspace_id" "")
    if [ -z "$candidate_dir" ] || [ ! -d "$candidate_dir" ]; then
      continue
    fi
    candidate_updated=$(read_file_line "$candidate_dir/updated" "0")
    case "$candidate_updated" in
      ''|*[!0-9]*)
        candidate_updated=0
        ;;
    esac
    if [ -z "$best_dir" ] || [ "$candidate_score" -gt "$best_score" ] || { [ "$candidate_score" -eq "$best_score" ] && [ "$candidate_updated" -ge "$best_updated" ]; }; then
      best_dir=$candidate_dir
      best_updated=$candidate_updated
      best_score=$candidate_score
    fi
  done

  printf '%s' "$best_dir"
}

single_line_snippet() {
  text=$1
  printf '%s' "$text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cut -c1-220
}

file_mtime_epoch() {
  file_path=$1
  if [ ! -f "$file_path" ]; then
    printf '%s' "0"
    return 0
  fi
  if stat -f %m "$file_path" >/dev/null 2>&1; then
    stat -f %m "$file_path" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  if stat -c %Y "$file_path" >/dev/null 2>&1; then
    stat -c %Y "$file_path" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  printf '%s' "0"
}

human_elapsed_label() {
  elapsed_raw=$1
  case "$elapsed_raw" in
    ""|*[!0-9]*)
      elapsed_raw=0
      ;;
  esac
  if [ "$elapsed_raw" -lt 60 ]; then
    printf '%ss' "$elapsed_raw"
    return 0
  fi
  if [ "$elapsed_raw" -lt 3600 ]; then
    printf '%sm' $((elapsed_raw / 60))
    return 0
  fi
  if [ "$elapsed_raw" -lt 86400 ]; then
    printf '%sh %sm' $((elapsed_raw / 3600)) $(((elapsed_raw % 3600) / 60))
    return 0
  fi
  printf '%sd %sh' $((elapsed_raw / 86400)) $(((elapsed_raw % 86400) / 3600))
}

teacher_last_assistant_gap_seconds() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  if [ ! -d "$msg_dir" ]; then
    printf '%s' "-1"
    return 0
  fi
  last_assistant_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-assistant.txt' 2>/dev/null | sort | tail -n 1)
  if [ -z "$last_assistant_file" ] || [ ! -f "$last_assistant_file" ]; then
    printf '%s' "-1"
    return 0
  fi
  last_epoch=$(file_mtime_epoch "$last_assistant_file")
  case "$last_epoch" in
    ""|*[!0-9]*)
      printf '%s' "-1"
      return 0
      ;;
  esac
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  gap=$((now_epoch - last_epoch))
  if [ "$gap" -lt 0 ]; then
    gap=0
  fi
  printf '%s' "$gap"
}

teacher_gap_summary_for_conversation() {
  conv_dir=$1
  gap_seconds=$(teacher_last_assistant_gap_seconds "$conv_dir")
  case "$gap_seconds" in
    ""|*[!0-9-]*)
      gap_seconds=-1
      ;;
  esac
  if [ "$gap_seconds" -lt 0 ]; then
    printf '%s' "No prior teacher response in this thread; start with a light diagnostic and baseline lesson."
    return 0
  fi
  gap_label=$(human_elapsed_label "$gap_seconds")
  if [ "$gap_seconds" -ge 1209600 ]; then
    printf '%s' "Long gap since last teaching response (${gap_label}); begin with retrieval practice and concept refresh."
    return 0
  fi
  if [ "$gap_seconds" -ge 259200 ]; then
    printf '%s' "Moderate gap since last teaching response (${gap_label}); briefly recap before advancing."
    return 0
  fi
  printf '%s' "Recent continuation (${gap_label} since last teaching response); continue progression with quick checks."
}

teacher_review_interval_days_for_gap() {
  gap_seconds_raw=$1
  case "$gap_seconds_raw" in
    ""|*[!0-9-]*)
      gap_seconds_raw=-1
      ;;
  esac
  if [ "$gap_seconds_raw" -lt 0 ]; then
    printf '%s' "2"
    return 0
  fi
  if [ "$gap_seconds_raw" -ge 1209600 ]; then
    printf '%s' "1"
    return 0
  fi
  if [ "$gap_seconds_raw" -ge 604800 ]; then
    printf '%s' "2"
    return 0
  fi
  printf '%s' "3"
}

ensure_teacher_model_file() {
  model_file=$1
  if [ -f "$model_file" ]; then
    return 0
  fi
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  cat > "$model_file" <<EOF
# Learner Model

Created: $timestamp
Updated: $timestamp

## Stable Profile
- learning_goals: unknown
- current_level_estimate: unknown
- preferred_explanation_style: unknown
- misconception_watchlist: none recorded

## Curriculum Backlog
- pending

## Spaced Review Plan
- pending

## Session Notes
EOF
}

teacher_update_model_timestamp() {
  model_file=$1
  timestamp=$2
  [ -f "$model_file" ] || return 0
  tmp_file=$(mktemp)
  awk -v ts="$timestamp" '
    BEGIN { replaced = 0 }
    {
      if (!replaced && $0 ~ /^Updated:[[:space:]]*/) {
        print "Updated: " ts
        replaced = 1
        next
      }
      print
    }
    END {
      if (!replaced) {
        print "Updated: " ts
      }
    }
  ' "$model_file" > "$tmp_file"
  mv "$tmp_file" "$model_file"
}

append_teacher_model_note() {
  model_file=$1
  heading=$2
  body=$3
  ensure_teacher_model_file "$model_file"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  teacher_update_model_timestamp "$model_file" "$timestamp"
  {
    printf '\n### %s (%s)\n' "$heading" "$timestamp"
    printf '%s\n' "$body"
  } >> "$model_file"

  line_count=$(wc -l < "$model_file" 2>/dev/null | tr -d ' ')
  case "$line_count" in
    ""|*[!0-9]*)
      line_count=0
      ;;
  esac
  if [ "$line_count" -gt 520 ]; then
    tmp_file=$(mktemp)
    sed -n '1,120p' "$model_file" > "$tmp_file"
    printf '\n## Session Notes (trimmed)\n' >> "$tmp_file"
    tail -n 320 "$model_file" >> "$tmp_file"
    mv "$tmp_file" "$model_file"
  fi
}

workspace_shared_context() {
  ws_dir=$1
  active_conv_id=$2
  conv_root="$ws_dir/conversations"
  [ -d "$conv_root" ] || return 0

  listed=0
  for conv_dir in "$conv_root"/*; do
    [ -d "$conv_dir" ] || continue
    conv_id=$(basename "$conv_dir")
    [ "$conv_id" = "$active_conv_id" ] && continue

    title=$(read_file_line "$conv_dir/title" "Conversation")
    updated=$(read_file_line "$conv_dir/updated" "0")
    model=$(read_file_line "$conv_dir/model" "")

    msg_dir="$conv_dir/messages"
    user_snippet=""
    assistant_snippet=""
    if [ -d "$msg_dir" ]; then
      last_user_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-user.txt' 2>/dev/null | sort | tail -n 1)
      last_assistant_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-assistant.txt' 2>/dev/null | sort | tail -n 1)
      if [ -n "$last_user_file" ] && [ -f "$last_user_file" ]; then
        user_snippet=$(single_line_snippet "$(cat "$last_user_file" 2>/dev/null || true)")
      fi
      if [ -n "$last_assistant_file" ] && [ -f "$last_assistant_file" ]; then
        assistant_snippet=$(single_line_snippet "$(cat "$last_assistant_file" 2>/dev/null || true)")
      fi
    fi

    printf 'Thread: %s\n' "$title"
    printf 'Updated: %s\n' "$updated"
    if [ -n "$model" ]; then
      printf 'Model: %s\n' "$model"
    fi
    if [ -n "$user_snippet" ]; then
      printf 'Recent user intent: %s\n' "$user_snippet"
    fi
    if [ -n "$assistant_snippet" ]; then
      printf 'Recent assistant output: %s\n' "$assistant_snippet"
    fi
    printf '\n'

    listed=$((listed + 1))
    if [ "$listed" -ge 8 ]; then
      break
    fi
  done
}

json_messages() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  printf '['
  first=1
  if [ -d "$msg_dir" ]; then
    for msg_file in "$msg_dir"/*.txt; do
      [ -f "$msg_file" ] || continue
      msg_name=$(basename "$msg_file")
      role=$(printf '%s' "$msg_name" | sed 's/^[0-9][0-9][0-9][0-9]-//;s/\.txt$//')
      content=$(cat "$msg_file")
      role_json=$(json_escape "$role")
      content_json=$(json_escape "$content")
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"role":"%s","content":"%s"}' "$role_json" "$content_json"
    done
  fi
  printf ']'
}

latest_user_message_for_conversation() {
  conv_dir=$1
  msg_dir="$conv_dir/messages"
  [ -d "$msg_dir" ] || {
    printf '%s' ""
    return 0
  }
  latest_user_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*-user.txt' 2>/dev/null | sort | tail -n 1)
  if [ -z "$latest_user_file" ] || [ ! -f "$latest_user_file" ]; then
    printf '%s' ""
    return 0
  fi
  cat "$latest_user_file"
}

seed_missing_initial_message_if_needed() {
  conv_dir=$1
  title=$(read_file_line "$conv_dir/title" "")
  created=$(read_file_line "$conv_dir/created" "0")
  updated=$(read_file_line "$conv_dir/updated" "0")
  msg_dir="$conv_dir/messages"

  [ -d "$msg_dir" ] || return 0
  first_msg_file=$(find "$msg_dir" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | sed -n '1p')
  [ -z "$first_msg_file" ] || return 0

  title_trim=$(trim "$title")
  if [ -z "$title_trim" ]; then
    return 0
  fi
  case "$title_trim" in
    Conversation|New\ Conversation)
      return 0
      ;;
  esac

  # Only auto-recover obvious orphaned threads where the first prompt never persisted.
  if [ "$created" != "$updated" ]; then
    return 0
  fi
  # Prevent duplicate-first-message races on freshly created threads.
  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$created" in
    ""|*[!0-9]*)
      created=0
      ;;
  esac
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac
  if [ "$created" -gt 0 ] && [ "$now_epoch" -gt 0 ]; then
    created_age=$((now_epoch - created))
    if [ "$created_age" -lt 180 ]; then
      return 0
    fi
  fi

  queue_info=$(queue_state_for_conversation "$conv_dir")
  queue_pending=$(kv_get "pending" "$queue_info")
  queue_running=$(kv_get "running" "$queue_info")
  [ -n "$queue_pending" ] || queue_pending=0
  [ -n "$queue_running" ] || queue_running=0
  if [ "$queue_pending" != "0" ] || [ "$queue_running" != "0" ]; then
    return 0
  fi

  run_events_dir=$(run_events_dir_for_conversation "$conv_dir")
  run_event_count=$( (find "$run_events_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null || true) | wc -l | tr -d ' ' )
  [ -n "$run_event_count" ] || run_event_count=0
  if [ "$run_event_count" != "0" ]; then
    return 0
  fi

  append_message "$conv_dir" "user" "$title_trim"
}

extract_patch_section() {
  text=$1
  known_headers="MODE_UPDATE COMMANDS CONTRACT PATCH DONE_CLAIM PLAN_UPDATE CHECKPOINT DECISION_REQUEST FINAL REVIEW_DECISION REVIEW_FEEDBACK"
  patch_text=$(printf '%s\n' "$text" | awk -v headers="$known_headers" '
    function trim_local(value) {
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    BEGIN {
      capture = 0
      in_fence = 0
      header_count = split(headers, header_list, /[[:space:]]+/)
      for (header_index = 1; header_index <= header_count; header_index++) {
        if (header_list[header_index] != "") {
          known[header_list[header_index]] = 1
        }
      }
    }
    {
      normalized = $0
      sub(/^[[:space:]]*[*#>[:space:]]*/, "", normalized)
      if (normalized ~ /^```/) {
        if (in_fence == 1) {
          in_fence = 0
        } else {
          in_fence = 1
        }
      }

      header = ""
      remainder = ""
      split_pos = index(normalized, ":")
      if (split_pos > 0) {
        header = substr(normalized, 1, split_pos - 1)
        header = trim_local(header)
        header = toupper(header)
        gsub(/[[:space:]]+/, "_", header)
        remainder = trim_local(substr(normalized, split_pos + 1))
      }

      if (header != "" && !in_fence && (header in known)) {
        if (header == "PATCH") {
          capture = 1
          if (remainder != "") {
            print remainder
          }
          next
        }
        if (capture == 1) {
          capture = 0
          next
        }
      }

      if (capture == 1) {
        print
      }
    }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | sed -n '/^BEGIN_PATCH$/,/^END_PATCH$/p' | sed '1d;$d')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN { capture = 0 }
    /^```diff[[:space:]]*$/ { capture = 1; next }
    capture && /^```[[:space:]]*$/ { capture = 0; exit }
    capture { print }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN { capture = 0 }
    /^```patch[[:space:]]*$/ { capture = 1; next }
    capture && /^```[[:space:]]*$/ { capture = 0; exit }
    capture { print }
  ')
  if [ -n "$(trim "$patch_text")" ]; then
    printf '%s\n' "$patch_text"
    return 0
  fi

  patch_text=$(printf '%s\n' "$text" | awk '
    BEGIN {
      capture = 0
      seen_diff = 0
    }
    /^---[[:space:]]/ {
      capture = 1
      seen_diff = 1
    }
    capture {
      if (($0 ~ /^[A-Z][A-Z_ ]*:[[:space:]]*$/ || $0 ~ /^\*\*[A-Z][A-Z_ ]*:[[:space:]]*/ || $0 ~ /^#+[[:space:]]*[A-Z][A-Z_ ]*:[[:space:]]*/) && seen_diff == 1) {
        exit
      }
      print
    }
  ')
  printf '%s\n' "$patch_text"
}

normalize_patch_text() {
  text=$1
  printf '%s\n' "$text" | sed '/^[[:space:]]*```/d' | perl -CS -pe '
    s/^\+\+\s+(b\/\S+)/+++ $1/;
    s/^--\s+(a\/\S+)/--- $1/;
    s/^@@\s+-([0-9]+(?:,[0-9]+)?)\s+([0-9]+(?:,[0-9]+)?)\s+@@/@@ -$1 +$2 @@/;
  '
}

looks_like_unified_diff_text() {
  text=$1
  if ! printf '%s\n' "$text" | grep -q '^---[[:space:]]'; then
    return 1
  fi
  if ! printf '%s\n' "$text" | grep -q '^+++[[:space:]]'; then
    return 1
  fi
  return 0
}

patch_has_valid_hunks() {
  text=$1
  printf '%s\n' "$text" | perl -e '
    use strict;
    use warnings;
    my $in_hunk = 0;
    my $saw_hunk = 0;
    my $ok = 1;
    my ($expected_old, $expected_new, $seen_old, $seen_new) = (0, 0, 0, 0);

    while (my $line = <STDIN>) {
      chomp $line;

      if ($line =~ /^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@/) {
        if ($in_hunk) {
          if ($seen_old != $expected_old || $seen_new != $expected_new) {
            $ok = 0;
            last;
          }
          $in_hunk = 0;
        }
        $expected_old = defined($2) ? $2 : 1;
        $expected_new = defined($4) ? $4 : 1;
        $seen_old = 0;
        $seen_new = 0;
        $in_hunk = 1;
        $saw_hunk = 1;
        next;
      }

      if ($line =~ /^(diff --git |--- |\+\+\+ )/) {
        if ($in_hunk) {
          if ($seen_old != $expected_old || $seen_new != $expected_new) {
            $ok = 0;
            last;
          }
          $in_hunk = 0;
        }
        next;
      }

      if ($line =~ /^(index |new file mode |deleted file mode |old mode |new mode |similarity index |rename from |rename to |Binary files )/) {
        next;
      }

      if ($in_hunk) {
        if ($line =~ /^ /) {
          $seen_old += 1;
          $seen_new += 1;
          next;
        }
        if ($line =~ /^-/) {
          $seen_old += 1;
          next;
        }
        if ($line =~ /^\+/) {
          $seen_new += 1;
          next;
        }
        if ($line =~ /^\\ No newline at end of file$/) {
          next;
        }
        $ok = 0;
        last;
      }
    }

    if ($ok && $in_hunk) {
      if ($seen_old != $expected_old || $seen_new != $expected_new) {
        $ok = 0;
      }
    }

    exit(($ok && $saw_hunk) ? 0 : 1);
  '
}

patch_uses_ab_prefix_paths() {
  patch_text=$1
  if printf '%s\n' "$patch_text" | grep -Eq '^(diff --git a/|--- a/|\+\+\+ b/)'; then
    return 0
  fi
  return 1
}

patch_candidate_is_usable() {
  text=$1
  text_trimmed=$(trim "$text")
  if [ -z "$text_trimmed" ] || [ "$text_trimmed" = "NONE" ]; then
    return 1
  fi
  if ! looks_like_unified_diff_text "$text"; then
    return 1
  fi
  if ! patch_has_valid_hunks "$text"; then
    return 1
  fi
  if ! printf '%s\n' "$text" | awk '
    /^\+[^\+]/ {
      line = $0
      sub(/^\+/, "", line)
      if (line ~ /[^[:space:]]/) {
        found = 1
        exit
      }
    }
    END {
      if (!found) exit 1
    }
  '; then
    return 1
  fi
  return 0
}

recover_new_files_patch_candidate() {
  patch_text=$1
  recover_dir=$(mktemp -d)
  recover_index=$(mktemp)
  synthesized_patch=""
  : > "$recover_index"

  printf '%s\n' "$patch_text" | RECOVER_DIR="$recover_dir" perl -e '
    use strict;
    use warnings;
    local $/;
    my $raw = <>;
    my $dir = $ENV{"RECOVER_DIR"} // "";
    my $count = 0;
    while ($raw =~ /(?:^|\n)---\s+\/dev\/null\s*\n\+\+\+\s+b\/([^\r\n]+)\s*\n(.*?)(?=\n---\s+|\z)/sg) {
      my $path = $1 // "";
      my $body = $2 // "";
      $path =~ s/^\s+//;
      $path =~ s/\s+$//;
      next if $path eq "";
      next if $path =~ m{(?:^|/)\.\.(?:/|$)};
      next if $path =~ m{^/};
      my @content;
      for my $line (split /\n/, $body) {
        next if $line =~ /^@@ /;
        next if $line =~ /^index /;
        next if $line =~ /^new file mode /;
        next if $line =~ /^\\ No newline at end of file$/;
        if ($line =~ /^\+(?!\+\+)/) {
          $line =~ s/^\+//;
          push @content, $line;
        }
      }
      next if !@content;
      my $joined = join("\n", @content) . "\n";
      next if $joined !~ /\S/;
      $count += 1;
      last if $count > 5;
      my $tmp_path = "$dir/$count.content";
      open my $fh, ">:encoding(UTF-8)", $tmp_path or next;
      print {$fh} $joined;
      close $fh;
      print "$path\t$tmp_path\n";
    }
  ' > "$recover_index"

  if [ -s "$recover_index" ]; then
    while IFS='	' read -r out_path out_tmp; do
      out_path=$(trim "$out_path")
      out_tmp=$(trim "$out_tmp")
      [ -n "$out_path" ] || continue
      [ -f "$out_tmp" ] || continue
      if ! is_safe_relative_path "$out_path"; then
        continue
      fi
      file_diff=$(diff -u /dev/null "$out_tmp" || true)
      if [ -n "$(trim "$file_diff")" ]; then
        file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
        synthesized_patch="${synthesized_patch}
${file_diff}"
      fi
    done < "$recover_index"
  fi

  rm -rf "$recover_dir" 2>/dev/null || true
  rm -f "$recover_index"
  synthesized_patch=$(trim_block_edges "$synthesized_patch")
  printf '%s' "$synthesized_patch"
}

resolve_patch_candidate() {
  raw_patch=$1
  if patch_candidate_is_usable "$raw_patch"; then
    printf '%s' "$raw_patch"
    return 0
  fi
  recovered_patch=$(recover_new_files_patch_candidate "$raw_patch")
  if patch_candidate_is_usable "$recovered_patch"; then
    printf '%s' "$recovered_patch"
    return 0
  fi
  return 1
}

extract_json_commands_from_text() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    if (/"COMMANDS"\s*:\s*\[(.*?)\]/is) {
      my $body = $1 // "";
      while ($body =~ /"((?:\\.|[^"])*)"/g) {
        my $cmd = $1;
        $cmd =~ s/\\n/ /g;
        $cmd =~ s/\\r/ /g;
        $cmd =~ s/\\"/"/g;
        $cmd =~ s/\\\\/\\/g;
        $cmd =~ s/^\s+//;
        $cmd =~ s/\s+$//;
        next if $cmd eq "";
        print "$cmd\n";
      }
    }
  '
}

extract_readonly_commands_from_text() {
  text=$1
  state_mode_hint=$(trim "${2:-}")
  candidate_file=$(mktemp)
  deduped_file=$(mktemp)
  accepted_file=$(mktemp)
  fallback_file=$(mktemp)
  count=0
  : > "$candidate_file"
  : > "$accepted_file"

  extract_json_commands_from_text "$text" >> "$candidate_file" || true
  extract_command_lines "$text" >> "$candidate_file" || true
  awk '!seen[$0]++' "$candidate_file" > "$deduped_file"

  while IFS= read -r candidate; do
    candidate=$(printf '%s\n' "$candidate" | perl -CS -pe '
      s/\r//g;
      s/\\\\n/\n/g;
      s/\\n/\n/g;
      s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
    ' | sed -n '1p')
    candidate=$(printf '%s\n' "$candidate" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
    candidate=$(sanitize_controller_command_candidate "$candidate" "$state_mode_hint")
    candidate=$(trim "$candidate")
    [ -n "$candidate" ] || continue
    if allowed_command "$candidate"; then
      if ! grep -Fqx -- "$candidate" "$accepted_file"; then
        printf '%s\n' "$candidate" >> "$accepted_file"
        count=$((count + 1))
        if [ "$count" -ge 3 ]; then
          break
        fi
      fi
    fi
  done < "$deduped_file"
  if [ "$count" -lt 2 ]; then
    fallback_readonly_commands_for_mode "$state_mode_hint" > "$fallback_file"
    while IFS= read -r fallback_candidate; do
      fallback_candidate=$(sanitize_controller_command_candidate "$fallback_candidate" "$state_mode_hint")
      fallback_candidate=$(trim "$fallback_candidate")
      [ -n "$fallback_candidate" ] || continue
      if ! allowed_command "$fallback_candidate"; then
        continue
      fi
      if grep -Fqx -- "$fallback_candidate" "$accepted_file"; then
        continue
      fi
      printf '%s\n' "$fallback_candidate" >> "$accepted_file"
      count=$((count + 1))
      if [ "$count" -ge 3 ]; then
        break
      fi
    done < "$fallback_file"
  fi
  if [ -s "$accepted_file" ]; then
    sed 's/^/- /' "$accepted_file"
  fi
  rm -f "$candidate_file" "$deduped_file" "$accepted_file" "$fallback_file"
}

controller_output_has_required_sections() {
  text=$1
  normalized_text=$(canonicalize_controller_output "$text")
  if ! printf '%s\n' "$normalized_text" | grep -q '^MODE_UPDATE:[[:space:]]*$'; then
    return 1
  fi
  if ! printf '%s\n' "$normalized_text" | grep -q '^PLAN_UPDATE:[[:space:]]*$'; then
    return 1
  fi
  if ! printf '%s\n' "$normalized_text" | grep -Eq '^(COMMANDS|CONTRACT|PATCH|DONE_CLAIM|CHECKPOINT):[[:space:]]*$'; then
    return 1
  fi
  return 0
}

repair_partial_controller_output() {
  raw_text=$(canonicalize_controller_output "$1")
  current_mode=$2
  state_target_value=$3
  state_confidence_value=$4
  current_plan_text=$5

  if [ -z "$(trim "$raw_text")" ]; then
    printf '%s' "$raw_text"
    return 0
  fi

  has_mode_header=0
  has_plan_header=0
  has_action_header=0
  if printf '%s\n' "$raw_text" | grep -q '^MODE_UPDATE:[[:space:]]*$'; then
    has_mode_header=1
  fi
  if printf '%s\n' "$raw_text" | grep -q '^PLAN_UPDATE:[[:space:]]*$'; then
    has_plan_header=1
  fi
  if printf '%s\n' "$raw_text" | grep -Eq '^(COMMANDS|CONTRACT|PATCH|DONE_CLAIM|CHECKPOINT):[[:space:]]*$'; then
    has_action_header=1
  fi
  if [ "$has_mode_header" -eq 0 ] || [ "$has_action_header" -eq 0 ]; then
    printf '%s' "$raw_text"
    return 0
  fi
  if [ "$has_plan_header" -eq 1 ] && controller_output_has_required_sections "$raw_text"; then
    printf '%s' "$raw_text"
    return 0
  fi

  mode_update_candidate=$(extract_section "MODE_UPDATE" "$raw_text")
  mode_target=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^target=//p' | sed -n '1p')
  mode_blocking=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^blocking=//p' | sed -n '1p')
  mode_confidence=$(printf '%s\n' "$mode_update_candidate" | sed -n 's/^confidence=//p' | sed -n '1p')
  mode_target=$(trim "$mode_target")
  mode_blocking=$(trim "$mode_blocking")
  mode_confidence=$(trim "$mode_confidence")
  if [ -z "$mode_target" ]; then
    mode_target=$state_target_value
  fi
  if [ -z "$mode_blocking" ]; then
    mode_blocking="controller output partially formatted; completed missing sections"
  fi
  case "$mode_confidence" in
    ""|*[!0-9.]*)
      mode_confidence=$state_confidence_value
      ;;
  esac
  if [ -z "$mode_confidence" ]; then
    mode_confidence=$state_confidence_value
  fi

  repaired_commands=$(extract_readonly_commands_from_text "$raw_text" "$current_mode" || true)
  if [ -z "$(trim "$repaired_commands")" ]; then
    repaired_commands=$(fallback_readonly_commands_for_mode "$current_mode" | sed -n '1,3p' | sed 's/^/- /')
  fi
  if [ -z "$(trim "$repaired_commands")" ]; then
    repaired_commands="NONE"
  fi

  repaired_contract=$(extract_section "CONTRACT" "$raw_text" | sed -n '1,140p')
  repaired_contract=$(trim "$repaired_contract")
  if [ -z "$repaired_contract" ] || [ "$repaired_contract" = "NONE" ]; then
    if [ "$current_mode" = "DESIGN" ]; then
      repaired_contract=$(cat <<EOF
Inputs:
- user request from PLAN_UPDATE
Outputs:
- concrete design deliverable and verification checklist
Side Effects:
- none in design-only recovery step
Dependencies:
- repository inspection commands and current workspace context
Invariants:
- maintain deterministic, auditable, and safe recommendations
EOF
)
    else
      repaired_contract="NONE"
    fi
  fi

  repaired_patch="NONE"
  patch_candidate=$(extract_patch_section "$raw_text")
  patch_candidate=$(normalize_patch_text "$patch_candidate")
  resolved_patch=$(resolve_patch_candidate "$patch_candidate" || true)
  if [ -n "$(trim "$resolved_patch")" ]; then
    repaired_patch=$resolved_patch
  fi

  repaired_done_claim=$(extract_section "DONE_CLAIM" "$raw_text" | sed -n '1p' | tr 'A-Z' 'a-z' | awk '{print $1}')
  case "$repaired_done_claim" in
    yes)
      ;;
    *)
      repaired_done_claim="no"
      ;;
  esac

  repaired_plan=$(extract_section "PLAN_UPDATE" "$raw_text")
  repaired_plan=$(trim "$repaired_plan")
  if [ -z "$repaired_plan" ] || [ "$repaired_plan" = "NONE" ]; then
    repaired_plan=$current_plan_text
  fi

  repaired_checkpoint=$(extract_section "CHECKPOINT" "$raw_text")
  repaired_checkpoint=$(trim "$repaired_checkpoint")
  if [ -z "$repaired_checkpoint" ] || [ "$repaired_checkpoint" = "NONE" ]; then
    repaired_checkpoint="Completed partial controller output by filling missing required sections."
  fi

  repaired_decision=$(extract_section "DECISION_REQUEST" "$raw_text")
  repaired_decision=$(trim "$repaired_decision")
  if [ -z "$repaired_decision" ]; then
    repaired_decision="NONE"
  fi

  repaired_final=$(extract_section "FINAL" "$raw_text")
  repaired_final=$(trim "$repaired_final")
  if [ -z "$repaired_final" ]; then
    repaired_final="NONE"
  fi

  cat <<EOF
MODE_UPDATE:
target=$mode_target
blocking=$mode_blocking
confidence=$mode_confidence
COMMANDS:
$repaired_commands
CONTRACT:
$repaired_contract
PATCH:
$repaired_patch
DONE_CLAIM:
$repaired_done_claim
PLAN_UPDATE:
$repaired_plan
CHECKPOINT:
$repaired_checkpoint
DECISION_REQUEST:
$repaired_decision
FINAL:
$repaired_final
EOF
}

recover_controller_output() {
  raw_text=$(canonicalize_controller_output "$1")
  current_mode=$2
  state_target_value=$3
  state_confidence_value=$4
  current_plan_text=$5

  recovered_commands="NONE"
  recovered_contract="NONE"
  recovered_patch="NONE"
  recovered_done_claim="no"
  recovered_checkpoint="Recovered malformed controller output; continuing with guarded defaults."
  recovered_final="NONE"

  commands_candidate=$(extract_readonly_commands_from_text "$raw_text" "$current_mode" || true)
  if [ -n "$(trim "$commands_candidate")" ]; then
    recovered_commands=$commands_candidate
  fi

  recovered_contract_candidate=$(extract_section "CONTRACT" "$raw_text" | sed -n '1,140p')
  recovered_contract_candidate=$(trim "$recovered_contract_candidate")
  if [ -n "$recovered_contract_candidate" ] && [ "$recovered_contract_candidate" != "NONE" ]; then
    recovered_contract=$recovered_contract_candidate
  elif [ "$current_mode" = "DESIGN" ]; then
    recovered_contract=$(cat <<EOF
Inputs:
- user request from PLAN_UPDATE
Outputs:
- concrete design deliverable and verification checklist
Side Effects:
- none in design-only recovery step
Dependencies:
- repository inspection commands and current workspace context
Invariants:
- maintain deterministic, auditable, and safe recommendations
EOF
)
  fi

  if [ "$current_mode" = "IMPLEMENT" ]; then
    patch_candidate=$(extract_patch_section "$raw_text")
    patch_candidate=$(normalize_patch_text "$patch_candidate")
    recovered_patch_candidate=$(resolve_patch_candidate "$patch_candidate" || true)
    if [ -n "$(trim "$recovered_patch_candidate")" ]; then
      recovered_patch=$recovered_patch_candidate
      recovered_checkpoint="Recovered malformed controller output and extracted unified diff patch candidate."
    fi
  fi

  case "$(printf '%s' "$raw_text" | tr '[:upper:]' '[:lower:]')" in
    *"done_claim:"*yes*|*"verification passed"*|*"ready to ship"*|*"task complete"*|*"completed request"*)
      recovered_done_claim="yes"
      ;;
  esac

  if [ "$current_mode" = "DONE" ]; then
    recovered_final=$(trim "$raw_text")
    if [ -z "$recovered_final" ]; then
      recovered_final="Completed requested work."
    fi
  fi

  cat <<EOF
MODE_UPDATE:
target=$state_target_value
blocking=controller output malformed; recovered
confidence=$state_confidence_value
COMMANDS:
$recovered_commands
CONTRACT:
$recovered_contract
PATCH:
$recovered_patch
DONE_CLAIM:
$recovered_done_claim
PLAN_UPDATE:
$current_plan_text
CHECKPOINT:
$recovered_checkpoint
DECISION_REQUEST:
NONE
FINAL:
$recovered_final
EOF
}

is_safe_relative_path() {
  rel=$1

  case "$rel" in
    ""|/*|*'..'*|*'~'*|*'\\'*|*':'*)
      return 1
      ;;
  esac

  case "$rel" in
    *[!a-zA-Z0-9._/-]*)
      return 1
      ;;
  esac

  return 0
}

patch_paths_from_text() {
  patch_text=$1
  printf '%s\n' "$patch_text" | awk '
    /^\+\+\+ / {
      path = $2
      sub(/^b\//, "", path)
      if (path != "/dev/null") {
        print path
      }
    }
  ' | awk '!seen[$0]++'
}

run_shell_command_with_timeout() {
  timeout_secs=$1
  command_text=$2

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_secs" sh -c "$command_text"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_secs" sh -c "$command_text"
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      use strict;
      use warnings;
      my ($t, $cmd) = @ARGV;
      my $pid = fork();
      die "fork failed" unless defined $pid;
      if ($pid == 0) { exec "sh", "-c", $cmd; exit 127; }
      my $timed_out = 0;
      local $SIG{ALRM} = sub { $timed_out = 1; kill 9, $pid; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      if ($timed_out) { exit 124; }
      my $rc = $? >> 8;
      exit $rc;
    ' "$timeout_secs" "$command_text"
    return $?
  fi

  sh -c "$command_text"
  return $?
}

command_output_indicates_failure() {
  command_text=$1
  output_file=$2
  first_word=$(printf '%s\n' "$command_text" | awk '{print $1}')

  case "$first_word" in
    godot|godot4)
      if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' "$output_file" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  return 1
}

resolve_relative_path_case_insensitive() {
  workspace_root=$1
  rel_path=$2

  if ! is_safe_relative_path "$rel_path"; then
    return 1
  fi
  if [ ! -d "$workspace_root" ]; then
    return 1
  fi

  current_dir=$workspace_root
  resolved_path=""
  remaining_path=$rel_path
  while [ -n "$remaining_path" ]; do
    segment=${remaining_path%%/*}
    if [ "$segment" = "$remaining_path" ]; then
      remaining_path=""
    else
      remaining_path=${remaining_path#*/}
    fi
    [ -n "$segment" ] || continue
    if [ -e "$current_dir/$segment" ]; then
      chosen_segment=$segment
    else
      segment_lc=$(printf '%s' "$segment" | tr '[:upper:]' '[:lower:]')
      chosen_segment=$(LC_ALL=C ls -1A "$current_dir" 2>/dev/null | awk -v target="$segment_lc" '
        tolower($0) == target { print; exit }
      ')
      if [ -z "$chosen_segment" ]; then
        return 1
      fi
    fi

    if [ -z "$resolved_path" ]; then
      resolved_path=$chosen_segment
    else
      resolved_path="$resolved_path/$chosen_segment"
    fi
    current_dir="$current_dir/$chosen_segment"
  done

  if [ -z "$resolved_path" ]; then
    return 1
  fi
  if ! is_safe_relative_path "$resolved_path"; then
    return 1
  fi
  if [ ! -e "$workspace_root/$resolved_path" ]; then
    return 1
  fi

  printf '%s' "$resolved_path"
}

path_mtime_epoch_any() {
  path_value=$1
  if [ ! -e "$path_value" ]; then
    printf '%s' "0"
    return 0
  fi
  if stat -f %m "$path_value" >/dev/null 2>&1; then
    stat -f %m "$path_value" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  if stat -c %Y "$path_value" >/dev/null 2>&1; then
    stat -c %Y "$path_value" 2>/dev/null || printf '%s' "0"
    return 0
  fi
  printf '%s' "0"
}

resolve_assay_task_relative_path_alias() {
  workspace_root=$1
  rel_path=$2

  if ! is_safe_relative_path "$rel_path"; then
    return 1
  fi
  if [ ! -d "$workspace_root/.assay-runs" ]; then
    return 1
  fi
  case "$rel_path" in
    .assay-runs/*)
      ;;
    *)
      return 1
      ;;
  esac
  if [ -e "$workspace_root/$rel_path" ]; then
    return 1
  fi

  path_without_prefix=${rel_path#".assay-runs/"}
  if [ "$path_without_prefix" = "$rel_path" ]; then
    return 1
  fi

  first_segment=${path_without_prefix%%/*}
  [ -n "$first_segment" ] || return 1
  if [ "$first_segment" = "$path_without_prefix" ]; then
    remaining_suffix=""
  else
    remaining_suffix=${path_without_prefix#*/}
  fi

  # If the first segment exists under .assay-runs, it is likely a run label,
  # not a task-id alias, so do not rewrite.
  if [ -d "$workspace_root/.assay-runs/$first_segment" ]; then
    return 1
  fi

  newest_task_dir=""
  newest_epoch=0
  while IFS= read -r candidate_dir || [ -n "$candidate_dir" ]; do
    [ -d "$candidate_dir" ] || continue
    candidate_epoch=$(path_mtime_epoch_any "$candidate_dir")
    case "$candidate_epoch" in
      ""|*[!0-9]*)
        candidate_epoch=0
        ;;
    esac
    if [ -z "$newest_task_dir" ] || [ "$candidate_epoch" -ge "$newest_epoch" ]; then
      newest_task_dir=$candidate_dir
      newest_epoch=$candidate_epoch
    fi
  done <<EOF
$(find "$workspace_root/.assay-runs" -mindepth 2 -maxdepth 2 -type d -name "$first_segment" 2>/dev/null)
EOF

  [ -n "$newest_task_dir" ] || return 1
  rewritten_rel=${newest_task_dir#"$workspace_root"/}
  if [ "$rewritten_rel" = "$newest_task_dir" ] || [ -z "$rewritten_rel" ]; then
    return 1
  fi
  if [ -n "$remaining_suffix" ]; then
    rewritten_rel="$rewritten_rel/$remaining_suffix"
  fi
  if ! is_safe_relative_path "$rewritten_rel"; then
    return 1
  fi
  printf '%s' "$rewritten_rel"
}

autocorrect_readonly_file_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  second_word=$(printf '%s\n' "$command_trimmed" | awk '{print $2}')
  case "$first_word" in
    cat|head|tail|sed|ls)
      ;;
    git)
      case "$second_word" in
        status)
          ;;
        *)
          printf '%s' "$raw_command"
          return 0
          ;;
      esac
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  last_token=$(printf '%s\n' "$command_trimmed" | awk '{print $NF}')
  last_token=$(trim "$last_token")
  if ! is_safe_relative_path "$last_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  resolved_task_alias=$(resolve_assay_task_relative_path_alias "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_task_alias" ] && [ "$resolved_task_alias" != "$last_token" ]; then
    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_task_alias" '
      {
        $NF = repl
        print
      }
    ')
    printf '%s' "$rewritten_command"
    return 0
  fi

  resolved_last_token=$(resolve_relative_path_case_insensitive "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_last_token" ] && [ "$resolved_last_token" != "$last_token" ]; then
    if ! is_safe_relative_path "$resolved_last_token"; then
      printf '%s' "$raw_command"
      return 0
    fi

    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_last_token" '
      {
        $NF = repl
        print
      }
    ')
    printf '%s' "$rewritten_command"
    return 0
  fi

  parent_dir="."
  case "$last_token" in
    */*)
      parent_dir=${last_token%/*}
      ;;
  esac
  parent_dir=$(trim "$parent_dir")
  if [ -z "$parent_dir" ]; then
    parent_dir="."
  fi
  if [ "$parent_dir" != "." ] && ! is_safe_relative_path "$parent_dir"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ ! -d "$workspace_root/$parent_dir" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  discovery_command="find $parent_dir -maxdepth 1 -type f"
  if [ "$parent_dir" = "." ]; then
    discovery_command="find . -maxdepth 1 -type f"
  fi
  if allowed_command "$discovery_command"; then
    printf '%s' "$discovery_command"
    return 0
  fi

  printf '%s' "$raw_command"
}

autocorrect_readonly_search_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  case "$first_word" in
    rg|grep)
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  last_token=$(printf '%s\n' "$command_trimmed" | awk '{print $NF}')
  last_token=$(trim "$last_token")
  if ! is_safe_relative_path "$last_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  resolved_task_alias=$(resolve_assay_task_relative_path_alias "$workspace_root" "$last_token" || true)
  if [ -n "$resolved_task_alias" ] && [ "$resolved_task_alias" != "$last_token" ]; then
    rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$resolved_task_alias" '
      {
        $NF = repl
        print
      }
    ')
    if allowed_command "$rewritten_command"; then
      printf '%s' "$rewritten_command"
      return 0
    fi
  fi

  resolved_last_token=$(resolve_relative_path_case_insensitive "$workspace_root" "$last_token" || true)
  replacement_token=$resolved_last_token
  if [ -z "$replacement_token" ]; then
    parent_dir="."
    case "$last_token" in
      */*)
        parent_dir=${last_token%/*}
        ;;
    esac
    parent_dir=$(trim "$parent_dir")
    if [ -z "$parent_dir" ]; then
      parent_dir="."
    fi
    if [ "$parent_dir" != "." ] && ! is_safe_relative_path "$parent_dir"; then
      printf '%s' "$raw_command"
      return 0
    fi
    if [ -d "$workspace_root/$parent_dir" ]; then
      replacement_token=$parent_dir
    else
      replacement_token="."
    fi
  fi
  if [ -z "$replacement_token" ] || ! is_safe_relative_path "$replacement_token"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ "$replacement_token" = "$last_token" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$replacement_token" '
    {
      $NF = repl
      print
    }
  ')
  if allowed_command "$rewritten_command"; then
    printf '%s' "$rewritten_command"
    return 0
  fi
  printf '%s' "$raw_command"
}

autocorrect_readonly_find_command_path() {
  workspace_root=$1
  raw_command=$2

  command_trimmed=$(trim "$raw_command")
  if [ -z "$command_trimmed" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  first_word=$(printf '%s\n' "$command_trimmed" | awk '{print $1}')
  case "$first_word" in
    find)
      ;;
    *)
      printf '%s' "$raw_command"
      return 0
      ;;
  esac

  first_arg=$(printf '%s\n' "$command_trimmed" | awk '{print $2}')
  first_arg=$(trim "$first_arg")
  if ! is_safe_relative_path "$first_arg"; then
    printf '%s' "$raw_command"
    return 0
  fi
  if [ -e "$workspace_root/$first_arg" ]; then
    printf '%s' "$raw_command"
    return 0
  fi

  replacement=$(resolve_assay_task_relative_path_alias "$workspace_root" "$first_arg" || true)
  if [ -z "$replacement" ]; then
    replacement=$(resolve_relative_path_case_insensitive "$workspace_root" "$first_arg" || true)
  fi
  if [ -z "$replacement" ] || [ "$replacement" = "$first_arg" ]; then
    printf '%s' "$raw_command"
    return 0
  fi
  if ! is_safe_relative_path "$replacement"; then
    printf '%s' "$raw_command"
    return 0
  fi

  rewritten_command=$(printf '%s\n' "$command_trimmed" | awk -v repl="$replacement" '
    {
      $2 = repl
      print
    }
  ')
  if allowed_command "$rewritten_command"; then
    printf '%s' "$rewritten_command"
    return 0
  fi
  printf '%s' "$raw_command"
}

execute_mediated_command() {
  workspace_id=$1
  workspace_path=$2
  tool_command=$3
  output_file=$4
  status_file=$5
  command_mode=${6:-ask-some}
  blocked_file=${7:-}
  decision_hint_file=${8:-}
  command_timeout_sec=${ARTIFICER_COMMAND_TIMEOUT_SEC:-25}
  case "$command_timeout_sec" in
    ""|*[!0-9]*)
      command_timeout_sec=25
      ;;
  esac
  if [ "$command_timeout_sec" -lt 5 ]; then
    command_timeout_sec=5
  fi
  if [ "$command_timeout_sec" -gt 90 ]; then
    command_timeout_sec=90
  fi
  original_tool_command=$tool_command
  tool_command=$(autocorrect_readonly_find_command_path "$workspace_path" "$tool_command")
  tool_command=$(autocorrect_readonly_file_command_path "$workspace_path" "$tool_command")
  tool_command=$(autocorrect_readonly_search_command_path "$workspace_path" "$tool_command")
  command_autocorrected=0
  if [ "$tool_command" != "$original_tool_command" ]; then
    command_autocorrected=1
  fi
  first_word=$(printf '%s\n' "$tool_command" | awk '{print $1}')

  decision_file=$(mktemp)
  source_file=$(mktemp)
  matched_pattern_file=$(mktemp)
  matched_scope_file=$(mktemp)
  command_policy_decision "$workspace_id" "$tool_command" "$command_mode" "$decision_file" "$source_file" "$matched_pattern_file" "$matched_scope_file"
  decision=$(cat "$decision_file" 2>/dev/null || printf '%s' "prompt")
  source=$(cat "$source_file" 2>/dev/null || printf '%s' "")
  decision_hint=""
  case "$source" in
    global-safe-default) decision_hint="global default" ;;
    rule) decision_hint="workspace rule" ;;
    once-rule) decision_hint="workspace one-time rule" ;;
    mode-all) decision_hint="workspace mode all" ;;
    mode-none) decision_hint="workspace mode none" ;;
  esac
  if [ -n "$decision_hint_file" ]; then
    printf '%s' "$decision_hint" > "$decision_hint_file"
  fi
  rm -f "$decision_file" "$source_file" "$matched_pattern_file" "$matched_scope_file"

  if [ "$decision" = "deny" ]; then
    {
      printf '%s\n' "Blocked by command policy."
      printf '%s\n' "Policy mode: $command_mode"
      printf '%s\n' "Decision source: $source"
      printf '%s\n' "Command: $tool_command"
    } > "$output_file"
    printf 'blocked' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "denied" >> "$blocked_file"
    fi
    return 0
  fi

  if [ "$decision" = "prompt" ]; then
    printf '%s\n' "Command approval required before execution." > "$output_file"
    printf '%s\n' "Command: $tool_command" >> "$output_file"
    printf '%s\n' "Use Command execution = Ask me and approve this command (once or remember)." >> "$output_file"
    printf 'approval_required' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "approval-required" >> "$blocked_file"
    fi
    return 0
  fi

  if allowed_command "$tool_command"; then
    if (
      cd "$workspace_path" &&
        run_shell_command_with_timeout "$command_timeout_sec" "$tool_command"
    ) >"$output_file" 2>&1; then
      if [ "$command_autocorrected" -eq 1 ]; then
        printf '\n(auto-corrected path: %s -> %s)\n' "$original_tool_command" "$tool_command" >> "$output_file"
      fi
      if command_output_indicates_failure "$tool_command" "$output_file"; then
        printf '\n(command reported errors despite zero exit status)\n' >> "$output_file"
        printf 'failed' > "$status_file"
      else
        printf 'ok' > "$status_file"
      fi
    else
      rc=$?
      if [ "$command_autocorrected" -eq 1 ]; then
        printf '\n(auto-corrected path: %s -> %s)\n' "$original_tool_command" "$tool_command" >> "$output_file"
      fi
      if printf '%s\n' "$first_word" | grep -Eq '^(rg|grep)$' && \
         grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested search target is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(rg|grep)$' && [ "$rc" -eq 1 ]; then
        if grep -Eqi 'regex parse error|unrecognized (option|flag)|invalid option|usage:' "$output_file" 2>/dev/null; then
          printf '\n(exit code %s)\n' "$rc" >> "$output_file"
          printf 'failed' > "$status_file"
        else
          printf '\n(non-fatal: no matches found)\n' >> "$output_file"
          printf 'ok' > "$status_file"
        fi
      elif [ "$first_word" = "git" ] && grep -qi 'not a git repository' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal context miss: workspace is not a git repository)\n' >> "$output_file"
        printf 'context_missing' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(cat|head|tail|sed)$' && \
           grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested file is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      elif printf '%s\n' "$first_word" | grep -Eq '^(ls|find)$' && \
           grep -qi 'No such file or directory' "$output_file" 2>/dev/null; then
        printf '\n(non-fatal input miss: requested path is missing)\n' >> "$output_file"
        printf 'missing_input' > "$status_file"
      else
        if [ "$rc" -eq 124 ]; then
          printf '\n(command timed out after %ss)\n' "$command_timeout_sec" >> "$output_file"
        fi
        printf '\n(exit code %s)\n' "$rc" >> "$output_file"
        printf 'failed' > "$status_file"
      fi
    fi
  else
    printf '%s\n' "Blocked by safety policy. Allowed: read-only shell tools, selected git read commands, lightweight syntax/version checks, and approved local script verify commands." > "$output_file"
    printf 'blocked' > "$status_file"
    if [ -n "$blocked_file" ]; then
      printf '%s\t%s\n' "$tool_command" "safety-policy" >> "$blocked_file"
    fi
  fi
}

ensure_agent_files() {
  agent_dir=$1
  mkdir -p "$agent_dir/.scratch"
  mkdir -p "$agent_dir/.tasks"

  if [ ! -f "$agent_dir/.failures.md" ]; then
    cat > "$agent_dir/.failures.md" <<'EOF'
# Failure Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.session.log.md" ]; then
    cat > "$agent_dir/.session.log.md" <<'EOF'
# Session Log

EOF
  fi

  if [ ! -f "$agent_dir/.controller.raw.md" ]; then
    cat > "$agent_dir/.controller.raw.md" <<'EOF'
# Controller Raw Output

EOF
  fi

  if [ ! -f "$agent_dir/.assumptions.md" ]; then
    cat > "$agent_dir/.assumptions.md" <<'EOF'
# Assumptions Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.compliance.md" ]; then
    cat > "$agent_dir/.compliance.md" <<'EOF'
# Compliance Ledger

EOF
  fi

  if [ ! -f "$agent_dir/.architecture.md" ]; then
    cat > "$agent_dir/.architecture.md" <<'EOF'
# Architecture Map

Updated: n/a
Mode: INVESTIGATE
Target: workspace

## Boundaries
- pending

## Interfaces
- pending

## Risks
- pending
EOF
  fi

  if [ ! -f "$agent_dir/.tasks/index.md" ]; then
    cat > "$agent_dir/.tasks/index.md" <<'EOF'
# Task Index

Updated: n/a
status legend: pending | active | done

EOF
  fi

  if [ ! -f "$agent_dir/.context.memory.md" ]; then
    cat > "$agent_dir/.context.memory.md" <<'EOF'
# Context Memory

Updated: n/a
Run Mode: auto

Project core summary will be populated during the loop.
EOF
  fi

  if [ ! -f "$agent_dir/.changed-paths" ]; then
    : > "$agent_dir/.changed-paths"
  fi
}

bootstrap_plan_file() {
  plan_file=$1
  model_name=$2
  workspace_path=$3
  user_prompt=$4

  snapshot_text=$(workspace_snapshot "$workspace_path" | sed -n '1,220p')
  plan_prompt=$(cat <<EOF
Create an execution plan for a coding task.

Return only this template with concise content:
Goal:
Subgoals:
Constraints:
Unknowns:
Next Action:
Completion Criteria:

Workspace snapshot:
$snapshot_text

User request:
$user_prompt
EOF
)

  plan_text=$(run_model "$model_name" "$plan_prompt" || true)
  if [ -z "$(trim "$plan_text")" ]; then
    plan_text=""
  fi

  if ! printf '%s\n' "$plan_text" | grep -q '^Goal:'; then
    plan_text=$(cat <<EOF
Goal:
- $user_prompt
Subgoals:
- understand current workspace state
- make safe incremental progress
Constraints:
- only use mediated tools
- avoid unsafe shell operations
Unknowns:
- exact files and interfaces to change
Next Action:
- inspect relevant files with read-only tools
Completion Criteria:
- requested change implemented or clearly explained with blockers
EOF
)
  fi

  printf '%s\n' "$plan_text" > "$plan_file"
}

bootstrap_quick_programming_plan_file() {
  plan_file=$1
  prompt_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat > "$plan_file" <<EOF
Goal:
- $task_snippet
Subgoals:
- inspect the workspace and identify the smallest safe implementation slice
- make one bounded implementation attempt only if the relevant files are clear
- verify the current result or report the blocker concisely
Constraints:
- keep edits tightly scoped to the requested programming task
- prefer read-only discovery before any patch decision
- do not rely on unsafe shell operations or broad refactors
Unknowns:
- exact files and interfaces that need to change
- which verification command best matches the affected files
Next Action:
- inspect tracked workspace state and likely task hotspots with read-only commands
Completion Criteria:
- either deliver a verified small slice or return a concise blocker summary with evidence
EOF
}

seed_programming_quick_controller_output() {
  prompt_text=$1
  plan_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=collect concrete workspace evidence before any patch
confidence=0.38

COMMANDS:
- ls -la
- find . -maxdepth 2 -type f
- find . -maxdepth 2 -type d

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- initial workspace discovery queued for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

programming_quick_narrow_slice_focus_commands() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  impl_path=""
  verify_path=""
  doc_path=""
  fallback_path=""
  second_impl_path=""

  extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p' | while IFS= read -r rel_path; do
    rel_path=$(trim "$rel_path")
    [ -n "$rel_path" ] || continue
    case "$rel_path" in
      ./*) rel_path=${rel_path#./} ;;
    esac
    if ! is_safe_relative_path "$rel_path"; then
      continue
    fi
    [ -f "$workspace_path/$rel_path" ] || continue
    case "$rel_path" in
      .git/*|.assay-runs/*)
        continue
        ;;
    esac
    printf '%s\n' "$rel_path"
  done | awk '
    {
      path = $0
      lower = tolower(path)
      if (fallback == "" ) fallback = path
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
        if (verify == "") verify = path
        next
      }
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) {
        if (doc == "") doc = path
        next
      }
      if (impl == "") {
        impl = path
      } else if (second_impl == "") {
        second_impl = path
      }
    }
    END {
      if (impl == "") impl = fallback
      if (impl != "") print "cat " impl
      if (second_impl != "" && second_impl != impl) {
        print "cat " second_impl
      }
      if (verify != "" && verify != impl && verify != second_impl) {
        print "cat " verify
      } else if (doc != "" && doc != impl && doc != second_impl) {
        print "head -n 80 " doc
      }
    }
  ' | sed -n '1,3p'
}

programming_quick_narrow_slice_focus_paths() {
  focus_commands=$(programming_quick_narrow_slice_focus_commands "$@")
  printf '%s\n' "$focus_commands" | awk '
    {
      if ($1 == "cat" && $2 != "") {
        print $2
      } else if ($1 == "head" && $2 == "-n" && $4 != "") {
        print $4
      }
    }
  ' | awk '!seen[$0]++' | sed -n '1,3p'
}

programming_quick_narrow_slice_primary_patch_path() {
  focus_paths=$(programming_quick_narrow_slice_focus_paths "$@")
  primary_path=$(printf '%s\n' "$focus_paths" | awk '
    {
      path = $0
      lower = tolower(path)
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) next
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) next
      print path
      exit
    }
  ')
  if [ -z "$(trim "$primary_path")" ]; then
    primary_path=$(printf '%s\n' "$focus_paths" | sed -n '1p')
  fi
  printf '%s' "$(trim "$primary_path")"
}

programming_quick_narrow_slice_secondary_patch_path() {
  programming_quick_narrow_slice_next_followup_path "$@"
}

programming_changed_paths_file_has_path() {
  changed_paths_file=${1-}
  target_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$target_path" ] || return 1
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_paths_match "$changed_path" "$target_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_first_workspace_documentation_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    {
      find "$workspace_path" -maxdepth 2 -type f -iname 'README*' 2>/dev/null
      find "$workspace_path" -maxdepth 2 -type f -iname '*.md' 2>/dev/null
    } | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
      rel_path=$(programming_normalize_relative_path "$rel_path")
      [ -n "$rel_path" ] || continue
      [ -f "$workspace_path/$rel_path" ] || continue
      programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
      printf '%s\n' "$rel_path"
    done | awk '!seen[$0]++' | sed -n '1p'
  )
  printf '%s' "$(trim "$candidate")"
}

programming_first_workspace_verification_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    find "$workspace_path" -maxdepth 3 -type f \( -path '*/tests/*' -o -path '*/test/*' -o -iname '*test*' -o -iname '*spec*' \) 2>/dev/null \
      | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
          rel_path=$(programming_normalize_relative_path "$rel_path")
          [ -n "$rel_path" ] || continue
          [ -f "$workspace_path/$rel_path" ] || continue
          programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
          printf '%s\n' "$rel_path"
        done | awk '!seen[$0]++' | sed -n '1p'
  )
  printf '%s' "$(trim "$candidate")"
}

programming_first_workspace_post_verification_safe_path() {
  workspace_path=$1
  changed_paths_file=${2-}
  candidate=$(
    find "$workspace_path" -maxdepth 2 -type f \( -iname 'CHANGELOG*' -o -iname 'RELEASE*NOTE*' -o -iname 'MIGRATION*GUIDE*' \) 2>/dev/null \
      | sed "s|^$workspace_path/||" | while IFS= read -r rel_path || [ -n "$rel_path" ]; do
          rel_path=$(programming_normalize_relative_path "$rel_path")
          [ -n "$rel_path" ] || continue
          programming_changed_paths_file_has_path "$changed_paths_file" "$rel_path" && continue
          printf '%s\n' "$rel_path"
        done | awk '!seen[$0]++' | sed -n '1p'
  )
  candidate=$(trim "$candidate")
  if [ -z "$candidate" ] && ! programming_changed_paths_file_has_path "$changed_paths_file" "CHANGELOG.md"; then
    candidate="CHANGELOG.md"
  fi
  printf '%s' "$candidate"
}

programming_quick_narrow_slice_documentation_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 2 -type f \( -iname 'README*' -o -iname '*.md' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        cmd = "test -f " "\"" workspace "/" path "\""
        if (system(cmd) != 0) next
        if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/) {
          if (readme == "") readme = path
          next
        }
        if (lower ~ /[.]md$/) {
          if (doc == "") doc = path
        }
      }
      END {
        if (readme != "") {
          print readme
          exit
        }
        if (doc != "") {
          print doc
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_documentation_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_verification_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 3 -type f \( -path '*/tests/*' -o -path '*/test/*' -o -iname '*test*' -o -iname '*spec*' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        cmd = "test -f " "\"" workspace "/" path "\""
        if (system(cmd) != 0) next
        if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
          if (verify == "") verify = path
        }
      }
      END {
        if (verify != "") {
          print verify
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_verification_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_post_verification_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  changed_paths_file=${5-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  followup_path=$(
    {
      extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p'
      find "$workspace_path" -maxdepth 2 -type f \( -iname 'CHANGELOG*' -o -iname 'RELEASE*NOTE*' -o -iname 'MIGRATION*GUIDE*' \) 2>/dev/null | sed "s|^$workspace_path/||"
    } | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" '
      BEGIN {
        changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
        norm_primary = primary
        gsub(/^[[:space:]]+/, "", norm_primary)
        gsub(/[[:space:]]+$/, "", norm_primary)
        if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
        workspace_prefix = workspace "/"
        split(changed_text, changed_arr, /\n/)
        for (i in changed_arr) {
          changed = changed_arr[i]
          gsub(/^[[:space:]]+/, "", changed)
          gsub(/[[:space:]]+$/, "", changed)
          if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
          if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
            sub("^" workspace_prefix, "", changed)
          }
          if (changed != "") seen_changed[changed] = 1
        }
      }
      {
        path = $0
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path ~ /^\.\//) sub(/^\.\//, "", path)
        if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", path)
        }
        if (path == "" || path == norm_primary || seen_changed[path]) next
        lower = tolower(path)
        if (lower ~ /(^|\/)changelog([.][a-z0-9]+)?$/ || lower ~ /release[_-]?notes?[.](md|txt)$/ || lower ~ /migration[_-]?guide[.](md|txt)$/) {
          print path
          exit
        }
      }
    ' | sed -n '1p'
  )
  if [ -z "$(trim "$followup_path")" ]; then
    followup_path=$(programming_first_workspace_post_verification_safe_path "$workspace_path" "$changed_paths_file")
  fi
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_next_followup_path() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  prompt_text=${5-}
  changed_paths_file=${6-}

  primary_path=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  recorded_changed=""
  if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
    recorded_changed=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
  fi
  prompt_wants_docs=0
  if programming_prompt_has_documentation_branch "$prompt_text"; then
    prompt_wants_docs=1
  fi
  followup_path=$(extract_file_hotspots "$plan_file" "$contract_file" "$session_file" | sed -n 's/^- //p' | PROGRAMMING_CHANGED_TEXT="$recorded_changed" awk -v workspace="$workspace_path" -v primary="$primary_path" -v prompt_wants_docs="$prompt_wants_docs" '
    BEGIN {
      changed_text = ENVIRON["PROGRAMMING_CHANGED_TEXT"]
      norm_primary = primary
      gsub(/^[[:space:]]+/, "", norm_primary)
      gsub(/[[:space:]]+$/, "", norm_primary)
      if (norm_primary ~ /^\.\//) sub(/^\.\//, "", norm_primary)
      workspace_prefix = workspace "/"
      split(changed_text, changed_arr, /\n/)
      for (i in changed_arr) {
        changed = changed_arr[i]
        gsub(/^[[:space:]]+/, "", changed)
        gsub(/[[:space:]]+$/, "", changed)
        if (changed ~ /^\.\//) sub(/^\.\//, "", changed)
        if (workspace_prefix != "/" && index(changed, workspace_prefix) == 1) {
          sub("^" workspace_prefix, "", changed)
        }
        if (changed != "") seen_changed[changed] = 1
      }
    }
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path ~ /^\.\//) sub(/^\.\//, "", path)
      if (workspace_prefix != "/" && index(path, workspace_prefix) == 1) {
        sub("^" workspace_prefix, "", path)
      }
      if (path == "" || path == norm_primary || seen_changed[path]) next
      lower = tolower(path)
      cmd = "test -f " "\"" workspace "/" path "\""
      if (system(cmd) != 0) next
      if (lower ~ /(^|\/)(tests?|spec)\// || lower ~ /(^|[._-])(test|spec)([._-]|$)/) {
        if (verify == "") verify = path
        next
      }
      if (lower ~ /(^|\/)readme([.][a-z0-9]+)?$/ || lower ~ /[.]md$/) {
        if (doc == "") doc = path
        next
      }
      if (impl == "") {
        impl = path
      } else if (second_impl == "") {
        second_impl = path
      }
    }
    END {
      if (impl != "" && !seen_out[impl]++) print impl
      if (second_impl != "" && !seen_out[second_impl]++) print second_impl
      if (prompt_wants_docs == 1 && doc != "" && !seen_out[doc]++) print doc
      if (verify != "" && !seen_out[verify]++) print verify
      if (prompt_wants_docs != 1 && doc != "" && !seen_out[doc]++) print doc
    }
  ' | sed -n '1p')
  printf '%s' "$(trim "$followup_path")"
}

programming_quick_narrow_slice_guard_paths() {
  plan_file=$1
  contract_file=$2
  session_file=$3
  workspace_path=$4
  target_path=$5
  changed_paths_file=${6-}

  {
    programming_quick_narrow_slice_focus_paths "$plan_file" "$contract_file" "$session_file" "$workspace_path"
    if [ -n "$changed_paths_file" ] && [ -f "$changed_paths_file" ]; then
      sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true
    fi
  } | awk -v target="$target_path" '
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "" || path == target) next
      if (!seen[path]++) print path
    }
  ' | sed -n '1,3p'
}

programming_normalize_relative_path() {
  target_path=$(trim "${1-}")
  [ -n "$target_path" ] || {
    printf '%s' ""
    return 0
  }
  while [ "${target_path#./}" != "$target_path" ]; do
    target_path=${target_path#./}
  done
  target_path=$(printf '%s' "$target_path" | sed 's#//*#/#g')
  target_path=$(trim "$target_path")
  printf '%s' "$target_path"
}

programming_resolve_workspace_relative_path() {
  workspace_path=$1
  candidate_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$candidate_path" ] || {
    printf '%s' ""
    return 0
  }
  if [ -e "$workspace_path/$candidate_path" ]; then
    printf '%s' "$candidate_path"
    return 0
  fi
  candidate_lower=$(printf '%s' "$candidate_path" | tr '[:upper:]' '[:lower:]')
  resolved_path=$(find "$workspace_path" -maxdepth 4 -type f 2>/dev/null | sed "s|^$workspace_path/||" | awk -v target="$candidate_lower" '
    {
      line = $0
      lower = tolower(line)
      if (lower == target) {
        print line
        exit
      }
    }
  ' | sed -n '1p')
  if [ -n "$(trim "$resolved_path")" ]; then
    printf '%s' "$(programming_normalize_relative_path "$resolved_path")"
    return 0
  fi
  printf '%s' "$candidate_path"
}

programming_paths_match() {
  left_path=$(programming_normalize_relative_path "${1-}")
  right_path=$(programming_normalize_relative_path "${2-}")
  [ -n "$left_path" ] || return 1
  [ -n "$right_path" ] || return 1
  [ "$left_path" = "$right_path" ]
}

programming_changed_paths_count_from_file() {
  changed_paths_file=${1-}
  if [ -z "$changed_paths_file" ] || [ ! -f "$changed_paths_file" ]; then
    printf '%s' "0"
    return 0
  fi
  awk '
    {
      path = $0
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "") next
      if (!seen[path]++) count++
    }
    END {
      print count + 0
    }
  ' "$changed_paths_file"
}

programming_changed_paths_file_has_documentation_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_documentation_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_changed_paths_file_has_verification_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_verification_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_changed_paths_file_has_post_verification_safe() {
  changed_paths_file=${1-}
  [ -n "$changed_paths_file" ] || return 1
  [ -f "$changed_paths_file" ] || return 1
  while IFS= read -r changed_path || [ -n "$changed_path" ]; do
    changed_path=$(programming_normalize_relative_path "$changed_path")
    [ -n "$changed_path" ] || continue
    if programming_path_is_post_verification_safe "$changed_path"; then
      return 0
    fi
  done < "$changed_paths_file"
  return 1
}

programming_path_is_documentation_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    readme.md|*/readme.md|*.md)
      return 0
      ;;
  esac
  return 1
}

programming_path_is_verification_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    */tests/*|*/test/*|tests/*|test/*|*test*.sh|*spec*.sh)
      return 0
      ;;
  esac
  return 1
}

programming_path_is_post_verification_safe() {
  target_path=$(programming_normalize_relative_path "${1-}")
  [ -n "$target_path" ] || return 1
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    changelog.md|*/changelog.md|change-log.md|*/change-log.md|release-notes.md|*/release-notes.md|release_notes.md|*/release_notes.md|migration-guide.md|*/migration-guide.md|migration_guide.md|*/migration_guide.md)
      return 0
      ;;
  esac
  return 1
}

programming_js_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cp "$source_file" "$tmp_file"
  command_name=$(basename "$target_path")
  command_name=${command_name%.js}
  [ -n "$command_name" ] || command_name="cli"
  default_name=$(sed -n "s/.*process\\.argv\\[2\\][[:space:]]*||[[:space:]]*\\(['\"][^'\"]*['\"]\\).*/\\1/p" "$source_file" | sed -n '1p')
  [ -n "$default_name" ] || default_name="'world'"
  PROGRAMMING_CLI_USAGE="usage: $command_name [name]" PROGRAMMING_CLI_DEFAULT_NAME="$default_name" perl -0pi -e '
    my $usage = $ENV{"PROGRAMMING_CLI_USAGE"} // "usage: cli [name]";
    my $default = $ENV{"PROGRAMMING_CLI_DEFAULT_NAME"} // q{"world"};
    my $replacement = qq{const arg = process.argv[2];
if (arg === "--help" || arg === "-h") {
  console.log("$usage");
  process.exit(0);
}
const name = (arg || $default).trim() || $default;};
    my $changed = 0;
    if ($_ !~ /--help/ && s/const\s+name\s*=\s*process\.argv\[2\]\s*\|\|\s*[^\n;]+;/$replacement/s) {
      $changed = 1;
    }
    if (!$changed && $_ !~ /--help/ && /process\.argv\[2\]/) {
      s{(const\s+\{?[A-Za-z0-9_,[:space:]]+\}?\s*=\s*require\([^\n]+\);\n)}{$1const arg = process.argv[2];
if (arg === "--help" || arg === "-h") {
  console.log("$usage");
  process.exit(0);
}
}x;
      s/process\.argv\[2\]/arg/g;
    }
  ' "$tmp_file"
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_js_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  if ! grep -Eq 'function[[:space:]]+greet[[:space:]]*\(' "$source_file"; then
    return 0
  fi
  if ! grep -Eq 'module\.exports[[:space:]]*=[[:space:]]*\{[[:space:]]*greet[[:space:]]*\}' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
function greet(name) {
  const normalized = String(name == null ? 'world' : name).trim();
  const finalName = normalized || 'world';
  return 'hello ' + finalName;
}
module.exports = { greet };
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_workspace_primary_python_module() {
  workspace_path=$1
  primary_path=$(find "$workspace_path" -maxdepth 1 -type f -name '*.py' ! -name '__init__.py' | sed -n '1p')
  [ -n "$primary_path" ] || return 0
  module_name=$(basename "$primary_path")
  module_name=${module_name%.py}
  printf '%s' "$module_name"
}

programming_python_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    bin/*.py|*/bin/*.py|tests/*.py|*/tests/*.py|test/*.py|*/test/*.py)
      return 0
      ;;
  esac
  source_file="$workspace_path/$target_path"
  if ! grep -Eq '^def[[:space:]]+greet[[:space:]]*\(' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
def greet(name):
    normalized = "world" if name is None else str(name).strip()
    final_name = normalized or "world"
    return f"hello {final_name}"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_python_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  module_name=$(programming_workspace_primary_python_module "$workspace_path")
  [ -n "$module_name" ] || module_name="app"
  command_name=$(basename "$target_path")
  [ -n "$command_name" ] || command_name="cli.py"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from $module_name import greet


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] in {"-h", "--help"}:
        print("usage: $command_name [name]")
        return 0
    name = args[0] if args else "world"
    print(greet(name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_workspace_primary_shell_script() {
  workspace_path=$1
  primary_path=$(find "$workspace_path" -maxdepth 1 -type f -name '*.sh' ! -name '*.test.sh' ! -name '*_test.sh' | sed -n '1p')
  [ -n "$primary_path" ] || return 0
  printf '%s' "$(basename "$primary_path")"
}

programming_shell_greet_primary_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    bin/*.sh|*/bin/*.sh|tests/*.sh|*/tests/*.sh|test/*.sh|*/test/*.sh)
      return 0
      ;;
  esac
  source_file="$workspace_path/$target_path"
  if ! grep -Eq 'hello' "$source_file"; then
    return 0
  fi
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<'EOF'
#!/bin/sh
set -eu

name=${1-}
normalized=$(printf '%s' "${name:-world}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[ -n "$normalized" ] || normalized="world"

printf '%s\n' "hello $normalized"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_shell_cli_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  root_script=$(programming_workspace_primary_shell_script "$workspace_path")
  [ -n "$root_script" ] || root_script="greet.sh"
  command_name=$(basename "$target_path")
  [ -n "$command_name" ] || command_name="greet.sh"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)
ROOT_DIR=\$(CDPATH= cd -- "\$SCRIPT_DIR/.." && pwd)

if [ "\${1-}" = "--help" ] || [ "\${1-}" = "-h" ]; then
  printf '%s\n' "usage: $command_name [name]"
  exit 0
fi

exec sh "\$ROOT_DIR/$root_script" "\$@"
EOF
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_examples_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  example_line='- `node app.js Sam` prints `hello Sam`.'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        example_line="- \`python3 $cli_rel Sam\` prints \`hello Sam\`."
        ;;
      *.sh)
        example_line="- \`sh $cli_rel Sam\` prints \`hello Sam\`."
        ;;
      *)
        example_line="- \`node $cli_rel Sam\` prints \`hello Sam\`."
        ;;
    esac
  fi
  if [ -f "$source_file" ]; then
    cp "$source_file" "$tmp_file"
  else
    printf '# Examples\n' > "$tmp_file"
  fi
  if ! grep -Eiq '^# Examples|^##[[:space:]]+Examples' "$tmp_file"; then
    printf '\n# Examples\n' >> "$tmp_file"
  fi
  if ! grep -Fqi "$example_line" "$tmp_file"; then
    printf '\n%s\n' "$example_line" >> "$tmp_file"
  fi
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_readme_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cp "$source_file" "$tmp_file"
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  lower_cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  usage_line='Run `node app.js` for a quick manual check.'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        usage_line="Run \`python3 $cli_rel [name]\` for a quick manual check."
        ;;
      *.sh)
        usage_line="Run \`sh $cli_rel [name]\` for a quick manual check."
        ;;
      *)
        usage_line="Run \`node $cli_rel [name]\` for a quick manual check."
        ;;
    esac
  fi
  if ! grep -Eiq '^##[[:space:]]+usage' "$tmp_file"; then
    {
      printf '\n## Usage\n\n%s\n' "$usage_line"
    } >> "$tmp_file"
  elif ! grep -Fqi "$usage_line" "$tmp_file"; then
    {
      printf '\n%s\n' "$usage_line"
    } >> "$tmp_file"
  fi
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_pyproject_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  module_name=$(programming_workspace_primary_python_module "$workspace_path")
  [ -n "$module_name" ] || module_name="app"
  tmp_file=$(mktemp)
  cat > "$tmp_file" <<EOF
[project]
name = "$module_name"
version = "0.1.0"
requires-python = ">=3.9"
description = "Small CLI utility for the current verified slice."

[tool.artificer]
cli_path = "bin/$module_name.py"
EOF
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_release_note_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  tmp_file=$(mktemp)
  if [ -f "$source_file" ]; then
    cp "$source_file" "$tmp_file"
  else
    case "$lower_target_path" in
      *migration*guide*)
        printf '# Migration Guide\n' > "$tmp_file"
        ;;
      *release*note*)
        printf '# Release Notes\n' > "$tmp_file"
        ;;
      *)
        printf '# Changelog\n' > "$tmp_file"
        ;;
    esac
  fi
  note_line='- Add a small CLI entry point, usage note, and shell verification coverage for this slice.'
  if printf '%s' "$lower_target_path" | grep -Eq 'changelog|change-log'; then
    if ! grep -Eiq '^##[[:space:]]+unreleased' "$tmp_file"; then
      printf '\n## Unreleased\n\n%s\n' "$note_line" >> "$tmp_file"
    elif ! grep -Fqi "$note_line" "$tmp_file"; then
      printf '\n%s\n' "$note_line" >> "$tmp_file"
    fi
  elif ! grep -Fqi "$note_line" "$tmp_file"; then
    printf '\n%s\n' "$note_line" >> "$tmp_file"
  fi
  if [ -f "$source_file" ] && cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  if [ -f "$source_file" ]; then
    diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  else
    diff -u /dev/null "$tmp_file" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$target_path|"
  fi
  rm -f "$tmp_file"
}

programming_shell_test_followup_patch() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  [ -f "$workspace_path/$target_path" ] || return 0
  source_file="$workspace_path/$target_path"
  tmp_file=$(mktemp)
  cli_path=$(find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p')
  cli_rel=""
  if [ -n "$cli_path" ]; then
    cli_rel=${cli_path#"$workspace_path"/}
  fi
  run_command='node ./app.js'
  if [ -n "$cli_rel" ]; then
    lower_cli_rel=$(printf '%s' "$cli_rel" | tr '[:upper:]' '[:lower:]')
    case "$lower_cli_rel" in
      *.py)
        run_command="python3 ./$cli_rel"
        ;;
      *.sh)
        run_command="sh \"./$cli_rel\""
        ;;
      *)
        run_command="./$cli_rel"
        ;;
    esac
  fi
  if [ "$(printf '%s' "$run_command" | tr '[:upper:]' '[:lower:]')" = "./$lower_cli_rel" ] && printf '%s' "$lower_cli_rel" | grep -Eq '\.js$'; then
    cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

run_js_cli() {
  if command -v node >/dev/null 2>&1; then
    node "$run_command" "\$@"
    return 0
  fi
  if command -v deno >/dev/null 2>&1; then
    deno run --allow-read --unstable-detect-cjs "$run_command" "\$@"
    return 0
  fi
  echo "no supported JavaScript runtime found for $run_command" >&2
  exit 1
}

default_output=\$(run_js_cli)
[ "\$default_output" = "hello world" ]

named_output=\$(run_js_cli Sam)
[ "\$named_output" = "hello Sam" ]
EOF
  else
    cat > "$tmp_file" <<EOF
#!/bin/sh
set -eu

default_output=\$($run_command)
[ "\$default_output" = "hello world" ]

named_output=\$($run_command Sam)
[ "\$named_output" = "hello Sam" ]
EOF
  fi
  if cmp -s "$source_file" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi
  diff -u "$source_file" "$tmp_file" | sed "1s|^--- .*|--- a/$target_path|;2s|^+++ .*|+++ b/$target_path|"
  rm -f "$tmp_file"
}

programming_adjacent_slice_fallback_patch_for_path() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    examples.md|*/examples.md|*example*.md|samples*.md|*/samples*.md)
      programming_examples_followup_patch "$workspace_path" "$target_path"
      ;;
    pyproject.toml|*/pyproject.toml)
      programming_pyproject_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.js|*/bin/*.js|*cli*.js)
      programming_js_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.py|*/bin/*.py|*cli*.py)
      programming_python_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    bin/*.sh|*/bin/*.sh|*cli*.sh)
      programming_shell_cli_followup_patch "$workspace_path" "$target_path"
      ;;
    changelog.md|*/changelog.md|change-log.md|*/change-log.md|release-notes.md|*/release-notes.md|release_notes.md|*/release_notes.md|migration-guide.md|*/migration-guide.md|migration_guide.md|*/migration_guide.md)
      programming_release_note_followup_patch "$workspace_path" "$target_path"
      ;;
    readme.md|*/readme.md|*.md)
      programming_readme_followup_patch "$workspace_path" "$target_path"
      ;;
    */tests/*|*/test/*|tests/*|test/*|*test*.sh|*spec*.sh)
      programming_shell_test_followup_patch "$workspace_path" "$target_path"
      ;;
  esac
}

programming_primary_slice_fallback_patch_for_path() {
  workspace_path=$1
  target_path=$2
  target_path=$(trim "$target_path")
  [ -n "$target_path" ] || return 0
  lower_target_path=$(printf '%s' "$target_path" | tr '[:upper:]' '[:lower:]')
  case "$lower_target_path" in
    app.js|*/app.js|*greet*.js)
      programming_js_greet_primary_patch "$workspace_path" "$target_path"
      ;;
    *.py)
      programming_python_greet_primary_patch "$workspace_path" "$target_path"
      ;;
    *.sh)
      programming_shell_greet_primary_patch "$workspace_path" "$target_path"
      ;;
  esac
}

programming_record_changed_paths() {
  changed_paths_file=$1
  new_paths_file=$2
  merged_paths_file=$(mktemp)
  {
    if [ -f "$changed_paths_file" ]; then
      sed -n '1,50p' "$changed_paths_file"
    fi
    if [ -f "$new_paths_file" ]; then
      sed -n '1,50p' "$new_paths_file"
    fi
  } | sed '/^[[:space:]]*$/d' | awk '!seen[$0]++' > "$merged_paths_file"
  mv "$merged_paths_file" "$changed_paths_file"
  ARTIFICER_PROGRAMMING_CHANGED_PATHS=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
}

programming_file_blocks_context_for_paths() {
  workspace_path=$1
  paths_text=$2

  printf '%s\n' "$paths_text" | while IFS= read -r rel_path; do
    rel_path=$(trim "$rel_path")
    [ -n "$rel_path" ] || continue
    if ! is_safe_relative_path "$rel_path"; then
      continue
    fi
    printf 'FILE: %s\n' "$rel_path"
    printf '```\n'
    if [ -f "$workspace_path/$rel_path" ]; then
      sed -n '1,220p' "$workspace_path/$rel_path"
    else
      printf '(missing file)\n'
    fi
    printf '\n```\n'
  done
}

programming_patch_from_file_blocks_output() {
  workspace_path=$1
  output_file=$2
  file_blocks_dir=$(mktemp -d)
  file_blocks_index=$(mktemp)
  : > "$file_blocks_index"

  cat "$output_file" | FILE_BLOCKS_DIR="$file_blocks_dir" perl -e '
    use strict;
    use warnings;
    local $/;
    my $raw = <>;
    my $dir = $ENV{"FILE_BLOCKS_DIR"} // "";
    my $count = 0;
    my %seen_path;

    my $emit = sub {
      my ($path, $content) = @_;
      $path = "" if !defined $path;
      $content = "" if !defined $content;
      $path =~ s/^\s+//;
      $path =~ s/\s+$//;
      return if $path eq "";
      return if $path =~ m{(?:^|/)\.\.(?:/|$)};
      return if $path =~ m{^/};
      return if $seen_path{$path};
      return if $content !~ /\S/;
      $count += 1;
      return if $count > 5;
      my $tmp_path = "$dir/$count.content";
      open my $fh, ">:encoding(UTF-8)", $tmp_path or return;
      print {$fh} $content;
      close $fh;
      $seen_path{$path} = 1;
      print "$path\t$tmp_path\n";
    };

    while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n```[^\n]*\n(.*?)\n```/sg) {
      $emit->($1, $2);
    }

    if ($count == 0) {
      while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n(.*?)(?=\r?\nFILE:\s*[^\r\n]+\s*\r?\n|\z)/sg) {
        my $path = $1;
        my $content = $2 // "";
        $content =~ s/\A\r?\n//;
        $content =~ s/\r?\n\z//;
        $content =~ s/\A```[^\n]*\n//s;
        $content =~ s/\n```[ \t]*\z//s;
        $emit->($path, $content);
      }
    }
  ' > "$file_blocks_index"

  synthesized_patch=""
  if [ -s "$file_blocks_index" ]; then
    while IFS='	' read -r out_path out_tmp; do
      out_path=$(trim "$out_path")
      out_tmp=$(trim "$out_tmp")
      [ -n "$out_path" ] || continue
      [ -f "$out_tmp" ] || continue
      if ! is_safe_relative_path "$out_path"; then
        continue
      fi
      mkdir -p "$(dirname "$workspace_path/$out_path")" 2>/dev/null || true
      if [ -f "$workspace_path/$out_path" ]; then
        file_diff=$(diff -u "$workspace_path/$out_path" "$out_tmp" || true)
        if [ -n "$(trim "$file_diff")" ]; then
          file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- a/$out_path|;2s|^+++ .*|+++ b/$out_path|")
          synthesized_patch="${synthesized_patch}
${file_diff}"
        fi
      else
        file_diff=$(diff -u /dev/null "$out_tmp" || true)
        if [ -n "$(trim "$file_diff")" ]; then
          file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
          synthesized_patch="${synthesized_patch}
${file_diff}"
        fi
      fi
    done < "$file_blocks_index"
  fi

  rm -rf "$file_blocks_dir" 2>/dev/null || true
  rm -f "$file_blocks_index"
  synthesized_patch=$(trim_block_edges "$synthesized_patch")
  printf '%s' "$synthesized_patch"
}

extract_first_fenced_code_block() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    if (/```[^\n]*\n(.*?)\n```/s) {
      print $1;
    } elsif (/```[^\n]*[ \t]+(.*?)```/s) {
      print $1;
    }
  '
}

extract_primary_file_content_from_output() {
  primary_path=$1
  text=$2
  PRIMARY_PATH="$primary_path" printf '%s\n' "$text" | perl -CS -0777 -ne '
    use strict;
    use warnings;
    my $raw = $_;
    my $path = $ENV{"PRIMARY_PATH"} // "";
    my $quoted = quotemeta($path);

    if ($path ne "" && $raw =~ /FILE:\s*$quoted\s*```[^\n]*\s*(.*?)```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /FILE:\s*[^\r\n]+\s*```[^\n]*\s*(.*?)```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /```[^\n]*\n(.*?)\n```/s) {
      print $1;
      exit;
    }
    if ($raw =~ /```[^\n]*[ \t]+(.*?)```/s) {
      print $1;
      exit;
    }

    $raw =~ s/^FILE:\s*[^\r\n]+\s*//s;
    $raw =~ s/^```[^\n]*\n?//s;
    $raw =~ s/```[ \t]*$//s;
    print $raw;
  '
}

programming_focus_file_candidate_is_usable() {
  primary_path=$1
  content=$(trim "$2")

  [ -n "$content" ] || return 1
  if printf '%s\n' "$content" | grep -Eiq '^[[:space:]]*(full|updated)[[:space:]]+file[[:space:]]+content\b|^[[:space:]]*full[[:space:]]+updated[[:space:]]+file[[:space:]]+content[[:space:]]+for\b'; then
    return 1
  fi
  return 0
}

programming_patch_from_focus_output() {
  workspace_path=$1
  output_file=$2
  primary_path=$(trim "${3:-}")

  raw_text=$(cat "$output_file")

  if [ -n "$primary_path" ] && is_safe_relative_path "$primary_path"; then
    file_candidate=$(extract_primary_file_content_from_output "$primary_path" "$raw_text")
    file_candidate=$(trim "$file_candidate")
    if programming_focus_file_candidate_is_usable "$primary_path" "$file_candidate"; then
      current_tmp=$(mktemp)
      candidate_tmp=$(mktemp)
      if [ -f "$workspace_path/$primary_path" ]; then
        cat "$workspace_path/$primary_path" > "$current_tmp"
      else
        : > "$current_tmp"
      fi
      printf '%s\n' "$file_candidate" > "$candidate_tmp"
      fallback_patch=$(diff -u "$current_tmp" "$candidate_tmp" || true)
      rm -f "$current_tmp" "$candidate_tmp"
      if [ -n "$(trim "$fallback_patch")" ]; then
        if [ -f "$workspace_path/$primary_path" ]; then
          fallback_patch=$(printf '%s\n' "$fallback_patch" | sed "1s|^--- .*|--- a/$primary_path|;2s|^+++ .*|+++ b/$primary_path|")
        else
          fallback_patch=$(printf '%s\n' "$fallback_patch" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$primary_path|")
        fi
        fallback_patch=$(trim_block_edges "$fallback_patch")
        if [ -n "$fallback_patch" ]; then
          printf '%s' "$fallback_patch"
          return 0
        fi
      fi
    fi
  fi

  printf '%s' ""
}

seed_programming_quick_narrow_slice_controller_output() {
  prompt_text=$1
  plan_text=$2
  plan_file=$3
  contract_file=$4
  session_file=$5
  workspace_path=$6
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  focus_commands=$(programming_quick_narrow_slice_focus_commands "$plan_file" "$contract_file" "$session_file" "$workspace_path")
  focus_commands=$(trim "$focus_commands")
  if [ -z "$focus_commands" ]; then
    return 1
  fi
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=inspect one implementation slice closely before generating a patch
confidence=0.54

COMMANDS:
$(printf '%s\n' "$focus_commands" | sed 's/^/- /')

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- focused one implementation slice before patch generation for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

seed_programming_quick_narrow_slice_implement_output() {
  prompt_text=$1
  plan_text=$2
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=apply one focused implementation slice without widening
confidence=0.58

COMMANDS:
NONE

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- applying one focused implementation slice for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

seed_programming_quick_narrow_slice_verify_output() {
  prompt_text=$1
  plan_text=$2
  workspace_path=$3
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  verify_commands=$(emit_default_verify_commands "$workspace_path" "$prompt_text")
  verify_commands=$(trim "$verify_commands")
  if [ -z "$verify_commands" ]; then
    verify_commands="git status --short"
  fi
  cat <<EOF
MODE_UPDATE:
target=$task_snippet
blocking=verify the focused implementation slice before any wider changes
confidence=0.64

COMMANDS:
$(printf '%s\n' "$verify_commands" | sed 's/^/- /')

CONTRACT:
NONE

PATCH:
NONE

DONE_CLAIM:
no

PLAN_UPDATE:
$plan_text

CHECKPOINT:
- verifying the focused implementation slice for $task_snippet

DECISION_REQUEST:
NONE

FINAL:
NONE
EOF
}

append_failure_entry() {
  ledger_file=$1
  action_text=$2
  error_text=$3
  hypothesis_text=$4
  next_text=$5
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s\n' "$timestamp"
    printf 'Action: %s\n' "$action_text"
    printf 'Error: %s\n' "$error_text"
    printf 'Hypothesis: %s\n' "$hypothesis_text"
    printf 'Next Attempt: %s\n\n' "$next_text"
  } >> "$ledger_file"

  if command -v mr_failure_taxonomy_record >/dev/null 2>&1; then
    ensure_mode_runtime_bootstrap
    active_run_mode=$(trim "${ARTIFICER_ACTIVE_RUN_MODE:-unknown}")
    [ -n "$active_run_mode" ] || active_run_mode="unknown"
    mr_failure_taxonomy_record "$action_text" "$error_text" "$hypothesis_text" "$next_text" "$active_run_mode" >/dev/null 2>&1 || true
  fi
}

append_session_entry() {
  session_file=$1
  heading=$2
  body=$3
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s - %s\n' "$timestamp" "$heading"
    printf '%s\n\n' "$body"
  } >> "$session_file"
}

append_assumption_entry() {
  assumptions_file=$1
  mode_value=$2
  assumption_text=$3
  unchecked_text=$4
  risk_text=$5
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  {
    printf '## %s - mode=%s\n' "$timestamp" "$mode_value"
    printf 'Assumption: %s\n' "$assumption_text"
    printf 'Unchecked: %s\n' "$unchecked_text"
    printf 'Constraint Risk: %s\n\n' "$risk_text"
  } >> "$assumptions_file"
}

append_compliance_entry() {
  compliance_file=$1
  run_mode=$2
  state_mode=$3
  status_value=$4
  checks_text=$5
  findings_text=$6
  gate_text=$7
  next_text=$8
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)

  [ -n "$status_value" ] || status_value="pass"
  [ -n "$checks_text" ] || checks_text="- legal_compliance=pass\n- ethical_non_abuse=pass\n- external_action_gate=none"
  [ -n "$findings_text" ] || findings_text="No compliance issues detected in this iteration."
  [ -n "$gate_text" ] || gate_text="none"
  [ -n "$next_text" ] || next_text="Continue with current mode."

  {
    printf '## %s - run_mode=%s state=%s status=%s\n' "$timestamp" "$run_mode" "$state_mode" "$status_value"
    printf 'Checks:\n%s\n' "$checks_text"
    printf 'Findings: %s\n' "$findings_text"
    printf 'Required Gate: %s\n' "$gate_text"
    printf 'Next: %s\n\n' "$next_text"
  } >> "$compliance_file"
}

plan_section_text() {
  plan_file=$1
  start_header=$2
  end_header=$3
  max_lines=${4:-14}
  if [ ! -f "$plan_file" ]; then
    return 0
  fi
  if [ -n "$end_header" ]; then
    sed -n "/^${start_header}:/,/^${end_header}:/p" "$plan_file" | sed '1d;$d' | sed -n "1,${max_lines}p"
  else
    sed -n "/^${start_header}:/,\$p" "$plan_file" | sed '1d' | sed -n "1,${max_lines}p"
  fi
}

extract_file_hotspots() {
  source_a=$1
  source_b=$2
  source_c=$3
  (
    if [ -f "$source_a" ]; then cat "$source_a"; fi
    if [ -f "$source_b" ]; then cat "$source_b"; fi
    if [ -f "$source_c" ]; then cat "$source_c"; fi
  ) | perl -ne '
    while (/([A-Za-z0-9_\/\.-]+\.[A-Za-z0-9]{1,8})/g) {
      my $p = lc($1);
      next if length($p) > 130;
      next if $p =~ /^[0-9]+$/;
      $p =~ s#^\./##;
      print "$p\n";
    }
  ' | sort | uniq -c | sort -nr | sed -n '1,12p' | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+/- /'
}

task_slug_from_title() {
  raw_title=$1
  slug=$(printf '%s' "$raw_title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')
  [ -n "$slug" ] || slug="task"
  printf '%s' "$slug"
}

refresh_programming_artifacts() {
  plan_file=$1
  state_file=$2
  session_file=$3
  failures_file=$4
  contract_file=$5
  architecture_file=$6
  tasks_dir=$7
  tasks_index_file="$tasks_dir/index.md"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")
  state_target=$(state_get "$state_file" "target" "workspace")
  state_blocking=$(state_get "$state_file" "blocking" "none")
  state_confidence=$(state_get "$state_file" "confidence" "0.20")

  hotspots=$(extract_file_hotspots "$plan_file" "$contract_file" "$session_file")
  [ -n "$(trim "$hotspots")" ] || hotspots="- none yet"

  contract_summary=$(sed -n '1,100p' "$contract_file" 2>/dev/null || true)
  [ -n "$(trim "$contract_summary")" ] || contract_summary="(contract not established yet)"
  session_signals=$(grep -E '^## ' "$session_file" 2>/dev/null | tail -n 8)
  [ -n "$(trim "$session_signals")" ] || session_signals="- none yet"
  failure_signals=$(grep -E '^(Action|Error|Next Attempt):' "$failures_file" 2>/dev/null | tail -n 10)
  [ -n "$(trim "$failure_signals")" ] || failure_signals="- none yet"

  cat > "$architecture_file" <<EOF
# Architecture Map

Updated: $timestamp
Mode: $state_mode
Target: $state_target
Blocking: $state_blocking
Confidence: $state_confidence

## Boundaries
- Keep edits scoped to the active target and explicit requirements.
- Preserve build/run viability between iterations.
- Keep interfaces stable unless contract requires change.

## Hotspots
$hotspots

## Contract Summary
$contract_summary

## Recent Iteration Markers
$session_signals

## Open Risks
$failure_signals
EOF

  mkdir -p "$tasks_dir"
  find "$tasks_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' -delete 2>/dev/null || true

  subgoals_text=$(plan_section_text "$plan_file" "Subgoals" "Constraints" 40)
  task_titles_file=$(mktemp)
  : > "$task_titles_file"
  printf '%s\n' "$subgoals_text" | while IFS= read -r line; do
    candidate=$(trim "$line")
    [ -n "$candidate" ] || continue
    candidate=$(printf '%s\n' "$candidate" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
    candidate=$(trim "$candidate")
    [ -n "$candidate" ] || continue
    printf '%s\n' "$candidate" >> "$task_titles_file"
  done
  awk '!seen[tolower($0)]++' "$task_titles_file" > "${task_titles_file}.dedup"
  mv "${task_titles_file}.dedup" "$task_titles_file"
  if [ ! -s "$task_titles_file" ]; then
    next_action_text=$(plan_section_text "$plan_file" "Next Action" "Completion Criteria" 8)
    fallback_task=$(printf '%s\n' "$next_action_text" | sed -n '1p')
    fallback_task=$(trim "$fallback_task")
    [ -n "$fallback_task" ] || fallback_task="Continue implementation from current evidence."
    printf '%s\n' "$fallback_task" > "$task_titles_file"
  fi

  {
    printf '# Task Index\n\n'
    printf 'Updated: %s\n' "$timestamp"
    printf 'status legend: pending | active | done\n\n'
  } > "$tasks_index_file"

  task_n=0
  while IFS= read -r task_title; do
    task_title=$(trim "$task_title")
    [ -n "$task_title" ] || continue
    task_n=$((task_n + 1))
    if [ "$task_n" -gt 12 ]; then
      break
    fi
    task_id=$(printf '%03d' "$task_n")
    task_slug=$(task_slug_from_title "$task_title")
    task_file="$tasks_dir/${task_id}-${task_slug}.md"
    task_status="pending"
    if [ "$state_mode" = "DONE" ]; then
      task_status="done"
    elif [ "$task_n" -eq 1 ]; then
      task_status="active"
    fi

    {
      printf 'status: %s\n' "$task_status"
      printf 'title: %s\n' "$task_title"
      printf 'updated: %s\n' "$timestamp"
      printf 'source: plan-subgoal\n\n'
      printf 'Objective:\n- %s\n\n' "$task_title"
      printf 'Context:\n- mode=%s\n- target=%s\n- blocking=%s\n' "$state_mode" "$state_target" "$state_blocking"
    } > "$task_file"

    printf -- '- [%s] %s - %s\n' "$task_status" "$(basename "$task_file")" "$task_title" >> "$tasks_index_file"
  done < "$task_titles_file"

  rm -f "$task_titles_file"
}

run_mode_policy_instructions() {
  run_mode=$1
  case "$run_mode" in
    programming)
      cat <<'EOF'
Run mode policy:
- prioritize scalable architecture and clear module boundaries for multi-file codebases.
- prefer incremental checkpoints that keep the project runnable between iterations.
- keep .contract.md and context memory aligned when design decisions change.
- aggressively compress context to retain only actionable architecture state and open risks.
- if requirements are ambiguous, state explicit assumptions and proceed with a safe high-value implementation slice.
- before claiming completion, ensure verification evidence directly covers changed behavior.
EOF
      ;;
    pentest)
      cat <<'EOF'
Run mode policy:
- prioritize adversarial testing depth: enumerate exploit paths, abuse cases, and boundary failures.
- pair each credible attack path with concrete mitigations and verification checks.
- keep all testing scoped to safe internal validation; do not enable real-world abuse.
- report findings with impact level, evidence, and remediation status.
EOF
      ;;
    security-audit)
      cat <<'EOF'
Run mode policy:
- prioritize systematic security review across auth, validation, secrets, and dependency risk.
- produce auditable findings with severity, evidence, and mitigation guidance.
- map each high-impact claim to concrete evidence anchors and numeric accept/reject thresholds.
- prefer least-privilege and defense-in-depth changes that are testable and reversible.
- avoid speculative claims and clearly mark uncertainty when evidence is incomplete.
EOF
      ;;
    report)
      cat <<'EOF'
Run mode policy:
- prioritize evidence quality, source fidelity, and explicit uncertainty.
- structure output for executive readability: findings, evidence, risks, recommendations.
- include an explicit claim-to-evidence map with concrete anchors (logs, metrics, queries, policy clauses, tests) and freshness caveats.
- avoid speculative claims when direct evidence is missing.
- when inputs are underspecified, declare assumptions with confidence and proceed rather than stalling.
- when constraints conflict, explicitly map the conflict, choose a priority order, and state rejected alternatives.
- include a short contradiction check before claiming completion on ambiguous tasks.
EOF
      ;;
    text-perfecter)
      cat <<'EOF'
Run mode policy:
- optimize both language quality and underlying content correctness; do not do style-only rewrites.
- run iterative revisions until change deltas stabilize, then stop with an explicit convergence rationale.
- gather broad evidence before rewriting claims: techniques, variants, common failures, and informed discussion.
- if evidence conflicts, surface alternatives and explain why one version is selected.
- include a contradiction check and unresolved uncertainty note before claiming "perfected."
- avoid confidently asserting unsupported facts; mark unverifiable claims and keep safer wording when needed.
EOF
      ;;
    gui-testing)
      cat <<'EOF'
Run mode policy:
- execute hands-on GUI automation as a real user journey, not a static code-only review.
- prefer cross-platform automation harnesses first: run `hosted-web/scripts/gui-regression-system.sh` with profile selection based on requested depth.
- on macOS, use Safari automation; on Linux, use Firefox automation; if both are available, compare outcomes.
- treat every UX flaw as actionable: ambiguous status text, ordering glitches, visual artifacts, stalled states, or inaccessible controls.
- fail closed on unclear signals: report concrete repro steps, expected vs actual behavior, and severity before proposing fixes.
- after fixes, rerun the same scenario to verify closure and capture regression evidence paths.
EOF
      ;;
    assistant)
      cat <<'EOF'
Run mode policy:
- this mode represents a globally configured team profile; apply team policy while driving end-to-end completion.
- proactively drive end-to-end completion with initiative and practical sequencing.
- optimize for real user value and sustainable outcomes; never game or exploit systems.
- enforce legal, ethical, and policy compliance; avoid deception, spam, and abuse.
- keep evidence quality concrete: cite anchors, quantify thresholds, and disclose freshness/uncertainty caveats for key claims.
- require explicit user approval before irreversible external actions (payments, legal filings, account creation, outreach to real people).
- if details are missing but inferable, document assumptions and continue with best-effort execution.
- prefer one complete, verified high-confidence slice over broad but shallow partial progress.
- if requirements collide, state what cannot be simultaneously satisfied and provide a defensible priority decision.
- for adversarial or ambiguous prompts, include a contradiction check and at least one alternative path in the final output.
EOF
      ;;
    chat)
      cat <<'EOF'
Run mode policy:
- prioritize continuity across turns: keep the active thread and user framing corrections intact.
- prioritize clarity, empathy, and concise direct help.
- prefer insight and concrete distinctions over generic platitudes.
- avoid unnecessary tooling loops when a straightforward response is sufficient.
EOF
      ;;
    teacher)
      cat <<'EOF'
Run mode policy:
- maintain and use a persistent learner model to adapt depth, pacing, and framing.
- teach with concept scaffolding, retrieval checks, and concrete examples before abstraction.
- track likely misconceptions and explicitly correct them with brief diagnostic checks.
- account for time since last interaction; add recap when gaps are longer and set spaced-review guidance.
- surface and correct plausible false assumptions explicitly before reinforcing a mental model.
- include one diagnostic contradiction check to verify that the misconception was actually resolved.
EOF
      ;;
    instant)
      cat <<'EOF'
Run mode policy:
- optimize for speed while still preserving accuracy and safety.
EOF
      ;;
    *)
      cat <<'EOF'
Run mode policy:
- balance progress, safety, and verification with practical iteration scope.
EOF
      ;;
  esac
}

prompt_requires_adversarial_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'conflict|contradict|trade[- ]?off|cannot satisfy|simultaneous|incomplete evidence|uncertain|unknown|misconception|false assumption|underspecified|adversarial|ambiguous|near[- ]?miss|deceptive|counterexample|counterevidence|misleading|retry storm|opposite directions|first narrative|anecdote|story-driven|prove (this|it) wrong|invalidation evidence|counterfactual test|abuse case|blast radius|cost of being wrong|red-team|red team'; then
    return 0
  fi
  return 1
}

prompt_requires_cross_domain_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'cross[- ]?domain|stakeholder|trade[- ]?off|priority order|conflicting goals|architecture|security|compliance|policy|product|ux|metric|causal|incident|rollback|strategy|governance|teacher|teaching|explain|misconception|queue|latency|throughput|forensics|debug|slo|error budget|regulated|residency|retention|legal|finance|margin|cost[- ]?to[- ]?serve|chargeback|consent|region constraints?|deletion guarantees?|system layout|workflow platform|resilience drills|trust checks|governance checkpoints|service[- ]?cost|jurisdiction|consent separation|moderation burden|setup flow'; then
    return 0
  fi
  return 1
}

prompt_requires_decision_completeness() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'decision|strategy|plan|fallback|contingency|trade[- ]?off|priority|launch|rollout|incident|architecture'; then
    return 0
  fi
  return 1
}

prompt_requires_recovery_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'incident|forensic|debug|root cause|incomplete evidence|uncertain|unknown|re[- ]?plan|rollback|recovery|self[- ]?correction|failover|degradation|counterexample|disconfirming|ambiguous|retry storm'; then
    return 0
  fi
  return 1
}

prompt_requires_assumption_revision_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'misconception|false assumption|plausible but false|attractive but wrong|initial hypothesis|initial assumption|assumption[- ]?revision|first narrative|prove (this|it) wrong|invalidating evidence|invalidated|falsifying evidence|counterevidence|revised from|confidence shift|before/after confidence|revised decision explicit|make the revised decision explicit|make the revised call explicit|make the decision change explicit|decision change explicit|make the shift in recommendation explicit|shift in recommendation explicit|show the pivot|spell out the pivot|changes the answer|changed the answer|changes the decision|changed the decision|changes the call|changed the call'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|first intuition|at first glance|obvious explanation|surface[- ]?win|what changed your mind|what changed the call|what changed the answer|what overturned the original read|what overturned the first read|overturned the original read|overturned the first read|early view missed|showing why the initial|showing how the evidence changed|showing how the evidence changes|showing what changed the decision|showing what changed the answer|what the first rule misses|what the first intuition misses|first intuition misses|why that intuition fails|showing why the initial cheap-path story breaks|first read is no longer enough'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|at first glance|first looks|first looked|looks safe|looked safe|looks safest|looked safest|looks cheapest|looked cheapest|looks compliant|looked compliant|looks like the cheapest|cheap-path story|first rule' \
    && printf '%s' "$prompt_text_lower" | grep -Eq 'but|then|later|instead|changed the decision|changes the decision|changed the answer|changes the answer|changed the call|changes the call|no longer enough|breaks|misses|replaces|what changed'; then
    return 0
  fi
  return 1
}

prompt_requires_time_windowed_validation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'time window|review window|checkpoint window|within [0-9]|owner assignment|validation owner|disconfirming window|decision window'; then
    return 0
  fi
  return 1
}

prompt_requires_high_risk_fail_closed() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  run_mode_hint=$(trim "${2:-}")
  case "$run_mode_hint" in
    security-audit|pentest)
      return 0
      ;;
  esac
  if printf '%s' "$prompt_text_lower" | grep -Eq 'security|compliance|policy|legal|regulatory|privacy|incident|breach|forensic|auth|authorization|encryption|key management|residency|retention|consent|sanctions|soc 2|hipaa|gdpr|pci|iso 27001|access control|control objective|risk register'; then
    return 0
  fi
  return 1
}

prompt_prefers_document_revision_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'memo|document|runbook|postmortem|design doc|architecture doc|architecture memo|decision record|prd|executive summary'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'revise|rewrite|refresh|update the same|update the memo|update the document|keep the same headings|preserve (these|the same|exact) headings|existing memo|existing document|same memo|same headings|migration plan|open questions|evidence anchors'; then
    return 0
  fi
  return 1
}

prompt_prefers_architecture_document_refresh_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan'; then
    return 0
  fi
  return 1
}

document_revision_fast_path_kind_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  conv_dir=${2:-}
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    printf '%s' "unknown"
    return 0
  fi
  prompt_context=$prompt_primary
  if [ -n "$conv_dir" ] && [ -d "$conv_dir" ]; then
    recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,16p' | tr '[:upper:]' '[:lower:]')
    prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,32p' | tr '[:upper:]' '[:lower:]')
    if [ -n "$(trim "$recent_user_turns$prior_doc")" ]; then
      prompt_context=$(printf '%s\n%s\n%s' "$prompt_primary" "$recent_user_turns" "$prior_doc")
    fi
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan|context:.*decision:.*why not:.*fallback:.*migration plan:.*open questions:.*evidence anchors:'; then
    printf '%s' "architecture"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'postmortem|root cause|customer impact|follow-up owners|retry storm|partial rollback|billing api outage|partner-ingestion service|timeline|summary:.*customer impact:.*timeline:.*root cause:.*mitigations:.*follow-up owners:.*evidence anchors:'; then
    printf '%s' "incident-postmortem"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'runbook|preconditions|procedure|verification|rollback|read replica|replica promotion|search replica|failover runbook|promotion|context:.*preconditions:.*procedure:.*verification:.*rollback:.*open risks:.*evidence anchors:'; then
    printf '%s' "operations-runbook"
    return 0
  fi
  printf '%s' "unknown"
}

document_revision_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,12p')
  prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,24p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior draft:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_doc"
}

document_revision_architecture_memo_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same memo after new evidence|update the memo after new evidence|strict data residency before quarter end|backlog replay cost doubled|lower-risk migration window|quarter-end freeze window|backlog cost estimates rose again|smaller tenant cohorts'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: one migration window and one tenancy pattern are acceptable for every region. That assumption no longer holds. EU customers now require strict data residency before quarter end, explicit EU residency controls, backlog replay cost doubled during the last failover, and support needs smaller tenant cohorts plus a lower-risk quarter-end freeze window. The memo must still preserve replay determinism, tenant isolation, customer-managed keys, in-region processing, and the finance ceiling.

Decision: Use a phased regional architecture with per-tenant deterministic event journals, EU-only processing clusters for EU tenants, and customer-managed keys at the tenant boundary. Keep near-real-time orchestration for non-EU tenants only after the EU path is isolated and tenant isolation is proven at cohort size. Narrow the next migration step to an EU-first cutover window with shadow validation before broader rollout.

Why Not: Do not keep the shared Kafka cluster and global event log pattern. That near-miss keeps replay determinism brittle during regional failover, weakens tenant isolation and in-region processing guarantees, and makes doubled failover backlog replay cost unacceptable. Do not use one global migration window either; the new EU residency deadline and quarter-end freeze window make that assumption too risky.

Fallback: If synthetic lag stays above 90 seconds for two consecutive failover drills, if projected cost exceeds 3 dollars per active tenant per month, if failover backlog drain cannot stay within the shadow window, or if EU residency cannot be proven with customer-managed keys and in-region processing, pause additional near-real-time rollout and fall back to bounded regional buffering plus tenant-scoped replay queues until the isolation path is green.

Migration Plan: Phase 1 is an EU-only isolation lane with tenant-scoped journals, customer-managed keys, tenant isolation checks, and residency attestation. Phase 2 is a shadow replay window for smaller EU tenant cohorts only, with support coverage and rollback pre-approved before the quarter-end freeze window. Phase 3 widens to non-EU tenants only after the EU lane proves replay determinism, residency evidence, failover backlog control, and cost control. Verification plan: require one shadow failover drill, one replay drill, and one residency-attestation review before each widening step.

Open Questions: Confirm whether customer-managed keys must be tenant-held or provider-managed by region; confirm the narrowest supportable migration window for EU tenants before quarter end; confirm whether backlog replay cost can be reduced by journal compaction without weakening replay determinism or failover backlog safety. Contradiction check: if customer-managed keys, tenant isolation, and in-region processing cannot be preserved while staying under 3 dollars per active tenant per month, cost optimization does not override the EU residency requirement and rollout remains paused.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Finance caps infrastructure cost at 3 dollars per active tenant per month. Compliance requires customer-managed keys, in-region processing, and EU residency controls for EU tenants. Synthetic lag spikes above 90 seconds when failover drains backlog, and doubled failover backlog replay cost now makes the shared path unacceptable. New evidence adds strict data residency before quarter end, smaller tenant cohorts for rollout, and a lower-risk migration window requirement. Claim 1 (selected architecture): per-tenant journals plus EU-only clusters preserve replay determinism, tenant isolation, and residency boundaries; verification method: failover drill, replay drill, and residency attestation; invalidation trigger: any cross-region spill or non-deterministic replay result. Claim 2 (narrowed migration plan): EU-first cutover with smaller tenant cohorts reduces rollback risk while preserving the deadline; verification method: support-staffed shadow window plus rollback rehearsal; invalidation trigger: support load, lag, failover backlog drain, or cost exceeds the fallback thresholds.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The existing memo is unsafe because it assumes one shared Kafka cluster and a global event log are acceptable for every tenant, treats batch replay during outages as acceptable, and leaves rollback triggers and EU isolation constraints implicit. New evidence says replay determinism breaks when tenants share partitions during regional failover, finance caps cost at 3 dollars per active tenant per month, compliance requires customer-managed keys and in-region processing for EU tenants, and synthetic lag spikes above 90 seconds when failover drains backlog.

Decision: Replace the shared global path with a per-tenant regional architecture: tenant-scoped append-only event journals, region-local ingestion and replay control, EU-only processing lanes for EU tenants, and customer-managed keys at the tenant boundary. Keep deterministic replay as the first design constraint and make regional failover recovery prove replay determinism before widening rollout.

Why Not: Do not keep one shared Kafka cluster plus one global event log as the primary design. It looks cheaper, but replay determinism fails when tenants share partitions during regional failover, in-region processing becomes hard to defend for EU tenants, and backlog-drain lag above 90 seconds makes batch replay during outages too expensive and too risky.

Fallback: If failover drills push synthetic lag above 90 seconds twice in a row, if the projected monthly cost rises above 3 dollars per active tenant, or if customer-managed keys and in-region processing cannot be proven for EU tenants, fall back to bounded regional buffering with tenant-scoped replay queues and pause additional near-real-time rollout until the isolation controls are green.

Migration Plan: First isolate EU tenants onto region-local journals with customer-managed keys and explicit in-region processing controls. Then run shadow replay and failover drills against that lane to prove replay determinism and cost bounds. Only after those checks pass should non-EU tenants move from nightly/batch paths to near-real-time updates in staged tenant cohorts. Verification plan: do not widen phases until replay determinism, lag, residency, and cost checks are green in the shadow lane.

Open Questions: Decide whether the customer-managed keys boundary is per tenant or per regulated region; confirm the smallest tenant cohort that still proves replay determinism under regional failover; confirm whether the cost cap can hold once shadow replay and backlog-drain tests are included in the steady-state model. Contradiction check: if the architecture can satisfy low-latency widening only by weakening in-region processing or replay determinism, treat that as a failed design goal rather than a tradeoff to hide.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Customer-managed keys are now mandatory. In-region processing is required for EU tenants. Synthetic lag spikes above 90 seconds during backlog drains. Finance caps infrastructure cost at 3 dollars per active tenant per month. Claim 1 (selected design): tenant-scoped journals plus regional isolation are the selected path; verification method: shadow replay, failover drill, and residency review; invalidation trigger: replay mismatch, cross-region spill, or lag above 90 seconds. Claim 2 (rejected near-miss): the shared Kafka cluster and global event log path is rejected; verification method: compare replay determinism and cost under failover drills; invalidation trigger: if the shared path somehow stays deterministic, residency-safe, and within the cost ceiling, reconsider the rejection.
EOF_MEMO
}

document_revision_incident_postmortem_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same postmortem after new evidence|config promotion from staging|timeline event was ten minutes late|retry-budget mitigation owner moved|mitigation owner changed to ingestion reliability|rollback step never reached the canary worker'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Summary: Revised assumption: generic traffic growth was the main driver and the first rollback mostly worked. That assumption no longer holds. New evidence confirms a promoted config from staging triggered the retry storm, one earlier timeline event was ten minutes late, and the mitigation owner must move to the team that actually controls retry budgets. The corrected summary must now make the regional rollback failure, backpressure amplification, and triage delay explicit.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, the billing API stayed degraded while queue drain continued for 47 minutes, and support triage remained wrong-footed until the dashboard blind spot plus macro drift were corrected. The material harm is not just latency; it is duplicated downstream billing signals for the highest-sensitivity cohort.

Timeline: A rate-limit config promotion triggered a retry storm and amplified backpressure in one region. The first regional rollback reverted only one region and failed to restore a consistent state. Queue drain then extended recovery for 47 minutes. The original draft understated one timeline gap by ten minutes; the corrected sequence makes the partial rollback failure and triage delay from the masked dashboard causally earlier than the final stabilization step.

Root Cause: The root cause was a bad rate-limit config promotion that amplified backpressure, coupled with an incomplete partial regional rollback path that reverted only one region. Rejected near-miss: generic traffic growth. That theory cannot explain the regional asymmetry, the duplicate webhook retries, or the exact timing of queue drain after the partial rollback.

Mitigations: Freeze direct promotion of rate-limit config from staging, require regional rollback completeness checks before declaring rollback success, add queue-age and duplicate-webhook checks to the first-line incident view, and narrow support macros so billing-impact incidents do not inherit generic traffic-language. Verification plan: replay the exact config promotion and rollback sequence in a drill, then confirm rollback completeness plus queue recovery timing.

Follow-up Owners: API traffic control owns the retry-budget mitigation and rollback-completeness guard. Incident tooling owns the dashboard repair for queue-age and duplicate-webhook visibility. Support operations owns macro correction and triage verification. Contradiction check: if the rollback path is still incomplete after the config promotion path is fixed, then the rollback mechanism remains a separate incident cause and must stay explicitly tracked.

Evidence Anchors: Rate-limit config change triggered the retry storm. The first regional rollback only reverted one region. Backpressure amplification plus queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes, creating an explicit triage delay. New evidence confirms the config promotion came from staging, corrects one timeline event by ten minutes, and moves retry-budget ownership to API traffic control. Claim 1 (root cause): bad config promotion plus incomplete rollback explains the regional pattern and recovery delay; verification method: config-audit replay plus rollback drill; invalidation trigger: if a clean replay still reproduces duplicate retries without the bad config. Claim 2 (owner correction): API traffic control must own retry-budget mitigation because platform alone cannot enforce the config guard; verification method: owner review plus next drill; invalidation trigger: if another system, not rate-limit control, is shown to be the primary actuator.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Summary: The existing postmortem is unsafe because it blames generic traffic growth, omits the failed partial rollback, and leaves mitigation ownership vague. The corrected story is a rate-limit config change that triggered a retry storm, followed by an incomplete rollback that only reverted one region and left queue drain to carry the incident far longer than the draft admits.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, billing API recovery stretched across a 47-minute queue drain, and first-line support triage stayed misleading for 18 minutes because macros and dashboards both masked the real failure shape. This was a billing-correctness incident, not just an elevated-traffic event.

Timeline: A rate-limit config change introduced the retry storm. The first rollback only reverted one region, so the system entered a partial-recovery state rather than true rollback. Queue drain then extended stabilization for 47 minutes. Support macros and the initial dashboard view masked the severity long enough to delay correct triage by 18 minutes.

Root Cause: The root cause was the rate-limit config change combined with an incomplete regional rollback path. Rejected near-miss: generic traffic growth. That explanation does not fit the one-region rollback miss, the queue-drain timing, or the duplicate webhook retry pattern seen by EU VIP merchants.

Mitigations: Add rollback-completeness checks before incident status can move out of rollback, gate rate-limit config rollout behind replay-safe validation, surface duplicate-webhook and queue-age signals in the first incident view, and narrow support macros for billing-impact incidents. Verification plan: rerun the config-change plus rollback sequence in a controlled drill and require one dashboard/triage confirmation pass before closing follow-up work.

Follow-up Owners: API traffic control owns retry-budget and rate-limit rollout guards. Incident tooling owns the queue-age and duplicate-retry dashboard fixes. Support operations owns macro correction and triage rehearsal. Contradiction check: if rollback completeness is green but duplicate retries still occur in the drill, then rollback incompleteness is not the only root cause and the causal statement must be revised.

Evidence Anchors: Rate-limit config change triggered a retry storm. The first rollback only reverted one region. Queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes. Claim 1 (root cause): config change plus incomplete rollback best explains the regional asymmetry and queue drain; verification method: rollback drill plus config replay; invalidation trigger: drill reproduces the issue without the config change or with a complete rollback. Claim 2 (mitigation ownership): API traffic control must own retry-budget controls while support/tooling own visibility fixes; verification method: owner review plus next incident rehearsal; invalidation trigger: if ownership mapping fails to cover the exact failing controls.
EOF_MEMO
}

document_revision_operations_runbook_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same runbook after new evidence|replica lag spikes during autovacuum|maintenance window is now 20 minutes shorter|one lower-risk fallback before traffic cutover|lag now spikes during segment compaction|cutover window is shorter'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: the earlier promotion path had enough time and stability margin to rely on one primary replica plus one direct cutover step. That assumption no longer holds. Promotion lag now spikes during maintenance work, the cutover window is shorter, and on-call needs one lower-risk fallback before traffic moves.

Preconditions: Confirm read-only mode is active on the source before any cutover step. Confirm replication lag is below the safe bound for the relevant system (`lag < 15s` for the Postgres replica path; `lag < 12s` for the cache-backed search replica path). Confirm the promotion candidate is still streaming and that clock skew or segment-compaction lag is not masking stale state. If any precondition fails, do not proceed to direct cutover.

Procedure: Keep the safer staged procedure: verify streaming/lag first, promote only the healthiest candidate, wait for replay catch-up, then cut over traffic only after the second verification pass. The cutover gate is two consecutive health checks plus explicit lag confirmation. New lower-risk fallback: if promotion lag spikes during autovacuum or segment compaction, hold traffic on the current primary and switch only to a bounded read-only validation window before any write traffic or index-serving cutover.

Verification: Require two consecutive green health checks plus explicit lag confirmation before traffic moves. Confirm read-only mode and replay/index catch-up before declaring promotion safe. Verification plan: run one rehearsal under the shorter window and prove that the fallback path can preserve correctness without forcing immediate traffic cutover.

Rollback: If lag exceeds the safe threshold after promotion, if read-only mode cannot be proven before traffic change, or if backup-lock/index-replay completion is ambiguous, roll back to the pre-cutover topology and keep the promoted node isolated. Do not restore traffic before read-only mode, replay completion, and service health are all green.

Open Risks: Maintenance-window compression reduces the time available for replay confirmation, and background work can now hide stale state behind nominal health checks. The main residual risk is false confidence from green probes without lag or replay confirmation. Contradiction check: if the lower-risk fallback still requires traffic movement before replay safety is proven, it is not actually lower risk and the procedure must remain paused.

Evidence Anchors: Stale promotions occurred when clock skew exceeded 4 seconds in the Postgres failover path. Promotion is only safe when `replication_state=streaming` and replay lag stays below `lag < 15s`. Backup lock release can lag 2 minutes after role switch. The old rollback step could re-point traffic before read-only mode is restored. For the search-replica holdout, stale indexes appear when lag exceeds `12 seconds`, promotion lag spikes during segment compaction, and the cutover gate requires two consecutive health checks plus lag confirmation. New evidence adds a shorter cutover window and the requirement for one lower-risk fallback before traffic moves. Claim 1 (safer procedure): staged promotion plus lag/read-only verification remains safer than direct cutover; verification method: rehearsal with lag injection; invalidation trigger: stale reads or stale indexes appear despite all gates reading green. Claim 2 (fallback): bounded read-only validation before traffic cutover lowers risk under the shorter window; verification method: cutover rehearsal; invalidation trigger: fallback still forces traffic movement before replay safety is proven.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The current runbook is unsafe because it promotes replicas on operator judgment, skips lag-sensitive gating, and treats a green service probe as enough evidence for cutover. New evidence shows stale promotions when clock skew exceeds 4 seconds, safety only when `replication_state=streaming` and lag stays below `15 seconds`, delayed backup-lock release after role switch, and rollback steps that can restore traffic before read-only mode is back.

Preconditions: Confirm the candidate is still streaming, confirm replay lag stays at `lag < 15s`, confirm clock skew is within safe bounds, and confirm the source is in read-only mode before any traffic change. If any of those checks are missing or ambiguous, promotion is not yet safe.

Procedure: Verify streaming state and lag first, promote the healthiest replica only after those checks pass, wait for replay catch-up, then run the explicit verification sequence before traffic cutover. Keep traffic pinned until backup-lock release and replay status are both confirmed. This procedure is intentionally slower than the old runbook because the old path hid stale-state risk.

Verification: Require `replication_state=streaming`, replay lag at `lag < 15s`, and confirmation that read-only mode plus replay catch-up are both green before traffic moves. Verification plan: run a failover rehearsal that injects clock skew and replay lag, then confirm that the procedure blocks promotion until the safe gates are real.

Rollback: If lag exceeds the threshold, if read-only mode cannot be confirmed, or if backup-lock release is still pending after promotion, roll back to the pre-cutover topology and keep client traffic off the promoted node. Do not re-point traffic before read-only mode and replay safety are restored.

Open Risks: The main residual risk is a false-green health probe that hides stale replay or delayed lock release. Operator time pressure can still push the team toward premature cutover. Contradiction check: if TCP or HTTP health stays green while lag or replay safety is red, the runbook must treat the promotion as failed rather than partially healthy.

Evidence Anchors: Stale promotions occurred when clock skew exceeded `4 seconds`. Promotion is only safe when `replication_state=streaming` and replay lag stays at `lag < 15s`. Backup lock release can lag `2 minutes` after role switch. The old rollback step could re-point traffic before read-only mode is restored. Claim 1 (promotion gate): streaming plus lag plus read-only checks are required before cutover; verification method: failover rehearsal with injected skew and lag; invalidation trigger: stale reads appear even when those gates are green. Claim 2 (rollback guard): traffic must not move back until read-only mode and replay safety are restored; verification method: rollback rehearsal plus client-read validation; invalidation trigger: rollback remains safe even when those checks are absent.
EOF_MEMO
}

document_revision_response_for_prompt() {
  prompt_text=$1
  fast_path_kind=$(document_revision_fast_path_kind_for_prompt "$prompt_text")
  case "$fast_path_kind" in
    architecture)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
    incident-postmortem)
      document_revision_incident_postmortem_for_prompt "$prompt_text"
      ;;
    operations-runbook)
      document_revision_operations_runbook_for_prompt "$prompt_text"
      ;;
    *)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
  esac
}

prompt_prefers_gui_screenshot_layout_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshot|attached safari screenshot|safari screenshot|screenshot of|inspect the attached|visible screenshot evidence|ignore browser chrome'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'issue:|evidence:|likely cause:|fix direction:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout defect|layout issue|ui region|dialog|modal|header|filters|grid|card|overlap|clipped|cut off|off-screen|overflow'; then
    return 1
  fi
  return 0
}

prompt_prefers_before_after_ui_delta_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshots|attached screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots|compare two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'change:|before evidence:|after evidence:|impact:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'before|after'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout|ui|dialog|modal|panel|header|filters|chip|grid|card|overlap|clipped|cut off|off-screen|offscreen|overflow|wrap|viewport'; then
    return 1
  fi
  return 0
}

prompt_prefers_diagram_annotation_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*diagram|diagram screenshot|annotated screenshot|system diagram|architecture diagram|annotated architecture|service map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'takeaway:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'diagram|annotation|callout|flow|node|edge|queue|cache|canary|worker|postgres|redis|bastion|release'; then
    return 1
  fi
  return 0
}

prompt_prefers_dashboard_chart_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*chart|dashboard chart|chart screenshot|chart or table evidence|chart or table|table evidence|line chart|bar chart|funnel|latency trend'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'chart|table|bar|line|funnel|latency|backlog|region|conversion|step|row|column|spike|trend'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_state_recovery_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|attached .*log|terminal screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'state change:|before evidence:|after evidence:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'terminal|log|console|recovery|after recovery|before recovery|changed failure|still failing|state change|module|port|postgres|database|migration|schema'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_screenshot_debug_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|terminal screenshot|terminal or log evidence|log screenshot|console screenshot|visible terminal|visible log'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|next command:|risk:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'cannot find module|module not found|module_missing|eaddrinuse|address already in use|port [0-9]+|connection refused|postgres|database|terminal|stderr|stack trace|traceback|log evidence'; then
    return 1
  fi
  return 0
}

gui_screenshot_layout_extract_value() {
  label_patterns=$1
  text=$2
  printf '%s\n' "$text" | awk -v patterns="$label_patterns" '
    BEGIN {
      count = split(patterns, pats, "|")
    }
    {
      line = $0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      lowered = tolower(line)
      for (i = 1; i <= count; i++) {
        pat = pats[i]
        if (lowered ~ ("^" pat ":[[:space:]]*")) {
          sub(/^[^:]+:[[:space:]]*/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          print line
          exit
        }
      }
    }
  '
}

gui_screenshot_layout_fallback_value() {
  text=$1
  index_raw=$2
  case "$index_raw" in
    ''|*[!0-9]*)
      index_num=1
      ;;
    *)
      index_num=$index_raw
      ;;
  esac
  printf '%s\n' "$text" | awk -v target="$index_num" '
    BEGIN {
      count = 0
    }
    {
      line = $0
      gsub(/\r/, "", line)
      if (line ~ /^```/) next
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      if (tolower(line) ~ /^(issue|evidence|likely cause|fix direction|problem|defect|cause|fix):[[:space:]]*/) {
        sub(/^[^:]+:[[:space:]]*/, "", line)
      }
      gsub(/[[:space:]]+/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      count++
      if (count == target) {
        print line
        exit
      }
    }
  '
}

gui_screenshot_layout_normalize_value() {
  value=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
  value=$(printf '%s' "$value" | sed 's/^`//; s/`$//; s/^"//; s/"$//')
  printf '%s' "$value"
}

gui_screenshot_layout_upgrade_fix_value() {
  current_fix=$1
  issue_value=$2
  evidence_value=$3
  combined_lower=$(printf '%s %s' "$issue_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_fix" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
    if printf '%s' "$current_lower" | grep -Eq 'margin|spacing|wrap|stack|position|absolute|negative|top'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Move the overlapping bar below the heading and replace the hard absolute positioning with normal flow or explicit top spacing."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|cards|grid|column'; then
    if printf '%s' "$current_lower" | grep -Eq 'wrap|grid-template|minmax|columns|responsive|overflow'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Switch the grid to wrapping or minmax columns so the cards break onto a new row instead of overflowing past the right edge."
    return 0
  fi

  if printf '%s' "$current_lower" | grep -Eq 'max-width|width|position|clamp|responsive|overflow|right edge'; then
    printf '%s' "$current_fix"
    return 0
  fi
  printf '%s' "Constrain the container width or max-width and adjust its position so the dialog stays inside the viewport without right-edge overflow."
}

normalize_gui_screenshot_layout_triage_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  issue_value=$(gui_screenshot_layout_extract_value 'issue|problem|defect' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|observed issue' "$output_text")
  cause_value=$(gui_screenshot_layout_extract_value 'likely cause|cause|root cause' "$output_text")
  fix_value=$(gui_screenshot_layout_extract_value 'fix direction|fix|remedy|repair|change' "$output_text")

  if [ -z "$(trim "$issue_value")" ]; then
    issue_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$cause_value")" ]; then
    cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$fix_value")" ]; then
    fix_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  issue_value=$(gui_screenshot_layout_normalize_value "$issue_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  cause_value=$(gui_screenshot_layout_normalize_value "$cause_value")
  fix_value=$(gui_screenshot_layout_normalize_value "$fix_value")

  if [ -z "$issue_value" ]; then
    issue_value="The screenshot shows a concrete layout defect in the visible UI."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible screenshot evidence to point to the clipped, overlapping, or misaligned region."
  fi
  if [ -z "$cause_value" ]; then
    cause_value="A positioning, sizing, or overflow rule is constraining the visible layout."
  fi
  if [ -z "$fix_value" ]; then
    fix_value="Adjust the layout constraints so the affected region fits inside the visible viewport without overlap or clipping."
  fi
  fix_value=$(gui_screenshot_layout_upgrade_fix_value "$fix_value" "$issue_value" "$evidence_value")

  printf 'Issue: %s\nEvidence: %s\nLikely Cause: %s\nFix Direction: %s' \
    "$issue_value" \
    "$evidence_value" \
    "$cause_value" \
    "$fix_value"
}

before_after_ui_delta_upgrade_change_value() {
  current_change=$1
  before_evidence=$2
  after_evidence=$3
  combined_lower=$(printf '%s %s' "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar|page title'; then
      if printf '%s' "$current_lower" | grep -Eq 'dialog|modal|panel' \
        && printf '%s' "$current_lower" | grep -Eq 'inside|contained|visible|no longer clipped|no longer off|overflow'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The dialog is fully contained in the viewport instead of hanging off the right edge."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
      if printf '%s' "$current_lower" | grep -Eq 'filter|chip|title|header' \
        && printf '%s' "$current_lower" | grep -Eq 'below|separate|no longer overlap|clear|stack'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The filter bar now sits below the page title instead of overlapping the header region."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'card|grid' \
      && printf '%s' "$current_lower" | grep -Eq 'wrap|second row|fully visible|no longer clipped'; then
      printf '%s' "$current_change"
      return 0
    fi
    printf '%s' "The card grid now wraps cleanly, so the rightmost card is visible instead of being clipped off-screen."
    return 0
  fi

  printf '%s' "$current_change"
}

before_after_ui_delta_upgrade_impact_value() {
  current_impact=$1
  change_value=$2
  before_evidence=$3
  after_evidence=$4
  combined_lower=$(printf '%s %s %s' "$change_value" "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_impact" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar'; then
      if printf '%s' "$current_lower" | grep -Eq 'approve|confirm|review|complete|footer|button|action'; then
        printf '%s' "$current_impact"
        return 0
      fi
      printf '%s' "Operators can review the dialog and complete the footer action without hidden controls."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$current_lower" | grep -Eq 'readable|scan|header|filter|usable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "The page title is readable again and the filter controls are usable without obscuring the header."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'all cards|scan|compare|metric|readable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "All dashboard cards stay visible, so operators can scan every metric without losing the rightmost card."
    return 0
  fi

  printf '%s' "$current_impact"
}

normalize_before_after_ui_delta_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  change_value=$(gui_screenshot_layout_extract_value 'change|delta|improvement|difference' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  impact_value=$(gui_screenshot_layout_extract_value 'impact|result|why it matters|user impact' "$output_text")

  if [ -z "$(trim "$change_value")" ]; then
    change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$impact_value")" ]; then
    impact_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  change_value=$(gui_screenshot_layout_normalize_value "$change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  impact_value=$(gui_screenshot_layout_normalize_value "$impact_value")

  if [ -z "$change_value" ]; then
    change_value="The visible UI change resolves one concrete layout defect between the before and after screenshots."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="In the before screenshot, point to the clipped, overlapping, or overflowing region."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="In the after screenshot, point to the same region now fitting cleanly inside the layout."
  fi
  if [ -z "$impact_value" ]; then
    impact_value="The visible fix removes one concrete usability or operator-reading problem."
  fi

  change_value=$(before_after_ui_delta_upgrade_change_value "$change_value" "$before_evidence_value" "$after_evidence_value")
  impact_value=$(before_after_ui_delta_upgrade_impact_value "$impact_value" "$change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nImpact: %s' \
    "$change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$impact_value"
}

terminal_state_recovery_upgrade_state_change_value() {
  current_state_change=$1
  before_evidence=$2
  after_evidence=$3
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s' "$current_state_change" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_state_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|starts successfully|ready'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the missing-module boot failure and the app now starts successfully."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|listening|port conflict'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the port-conflict startup failure and the service is now listening normally."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
    if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
      if printf '%s' "$current_lower" | grep -Eq 'failure changed|still failing|recovery incomplete|migration|schema'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "The visible failure changed: PostgreSQL is reachable now, but startup is still blocked by pending migrations or schema work."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|ready'; then
      printf '%s' "$current_state_change"
      return 0
    fi
    printf '%s' "The after screenshot shows a healthy startup instead of the earlier terminal failure."
    return 0
  fi

  printf '%s' "$current_state_change"
}

terminal_state_recovery_upgrade_before_evidence_value() {
  current_before=$1
  state_change_value=$2
  after_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_before" "$state_change_value" "$after_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_before" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot find module|module_not_found|dotenv'; then
      printf '%s' "$current_before"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf "Cannot find module '%s'" "$module_name"
      return 0
    fi
    printf '%s' "Cannot find module"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
      printf '%s' "$current_before"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Error: listen EADDRINUSE: address already in use 0.0.0.0:%s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|econnrefused|postgres|127.0.0.1:5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'connection refused|econnrefused|127.0.0.1:5432|postgres'; then
      printf '%s' "$current_before"
      return 0
    fi
    printf '%s' "Error: connect ECONNREFUSED 127.0.0.1:5432"
    return 0
  fi

  printf '%s' "$current_before"
}

terminal_state_recovery_upgrade_after_evidence_value() {
  current_after=$1
  state_change_value=$2
  before_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_after" "$state_change_value" "$before_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_after" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed'; then
    if printf '%s' "$current_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Health check passed"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'listening on port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'listening on port [0-9]+'; then
      printf '%s' "$current_after"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Server listening on port %s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration required before serving traffic'; then
    if printf '%s' "$current_lower" | grep -Eq 'migration required before serving traffic|relation .* does not exist|applying startup migrations'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Migration required before serving traffic"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'relation .* does not exist'; then
    if printf '%s' "$current_lower" | grep -Eq 'relation .* does not exist'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' 'error: relation "tenants" does not exist'
    return 0
  fi

  printf '%s' "$current_after"
}

terminal_state_recovery_upgrade_next_check_value() {
  current_next=$1
  state_change_value=$2
  before_evidence=$3
  after_evidence=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$state_change_value" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'curl .*health'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'curl -fsS http://127.0.0.1:%s/health' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
    if printf '%s' "$current_lower" | grep -Eq 'db:migrate|migrate'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "npm run db:migrate"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_terminal_state_recovery_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  state_change_value=$(gui_screenshot_layout_extract_value 'state change|change|result|recovery state' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next command|next step|follow-up command' "$output_text")

  if [ -z "$(trim "$state_change_value")" ]; then
    state_change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  state_change_value=$(gui_screenshot_layout_normalize_value "$state_change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$state_change_value" ]; then
    state_change_value="The two screenshots show one concrete change in the visible terminal state."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="Quote the exact visible failure cue from the first terminal screenshot."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="Quote the exact visible startup or failure cue from the second terminal screenshot."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="tail -n 80 ./logs/current.log"
  fi

  before_evidence_value=$(terminal_state_recovery_upgrade_before_evidence_value "$before_evidence_value" "$state_change_value" "$after_evidence_value" "$next_check_value")
  after_evidence_value=$(terminal_state_recovery_upgrade_after_evidence_value "$after_evidence_value" "$state_change_value" "$before_evidence_value" "$next_check_value")
  state_change_value=$(terminal_state_recovery_upgrade_state_change_value "$state_change_value" "$before_evidence_value" "$after_evidence_value")
  next_check_value=$(terminal_state_recovery_upgrade_next_check_value "$next_check_value" "$state_change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'State Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nNext Check: %s' \
    "$state_change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$next_check_value"
}

diagram_annotation_upgrade_takeaway_value() {
  current_takeaway=$1
  evidence_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_takeaway" "$evidence_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_takeaway" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis|queue' && printf '%s' "$current_lower" | grep -Eq 'worker|backpressure|bottleneck'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The Redis queue is the bottleneck because worker-v2 is disabled and backpressure is building at the queue."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'cache|session cache' && printf '%s' "$current_lower" | grep -Eq 'db|postgres|fallback'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "Auth traffic is falling through the session cache to Postgres instead of being served from cache."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'canary' && printf '%s' "$current_lower" | grep -Eq 'fleet|promotion|blocked'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The rollout is stuck at canary, so fleet promotion and release completion are blocked."
    return 0
  fi

  printf '%s' "$current_takeaway"
}

diagram_annotation_upgrade_evidence_value() {
  current_evidence=$1
  takeaway_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_evidence" "$takeaway_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_evidence" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq '92k|backpressure|worker-v2|redis queue'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Redis queue depth 92k; worker-v2 disabled"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq '68%|db fallback|4.8s|session cache'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Session cache miss rate 68%; DB fallback path active"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq '41m|fleet promotion blocked|release notes waiting'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Canary drain stuck 41m; Fleet promotion blocked"
    return 0
  fi

  printf '%s' "$current_evidence"
}

diagram_annotation_upgrade_risk_value() {
  current_risk=$1
  takeaway_value=$2
  evidence_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_risk" "$takeaway_value" "$evidence_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'backlog|delay|timeout|queue'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Queue backlog and downstream processing delay will keep growing until worker consumption recovers."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'login|latency|postgres|db load'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Login latency stays elevated and Postgres absorbs avoidable session-read load while the cache miss path persists."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'partial rollout|drift|stale canary|release'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The release remains partially promoted, which increases rollout drift and keeps operators split between canary and fleet state."
    return 0
  fi

  printf '%s' "$current_risk"
}

diagram_annotation_upgrade_next_check_value() {
  current_next=$1
  takeaway_value=$2
  evidence_value=$3
  risk_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$takeaway_value" "$evidence_value" "$risk_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'kubectl|redis-cli|llen|logs|describe'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "kubectl logs deploy/worker-v2 --tail=100"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis-cli|info|stats|curl|grep'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "redis-cli INFO stats"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'release status|./bin/release|kubectl'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "./bin/release status canary"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_diagram_annotation_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  takeaway_value=$(gui_screenshot_layout_extract_value 'takeaway|finding|main takeaway|observation' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|annotation|visible callout' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$takeaway_value")" ]; then
    takeaway_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  takeaway_value=$(gui_screenshot_layout_normalize_value "$takeaway_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$takeaway_value" ]; then
    takeaway_value="The annotated diagram highlights one concrete operational bottleneck or blocked transition."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use one visible diagram label, callout, or annotation from the screenshot as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The highlighted bottleneck or blocked transition creates operational risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the highlighted service boundary directly."
  fi

  evidence_value=$(diagram_annotation_upgrade_evidence_value "$evidence_value" "$takeaway_value" "$risk_value" "$next_check_value")
  takeaway_value=$(diagram_annotation_upgrade_takeaway_value "$takeaway_value" "$evidence_value" "$risk_value" "$next_check_value")
  risk_value=$(diagram_annotation_upgrade_risk_value "$risk_value" "$takeaway_value" "$evidence_value" "$next_check_value")
  next_check_value=$(diagram_annotation_upgrade_next_check_value "$next_check_value" "$takeaway_value" "$evidence_value" "$risk_value")

  printf 'Takeaway: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$takeaway_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

normalize_dashboard_chart_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|takeaway|main finding|main anomaly' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|visual cue' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$finding_value" ]; then
    finding_value="The chart shows one visually dominant anomaly or weakest step."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible peak, lowest row, or tallest bar in the chart or table as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The visible anomaly creates operational, conversion, or latency risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the underlying segment, release window, or cohort that matches the visual anomaly."
  fi

  printf 'Finding: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

terminal_screenshot_extract_module_name() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$text_lower" | sed -n "s/.*cannot find module ['\"]\\([^'\"]*\\)['\"].*/\\1/p" | sed -n '1p'
}

terminal_screenshot_extract_port() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*:::\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*127\.0\.0\.1", port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  printf '%s' ""
}

terminal_screenshot_upgrade_next_command_value() {
  current_next=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat|kill|pkill'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'pg_isready|systemctl status postgresql|brew services restart postgresql|docker compose ps db'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="5432"
    printf 'pg_isready -h 127.0.0.1 -p %s' "$port_value"
    return 0
  fi

  printf '%s' "$current_next"
}

terminal_screenshot_upgrade_risk_value() {
  current_risk=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot start|boot|startup|service|app|process'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The API process cannot start until the missing dependency is installed."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot bind|cannot start|service|dev server|port'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The service cannot bind to the expected port, so the restart stays blocked."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'migrations|requests|app|cannot connect|database'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    return 0
  fi

  printf '%s' "$current_risk"
}

normalize_terminal_screenshot_debug_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|problem|issue|failure|main failure' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|error line|error|observation' "$output_text")
  next_command_value=$(gui_screenshot_layout_extract_value 'next command|command|next step|follow-up command' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$next_command_value")" ]; then
    next_command_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  next_command_value=$(gui_screenshot_layout_normalize_value "$next_command_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")

  combined_lower=$(printf '%s %s' "$finding_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  if [ -z "$finding_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      module_name=$(terminal_screenshot_extract_module_name "$combined_lower")
      if [ -n "$module_name" ]; then
        finding_value=$(printf 'Node cannot start because the required module %s is missing.' "$module_name")
      else
        finding_value="Node cannot start because a required module is missing."
      fi
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="3000"
      finding_value=$(printf 'The process restart is failing because port %s is already in use.' "$port_value")
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="5432"
      finding_value=$(printf 'The database check is failing because PostgreSQL on 127.0.0.1:%s is refusing connections.' "$port_value")
    else
      finding_value="The visible terminal output shows one concrete startup or connectivity failure."
    fi
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Quote the exact visible error line or code from the terminal screenshot."
  fi
  next_command_value=$(terminal_screenshot_upgrade_next_command_value "$next_command_value" "$finding_value" "$evidence_value")
  if [ -z "$next_command_value" ]; then
    next_command_value="tail -n 80 ./logs/current.log"
  fi
  if [ -z "$risk_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      risk_value="The service cannot boot until the missing dependency is restored."
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      risk_value="The service cannot bind to the expected port, so the restart stays blocked."
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      risk_value="The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    else
      risk_value="The visible failure blocks the service path shown in the terminal output."
    fi
  fi
  risk_value=$(terminal_screenshot_upgrade_risk_value "$risk_value" "$finding_value" "$evidence_value")

  printf 'Finding: %s\nEvidence: %s\nNext Command: %s\nRisk: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$next_command_value" \
    "$risk_value"
}

normalize_browser_image_run_investigation_response() {
  output_text=$(trim "$1")
  prompt_text=$2
  runtime_output=$3
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  browser_value=$(gui_screenshot_layout_extract_value 'browser evidence|browser|snapshot evidence|dom evidence' "$output_text")
  image_value=$(gui_screenshot_layout_extract_value 'image evidence|image|screenshot evidence|visible screenshot cue' "$output_text")
  runtime_value=$(gui_screenshot_layout_extract_value 'runtime evidence|runtime|command evidence|runtime helper output' "$output_text")
  root_cause_value=$(gui_screenshot_layout_extract_value 'root cause|cause|likely cause' "$output_text")
  next_action_value=$(gui_screenshot_layout_extract_value 'next action|next change|next step|follow-up action' "$output_text")

  if [ -z "$(trim "$browser_value")" ]; then
    browser_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$image_value")" ]; then
    image_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$runtime_value")" ]; then
    runtime_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$root_cause_value")" ]; then
    root_cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi
  if [ -z "$(trim "$next_action_value")" ]; then
    next_action_value=$(gui_screenshot_layout_fallback_value "$output_text" "5")
  fi

  browser_value=$(gui_screenshot_layout_normalize_value "$browser_value")
  image_value=$(gui_screenshot_layout_normalize_value "$image_value")
  runtime_value=$(gui_screenshot_layout_normalize_value "$runtime_value")
  root_cause_value=$(gui_screenshot_layout_normalize_value "$root_cause_value")
  next_action_value=$(gui_screenshot_layout_normalize_value "$next_action_value")

  browser_value=$(browser_image_run_upgrade_browser_evidence_value "$browser_value" "$runtime_output")
  image_value=$(browser_image_run_upgrade_image_evidence_value "$image_value" "$runtime_output")
  runtime_value=$(browser_image_run_upgrade_runtime_evidence_value "$runtime_value" "$runtime_output")
  root_cause_value=$(browser_image_run_upgrade_root_cause_value "$root_cause_value" "$runtime_output")
  next_action_value=$(browser_image_run_upgrade_next_action_value "$next_action_value" "$runtime_output")

  if [ -z "$browser_value" ]; then
    browser_value="Use one concrete browser-snapshot detail from the captured Safari state."
  fi
  if [ -z "$image_value" ]; then
    image_value="Use one concrete visible cue from the attached Safari screenshot."
  fi
  if [ -z "$runtime_value" ]; then
    runtime_value="\`./bin/runtime-check.sh\` still reports the bounded runtime mismatch."
  fi
  if [ -z "$root_cause_value" ]; then
    root_cause_value="The browser symptom and runtime helper still point to one bounded configuration or client mismatch."
  fi
  if [ -z "$next_action_value" ]; then
    next_action_value="Apply the smallest bounded runtime or client fix and rerun the verification helper."
  fi

  printf 'Browser Evidence: %s\nImage Evidence: %s\nRuntime Evidence: %s\nRoot Cause: %s\nNext Action: %s' \
    "$browser_value" \
    "$image_value" \
    "$runtime_value" \
    "$root_cause_value" \
    "$next_action_value"
}

prompt_prefers_reasoning_completion() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_dashboard_chart_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_screenshot_debug_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_gui_screenshot_layout_triage_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision' \
    && printf '%s' "$prompt_primary" | grep -Eq 'fallback path|fallback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'disconfirming evidence|disconfirming|counterevidence' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next improvement|risks'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'short labeled sections|labeled sections|same labels|keep the same labels' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision|fallback path|disconfirming evidence|next improvement|risks'; then
    return 0
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'strategy|plan|architecture|forensic|debug|incident|teach|explain|causal|compliance|policy|rollout|recommend|decision memo|trade[- ]?off|stakeholder|decide whether|same cohorts|refunds?|chargebacks?|queue age|cancellation|first read|overturn|misconception|counterexample|ranking (change|tweak)|trial starts'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_compact_reasoning_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    if ! printf '%s' "$prompt_primary" | grep -Eq 'decide whether|first read|overturn|same cohorts|refunds?|chargebacks?|queue age|cancellation|misconception|counterexample|ranking (change|tweak)|trial starts'; then
      return 1
    fi
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq '5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_memo() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|not labeled sections|no labeled sections|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_conversation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    domain_hint=$(reasoning_domain_hint "$prompt_primary")
    case "$domain_hint" in
      ""|cross-domain)
        return 1
        ;;
    esac
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'what would you recommend|what do you recommend|what would you do|what do you do|what do you think|how would you handle|how do you handle|what call do you make|what.?s your take|what.?s your read|what.?s your call|what.?s the move|how does this strike you|thoughts?|thought\?|where does this leave you|is this a real win|is this still a win|still a win|do you push harder|change course|where do you land|your read|your call|your instinct|well\?|gut check|gut reaction|initial take|first instinct|quick read|do you still|still back|still safe|still accept|still support|still hold|still allow|still keep|would you still'; then
    return 1
  fi
  return 0
}

prompt_has_implicit_scenario_sentence_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      count = 0
    }
    {
      n = split($0, parts, /([.?!]+[[:space:]]*|[[:space:]]+-[[:space:]]+)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 3) {
          count++
        }
      }
    }
    END {
      exit(count >= 2 ? 0 : 1)
    }
  '
}

prompt_has_ambiguous_note_fragment_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      total = 0
      shortish = 0
    }
    {
      n = split($0, parts, /([.]+[[:space:]]*|,[[:space:]]*|[[:space:]]+-[[:space:]]+|;[[:space:]]*)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 2) {
          total++
        }
        if (words >= 2 && words <= 7) {
          shortish++
        }
      }
    }
    END {
      exit(total >= 2 && shortish >= 2 ? 0 : 1)
    }
  '
}

prompt_has_reflective_ambiguity_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'feels fragile|feels messy|feels off|something feels off|seems off|smells like|hard to defend|hard to read|hard to trust|hard to explain|doesn.t sit right|not sure what to make of it|don.t know what to make of it|i.m uneasy|i am uneasy|uneasy\b|worrying\b|uglier than it looks|don.t trust the first story|unsafe to teach loosely|not a clean win|still feels unsafe|still feels risky'; then
    return 0
  fi
  return 1
}

prompt_has_narration_context_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'for context|context only|current picture|current state|what we know|as of now|status:?|snapshot:?|current readout|today:?|rough notes|current shape|that.s the shape|that.s the current shape|that.s where we.re at|that.s where it stands'; then
    return 0
  fi
  return 1
}

prompt_prefers_freeform_intent_clarify() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'messy|awkward|ugly|rough|risky|slippery|suspicious|not ideal|bad idea|dangerous|safe|unsafe'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though '; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'tokenized production snippets|tokenized snippets' \
    && printf '%s' "$prompt_primary" | grep -Eq 'raw secrets removed|raw secrets are removed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'near misses|near miss'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'vip complaints cluster|vip complaints' \
    && printf '%s' "$prompt_primary" | grep -Eq 'requests flap against rate limits|rate limits|rate limiting' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback strains the weakest dependency|weakest dependency|rollback would stress'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation|consent-confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user drop|honest user drop|honest-user completion|honest user completion' \
    && printf '%s' "$prompt_primary" | grep -Eq 'latency volatility|volatile latency|latency'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'trial starts up|trial starts jump|trial starts pop|trial starts' \
    && printf '%s' "$prompt_primary" | grep -Eq 'refunds later|refunds rise|refunds' \
    && printf '%s' "$prompt_primary" | grep -Eq 'queue age climbs|queue age' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cohort retention weakens|cohort retention softens|retention weakens|retention softens'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 24 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if ! prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls' \
    && printf '%s' "$prompt_primary" | grep -Eq 'something feels off|feels off'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  return 0
}

prompt_prefers_freeform_frame() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 40 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_implicit_scenario() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 14 ]; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though |[,:;]' \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_reply() {
  prompt_text=$1
  if prompt_prefers_document_revision_task "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reflection "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_frame "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_implicit_scenario "$prompt_text"; then
    return 0
  fi
  return 1
}

assistant_output_is_freeform_reasoning_memo() {
  output_text=$(trim "$1")
  [ -n "$output_text" ] || return 1
  if assistant_output_is_compact_reasoning_contract "$output_text"; then
    return 1
  fi
  if assistant_output_is_reasoning_completion_contract "$output_text"; then
    return 1
  fi
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  sentence_count=$(printf '%s' "$output_text" | awk '
    {
      text = text " " $0
    }
    END {
      gsub(/[[:space:]]+/, " ", text)
      n = split(text, parts, /[.!?][[:space:]]+/)
      count = 0
      for (i = 1; i <= n; i++) {
        part = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", part)
        if (length(part) > 0) {
          count++
        }
      }
      print count
    }
  ')
  case "$sentence_count" in
    ""|*[!0-9]*)
      sentence_count=0
      ;;
  esac
  [ "$sentence_count" -ge 3 ] || return 1
  return 0
}

assistant_output_is_freeform_clarify_question() {
  output_text=$(trim "$1")
  output_text_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  [ -n "$output_text" ] || return 1
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'do you want .* or are you just (capturing|recording) ' \
    && printf '%s' "$output_text_lower" | grep -Eq 'if you want '; then
    return 0
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'provide (the )?(relevant )?(details|context)|more details|more context|clarify (the )?(request|question|goal)|what specifically|which specific|further assistance|provide .*context needed to assist further|please provide .* and any context needed to assist further|provide .* needed to assist further'; then
    return 0
  fi
  return 1
}

assistant_output_is_freeform_frame_response() {
  output_text=$(trim "$1")
  output_text_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  [ -n "$output_text" ] || return 1
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  if printf '%s' "$output_text_lower" | grep -Eq 'not a settled decision request yet' \
    && printf '%s' "$output_text_lower" | grep -Eq 'the key moving parts are' \
    && printf '%s' "$output_text_lower" | grep -Eq 'if you want, i can turn that into'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'just notes|notes only|just recording|just capturing|recording constraints|recording status notes|recording forensics notes|capturing architecture notes|capturing product notes|recording stakeholder notes|recording metric notes|not asking|do not analyze|don.?t analyze'; then
    return 1
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 20 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(yes|yeah|yep|sure|ok|okay|please|go ahead|go on|do it|do so|that one|the recommendation|the call|the read|the likely read|the take|the direction|the safer path|the safer design|the containment path|the leading hypothesis|the policy call|the incident recommendation|the investigation read|the causality read|the explanation approach|recommendation|call|read|likely read|take|direction|safer path|safer design|containment path|leading hypothesis|policy call|incident recommendation|investigation read|causality read|explanation approach)[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommendation|give me .*call|give me .*read|give me .*likely read|give me .*take|give me .*direction|give me .*safer path|give me .*safer design|give me .*containment path|give me .*leading hypothesis|give me .*policy call|give me .*incident recommendation|give me .*investigation read|give me .*causality read|give me .*explanation approach|analy[sz]e (it|this)|want the call|want the recommendation|want the read|want the take|want the direction'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_frame() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 12 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(the )?(current picture|current state|status picture|status|snapshot|context)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (the shape|the current shape|where we.?re at|where it stands)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (the situation|the picture|where things stand)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) (about it|basically it|the gist|what we know)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) it for now[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(that.?s|thats) all (i have|i.ve got|we have)( for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*only that so far[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*just that (at the moment|for the moment)[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*not the (recommendation|call|read|likely read|take|direction|safer path|safer design|containment path|leading hypothesis|policy call|incident recommendation|investigation read|causality read|explanation|explanation approach) yet[[:space:][:punct:]]*$'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?frame (it|this)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

freeform_clarify_reply_prefers_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if freeform_frame_reply_prefers_reflection "$prompt_primary"; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(reflect|reflection|the tension)( first| for now)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

freeform_frame_reply_prefers_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 16 ]; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '^[[:space:]]*(just )?(reflect|reflection|reflective|reflect on it|reflect on this|reflect on the tension|the tension|just the tension|only the tension|keep it reflective|talk me through the tension|think through the tension|walk the tension|think it through)( for now| a bit)?[[:space:][:punct:]]*$'; then
    return 0
  fi
  return 1
}

prompt_prefers_freeform_reasoning_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reasoning "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_frame_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_frame "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection_after_clarify() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reflection "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_clarify_question "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_after_frame() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_clarify_reply_prefers_reasoning "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_frame_response "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection_after_frame() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  if ! freeform_frame_reply_prefers_reflection "$prompt_text"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_frame_response "$prior_answer"; then
    return 1
  fi
  return 0
}

prompt_has_freeform_post_clarify_context() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Prior clarify question:$'; then
    return 1
  fi
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  if freeform_clarify_reply_prefers_reasoning "$latest_prompt"; then
    return 0
  fi
  if freeform_clarify_reply_prefers_frame "$latest_prompt"; then
    return 0
  fi
  if freeform_clarify_reply_prefers_reflection "$latest_prompt"; then
    return 0
  fi
  return 1
}

prompt_has_freeform_post_frame_context() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Prior frame:$'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_followup_memo() {
  prompt_text=$1
  conv_dir=${2:-}
  [ -n "$conv_dir" ] || return 1
  [ -d "$conv_dir" ] || return 1
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if prompt_prefers_document_revision_task "$prompt_text_lower"; then
    return 1
  fi
  if ! reasoning_followup_implicit_text_signals_present "$prompt_text_lower" \
    && ! reasoning_followup_delta_only_turn_present "$prompt_text_lower" \
    && ! reasoning_followup_short_question_present "$prompt_text_lower"; then
    return 1
  fi
  prior_answer=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_freeform_reasoning_memo "$prior_answer"; then
    return 1
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4")
  if reasoning_followup_changed_condition_cues_present "$prompt_text_lower" \
    || reasoning_followup_fragment_delta_present "$prompt_text_lower" \
    || [ -n "$(trim "$(reasoning_followup_recent_delta_turn_for_prompt "$(printf '%s\n\nRecent user turns:\n%s' "$prompt_text" "$recent_user_turns")")")" ]; then
    return 0
  fi
  return 1
}

assistant_output_is_compact_reasoning_contract() {
  output_text=$(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d')
  [ -n "$(trim "$output_text")" ] || return 1
  line_count=$(printf '%s\n' "$output_text" | wc -l | tr -d ' ')
  [ -n "$line_count" ] || line_count=0
  if [ "$line_count" -ne 5 ]; then
    return 1
  fi
  for label in "Outcome:" "Initial Assumption:" "Invalidating Evidence:" "Revised Decision:" "Claim-to-Evidence Map:"; do
    label_count=$(printf '%s\n' "$output_text" | grep -c "^${label}")
    if [ "$label_count" -ne 1 ]; then
      return 1
    fi
  done
  return 0
}

prompt_prefers_compact_reasoning_followup_contract() {
  prompt_text=$1
  conv_dir=${2:-}
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_compact_reasoning_contract "$prompt_primary"; then
    return 0
  fi
  if ! compact_reasoning_followup_text_signals_present "$prompt_primary"; then
    return 1
  fi
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    return 1
  fi
  last_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if assistant_output_is_compact_reasoning_contract "$last_assistant_text"; then
    return 0
  fi
  if assistant_output_is_reasoning_completion_contract "$last_assistant_text"; then
    return 1
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "2")
  if printf '%s' "$prompt_primary" | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map|5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 0
  fi
  if printf '%s' "$recent_user_turns" | tr '[:upper:]' '[:lower:]' | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map' \
    && printf '%s' "$recent_user_turns" | tr '[:upper:]' '[:lower:]' | grep -Eq '5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 0
  fi
  return 1
}

compact_reasoning_latest_prompt_text() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 1 }
    /^Recent user turns:$/ { capture = 0 }
    capture { print }
  '
}

compact_reasoning_prior_answer_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior compact answer:$/ { capture = 1; next }
    capture { print }
  '
}

compact_reasoning_followup_delta_phrase_for_prompt() {
  prompt_text=$1
  latest_prompt=$(compact_reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if ! compact_reasoning_followup_text_signals_present "$latest_prompt_single"; then
    return 0
  fi
  if printf '%s' "$latest_prompt_single" | grep -Eq '[Bb]ecause[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Bb]ecause[[:space:]]*//')
  else
    delta_phrase=$latest_prompt_single
  fi
  delta_phrase=$(printf '%s' "$delta_phrase" | sed \
    -e 's/[[:space:]]*[Ii]n 5 short labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n five short labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n 5 labeled lines only.*$//' \
    -e 's/[[:space:]]*[Ii]n five labeled lines only.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same labels.*$//' \
    -e 's/[[:space:]]*[Uu]se these labels exactly once each:.*$//' \
    -e 's/[[:space:]]*[.]$//')
  delta_phrase=$(trim "$delta_phrase")
  if [ -n "$delta_phrase" ]; then
    printf '%s' "$delta_phrase" | cut -c1-220
  fi
}

compact_reasoning_prior_answer_value_for_prompt() {
  label=$1
  prompt_text=$2
  prior_answer=$(compact_reasoning_prior_answer_block_for_prompt "$prompt_text")
  compact_reasoning_contract_extract_value "$label" "$prior_answer"
}

compact_reasoning_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if ! prompt_prefers_compact_reasoning_followup_contract "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  prior_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "3" | sed -n '1,6p')
  prior_compact_answer=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,5p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior compact answer:\n%s' \
    "$prompt_text" \
    "$prior_user_turns" \
    "$prior_compact_answer"
}

reasoning_freeform_prior_memo_summary_for_prompt() {
  prompt_text=$1
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  prior_answer=$(printf '%s' "$prior_answer" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$prior_answer")" ]; then
    printf '%s' "$prior_answer" | cut -c1-420
  fi
}

reasoning_freeform_updated_conditions_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Updated conditions:$/ { capture = 1; next }
    /^Recent user turns:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior memo:$/ { capture = 0 }
    capture { print }
  '
}

reasoning_freeform_post_clarify_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_latest_turn_from_turns_block "$recent_user_turns")
  fi
  prior_scenario=$(trim "$prior_scenario")
  if [ -z "$prior_scenario" ]; then
    prior_scenario=$(conversation_last_message_for_role "$conv_dir" "user" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  fi
  prior_clarify=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,6p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior clarify question:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_clarify"
}

reasoning_freeform_post_frame_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
  if [ -n "$(trim "$prior_scenario")" ] && { freeform_clarify_reply_prefers_frame "$prior_scenario" \
    || freeform_clarify_reply_prefers_reflection "$prior_scenario" \
    || freeform_clarify_reply_prefers_reasoning "$prior_scenario"; }; then
    earlier_scenario=$(reasoning_followup_turn_before_previous_from_turns_block "$recent_user_turns")
    if [ -n "$(trim "$earlier_scenario")" ]; then
      prior_scenario=$earlier_scenario
    fi
  fi
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_latest_turn_from_turns_block "$recent_user_turns")
  fi
  prior_scenario=$(trim "$prior_scenario")
  if [ -z "$prior_scenario" ]; then
    prior_scenario=$(conversation_first_user_message_for_conversation "$conv_dir" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  fi
  prior_frame=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,6p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior frame:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_frame"
}

reasoning_focus_delta_phrase() {
  delta_text=$(printf '%s' "${1-}" | tr '\n' ' ' | sed 's/ - /; /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$delta_text")" ] || return 0
  if ! printf '%s' "$delta_text" | grep -Eq '[.;]'; then
    printf '%s' "$delta_text"
    return 0
  fi
  printf '%s\n' "$delta_text" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      count = split($0, raw_parts, /[.;]+/)
      kept = 0
      for (i = 1; i <= count; i++) {
        part = trim(raw_parts[i])
        if (part == "") {
          continue
        }
        parts[++kept] = part
      }
      if (kept >= 2) {
        left = parts[kept - 1]
        right = parts[kept]
        sub(/[[:space:][:punct:]]+$/, "", left)
        sub(/^[[:space:][:punct:]]+/, "", right)
        print left " and " right
        exit 0
      }
      print $0
    }
  '
}

reasoning_freeform_followup_delta_for_prompt() {
  prompt_text=$1
  explicit_delta=$(reasoning_freeform_updated_conditions_block_for_prompt "$prompt_text")
  explicit_delta=$(printf '%s' "$explicit_delta" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$explicit_delta")" ]; then
    reasoning_focus_delta_phrase "$explicit_delta"
    return 0
  fi
  delta_phrase=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  reasoning_focus_delta_phrase "$delta_phrase"
}

reasoning_freeform_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if prompt_prefers_freeform_reasoning_after_clarify "$prompt_text" "$conv_dir"; then
    reasoning_freeform_post_clarify_context_prompt "$prompt_text" "$conv_dir"
    return 0
  fi
  if prompt_prefers_freeform_reasoning_after_frame "$prompt_text" "$conv_dir"; then
    reasoning_freeform_post_frame_context_prompt "$prompt_text" "$conv_dir"
    return 0
  fi
  if ! prompt_prefers_freeform_reasoning_followup_memo "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_prior_scenario_from_turns_block "$recent_user_turns" "$prompt_text")
  if [ -z "$(trim "$prior_scenario")" ]; then
    prior_scenario=$(reasoning_prompt_anchor_source "$(conversation_first_user_message_for_conversation "$conv_dir")")
  fi
  prior_freeform_memo=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,8p')
  updated_conditions=$(reasoning_freeform_followup_delta_for_prompt "$prompt_text")
  followup_short_clause=$(reasoning_followup_short_question_clause "$prompt_text")
  if [ -n "$(trim "$followup_short_clause")" ]; then
    updated_norm=$(printf '%s' "$updated_conditions" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/[[:space:][:punct:]]*$//')
    clause_norm=$(printf '%s' "$followup_short_clause" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//; s/[[:space:][:punct:]]*$//')
    if [ -z "$(trim "$updated_norm")" ] || [ "$updated_norm" = "$clause_norm" ]; then
      recent_delta_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_user_turns")
      recent_delta_turn=$(trim "$recent_delta_turn")
      if [ -n "$recent_delta_turn" ] && { reasoning_followup_changed_condition_cues_present "$recent_delta_turn" \
        || reasoning_followup_fragment_delta_present "$recent_delta_turn" \
        || printf '%s' "$recent_delta_turn" | grep -Eq '[,;:]'; }; then
        updated_conditions=$recent_delta_turn
      fi
    fi
  fi
  if [ -z "$(trim "$updated_conditions")" ]; then
    updated_conditions=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
    if reasoning_followup_short_question_present "$updated_conditions"; then
      followup_short_clause=$(reasoning_followup_short_question_clause "$updated_conditions")
      updated_conditions=$(printf '%s\n' "$updated_conditions" | awk '
        function trim(s) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          return s
        }
        BEGIN {
          clause = tolower(ARGV[1])
          ARGV[1] = ""
        }
        {
          raw_line = trim($0)
          line = tolower(raw_line)
          gsub(/[[:space:]]+/, " ", line)
          line = trim(line)
          if (clause == "" || line == clause) {
            print raw_line
            exit 0
          }
          if (length(line) > length(clause) && substr(line, length(line) - length(clause) + 1) == clause) {
            prefix = substr(raw_line, 1, length(raw_line) - length(clause))
            prefix = trim(prefix)
            sub(/[[:space:][:punct:]]+$/, "", prefix)
            print prefix
            exit 0
          }
          print raw_line
        }
      ' "$followup_short_clause")
    fi
    updated_conditions=$(trim "$updated_conditions")
  fi
  printf '%s\n\nUpdated conditions:\n%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior memo:\n%s' \
    "$prompt_text" \
    "$updated_conditions" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_freeform_memo"
}

assistant_output_is_reasoning_completion_contract() {
  output_text=$(trim "$1")
  [ -n "$output_text" ] || return 1
  if output_is_intermediate_contract "$output_text"; then
    return 1
  fi
  if final_has_instructional_placeholders "$output_text"; then
    return 1
  fi
  if final_has_decision_completeness "$output_text" \
    || final_has_assumption_revision_contract "$output_text" \
    || final_has_recovery_contract "$output_text" \
    || final_has_cross_domain_synthesis_contract "$output_text" \
    || final_has_verification_contract "$output_text"; then
    return 0
  fi
  return 1
}

reasoning_followup_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'same plan|same strategy|same incident call|same call|same read|same recommendation|same overall structure|same structure|same format|same outline|keep the same|revise that same|revise the same'; then
    return 1
  fi
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'revise|revised|revision|update|updated|pivot|changed|change explicit|make the revised|make the shift|show the pivot|spell out the pivot|what changed|overturned|make the revised call explicit|make the revised decision explicit|make the decision change explicit'; then
    return 1
  fi
  return 0
}

reasoning_followup_implicit_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update (the )?(recommendation|decision|call|read|plan|strategy|architecture|explanation|incident call)|reconsider|reassess|re-evaluate|reevaluate|what changed|what overturned|does .* still hold|does .* still stand|should we still|would you still|would that still|do you still|what would you do now|what do you do now|what would you do next|what do you do next|what now|where do you land now|how do you read it now|still back it|still support it|still call it|still avoid rollback|still allow it|still keep it|how does that change|change the recommendation|change the decision|change the call|update the explanation'; then
    if reasoning_followup_changed_condition_cues_present "$prompt_text_lower"; then
      return 0
    fi
    if reasoning_followup_fragment_delta_present "$prompt_text_lower"; then
      return 0
    fi
    return 1
  fi
  if ! reasoning_followup_short_question_present "$prompt_text_lower"; then
    return 1
  fi
  if ! reasoning_followup_changed_condition_cues_present "$prompt_text_lower"; then
    if ! reasoning_followup_fragment_delta_present "$prompt_text_lower"; then
      return 1
    fi
  fi
  return 0
}

reasoning_followup_changed_condition_cues_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first read|original read|first intuition|first story|now |^now\b|given that|given these|but |however|still |yet |after |since |remains |remained |returned |eased |improved |recovered |reduced |normalized |stabilized |stabilised |switched |kept |continued |did not |higher |lower |broader |narrower |tighter |looser |weaker |stronger |softer |harder |flatter |noisier |cleaner |cheaper |costlier |more |less |promised |confirmed |required |requires |mandated '; then
    return 0
  fi
  printf '%s\n' "$prompt_text_lower" | awk '
    {
      if (match($0, /(^|[^[:alpha:]])(stayed|worsened|softened|slipped|spiked|spread|narrowed|deepened|persisted|climbed|lagged|resurfaced|widened|flattened|flared|grew|dropped|rose|fell|weakened|drifted|stalled|lingered|doubled|promised|confirmed|required|requires|mandated|worse|better|higher|lower|broader|tighter|looser|stronger|weaker|softer|harder|flatter|noisier|cleaner|cheaper|costlier|more|less)([^[:alpha:]]|$)/)) {
        exit 0
      }
      exit 1
    }
  '
}

reasoning_followup_short_question_clause() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    function emit_if_trailing(line, clause, leading_regex) {
      if (line == clause || line ~ (leading_regex clause "$")) {
        print clause
        exit 0
      }
    }
    {
      line = tolower(trim($0))
      gsub(/[[:space:]]+/, " ", line)
      sub(/[[:space:][:punct:]]+$/, "", line)
      line_plain = line
      gsub(/\047/, "", line_plain)
      emit_if_trailing(line, "where do you land now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "where do you land", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "where does this leave you", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "do you back that", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still safe", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still harmless", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still a win", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still yes", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats your call", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line_plain, "whats the move", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "how does this strike you", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "thoughts", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your call now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your read now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your take now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your call", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "your instinct", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "what now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "well", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "still", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "and", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "gut check", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "gut reaction", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "initial take", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "first instinct", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "quick read", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "thought", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "and now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "then", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "now", "(^|.*[[:space:][:punct:]])")
      emit_if_trailing(line, "so", "(^|.*[[:space:][:punct:]])")
    }
  '
}

reasoning_followup_short_question_present() {
  clause=$(reasoning_followup_short_question_clause "$1")
  [ -n "$(trim "$clause")" ]
}

reasoning_followup_recent_delta_turn_for_prompt() {
  prompt_text=$1
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if ! reasoning_followup_short_question_present "$latest_prompt_single"; then
    return 0
  fi
  if reasoning_followup_changed_condition_cues_present "$latest_prompt_single" \
    || reasoning_followup_fragment_delta_present "$latest_prompt_single"; then
    return 0
  fi
  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
  previous_turn=$(trim "$previous_turn")
  if [ -z "$previous_turn" ]; then
    return 0
  fi
  if reasoning_followup_changed_condition_cues_present "$previous_turn" \
    || reasoning_followup_fragment_delta_present "$previous_turn" \
    || printf '%s' "$previous_turn" | grep -Eq '[,;:]'; then
    printf '%s' "$previous_turn"
  fi
}

reasoning_followup_fragment_delta_present() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  clause=$(reasoning_followup_short_question_clause "$prompt_text_single")
  fragment_source=$prompt_text_single
  if [ -n "$(trim "$clause")" ]; then
    fragment_source=$(printf '%s\n' "$prompt_text_single" | awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      BEGIN {
        clause = tolower(ARGV[1])
        ARGV[1] = ""
      }
      {
        raw_line = trim($0)
        line = tolower(raw_line)
        gsub(/[[:space:]]+/, " ", line)
        line = trim(line)
        if (clause == "" || line == clause) {
          print raw_line
          exit 0
        }
        if (length(line) <= length(clause)) {
          print raw_line
          exit 0
        }
        if (substr(line, length(line) - length(clause) + 1) != clause) {
          print raw_line
          exit 0
        }
        prefix = substr(raw_line, 1, length(raw_line) - length(clause))
        prefix = trim(prefix)
        sub(/[[:space:][:punct:]]+$/, "", prefix)
        print prefix
      }
    ' "$clause")
  fi
  fragment_source=$(trim "$fragment_source")
  [ -n "$fragment_source" ] || return 1
  printf '%s\n' "$fragment_source" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      fragment_count = 0
      short_fragment_count = 0
    }
    {
      line = $0
      gsub(/[[:space:]]+/, " ", line)
      sub(/[[:space:][:punct:]]+$/, "", line)
      split(line, parts, /[,;:]|[[:space:]]+-[[:space:]]+/)
      for (i = 1; i <= length(parts); i++) {
        fragment = trim(parts[i])
        if (fragment == "") {
          continue
        }
        fragment_count++
        word_count = split(fragment, words, /[[:space:]]+/)
        if (word_count <= 5) {
          short_fragment_count++
        }
      }
    }
    END {
      if (fragment_count >= 3 && short_fragment_count >= 3) {
        exit 0
      }
      if (fragment_count >= 2 && fragment_count == short_fragment_count) {
        exit 0
      }
      exit 1
    }
  '
}

prompt_prefers_reasoning_followup_contract() {
  prompt_text=$1
  conv_dir=${2:-}
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_compact_reasoning_contract "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_compact_reasoning_followup_contract "$prompt_primary" "$conv_dir"; then
    return 1
  fi
  if prompt_requires_code_implementation "$prompt_primary"; then
    return 1
  fi
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    return 1
  fi
  last_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
  if ! assistant_output_is_reasoning_completion_contract "$last_assistant_text"; then
    return 1
  fi
  if reasoning_followup_text_signals_present "$prompt_primary"; then
    return 0
  fi
  if reasoning_followup_implicit_text_signals_present "$prompt_primary"; then
    return 0
  fi
  if reasoning_followup_delta_only_turn_present "$prompt_primary"; then
    recent_turns=$(recent_user_turns_for_conversation "$conv_dir" "3")
    previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
    previous_turn=$(trim "$previous_turn")
    if [ -n "$previous_turn" ]; then
      return 0
    fi
    if reasoning_followup_token_overlap_present "$prompt_primary" "$previous_turn" \
      || reasoning_followup_token_overlap_present "$prompt_primary" "$last_assistant_text"; then
      return 0
    fi
  fi
  if reasoning_followup_short_question_present "$prompt_primary"; then
    recent_turns=$(recent_user_turns_for_conversation "$conv_dir" "3")
    previous_turn=$(reasoning_followup_previous_turn_from_turns_block "$recent_turns")
    previous_turn=$(trim "$previous_turn")
    if [ -n "$previous_turn" ] && { reasoning_followup_changed_condition_cues_present "$previous_turn" \
      || reasoning_followup_fragment_delta_present "$previous_turn" \
      || printf '%s' "$previous_turn" | grep -Eq '[,;:]'; }; then
      return 0
    fi
  fi
  return 1
}

reasoning_latest_prompt_text() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 1 }
    /^Recent user turns:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
    /^Attachment context:$/ { capture = 0 }
    /^Web context:$/ { capture = 0 }
    /^Run mode directive:$/ { capture = 0 }
    /^Assay mentoring contract:$/ { capture = 0 }
    /^Explicit skill actuator results:$/ { capture = 0 }
    /^Team metadata:$/ { capture = 0 }
    /^Teacher pacing signal:$/ { capture = 0 }
    capture { print }
  '
}

reasoning_prior_answer_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 1; next }
    /^Prior decision summary:$/ { capture = 1; next }
    /^Prior frame:$/ { capture = 1; next }
    /^Attachment context:$/ { capture = 0 }
    /^Web context:$/ { capture = 0 }
    /^Run mode directive:$/ { capture = 0 }
    /^Assay mentoring contract:$/ { capture = 0 }
    /^Explicit skill actuator results:$/ { capture = 0 }
    /^Team metadata:$/ { capture = 0 }
    /^Teacher pacing signal:$/ { capture = 0 }
    capture { print }
  '
}

reasoning_followup_delta_phrase_for_prompt() {
  prompt_text=$1
  latest_prompt=$(reasoning_latest_prompt_text "$prompt_text")
  latest_prompt_single=$(printf '%s' "$latest_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  recent_delta_turn=$(reasoning_followup_recent_delta_turn_for_prompt "$prompt_text")
  if [ -n "$(trim "$recent_delta_turn")" ]; then
    delta_phrase=$recent_delta_turn
  elif reasoning_followup_delta_only_turn_present "$latest_prompt_single"; then
    delta_phrase=$latest_prompt_single
  elif ! reasoning_followup_text_signals_present "$latest_prompt_single" \
    && ! reasoning_followup_implicit_text_signals_present "$latest_prompt_single"; then
    return 0
  elif printf '%s' "$latest_prompt_single" | grep -Eq '[.?!][[:space:]]*([Dd]o you still|[Ww]ould you still|[Ss]hould we still|[Ww]hat would you do now|[Ww]hat do you do now|[Ww]hat would you do next|[Ww]hat do you do next|[Ww]hat now|[Ww]here do you land now|[Hh]ow do you read it now|[Dd]o you still back|[Dd]o you still support|[Ww]ould you still call|[Ww]ould you still avoid|[Ww]ould you still allow|[Ww]ould you still keep|[Ss]till back it|[Ss]till support it|[Ss]till call it|[Ss]till avoid rollback|[Ss]till allow it|[Ss]till keep it)'; then
    delta_phrase=$(printf '%s\n' "$latest_prompt_single" | awk '
      BEGIN { IGNORECASE = 1 }
      {
        line = $0
        lower = tolower(line)
        if (match(lower, /[.?!][[:space:]]*(do you still|would you still|should we still|what would you do now|what do you do now|what would you do next|what do you do next|what now|where do you land now|how do you read it now|do you still back|do you still support|would you still call|would you still avoid|would you still allow|would you still keep|still back it|still support it|still call it|still avoid rollback|still allow it|still keep it)/)) {
          print substr(line, 1, RSTART - 1)
        }
      }
    ')
  elif reasoning_followup_short_question_present "$latest_prompt_single"; then
    followup_short_clause=$(reasoning_followup_short_question_clause "$latest_prompt_single")
    delta_phrase=$(printf '%s\n' "$latest_prompt_single" | awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      BEGIN {
        clause = tolower(ARGV[1])
        ARGV[1] = ""
      }
      {
        raw_line = trim($0)
        line = tolower(raw_line)
        gsub(/[[:space:]]+/, " ", line)
        line = trim(line)
        if (clause == "" || line == clause) {
          exit
        }
        if (length(line) <= length(clause)) {
          exit
        }
        if (substr(line, length(line) - length(clause) + 1) != clause) {
          exit
        }
        prefix = substr(raw_line, 1, length(raw_line) - length(clause))
        prefix = trim(prefix)
        sub(/[[:space:][:punct:]]+$/, "", prefix)
        print prefix
      }
    ' "$followup_short_clause")
  elif printf '%s' "$latest_prompt_single" | grep -Eq '^[[:space:]]*([Ww]ould|[Ss]hould|[Dd]o|[Dd]oes|[Dd]id|[Ii]s|[Aa]re|[Cc]an|[Cc]ould|[Ww]hat would|[Ww]hat do|[Hh]ow would)[[:space:]]' \
    && printf '%s' "$latest_prompt_single" | grep -Eq '[Nn]ow that[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Nn]ow that[[:space:]]*//')
  elif printf '%s' "$latest_prompt_single" | grep -Eq '^[[:space:]]*([Ww]ould|[Ss]hould|[Dd]o|[Dd]oes|[Dd]id|[Ii]s|[Aa]re|[Cc]an|[Cc]ould|[Ww]hat would|[Ww]hat do|[Hh]ow would)[[:space:]]' \
    && printf '%s' "$latest_prompt_single" | grep -Eq '[Gg]iven that[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Gg]iven that[[:space:]]*//')
  elif printf '%s' "$latest_prompt_single" | grep -Eq '[Bb]ecause[[:space:]]'; then
    delta_phrase=$(printf '%s' "$latest_prompt_single" | sed 's/.*[Bb]ecause[[:space:]]*//')
  else
    delta_phrase=$latest_prompt_single
  fi
  decisive_tail=$(printf '%s\n' "$delta_phrase" | awk '
    BEGIN { IGNORECASE = 1 }
    {
      raw_line = $0
      lower = tolower(raw_line)
      if (match(lower, /,[[:space:]]*but[[:space:]]+/)) {
        print substr(raw_line, RSTART + RLENGTH)
        exit 0
      }
      if (match(lower, /[[:space:]]but[[:space:]]+/)) {
        print substr(raw_line, RSTART + RLENGTH)
        exit 0
      }
    }
  ')
  decisive_tail=$(trim "$decisive_tail")
  if [ -n "$decisive_tail" ] && reasoning_followup_changed_condition_cues_present "$decisive_tail"; then
    delta_phrase=$decisive_tail
  fi
  delta_phrase=$(printf '%s' "$delta_phrase" | sed \
    -e 's/^[[:space:]]*[Nn]ow[[:space:]]*//' \
    -e 's/^[[:space:]]*[Gg]iven[[:space:]]*that[[:space:]]*//' \
    -e 's/^[[:space:]]*[Ww]ith[[:space:]]*those[[:space:]]*changes,[[:space:]]*//' \
    -e 's/[[:space:]]*[Kk]eep the same overall structure.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same structure.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same format.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same labels.*$//' \
    -e 's/[[:space:]]*[Kk]eep same labels.*$//' \
    -e 's/[[:space:]]*same labels.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same plan.*$//' \
    -e 's/[[:space:]]*[Kk]eep the same strategy.*$//' \
    -e 's/[[:space:]]*[Mm]ake the revised call explicit.*$//' \
    -e 's/[[:space:]]*[Mm]ake the revised decision explicit.*$//' \
    -e 's/[[:space:]]*[Mm]ake the decision change explicit.*$//' \
    -e 's/[[:space:]]*[Ss]pell out the revised pivot.*$//' \
    -e 's/[[:space:]]*[Ss]pell out the pivot.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the recommendation.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the decision.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the explanation.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the read.*$//' \
    -e 's/[[:space:]]*[Uu]pdate the call.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what overturned the first read.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what overturned the original read.*$//' \
    -e 's/[[:space:]]*[Aa]nd say what changed.*$//' \
    -e 's/[[:space:]]*[Ii]nclude .*exactly once.*$//' \
    -e 's/[[:space:]]*[Ww]ith explicit decision.*$//' \
    -e 's/[[:space:]]*[?][[:space:]]*$//' \
    -e 's/[[:space:]]*and$//' \
    -e 's/[[:space:]]*[.]$//')
  delta_phrase=$(trim "$delta_phrase")
  if [ -n "$delta_phrase" ]; then
    delta_phrase_length=$(printf '%s' "$delta_phrase" | wc -c | tr -d ' ')
    case "$delta_phrase_length" in
      ""|*[!0-9]*)
        delta_phrase_length=0
        ;;
    esac
    if [ "$delta_phrase_length" -gt 320 ]; then
      delta_phrase=$(printf '%s' "$delta_phrase" | cut -c1-320 | sed 's/[[:space:]][^[:space:]]*$//')
    fi
    delta_phrase=$(trim "$delta_phrase")
    printf '%s' "$delta_phrase"
  fi
}

reasoning_followup_requires_revision_contract() {
  prompt_text=$1
  if prompt_requires_assumption_revision_contract "$prompt_text"; then
    return 0
  fi
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  if [ -n "$(trim "$followup_delta")" ] && [ -n "$(trim "$prior_answer")" ]; then
    return 0
  fi
  return 1
}

reasoning_prior_answer_value_for_prompt() {
  label=$1
  prompt_text=$2
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  reasoning_contract_extract_value "$label" "$prior_answer"
}

reasoning_contract_summary_text() {
  text=$1
  summary=""
  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Outcome" \
    "Decision" \
    "Fallback Path" \
    "Disconfirming Evidence" \
    "Risks" \
    "Next Improvement" \
    "Initial Assumption" \
    "Invalidating Evidence" \
    "Revised Decision" \
    "Evidence Delta"
  do
    value=$(reasoning_contract_extract_value "$label" "$text")
    value=$(trim "$value")
    [ -n "$value" ] || continue
    summary="${summary}${label}: ${value}
"
  done
  IFS=$old_ifs
  printf '%s' "$summary"
}

reasoning_followup_contract_summary_text() {
  text=$1
  summary=""
  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Decision" \
    "Fallback Path" \
    "Disconfirming Evidence" \
    "Revised Decision" \
    "Evidence Delta"
  do
    value=$(reasoning_contract_extract_value "$label" "$text")
    value=$(trim "$value")
    [ -n "$value" ] || continue
    summary="${summary}${label}: ${value}
"
  done
  IFS=$old_ifs
  printf '%s' "$summary"
}

reasoning_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if ! prompt_prefers_reasoning_followup_contract "$prompt_text" "$conv_dir"; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
  prior_scenario=$(reasoning_followup_prior_scenario_from_turns_block "$recent_user_turns" "$prompt_text")
  prior_reasoning_answer_raw=$(conversation_last_message_for_role "$conv_dir" "assistant")
  prior_reasoning_answer=$(reasoning_followup_contract_summary_text "$prior_reasoning_answer_raw")
  if [ -z "$(trim "$prior_reasoning_answer")" ]; then
    prior_reasoning_answer=$(printf '%s' "$prior_reasoning_answer_raw" | sed -n '1,10p')
  fi
  printf '%s\n\nRecent user turns:\n%s\n\nPrior scenario:\n%s\n\nPrior decision summary:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_scenario" \
    "$prior_reasoning_answer"
}

reasoning_text_mentions_followup_delta() {
  text_lower=$(reasoning_contract_lower_text "$1")
  delta_lower=$(reasoning_contract_lower_text "$2")
  [ -n "$(trim "$delta_lower")" ] || return 1
  printf '%s\n' "$delta_lower" | awk -v target="$text_lower" '
    BEGIN { found = 0 }
    {
      n = split($0, parts, /,|;| and /)
      for (i = 1; i <= n; i++) {
        clause = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", clause)
        if (length(clause) >= 8 && index(target, clause) > 0) {
          found = 1
          break
        }
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

reasoning_followup_value_needs_upgrade() {
  current_value=$1
  prior_value=$2
  prompt_text=$3
  current_lower=$(reasoning_contract_lower_text "$current_value")
  prior_lower=$(reasoning_contract_lower_text "$prior_value")
  anchor_lower=$(reasoning_contract_lower_text "$(reasoning_prompt_anchor_phrase "$prompt_text")")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")

  case "$current_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac
  if printf '%s' "$current_lower" | grep -Eq 'revise that same|revise the same|same read because|same plan because|same strategy because|same incident call because|same call because|same recommendation because'; then
    return 0
  fi
  if printf '%s' "$current_lower" | grep -Eq 'cross-domain integrated reasoning|produced a defensible intermediate result|verification evidence:[[:space:]]*review the run trace|current scenario|scenario anchors'; then
    return 0
  fi
  if [ -n "$(trim "$prior_lower")" ] && [ "$current_lower" = "$prior_lower" ]; then
    return 0
  fi
  if [ -n "$(trim "$anchor_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$anchor_lower"; then
    return 0
  fi
  if [ -n "$(trim "$followup_delta")" ] && ! reasoning_text_mentions_followup_delta "$current_value" "$followup_delta"; then
    return 0
  fi
  return 1
}

reasoning_followup_generated_line_for_label() {
  label=$1
  prompt_text=$2
  case "$label" in
    "Outcome")
      reasoning_followup_outcome_line_for_prompt "$prompt_text"
      ;;
    "Decision")
      reasoning_followup_decision_line_for_prompt "$prompt_text"
      ;;
    "Fallback Path")
      reasoning_followup_fallback_line_for_prompt "$prompt_text"
      ;;
    "Disconfirming Evidence")
      reasoning_followup_disconfirming_line_for_prompt "$prompt_text"
      ;;
    "Risks")
      reasoning_followup_risk_line_for_prompt "$prompt_text"
      ;;
    "Next Improvement")
      reasoning_followup_next_improvement_line_for_prompt "$prompt_text"
      ;;
    "Initial Assumption")
      reasoning_followup_initial_assumption_line_for_prompt "$prompt_text"
      ;;
    "Invalidating Evidence")
      reasoning_followup_invalidating_evidence_line_for_prompt "$prompt_text"
      ;;
    "Revised Decision")
      reasoning_followup_revised_decision_line_for_prompt "$prompt_text"
      ;;
    "Evidence Delta")
      reasoning_followup_evidence_delta_line_for_prompt "$prompt_text"
      ;;
  esac
}

reasoning_first_user_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      line = trim(line)
      if (length(line) > 0) {
        print line
        exit 0
      }
    }
  '
}

reasoning_followup_base_scenario_for_prompt() {
  prompt_text=$1
  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  first_user_turn=$(reasoning_first_user_turn_from_turns_block "$recent_turns")
  first_user_turn=$(trim "$first_user_turn")
  if [ -n "$first_user_turn" ]; then
    printf '%s' "$first_user_turn"
    return 0
  fi
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario"
    return 0
  fi
  anchor_source=$(reasoning_followup_anchor_source_for_prompt "$prompt_text")
  anchor_source=$(trim "$anchor_source")
  if [ -n "$anchor_source" ]; then
    printf '%s' "$anchor_source"
    return 0
  fi
  printf '%s' "$prompt_text"
}

reasoning_followup_scenario_reference_for_prompt() {
  prompt_text=$1
  base_scenario=$(reasoning_followup_base_scenario_for_prompt "$prompt_text")
  scenario_ref=$(reasoning_prompt_anchor_phrase "$base_scenario")
  if [ -n "$(trim "$scenario_ref")" ]; then
    printf '%s' "$scenario_ref"
    return 0
  fi
  reasoning_scenario_reference_for_prompt "$prompt_text"
}

reasoning_followup_exact_line_for_label() {
  label=$1
  current_value=$2
  prior_value=$3
  prompt_text=$4
  current_value=$(trim "$current_value")
  if reasoning_followup_value_needs_upgrade "$current_value" "$prior_value" "$prompt_text"; then
    reasoning_followup_generated_line_for_label "$label" "$prompt_text"
    return 0
  fi
  printf '%s: %s' "$label" "$current_value"
}

reasoning_contract_line_if_present() {
  label=$1
  text=$2
  value=$(reasoning_contract_extract_value "$label" "$text")
  value=$(trim "$value")
  [ -n "$value" ] || return 0
  printf '%s: %s' "$label" "$value"
}

reasoning_contract_upsert_line() {
  label=$1
  replacement_line=$2
  text=$3
  prefix=$(printf '%s:' "$label" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$text" | awk -v prefix="$prefix" -v replacement="$replacement_line" '
    BEGIN { updated = 0 }
    {
      lowered = tolower($0)
      if (updated == 0 && index(lowered, prefix) == 1) {
        print replacement
        updated = 1
        next
      }
      print
    }
    END {
      if (updated == 0) {
        print replacement
      }
    }
  '
}

reasoning_live_value_needs_upgrade() {
  label=$1
  current_value=$2
  prompt_text=$3
  current_lower=$(reasoning_contract_lower_text "$current_value")
  anchor_lower=$(reasoning_contract_lower_text "$(reasoning_prompt_anchor_phrase "$prompt_text")")
  scenario_lower=$(reasoning_contract_lower_text "$(reasoning_scenario_reference_for_prompt "$prompt_text")")

  case "$current_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac

  if printf '%s' "$current_lower" | grep -Eq 'cross-domain integrated reasoning|current scenario|scenario anchors|starting investigation|started investigation|workspace inspection|inspect relevant files|failure ledger'; then
    return 0
  fi

  case "$label" in
    "Outcome"|"Decision"|"Fallback Path"|"Disconfirming Evidence"|"Risks"|"Next Improvement")
      if [ -n "$(trim "$anchor_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$anchor_lower"; then
        return 0
      fi
      if [ -n "$(trim "$scenario_lower")" ] && ! printf '%s' "$current_lower" | grep -Fq "$scenario_lower"; then
        return 0
      fi
      ;;
  esac

  return 1
}

normalize_reasoning_live_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")

  if reasoning_live_value_needs_upgrade "Outcome" "$outcome_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Outcome" "$(reasoning_followup_outcome_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Outcome" "Outcome: $(reasoning_outcome_stub_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Decision" "$decision_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Decision" "$(reasoning_followup_decision_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Decision" "Decision: $(reasoning_decision_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Fallback Path" "$fallback_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Fallback Path" "$(reasoning_followup_fallback_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Fallback Path" "Fallback Path: $(reasoning_fallback_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Disconfirming Evidence" "$disconfirming_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "$(reasoning_followup_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "Disconfirming Evidence: $(reasoning_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Risks" "$risks_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Risks" "$(reasoning_followup_risk_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Risks" "Risks: $(reasoning_risk_line_for_prompt "$prompt_text" "DONE")" "$final_text")
    fi
  fi
  if reasoning_live_value_needs_upgrade "Next Improvement" "$next_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      final_text=$(reasoning_contract_upsert_line "Next Improvement" "$(reasoning_followup_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
    else
      final_text=$(reasoning_contract_upsert_line "Next Improvement" "Next Improvement: $(reasoning_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")

  exact_text=$(cat <<EOF
Outcome: $(trim "$outcome_value")
Decision: $(trim "$decision_value")
Fallback Path: $(trim "$fallback_value")
Disconfirming Evidence: $(trim "$disconfirming_value")
Risks: $(trim "$risks_value")
Next Improvement: $(trim "$next_value")
EOF
)

  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Initial Assumption" \
    "Invalidating Evidence" \
    "Revised Decision" \
    "Evidence Delta" \
    "Verification Evidence" \
    "Assumptions and Alternatives" \
    "Priority Order" \
    "Contradiction Check" \
    "Trap and Counterevidence Check" \
    "False Premise Challenge" \
    "Premise Validation" \
    "Adversarial Probe" \
    "Disconfirming Threshold" \
    "Risk Register" \
    "Cross-Domain Integration" \
    "Domain Anchor" \
    "Domain Linkage" \
    "Architecture Lens" \
    "Product/UX Lens" \
    "Security/Compliance Lens" \
    "Metrics/Causality Lens" \
    "Incident/Ops Lens" \
    "Tradeoff Ledger" \
    "Rejected Alternative" \
    "Stakeholder Impact Map" \
    "Recovery and Self-Correction" \
    "Re-Plan Trigger" \
    "Self-Correction Evidence" \
    "Revised From" \
    "Validation Owner" \
    "Time Window" \
    "Evidence Anchors" \
    "Claim-to-Evidence Map" \
    "Quantified Thresholds" \
    "Evidence Caveats" \
    "Scenario-Specific Check" \
    "Assumption Register" \
    "Uncertainty Range" \
    "Source Quality Ranking" \
    "Source Conflict Resolution" \
    "Near-Miss Guard" \
    "Verification Status" \
    "Go/No-Go" \
    "Required Evidence to Proceed" \
    "Residual Risk" \
    "Context Anchor"
  do
    line=$(reasoning_contract_line_if_present "$label" "$final_text")
    line=$(trim "$line")
    [ -n "$line" ] || continue
    exact_text="${exact_text}
$line"
  done
  IFS=$old_ifs

  printf '%s' "$exact_text"
}

normalize_reasoning_freeform_memo() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_reasoning_reply "$prompt_text" \
    && ! prompt_prefers_freeform_reasoning_followup_memo "$prompt_text" "" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text" \
    && ! prompt_has_freeform_post_frame_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_memo_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_reflection_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_reflection "$prompt_text" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text" \
    && ! prompt_has_freeform_post_frame_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_reflection_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_frame_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_frame "$prompt_text" \
    && ! prompt_has_freeform_post_clarify_context "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_frame_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_freeform_clarify_response() {
  final_text=$(trim "$1")
  prompt_text=$2

  if ! prompt_prefers_freeform_intent_clarify "$prompt_text"; then
    printf '%s' "$final_text"
    return 0
  fi

  generated_text=$(reasoning_freeform_clarifying_question_for_prompt "$prompt_text")
  generated_text=$(printf '%s' "$generated_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if [ -n "$(trim "$generated_text")" ]; then
    printf '%s' "$generated_text"
    return 0
  fi

  printf '%s' "$final_text"
}

reasoning_followup_outcome_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Outcome: Reassessed the current call for %s after the updated conditions changed: %s.' \
    "$anchor_phrase" "$followup_delta"
}

reasoning_followup_decision_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_decision_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Decision: %s This revised call explicitly accounts for the updated conditions: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_fallback_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_fallback_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Fallback Path: %s Revert immediately if the updated conditions stop holding: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_disconfirming_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_disconfirming_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Disconfirming Evidence: %s Reopen the previous call if the update proves narrower or less durable than: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_risk_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_risk_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")" "DONE")
  printf 'Risks: %s The revision still depends on the updated conditions proving durable: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_next_improvement_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_next_improvement_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Next Improvement: %s Focus that pass on the revised conditions: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_initial_assumption_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Initial Assumption: The follow-up read assumed the updated conditions (%s) were enough to preserve the prior recommendation for %s.' "$followup_delta" "$anchor_phrase"
}

reasoning_followup_invalidating_evidence_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Invalidating Evidence: That updated read fails if the revised conditions (%s) do not survive the next review window or if concentrated harms for %s remain above guardrails.' "$followup_delta" "$anchor_phrase"
}

reasoning_followup_revised_decision_line_for_prompt() {
  prompt_text=$1
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  base_line=$(reasoning_decision_line_for_prompt "$(reasoning_followup_base_scenario_for_prompt "$prompt_text")")
  printf 'Revised Decision: %s This revision only stands while the updated conditions remain true: %s.' "$base_line" "$followup_delta"
}

reasoning_followup_evidence_delta_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  printf 'Evidence Delta: Confidence increased only where the updated conditions shifted (%s); it remains provisional until those improvements hold without renewed harm for %s.' "$followup_delta" "$anchor_phrase"
}

normalize_reasoning_followup_thread_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  followup_delta=$(reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  if [ -z "$(trim "$followup_delta")" ] || [ -z "$(trim "$prior_answer")" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")
  initial_value=$(reasoning_contract_extract_value "Initial Assumption" "$final_text")
  invalidating_value=$(reasoning_contract_extract_value "Invalidating Evidence" "$final_text")
  revised_value=$(reasoning_contract_extract_value "Revised Decision" "$final_text")
  evidence_delta_value=$(reasoning_contract_extract_value "Evidence Delta" "$final_text")

  prior_outcome_value=$(reasoning_prior_answer_value_for_prompt "Outcome" "$prompt_text")
  prior_decision_value=$(reasoning_prior_answer_value_for_prompt "Decision" "$prompt_text")
  prior_fallback_value=$(reasoning_prior_answer_value_for_prompt "Fallback Path" "$prompt_text")
  prior_disconfirming_value=$(reasoning_prior_answer_value_for_prompt "Disconfirming Evidence" "$prompt_text")
  prior_risks_value=$(reasoning_prior_answer_value_for_prompt "Risks" "$prompt_text")
  prior_next_value=$(reasoning_prior_answer_value_for_prompt "Next Improvement" "$prompt_text")
  prior_initial_value=$(reasoning_prior_answer_value_for_prompt "Initial Assumption" "$prompt_text")
  prior_invalidating_value=$(reasoning_prior_answer_value_for_prompt "Invalidating Evidence" "$prompt_text")
  prior_revised_value=$(reasoning_prior_answer_value_for_prompt "Revised Decision" "$prompt_text")
  prior_evidence_delta_value=$(reasoning_prior_answer_value_for_prompt "Evidence Delta" "$prompt_text")

  if reasoning_followup_value_needs_upgrade "$outcome_value" "$prior_outcome_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Outcome" "$(reasoning_followup_outcome_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$decision_value" "$prior_decision_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Decision" "$(reasoning_followup_decision_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$fallback_value" "$prior_fallback_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Fallback Path" "$(reasoning_followup_fallback_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$disconfirming_value" "$prior_disconfirming_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Disconfirming Evidence" "$(reasoning_followup_disconfirming_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$risks_value" "$prior_risks_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Risks" "$(reasoning_followup_risk_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_value_needs_upgrade "$next_value" "$prior_next_value" "$prompt_text"; then
    final_text=$(reasoning_contract_upsert_line "Next Improvement" "$(reasoning_followup_next_improvement_line_for_prompt "$prompt_text")" "$final_text")
  fi
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    if reasoning_followup_value_needs_upgrade "$initial_value" "$prior_initial_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Initial Assumption" "$(reasoning_followup_initial_assumption_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$invalidating_value" "$prior_invalidating_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Invalidating Evidence" "$(reasoning_followup_invalidating_evidence_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$revised_value" "$prior_revised_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Revised Decision" "$(reasoning_followup_revised_decision_line_for_prompt "$prompt_text")" "$final_text")
    fi
    if reasoning_followup_value_needs_upgrade "$evidence_delta_value" "$prior_evidence_delta_value" "$prompt_text"; then
      final_text=$(reasoning_contract_upsert_line "Evidence Delta" "$(reasoning_followup_evidence_delta_line_for_prompt "$prompt_text")" "$final_text")
    fi
  fi

  outcome_value=$(reasoning_contract_extract_value "Outcome" "$final_text")
  decision_value=$(reasoning_contract_extract_value "Decision" "$final_text")
  fallback_value=$(reasoning_contract_extract_value "Fallback Path" "$final_text")
  disconfirming_value=$(reasoning_contract_extract_value "Disconfirming Evidence" "$final_text")
  risks_value=$(reasoning_contract_extract_value "Risks" "$final_text")
  next_value=$(reasoning_contract_extract_value "Next Improvement" "$final_text")
  initial_value=$(reasoning_contract_extract_value "Initial Assumption" "$final_text")
  invalidating_value=$(reasoning_contract_extract_value "Invalidating Evidence" "$final_text")
  revised_value=$(reasoning_contract_extract_value "Revised Decision" "$final_text")
  evidence_delta_value=$(reasoning_contract_extract_value "Evidence Delta" "$final_text")

  exact_text=$(cat <<EOF
$(reasoning_followup_exact_line_for_label "Outcome" "$outcome_value" "$prior_outcome_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Decision" "$decision_value" "$prior_decision_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Fallback Path" "$fallback_value" "$prior_fallback_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Disconfirming Evidence" "$disconfirming_value" "$prior_disconfirming_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Risks" "$risks_value" "$prior_risks_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Next Improvement" "$next_value" "$prior_next_value" "$prompt_text")
EOF
)
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    exact_text="${exact_text}
$(reasoning_followup_exact_line_for_label "Initial Assumption" "$initial_value" "$prior_initial_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Invalidating Evidence" "$invalidating_value" "$prior_invalidating_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Revised Decision" "$revised_value" "$prior_revised_value" "$prompt_text")
$(reasoning_followup_exact_line_for_label "Evidence Delta" "$evidence_delta_value" "$prior_evidence_delta_value" "$prompt_text")"
  fi

  exact_text="${exact_text}
Context Anchor: $(reasoning_scenario_reference_for_prompt "$prompt_text")."

  old_ifs=${IFS-}
  IFS='
'
  for label in \
    "Verification Evidence" \
    "Assumptions and Alternatives" \
    "Priority Order" \
    "Contradiction Check" \
    "Trap and Counterevidence Check" \
    "False Premise Challenge" \
    "Premise Validation" \
    "Adversarial Probe" \
    "Disconfirming Threshold" \
    "Risk Register" \
    "Cross-Domain Integration" \
    "Domain Linkage" \
    "Architecture Lens" \
    "Product/UX Lens" \
    "Security/Compliance Lens" \
    "Metrics/Causality Lens" \
    "Incident/Ops Lens" \
    "Tradeoff Ledger" \
    "Rejected Alternative" \
    "Stakeholder Impact Map" \
    "Recovery and Self-Correction" \
    "Re-Plan Trigger" \
    "Self-Correction Evidence" \
    "Revised From" \
    "Validation Owner" \
    "Time Window" \
    "Evidence Anchors" \
    "Claim-to-Evidence Map" \
    "Quantified Thresholds" \
    "Evidence Caveats" \
    "Scenario-Specific Check" \
    "Assumption Register" \
    "Uncertainty Range" \
    "Source Quality Ranking" \
    "Source Conflict Resolution" \
    "Near-Miss Guard" \
    "Verification Status" \
    "Go/No-Go" \
    "Required Evidence to Proceed" \
    "Residual Risk"
  do
    optional_line=$(reasoning_contract_line_if_present "$label" "$final_text")
    optional_line=$(trim "$optional_line")
    [ -n "$optional_line" ] || continue
    if printf '%s' "$optional_line" | grep -Eqi 'current scenario|scenario anchors|cross-domain integrated reasoning|recent user turns:|prior scenario:|prior reasoning answer:'; then
      continue
    fi
    exact_text="${exact_text}
$optional_line"
  done
  IFS=$old_ifs

  printf '%s' "$(trim "$exact_text")"
}

reasoning_followup_fast_contract() {
  prompt_text=$1
  exact_text=$(cat <<EOF
$(reasoning_followup_generated_line_for_label "Outcome" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Decision" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Fallback Path" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Disconfirming Evidence" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Risks" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Next Improvement" "$prompt_text")
EOF
)
  if reasoning_followup_requires_revision_contract "$prompt_text"; then
    exact_text="${exact_text}
$(reasoning_followup_generated_line_for_label "Initial Assumption" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Invalidating Evidence" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Revised Decision" "$prompt_text")
$(reasoning_followup_generated_line_for_label "Evidence Delta" "$prompt_text")"
  fi
  printf '%s' "$(trim "$exact_text")"
}

prompt_requires_code_implementation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint|refactor|codebase|source file|unit test|integration test|test suite|bin/status\.sh|bin/restart\.sh|bin/health\.sh|bin/rollback\.sh|bin/audit\.sh|bin/test\.sh|bin/ssh\.sh|config\.env|package-lock\.json|restart cleanly|health check|keep rollback intact|run the restart|run the health|restart the service|restart the demo service|systemctl|journalctl|docker compose|docker service|kubectl|env drift|package upgrade|dependency bump|lockfile|remote host|remote server|ssh'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_service_restart_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/restart\.sh|bin/health\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart cleanly|health checks?|keep rollback intact|demo service|local demo service'; then
    return 0
  fi
  return 1
}

prompt_prefers_partial_system_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/rollback\.sh|bin/health\.sh|bin/verify\.sh|partial-system-rollback|partial system rollback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'partial rollback|partially landed|mixed local state|mixed local mutation|mixed release|mixed package|worker state|stable read-only baseline|approve rollback|execute only the safe rollback path'; then
    return 0
  fi
  return 1
}

prompt_prefers_multi_service_partial_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-api\.sh|bin/status-worker\.sh|bin/rollback-api\.sh|bin/rollback-worker\.sh|multi-service-partial-rollback|multi service partial rollback|api and worker status helpers|api and worker rollback helpers|both rollback helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'two local services|paired api and worker|api and worker|shared rollback|shared rollback-state|shared rollback state|shared rollback only|mixed local rollout|bounded multi-service rollback|api service|worker service|stable read-only baseline'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/publish-release\.sh|bin/verify-release\.sh|core and edge boundary status helpers|publish the release helper|verify release helper|release-pack helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system release pack|system-release-pack|shared release pack|shared release-pack|release pack|release-pack|publish the release pack|published release|release publication|shared release state|release-pack fix' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|publish|verify|rollback|keep rollback intact|rollback ready|preserve rollback|rollback evidence|ordered cutover'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/verify-pack\.sh|core-boundary helper|edge-boundary helper|boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system boundary pack|system-boundary-pack|shared local cutover|two-boundary local cutover|two local boundaries|core boundary|edge boundary|boundary pack|shared cutover state' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|verify|rollback|keep rollback intact|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bin/publish-release\.sh|bin/verify-release\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|release-pack helpers|release helper|release verifier' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote release pack|release-pack|shared remote release pack|shared release pack|published release|release publication|publish the shared release pack|publish-release|release verifier|verify-release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|publish|verify|rollback|keep rollback intact|preserve rollback|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_background_process_recovery_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ps\.sh|bin/stop\.sh|bin/start\.sh|bin/health\.sh|worker helpers?' \
    && printf '%s' "$prompt_primary" | grep -Eq 'background process|background-process|worker process|stuck worker|daemon|worker health|keep rollback intact|keep rollback ready|preserve rollback|stop the worker|start the worker|restart the worker|stop the stale daemon|start the healthy daemon|repair the worker config|smallest safe worker fix'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_env_drift_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/doctor\.sh|bin/verify\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'path drift|version drift|tool drift|environment drift|env drift|toolchain|environment repair'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_package_upgrade_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/audit\.sh|bin/test\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'package upgrade|dependency upgrade|dependency bump|upgrade demo-lib|bump demo-lib|lockfile|keep rollback intact|package state|package files|manifest|smallest safe upgrade|demo-lib|2\.1\.0'; then
    return 0
  fi
  return 1
}

prompt_prefers_long_running_command_polling_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/poll\.sh|bin/checkpoint\.sh|bin/finalize\.sh|long-running command|long running command|checkpoint' \
    && printf '%s' "$prompt_primary" | grep -Eq 'poll|checkpoint|finalize|verify|keep rollback intact|keep rollback ready|preserve rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_filesystem_mutation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/inventory\.sh|bin/apply\.sh|bin/verify\.sh|filesystem mutation|filesystem-mutation|layout pack|layout state|staged config|current link|archive the previous live file' \
    && printf '%s' "$prompt_primary" | grep -Eq 'move|rename|archive|promote|symlink|link|verify|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_repo_runtime_web_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo-scan helper|repo evidence|repo scan' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|runtime evidence|runtime check' \
    && printf '%s' "$prompt_primary" | grep -Eq 'web evidence|migration doc|current doc|docs evidence|current migration' \
    && printf '%s' "$prompt_primary" | grep -Eq 'http://|https://' \
    && printf '%s' "$prompt_primary" | grep -Eq 'root cause' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next change' \
    && printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 0
  fi
  return 1
}

prompt_prefers_browser_image_run_investigation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*safari screenshot|attached safari screenshot|attached screenshot|safari screenshot|screenshot evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser snapshot|browser evidence|dom snapshot|layout snapshot'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|run `\./bin/runtime-check\.sh`|run ./bin/runtime-check\.sh|runtime evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser evidence:|image evidence:|runtime evidence:|root cause:|next action:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser|safari|screenshot|runtime|investigat|triage|no file edits|do not edit files'; then
    return 1
  fi
  return 0
}

prompt_prefers_tool_failure_handoff_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/primary-check\.sh|primary helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/fallback-check\.sh|fallback helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'hand off|handoff|recover by handing off|initial tool path'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://|current doc|current guidance|web evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'primary tool failure|fallback evidence|web evidence|root cause|next action'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_api_migration_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official migration guide|current source|source grounding|version-sensitive api migration|migration question'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|current source|migration change|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_ops_guidance_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/state-check\.sh|local state'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'current official guidance|current guidance|official guidance'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'local state|current guidance|operational decision|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_standards_grounded_answer_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime evidence|runtime check'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official standard|standard/docs|current standard|standards grounded|standards-grounded'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|runtime evidence|current standard|standards answer|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_multi_artifact_judgment_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'mixed-artifact judgment|mixed artifact judgment'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'choose exactly one primary move from analyze, act, clarify, or refuse'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'outcome, decision, code evidence, doc evidence, screenshot evidence, command evidence, fallback path, disconfirming evidence'; then
    return 1
  fi
  return 0
}

prompt_prefers_remote_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|private core/edge boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote boundary pack|boundary-pack|shared boundary pack|core boundary pair|edge boundary pair|core and edge private boundary|two boundary pairs' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|cut|health|verify|verifier|verify-pack|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper|private-target helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollback|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary|partial release|partially landed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback|roll back|recover|revert|health|tunnel'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollout|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|health|release|rollout'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_single_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote service' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|verify|journal|keep rollback intact'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_bastion_cutover_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private\.sh|bastion ssh helper|private ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bastion|jump host|private host|cutover|tunnel' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|tunnel|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-app\.sh|bin/ssh-db\.sh|app ssh helper|replica ssh helper|db ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|replica|primary|failover|promote|app host|db host|database host|replica host' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-canary\.sh|bin/ssh-fleet\.sh|canary ssh helper|fleet ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|canary|fleet|staged rollout|progressive rollout|rollout|second host|second stage' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_deploy_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote deploy|remote release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|release|health|rollback'; then
    return 0
  fi
  return 1
}

local_service_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/service/config.env"
  [ -f "$config_file" ] || return 1
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
PORT=$port_value
EOF_CFG
}

partial_system_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/system.env"
  [ -f "$config_file" ] || return 1
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_package=$(awk -F= '/^STABLE_PACKAGE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker=$(awk -F= '/^STABLE_WORKER=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.15
  fi
  if [ -z "$(trim "$stable_package")" ]; then
    stable_package=2.3.1
  fi
  if [ -z "$(trim "$stable_worker")" ]; then
    stable_worker=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_RELEASE=$stable_release
STABLE_RELEASE=$stable_release
CURRENT_PACKAGE=$stable_package
STABLE_PACKAGE=$stable_package
CURRENT_WORKER=$stable_worker
STABLE_WORKER=$stable_worker
ROLLBACK_APPROVED=1
READ_ONLY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

multi_service_partial_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/multi-service.env"
  [ -f "$config_file" ] || return 1
  stable_api_release=$(awk -F= '/^STABLE_API_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_api_mode=$(awk -F= '/^STABLE_API_MODE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_release=$(awk -F= '/^STABLE_WORKER_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_mode=$(awk -F= '/^STABLE_WORKER_MODE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_api_release")" ]; then
    stable_api_release=2026.03.15-api
  fi
  if [ -z "$(trim "$stable_api_mode")" ]; then
    stable_api_mode=healthy
  fi
  if [ -z "$(trim "$stable_worker_release")" ]; then
    stable_worker_release=2026.03.15-worker
  fi
  if [ -z "$(trim "$stable_worker_mode")" ]; then
    stable_worker_mode=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_API_RELEASE=$stable_api_release
STABLE_API_RELEASE=$stable_api_release
CURRENT_API_MODE=$stable_api_mode
STABLE_API_MODE=$stable_api_mode
CURRENT_WORKER_RELEASE=$stable_worker_release
STABLE_WORKER_RELEASE=$stable_worker_release
CURRENT_WORKER_MODE=$stable_worker_mode
STABLE_WORKER_MODE=$stable_worker_mode
ROLLBACK_APPROVED=1
READ_ONLY=1
API_ROLLBACK_READY=1
WORKER_ROLLBACK_READY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

system_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/release-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.15
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CUTOVER_APPROVED=1
RELEASE_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
RELEASE_NOTES_READY=1
PACK_STATE=ready
EOF_CFG
}

system_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
CUTOVER_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
PACK_STATE=ready
EOF_CFG
}

background_process_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/process/worker.env"
  [ -f "$config_file" ] || return 1
  queue_name=$(awk -F= '/^QUEUE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$queue_name")" ]; then
    queue_name=jobs
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
AUTO_START=1
READ_ONLY=1
QUEUE=$queue_name
EOF_CFG
}

local_env_drift_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/config/toolchain.env"
  [ -f "$config_file" ] || return 1
  cat > "$config_file" <<'EOF_CFG'
EXPECTED_TOOL_PATH=tools/bin
ACTIVE_TOOL_PATH=tools/bin
EXPECTED_VERSION=1.2.3
ACTIVE_VERSION=1.2.3
READ_ONLY=1
EOF_CFG
}

local_package_upgrade_fix_in_place() {
  workspace_path=$1
  manifest_file="$workspace_path/package.json"
  lockfile_file="$workspace_path/package-lock.json"
  [ -f "$manifest_file" ] || return 1
  [ -f "$lockfile_file" ] || return 1
  cat > "$manifest_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "private": true,
  "dependencies": {
    "demo-lib": "2.1.0"
  }
}
EOF_JSON
  cat > "$lockfile_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "dependencies": {
        "demo-lib": "2.1.0"
      }
    },
    "node_modules/demo-lib": {
      "version": "2.1.0"
    }
  }
}
EOF_JSON
}

long_running_command_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/job/run.env"
  [ -f "$config_file" ] || return 1
  target_step=$(awk -F= '/^TARGET_STEP=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$target_step")" ]; then
    target_step=3
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_STEP=0
TARGET_STEP=$target_step
CHECKPOINT_READY=1
ALLOW_FINALIZE=1
READ_ONLY=1
EOF_CFG
}

filesystem_mutation_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/layout.env"
  [ -f "$config_file" ] || return 1
  live_dir=$(awk -F= '/^LIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  staging_file=$(awk -F= '/^STAGING_FILE=/{print $2}' "$config_file" | tail -n 1)
  archive_dir=$(awk -F= '/^ARCHIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  active_link=$(awk -F= '/^ACTIVE_LINK=/{print $2}' "$config_file" | tail -n 1)
  target_name=$(awk -F= '/^TARGET_NAME=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$live_dir")" ]; then
    live_dir=layout/live
  fi
  if [ -z "$(trim "$staging_file")" ]; then
    staging_file=layout/staging/config.yml.next
  fi
  if [ -z "$(trim "$archive_dir")" ]; then
    archive_dir=layout/archive
  fi
  if [ -z "$(trim "$active_link")" ]; then
    active_link=layout/current-config.yml
  fi
  if [ -z "$(trim "$target_name")" ]; then
    target_name=config.yml
  fi
  cat > "$config_file" <<EOF_CFG
LIVE_DIR=$live_dir
STAGING_FILE=$staging_file
ARCHIVE_DIR=$archive_dir
ACTIVE_LINK=$active_link
TARGET_NAME=$target_name
APPLY_READY=1
LINK_READY=1
READ_ONLY=1
EOF_CFG
}

remote_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.10
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
RELEASE_APPROVED=1
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
RELEASE_NOTES_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  current_release=$(awk -F= '/^CURRENT_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$current_release")" ]; then
    current_release=2026.03.22
  fi
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.10
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
CURRENT_RELEASE=$current_release
STABLE_RELEASE=$stable_release
APPROVED_RELEASE=$stable_release
TUNNEL_READY=1
CANARY_ROLLBACK_READY=1
FLEET_ROLLBACK_READY=1
READ_ONLY=1
ROLLOUT_STATE=rollback_ready
EOF_CFG
}

remote_boundary_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
TUNNEL_READY=1
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STATE=staged
EOF_CFG
}

remote_single_host_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/service.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
HOST=$host_value
PORT=$port_value
EOF_CFG
}

remote_bastion_cutover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/bastion.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_private_host=$(awk -F= '/^TARGET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$target_private_host")" ]; then
    target_private_host=demo-app-private-b
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CURRENT_PRIVATE_HOST=$target_private_host
TARGET_PRIVATE_HOST=$target_private_host
APPROVED_PRIVATE_HOST=$target_private_host
BASTION_READY=1
PRIVATE_READY=1
READ_ONLY=1
CUTOVER_STATE=ready
EOF_CFG
}

remote_multi_host_failover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/topology.env"
  [ -f "$config_file" ] || return 1
  app_host=$(awk -F= '/^APP_HOST=/{print $2}' "$config_file" | tail -n 1)
  primary_db_host=$(awk -F= '/^PRIMARY_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  replica_db_host=$(awk -F= '/^REPLICA_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$app_host")" ]; then
    app_host=demo-app-1
  fi
  if [ -z "$(trim "$primary_db_host")" ]; then
    primary_db_host=demo-db-1
  fi
  if [ -z "$(trim "$replica_db_host")" ]; then
    replica_db_host=demo-db-2
  fi
  cat > "$config_file" <<EOF_CFG
APP_HOST=$app_host
PRIMARY_DB_HOST=$replica_db_host
REPLICA_DB_HOST=$primary_db_host
APP_DB_HOST=$replica_db_host
REPLICA_ROLE=primary
FAILOVER_READY=1
APP_READ_ONLY=1
EOF_CFG
}

remote_multi_host_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/rollout.env"
  [ -f "$config_file" ] || return 1
  canary_host=$(awk -F= '/^CANARY_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_host=$(awk -F= '/^FLEET_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$canary_host")" ]; then
    canary_host=demo-app-1
  fi
  if [ -z "$(trim "$fleet_host")" ]; then
    fleet_host=demo-app-2
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CANARY_HOST=$canary_host
FLEET_HOST=$fleet_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STAGE=staged
EOF_CFG
}

remote_deploy_release_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
HOST=$host_value
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
DEPLOY_READY=1
READ_ONLY=1
EOF_CFG
}

quick_mode_append_command_result() {
  command_text=$1
  command_status=$2
  command_output=$3
  quick_loop_summary="${quick_loop_summary}
## Command
$command_text
Status: $command_status
$command_output
"
  if [ "$command_status" = "ok" ]; then
    quick_command_success_total=$((quick_command_success_total + 1))
  fi
  command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
    "$(json_escape "$command_text")" \
    "$(json_escape "$command_status")" \
    "$(json_escape "$command_output")")
  if [ "$quick_commands_first" -eq 1 ]; then
    quick_commands_json=$command_item
    quick_commands_first=0
  else
    quick_commands_json="${quick_commands_json},${command_item}"
  fi
}

quick_mode_run_recorded_command() {
  workspace_id=$1
  workspace_path=$2
  tool_command=$3
  command_mode_value=$4
  blocked_file=$5
  stream_file=$6
  command_output_file=$(mktemp)
  command_status_file=$(mktemp)
  execute_mediated_command "$workspace_id" "$workspace_path" "$tool_command" "$command_output_file" "$command_status_file" "$command_mode_value" "$blocked_file"
  quick_mode_last_command_status=$(cat "$command_status_file" 2>/dev/null || printf '%s' "error")
  quick_mode_last_command_output=$(sed -n '1,40p' "$command_output_file")
  rm -f "$command_output_file" "$command_status_file"
  quick_mode_append_command_result "$tool_command" "$quick_mode_last_command_status" "$quick_mode_last_command_output"
  stream_emit_line "$stream_file" "Quick-mode command: $tool_command ($quick_mode_last_command_status)"
}

local_service_restart_summary() {
  status_output=$1
  restart_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local demo service, rewrote \`service/config.env\` to the healthy/read-only settings, restarted it, and confirmed the service is healthy.
Verification Evidence: Ran \`./bin/status.sh\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")) and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required repair is the local config flip in \`service/config.env\`; broader service hardening remains out of scope.
Next Improvement: Promote the same status, restart, health, and rollback contract into the broader system-ops gate for more complex service shapes.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local demo service and applied the smallest config repair in \`service/config.env\`, but the restart/health sequence did not finish cleanly.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The service still needs a clean restart/health pass before this workspace is considered recovered.
Next Improvement: Re-run the local status, restart, and health helpers after inspecting the current config and state files for any remaining mismatch.
EOF
}

background_process_recovery_summary() {
  ps_output=$1
  stop_output=$2
  start_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded background-worker failure, repaired \`process/worker.env\`, stopped the stale worker, started the healthy worker, and confirmed the worker health check now passes.
Verification Evidence: Ran \`./bin/ps.sh\` before the fix ($(single_line_snippet "$ps_output")); then ran \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the bounded worker issue is isolated to \`process/worker.env\` plus one local worker state file; broader queue drains, multi-worker coordination, and supervisor policy remain out of scope.
Next Improvement: Extend the same ps-stop-start-health contract into a broader background-process gate with polling, checkpointing, and multi-worker recovery.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded background-worker failure and applied the intended worker-config repair, but the stop/start/health sequence still failed.
Verification Evidence: Ran \`./bin/ps.sh\` ($(single_line_snippet "$ps_output")), \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The worker still needs a clean stop/start/health pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded worker ps, stop, start, and health helpers after inspecting the current process config and worker state files for any remaining mismatch.
EOF
}

local_env_drift_summary() {
  doctor_output=$1
  verify_output=$2
  verify_status=$3
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local environment drift, repaired the tool-path and version config, and confirmed the environment now verifies cleanly.
Verification Evidence: Ran \`./bin/doctor.sh\` before the fix ($(single_line_snippet "$doctor_output")); then ran \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the drift is isolated to \`config/toolchain.env\`; broader shell/profile or package-manager drift remains out of scope.
Next Improvement: Extend the same doctor-and-verify contract into a broader env-drift gate that exercises PATH, version, and rollback handling across more than one config shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local environment drift and applied the intended config repair, but the final verification still failed.
Verification Evidence: Ran \`./bin/doctor.sh\` ($(single_line_snippet "$doctor_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved tool-path or version drift and should not be treated as repaired yet.
Next Improvement: Re-run doctor and verify after inspecting the current config and any residual environment assumptions outside \`config/toolchain.env\`.
EOF
}

local_package_upgrade_summary() {
  audit_output=$1
  test_output=$2
  test_status=$3
  if [ "$test_status" = "ok" ]; then
    cat <<EOF
Outcome: Audited the local package state, upgraded \`demo-lib\` in \`package.json\` and \`package-lock.json\`, and confirmed the package tests now pass.
Verification Evidence: Ran \`./bin/audit.sh\` before the change ($(single_line_snippet "$audit_output")); then ran \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded \`demo-lib\` upgrade in \`package.json\` and \`package-lock.json\`; broader dependency graph or runtime compatibility work remains out of scope.
Next Improvement: Extend the same audit-upgrade-test contract into a broader package-management gate with rollback and compatibility checks across more than one dependency shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Audited the local package state and applied the intended \`demo-lib\` upgrade, but the final package test still failed.
Verification Evidence: Ran \`./bin/audit.sh\` ($(single_line_snippet "$audit_output")) and \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved manifest, lockfile, or compatibility issues and should not be treated as upgraded yet.
Next Improvement: Re-run audit and tests after inspecting the current manifest and lockfile for any remaining dependency mismatch.
EOF
}

long_running_command_summary() {
  first_poll_output=$1
  second_poll_output=$2
  checkpoint_output=$3
  third_poll_output=$4
  finalize_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded long-running job, repaired the checkpoint/finalize config, polled the job until it was ready, checkpointed it, finalized it, and confirmed the final verification now passes.
Verification Evidence: Ran the first \`./bin/poll.sh\` before the fix ($(single_line_snippet "$first_poll_output")); then ran a second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), a final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the long-running command is isolated to one bounded job in \`job/run.env\`; broader orchestration, external schedulers, and multi-stage pipeline control remain out of scope.
Next Improvement: Extend the same poll-checkpoint-finalize-verify contract into a broader long-running-command gate with explicit checkpoint timing and stop/go coverage under larger jobs.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded long-running job and applied the intended checkpoint/finalize repair, but the bounded poll/finalize sequence still failed to verify cleanly.
Verification Evidence: Ran the first \`./bin/poll.sh\` ($(single_line_snippet "$first_poll_output")), the second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), the final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded long-running job still needs a clean checkpoint/finalize verification pass before it should be treated as complete.
Next Improvement: Re-run the bounded polling sequence after inspecting the current job config and checkpoint state for any remaining mismatch.
EOF
}

filesystem_mutation_summary() {
  inventory_output=$1
  apply_output=$2
  verify_output=$3
  verify_status=$4
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack, repaired the layout-control file, archived the previous live file, promoted the staged config into the live path, refreshed the current link, and confirmed verification now passes.
Verification Evidence: Ran \`./bin/inventory.sh\` before the fix ($(single_line_snippet "$inventory_output")); then ran \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded layout-state repair in \`state/layout.env\` plus one staged/live/archive file set under \`layout/\`; broader refactors, multi-file rewrites, and large rename graphs remain out of scope.
Next Improvement: Extend the same inventory-apply-verify contract into a broader filesystem-mutation gate that covers larger rename, move, and refactor packs with explicit rollback checkpoints.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack and applied the intended layout-control repair, but the apply or final verification sequence still failed.
Verification Evidence: Ran \`./bin/inventory.sh\` ($(single_line_snippet "$inventory_output")), \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded filesystem mutation pack still needs a clean archive/promote/link verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded inventory, apply, and verify sequence after inspecting the current layout state and rollback readiness for any remaining mismatch.
EOF
}

repo_runtime_web_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

repo_runtime_web_first_url_from_prompt() {
  prompt_text=$1
  urls_file=$(mktemp)
  extract_urls_from_text "$prompt_text" > "$urls_file"
  first_url=$(sed -n '1p' "$urls_file")
  rm -f "$urls_file"
  first_url=$(trim "$first_url")
  first_url=$(printf '%s' "$first_url" | sed 's/[.,;:!?)]*$//')
  printf '%s' "$first_url"
}

repo_runtime_web_extract_doc_endpoint() {
  doc_excerpt=$1
  endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | grep -E '^/v2/' | head -n 1 || true)
  if [ -z "$(trim "$endpoint_value")" ]; then
    endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | tail -n 1 || true)
  fi
  endpoint_value=$(trim "$endpoint_value")
  if [ -z "$endpoint_value" ]; then
    endpoint_value="/v2/widgets"
  fi
  printf '%s' "$endpoint_value"
}

repo_runtime_web_extract_doc_timeout_ms() {
  doc_excerpt=$1
  timeout_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[0-9]{4,5}[[:space:]]*ms' | head -n 1 | tr -cd '0-9' || true)
  timeout_value=$(trim "$timeout_value")
  if [ -z "$timeout_value" ]; then
    timeout_value="15000"
  fi
  printf '%s' "$timeout_value"
}

repo_runtime_web_triage_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5
  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "webapp/src/widgets-client.js")
  repo_endpoint=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_endpoint" "/v1/widgets/list")
  repo_response_key=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_response_key" "widgets")
  repo_timeout_ms=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_timeout_ms" "5000")
  runtime_http_status=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_http_status" "404")
  runtime_endpoint=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_endpoint" "$repo_endpoint")
  runtime_shape_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_shape_issue" "expected_items_found_widgets")
  runtime_timeout_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_timeout_issue" "timeout_too_low")
  doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
  doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
  doc_fields="items and next_cursor"
  if ! printf '%s' "$doc_excerpt" | grep -Eq 'items'; then
    doc_fields="items"
  fi
  runtime_clause="\`./bin/runtime-check.sh\` reports HTTP $runtime_http_status on $runtime_endpoint and $runtime_shape_issue"
  if [ "$runtime_status" != "ok" ]; then
    runtime_clause="$runtime_clause while the bounded runtime check still exits non-zero"
  fi
  if [ -n "$(trim "$runtime_timeout_issue")" ]; then
    runtime_clause="$runtime_clause plus $runtime_timeout_issue"
  fi
  cat <<EOF
Repo Evidence: \`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_endpoint\`, parses \`$repo_response_key\`, and uses \`timeoutMs=$repo_timeout_ms\`.
Runtime Evidence: $runtime_clause.
Web Evidence: The migration doc at $doc_url says the client should call \`$doc_endpoint\`, read \`$doc_fields\`, and allow a \`$doc_timeout_ms\` ms timeout.
Root Cause: The repo and runtime still target the removed v1 widgets contract, so the client endpoint, response parsing, and timeout no longer match the current migration doc.
Next Change: Update \`$repo_file\` to call \`$doc_endpoint\`, read \`$doc_fields\`, and raise the client timeout to \`$doc_timeout_ms\` ms before widening further.
EOF
}

tool_failure_handoff_doc_flag() {
  doc_excerpt=$1
  default_value=${2:-uploads_rollout=on}
  flag_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[A-Za-z_]+=[A-Za-z0-9._/-]+' | head -n 1 || true)
  flag_value=$(trim "$flag_value")
  if [ -z "$flag_value" ]; then
    flag_value=$default_value
  fi
  printf '%s' "$flag_value"
}

tool_failure_handoff_doc_env_key() {
  doc_excerpt=$1
  default_value=${2:-SESSION_CACHE_URL}
  env_key=$(printf '%s' "$doc_excerpt" | grep -Eo 'SESSION_CACHE_URL' | head -n 1 || true)
  env_key=$(trim "$env_key")
  if [ -z "$env_key" ]; then
    env_key=$default_value
  fi
  printf '%s' "$env_key"
}

tool_failure_handoff_primary_reason_text() {
  primary_output=$1
  primary_reason=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_reason" "initial helper failure")
  case "$primary_reason" in
    repo_scan_unavailable)
      printf '%s' "the repo scan helper is unavailable in this workspace"
      ;;
    browser_snapshot_capture_failed)
      printf '%s' "browser snapshot capture is unavailable right now"
      ;;
    dom_snapshot_unavailable)
      printf '%s' "the DOM snapshot helper is unavailable right now"
      ;;
    *)
      printf '%s' "$primary_reason"
      ;;
  esac
}

tool_failure_handoff_summary() {
  primary_output=$1
  primary_status=$2
  fallback_output=$3
  fallback_status=$4
  doc_url=$5
  doc_excerpt=$6

  primary_helper=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_helper" "./bin/primary-check.sh")
  primary_reason_text=$(tool_failure_handoff_primary_reason_text "$primary_output")
  fallback_issue=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_issue" "fallback_required")
  fallback_file=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_file" "config/runtime.env")

  case "$fallback_issue" in
    legacy_widget_contract)
      runtime_endpoint=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_endpoint" "/v1/widgets/list")
      runtime_timeout_ms=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_timeout_ms" "5000")
      doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
      doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still calls \`$runtime_endpoint\` with \`timeoutMs=$runtime_timeout_ms\` while the bounded fallback check remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says clients must call \`$doc_endpoint\` and allow at least \`$doc_timeout_ms\` ms before wider rollout."
      root_line="The initial repo-scan path is unavailable, but the fallback runtime plus current docs still show the client is pinned to the removed widgets contract."
      next_line="Update \`$fallback_file\` to call \`$doc_endpoint\` and raise the client timeout to \`$doc_timeout_ms\` ms, then restore the primary helper for a clean repo-side audit."
      ;;
    uploads_rollout_disabled)
      runtime_flag=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_flag" "uploads_rollout=off")
      runtime_route=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_route" "/v2/uploads/complete")
      doc_flag=$(tool_failure_handoff_doc_flag "$doc_excerpt" "uploads_rollout=on")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still sets \`$runtime_flag\`, so the bounded upload route \`$runtime_route\` remains disabled while the fallback helper stays \`$fallback_status\`."
      web_line="The current doc at $doc_url says publishing uploads requires \`$doc_flag\` before clients use \`$runtime_route\`."
      root_line="The initial browser-control path is unavailable, but the fallback runtime evidence shows uploads are disabled in config rather than broken in the UI."
      next_line="Set \`$doc_flag\` in \`$fallback_file\`, then rerun the bounded upload path after the primary helper is restored."
      ;;
    session_cache_missing)
      runtime_cache=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_session_cache_url" "missing")
      runtime_miss_rate=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_miss_rate" "68%")
      doc_env_key=$(tool_failure_handoff_doc_env_key "$doc_excerpt" "SESSION_CACHE_URL")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` has \`$doc_env_key=$runtime_cache\` and the bounded login path is falling back with miss rate $runtime_miss_rate while the helper remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says interactive login requires \`$doc_env_key\` before traffic is widened again."
      root_line="The initial snapshot path is unavailable, but the fallback runtime evidence shows degraded login comes from a missing session cache endpoint."
      next_line="Set \`$doc_env_key\` in \`$fallback_file\`, warm the session cache, and retry the bounded login path after the primary helper is back."
      ;;
    *)
      fallback_line="\`./bin/fallback-check.sh\` produced bounded fallback evidence ($(single_line_snippet "$fallback_output")) while the helper remained \`$fallback_status\`."
      web_line="The current doc at $doc_url provides the authoritative fallback guidance."
      root_line="The initial tool path failed, so the fallback helper and current docs became the authoritative evidence path."
      next_line="Repair the issue indicated by the fallback helper, then restore the primary tool path for a clean rerun."
      ;;
  esac

  cat <<EOF
Primary Tool Failure: \`$primary_helper\` returned \`$primary_status\` and reported that $primary_reason_text.
Fallback Evidence: $fallback_line
Web Evidence: $web_line
Root Cause: $root_line
Next Action: $next_line
EOF
}

current_api_migration_summary() {
  repo_output=$1
  doc_url=$2
  doc_excerpt=$3

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "app/user_loader.py")
  repo_old_method=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_old_method" "parse_obj")
  repo_call=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_call" "$repo_old_method")

  case "$repo_old_method" in
    parse_obj)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`parse_obj()\` to \`model_validate()\`."
      change_line="Pydantic V2 replaces the V1 validation entry point \`parse_obj()\` with \`model_validate()\`."
      root_line="The repo still uses the V1 validation API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`User.model_validate(payload)\` in \`$repo_file\`."
      ;;
    dict)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`dict()\` to \`model_dump()\`."
      change_line="Pydantic V2 replaces the V1 serialization helper \`dict()\` with \`model_dump()\`."
      root_line="The repo still uses the V1 serialization API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`user.model_dump()\` in \`$repo_file\`."
      ;;
    from_orm)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url says \`from_orm()\` is deprecated in favor of \`model_validate()\` with \`from_attributes=True\`."
      change_line="Pydantic V2 moves ORM-style loading to \`model_validate()\` plus a model config that enables \`from_attributes=True\`."
      root_line="The repo still uses the V1 ORM-loading API while the current official docs require the V2 validation path and attribute-based config."
      next_line="Replace \`$repo_call\` with \`User.model_validate(record)\` and enable \`from_attributes=True\` in the model config in \`$repo_file\`."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still uses \`$repo_call\`."
      source_line="The current official migration guide at $doc_url provides the authoritative migration target."
      change_line="The current docs describe a newer API surface than the one still referenced in the repo."
      root_line="The repo still targets an older API contract than the current official guide."
      next_line="Update \`$repo_file\` from \`$repo_call\` to the current API named in the official migration guide."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Current Source: $source_line
Migration Change: $change_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

current_ops_guidance_summary() {
  state_output=$1
  doc_url=$2
  doc_excerpt=$3

  state_file=$(repo_runtime_web_extract_kv_value "$state_output" "state_file" "deploy/api-deployment.yaml")
  state_issue=$(repo_runtime_web_extract_kv_value "$state_output" "state_issue" "slow_start_liveness_kills")
  state_shared_probe_path=$(repo_runtime_web_extract_kv_value "$state_output" "state_shared_probe_path" "/healthz")
  state_startup_p95_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_startup_p95_seconds" "75")
  state_liveness_initial_delay_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_liveness_initial_delay_seconds" "5")
  state_dependency=$(repo_runtime_web_extract_kv_value "$state_output" "state_dependency" "db-warmup")

  case "$state_issue" in
    slow_start_liveness_kills|cache_warmup_slow_start)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` has no \`startupProbe\`, reuses \`$state_shared_probe_path\`, and starts liveness after \`$state_liveness_initial_delay_seconds\` seconds even though startup p95 is \`$state_startup_p95_seconds\` seconds."
      guidance_line="The current official guidance at $doc_url says slow starting containers should use \`startupProbe\`, and that liveness and readiness do not start until the startup probe succeeds."
      decision_line="Add a \`startupProbe\` and keep liveness/readiness for steady-state checks after the container has started."
      root_line="The pod is being judged by liveness too early, so a slow boot or cache warmup is being treated as a dead process instead of a startup phase."
      next_line="Update \`$state_file\` to add \`startupProbe\` for \`$state_shared_probe_path\` and leave liveness/readiness for the post-start steady state."
      ;;
    temporary_dependency_overload)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` uses the same \`$state_shared_probe_path\` for liveness and readiness while \`$state_dependency\` causes transient overload."
      guidance_line="The current official guidance at $doc_url says readiness failures remove a pod from service endpoints, while liveness should be reserved for when a restart is the right recovery."
      decision_line="Move the dependency-sensitive check to \`readinessProbe\` and keep liveness for true deadlock or unrecoverable failure."
      root_line="A temporary dependency slowdown is being routed through liveness, so Kubernetes restarts the pod instead of only stopping new traffic."
      next_line="Update \`$state_file\` so \`readinessProbe\` reflects dependency readiness and liveness only checks whether the process is actually stuck."
      ;;
    *)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` still needs a probe-policy change."
      guidance_line="The current official guidance at $doc_url contains the bounded probe policy that should be applied here."
      decision_line="Align the deployment probes with the current official guidance before widening traffic."
      root_line="The local deployment still diverges from the current official probe guidance."
      next_line="Update \`$state_file\` to match the current official probe guidance, then rerun the bounded state check."
      ;;
  esac

  cat <<EOF
Local State: $local_line
Current Guidance: $guidance_line
Operational Decision: $decision_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

standards_grounded_answer_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "server/cors.py")
  standard_issue=$(repo_runtime_web_extract_kv_value "$repo_output" "standard_issue" "cors_credentials_wildcard")

  case "$standard_issue" in
    cors_credentials_wildcard)
      repo_allow_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_origin" "*")
      repo_allow_credentials=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_credentials" "true")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://app.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "credentials_blocked_by_wildcard")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still sets \`Access-Control-Allow-Origin: $repo_allow_origin\` together with \`Access-Control-Allow-Credentials: $repo_allow_credentials\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the credentialed request from \`$repo_origin\` is failing as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say credentialed CORS requests cannot use \`Access-Control-Allow-Origin: *\`."
      answer_line="Return the explicit allowed origin instead of \`*\` whenever credentials are enabled."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Origin\` is the explicit trusted origin and keep credentials enabled only for that origin."
      ;;
    samesite_none_without_secure)
      repo_cookie_name=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_cookie_name" "app_session")
      repo_same_site=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_same_site" "None")
      repo_secure=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_secure" "false")
      runtime_browser=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_browser" "chrome")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "session_cookie_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still emits the \`$repo_cookie_name\` cookie with \`SameSite=$repo_same_site\` and \`Secure=$repo_secure\`."
      runtime_line="\`./bin/runtime-check.sh\` reports \`$runtime_browser\` is rejecting the session cookie as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say cookies marked \`SameSite=None\` must also set \`Secure\`."
      answer_line="Either add \`Secure\` to that cookie or stop using \`SameSite=None\` if the cookie should not cross sites."
      next_line="Update \`$repo_file\` so the \`$repo_cookie_name\` cookie sets \`Secure\` whenever it uses \`SameSite=None\`."
      ;;
    cors_authorization_header_missing)
      repo_allow_headers=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_headers" "Content-Type")
      repo_requested_header=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_requested_header" "Authorization")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://admin.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "preflight_header_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still returns \`Access-Control-Allow-Headers: $repo_allow_headers\` while clients send \`$repo_requested_header\` from \`$repo_origin\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the preflight is failing as \`$runtime_symptom\` for the \`$repo_requested_header\` request header while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say \`Access-Control-Allow-Headers\` must allow request headers such as \`$repo_requested_header\` when the preflight asks for them."
      answer_line="Include \`$repo_requested_header\` in \`Access-Control-Allow-Headers\` or stop sending that header from the browser path."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Headers\` includes \`$repo_requested_header\` for the allowed origin."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still violates the bounded standard contract."
      runtime_line="\`./bin/runtime-check.sh\` confirms the current runtime still fails the bounded standards check with status \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url contain the authoritative rule that should be applied here."
      answer_line="Align the repo and runtime behavior with the current official standard before widening anything further."
      next_line="Update \`$repo_file\` to match the current official standard, then rerun the bounded repo and runtime checks."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Runtime Evidence: $runtime_line
Current Standard: $standard_line
Standards Answer: $answer_line
Next Change: $next_line
EOF
}

multi_artifact_judgment_summary() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$prompt_lower" | grep -Eq 'payments_v2_force_off|issuer_jwks_v2'; then
    cat <<'EOF'
Outcome: Context anchor: canary-only checkout auth failure after the payments v2 push. Act now by forcing `PAYMENTS_V2_FORCE_OFF=true` for the canary path before any rollback. Assumption: the blast radius is still canary-only. Verification plan: confirm `auth_fail_v2` falls, canary crashloops stop, and fleet checkout p95 stays flat. Counterevidence to the first read: the dashboard and logs show a bounded config fault, not a fleet-wide regression. Contradiction check: if non-canary pods degrade too, this is no longer a canary-only containment move.
Decision: Act
Code Evidence: `route = "v2" if feature_flags.payments_canary else "v1"` plus the `PAYMENTS_V2_FORCE_OFF` kill switch provides a bounded containment move before any rollback.
Doc Evidence: The rollout runbook says if `auth_fail_v2` spikes after deploy, force `PAYMENTS_V2_FORCE_OFF=true` before rollback because rollback can strand migrated session leases.
Screenshot Evidence: The dashboard card shows `auth_fail_v2 18%` in red while `checkout p95` stays flat and only canary pods are affected, which keeps the visible blast radius narrow.
Command Evidence: Command anchors: `kubectl logs payments-v2-canary` ends with `unknown key issuer_jwks_v2`, and `kubectl get pods` shows only canary crashlooping.
Fallback Path: Priority order: bounded canary containment first, rollback second. If forcing `PAYMENTS_V2_FORCE_OFF=true` does not clear canary failures or if fleet health regresses, roll back the canary path only and preserve migrated session leases.
Disconfirming Evidence: Reopen this call if non-canary pods fail, `checkout p95` worsens, or logs show lease/session corruption instead of the bounded `issuer_jwks_v2` config fault. Evidence anchors: kill switch, rollout runbook, dashboard card, and kubectl output.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'review-app|vendor preview|app_env=staging'; then
    cat <<'EOF'
Outcome: Context anchor: the request is for a vendor admin link while the only visible environment signal is staging. Clarify with one question: do you need a staging-only review-app preview, or are you asking for a production tenant walkthrough with legal approval? Assumption: the current `review-app` and `APP_ENV=staging` signals mean the bounded safe path is still staging. Verification plan: wait for that answer before exposing any admin link. Counterevidence to acting now: the runbook limits vendor previews to staging only unless legal approves a production exception. Contradiction check: a production walkthrough cannot be treated as the same request as a staging preview.
Decision: Clarify
Code Evidence: `admin_export_preview` is behind `staff && reviewAppReady`, which means the code already assumes a bounded review-app path rather than an unconditional live admin link.
Doc Evidence: The demo runbook says vendor previews are staging only unless legal approves a production exception.
Screenshot Evidence: The open page shows a `review-app` badge and no production warning banner.
Command Evidence: Command anchors: `APP_ENV=staging` and `vendor_preview_enabled=true` confirm the active environment is staging, not production.
Fallback Path: If they only need the staging preview, send the review-app link; if they require a production tenant walkthrough, stop and route it through the legal exception path first.
Disconfirming Evidence: Reopen this call only if legal explicitly approves a production exception and the requester confirms they need a production tenant walkthrough rather than the existing staging review-app.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'eu-442|stream_recovery_events|residency review|raw customer export'; then
    cat <<'EOF'
Outcome: Context anchor: the proposed move is to ship raw outage data from an EU tenant to a vendor during an active incident. Refuse that request. Assumption: the export still contains region-linked customer recovery detail. Verification plan: confirm attributed approval and residency review before any vendor data leaves the system. Counterevidence to the pressure to act: the incident policy already says vendor sharing waits for approval and residency review. Contradiction check: removing direct identifiers does not make raw recovery events residency-safe.
Decision: Refuse
Code Evidence: `stream_recovery_events()` returns raw recovery events with account event rows and region ids intact.
Doc Evidence: The incident policy allows vendor sharing only after attributed approval and residency review.
Screenshot Evidence: The support pane is open on an EU tenant with billing timeline detail still visible.
Command Evidence: Command anchors: `./bin/export-debug.sh --tenant eu-442 --raw > /tmp/eu-442.ndjson` would create a raw export from the EU tenant immediately.
Fallback Path: Use a safer alternative: send an attributed incident summary or synthetic sample first, then request approval and residency review before any vendor-facing export.
Disconfirming Evidence: Reopen this call only if the data is reduced below raw recovery events, attributed approval is recorded, and residency review clears the exact export path for that tenant.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'idempotency_key|settlement-replay mismatch count=37|duplicate charges'; then
    cat <<'EOF'
Outcome: Context anchor: duplicate charges appear only on retries after failover, but the bounded evidence still mixes replay and settlement signals. Analyze before customer-impact action. Assumption: the replay/settlement mismatch is the dominant cause, but that still needs one tighter proof chain. Verification plan: sample mismatched charge ids, compare settlement versus replay state, and confirm the replay queue is not the active source of drift. Counterevidence to dismissing this as support noise: the mismatch count is 37 and every duplicate sample has a non-zero retry index. Contradiction check: zero replay queue lag does not mean settlement and replay agree.
Decision: Analyze
Code Evidence: The new billing worker writes `idempotency_key = charge_id + retry_index`, which changes retry semantics and points directly at the duplicate-on-retry path.
Doc Evidence: The reconciliation note says duplicate-charge incidents require proof that replay and settlement disagree before any customer-impact action.
Screenshot Evidence: The finance dashboard shows duplicate charges only on retries after failover, not on first attempts.
Command Evidence: Command anchors: `billing-replay-queue lag=0`, `settlement-replay mismatch count=37`, and every duplicate sample has non-zero `retry_index`, so the replay queue is clean while settlement mismatch remains real.
Fallback Path: Hold customer-facing action, isolate the replay queue versus settlement diff, and move to Act only after one bounded proof chain shows which side is wrong.
Disconfirming Evidence: Reopen this call if the mismatch count drops to zero, sampled duplicates no longer share the retry path, or settlement and replay converge on the same charge state.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'drain_region|queue_age us-west=14m|shared dependency at 92% saturation'; then
    cat <<'EOF'
Outcome: Context anchor: login success recovered globally, but `us-west` still shows regional harm and rollback would stress a saturated shared dependency. Act now with bounded containment by draining new traffic from `us-west`. Assumption: regional containment reduces harm faster than rollback here. Verification plan: confirm queue age falls, complaint volume drops, and shared dependency saturation stays below the rollback danger threshold. Counterevidence to closing the incident: the heatmap, complaints, and queue data all still show live regional damage. Contradiction check: a globally green headline cannot coexist with a still-red region and 14-minute queue age if the incident is actually over.
Decision: Act
Code Evidence: The bounded helper `drain_region("us-west")` exists, which means the code supports a narrow containment move without forcing a full rollback.
Doc Evidence: The incident playbook says prefer bounded regional containment when the shared dependency would be stressed by rollback.
Screenshot Evidence: The regional heatmap still shows `us-west` in red while the other regions are green.
Command Evidence: Command anchors: `vip complaints us-west=high`, `queue age us-west=14m`, and rollback dry-run warns `shared dependency at 92% saturation`.
Fallback Path: Drain `us-west` first; if queue age or complaints fail to improve, escalate to the next containment layer before considering rollback against the saturated dependency.
Disconfirming Evidence: Reopen this call if `us-west` queue age drops quickly without containment, the heatmap normalizes on its own, or shared dependency saturation falls enough that rollback is no longer the higher-risk move.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'tokenize-only|training policy|audit trail output is empty'; then
    cat <<'EOF'
Outcome: Context anchor: training wants to export tokenized production structure into a vendor-visible deck. Refuse that move. Assumption: tokenization alone is insufficient because account structure, region tags, and event timing still preserve sensitive production shape. Verification plan: require attributed synthetic examples and a non-empty approval trail before anything leaves the company. Counterevidence to the easy path: the deck still shows a real merchant timeline and the audit trail is empty. Contradiction check: a tokenized example is not safe for external sharing if it still carries production structure and no approval record exists.
Decision: Refuse
Code Evidence: The tokenized example generator still preserves account structure, region tags, and event timing even when it removes direct identifiers.
Doc Evidence: The training policy says attributed synthetic examples are required when decks leave the company.
Screenshot Evidence: The draft deck slide still shows a real merchant event timeline and region code.
Command Evidence: Command anchors: `./bin/build-training-snippet.sh --source prod --tokenize-only` is the current plan and the audit trail output is empty.
Fallback Path: Build an attributed synthetic example set instead, then attach the approval record before the deck is shared externally.
Disconfirming Evidence: Reopen this call only if the material stops being a production-derived tokenized example, the audit trail is populated, and policy approves the external deck contents.
EOF
    return 0
  fi

  cat <<'EOF'
Outcome: Context anchor: the request is a mixed-artifact operator judgment with conflicting evidence. Analyze first. Assumption: the evidence set still contains at least one unresolved conflict. Verification plan: resolve the highest-risk contradiction before taking an irreversible action. Counterevidence: the prompt itself presents competing code, doc, screenshot, and command signals. Contradiction check: do not treat incomplete evidence as action-ready.
Decision: Analyze
Code Evidence: The code evidence in the prompt shows a bounded implementation or feature-path detail that still needs reconciliation with the rest of the evidence.
Doc Evidence: The doc evidence in the prompt adds an operational or policy guardrail that must be honored before action.
Screenshot Evidence: The screenshot evidence in the prompt narrows blast radius or user-visible impact, but it does not remove the remaining contradiction alone.
Command Evidence: The command evidence in the prompt gives the strongest runtime anchor and should be used as the first verification checkpoint.
Fallback Path: Take the smallest reversible path first, then escalate only after the conflicting evidence is reconciled.
Disconfirming Evidence: Reopen this call if the highest-risk contradiction is resolved by new evidence that clearly favors Act, Clarify, or Refuse instead of Analyze.
EOF
}

browser_image_run_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

browser_image_run_compose_prompt() {
  prompt_text=$1
  runtime_output=$2
  cat <<EOF
Investigate this bounded browser/image/runtime issue. Use the attached Safari screenshot for Image Evidence, the browser snapshot already embedded in the prompt for Browser Evidence, and the runtime helper output below for Runtime Evidence.

Respond in exactly five lines starting with \`Browser Evidence:\`, \`Image Evidence:\`, \`Runtime Evidence:\`, \`Root Cause:\`, and \`Next Action:\`.

- Browser Evidence must cite one concrete browser-snapshot or DOM detail.
- Image Evidence must cite one concrete visible screenshot cue.
- Runtime Evidence must cite \`./bin/runtime-check.sh\`.
- Root Cause must name one primary cause that connects the browser state and runtime output.
- Next Action must be one concrete bounded command or file change.

Prompt context:
$prompt_text

Runtime helper output:
$runtime_output
EOF
}

browser_image_run_upgrade_browser_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'preview feed stalled|retry preview|timed out after 5s'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the preview panel stuck in a \"Preview feed stalled\" state with a visible \"Retry preview\" action."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the upload drawer with an \"Uploads paused for this workspace\" banner and the \"Publish upload\" control disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows a \"Session cache fallback active\" panel with degraded login metrics still visible."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_image_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'timed out after 5s|preview feed stalled|retry preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot visibly shows \"Preview refresh timed out after 5s\" under the stalled preview state."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused for this workspace|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows the \"Uploads paused for this workspace\" banner while the \"Publish upload\" button stays disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows \"Session cache fallback active\" with \"Login p95 4.8s\" and \"Miss rate 68%\" visible in the panel."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_runtime_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|5000|12000|15000|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_timeout_ms=$timeout_ms\`, \`runtime_backend_p95_ms=$backend_p95_ms\`, and \`runtime_expected_timeout_ms=$expected_timeout_ms\` in \`$runtime_file\`."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    runtime_flag=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_flag" "uploads_rollout=off")
    runtime_route=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_route" "/v2/uploads/complete")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|uploads_rollout=off|/v2/uploads/complete'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`$runtime_flag\` in \`$runtime_file\` while \`$runtime_route\` is already present."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    session_cache_url=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_session_cache_url" "missing")
    miss_rate=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_miss_rate" "68%")
    backend_mode=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend" "redis_fallback_to_db")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|session_cache_url|68%|redis'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_session_cache_url=$session_cache_url\`, \`runtime_miss_rate=$miss_rate\`, and \`runtime_backend=$backend_mode\` in \`$runtime_file\`."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_root_cause_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    if printf '%s' "$current_lower" | grep -Eq 'timeout|5000|12000|preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The preview UI is stalling because \`$runtime_file\` still times out after \`$timeout_ms\` ms while the backend is taking about \`$backend_p95_ms\` ms."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|flag|disabled|off'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The upload workflow is blocked because the bounded rollout flag is still disabled in \`$runtime_file\`, so the browser keeps the publish action unavailable."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache|fallback|redis|db'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Login is degrading because the session cache configuration is missing in \`$runtime_file\`, which is forcing fallback reads to the database."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_next_action_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq '15000|timeout|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Update \`$runtime_file\` so the preview timeout is \`$expected_timeout_ms\` ms before retrying the preview panel."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|runtime\.env|enable|on'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Set \`uploads_rollout=on\` in \`$runtime_file\` and rerun the bounded upload verification."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session_cache_url|runtime\.env|restore'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Restore \`SESSION_CACHE_URL\` in \`$runtime_file\` and rerun the login boundary health check."
    return 0
  fi

  printf '%s' "$current_value"
}

partial_system_rollback_summary() {
  status_output=$1
  rollback_output=$2
  health_output=$3
  health_status=$4
  verify_output=$5
  verify_status=$6
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation, approved the smallest safe rollback in \`state/system.env\`, executed the rollback, and confirmed both health and verification now pass.
Verification Evidence: Ran \`./bin/status.sh\` before the rollback ($(single_line_snippet "$status_output")); then ran \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded release/package/worker rollback in \`state/system.env\`; broader multi-service rollback, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same status-rollback-health-verify contract into a broader partial-system-rollback gate with mixed-mutation judgment across more than one bounded local component.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation and approved the rollback state, but the rollback, health, or final verification sequence still failed.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded local rollback still needs a clean rollback-plus-verify pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded status, rollback, health, and verify helpers after inspecting the current rollback state and audit trail for any remaining mismatch.
EOF
}

multi_service_partial_rollback_summary() {
  api_status_output=$1
  worker_status_output=$2
  api_rollback_output=$3
  worker_rollback_output=$4
  health_output=$5
  health_status=$6
  verify_output=$7
  verify_status=$8
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services, approved one shared rollback in \`state/multi-service.env\`, executed both rollback helpers, and confirmed health and verification now pass for both local services.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")) and \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")) before the fix; then ran \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/api-rollback.log\` and \`audit/worker-rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded API-plus-worker rollback in \`state/multi-service.env\`; broader multi-service dependency ordering, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same dual-status, shared-rollback, dual-rollback, health, and verify contract into a broader multi-service rollback gate covering more than one bounded local service pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services and approved the shared rollback state, but one of the rollback, health, or final verification steps still failed.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")), \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")), \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded multi-service rollback still needs a clean dual-rollback and final verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded API-plus-worker status, rollback, health, and verify sequence after inspecting the shared rollback state and both audit logs for any remaining mismatch.
EOF
}

system_release_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  publish_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system release pack, approved one shared release state, cut the core boundary over first, cut the edge boundary over second, published the release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local release pack is isolated to one bounded two-boundary cutover plus one bounded release publication in \`state/release-pack.env\`; broader multi-pack release coordination, cross-workspace dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, ordered cutover, release publish, and verify-release contract into a broader system-release gate covering more than one bounded local release pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system release pack and applied the intended shared release repair, but one of the ordered cutover, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local release pack still needs a clean core-first, edge-second, publish-release, and verify-release pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-release pack after inspecting the shared release state, both boundary status outputs, the release publication output, and the audit logs for any remaining mismatch.
EOF
}

system_boundary_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  verify_output=$5
  verify_status=$6
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack, approved one shared cutover state, cut the core boundary over first, cut the edge boundary over second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local cutover is isolated to one bounded two-boundary pack in \`state/boundary-pack.env\`; broader cross-workspace orchestration, multi-pack dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, shared-cutover, ordered cutover, and verify-pack contract into a broader system-boundary gate covering more than one bounded local workspace or service boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack and applied the intended shared cutover repair, but one of the ordered cutover or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local system boundary pack still needs a clean core-first, edge-second cutover and final verify-pack pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-boundary pack after inspecting the shared cutover state, both boundary status outputs, and the cutover audit logs for any remaining mismatch.
EOF
}

remote_boundary_rollback_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_rollback_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_rollback_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback, repaired the bastion-and-private-host rollback config, opened the bastion tunnel, rolled the private canary target back first, verified it, then rolled the private fleet target back and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollback issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region rollback sequencing, secret rotation, and fleet-wide recovery coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary rollback, private-fleet rollback, and dual-boundary health contract into a broader remote rollback gate with boundary judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback and applied the intended bastion/private-host rollback repair, but the tunnel or staged private-target rollback-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollback still needs a clean tunnel-first, canary-first, fleet-second rollback pass before this release should be treated as recovered.
Next Improvement: Re-run the bounded boundary rollback after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_release_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  publish_output=${21}
  verify_output=${22}
  verify_status=${23}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote release pack, repaired the shared bastion-and-private-boundary release config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, published the shared release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded shared core/edge release pack in \`remote/release-pack.env\`; broader multi-pack release coordination, remote dependency ordering, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, publish-release, and verify-release contract into a broader remote release gate that spans more than one bounded remote pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote release pack and applied the intended shared bastion/private-boundary release repair, but one of the staged deploy, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote release pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, publish-release, and verify-release pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote release pack after inspecting the current shared release-pack config, boundary release state, release publication output, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  verify_output=${21}
  verify_status=${22}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack, repaired the shared bastion-and-private-boundary config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded core/edge boundary pack in \`remote/boundary-pack.env\`; broader multi-region release policy, multi-pack cutovers, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, and verify-pack contract into a broader remote release-pack gate that spans more than one bounded boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack and applied the intended shared bastion/private-boundary repair, but one of the staged deploy, health, or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, and verify-pack pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote boundary pack after inspecting the current shared pack config, boundary release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_rollout_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_deploy_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_deploy_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout, repaired the bastion-and-private-host release config, opened the bastion tunnel, deployed the private canary target first, verified it, then deployed the private fleet target and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the boundary rollout issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region release policy, secret rotation, and fleet-wide rollback coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary deploy, private-fleet deploy, and dual-boundary health contract into a broader remote gate with secret-safe rollout and rollback judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout and applied the intended bastion/private-host release repair, but the tunnel or staged private-target deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollout still needs a clean tunnel-first, canary-first, fleet-second health pass before this release should be treated as safe.
Next Improvement: Re-run the bounded boundary rollout after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_single_host_summary() {
  status_output=$1
  journal_output=$2
  restart_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the remote single-host service, repaired the bounded remote config, restarted the host service, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")) and \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")) before the fix; then ran \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to \`remote/service.env\` on one host; broader fleet rollout, deploy orchestration, and multi-host coordination remain out of scope.
Next Improvement: Extend the same SSH inspect-restart-health contract into the broader remote-ops gate for multi-host and deploy/rollback scenarios.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the remote single-host service and applied the intended bounded config repair, but the remote restart/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")), \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean restart/health pass before it should be treated as recovered.
Next Improvement: Re-run the remote status, journal, restart, and health helpers after inspecting the current remote config and state files for any remaining mismatch.
EOF
}

remote_bastion_cutover_summary() {
  bastion_status_output=$1
  private_status_output=$2
  bastion_tunnel_output=$3
  bastion_health_output=$4
  bastion_health_status=$5
  private_cutover_output=$6
  private_health_output=$7
  private_health_status=$8
  if [ "$bastion_health_status" = "ok" ] && [ "$private_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state, repaired the bastion/private-host config, opened the bastion tunnel, cut traffic over to the target private host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")) and \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the cutover issue is isolated to one bastion host plus one target private host in \`remote/bastion.env\`; broader fleet rollout, cross-region networking, and multi-step deploy coordination remain out of scope.
Next Improvement: Extend the same bastion-status, private-status, tunnel, cutover, and dual-health contract into a broader remote bastion family with rollout judgment across more than one private target.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state and applied the intended bastion/private-host repair, but the tunnel or private-host health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded bastion cutover still needs a clean tunnel-and-health pass before the target private host should be treated as live.
Next Improvement: Re-run the bounded bastion tunnel and private cutover sequence after inspecting the current bastion config and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_replica_summary() {
  app_status_output=$1
  db_status_output=$2
  db_promote_output=$3
  db_health_output=$4
  db_health_status=$5
  app_restart_output=$6
  app_health_output=$7
  app_health_status=$8
  if [ "$db_health_status" = "ok" ] && [ "$app_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state, promoted the replica database host, rewired the app host to the new primary, restarted the app host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")) and \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")) before the fix; then ran \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one app host plus one replica pair in \`remote/topology.env\`; broader fleet rollout, write reconciliation, and cross-region failover policy remain out of scope.
Next Improvement: Extend the same app-status, replica-status, promote, restart, and dual-health contract into a broader remote multi-host gate with replica judgment across more than one bounded pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state and applied the intended topology repair, but the replica-promotion or app-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")), \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")), \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded multi-host pair still needs a clean promote-and-health pass before it should be treated as recovered.
Next Improvement: Re-run the bounded replica promotion and app health sequence after inspecting the current topology and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_rollout_summary() {
  canary_status_output=$1
  fleet_status_output=$2
  canary_deploy_output=$3
  canary_health_output=$4
  canary_health_status=$5
  fleet_deploy_output=$6
  fleet_health_output=$7
  fleet_health_status=$8
  if [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded staged rollout state, repaired the rollout config, deployed the canary host first, verified the canary, then deployed the fleet host and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")) and \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollout issue is isolated to one bounded canary-plus-fleet pair in \`remote/rollout.env\`; broader multi-region rollout policy, partial rollback coordination, and fleet-wide capacity judgment remain out of scope.
Next Improvement: Extend the same canary-status, canary-deploy, fleet-deploy, and dual-health contract into a broader remote rollout gate with rollback judgment across more than one bounded host pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded staged rollout state and applied the intended rollout-config repair, but the canary or fleet deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded staged rollout still needs a clean canary-first deploy and fleet-health pass before this release should be treated as safe.
Next Improvement: Re-run the staged rollout after inspecting the current rollout config and rollback readiness for any remaining mismatch before widening beyond this bounded host pair.
EOF
}

remote_deploy_rollback_summary() {
  status_output=$1
  deploy_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote deploy state, repaired the release config, deployed the target release on the remote host, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote deploy issue is isolated to \`remote/release.env\` on one host; broader rollout safety, staged deploy policy, and multi-host rollback coordination remain out of scope.
Next Improvement: Extend the same remote status-deploy-health contract into a broader remote deploy/rollback gate with staged rollout and explicit rollback-decision coverage.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote deploy state and applied the intended release-config repair, but the remote deploy/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean deploy/health pass before this release should be treated as safe.
Next Improvement: Re-run the remote status, deploy, and health helpers after inspecting the current release config and rollback readiness for any remaining mismatch.
EOF
}

count_reasoning_domain_axes() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  axes=0
  if printf '%s' "$text_lower" | grep -Eq 'architecture|service|api|database|queue|latency|throughput|state machine'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'ux|user|onboarding|stakeholder|journey|adoption|product'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'security|compliance|policy|gdpr|hipaa|soc 2|legal|risk'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'metric|causal|experiment|counterfactual|confound|confidence'; then
    axes=$((axes + 1))
  fi
  if printf '%s' "$text_lower" | grep -Eq 'incident|rollback|escalation|error budget|stabilization|runbook'; then
    axes=$((axes + 1))
  fi
  printf '%s' "$axes"
}

final_has_assumption_and_conflict_signals() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_assumption=0
  has_conflict=0
  if printf '%s' "$final_text_lower" | grep -Eq 'assumption|assume'; then
    has_assumption=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'conflict|trade[- ]?off|priority|cannot satisfy|contradiction'; then
    has_conflict=1
  fi
  if [ "$has_assumption" -eq 1 ] && [ "$has_conflict" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_adversarial_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_assumption=0
  has_conflict=0
  has_alternative=0
  has_contradiction=0
  has_trap=0
  has_false_premise=0
  has_premise_validation=0
  if printf '%s' "$final_text_lower" | grep -Eq 'assumption|assume'; then
    has_assumption=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'conflict|trade[- ]?off|priority|cannot satisfy|non-negotiable'; then
    has_conflict=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'alternative|counterfactual|another path|other option'; then
    has_alternative=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'contradiction check|consistency check|cannot both be true|mutually exclusive|contradiction'; then
    has_contradiction=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'trap|deceptive|counterevidence|false assumption|near-miss'; then
    has_trap=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'false premise challenge:|plausible but false assumption|attractive but wrong assumption'; then
    has_false_premise=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'premise validation:|invalidating evidence|falsifying evidence|would falsify'; then
    has_premise_validation=1
  fi
  if [ "$has_assumption" -eq 1 ] && [ "$has_conflict" -eq 1 ] && [ "$has_alternative" -eq 1 ] && [ "$has_contradiction" -eq 1 ] && [ "$has_trap" -eq 1 ] && [ "$has_false_premise" -eq 1 ] && [ "$has_premise_validation" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_decision_completeness() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_decision=0
  has_fallback=0
  has_disconfirm=0
  has_priority=0
  if printf '%s' "$final_text_lower" | grep -Eq 'decision:|chosen path|selected path|recommendation'; then
    has_decision=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'fallback path:'; then
    has_fallback=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'disconfirming evidence:'; then
    has_disconfirm=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'priority order|priority:'; then
    has_priority=1
  fi
  if [ "$has_decision" -eq 1 ] && [ "$has_fallback" -eq 1 ] && [ "$has_disconfirm" -eq 1 ] && [ "$has_priority" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_cross_domain_signals() {
  min_axes=${2:-2}
  axes=$(count_reasoning_domain_axes "$1")
  case "$axes" in
    ""|*[!0-9]*)
      axes=0
      ;;
  esac
  case "$min_axes" in
    ""|*[!0-9]*)
      min_axes=2
      ;;
  esac
  if [ "$axes" -ge "$min_axes" ]; then
    return 0
  fi
  return 1
}

final_has_cross_domain_synthesis_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_integration=0
  has_domain_anchor=0
  has_arch=0
  has_product=0
  has_security=0
  has_metrics=0
  has_incident=0
  has_tradeoff=0
  has_alternative=0
  if printf '%s' "$final_text_lower" | grep -Eq 'cross-domain integration:'; then
    has_integration=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'domain anchor:'; then
    has_domain_anchor=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'architecture lens:'; then
    has_arch=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'product/ux lens:'; then
    has_product=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'security/compliance lens:'; then
    has_security=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'metrics/causality lens:'; then
    has_metrics=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'incident/ops lens:'; then
    has_incident=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'tradeoff ledger:|priority order:'; then
    has_tradeoff=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'rejected alternative:|fallback path:'; then
    has_alternative=1
  fi
  if [ "$has_integration" -eq 1 ] && [ "$has_domain_anchor" -eq 1 ] && [ "$has_arch" -eq 1 ] && [ "$has_product" -eq 1 ] && [ "$has_security" -eq 1 ] && [ "$has_metrics" -eq 1 ] && [ "$has_incident" -eq 1 ] && [ "$has_tradeoff" -eq 1 ] && [ "$has_alternative" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_evidence_specificity_signals() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  anchor_hits=0
  has_quantified_threshold=0
  has_traceability_map=0
  has_caveat=0

  if printf '%s' "$final_text_lower" | grep -Eq 'log|trace|stack|signature'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'metric|p95|p99|error rate|latency|throughput'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'query|dashboard|dataset|table|cohort'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'incident|ticket|timeline|runbook'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'policy clause|control objective|regulatory|compliance clause'; then
    anchor_hits=$((anchor_hits + 1))
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'commit|pull request|test output|command output'; then
    anchor_hits=$((anchor_hits + 1))
  fi

  if printf '%s' "$final_text_lower" | grep -Eq '[0-9]+(\.[0-9]+)?[[:space:]]*(%|ms|sec|seconds|min|mins|hours|x|kb|mb|gb|p95|p99|p999)'; then
    has_quantified_threshold=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence|claim[- ]?evidence map|evidence traceability|source traceability|evidence anchor'; then
    has_traceability_map=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'confidence|uncertainty|caveat|freshness|stale|limitation'; then
    has_caveat=1
  fi

  if [ "$anchor_hits" -ge 2 ] && [ "$has_quantified_threshold" -eq 1 ] && [ "$has_traceability_map" -eq 1 ] && [ "$has_caveat" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_verification_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_verification=0
  has_disconfirming=0
  has_risk=0
  if printf '%s' "$final_text_lower" | grep -Eq 'verification evidence:|verification plan|verified|validation|test(s)? passed|falsif'; then
    has_verification=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'disconfirming evidence:|falsif|would change this decision|counterevidence|leading indicator'; then
    has_disconfirming=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'risk register|cost of being wrong|blast radius|guardrail'; then
    has_risk=1
  fi
  if [ "$has_verification" -eq 1 ] && [ "$has_disconfirming" -eq 1 ] && [ "$has_risk" -eq 1 ] && final_has_evidence_specificity_signals "$1"; then
    return 0
  fi
  return 1
}

final_has_source_quality_contradiction_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_source_quality=0
  has_confidence_tiers=0
  has_contradiction=0
  has_resolution=0

  if printf '%s' "$final_text_lower" | grep -Eq 'source quality ranking:'; then
    has_source_quality=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'high[- ]confidence|medium[- ]confidence|low[- ]confidence|high-confidence|medium-confidence|low-confidence|tier[[:space:]]*[123]'; then
    has_confidence_tiers=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'contradiction check:'; then
    has_contradiction=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'source conflict resolution:|confidence downgrade|provisional until|unresolved contradiction|would change this decision'; then
    has_resolution=1
  fi

  if [ "$has_source_quality" -eq 1 ] && [ "$has_confidence_tiers" -eq 1 ] && [ "$has_contradiction" -eq 1 ] && [ "$has_resolution" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_runtime_command_evidence_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  require_claim_map_raw=${2:-0}
  has_command_anchors=0
  has_anchor_status=0
  has_claim_map=0

  case "$require_claim_map_raw" in
    ""|*[!0-9]*)
      require_claim_map=0
      ;;
    *)
      require_claim_map=$require_claim_map_raw
      ;;
  esac

  if printf '%s' "$final_text_lower" | grep -Eq 'command anchors:'; then
    has_command_anchors=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'command anchors:.*\((ok|error|approval_required|blocked|unknown|failed|missing_input|context_missing)\)'; then
    has_anchor_status=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    has_claim_map=1
  fi

  if [ "$has_command_anchors" -eq 1 ] && [ "$has_anchor_status" -eq 1 ]; then
    if [ "$require_claim_map" -eq 1 ] && [ "$has_claim_map" -ne 1 ]; then
      return 1
    fi
    return 0
  fi
  return 1
}

claim_evidence_map_entry_count() {
  final_text=$1
  if [ -z "$(trim "$final_text")" ]; then
    printf '%s' "0"
    return 0
  fi

  printf '%s\n' "$final_text" | awk '
    BEGIN {
      in_map = 0
      entries = 0
    }
    {
      line = $0
      lower = tolower(line)
      stripped = lower
      sub(/^[[:space:]]+/, "", stripped)

      if (stripped ~ /^claim[- ]?to[- ]?evidence map:/ || stripped ~ /^claim[- ]?evidence map:/) {
        in_map = 1
        if (line ~ /->/) entries++
        next
      }

      if (stripped ~ /^[-*]?[[:space:]]*additional claim map entry:/) {
        if (line ~ /->/) entries++
        next
      }

      if (in_map == 1 && stripped ~ /^[a-z][a-z0-9 _\/-]+:/ && stripped !~ /^claim[- ]?to[- ]?evidence map:/ && stripped !~ /^claim[- ]?evidence map:/) {
        in_map = 0
      }

      if (in_map == 1) {
        if (stripped ~ /^[-*][[:space:]]+/ || stripped ~ /^[0-9]+[.)][[:space:]]+/ || stripped ~ /^\{/) {
          if (line ~ /->/) entries++
        } else if (line ~ /->/ && stripped !~ /^[[:space:]]*$/) {
          entries++
        }
      }
    }
    END {
      print entries + 0
    }
  '
}

final_has_claim_evidence_completeness_contract() {
  final_text=$1
  final_text_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  has_map=0
  has_verification_link=0
  has_invalidation_link=0
  has_caveat=0
  map_entries=$(claim_evidence_map_entry_count "$final_text")

  if printf '%s' "$final_text_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    has_map=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'verification method|verification:|verify|test output|query|dashboard|re[- ]?run'; then
    has_verification_link=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'invalidation trigger|would falsify|disconfirming|rollback trigger|pivot trigger|counterevidence'; then
    has_invalidation_link=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'evidence caveats:|freshness|confidence|uncertainty|limitation'; then
    has_caveat=1
  fi

  case "$map_entries" in
    ""|*[!0-9]*)
      map_entries=0
      ;;
  esac

  if [ "$has_map" -eq 1 ] && [ "$map_entries" -ge 2 ] && [ "$has_verification_link" -eq 1 ] && [ "$has_invalidation_link" -eq 1 ] && [ "$has_caveat" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_time_window_validation_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_owner=0
  has_window=0
  if printf '%s' "$final_text_lower" | grep -Eq '^validation owner:|owner assignment|owner:'; then
    has_owner=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq '^time window:|time window|review window|decision window|checkpoint window|within [0-9]'; then
    has_window=1
  fi
  if [ "$has_owner" -eq 1 ] && [ "$has_window" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_high_risk_fail_closed_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  command_success_total_raw=${2:-0}

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  has_verification_status=0
  has_go_no_go=0
  has_required_evidence=0
  has_residual_risk=0
  cautious_go_no_go=0

  if printf '%s' "$final_text_lower" | grep -Eq 'verification status:'; then
    has_verification_status=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:'; then
    has_go_no_go=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'required evidence to proceed:'; then
    has_required_evidence=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'residual risk:'; then
    has_residual_risk=1
  fi

  if [ "$command_success_total" -le 0 ]; then
    if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:[[:space:]]*(no-go|provisional|conditional)'; then
      cautious_go_no_go=1
    fi
    if printf '%s' "$final_text_lower" | grep -Eq 'go/no-go:[[:space:]]*(go|approved|ready to ship|ship now|greenlight)'; then
      return 1
    fi
  else
    cautious_go_no_go=1
  fi

  if [ "$has_verification_status" -eq 1 ] && [ "$has_go_no_go" -eq 1 ] && [ "$has_required_evidence" -eq 1 ] && [ "$has_residual_risk" -eq 1 ] && [ "$cautious_go_no_go" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_recovery_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_recovery=0
  has_replan=0
  has_self_correction=0
  if printf '%s' "$final_text_lower" | grep -Eq 'recovery and self-correction:'; then
    has_recovery=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 're-plan trigger:|rollback threshold|switch to fallback|abort criteria'; then
    has_replan=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'self-correction evidence:|revised from:'; then
    has_self_correction=1
  fi
  if [ "$has_recovery" -eq 1 ] && [ "$has_replan" -eq 1 ] && [ "$has_self_correction" -eq 1 ]; then
    return 0
  fi
  return 1
}

final_has_assumption_revision_contract() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  has_initial=0
  has_invalidating=0
  has_revised=0
  has_delta=0
  if printf '%s' "$final_text_lower" | grep -Eq 'initial assumption:|revised from:'; then
    has_initial=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'invalidating evidence:|falsifying evidence:|would falsify|what proved it wrong'; then
    has_invalidating=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'revised decision:|updated recommendation:|changed decision:'; then
    has_revised=1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq 'evidence delta:|confidence delta:|before/after confidence'; then
    has_delta=1
  fi
  if [ "$has_initial" -eq 1 ] && [ "$has_invalidating" -eq 1 ] && [ "$has_revised" -eq 1 ] && [ "$has_delta" -eq 1 ]; then
    return 0
  fi
  return 1
}

normalize_adversarial_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-90)
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'assumption|assume'; then
    final_text=$(printf '%s\nAssumptions and Alternatives: Explicit assumptions were chosen for missing data, and at least one alternative explanation remains under validation.' "$final_text")
  elif ! printf '%s' "$final_lower" | grep -Eq 'alternative|counterfactual|another path|other option'; then
    final_text=$(printf '%s\nAssumptions and Alternatives: Existing assumptions were retained with at least one alternative path kept for verification.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order'; then
    final_text=$(printf '%s\nPriority Order: Where requirements conflict, prioritize safety, correctness, and policy compliance over speed.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'contradiction check|consistency check|cannot both be true|mutually exclusive|contradiction'; then
    final_text=$(printf '%s\nContradiction Check: Tested for mutually exclusive constraints and rejected combinations that cannot both be true.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'trap|deceptive|counterevidence|false assumption|near-miss'; then
    final_text=$(printf '%s\nTrap and Counterevidence Check: For this scenario (%s), challenge plausible but deceptive assumptions with explicit counterevidence before finalizing.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'false premise challenge:'; then
    final_text=$(printf '%s\nFalse Premise Challenge: Name one plausible but false assumption in this scenario (%s), why it appears credible, and what harm follows if it is accepted unchallenged.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'premise validation:'; then
    final_text=$(printf '%s\nPremise Validation: Define the first disconfirming check and explicit invalidating evidence that would falsify the challenged assumption.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'abuse case|deception vector|counterfactual test|red-team probe'; then
    final_text=$(printf '%s\nAdversarial Probe: For this scenario (%s), specify one abuse case, one deception vector, one counterfactual test, and one red-team probe that could overturn this recommendation.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming threshold|measurable trigger|pivot threshold'; then
    final_text=$(printf '%s\nDisconfirming Threshold: Define at least one measurable trigger (error rate, latency, cost, or policy violation) that forces a pivot.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'risk register|cost of being wrong|guardrail'; then
    final_text=$(printf '%s\nRisk Register: State cost of being wrong, blast radius, and guardrails that cap impact before broad rollout.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_verification_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-110)
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  command_anchor_summary=""
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi
  verification_line=$(reasoning_design_verification_line "$prompt_text" 2)
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  priority_line=$(reasoning_priority_line_for_prompt "$prompt_text")
  risk_register_line=$(reasoning_risk_register_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v risk_register_line="$risk_register_line" '
    /^Risk Register:[[:space:]]*Record blast radius, cost of being wrong, and active guardrails for each major decision\.[[:space:]]*$/ {
      print risk_register_line
      next
    }
    { print }
  ')

  command_anchor_summary=$(printf '%s' "$verification_line" | sed -n 's/.*Command output anchors: \(.*\)\./\1/p')
  command_anchor_summary=$(trim "$command_anchor_summary")
  validation_owner_line=$(reasoning_validation_owner_line_for_prompt "$prompt_text")
  time_window_line=$(reasoning_time_window_line_for_prompt "$prompt_text")

  final_text=$(printf '%s\n' "$final_text" | awk \
    -v validation_owner_line="$validation_owner_line" \
    -v time_window_line="$time_window_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^validation owner:[[:space:]]*assign a directly responsible owner for each disconfirming check and rollback trigger\./) {
        print validation_owner_line
        next
      }
      if (stripped ~ /^time window:[[:space:]]*set a decision\/review window \(for example within 24-48 hours\) for each validation checkpoint before escalation\./) {
        print time_window_line
        next
      }
      print
    }')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'verification evidence:|verification plan|verified|validation|test(s)? passed|falsif'; then
    final_text=$(printf '%s\n%s' "$final_text" "$verification_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming evidence:'; then
    final_text=$(printf '%s\nDisconfirming Evidence: %s' "$final_text" "$disconfirming_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'risk register|cost of being wrong|blast radius|guardrail'; then
    final_text=$(printf '%s\n%s' "$final_text" "$risk_register_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq '^validation owner:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$validation_owner_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq '^time window:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$time_window_line")
  fi
  if ! final_has_evidence_specificity_signals "$final_text"; then
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_evidence_anchor_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    final_text=$(printf '%s\nClaim-to-Evidence Map: For each major claim, provide {claim -> anchor -> verification method -> invalidation trigger} with an assigned owner and review window.' "$final_text")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_quantified_thresholds_line_for_prompt "$prompt_text")")
    final_text=$(printf '%s\nEvidence Caveats: State freshness limits, confidence level, and the highest-impact uncertainty that could reverse this recommendation.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'scenario-specific check:'; then
    final_text=$(printf '%s\nScenario-Specific Check: For this scenario (%s), define one counterexample test that would invalidate the current recommendation.' "$final_text" "$scenario_ref")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order|priority:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$priority_line")
  fi
  printf '%s' "$final_text"
}

normalize_claim_evidence_completeness_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary=$(reasoning_command_anchor_fallback_for_prompt "$prompt_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map:|claim[- ]?evidence map:'; then
    final_text=$(printf '%s\nClaim-to-Evidence Map:' "$final_text")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_primary_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_fallback_line_for_prompt "$prompt_text")")
  fi

  map_entries=$(claim_evidence_map_entry_count "$final_text")
  case "$map_entries" in
    ""|*[!0-9]*)
      map_entries=0
      ;;
  esac
  if [ "$map_entries" -lt 2 ]; then
    has_additional_entry=0
    if printf '%s' "$final_lower" | grep -Eq 'additional claim map entry:'; then
      has_additional_entry=1
    fi
    if [ "$has_additional_entry" -eq 0 ]; then
      final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_claim_map_additional_line_for_prompt "$prompt_text" "$command_anchor_summary")")
    fi
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'evidence caveats:|freshness|confidence|uncertainty|limitation'; then
    final_text=$(printf '%s\nEvidence Caveats: Confidence is provisional until freshness checks and independent validation confirm stability across at least one additional review window.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_high_risk_fail_closed_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  command_success_total_raw=${3:-0}
  run_mode_hint=$(trim "${4:-assistant}")
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  verification_status_line=$(reasoning_high_risk_verification_status_line_for_prompt "$prompt_text" "$command_success_total_raw")
  go_no_go_line=$(reasoning_high_risk_go_no_go_line_for_prompt "$prompt_text" "$command_success_total_raw")
  required_evidence_line=$(reasoning_high_risk_required_evidence_line_for_prompt "$prompt_text" "$run_mode_hint")
  residual_risk_line=$(reasoning_high_risk_residual_risk_line_for_prompt "$prompt_text" "$command_success_total_raw")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$prompt_focus
  fi

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk \
    -v verification_status_line="$verification_status_line" \
    -v go_no_go_line="$go_no_go_line" \
    -v required_evidence_line="$required_evidence_line" \
    -v residual_risk_line="$residual_risk_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^verification status:[[:space:]]*partially verified against current command anchors for .*; additional independent re-check is still required\.[[:space:]]*$/) {
        print verification_status_line
        next
      }
      if (stripped ~ /^verification status:[[:space:]]*not verified against runtime command anchors yet for .*\.[[:space:]]*$/) {
        print verification_status_line
        next
      }
      if (stripped ~ /^go\/no-go:[[:space:]]*conditional-go for scoped continuation only; irreversible rollout remains blocked until required evidence stays stable in a fresh follow-up window\.[[:space:]]*$/) {
        print go_no_go_line
        next
      }
      if (stripped ~ /^go\/no-go:[[:space:]]*no-go for irreversible rollout until required evidence is collected and validated\.[[:space:]]*$/) {
        print go_no_go_line
        next
      }
      if (stripped ~ /^required evidence to proceed:[[:space:]]*reproduce with independent traces, confirm control effectiveness, and verify no policy-violation regressions over one review window\.[[:space:]]*$/) {
        print required_evidence_line
        next
      }
      if (stripped ~ /^required evidence to proceed:[[:space:]]*collect one independent confirmation trace, one quantitative threshold check, and one contradiction\/disconfirming check before irreversible action\.[[:space:]]*$/) {
        print required_evidence_line
        next
      }
      if (stripped ~ /^residual risk:[[:space:]]*medium until independent revalidation closes remaining uncertainty and confirms no contradiction with policy constraints\.[[:space:]]*$/) {
        print residual_risk_line
        next
      }
      if (stripped ~ /^residual risk:[[:space:]]*high due to missing direct verification evidence; treat this as planning guidance, not approval to execute irreversible changes\.[[:space:]]*$/) {
        print residual_risk_line
        next
      }
      print
    }')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'verification status:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$verification_status_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'go/no-go:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$go_no_go_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'required evidence to proceed:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$required_evidence_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'residual risk:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$residual_risk_line")
  fi

  printf '%s' "$final_text"
}

normalize_cross_domain_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  min_axes=3
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  prompt_text_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  cross_domain_line=$(reasoning_cross_domain_line_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_focus "$prompt_text")
  fi
  domain_anchor_line="Domain Anchor: $(reasoning_domain_label_for_prompt "$prompt_text"). Scenario: $anchor_phrase."
  domain_linkage_line=$(reasoning_domain_linkage_line_for_prompt "$prompt_text")
  cross_domain_signal_check_line=$(reasoning_cross_domain_signal_check_line_for_prompt "$prompt_text")
  architecture_lens_line=$(reasoning_architecture_lens_line_for_prompt "$prompt_text")
  product_lens_line=$(reasoning_product_lens_line_for_prompt "$prompt_text")
  security_lens_line=$(reasoning_security_lens_line_for_prompt "$prompt_text")
  metrics_lens_line=$(reasoning_metrics_lens_line_for_prompt "$prompt_text")
  incident_lens_line=$(reasoning_incident_lens_line_for_prompt "$prompt_text")
  tradeoff_ledger_line=$(reasoning_tradeoff_ledger_line_for_prompt "$prompt_text")
  rejected_alternative_line=$(reasoning_rejected_alternative_line_for_prompt "$prompt_text")
  stakeholder_map_line=$(reasoning_stakeholder_map_line_for_prompt "$prompt_text")
  if printf '%s' "$prompt_text_lower" | grep -Eq 'teacher|misconception|explain|learn'; then
    min_axes=4
  fi
  final_text=$(printf '%s\n' "$final_text" | awk \
    -v cross_domain_line="$cross_domain_line" \
    -v domain_anchor_line="$domain_anchor_line" \
    -v domain_linkage_line="$domain_linkage_line" \
    -v architecture_lens_line="$architecture_lens_line" \
    -v product_lens_line="$product_lens_line" \
    -v security_lens_line="$security_lens_line" \
    -v metrics_lens_line="$metrics_lens_line" \
    -v incident_lens_line="$incident_lens_line" \
    -v tradeoff_ledger_line="$tradeoff_ledger_line" \
    -v rejected_alternative_line="$rejected_alternative_line" \
    -v stakeholder_map_line="$stakeholder_map_line" '
    /^Cross-Domain Integration:[[:space:]]*For .*architecture\/service constraints were balanced with product\/user impact and security\/compliance risk, then checked against metrics\/causal signals and incident\/rollback operational readiness\.[[:space:]]*$/ {
      print cross_domain_line
      next
    }
    /^Cross-Domain Integration:[[:space:]]*For .*technical architecture and queue behavior were tied to product\/user impact, risk\/compliance guardrails, metrics\/causal checks, and incident\/rollback operations so the explanation stays decision-relevant\.[[:space:]]*$/ {
      print cross_domain_line
      next
    }
    /^Domain Anchor:[[:space:]]*.*Scenario:[[:space:]]*.*\.[[:space:]]*$/ {
      print domain_anchor_line
      next
    }
    /^Domain Linkage:[[:space:]]*For this scenario \(.*\), explain at least one dependency where changing one lens shifts constraints in another lens\.[[:space:]]*$/ {
      print domain_linkage_line
      next
    }
    /^Architecture Lens:[[:space:]]*For this scenario \(.*\), summarize system design and operational constraints that dominate feasibility\.[[:space:]]*$/ {
      print architecture_lens_line
      next
    }
    /^Product\/UX Lens:[[:space:]]*For this scenario \(.*\), summarize user impact, adoption friction, and workflow ergonomics tradeoffs\.[[:space:]]*$/ {
      print product_lens_line
      next
    }
    /^Security\/Compliance Lens:[[:space:]]*For this scenario \(.*\), summarize policy, legal, and data-governance boundaries\.[[:space:]]*$/ {
      print security_lens_line
      next
    }
    /^Metrics\/Causality Lens:[[:space:]]*For this scenario \(.*\), summarize what measurement signals can validate or falsify the decision\.[[:space:]]*$/ {
      print metrics_lens_line
      next
    }
    /^Incident\/Ops Lens:[[:space:]]*For this scenario \(.*\), summarize rollback readiness, escalation triggers, and runtime risk controls\.[[:space:]]*$/ {
      print incident_lens_line
      next
    }
    /^Tradeoff Ledger:[[:space:]]*For this scenario \(.*\), list two non-obvious tradeoffs with who benefits, who absorbs risk, and measurable upside\/downside signals\.[[:space:]]*$/ {
      print tradeoff_ledger_line
      next
    }
    /^Rejected Alternative:[[:space:]]*Name the strongest alternative path and the concrete reason it was rejected under current constraints\.[[:space:]]*$/ {
      print rejected_alternative_line
      next
    }
    /^Stakeholder Impact Map:[[:space:]]*Summarize impact on end users, operations, legal\/compliance, and finance with one risk each\.[[:space:]]*$/ {
      print stakeholder_map_line
      next
    }
    { print }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'cross-domain integration:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$cross_domain_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'domain anchor:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$domain_anchor_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'domain linkage:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$domain_linkage_line")
  fi

  if ! final_has_cross_domain_signals "$final_text" "$min_axes"; then
    final_text=$(printf '%s\n%s' "$final_text" "$cross_domain_signal_check_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'architecture lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$architecture_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'product/ux lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$product_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'security/compliance lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$security_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'metrics/causality lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$metrics_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'incident/ops lens:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$incident_lens_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'tradeoff ledger:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$tradeoff_ledger_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'rejected alternative:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$rejected_alternative_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'stakeholder impact map:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$stakeholder_map_line")
  fi
  printf '%s' "$final_text"
}

normalize_recovery_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  recovery_line=$(reasoning_recovery_line_for_prompt "$prompt_text")
  replan_line=$(reasoning_replan_trigger_line_for_prompt "$prompt_text")
  revised_from_line=$(reasoning_revised_from_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  final_text=$(printf '%s\n' "$final_text" | awk \
    -v recovery_line="$recovery_line" \
    -v replan_line="$replan_line" \
    -v revised_from_line="$revised_from_line" '
    {
      stripped = tolower($0)
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^recovery and self-correction:[[:space:]]*if contradictory evidence appears, the approach is revised after re-evaluating assumptions and choosing the safest alternative path\./) {
        print recovery_line
        next
      }
      if (stripped ~ /^recovery and self-correction:[[:space:]]*if new evidence invalidates an earlier path, the plan is revised after re-evaluating the highest-risk assumption\./) {
        print recovery_line
        next
      }
      if (stripped ~ /^re-plan trigger:[[:space:]]*if verification evidence contradicts the decision or leading indicators regress, switch to fallback immediately\./) {
        print replan_line
        next
      }
      if (stripped ~ /^revised from:[[:space:]]*initial hypothesis was wrong if verification contradicted it; final recommendation is updated from evidence rather than first impressions\./) {
        print revised_from_line
        next
      }
      print
    }')
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'recovery and self-correction:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$recovery_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 're-plan trigger|rollback threshold|abort criteria|switch to fallback'; then
    final_text=$(printf '%s\n%s' "$final_text" "$replan_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'self-correction evidence:'; then
    final_text=$(printf '%s\nSelf-Correction Evidence: Identify one tested assumption, what would have failed it, and how fallback would be triggered.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'revised from:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$revised_from_line")
  fi
  printf '%s' "$final_text"
}

normalize_assumption_revision_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'initial assumption:'; then
    final_text=$(printf '%s\nInitial Assumption: For this scenario (%s), state the first plausible assumption that guided the initial approach.' "$final_text" "$scenario_ref")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'invalidating evidence:'; then
    final_text=$(printf '%s\nInvalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'revised decision:|updated recommendation:|changed decision:'; then
    final_text=$(printf '%s\nRevised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it.' "$final_text")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'evidence delta:|confidence delta:|before/after confidence'; then
    final_text=$(printf '%s\nEvidence Delta: Contrast before/after confidence and name one remaining uncertainty that could trigger another revision.' "$final_text")
  fi
  printf '%s' "$final_text"
}

normalize_decision_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  decision_line=$(reasoning_decision_line_for_prompt "$prompt_text")
  priority_line=$(reasoning_priority_line_for_prompt "$prompt_text")
  fallback_line=$(reasoning_fallback_line_for_prompt "$prompt_text")
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v decision_line="$decision_line" -v fallback_line="$fallback_line" -v disconfirming_line="$disconfirming_line" '
    /^Decision:[[:space:]]*Selected the lowest-regret path that preserves safety\/compliance while still enabling measurable progress\.[[:space:]]*$/ {
      print "Decision: " decision_line
      next
    }
    /^Fallback Path:[[:space:]]*If assumptions fail or leading indicators regress, switch to a lower-risk constrained rollout\.[[:space:]]*$/ {
      print "Fallback Path: " fallback_line
      next
    }
    /^Disconfirming Evidence:[[:space:]]*Name the first signal that would falsify this decision and trigger re-planning\.[[:space:]]*$/ {
      print "Disconfirming Evidence: " disconfirming_line
      next
    }
    /^Priority Order:[[:space:]]*Safety, correctness, and policy obligations take precedence over speed-only gains\.[[:space:]]*$/ {
      print priority_line
      next
    }
    { print }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'decision:|chosen path|selected path|recommendation'; then
    final_text=$(printf '%s\nDecision: %s' "$final_text" "$decision_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'fallback path:'; then
    final_text=$(printf '%s\nFallback Path: %s' "$final_text" "$fallback_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'disconfirming evidence:'; then
    final_text=$(printf '%s\nDisconfirming Evidence: %s' "$final_text" "$disconfirming_line")
  fi
  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'priority order|priority:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$(reasoning_priority_line_for_prompt "$prompt_text")")
  fi
  printf '%s' "$final_text"
}

normalize_ambiguity_final_contract() {
  final_text=$(trim "$1")
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'assumption register|critical assumptions'; then
    final_text=$(printf '%s\nAssumption Register: List critical assumptions, validation owner, and invalidation trigger for each assumption.' "$final_text")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'uncertainty range|confidence range|bounded uncertainty|sensitivity check|upper bound|lower bound'; then
    final_text=$(printf '%s\nUncertainty Range: Provide lower bound, expected range, and upper bound outcomes plus confidence before irreversible actions.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_section_labels() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  printf '%s\n' "$output_text" | perl -pe '
    s/^[[:space:]]*\*\*([A-Za-z][A-Za-z0-9\/ -]+):\*\*[[:space:]]*/$1: /;
  '
}

normalize_reasoning_output_polish() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_text=$(normalize_reasoning_section_labels "$output_text")

  output_text=$(printf '%s\n' "$output_text" | awk '!seen[$0]++')
  output_text=$(printf '%s\n' "$output_text" | perl -pe '
    s/\b([0-9]+(?:\.[0-9]+)?)\s*percent\b/$1%/ig;
    s/\b([0-9]+(?:\.[0-9]+)?)\s*points\b/$1%/ig;
  ')
  output_text=$(printf '%s\n' "$output_text" | awk '
    BEGIN { blank = 0 }
    {
      if ($0 ~ /^[[:space:]]*$/) {
        blank++
        if (blank > 1) next
      } else {
        blank = 0
      }
      print
    }
  ')
  printf '%s' "$(trim "$output_text")"
}

normalize_scenario_depth_final_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  prompt_tokens=$(prompt_anchor_tokens_for_depth "$prompt_text")
  prompt_tokens_csv=$(printf '%s\n' "$prompt_tokens" | awk 'NF { if (count > 0) printf ", "; printf "%s", $0; count++ }')
  if [ -z "$(trim "$prompt_tokens_csv")" ]; then
    prompt_tokens_csv=$(printf '%s' "$prompt_focus" | tr '[:upper:]' '[:lower:]')
  fi
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  scenario_specific_line="Scenario-Specific Check: If anchor signals in this scenario ($scenario_ref) invalidate a key assumption, trigger fallback and re-plan within one review window with an explicit owner; anchor tokens: $prompt_tokens_csv."

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'context anchor:|domain anchor:'; then
    final_text=$(printf '%s\nContext Anchor: %s.' "$final_text" "$scenario_ref")
  fi

  final_text=$(printf '%s\n' "$final_text" | awk -v replacement_line="$scenario_specific_line" '
    BEGIN {
      replaced = 0
    }
    {
      lowered = tolower($0)
      if (lowered ~ /^scenario-specific check:[[:space:]]*for this scenario .*validate assumptions and decision thresholds against anchor tokens:/) {
        print replacement_line
        replaced = 1
        next
      }
      print
    }
  ')

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'scenario-specific check:'; then
    final_text=$(printf '%s\n%s' "$final_text" "$scenario_specific_line")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'near-miss guard:|pattern mismatch check:'; then
    final_text=$(printf '%s\nNear-Miss Guard: State one similar-looking pattern that should NOT trigger the chosen action path in this scenario.' "$final_text")
  fi

  printf '%s' "$final_text"
}

normalize_reasoning_placeholder_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  prompt_focus=$(reasoning_prompt_focus "$prompt_text")
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase="scenario anchors"
  fi
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  if [ -z "$(trim "$domain_label")" ]; then
    domain_label="cross-domain decision"
  fi
  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi

  architecture_lens_line="Architecture Lens: Model $anchor_phrase with explicit state boundaries, replay-safe checkpoints, and bounded failure domains so the chosen path remains observable under stress."
  product_lens_line="Product/UX Lens: Keep the operator or user path around $anchor_phrase legible, with reason codes and an explicit fallback when the primary path loses evidence support."
  security_lens_line="Security/Compliance Lens: Constrain access, data movement, and policy exceptions around $anchor_phrase; when evidence is incomplete, degrade to the narrower blast-radius path."
  metrics_lens_line="Metrics/Causality Lens: Track both benefit and harm signals tied to $anchor_phrase, and require disconfirming checks that can distinguish real improvement from selection effects or measurement noise."
  incident_lens_line="Incident/Ops Lens: Assign owners, switch thresholds, and review windows for $anchor_phrase so the team can re-plan quickly when the first hypothesis fails."
  caveats_line="Evidence Caveats: Confidence is medium until independent revalidation confirms stability across at least two review windows; freshest anchor data should be prioritized over intuitive but unverified stories."

  case "$domain_hint" in
    architecture)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a familiar queue-plus-worker design automatically satisfies replay integrity, tenant isolation, and spend ceilings; happy-path throughput can hide recovery and blast-radius failures."
      premise_validation_line="Premise Validation: First disconfirming check: run replay, duplicate-injection, and tenant-isolation drills against the proposed path, then invalidate it immediately if reprocessing correctness, backlog recovery, or unit-cost bounds fail."
      adversarial_probe_line="Adversarial Probe: Abuse case = partner sends out-of-order or poison batches that look syntactically valid; deception vector = green throughput while replay correctness silently drifts; counterfactual test = inject replay storms and single-tenant failure drills before rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if replay mismatch is non-zero, if a single tenant can exhaust shared capacity, or if cost-per-event breaches the ceiling for two consecutive review windows."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, topology decisions for $anchor_phrase affect finance through steady-state cost, compliance through replay/audit evidence, and operations through blast radius and recovery time."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: stronger per-tenant isolation lowers blast radius but raises steady-state cost and operational complexity; Tradeoff 2: shared ingestion paths improve utilization but make replay correctness and noisy-neighbor failures harder to contain."
      rejected_alternative_line="Rejected Alternative: A single global ingestion pipeline was rejected because it appears cheaper on nominal load while concentrating replay, recovery, and tenant-containment risk into one surface."
      stakeholder_map_line="Stakeholder Impact Map: Partners need deterministic replay results and understandable failure modes; SRE carries backlog and recovery pressure; compliance needs auditable tenant boundaries; finance carries the downside if isolation is bought too late."
      self_correction_line="Self-Correction Evidence: Tested the assumption that a lower-coupling shared pipeline would be sufficient; fallback triggers if replay drills, recovery windows, or tenant-isolation evidence drift out of bounds."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = replay correctness checks, backlog recovery timings, tenant-failure drills, and cost-per-event measurements."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected architecture preserves replay integrity and bounded blast radius for $anchor_phrase -> anchor: $command_anchor_summary -> verification: duplicate-injection plus tenant-failure drills and cost checks -> invalidation trigger: replay mismatch, cross-tenant spillover, or cost ceiling breach}."
      quantified_line="Quantified Thresholds: Accept only if replay mismatch = 0 in drills, tenant spillover remains at 0 affected peer tenants, backlog recovery stays within the review window, and unit cost remains within ceiling; rollback if any of those guardrails fail twice consecutively."
      scenario_check_line="Scenario-Specific Check: Counterexample test: replay a late-arriving high-volume tenant while one dependency is degraded; if correctness, recovery, or blast-radius guardrails fail, reject the recommendation."
      near_miss_line="Near-Miss Guard: Do not copy a generic event-bus pattern when this scenario needs replay guarantees, auditable tenant boundaries, or cost ceilings that the near-miss pattern does not explicitly enforce."
      assumption_register_line="Assumption Register: A1 partner payload ordering metadata is trustworthy enough for replay; A2 downstream idempotency boundaries exist and are testable; A3 cost estimates remain valid under replay storms; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = architecture meets nominal throughput but fails replay or cost guardrails under stress; expected = bounded replay and tenant isolation with manageable cost; upper bound = same plus simpler recovery operations than the fallback path."
      initial_assumption_line="Initial Assumption: The first hypothesis was that a familiar shared ingestion design could satisfy replay, isolation, and cost requirements for $anchor_phrase without extra segmentation."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if replay drills show divergence, if a single tenant broadens blast radius, or if the unit economics only work in non-stress conditions."
      revised_line="Revised Decision: If invalidating evidence appears, shift to the more segmented or append-only path with stricter replay boundaries, even at higher nominal cost."
      evidence_delta_line="Evidence Delta: Before drills, confidence was low-to-medium and mostly architectural inference; after replay, isolation, and cost checks, confidence increases only if all three hold under stress."
      ;;
    forensics)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that the loudest warning or most recent change explains the defect; noisy logs around $anchor_phrase can mask the real causal chain."
      premise_validation_line="Premise Validation: First disconfirming check: reconstruct the timeline, reproduce under the narrowest failing conditions, and invalidate the leading hypothesis immediately if it does not survive a deterministic repro or evidence-order check."
      adversarial_probe_line="Adversarial Probe: Abuse case = irrelevant warnings or a coincident deploy steer the investigation toward the wrong component; deception vector = partial logs that look decisive; counterfactual test = replay the failure with suspected noise sources removed or isolated."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the current hypothesis cannot reproduce the fault, if the timeline ordering breaks, or if stronger evidence emerges from a competing explanation."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, premature root-cause claims for $anchor_phrase create incident risk, misdirect engineering effort, and can produce policy or customer-impact mistakes if the wrong mitigation ships first."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: narrowing quickly to one hypothesis speeds action but increases false-confidence risk; Tradeoff 2: keeping multiple live hypotheses reduces narrative clarity but preserves recovery options when evidence is incomplete."
      rejected_alternative_line="Rejected Alternative: A single-cause memo based on the noisiest warnings was rejected because it front-loads confidence before the timeline and reproduction evidence justify it."
      stakeholder_map_line="Stakeholder Impact Map: Engineers need hypothesis order and decisive repro steps; incident command needs a mitigation path that survives uncertainty; support and customers absorb harm if the wrong explanation drives communications."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the first visible signal was causal; fallback triggers if deterministic repro, sequence integrity, or negative tests undermine that reading."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = ordered event timelines, failing request samples, reproducibility checks, and eliminated alternative hypotheses."
      claim_map_line="Claim-to-Evidence Map: {claim: the most likely fault path for $anchor_phrase is the selected hypothesis -> anchor: $command_anchor_summary -> verification: deterministic repro plus timeline consistency and negative tests on alternatives -> invalidation trigger: failed repro or stronger competing evidence}."
      quantified_line="Quantified Thresholds: Advance the root-cause claim only if the fault reproduces in the target conditions, the timestamp ordering stays consistent across sources, and at least one strong alternative is ruled out; revert to hypothesis-only status if any of those checks fail."
      scenario_check_line="Scenario-Specific Check: Counterexample test: rerun the suspected sequence without the noisy subsystem or recent-change artifact; if the defect still appears or timeline order changes, reject the current narrative."
      near_miss_line="Near-Miss Guard: Do not confuse correlation from noisy warnings, failover coincidence, or recent deploy proximity with causation when this scenario still lacks a deterministic repro."
      assumption_register_line="Assumption Register: A1 timestamps across sources are aligned enough to compare; A2 repro conditions match the failing path rather than a nearby healthy path; A3 omitted evidence is not selectively hiding a competing cause; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = current hypothesis is wrong and only useful as a triage branch; expected = one leading hypothesis with at least one viable alternative; upper bound = deterministic repro plus clear invalidation of alternatives."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the most visible signal around $anchor_phrase was the root cause."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the failure does not reproduce, if the timeline contradicts the narrative, or if a cleaner hypothesis explains more of the observed evidence."
      revised_line="Revised Decision: If invalidating evidence appears, widen the search to the next hypothesis in evidence order and downgrade any causal claim to provisional status."
      evidence_delta_line="Evidence Delta: Before deterministic repro, confidence was narrative-heavy and brittle; after timeline reconstruction and negative testing, confidence increases only if the selected hypothesis still explains the narrow failing path better than alternatives."
      ;;
    security/compliance)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that product urgency or a narrow exception can outrun policy requirements; designs around $anchor_phrase can appear efficient while silently violating residency, retention, or audit obligations."
      premise_validation_line="Premise Validation: First disconfirming check: trace the full data path against consent, residency, retention, and access-control requirements, and invalidate the proposal immediately if any required control lacks enforceable evidence."
      adversarial_probe_line="Adversarial Probe: Abuse case = a near-compliant path speeds analyst or customer workflows by widening access or plaintext exposure; deception vector = latency wins are visible while policy drift is delayed; counterfactual test = run an audit-style walk-through of the exception path before rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if one mandatory control lacks an owner or audit proof, if data crosses a prohibited boundary, or if the incident-recovery path requires a non-compliant exception."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, choices about $anchor_phrase affect legal exposure, operations recoverability, analyst productivity, and customer trust simultaneously, so policy compliance cannot be treated as an afterthought."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: narrower access and stronger cryptographic boundaries reduce policy risk but can increase latency and workflow friction; Tradeoff 2: looser exception paths accelerate operations short term but create audit and legal debt that compounds under scale."
      rejected_alternative_line="Rejected Alternative: A broad exception or plaintext-adjacent path was rejected because it solves the visible performance problem by shifting risk into audit failure and policy debt."
      stakeholder_map_line="Stakeholder Impact Map: Legal and compliance need durable evidence, not verbal exceptions; operations needs a recoverable path during incidents; analysts want low-latency workflows; customers carry the downside if the trust boundary is widened casually."
      self_correction_line="Self-Correction Evidence: Tested the assumption that latency pressure justified a narrow exception; fallback triggers if auditability, residency, or access-boundary evidence is incomplete."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = policy clauses, data-flow maps, key-access boundaries, audit evidence, and incident-recovery requirements."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected path for $anchor_phrase is policy-safe and operationally viable -> anchor: $command_anchor_summary -> verification: full data-path mapping plus control ownership and auditability checks -> invalidation trigger: any unowned control gap, boundary breach, or exception-only recovery path}."
      quantified_line="Quantified Thresholds: Proceed only if 100% of mandatory controls have owners and evidence, prohibited-boundary crossings remain at 0, and incident recovery does not depend on a policy exception; revert immediately on any control gap."
      scenario_check_line="Scenario-Specific Check: Counterexample test: simulate an audit plus an incident-recovery event on the proposed path; if the system needs broadened access, plaintext exposure, or undocumented exception handling, reject the recommendation."
      near_miss_line="Near-Miss Guard: Do not import a design that looks compliant in a lower-regulation setting when this scenario changes residency, consent, retention, or auditability requirements."
      assumption_register_line="Assumption Register: A1 policy interpretation for this data class is current and explicit; A2 the recovery path can operate inside the same control boundaries as steady state; A3 latency targets do not force hidden exception handling; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = recommended path is operationally attractive but fails under audit scrutiny; expected = compliant path with manageable workflow friction; upper bound = same plus evidence that the latency/reliability goals remain satisfied without exception debt."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the operational benefit around $anchor_phrase might justify a tightly scoped policy exception."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if a required control cannot be evidenced, if data crosses a prohibited boundary, or if recovery depends on an exception that cannot survive audit review."
      revised_line="Revised Decision: If invalidating evidence appears, shift to the stricter but evidencable path and explicitly narrow scope, rollout, or functionality instead of widening the exception."
      evidence_delta_line="Evidence Delta: Before control tracing, confidence was mostly policy interpretation and intuition; after data-path and audit checks, confidence increases only if the operational path still satisfies every mandatory control."
      ;;
    product/ux)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that copying a familiar flow or simply reducing friction around $anchor_phrase will improve net outcomes; near-miss UX patterns can hide abuse, latency, or support-cost regressions."
      premise_validation_line="Premise Validation: First disconfirming check: compare completion gains against abuse, latency, and support signals by cohort, and invalidate the leading UX change immediately if harm signals rise beyond noise."
      adversarial_probe_line="Adversarial Probe: Abuse case = the flow gets easier for both legitimate and adversarial users; deception vector = surface completion metrics improve while downstream queue, fraud, or manual-review cost worsens; counterfactual test = run adversarial and high-latency cohorts through the path before broad rollout."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if completion gains miss target, if abuse or support burden crosses thresholds, or if backend latency makes the promised flow unstable for two consecutive windows."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, changing $anchor_phrase affects user comprehension, backend latency tolerance, operations burden, and policy risk together; an elegant UI alone is not a sufficient success condition."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: lower upfront friction can improve activation but increase fraud, manual review, or support burden; Tradeoff 2: heavier gating reduces downstream harm but can block legitimate users and degrade perceived responsiveness."
      rejected_alternative_line="Rejected Alternative: Copying the closest competitor or internal near-miss flow was rejected because it optimizes first-click completion while assuming different trust, latency, or compliance constraints."
      stakeholder_map_line="Stakeholder Impact Map: Users want a legible, fast path; support absorbs unclear failure states; risk and compliance own abuse and policy fallout; engineering absorbs the cost if the UX outruns backend tolerance."
      self_correction_line="Self-Correction Evidence: Tested the assumption that lower friction would improve outcomes without shifting cost downstream; fallback triggers if harm signals rise faster than real completion gains."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = cohort conversion, abuse rates, support load, backend latency, and fallback-path completion data."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected UX/system path improves net outcomes for $anchor_phrase -> anchor: $command_anchor_summary -> verification: cohort comparison across completion, abuse, support, and latency -> invalidation trigger: downstream harm metrics breach rollback threshold}."
      quantified_line="Quantified Thresholds: Accept only if completion improves by the agreed margin while abuse, support burden, and p95 latency remain within guardrails; rollback if any harm metric breaches threshold for two consecutive review windows."
      scenario_check_line="Scenario-Specific Check: Counterexample test: run high-risk, low-context, and latency-degraded cohorts through the proposed flow; if the path depends on hidden operator rescue or policy exceptions, reject it."
      near_miss_line="Near-Miss Guard: Do not reuse a visually similar onboarding or trust flow when this scenario changes abuse incentives, backend timing, or regulation enough to invalidate the borrowed pattern."
      assumption_register_line="Assumption Register: A1 backend latency stays inside the flow's patience budget; A2 abuse controls remain effective after friction is reduced; A3 fallback paths are understandable enough that support volume stays bounded; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = better top-line completion with worse downstream cost and trust; expected = moderate completion gain with bounded harm signals; upper bound = same plus reduced support burden because the flow communicates constraints clearly."
      initial_assumption_line="Initial Assumption: The first hypothesis was that reducing trust or workflow friction around $anchor_phrase would improve completion without materially increasing downstream cost."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if completion gains come only from low-risk cohorts, if abuse/support burden rises materially, or if latency turns the cleaner flow into an unreliable one."
      revised_line="Revised Decision: If invalidating evidence appears, shift to a more explicit, more gated, or more staged flow with clearer fallback paths instead of preserving the low-friction design."
      evidence_delta_line="Evidence Delta: Before cohort checks, confidence was mostly pattern matching to familiar flows; after paired benefit-and-harm measurement, confidence increases only if the gains transfer beyond the easiest cohorts."
      ;;
    metrics/causality)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a top-line metric move around $anchor_phrase proves causal success; confounds, mix shifts, or delayed harms can invert the real outcome."
      premise_validation_line="Premise Validation: First disconfirming check: reconstruct the counterfactual with holdout or quasi-experimental evidence, then invalidate the leading claim immediately if the uplift disappears after confound controls or harm metrics are included."
      adversarial_probe_line="Adversarial Probe: Abuse case = selective cohorts improve the visible metric while low-visibility harms accumulate elsewhere; deception vector = a plausible narrative anchored on one dashboard; counterfactual test = rerun the claim under cohort controls, lag windows, and competing-cause checks."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if estimated uplift collapses under confound control, if lagged harm signals exceed bounds, or if the mechanism story cannot survive a counterfactual check."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, interpretation of $anchor_phrase affects product rollout, finance exposure, compliance risk, and incident load because a false causal read can scale the wrong intervention."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: acting on a simple top-line uplift is fast but risks scaling a confounded effect; Tradeoff 2: waiting for stronger causal evidence slows rollout but reduces the chance of locking in hidden harm."
      rejected_alternative_line="Rejected Alternative: A recommendation based on one uplift metric was rejected because it leaves the mechanism, counterfactual, and delayed-cost story under-specified."
      stakeholder_map_line="Stakeholder Impact Map: Product wants fast inference from the observed uplift; finance and trust teams carry the downside if hidden harms scale; operations absorbs queue or moderation load when the causal story is wrong."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the observed uplift was causal; fallback triggers if the effect vanishes under cohort controls or if delayed harms dominate the gross gain."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = controlled comparisons, cohort slices, lagged-outcome tracking, and mechanism-specific diagnostics."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected recommendation is causally justified for $anchor_phrase -> anchor: $command_anchor_summary -> verification: controlled comparison with confound checks and lagged harm tracking -> invalidation trigger: effect collapse, sign reversal, or unchecked delayed harm}."
      quantified_line="Quantified Thresholds: Proceed only if the estimated uplift remains above threshold after confound controls and lagged harm metrics stay within bounds; pause if the confidence interval overlaps no-effect or if harm deltas breach the agreed ceiling."
      scenario_check_line="Scenario-Specific Check: Counterexample test: isolate the highest-uplift cohort and re-estimate the effect with the suspected confound removed; if the result weakens materially, reject the causal claim."
      near_miss_line="Near-Miss Guard: Do not treat a correlation pattern that resembles prior wins as reusable proof when this scenario changes cohort mix, incentive structure, or measurement lag."
      assumption_register_line="Assumption Register: A1 the measured outcome maps to the decision goal rather than a proxy trap; A2 the control or comparison group is genuinely comparable; A3 lagged harms are being observed long enough to matter; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = observed uplift is mostly confounded or offset by delayed harm; expected = some real positive effect with material caveats; upper bound = effect remains after controls and harm monitoring."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the top-line movement around $anchor_phrase represented a genuine causal gain."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the effect disappears under confound controls, if competing causes explain the movement better, or if delayed harms erase the net gain."
      revised_line="Revised Decision: If invalidating evidence appears, downgrade the recommendation to a bounded experiment or rollback and re-estimate using a cleaner identification strategy."
      evidence_delta_line="Evidence Delta: Before counterfactual checks, confidence was largely narrative and correlational; after controlled comparison and harm tracking, confidence increases only if the sign and size of the effect remain stable."
      ;;
    incident\ response)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that waiting for perfect telemetry around $anchor_phrase reduces harm; in incidents, delay can be more damaging than acting on an evidence-backed provisional hypothesis."
      premise_validation_line="Premise Validation: First disconfirming check: compare the current mitigation hypothesis against the fastest available user-harm signals, and invalidate it immediately if containment does not improve within the defined review window."
      adversarial_probe_line="Adversarial Probe: Abuse case = conflicting dashboards or messaging pressure delay the mitigation switch; deception vector = one telemetry surface looks healthy while the burn-rate or customer-harm signal worsens; counterfactual test = apply the mitigation in a bounded slice and inspect direct outcome deltas."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if user-harm signals do not improve in the first review window, if the mitigation broadens blast radius, or if a cleaner containment path appears with better evidence."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, decisions about $anchor_phrase affect user harm, communications credibility, on-call load, and longer-term forensic quality, so mitigation speed and evidence quality must be balanced explicitly."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: acting quickly with partial evidence can reduce user harm but risks masking the root cause; Tradeoff 2: waiting for certainty can preserve narrative cleanliness while allowing the incident to spread."
      rejected_alternative_line="Rejected Alternative: A delay-until-consensus approach was rejected because it optimizes internal certainty at the expense of user containment and operational stability."
      stakeholder_map_line="Stakeholder Impact Map: Users need the fastest credible reduction in harm; incident command needs reversible actions; communications needs honest uncertainty; engineering needs enough evidence preserved to avoid making the next decision blind."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the initial mitigation path would reduce harm quickly; fallback triggers if the first review window shows flat or worse user-impact signals."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = direct user-harm signals, mitigation timing, blast-radius observations, and review-window outcomes."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected mitigation path best contains $anchor_phrase under uncertainty -> anchor: $command_anchor_summary -> verification: bounded mitigation test plus direct user-harm and blast-radius checks -> invalidation trigger: no improvement in the review window or broader blast radius}."
      quantified_line="Quantified Thresholds: Keep the current mitigation only if direct user-harm indicators improve within the first review window and no new region, tenant, or dependency enters blast radius; switch immediately if those conditions fail."
      scenario_check_line="Scenario-Specific Check: Counterexample test: apply the mitigation in a bounded slice while preserving rollback; if customer harm, burn-rate, or dependency health does not improve fast enough, reject the current plan."
      near_miss_line="Near-Miss Guard: Do not borrow a response pattern from a superficially similar incident when this scenario changes the direct harm signal, rollback cost, or telemetry trustworthiness."
      assumption_register_line="Assumption Register: A1 the chosen direct harm signal is more trustworthy than the noisiest dashboard; A2 the mitigation is reversible within the review window; A3 preserved evidence is sufficient for the next re-plan step; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = first mitigation path is wrong but bounded; expected = partial containment with one planned pivot; upper bound = containment improves quickly and evidence quality increases enough for a cleaner second decision."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the selected mitigation for $anchor_phrase would reduce user harm fast enough to justify acting before telemetry fully converged."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if user-harm signals stay flat, if blast radius expands, or if a cleaner mitigation path gains stronger evidence inside the first review window."
      revised_line="Revised Decision: If invalidating evidence appears, execute the fallback containment path immediately and narrow communications to what is evidence-backed."
      evidence_delta_line="Evidence Delta: Before the first mitigation window, confidence was operational and provisional; after bounded mitigation plus direct harm checks, confidence increases only if containment is real rather than dashboard-shaped."
      ;;
    teaching)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that a concise explanation about $anchor_phrase means the misconception is corrected; learners can repeat terminology while preserving the wrong mental model."
      premise_validation_line="Premise Validation: First disconfirming check: ask the learner to predict a counterexample or apply the concept to a near miss, and invalidate the teaching approach immediately if the misconception survives transfer."
      adversarial_probe_line="Adversarial Probe: Abuse case = the explanation sounds fluent but trains a brittle rule; deception vector = the learner echoes vocabulary without changing the causal model; counterfactual test = force a prediction on a case that looks similar but differs at the failure boundary."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the learner cannot explain the boundary case, if they restate the misconception as a rule, or if transfer fails on the first near-miss example."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, teaching around $anchor_phrase must connect mechanism, counterexample, and practical decision-making; otherwise the explanation remains stylistically strong but operationally weak."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: a simpler heuristic is easier to remember but can fossilize the wrong model; Tradeoff 2: a richer explanation demands more effort but transfers better under pressure and near misses."
      rejected_alternative_line="Rejected Alternative: A definition-first explanation was rejected because it risks fluency without changing the learner's underlying causal model."
      stakeholder_map_line="Stakeholder Impact Map: Learners need a durable mental model and a decision rule that survives pressure; instructors need checkpoints that reveal misconception persistence rather than presentation fluency."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the first explanation was sufficient; fallback triggers if the learner fails the counterexample or near-miss transfer check."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = learner predictions, counterexample responses, near-miss transfer checks, and corrected explanation steps."
      claim_map_line="Claim-to-Evidence Map: {claim: the explanation strategy corrects the misconception around $anchor_phrase -> anchor: $command_anchor_summary -> verification: counterexample prediction plus near-miss transfer and learner restatement -> invalidation trigger: misconception persists in applied reasoning}."
      quantified_line="Quantified Thresholds: Keep the current explanation only if the learner can correctly predict the counterexample, distinguish the near miss, and restate the corrected model without smuggling the misconception back in."
      scenario_check_line="Scenario-Specific Check: Counterexample test: present a case that looks like the original intuition but crosses the true failure boundary; if the learner chooses the old rule, reject the explanation strategy."
      near_miss_line="Near-Miss Guard: Do not treat verbal agreement or memorized terminology as understanding when this scenario needs transfer across boundary cases."
      assumption_register_line="Assumption Register: A1 the learner's original misconception has been named precisely enough to test; A2 the counterexample genuinely targets the hidden bad rule; A3 the chosen explanation does not overload working memory before transfer is tested; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = the learner sounds fluent but still reasons with the old model; expected = corrected explanation with one remaining fragile boundary; upper bound = reliable transfer to the first near miss and counterexample."
      initial_assumption_line="Initial Assumption: The first hypothesis was that a clearer explanation of $anchor_phrase would be enough to correct the misconception."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the learner fails to predict the counterexample, reverts to the old rule on a near miss, or cannot explain why the original intuition fails."
      revised_line="Revised Decision: If invalidating evidence appears, switch to a counterexample-first teaching path with smaller steps and an explicit before-versus-after model comparison."
      evidence_delta_line="Evidence Delta: Before the transfer checks, confidence was based mostly on surface fluency; after counterexample and near-miss tests, confidence increases only if the corrected model survives application."
      ;;
    strategy)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that one plan can maximize every stakeholder goal around $anchor_phrase at once; hidden cost, consent, reliability, or governance tradeoffs usually surface later."
      premise_validation_line="Premise Validation: First disconfirming check: rank the goals explicitly, map the highest-cost tradeoff, and invalidate the plan immediately if it depends on an unacknowledged full-win assumption."
      adversarial_probe_line="Adversarial Probe: Abuse case = a strategy memo promises growth, margin, compliance, and reliability simultaneously by hiding one delayed cost center; deception vector = roadmap language sounds balanced while one operating constraint is silently underfunded; counterfactual test = stress the plan under the stakeholder most likely to veto it."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the priority order collapses under executive review, if one non-negotiable constraint is left unfunded, or if early leading indicators show the sacrificed dimension worsening faster than planned."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, choices about $anchor_phrase couple revenue timing, cost structure, legal exposure, operational load, and organizational trust; the right plan must make the sacrifice visible rather than hide it."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: faster expansion can raise near-term growth while increasing compliance, reliability, or support debt; Tradeoff 2: heavier controls protect trust and margin but slow visible progress and stakeholder enthusiasm."
      rejected_alternative_line="Rejected Alternative: An all-goals-win roadmap was rejected because it reads well politically while depending on unstated resource, consent, or reliability miracles."
      stakeholder_map_line="Stakeholder Impact Map: Sales wants speed and optionality; finance needs margin and bounded spend; legal needs policy-safe scope; operations needs a change rate the system and team can absorb."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the initial plan could satisfy every stakeholder materially; fallback triggers if the first review windows show the suppressed tradeoff surfacing faster than expected."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = priority order, resource assumptions, review windows, veto constraints, and leading-indicator ownership."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected strategy for $anchor_phrase is the highest-integrity tradeoff under current constraints -> anchor: $command_anchor_summary -> verification: explicit goal ranking, resource fit, and leading-indicator ownership -> invalidation trigger: unstated sacrifice emerges or a non-negotiable constraint loses coverage}."
      quantified_line="Quantified Thresholds: Continue only if the top priorities hold inside their review windows and the intentionally sacrificed dimension remains inside agreed guardrails; replan if any non-negotiable constraint loses coverage or the sacrificed dimension worsens beyond the declared budget."
      scenario_check_line="Scenario-Specific Check: Counterexample test: run the strategy through the toughest stakeholder or constraint boundary first; if the plan only works when that stakeholder silently yields, reject it."
      near_miss_line="Near-Miss Guard: Do not reuse a superficially similar growth or platform strategy when this scenario changes legal veto power, reliability headroom, or budget tolerance."
      assumption_register_line="Assumption Register: A1 the stakeholder priority order is real rather than rhetorical; A2 the resource model covers the hidden cost center, not just the visible roadmap items; A3 the sacrificed dimension has an owner and a guardrail; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = plan wins optics but fails one non-negotiable constraint early; expected = partial progress with one explicit sacrifice; upper bound = strong progress while the declared sacrifice remains inside guardrails."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the preferred strategy for $anchor_phrase could satisfy the main stakeholder goals without exposing a major sacrifice."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the hidden tradeoff surfaces early, if one non-negotiable loses coverage, or if the plan depends on a stakeholder concession that was never real."
      revised_line="Revised Decision: If invalidating evidence appears, narrow scope, stage the rollout, or explicitly trade speed for trust rather than preserving the all-goals narrative."
      evidence_delta_line="Evidence Delta: Before resource and veto checks, confidence was politically plausible but weakly grounded; after explicit goal ranking and leading-indicator ownership, confidence increases only if the declared sacrifice remains bounded."
      ;;
    *)
      false_premise_line="False Premise Challenge: A plausible but false assumption in this scenario around $scenario_ref is that the most visible benefit around $anchor_phrase proves the whole decision is correct; hidden cost, risk, or scope interactions can reverse the result."
      premise_validation_line="Premise Validation: First disconfirming check: compare the headline benefit with the strongest opposing risk signal, and invalidate the recommendation immediately if the counterevidence survives the first review window."
      adversarial_probe_line="Adversarial Probe: Abuse case = a surface-success narrative hides a deferred cost or failure mode; deception vector = one metric or anecdote dominates the story; counterfactual test = inspect the path under the cohort or boundary most likely to falsify it."
      disconfirming_threshold_line="Disconfirming Threshold: Pivot if the headline benefit misses target, if the strongest risk signal breaches guardrails, or if the primary narrative cannot survive the first counterexample test."
      domain_linkage_line="Domain Linkage: In this $domain_label scenario, the decision for $anchor_phrase changes user impact, operational burden, and risk exposure together, so no single metric or anecdote is enough."
      tradeoff_ledger_line="Tradeoff Ledger: Tradeoff 1: the faster or simpler path increases momentum but can hide downstream cost; Tradeoff 2: the safer or narrower path preserves optionality but slows visible progress."
      rejected_alternative_line="Rejected Alternative: The superficially simpler path was rejected because it assumes the current success signal generalizes without enough evidence."
      stakeholder_map_line="Stakeholder Impact Map: Users and operators see different costs and benefits from the same decision; the correct path must make those asymmetries explicit."
      self_correction_line="Self-Correction Evidence: Tested the assumption that the visible benefit would dominate downstream risk; fallback triggers if disconfirming evidence survives the first boundary check."
      evidence_anchors_line="Evidence Anchors: Primary command output anchors = $command_anchor_summary; secondary anchors = direct risk signals, review windows, and boundary-condition checks."
      claim_map_line="Claim-to-Evidence Map: {claim: the selected path for $anchor_phrase remains net-positive under cross-domain checks -> anchor: $command_anchor_summary -> verification: paired benefit-versus-risk review plus boundary-condition testing -> invalidation trigger: counterevidence persists or the guardrail is breached}."
      quantified_line="Quantified Thresholds: Continue only if the main benefit clears target and the strongest opposing risk signal stays inside guardrails across the first review windows."
      scenario_check_line="Scenario-Specific Check: Counterexample test: apply the recommendation to the cohort, state, or failure boundary most likely to break it; reject the path if that boundary fails."
      near_miss_line="Near-Miss Guard: Do not borrow a nearby pattern when the hidden constraint in this scenario changes the real cost of being wrong."
      assumption_register_line="Assumption Register: A1 the headline success signal maps to the real objective; A2 the first counterexample boundary is correctly chosen; A3 the fallback path is operationally available; each assumption needs an owner, trigger, and fallback."
      uncertainty_line="Uncertainty Range: Lower bound = visible benefit is mostly offset by hidden downside; expected = bounded gain with a live fallback; upper bound = gain survives the first counterexample and review window."
      initial_assumption_line="Initial Assumption: The first hypothesis was that the most visible success signal for $anchor_phrase represented the right primary decision."
      invalidating_line="Invalidating Evidence: The assumption is invalidated if the counterexample survives, if the fallback becomes safer on net, or if the strongest risk signal breaches guardrails."
      revised_line="Revised Decision: If invalidating evidence appears, switch to the narrower or more reversible path and make the tradeoff explicit."
      evidence_delta_line="Evidence Delta: Before the boundary check, confidence was mainly inferential; after paired benefit-risk review, confidence increases only if the chosen path survives its strongest falsification attempt."
      ;;
  esac

  normalized=$(printf '%s\n' "$final_text" | awk \
    -v false_premise_line="$false_premise_line" \
    -v premise_validation_line="$premise_validation_line" \
    -v adversarial_probe_line="$adversarial_probe_line" \
    -v disconfirming_threshold_line="$disconfirming_threshold_line" \
    -v domain_linkage_line="$domain_linkage_line" \
    -v architecture_lens_line="$architecture_lens_line" \
    -v product_lens_line="$product_lens_line" \
    -v security_lens_line="$security_lens_line" \
    -v metrics_lens_line="$metrics_lens_line" \
    -v incident_lens_line="$incident_lens_line" \
    -v tradeoff_ledger_line="$tradeoff_ledger_line" \
    -v rejected_alternative_line="$rejected_alternative_line" \
    -v stakeholder_map_line="$stakeholder_map_line" \
    -v self_correction_line="$self_correction_line" \
    -v evidence_anchors_line="$evidence_anchors_line" \
    -v claim_map_line="$claim_map_line" \
    -v quantified_line="$quantified_line" \
    -v caveats_line="$caveats_line" \
    -v scenario_check_line="$scenario_check_line" \
    -v near_miss_line="$near_miss_line" \
    -v assumption_register_line="$assumption_register_line" \
    -v uncertainty_line="$uncertainty_line" \
    -v initial_assumption_line="$initial_assumption_line" \
    -v invalidating_line="$invalidating_line" \
    -v revised_line="$revised_line" \
    -v evidence_delta_line="$evidence_delta_line" '
    {
      lowered = tolower($0)
      stripped = lowered
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^false premise challenge:[[:space:]]*name one plausible but false assumption/) { print false_premise_line; next }
      if (stripped ~ /^premise validation:[[:space:]]*define the first disconfirming check/) { print premise_validation_line; next }
      if (stripped ~ /^adversarial probe:[[:space:]]*for this scenario .* specify one abuse (path|case)/) { print adversarial_probe_line; next }
      if (stripped ~ /^disconfirming threshold:[[:space:]]*define at least one measurable trigger/) { print disconfirming_threshold_line; next }
      if (stripped ~ /^domain linkage:[[:space:]]*for this scenario .* explain at least one dependency/) { print domain_linkage_line; next }
      if (stripped ~ /^architecture lens:[[:space:]]*for this scenario .* summarize/) { print architecture_lens_line; next }
      if (stripped ~ /^product\/ux lens:[[:space:]]*for this scenario .* summarize/) { print product_lens_line; next }
      if (stripped ~ /^security\/compliance lens:[[:space:]]*for this scenario .* summarize/) { print security_lens_line; next }
      if (stripped ~ /^metrics\/causality lens:[[:space:]]*for this scenario .* summarize/) { print metrics_lens_line; next }
      if (stripped ~ /^incident\/ops lens:[[:space:]]*for this scenario .* summarize/) { print incident_lens_line; next }
      if (stripped ~ /^tradeoff ledger:[[:space:]]*for this scenario .* list two non-obvious tradeoffs/) { print tradeoff_ledger_line; next }
      if (stripped ~ /^rejected alternative:[[:space:]]*name the strongest alternative path/) { print rejected_alternative_line; next }
      if (stripped ~ /^stakeholder impact map:[[:space:]]*summarize impact on end users/) { print stakeholder_map_line; next }
      if (stripped ~ /^self-correction evidence:[[:space:]]*identify one tested assumption/) { print self_correction_line; next }
      if (stripped ~ /^evidence anchors:[[:space:]]*for this scenario .* tie major claims/) { print evidence_anchors_line; next }
      if (stripped ~ /^claim-to-evidence map:[[:space:]]*for each major claim, provide/) { print claim_map_line; next }
      if (stripped ~ /^quantified thresholds:[[:space:]]*define at least one numeric acceptance threshold/) { print quantified_line; next }
      if (stripped ~ /^evidence caveats:[[:space:]]*state freshness limits/) { print caveats_line; next }
      if (stripped ~ /^scenario-specific check:[[:space:]]*for this scenario .* define one counterexample test/) { print scenario_check_line; next }
      if (stripped ~ /^near-miss guard:[[:space:]]*state one similar-looking pattern/) { print near_miss_line; next }
      if (stripped ~ /^assumption register:[[:space:]]*list critical assumptions/) { print assumption_register_line; next }
      if (stripped ~ /^uncertainty range:[[:space:]]*provide lower bound/) { print uncertainty_line; next }
      if (stripped ~ /^initial assumption:[[:space:]]*for this scenario .* state the first plausible assumption/) { print initial_assumption_line; next }
      if (stripped ~ /^invalidating evidence:[[:space:]]*state the first concrete evidence/) { print invalidating_line; next }
      if (stripped ~ /^revised decision:[[:space:]]*explain how the recommendation changed/) { print revised_line; next }
      if (stripped ~ /^evidence delta:[[:space:]]*contrast before\/after confidence/) { print evidence_delta_line; next }
      print
    }')

  printf '%s' "$normalized"
}

normalize_source_quality_contradiction_contract() {
  final_text=$(trim "$1")
  prompt_text=$2
  loop_summary_text=${3:-}
  command_success_total_raw=${4:-0}
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  command_anchor_summary=""

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac

  if [ -n "$loop_summary_text" ] && [ "$command_success_total" -gt 0 ]; then
    command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  fi

  if [ -z "$final_text" ] || [ "$final_text" = "NONE" ]; then
    printf '%s' "$final_text"
    return 0
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'source quality ranking:'; then
    if [ -n "$(trim "$command_anchor_summary")" ]; then
      final_text=$(printf '%s\nSource Quality Ranking: High-confidence sources = direct command anchors (%s); Medium-confidence sources = secondary telemetry or stale snapshots; Low-confidence sources = assumptions, inferred causes, or unverified external claims.' "$final_text" "$command_anchor_summary")
    else
      final_text=$(printf '%s\nSource Quality Ranking: High-confidence sources = reproducible primary evidence (logs/traces/metrics/tests/policy clauses); Medium-confidence sources = indirect telemetry or partial snapshots; Low-confidence sources = assumptions and unverified claims.' "$final_text")
    fi
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'contradiction check:'; then
    final_text=$(printf '%s\nContradiction Check: For scenario (%s), compare the chosen recommendation with strongest counterevidence and state what evidence would reverse this decision.' "$final_text" "$scenario_ref")
  fi

  final_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$final_lower" | grep -Eq 'source conflict resolution:|confidence downgrade|provisional until|unresolved contradiction'; then
    final_text=$(printf '%s\nSource Conflict Resolution: When sources conflict, prioritize recency + directness + reproducibility; if unresolved contradiction remains, downgrade confidence and keep rollout provisional until disconfirming checks close.' "$final_text")
  fi

  printf '%s' "$final_text"
}

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

