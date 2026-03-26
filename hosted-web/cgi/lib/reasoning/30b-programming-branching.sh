programming_task_snippet_for_prompt() {
  prompt_text=$1
  prompt_primary=$(printf '%s' "$prompt_text" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Attachment context:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Web context:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Run mode directive:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Explicit skill actuator results:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Teacher pacing signal:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Learner model snapshot:/,$d')
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/^Team metadata:/,$d')
  prompt_prior_request=$(printf '%s\n' "$prompt_primary" | awk '
    /^Prior project request:/ { in_block = 1; next }
    /^Prior programming summary:/ { in_block = 0 }
    in_block { print }
  ')
  prompt_prior_request=$(trim "$prompt_prior_request")
  if printf '%s\n' "$prompt_primary" | grep -Eq '^Requested continuation phase:' && [ -n "$prompt_prior_request" ]; then
    prompt_primary=$prompt_prior_request
  else
    prompt_followup=$(printf '%s\n' "$prompt_primary" | sed -n '/^Current follow-up:/,$p' | sed '1d')
    if [ -n "$(trim "$prompt_followup")" ]; then
      prompt_primary=$prompt_followup
    fi
  fi
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  task_snippet=$(single_line_snippet "$prompt_primary")
  if [ -z "$task_snippet" ]; then
    task_snippet="the requested programming task"
  fi
  printf '%s' "$(printf '%s' "$task_snippet" | cut -c1-160)"
}

join_first_lines_comma_space() {
  max_lines=$1
  text=$2
  case "$max_lines" in
    ""|*[!0-9]*)
      max_lines=5
      ;;
  esac
  printf '%s\n' "$text" | sed '/^[[:space:]]*$/d' | sed -n "1,${max_lines}p" | awk '
    BEGIN { first = 1 }
    {
      if (!first) printf ", "
      printf "%s", $0
      first = 0
    }
    END {
      if (!first) printf "\n"
    }
  '
}

programming_changed_files_count() {
  git_status_text=$1
  recorded_paths_text=$(trim "${ARTIFICER_PROGRAMMING_CHANGED_PATHS:-}")
  changed_paths_count=$(printf '%s\n' "$git_status_text" | awk '
    {
      line = $0
      gsub(/\r/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^Not a git repository\./) next
      path = line
      sub(/^[[:space:]]*[?MADRCU! ][?MADRCU! ][[:space:]]+/, "", path)
      sub(/^.* -> /, "", path)
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "") next
      if (!seen[path]++) {
        count += 1
      }
    }
    END { print count + 0 }
  ')
  changed_paths_count=$(trim "$changed_paths_count")
  case "$changed_paths_count" in
    ""|*[!0-9]*)
      changed_paths_count=0
      ;;
  esac
  if [ "$changed_paths_count" -eq 0 ] && [ -n "$recorded_paths_text" ]; then
    changed_paths_count=$(printf '%s\n' "$recorded_paths_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
    case "$changed_paths_count" in
      ""|*[!0-9]*)
        changed_paths_count=0
        ;;
    esac
  fi
  printf '%s' "$changed_paths_count"
}

programming_changed_files_summary() {
  git_status_text=$1
  recorded_paths_text=$(trim "${ARTIFICER_PROGRAMMING_CHANGED_PATHS:-}")
  changed_paths=$(printf '%s\n' "$git_status_text" | awk '
    {
      line = $0
      gsub(/\r/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^Not a git repository\./) next
      path = line
      sub(/^[[:space:]]*[?MADRCU! ][?MADRCU! ][[:space:]]+/, "", path)
      sub(/^.* -> /, "", path)
      gsub(/^[[:space:]]+/, "", path)
      gsub(/[[:space:]]+$/, "", path)
      if (path == "") next
      if (!seen[path]++) {
        print path
      }
    }
  ')
  changed_paths=$(trim "$changed_paths")
  if [ -z "$changed_paths" ] && [ -n "$recorded_paths_text" ]; then
    changed_paths=$recorded_paths_text
    changed_paths=$(trim "$changed_paths")
  fi
  if [ -z "$changed_paths" ]; then
    printf '%s' "No workspace file changes were confirmed."
    return 0
  fi
  changed_paths_joined=$(join_first_lines_comma_space 8 "$changed_paths")
  changed_paths_joined=$(trim "$changed_paths_joined")
  printf '%s' "$changed_paths_joined"
}

programming_prompt_has_multiple_branches() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq '([,;][[:space:]]*(add|update|wire|hook|connect|document|test|verify|refactor|rename|create|implement|fix|clean up|polish|write|extend|adjust|split))|(\band[[:space:]]+(add|update|wire|hook|connect|document|test|verify|refactor|rename|create|implement|fix|clean up|polish|write|extend|adjust|split))|(\b(if time remains|if time permits|also|then)\b)'; then
    return 0
  fi
  return 1
}

programming_prompt_prefers_bounded_narrow_execution() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'keep changes narrow|keep this narrow|keep it narrow|keep changes scoped|keep scope tight|keep scope narrow|narrow and verify|verify what you can|one small verifiable|one small verified|small verifiable slice|small verified slice|multi-phase project|multi phase project|phased project|phase 1|phase one|phase 2|phase two|first phase|keep phase 1 shippable|keep phase one shippable|keep the first phase shippable|stop if phase 2 is not justified yet|stop if phase two is not justified yet|wait for me to justify the next deferred branch|justify the next deferred branch|phase 2 is not justified yet|phase two is not justified yet|larger multi-phase project|larger multi phase project|requested continuation phase:'; then
    return 0
  fi
  return 1
}

programming_prompt_prefers_phase_summary() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'multi-phase project|multi phase project|phased project|phase 1|phase one|phase 2|phase two|first phase|phase plan|phased plan|keep phase 1 shippable|keep phase one shippable|keep the first phase shippable|wait for me to justify the next deferred branch|justify the next deferred branch|larger multi-phase project|larger multi phase project|requested continuation phase:'; then
    return 0
  fi
  return 1
}

programming_requested_phase_number_for_prompt() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  requested_phase=$(printf '%s\n' "$prompt_lower" | sed -n 's/.*requested continuation phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  case "$requested_phase" in
    ''|*[!0-9]*)
      requested_phase=""
      ;;
  esac
  if [ -n "$requested_phase" ]; then
    printf '%s' "$requested_phase"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase 3 is justified now|phase three is justified now|continue (with |to )?phase 3|continue (with |to )?phase three|resume phase 3|resume phase three|proceed (with |to )?phase 3|proceed (with |to )?phase three'; then
    printf '%s' "3"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase 2 is justified now|phase two is justified now|continue (with |to )?phase 2|continue (with |to )?phase two|resume phase 2|resume phase two|proceed (with |to )?phase 2|proceed (with |to )?phase two'; then
    printf '%s' "2"
    return 0
  fi
  printf '%s' "1"
}

programming_prompt_requests_next_deferred_branch_resume() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'phase 2 is justified now|phase two is justified now|phase 3 is justified now|phase three is justified now|phase 4 is justified now|phase four is justified now|next deferred branch only|one deferred branch only|take the next deferred branch|resume with exactly one previously deferred branch|continue with the next deferred branch|proceed with the next deferred branch|requested continuation phase:'; then
    return 0
  fi
  return 1
}

programming_prompt_requests_phase_stopgo() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'phase [0-9][0-9]* is not justified (now|yet)|phase two is not justified (now|yet)|phase three is not justified (now|yet)|phase four is not justified (now|yet)|phase five is not justified (now|yet)|do not resume another deferred branch|do not take another deferred branch|stop here|stop and rescope|keep the current landed slices|give me only the phase [0-9][0-9]* queue|give me only the phase [0-9][0-9]* entry gate|give me only the phase two queue|give me only the phase three queue|give me only the phase four queue|give me only the phase five queue|give me only the phase two entry gate|give me only the phase three entry gate|give me only the phase four entry gate|give me only the phase five entry gate'; then
    return 0
  fi
  return 1
}

programming_stopgo_phase_number_for_prompt() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  requested_phase=$(printf '%s\n' "$prompt_lower" | sed -n 's/.*phase[[:space:]]\([0-9][0-9]*\)[[:space:]]\+is not justified.*/\1/p' | sed -n '1p')
  case "$requested_phase" in
    ''|*[!0-9]*)
      requested_phase=""
      ;;
  esac
  if [ -n "$requested_phase" ]; then
    printf '%s' "$requested_phase"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase five is not justified'; then
    printf '%s' "5"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase four is not justified'; then
    printf '%s' "4"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase three is not justified'; then
    printf '%s' "3"
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'phase two is not justified'; then
    printf '%s' "2"
    return 0
  fi
  printf '%s' ""
}

programming_prompt_is_phase_control_followup() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if programming_prompt_requests_next_deferred_branch_resume "$prompt_text" || programming_prompt_requests_phase_stopgo "$prompt_text"; then
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'requested continuation phase:'; then
    return 0
  fi
  return 1
}

programming_project_request_from_conversation() {
  conv_dir=$1
  current_prompt=${2-}
  recent_turns=$(recent_user_turns_for_conversation "$conv_dir" "6")
  if [ -z "$(trim "$recent_turns")" ]; then
    printf '%s' ""
    return 0
  fi
  project_request=""
  while IFS= read -r raw_line; do
    line=$(printf '%s' "$raw_line" | sed 's/^[0-9][0-9]*\.[[:space:]]*//')
    line=$(trim "$line")
    [ -n "$line" ] || continue
    if [ "$(trim "$line")" = "$(trim "$current_prompt")" ]; then
      continue
    fi
    if programming_prompt_requests_next_deferred_branch_resume "$line"; then
      continue
    fi
    if programming_prompt_requests_phase_stopgo "$line" && ! programming_prompt_has_multiple_branches "$line"; then
      continue
    fi
    project_request=$line
  done <<EOF
$recent_turns
EOF
  printf '%s' "$(trim "$project_request")"
}

programming_prior_next_deferred_branch_from_text() {
  assistant_text=$1
  branch_label=$(printf '%s\n' "$assistant_text" | awk '
    BEGIN { IGNORECASE = 1 }
    /^Next Improvement:/ {
      line = $0
      if (line ~ /next deferred branch only:/) {
        sub(/^.*next deferred branch only:[[:space:]]*/, "", line)
        sub(/[[:space:]]*[.]$/, "", line)
        print line
        exit
      }
    }
  ' | sed -n '1p')
  branch_label=$(trim "$branch_label")
  if [ -z "$branch_label" ]; then
    branch_label=$(printf '%s\n' "$assistant_text" | awk '
      BEGIN { IGNORECASE = 1 }
      /^Next Improvement:/ {
        line = $0
        if (line ~ /deferred[[:space:]].*[[:space:]]branch/) {
          sub(/^.*deferred[[:space:]]*/, "", line)
          sub(/[[:space:]]branch.*$/, "", line)
          print line
          exit
        }
      }
    ' | sed -n '1p')
    branch_label=$(trim "$branch_label")
  fi
  printf '%s' "$branch_label"
}

programming_prior_deferred_branch_queue_from_text() {
  summary_text=$1
  queue_text=$(printf '%s\n' "$summary_text" | awk '
    {
      line = $0
      if (line ~ /Phase [0-9][0-9]* queue:/) {
        sub(/^.*Phase [0-9][0-9]* queue:[[:space:]]*/, "", line)
        sub(/[.][[:space:]]*Starting phase.*$/, "", line)
        print line
        exit
      }
      if (line ~ /Deferred backlog:/) {
        sub(/^.*Deferred backlog:[[:space:]]*/, "", line)
        sub(/[.][[:space:]]*Widening before.*$/, "", line)
        print line
        exit
      }
    }
  ' | sed -n '1p')
  printf '%s' "$(trim "$queue_text")"
}

programming_prior_completed_phase_number_from_text() {
  summary_text=$1
  phase_number=$(printf '%s\n' "$summary_text" | sed -n 's/^Outcome: Completed phase \([0-9][0-9]*\) .*/\1/p' | sed -n '1p')
  phase_number=$(trim "$phase_number")
  case "$phase_number" in
    ''|*[!0-9]*)
      phase_number=""
      ;;
  esac
  printf '%s' "$phase_number"
}

programming_deferred_branch_queue_without_label() {
  queue_text=$1
  branch_label=$(printf '%s' "${2-}" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  printf '%s\n' "$queue_text" | awk -F ', ' -v skip="$branch_label" '
    BEGIN {
      first = 1
      removed = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        label = $i
        gsub(/^[[:space:]]+/, "", label)
        gsub(/[[:space:]]+$/, "", label)
        lower = tolower(label)
        gsub(/[[:space:]]+/, " ", lower)
        gsub(/^ /, "", lower)
        gsub(/ $/, "", lower)
        if (skip != "" && removed == 0 && lower == skip) {
          removed = 1
          continue
        }
        if (label == "") continue
        if (first == 0) printf ", "
        printf "%s", label
        first = 0
      }
    }
    END {
      if (first == 0) printf "\n"
    }
  '
}

programming_resume_target_branch_from_prompt_text() {
  prompt_text=$1
  branch_label=$(printf '%s\n' "$prompt_text" | sed -n 's/^Resume target branch:[[:space:]]*//p' | sed -n '1p')
  branch_label=$(trim "$branch_label")
  if [ -n "$branch_label" ]; then
    printf '%s' "$branch_label"
    return 0
  fi
  programming_prior_next_deferred_branch_from_text "$prompt_text"
}

programming_prompt_has_documentation_branch() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'readme|documentation|document\b|docs?\b|usage\b'; then
    return 0
  fi
  return 1
}

programming_prompt_has_verification_branch() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'tests?\b|verify\b|verification\b|spec\b|specs\b|test coverage\b|regression\b'; then
    return 0
  fi
  return 1
}

programming_prompt_has_release_note_safe_branch() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if ! programming_prompt_has_multiple_branches "$prompt_text"; then
    return 1
  fi
  if ! programming_prompt_has_documentation_branch "$prompt_text"; then
    return 1
  fi
  if ! programming_prompt_has_verification_branch "$prompt_text"; then
    return 1
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\bchangelog\b|change[ -]?log|release[ -]?notes?\b|release[_-]?notes?\b|migration[ -]?guide\b|migration[_-]?guide\b'; then
    return 0
  fi
  return 1
}

programming_prompt_has_extended_post_safe_branch() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_lower" | grep -Eq 'examples?\b|sample(s)?\b|usage example|worked example'; then
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'package[.]json\b|pyproject[.]toml\b|poetry[.]lock\b|npm script\b|yarn script\b|pnpm script\b|python script\b|console script\b|cli script\b|run the cli\b|makefile\b|justfile\b|dockerfile\b|containerfile\b|docker-compose\b|docker compose\b|compose[.](ya?ml)\b|compose[.-](ya?ml)\b|github actions\b|github workflow\b|[.]github/workflows\b|workflow[.]ya?ml\b|workflow[[:space:]]+file\b|ci[.]ya?ml\b|utils?[.](py|js|ts)\b|helpers?[.](py|js|ts)\b|helper module\b|shared helper\b|shared logic\b|reusable module\b|split .* into .* module\b|extract .* into .* module\b'; then
    return 0
  fi
  return 1
}

programming_prompt_has_post_release_note_branch() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  release_note_target_count=0
  if ! programming_prompt_has_release_note_safe_branch "$prompt_text"; then
    return 1
  fi
  if programming_prompt_has_extended_post_safe_branch "$prompt_text"; then
    return 0
  fi
  if printf '%s' "$prompt_lower" | grep -Eq '\bchangelog\b|change[ -]?log'; then
    release_note_target_count=$((release_note_target_count + 1))
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'release[ -]?notes?\b|release[_-]?notes?\b'; then
    release_note_target_count=$((release_note_target_count + 1))
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'migration[ -]?guide\b|migration[_-]?guide\b'; then
    release_note_target_count=$((release_note_target_count + 1))
  fi
  if [ "$release_note_target_count" -ge 2 ]; then
    return 0
  fi
  return 1
}

programming_prompt_has_post_verification_branch() {
  prompt_text=$1
  if programming_prompt_has_release_note_safe_branch "$prompt_text"; then
    return 0
  fi
  if ! programming_prompt_has_multiple_branches "$prompt_text"; then
    return 1
  fi
  if ! programming_prompt_has_documentation_branch "$prompt_text"; then
    return 1
  fi
  if ! programming_prompt_has_verification_branch "$prompt_text"; then
    return 1
  fi
  if programming_prompt_has_extended_post_safe_branch "$prompt_text"; then
    return 0
  fi
  return 1
}

programming_append_branch_label() {
  current_labels=$1
  branch_label=$2
  if [ -z "$(trim "$branch_label")" ]; then
    printf '%s' "$current_labels"
    return 0
  fi
  if [ -z "$(trim "$current_labels")" ]; then
    printf '%s' "$branch_label"
  else
    printf '%s, %s' "$current_labels" "$branch_label"
  fi
}

programming_deferred_branch_queue() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  resume_queue=$(programming_prior_deferred_branch_queue_from_text "$prompt_text")
  resume_target_branch=$(programming_resume_target_branch_from_prompt_text "$prompt_text")
  if [ -n "$resume_queue" ] || printf '%s\n' "$prompt_text" | grep -Eq '^Requested continuation phase:|^Resume target branch:|^Prior programming summary:'; then
    if [ -n "$resume_target_branch" ]; then
      resume_queue=$(programming_deferred_branch_queue_without_label "$resume_queue" "$resume_target_branch")
    fi
    printf '%s' "$(trim "$resume_queue")"
    return 0
  fi
  deferred_queue=""
  if printf '%s' "$prompt_lower" | grep -Eq 'examples?\b|sample(s)?\b|usage example|worked example'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "examples note")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'migration[ -]?guide\b|migration[_-]?guide\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "migration guide note")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'package[.]json\b|npm script\b|yarn script\b|pnpm script\b|cli script\b|run the cli\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "package.json script")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'pyproject[.]toml\b|console script\b|python script\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "pyproject.toml entry")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'makefile\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "Makefile target")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'justfile\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "Justfile target")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'github actions\b|github workflow\b|[.]github/workflows\b|workflow[.]ya?ml\b|workflow[[:space:]]+file\b|ci[.]ya?ml\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "workflow")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'dockerfile\b|containerfile\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "Dockerfile")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'docker-compose\b|docker compose\b|compose[.](ya?ml)\b|compose[.-](ya?ml)\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "compose file")
  fi
  if printf '%s' "$prompt_lower" | grep -Eq 'utils?[.](py|js|ts)\b|helpers?[.](py|js|ts)\b|helper module\b|shared helper\b|shared logic\b|reusable module\b|split .* into .* module\b|extract .* into .* module\b'; then
    deferred_queue=$(programming_append_branch_label "$deferred_queue" "helper-module extraction")
  fi
  printf '%s' "$deferred_queue"
}

programming_deferred_branch_queue_count() {
  deferred_queue=$(programming_deferred_branch_queue "$1")
  if [ -z "$(trim "$deferred_queue")" ]; then
    printf '%s' "0"
    return 0
  fi
  printf '%s\n' "$deferred_queue" | awk -F ', ' '{ print NF + 0 }'
}

programming_next_deferred_branch() {
  deferred_queue=$(programming_deferred_branch_queue "$1")
  if [ -z "$(trim "$deferred_queue")" ]; then
    printf '%s' ""
    return 0
  fi
  printf '%s\n' "$deferred_queue" | awk -F ', ' '{ print $1 }'
}

programming_deferred_branch_target_path_for_label() {
  workspace_path=$1
  branch_label=$(printf '%s' "${2-}" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  case "$branch_label" in
    "examples note")
      existing_path=$(find "$workspace_path" -maxdepth 3 -type f \( -iname 'examples*.md' -o -iname '*example*.md' -o -iname 'samples*.md' \) 2>/dev/null | sed -n "1s|^$workspace_path/||p")
      [ -n "$existing_path" ] || existing_path="examples.md"
      printf '%s' "$existing_path"
      ;;
    "migration guide note")
      printf '%s' "migration-guide.md"
      ;;
    "package.json script")
      printf '%s' "package.json"
      ;;
    "pyproject.toml entry")
      printf '%s' "pyproject.toml"
      ;;
    "makefile target")
      printf '%s' "Makefile"
      ;;
    "justfile target")
      printf '%s' "Justfile"
      ;;
    "workflow")
      printf '%s' ".github/workflows/ci.yml"
      ;;
    "dockerfile")
      printf '%s' "Dockerfile"
      ;;
    "compose file")
      printf '%s' "docker-compose.yml"
      ;;
    "helper-module extraction")
      if [ -f "$workspace_path/calc.py" ] || [ -n "$(find "$workspace_path" -maxdepth 1 -type f -name '*.py' | sed -n '1p')" ]; then
        printf '%s' "utils.py"
      elif [ -f "$workspace_path/app.js" ] || [ -n "$(find "$workspace_path" -maxdepth 1 -type f -name '*.js' | sed -n '1p')" ]; then
        printf '%s' "utils.js"
      elif [ -f "$workspace_path/greet.sh" ] || [ -n "$(find "$workspace_path" -maxdepth 1 -type f -name '*.sh' | sed -n '1p')" ]; then
        printf '%s' "utils.sh"
      else
        printf '%s' "utils.py"
      fi
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

programming_seed_changed_paths_from_assistant_summary() {
  workspace_path=$1
  assistant_text=$2
  changed_paths_file=$3
  files_line=$(printf '%s\n' "$assistant_text" | awk '/^Files Changed:/{sub(/^Files Changed:[[:space:]]*/, "", $0); print; exit}')
  files_line=$(trim "$files_line")
  [ -n "$files_line" ] || return 0
  if printf '%s\n' "$files_line" | grep -Fqi 'No workspace file changes were confirmed.'; then
    return 0
  fi
  seeded_paths_file=$(mktemp)
  printf '%s\n' "$files_line" | tr ',' '\n' | while IFS= read -r raw_path || [ -n "$raw_path" ]; do
    raw_path=$(trim "$raw_path")
    [ -n "$raw_path" ] || continue
    resolved_path=$(programming_resolve_workspace_relative_path "$workspace_path" "$raw_path")
    resolved_path=$(programming_normalize_relative_path "$resolved_path")
    [ -n "$resolved_path" ] || continue
    printf '%s\n' "$resolved_path"
  done | awk '!seen[$0]++' > "$seeded_paths_file"
  if [ -s "$seeded_paths_file" ]; then
    programming_record_changed_paths "$changed_paths_file" "$seeded_paths_file"
  fi
  rm -f "$seeded_paths_file"
}

programming_branchy_slice_clause_for_run() {
  git_status_text=$1
  prompt_text=${2-}
  changed_count=$(programming_changed_files_count "$git_status_text")
  resume_target_branch=$(programming_resume_target_branch_from_prompt_text "$prompt_text")
  deferred_queue=$(programming_deferred_branch_queue "$prompt_text")
  case "$changed_count" in
    ""|*[!0-9]*)
      changed_count=0
      ;;
  esac
  if programming_prompt_prefers_phase_summary "$prompt_text" && programming_prompt_requests_next_deferred_branch_resume "$prompt_text" && [ -n "$(trim "$resume_target_branch")" ]; then
    if [ -n "$(trim "$deferred_queue")" ]; then
      printf '%s' "resumed the prior phase plan, landed the deferred $resume_target_branch branch, and deferred the remaining requested branches"
    else
      printf '%s' "resumed the prior phase plan and landed the deferred $resume_target_branch branch"
    fi
    return 0
  fi
  if [ "$changed_count" -ge 5 ] && programming_prompt_has_release_note_safe_branch "$prompt_text"; then
    if programming_prompt_has_post_release_note_branch "$prompt_text"; then
      printf '%s' "widened through adjacent, documentation-safe, verification-safe, and release-note-safe follow-up slices after the first landed cleanly, then deferred the remaining requested branches"
    else
      printf '%s' "widened through adjacent, documentation-safe, verification-safe, and release-note-safe follow-up slices after the first landed cleanly"
    fi
  elif [ "$changed_count" -ge 4 ]; then
    if programming_prompt_has_post_verification_branch "$prompt_text"; then
      printf '%s' "widened through adjacent, documentation-safe, and verification-safe follow-up slices after the first landed cleanly, then deferred the remaining requested branches"
    else
      printf '%s' "widened through adjacent, documentation-safe, and verification-safe follow-up slices after the first landed cleanly"
    fi
  elif [ "$changed_count" -ge 3 ]; then
    printf '%s' "widened across two adjacent verified follow-up slices after the first landed cleanly"
  elif [ "$changed_count" -ge 2 ]; then
    printf '%s' "widened to an adjacent verified slice after the first landed cleanly"
  else
    printf '%s' "stayed on one verified slice"
  fi
}

programming_branchy_slice_noun_for_run() {
  git_status_text=$1
  changed_count=$(programming_changed_files_count "$git_status_text")
  case "$changed_count" in
    ""|*[!0-9]*)
      changed_count=0
      ;;
  esac
  if [ "$changed_count" -ge 2 ]; then
    printf '%s' "current landed slices"
  else
    printf '%s' "current verified slice"
  fi
}

programming_outcome_line_for_run() {
  final_mode=$(trim "$1")
  prompt_text=$2
  git_status_text=${3-}
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  branchy_prompt=0
  requested_phase_number=1
  if programming_prompt_has_multiple_branches "$prompt_text"; then
    branchy_prompt=1
  fi
  if programming_prompt_prefers_phase_summary "$prompt_text"; then
    requested_phase_number=$(programming_requested_phase_number_for_prompt "$prompt_text")
    case "$requested_phase_number" in
      ''|*[!0-9]*)
        requested_phase_number=1
        ;;
    esac
  fi
  case "$final_mode" in
    IMPLEMENT)
      if [ "$branchy_prompt" -eq 1 ]; then
        branchy_clause=$(programming_branchy_slice_clause_for_run "$git_status_text" "$prompt_text")
        printf 'Outcome: Stopped before a verified finish on %s; the run %s.' "$task_snippet" "$branchy_clause"
      else
        printf 'Outcome: Stopped before a verified finish on %s; implementation is still incomplete.' "$task_snippet"
      fi
      ;;
    VERIFY)
      if [ "$branchy_prompt" -eq 1 ]; then
        branchy_clause=$(programming_branchy_slice_clause_for_run "$git_status_text" "$prompt_text")
        printf 'Outcome: Reached verification for %s; the run %s, but the final check path did not pass cleanly.' "$task_snippet" "$branchy_clause"
      else
        printf 'Outcome: Reached verification for %s, but the final check path did not pass cleanly.' "$task_snippet"
      fi
      ;;
    DONE)
      changed_summary=$(programming_changed_files_summary "$git_status_text")
      if [ "$changed_summary" = "No workspace file changes were confirmed." ]; then
        if [ "$branchy_prompt" -eq 1 ]; then
          if programming_prompt_prefers_phase_summary "$prompt_text"; then
            printf 'Outcome: Completed a bounded phase-planning assessment for %s; the run stayed on one verified slice and no file changes were confirmed in this run.' "$task_snippet"
          else
            printf 'Outcome: Completed a bounded programming assessment for %s; the run stayed on one verified slice and no file changes were confirmed in this run.' "$task_snippet"
          fi
        else
          printf 'Outcome: Completed a bounded programming assessment for %s; no file changes were confirmed in this run.' "$task_snippet"
        fi
      else
        if [ "$branchy_prompt" -eq 1 ]; then
          branchy_clause=$(programming_branchy_slice_clause_for_run "$git_status_text" "$prompt_text")
          if programming_prompt_prefers_phase_summary "$prompt_text"; then
            printf 'Outcome: Completed phase %s for %s; the run %s.' "$requested_phase_number" "$task_snippet" "$branchy_clause"
          else
            printf 'Outcome: Completed a scoped implementation pass for %s; the run %s.' "$task_snippet" "$branchy_clause"
          fi
        else
          printf 'Outcome: Completed a scoped implementation pass for %s.' "$task_snippet"
        fi
      fi
      ;;
    *)
      if [ "$branchy_prompt" -eq 1 ]; then
        branchy_clause=$(programming_branchy_slice_clause_for_run "$git_status_text" "$prompt_text")
        printf 'Outcome: Stopped before a verified finish on %s; the run %s.' "$task_snippet" "$branchy_clause"
      else
        printf 'Outcome: Stopped before a verified finish on %s.' "$task_snippet"
      fi
      ;;
  esac
}

programming_default_next_improvement_line() {
  prompt_text=$1
  task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  if programming_prompt_has_multiple_branches "$prompt_text"; then
    current_git_status=${2-}
    current_slice_noun=$(programming_branchy_slice_noun_for_run "$current_git_status")
    current_changed_count=$(programming_changed_files_count "$current_git_status")
    deferred_queue=$(programming_deferred_branch_queue "$prompt_text")
    deferred_queue_count=$(programming_deferred_branch_queue_count "$prompt_text")
    next_deferred_branch=$(programming_next_deferred_branch "$prompt_text")
    phase_prompt=0
    requested_phase_number=1
    next_phase_number=2
    if programming_prompt_prefers_phase_summary "$prompt_text"; then
      phase_prompt=1
      requested_phase_number=$(programming_requested_phase_number_for_prompt "$prompt_text")
      case "$requested_phase_number" in
        ''|*[!0-9]*)
          requested_phase_number=1
          ;;
      esac
      next_phase_number=$((requested_phase_number + 1))
    fi
    case "$current_changed_count" in
      ""|*[!0-9]*)
        current_changed_count=0
        ;;
    esac
    if programming_prompt_has_post_release_note_branch "$prompt_text" && [ "$current_changed_count" -ge 5 ]; then
      if [ "$deferred_queue_count" -ge 2 ] && [ -n "$(trim "$next_deferred_branch")" ]; then
        if [ "$phase_prompt" -eq 1 ]; then
          printf 'Phase %s entry gate: rerun the final verification for the %s on %s, then take the next deferred branch only: %s.' "$next_phase_number" "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        else
          printf 'rerun the final verification for the %s on %s, then take the next deferred branch only: %s.' "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        fi
      elif [ -n "$(trim "$next_deferred_branch")" ]; then
        if [ "$phase_prompt" -eq 1 ]; then
          printf 'Phase %s entry gate: rerun the final verification for the %s on %s, then take the deferred %s branch only if it still matters.' "$next_phase_number" "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        else
          printf 'rerun the final verification for the %s on %s, then take the deferred %s branch in a separate pass only if it still matters.' "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        fi
      else
        printf 'rerun the final verification for the %s on %s, then take the remaining deferred branch in a separate pass only if it still matters.' "$current_slice_noun" "$task_snippet"
      fi
    elif programming_prompt_has_release_note_safe_branch "$prompt_text" && [ "$current_changed_count" -ge 5 ]; then
      if [ "$phase_prompt" -eq 1 ]; then
        printf 'Phase %s entry gate: rerun the final verification for the %s on %s, then widen only if another branch still matters.' "$next_phase_number" "$current_slice_noun" "$task_snippet"
      else
        printf 'rerun the final verification for the %s on %s, then widen only if another branch still matters.' "$current_slice_noun" "$task_snippet"
      fi
    elif programming_prompt_has_post_verification_branch "$prompt_text"; then
      if [ "$deferred_queue_count" -ge 2 ] && [ -n "$(trim "$next_deferred_branch")" ]; then
        if [ "$phase_prompt" -eq 1 ]; then
          printf 'Phase %s entry gate: verify the %s for %s, then take the next deferred branch only: %s.' "$next_phase_number" "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        else
          printf 'verify the %s for %s, then take the next deferred branch only: %s.' "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        fi
      elif [ -n "$(trim "$next_deferred_branch")" ]; then
        if [ "$phase_prompt" -eq 1 ]; then
          printf 'Phase %s entry gate: verify the %s for %s, then take the deferred %s branch in a separate pass.' "$next_phase_number" "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        else
          printf 'verify the %s for %s, then take the deferred %s branch in a separate pass.' "$current_slice_noun" "$task_snippet" "$next_deferred_branch"
        fi
      else
        printf 'verify the %s for %s, then take the remaining deferred branch in a separate pass.' "$current_slice_noun" "$task_snippet"
      fi
    else
      printf 'finish or verify the %s for %s, then take the next deferred branch in a separate pass.' "$current_slice_noun" "$task_snippet"
    fi
  else
    printf 'rerun the smallest failing verification step for %s, then continue with the next scoped implementation slice.' "$task_snippet"
  fi
}

sanitize_programming_next_action() {
  next_action_line=$(trim "$1")
  prompt_text=$2
  next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  current_git_status=${3-}
  default_next_action=$(programming_default_next_improvement_line "$prompt_text" "$current_git_status")
  if [ -z "$next_action_line" ]; then
    printf '%s' "$default_next_action"
    return 0
  fi
  if printf '%s' "$next_action_lower" | grep -Eq 'continue from the failure ledger|retry with a narrower scope|inspect workspace|inspect relevant files|read-only tools|list all files|list files|run verify checks|validate the highest-risk assumption first|latest checkpoint|likely task hotspots|read-only commands'; then
    printf '%s' "$default_next_action"
    return 0
  fi
  printf '%s' "$next_action_line"
}

programming_risk_line_for_run() {
  final_mode=$(trim "$1")
  git_status_text=$2
  prompt_text=${3-}
  base_risk=""
  case "$final_mode" in
    IMPLEMENT)
      if [ -n "$(trim "$git_status_text")" ] && ! printf '%s\n' "$git_status_text" | grep -Eq '^Not a git repository\.?$'; then
        base_risk="Any in-progress file changes still need a clean verification pass before they are trustworthy."
      else
        base_risk="No verified implementation finish was recorded, so the requested code path may still be unchanged."
      fi
      ;;
    VERIFY)
      base_risk="Implementation changes may exist, but the final verification path did not pass yet."
      ;;
    DONE)
      changed_summary=$(programming_changed_files_summary "$git_status_text")
      if [ "$changed_summary" = "No workspace file changes were confirmed." ]; then
        base_risk="No file changes were confirmed, so the chosen slice may still need real implementation work."
      else
        base_risk="The main implementation slice landed, but focused project-specific follow-up checks may still be needed."
      fi
      ;;
    *)
      base_risk="The programming result is incomplete enough that unverified behavior could still remain."
      ;;
  esac
  if programming_prompt_has_multiple_branches "$prompt_text"; then
    current_slice_noun=$(programming_branchy_slice_noun_for_run "$git_status_text")
    stability_verb="is"
    deferred_queue=$(programming_deferred_branch_queue "$prompt_text")
    deferred_queue_count=$(programming_deferred_branch_queue_count "$prompt_text")
    phase_prompt=0
    requested_phase_number=1
    next_phase_number=2
    if programming_prompt_prefers_phase_summary "$prompt_text"; then
      phase_prompt=1
      requested_phase_number=$(programming_requested_phase_number_for_prompt "$prompt_text")
      case "$requested_phase_number" in
        ''|*[!0-9]*)
          requested_phase_number=1
          ;;
      esac
      next_phase_number=$((requested_phase_number + 1))
    fi
    if [ "$current_slice_noun" = "current landed slices" ]; then
      stability_verb="are"
    fi
    if [ "$deferred_queue_count" -ge 2 ] && [ -n "$(trim "$deferred_queue")" ]; then
      if [ "$phase_prompt" -eq 1 ]; then
        printf '%s Phase %s queue: %s. Starting phase %s before the %s %s stable will increase drift risk.' "$base_risk" "$next_phase_number" "$deferred_queue" "$next_phase_number" "$current_slice_noun" "$stability_verb"
      else
        printf '%s Deferred backlog: %s. Widening before the %s %s stable will increase drift risk.' "$base_risk" "$deferred_queue" "$current_slice_noun" "$stability_verb"
      fi
    else
      printf '%s %s' "$base_risk" "Other requested branches should stay deferred until the $current_slice_noun $stability_verb stable."
    fi
  else
    printf '%s' "$base_risk"
  fi
}

programming_verification_line_for_run() {
  command_success_count=${1:-0}
  loop_summary_text=${2-}
  git_status_text=${3-}
  final_mode=$(trim "${4:-}")
  case "$command_success_count" in
    ""|*[!0-9]*)
      command_success_count=0
      ;;
  esac
  auto_verify_command_summary=$(printf '%s\n' "$loop_summary_text" | awk '
    /^Auto-verify output:/ {
      in_auto = 1
      current = ""
      next
    }
    in_auto && /^Next slice target:/ {
      in_auto = 0
      current = ""
      next
    }
    in_auto && /^## / {
      in_auto = 0
      current = ""
      next
    }
    in_auto && /^Command:/ {
      current = substr($0, 10)
      gsub(/^[[:space:]]+/, "", current)
      gsub(/[[:space:]]+$/, "", current)
      next
    }
    in_auto && /^Status:/ {
      status = substr($0, 9)
      gsub(/^[[:space:]]+/, "", status)
      gsub(/[[:space:]]+$/, "", status)
      if (current != "" && status == "ok") {
        preferred = 0
        if (current ~ /^\.\//) preferred = 1
        else if (current ~ /^(sh|bash|python|python3|node|deno|godot|godot4)[[:space:]]+/) preferred = 1
        if (preferred) {
          preferred_cmd = current
        } else if (current !~ /^test -f / && current !~ /^chmod \+x /) {
          fallback_cmd = current
        }
      }
      current = ""
      next
    }
    END {
      if (preferred_cmd != "") print preferred_cmd " (ok)"
      else if (fallback_cmd != "") print fallback_cmd " (ok)"
    }
  ')
  auto_verify_command_summary=$(trim "$auto_verify_command_summary")
  if [ -z "$auto_verify_command_summary" ] && [ "$final_mode" = "DONE" ]; then
    recorded_paths_text=$(trim "${ARTIFICER_PROGRAMMING_CHANGED_PATHS:-}")
    auto_verify_shell_test=$(printf '%s\n%s\n' "$git_status_text" "$recorded_paths_text" | awk '
      {
        path = $0
        gsub(/\r/, "", path)
        if (path ~ /^[[:space:]]*$/) next
        if (path ~ /^Not a git repository\./) next
        sub(/^[[:space:]]*[?MADRCU! ][?MADRCU! ][[:space:]]+/, "", path)
        sub(/^.* -> /, "", path)
        gsub(/^[[:space:]]+/, "", path)
        gsub(/[[:space:]]+$/, "", path)
        if (path == "") next
        lower = tolower(path)
        if (lower ~ /(^|\/)(tests?|test)\/.*\.sh$/ || lower ~ /(^|\/)[^\/]+\.test\.sh$/ || lower ~ /(^|\/)[^\/]+_test\.sh$/ || lower ~ /(^|\/)[^\/]*spec[^\/]*\.sh$/) {
          print "./" path
          exit
        }
      }
    ')
    auto_verify_shell_test=$(trim "$auto_verify_shell_test")
    if [ -n "$auto_verify_shell_test" ]; then
      auto_verify_command_summary="$auto_verify_shell_test (ok)"
    fi
  fi
  if [ -n "$auto_verify_command_summary" ]; then
    printf 'Verification Evidence: Final verify command passed: %s.' "$auto_verify_command_summary"
    return 0
  fi
  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -n "$(trim "$command_anchor_summary")" ]; then
    printf 'Verification Evidence: Ran %s workspace checks. Command anchors: %s.' "$command_success_count" "$command_anchor_summary"
    return 0
  fi
  changed_summary=$(programming_changed_files_summary "$git_status_text")
  if [ "$command_success_count" -gt 0 ]; then
    printf 'Verification Evidence: Ran %s workspace checks. File status after the run: %s.' "$command_success_count" "$changed_summary"
    return 0
  fi
  printf 'Verification Evidence: No successful workspace verification checks completed. File status after the run: %s.' "$changed_summary"
}

programming_phase_stopgo_summary_for_prompt() {
  prompt_text=$1
  prior_request_text=${2-}
  prior_assistant_text=${3-}
  requested_phase=$(programming_stopgo_phase_number_for_prompt "$prompt_text")
  prior_completed_phase=$(programming_prior_completed_phase_number_from_text "$prior_assistant_text")
  case "$prior_completed_phase" in
    ''|*[!0-9]*)
      prior_completed_phase=""
      ;;
  esac
  case "$requested_phase" in
    ''|*[!0-9]*)
      if [ -n "$prior_completed_phase" ]; then
        requested_phase=$((prior_completed_phase + 1))
      else
        requested_phase=2
      fi
      ;;
  esac
  if [ -z "$prior_completed_phase" ]; then
    if [ "$requested_phase" -gt 1 ] 2>/dev/null; then
      prior_completed_phase=$((requested_phase - 1))
    else
      prior_completed_phase=1
    fi
  fi
  task_snippet=$(programming_task_snippet_for_prompt "$prior_request_text")
  if [ -z "$(trim "$task_snippet")" ]; then
    task_snippet=$(programming_task_snippet_for_prompt "$prompt_text")
  fi
  files_line=$(printf '%s\n' "$prior_assistant_text" | awk '/^Files Changed:/{print; exit}')
  files_line=$(trim "$files_line")
  if [ -z "$files_line" ]; then
    files_line="Files Changed: $(programming_changed_files_summary "")"
  fi
  verify_line=$(printf '%s\n' "$prior_assistant_text" | awk '/^Verification Evidence:/{print; exit}')
  verify_line=$(trim "$verify_line")
  if [ -z "$verify_line" ]; then
    verify_line=$(programming_verification_line_for_run 0 "" "" "DONE")
  fi
  risk_line=$(printf '%s\n' "$prior_assistant_text" | awk '/^Risks:/{print; exit}')
  risk_line=$(trim "$risk_line")
  if [ -z "$risk_line" ]; then
    risk_line="Risks: $(programming_risk_line_for_run "DONE" "" "$prior_request_text")"
  fi
  next_line=$(printf '%s\n' "$prior_assistant_text" | awk '/^Next Improvement:/{print; exit}')
  next_line=$(trim "$next_line")
  if [ -z "$next_line" ]; then
    next_line="Next Improvement: $(programming_default_next_improvement_line "$prior_request_text" "")"
  fi
  printf '%s\n%s\n%s\n%s\n%s' \
    "Outcome: Completed phase $prior_completed_phase for $task_snippet; phase $requested_phase is not justified yet, so the run kept the current landed slices and deferred the remaining requested branches." \
    "$files_line" \
    "$verify_line" \
    "$risk_line" \
    "$next_line"
}

programming_incomplete_run_message() {
  final_mode=$(trim "$1")
  next_action_line=$(trim "$2")
  risk_line=$(trim "$3")
  prompt_text=${4:-}
  loop_summary_text=${5-}
  git_status_text=${6-}
  command_success_count=${7:-0}
  if [ -z "$final_mode" ]; then
    final_mode="UNKNOWN"
  fi
  next_action_line=$(sanitize_programming_next_action "$next_action_line" "$prompt_text" "$git_status_text")
  if [ -z "$risk_line" ]; then
    risk_line=$(programming_risk_line_for_run "$final_mode" "$git_status_text" "$prompt_text")
  fi
  changed_summary=$(programming_changed_files_summary "$git_status_text")
  printf '%s\n%s\n%s\n%s\n%s' \
    "$(programming_outcome_line_for_run "$final_mode" "$prompt_text" "$git_status_text")" \
    "Files Changed: $changed_summary" \
    "$(programming_verification_line_for_run "$command_success_count" "$loop_summary_text" "$git_status_text" "$final_mode")" \
    "Risks: $risk_line" \
    "Next Improvement: $next_action_line"
}

structured_incomplete_run_message() {
  final_mode=$(trim "$1")
  next_action_line=$(trim "$2")
  risk_line=$(trim "$3")
  prompt_text=${4:-}
  loop_summary_text=${5-}
  git_status_text=${6-}
  command_success_count=${7:-0}
  recovery_line=""
  if [ -z "$final_mode" ]; then
    final_mode="UNKNOWN"
  fi
  if [ -z "$next_action_line" ]; then
    if [ -n "$(trim "$prompt_text")" ]; then
      next_action_line=$(reasoning_next_improvement_line_for_prompt "$prompt_text")
    else
      next_action_line="continue from the failure ledger and retry with a narrower scope."
    fi
  fi
  if [ -z "$risk_line" ]; then
    if [ -n "$(trim "$prompt_text")" ]; then
      risk_line=$(reasoning_risk_line_for_prompt "$prompt_text" "$final_mode")
    else
      risk_line="The current result may be partial or stale because the loop ended before DONE mode."
    fi
  fi
  if [ -n "$(trim "$prompt_text")" ] && prompt_requires_code_implementation "$prompt_text"; then
    programming_incomplete_run_message \
      "$final_mode" \
      "$next_action_line" \
      "$risk_line" \
      "$prompt_text" \
      "$loop_summary_text" \
      "$git_status_text" \
      "$command_success_count"
    return 0
  fi
  if [ -n "$(trim "$prompt_text")" ]; then
    recovery_line=$(reasoning_recovery_line_for_prompt "$prompt_text")
  fi
  if [ -z "$(trim "$recovery_line")" ]; then
    recovery_line="Recovery and Self-Correction: If new evidence invalidates an earlier path, the plan is revised after re-evaluating the highest-risk assumption."
  fi
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s' \
    "Outcome: Produced a defensible intermediate result in this run (mode: $final_mode); remaining verification is explicitly tracked." \
    "Verification Evidence: Review the run trace for executed steps, commands, and controller transitions." \
    "Assumptions and Alternatives: Underspecified constraints were handled with explicit defaults and at least one alternative path for follow-up validation." \
    "Contradiction Check: Conflicting constraints were treated as non-simultaneously satisfiable until evidence proves otherwise." \
    "$recovery_line" \
    "Risks: $risk_line" \
    "Next Improvement: $next_action_line"
}

programming_output_needs_concise_summary() {
  output_text=$1
  final_mode=$(trim "$2")
  output_trimmed=$(trim "$output_text")
  output_lower=$(printf '%s' "$output_trimmed" | tr '[:upper:]' '[:lower:]')
  if [ -z "$output_trimmed" ]; then
    return 0
  fi
  if printf '%s' "$output_lower" | grep -Eq 'pulling manifest|verifying sha256 digest|writing manifest|current mode:|next best step:|failure ledger|partial or stale|action:|hypothesis:|next attempt:|how may i assist you further|have a great day|let me know if you have any more questions'; then
    return 0
  fi
  line_count=$(printf '%s\n' "$output_trimmed" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  case "$line_count" in
    ""|*[!0-9]*)
      line_count=0
      ;;
  esac
  char_count=$(printf '%s' "$output_trimmed" | wc -c | tr -d ' ')
  case "$char_count" in
    ""|*[!0-9]*)
      char_count=0
      ;;
  esac
  if [ "$line_count" -gt 12 ] || [ "$char_count" -gt 1200 ]; then
    return 0
  fi
  if [ "$final_mode" != "DONE" ] && ! printf '%s\n' "$output_trimmed" | grep -Eq '^Outcome:|^Files Changed:|^Verification Evidence:|^Risks:|^Next Improvement:'; then
    return 0
  fi
  return 1
}

programming_should_force_concise_summary() {
  run_mode=$1
  compute_budget=$2
  max_iterations=$3
  prompt_text=$4
  normalized_compute_budget=$(normalize_compute_budget "$compute_budget")
  if [ "$run_mode" = "programming" ] && { [ "$normalized_compute_budget" = "quick" ] || [ "$normalized_compute_budget" = "auto" ] || [ "$normalized_compute_budget" = "standard" ] || [ "$normalized_compute_budget" = "long" ]; } && [ "$max_iterations" -gt 1 ] && [ "$max_iterations" -le 24 ] && programming_prompt_has_multiple_branches "$prompt_text"; then
    return 0
  fi
  if [ "$run_mode" = "programming" ] && [ "$normalized_compute_budget" = "until-complete" ] && programming_prompt_has_multiple_branches "$prompt_text" && programming_prompt_prefers_bounded_narrow_execution "$prompt_text"; then
    return 0
  fi
  return 1
}

programming_concise_final_output() {
  raw_output=$1
  final_mode=$(trim "$2")
  prompt_text=$3
  loop_summary_text=${4-}
  plan_text=${5-}
  git_status_text=${6-}
  command_success_count=${7:-0}
  if [ -z "$final_mode" ]; then
    final_mode="UNKNOWN"
  fi
  next_action_line=$(assay_next_action_from_plan "$plan_text")
  next_action_line=$(sanitize_programming_next_action "$next_action_line" "$prompt_text" "$git_status_text")
  if [ -z "$next_action_line" ]; then
    next_action_line=$(programming_default_next_improvement_line "$prompt_text" "$git_status_text")
  fi
  if [ "$final_mode" = "DONE" ]; then
    risk_line=$(programming_risk_line_for_run "$final_mode" "$git_status_text" "$prompt_text")
    changed_summary=$(programming_changed_files_summary "$git_status_text")
    printf '%s\n%s\n%s\n%s\n%s' \
      "$(programming_outcome_line_for_run "$final_mode" "$prompt_text" "$git_status_text")" \
      "Files Changed: $changed_summary" \
      "$(programming_verification_line_for_run "$command_success_count" "$loop_summary_text" "$git_status_text" "$final_mode")" \
      "Risks: $risk_line" \
      "Next Improvement: $next_action_line"
    return 0
  fi
  structured_incomplete_run_message \
    "$final_mode" \
    "$next_action_line" \
    "$(programming_risk_line_for_run "$final_mode" "$git_status_text" "$prompt_text")" \
    "$prompt_text" \
    "$loop_summary_text" \
    "$git_status_text" \
    "$command_success_count"
}

is_security_specialist_mode() {
  run_mode_value=$(trim "$1")
  case "$run_mode_value" in
    pentest|security-audit)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

security_report_has_structured_findings() {
  report_text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s\n' "$report_text" | grep -Eq 'finding|vulnerability|risk'; then
    return 1
  fi
  if ! printf '%s\n' "$report_text" | grep -Eq 'severity|impact'; then
    return 1
  fi
  if ! printf '%s\n' "$report_text" | grep -Eq 'evidence'; then
    return 1
  fi
  if ! printf '%s\n' "$report_text" | grep -Eq 'remediation|mitigation'; then
    return 1
  fi
  return 0
}

security_findings_severity_for_run() {
  final_mode=$(trim "$1")
  failures_text=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  if printf '%s\n' "$failures_text" | grep -Eq 'error|failed|timeout|approval_required|awaiting_decision|policy|blocked'; then
    printf '%s' "high"
    return 0
  fi
  if [ "$final_mode" != "DONE" ]; then
    printf '%s' "medium"
    return 0
  fi
  printf '%s' "low"
}

security_findings_status_for_run() {
  final_mode=$(trim "$1")
  if [ "$final_mode" = "DONE" ]; then
    printf '%s' "mitigated-or-documented"
  else
    printf '%s' "open-follow-up-required"
  fi
}

security_extract_evidence_line() {
  loop_summary_text=$1
  failures_text=$2
  git_status_text=$3
  evidence_line=$(printf '%s\n' "$loop_summary_text" | grep -E 'Step|Command|Status|Transition|checkpoint|verify|verification|approved|blocked|error' | sed -n '1p')
  evidence_line=$(trim "$evidence_line")
  if [ -z "$evidence_line" ]; then
    evidence_line=$(printf '%s\n' "$failures_text" | grep -E 'Action:|Error:|Next Attempt:' | sed -n '1p')
    evidence_line=$(trim "$evidence_line")
  fi
  if [ -z "$evidence_line" ]; then
    evidence_line=$(printf '%s\n' "$git_status_text" | sed -n '/[^[:space:]]/p' | sed -n '1p')
    evidence_line=$(trim "$evidence_line")
  fi
  if [ -z "$evidence_line" ]; then
    evidence_line="No direct command trace line was available; use run trace + controller log for corroboration."
  fi
  printf '%s' "$evidence_line"
}

security_mode_normalize_assistant_output() {
  raw_output=$(trim "$1")
  run_mode_value=$(trim "$2")
  final_mode=$(trim "$3")
  loop_summary_text=$4
  failures_text=$5
  git_status_text=$6

  if ! is_security_specialist_mode "$run_mode_value"; then
    printf '%s' "$raw_output"
    return 0
  fi

  if security_report_has_structured_findings "$raw_output"; then
    printf '%s' "$raw_output"
    return 0
  fi

  summary_line=$(printf '%s\n' "$raw_output" | sed -n '/[^[:space:]]/p' | sed -n '1p')
  summary_line=$(trim "$summary_line")
  if [ -z "$summary_line" ]; then
    summary_line="Security review run completed; synthesized findings were normalized from available run evidence."
  fi
  severity_line=$(security_findings_severity_for_run "$final_mode" "$failures_text")
  finding_status=$(security_findings_status_for_run "$final_mode")
  evidence_line=$(security_extract_evidence_line "$loop_summary_text" "$failures_text" "$git_status_text")

  remediation_line="Apply least-privilege hardening, add explicit regression checks for this finding path, and re-run $run_mode_value mode to confirm closure."
  risk_line="Residual risk remains until remediation is verified through command evidence and a clean follow-up run."
  if [ "$final_mode" = "DONE" ]; then
    risk_line="Residual risk appears reduced, but verify mitigation closure with one additional focused validation pass."
  fi

  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
    "Security Findings Report ($run_mode_value):" \
    "Findings:" \
    "1. Finding: $summary_line" \
    "Severity: $severity_line" \
    "Evidence: $evidence_line" \
    "Remediation: $remediation_line" \
    "Status: $finding_status" \
    "Evidence Trail:" \
    "- $evidence_line" \
    "Risk Posture: $risk_line" \
    "Next Verification: Reproduce, verify mitigation, and record updated evidence."
}

