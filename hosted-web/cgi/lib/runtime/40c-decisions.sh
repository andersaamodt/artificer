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

