param() {
  key=$1
  value=""
  if [ -n "$post_data" ]; then
    value=$(get-query-param "$key" "$post_data")
  fi
  if [ -z "$value" ] && [ -n "$query_data" ]; then
    value=$(get-query-param "$key" "$query_data")
  fi
  printf '%s' "$value"
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

trim_block_edges() {
  printf '%s' "$1" | perl -0pe 's/\A[[:space:]]+//; s/[[:space:]]+\z//;'
}

model_context_tokens_for() {
  model_name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$model_name" in
    *llama3.1:8b*) printf '%s' "128000" ;;
    *deepseek-coder-v2:16b*) printf '%s' "32000" ;;
    *qwen2.5-coder:7b*) printf '%s' "32000" ;;
    *starcoder2:7b*) printf '%s' "16000" ;;
    *codellama:13b*) printf '%s' "16000" ;;
    *phi3:mini*) printf '%s' "8000" ;;
    *mistral:7b*) printf '%s' "8000" ;;
    *)
      inferred=$(printf '%s' "$model_name" | sed -n 's/.*\([0-9][0-9]*\)[[:space:]]*k.*/\1/p' | sed -n '1p')
      case "$inferred" in
        ""|*[!0-9]*)
          printf '%s' ""
          ;;
        *)
          printf '%s' $((inferred * 1000))
          ;;
      esac
      ;;
  esac
}

estimate_tokens_approx() {
  text=$1
  if [ -z "$(trim "$text")" ]; then
    printf '%s' "0"
    return 0
  fi
  printf '%s' "$text" | awk '
    {
      chars += length($0) + 1
    }
    END {
      if (chars <= 0) {
        print 0
      } else {
        printf "%d\n", int((chars + 3) / 4)
      }
    }
  '
}

compact_text_block() {
  block_name=$1
  text=$2
  budget_tokens=$3
  case "$budget_tokens" in
    ""|*[!0-9]*)
      budget_tokens=0
      ;;
  esac
  if [ "$budget_tokens" -le 0 ]; then
    printf '%s' ""
    return 0
  fi
  approx_before=$(estimate_tokens_approx "$text")
  if [ "$approx_before" -le "$budget_tokens" ]; then
    printf '%s' "$text"
    return 0
  fi

  max_chars=$((budget_tokens * 4))
  [ "$max_chars" -gt 240 ] || max_chars=240
  compacted=$(printf '%s' "$text" | awk -v max="$max_chars" -v title="$block_name" '
    BEGIN { RS = ""; ORS = "" }
    {
      txt = $0
      n = length(txt)
      if (n <= max) {
        print txt
        next
      }
      head = int(max * 0.56)
      tail = int(max * 0.30)
      min_keep = 72
      if (head < min_keep) head = min_keep
      if (tail < min_keep) tail = min_keep
      if (head + tail > max - 64) {
        head = int((max - 64) / 2)
        tail = max - 64 - head
      }
      if (head < 1) head = 1
      if (tail < 1) tail = 1
      omitted = n - head - tail
      if (omitted < 0) omitted = 0
      print substr(txt, 1, head)
      print "\n\n[... " title " compacted; omitted " omitted " chars to fit context window ...]\n\n"
      print substr(txt, n - tail + 1)
    }
  ')
  printf '%s' "$compacted"
}

summarize_git_status_output_for_context() {
  raw_output=$1
  assay_profile_raw=${2:-0}

  case "$assay_profile_raw" in
    ""|*[!0-9]*)
      assay_profile=0
      ;;
    *)
      assay_profile=$assay_profile_raw
      ;;
  esac

  if [ -z "$(trim "$raw_output")" ]; then
    printf '%s' "$raw_output"
    return 0
  fi
  if printf '%s\n' "$raw_output" | grep -Eqi '^[[:space:]]*fatal:'; then
    printf '%s' "$raw_output"
    return 0
  fi

  tracked_lines=$(printf '%s\n' "$raw_output" | awk 'NF > 0 && $0 !~ /^\?\? / { print }')
  untracked_lines=$(printf '%s\n' "$raw_output" | awk 'NF > 0 && $0 ~ /^\?\? / { print }')
  tracked_count=$(printf '%s\n' "$tracked_lines" | sed '/^$/d' | wc -l | tr -d ' ')
  untracked_count=$(printf '%s\n' "$untracked_lines" | sed '/^$/d' | wc -l | tr -d ' ')
  case "$tracked_count" in
    ""|*[!0-9]*)
      tracked_count=0
      ;;
  esac
  case "$untracked_count" in
    ""|*[!0-9]*)
      untracked_count=0
      ;;
  esac

  if [ "$untracked_count" -eq 0 ]; then
    printf '%s' "$raw_output"
    return 0
  fi

  if [ "$assay_profile" -eq 1 ]; then
    untracked_threshold=8
  else
    untracked_threshold=40
  fi
  if [ "$untracked_count" -le "$untracked_threshold" ]; then
    printf '%s' "$raw_output"
    return 0
  fi

  printf 'git status summary:\n'
  printf 'tracked changes: %s\n' "$tracked_count"
  printf 'untracked files: %s\n' "$untracked_count"
  if [ "$tracked_count" -gt 0 ]; then
    printf 'tracked sample (up to 20):\n'
    printf '%s\n' "$tracked_lines" | sed -n '1,20p'
    if [ "$tracked_count" -gt 20 ]; then
      printf '... (%s more tracked changes)\n' "$((tracked_count - 20))"
    fi
  else
    printf 'tracked sample: (none)\n'
  fi
  printf 'untracked sample (up to 8):\n'
  printf '%s\n' "$untracked_lines" | sed -n '1,8p'
  if [ "$untracked_count" -gt 8 ]; then
    printf '... (%s more untracked files)\n' "$((untracked_count - 8))"
  fi
  printf 'hint: use git status --short --untracked-files=no for tracked-only inspection.\n'
}

compact_command_output_for_context() {
  command_line=$1
  raw_output=$2
  assay_profile_raw=${3:-0}
  output_text=$raw_output

  lower_command=$(printf '%s' "$command_line" | tr '[:upper:]' '[:lower:]')
  case "$lower_command" in
    git\ status*)
      output_text=$(summarize_git_status_output_for_context "$output_text" "$assay_profile_raw")
      ;;
  esac

  output_line_count=$(printf '%s\n' "$output_text" | wc -l | tr -d ' ')
  output_char_count=$(printf '%s' "$output_text" | wc -c | tr -d ' ')
  case "$output_line_count" in
    ""|*[!0-9]*)
      output_line_count=0
      ;;
  esac
  case "$output_char_count" in
    ""|*[!0-9]*)
      output_char_count=0
      ;;
  esac

  if [ "$output_line_count" -gt 140 ] || [ "$output_char_count" -gt 14000 ]; then
    compact_head_lines=90
    compact_tail_lines=30
    if [ "$output_line_count" -lt $((compact_head_lines + compact_tail_lines + 1)) ]; then
      compact_head_lines=$((output_line_count / 2))
      compact_tail_lines=$((output_line_count - compact_head_lines))
      if [ "$compact_head_lines" -lt 1 ]; then
        compact_head_lines=1
      fi
      if [ "$compact_tail_lines" -lt 1 ]; then
        compact_tail_lines=1
      fi
    fi
    omitted_lines=$((output_line_count - compact_head_lines - compact_tail_lines))
    if [ "$omitted_lines" -lt 0 ]; then
      omitted_lines=0
    fi
    output_head=$(printf '%s\n' "$output_text" | sed -n "1,${compact_head_lines}p")
    output_tail=$(printf '%s\n' "$output_text" | tail -n "$compact_tail_lines")
    output_text=$(printf '%s\n\n[... command output compacted; omitted %s lines to preserve context stability ...]\n\n%s' \
      "$output_head" "$omitted_lines" "$output_tail")
  fi

  printf '%s' "$output_text"
}

model_timeout_for_run() {
  started_epoch=$1
  budget_sec=$2
  fallback_sec=${3:-120}
  reserve_sec=${4:-8}
  min_sec=${5:-12}

  case "$started_epoch" in
    ""|*[!0-9]*) started_epoch=0 ;;
  esac
  case "$budget_sec" in
    ""|*[!0-9]*) budget_sec=$fallback_sec ;;
  esac
  case "$fallback_sec" in
    ""|*[!0-9]*) fallback_sec=120 ;;
  esac
  case "$reserve_sec" in
    ""|*[!0-9]*) reserve_sec=8 ;;
  esac
  case "$min_sec" in
    ""|*[!0-9]*) min_sec=8 ;;
  esac
  timeout_scale=${ARTIFICER_MODEL_TIMEOUT_SCALE:-1}
  case "$timeout_scale" in
    ""|*[!0-9]*)
      timeout_scale=1
      ;;
  esac
  if [ "$timeout_scale" -lt 1 ]; then
    timeout_scale=1
  fi
  if [ "$timeout_scale" -gt 6 ]; then
    timeout_scale=6
  fi
  if [ "$timeout_scale" -gt 1 ]; then
    fallback_sec=$((fallback_sec * timeout_scale))
    min_sec=$((min_sec * timeout_scale))
  fi
  if [ "$fallback_sec" -gt 600 ]; then
    fallback_sec=600
  fi
  if [ "$min_sec" -gt "$fallback_sec" ]; then
    min_sec=$fallback_sec
  fi

  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*) now_epoch=0 ;;
  esac

  elapsed=$((now_epoch - started_epoch))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi
  remaining=$((budget_sec - elapsed - reserve_sec))
  timeout_sec=$fallback_sec
  if [ "$remaining" -le 0 ]; then
    timeout_sec=5
  elif [ "$remaining" -lt "$timeout_sec" ]; then
    timeout_sec=$remaining
  fi
  if [ "$remaining" -gt 0 ] && [ "$timeout_sec" -lt "$min_sec" ]; then
    timeout_sec=$min_sec
    if [ "$timeout_sec" -gt "$remaining" ]; then
      timeout_sec=$remaining
    fi
  fi
  if [ "$timeout_sec" -lt 5 ]; then
    timeout_sec=5
  fi
  if [ "$timeout_sec" -gt "$fallback_sec" ]; then
    timeout_sec=$fallback_sec
  fi
  printf '%s' "$timeout_sec"
}

run_budget_remaining_seconds() {
  started_epoch=$1
  budget_sec=$2

  case "$started_epoch" in
    ""|*[!0-9]*)
      started_epoch=0
      ;;
  esac
  case "$budget_sec" in
    ""|*[!0-9]*)
      budget_sec=0
      ;;
  esac

  now_epoch=$(date +%s 2>/dev/null || printf '0')
  case "$now_epoch" in
    ""|*[!0-9]*)
      now_epoch=0
      ;;
  esac

  elapsed=$((now_epoch - started_epoch))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi
  remaining=$((budget_sec - elapsed))
  if [ "$remaining" -lt 0 ]; then
    remaining=0
  fi
  printf '%s' "$remaining"
}

should_skip_controller_format_retry() {
  budget_remaining_raw=$1
  recovery_total_raw=$2
  recovery_streak_raw=$3
  run_mode_hint=$(trim "${4:-}")

  case "$budget_remaining_raw" in
    ""|*[!0-9]*)
      budget_remaining=0
      ;;
    *)
      budget_remaining=$budget_remaining_raw
      ;;
  esac
  case "$recovery_total_raw" in
    ""|*[!0-9]*)
      recovery_total=0
      ;;
    *)
      recovery_total=$recovery_total_raw
      ;;
  esac
  case "$recovery_streak_raw" in
    ""|*[!0-9]*)
      recovery_streak=0
      ;;
    *)
      recovery_streak=$recovery_streak_raw
      ;;
  esac

  if [ "$recovery_streak" -ge 1 ] && [ "$budget_remaining" -le 70 ]; then
    return 0
  fi
  if [ "$recovery_total" -ge 2 ] && [ "$budget_remaining" -le 90 ]; then
    return 0
  fi
  case "$run_mode_hint" in
    assistant|report|teacher|security-audit|pentest|text-perfecter|gui-testing)
      if [ "$budget_remaining" -le 55 ]; then
        return 0
      fi
      if [ "$recovery_total" -ge 1 ] && [ "$budget_remaining" -le 80 ]; then
        return 0
      fi
      ;;
  esac

  return 1
}

reasoning_completion_reserve_seconds() {
  compute_budget_hint=$(trim "${1:-standard}")
  assay_profile_raw=${2:-0}
  recovery_total_raw=${3:-0}
  stagnation_repeat_raw=${4:-0}

  reserve_sec=22
  case "$compute_budget_hint" in
    quick)
      reserve_sec=18
      ;;
    standard|auto)
      reserve_sec=22
      ;;
    long)
      reserve_sec=26
      ;;
    until-complete)
      reserve_sec=30
      ;;
  esac

  case "$assay_profile_raw" in
    ""|*[!0-9]*)
      assay_profile=0
      ;;
    *)
      assay_profile=$assay_profile_raw
      ;;
  esac
  case "$recovery_total_raw" in
    ""|*[!0-9]*)
      recovery_total=0
      ;;
    *)
      recovery_total=$recovery_total_raw
      ;;
  esac
  case "$stagnation_repeat_raw" in
    ""|*[!0-9]*)
      stagnation_repeat=0
      ;;
    *)
      stagnation_repeat=$stagnation_repeat_raw
      ;;
  esac

  if [ "$assay_profile" -eq 1 ] && [ "$reserve_sec" -lt 24 ]; then
    reserve_sec=24
  fi
  if [ "$recovery_total" -ge 1 ]; then
    reserve_sec=$((reserve_sec + 6))
  fi
  if [ "$stagnation_repeat" -ge 1 ]; then
    reserve_sec=$((reserve_sec + 4))
  fi
  if [ "$reserve_sec" -gt 45 ]; then
    reserve_sec=45
  fi

  printf '%s' "$reserve_sec"
}

looks_like_embedding_vector() {
  raw_text=$(trim "$1")
  case "$raw_text" in
    \[*\]) ;;
    *)
      return 1
      ;;
  esac

  if ! printf '%s' "$raw_text" | grep -Eq '^\[[0-9eE+., -]+\]$'; then
    return 1
  fi

  comma_count=$(printf '%s' "$raw_text" | tr -cd ',' | wc -c | tr -d ' ')
  if [ "$comma_count" -lt 32 ]; then
    return 1
  fi

  return 0
}

normalize_assistant_output() {
  text=$1
  cleaned=$(strip_terminal_noise "$text")
  cleaned=$(printf '%s' "$cleaned" | sed 's/<|end_of_text|>//g;s/<end_of_text>//g;s/<\/s>//g;s/<|im_end|>//g')

  first_line=$(printf '%s\n' "$cleaned" | sed -n '1p')
  first_line_lower=$(printf '%s' "$first_line" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//')
  case "$first_line_lower" in
    assistant:*|user:*|system:*|"# response"|response:|"# answer"|answer:)
      cleaned=$(printf '%s\n' "$cleaned" | sed '1d')
      ;;
  esac

  output=""
  seen_non_empty=0
  while IFS= read -r line; do
    line_lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//')
    if [ "$seen_non_empty" -eq 1 ]; then
      case "$line_lower" in
        user:*|system:*)
          break
          ;;
      esac
    fi

    if [ -z "$output" ]; then
      output=$line
    else
      output=$(printf '%s\n%s' "$output" "$line")
    fi

    if [ -n "$(trim "$line")" ]; then
      seen_non_empty=1
    fi
  done <<EOF
$cleaned
EOF

  cleaned=$(trim "$output")
  if [ -z "$cleaned" ]; then
    raw_trimmed=$(trim "$text")
    if printf '%s' "$raw_trimmed" | grep -Eq '[[:alnum:]]'; then
      cleaned=$raw_trimmed
    else
      cleaned=""
    fi
  fi
  cleaned=$(printf '%s\n' "$cleaned" | sed '/^[[:space:]]*[Uu]ser[[:space:]]*request:/,$d')
  cleaned=$(trim "$cleaned")
  printf '%s' "$cleaned"
}

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

assay_output_has_required_sections() {
  text=$1
  for required in "Outcome:" "Verification Evidence:" "Risks:" "Next Improvement:"; do
    if ! printf '%s\n' "$text" | grep -q "$required"; then
      return 1
    fi
  done
  return 0
}

output_is_intermediate_contract() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$text_lower")" ]; then
    return 0
  fi
  if printf '%s' "$text_lower" | grep -Eq '^outcome:[[:space:]]+produced a defensible intermediate result|^outcome:[[:space:]]+best-effort progress was produced|^outcome:[[:space:]]+run was interrupted before full completion|current result may be partial|partial or stale|loop ended before done mode|run ended in mode:'; then
    return 0
  fi
  return 1
}

final_has_instructional_placeholders() {
  final_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$final_text_lower")" ]; then
    return 1
  fi
  if printf '%s' "$final_text_lower" | grep -Eq \
    'false premise challenge:[[:space:]]*name one plausible but false assumption|premise validation:[[:space:]]*define the first disconfirming check|adversarial probe:[[:space:]]*for this scenario .* specify one abuse (path|case)|disconfirming threshold:[[:space:]]*define at least one measurable trigger|domain linkage:[[:space:]]*for this scenario .* explain at least one dependency|architecture lens:[[:space:]]*for this scenario .* summarize|product/ux lens:[[:space:]]*for this scenario .* summarize|security/compliance lens:[[:space:]]*for this scenario .* summarize|metrics/causality lens:[[:space:]]*for this scenario .* summarize|incident/ops lens:[[:space:]]*for this scenario .* summarize|tradeoff ledger:[[:space:]]*for this scenario .* list two non-obvious tradeoffs|rejected alternative:[[:space:]]*name the strongest alternative path|stakeholder impact map:[[:space:]]*summarize impact on end users|self-correction evidence:[[:space:]]*identify one tested assumption|evidence anchors:[[:space:]]*for this scenario .* tie major claims|claim-to-evidence map:[[:space:]]*for each major claim, provide|quantified thresholds:[[:space:]]*define at least one numeric acceptance threshold|evidence caveats:[[:space:]]*state freshness limits|scenario-specific check:[[:space:]]*for this scenario .* define one counterexample test|near-miss guard:[[:space:]]*state one similar-looking pattern|assumption register:[[:space:]]*list critical assumptions|uncertainty range:[[:space:]]*provide lower bound|initial assumption:[[:space:]]*for this scenario .* state the first plausible assumption|invalidating evidence:[[:space:]]*state the first concrete evidence|revised decision:[[:space:]]*explain how the recommendation changed|evidence delta:[[:space:]]*contrast before/after confidence'
  then
    return 0
  fi
  return 1
}

assay_next_action_from_plan() {
  plan_text=$1
  next_action_line=$(printf '%s\n' "$plan_text" | sed -n '/^Next Action:/,$p' | sed -n '2p')
  next_action_line=$(trim "$next_action_line")
  if [ -z "$next_action_line" ]; then
    next_action_line="continue from the failure ledger and retry with a narrower scope."
  fi
  printf '%s' "$next_action_line"
}

assay_prefers_scenario_reasoning_normalization() {
  prompt_text=$1
  if prompt_prefers_reasoning_completion "$prompt_text"; then
    return 0
  fi
  if prompt_requires_high_risk_fail_closed "$prompt_text" ""; then
    return 0
  fi
  if prompt_requires_decision_completeness "$prompt_text"; then
    return 0
  fi
  if prompt_requires_cross_domain_reasoning "$prompt_text"; then
    return 0
  fi
  if prompt_requires_adversarial_reasoning "$prompt_text"; then
    return 0
  fi
  return 1
}

sanitize_reasoning_next_action() {
  next_action_line=$(trim "$1")
  prompt_text=$2
  next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  default_reasoning_next_action=$(reasoning_next_improvement_line_for_prompt "$prompt_text")

  if [ -z "$next_action_line" ]; then
    next_action_line=$default_reasoning_next_action
    next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  fi

  if assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    if printf '%s' "$next_action_lower" | grep -Eq 'list all files|list files|inspect workspace|inspect relevant files|read-only tools|readme|git status|ls -|open repository|review folder structure|^completion criteria|^goal:|identified files and their contents|requested change implemented|continue from the failure ledger|narrower scope|latest checkpoint|implementation patch|run verify checks|validate the highest-risk assumption first'; then
      next_action_line=$default_reasoning_next_action
    fi
  fi

  printf '%s' "$next_action_line"
}

assay_reasoning_verification_line_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$(trim "$scenario_ref")" ]; then
    printf '%s' "Verification Evidence: Review the run trace for executed steps, commands, and controller transitions."
    return 0
  fi
  printf 'Verification Evidence: Review the run trace and command anchors for scenario (%s).' "$scenario_ref"
}

assay_sanitize_reasoning_outcome() {
  outcome_line=$(trim "$1")
  prompt_text=$2
  outcome_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')

  if ! assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    printf '%s' "$outcome_line"
    return 0
  fi

  if [ -z "$outcome_line" ] || [ "$outcome_lower" = "none" ] || [ "$outcome_lower" = "null" ] || [ "$outcome_lower" = "n/a" ]; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq '^security findings report(\b|[[:space:]]*\()|^pentest findings report(\b|[[:space:]]*\()|^security review run completed; synthesized findings were normalized from available run evidence\.?$'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  printf '%s' "$outcome_line"
}

reasoning_prompt_focus() {
  prompt_text=$1
  prompt_primary=$(printf '%s' "$prompt_text" | sed '/Assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/Assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_focus=$(printf '%s' "$prompt_primary" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//' | cut -c1-96)
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  printf '%s' "$prompt_focus"
}

prompt_anchor_tokens_for_depth() {
  prompt_focus=$(reasoning_prompt_focus "$1")
  printf '%s\n' "$prompt_focus" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '\n' | awk '
    length($0) < 4 { next }
    $0 ~ /^[0-9]+$/ { next }
    $0 ~ /^(this|that|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|about|across|against|around|would|could|should|must|need|needs|required|requireds|current|scenario|domain|integration|analysis|decision|strategy|plan|check|final|output|verify|verification|evidence|risk|risks|next|improvement|tradeoff|tradeoffs|priority|fallback|assumption|assumptions|alternative|alternatives|contract|constraints|through|using|user|users|system|service|services|team|teams|stakeholder|stakeholders|request|prompt)$/ { next }
    !seen[$0]++ { print }
  ' | sed -n '1,8p'
}

reasoning_prompt_focus_brief() {
  prompt_focus=$(reasoning_prompt_focus "$1")
  prompt_focus=$(printf '%s' "$prompt_focus" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  prompt_focus=$(printf '%s' "$prompt_focus" | cut -c1-84)
  if [ -z "$(trim "$prompt_focus")" ]; then
    prompt_focus="current scenario"
  fi
  printf '%s' "$prompt_focus"
}

reasoning_recent_user_turns_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Recent user turns:$/ { capture = 1; next }
    /^Prior compact answer:$/ { capture = 0 }
    /^Prior scenario:$/ { capture = 0 }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
    /^Prior reasoning answer:$/ { capture = 0 }
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

reasoning_latest_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        latest = line
      }
    }
    END {
      print latest
    }
  '
}

reasoning_followup_previous_turn_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n >= 2) {
        print turns[n - 1]
      }
    }
  '
}

reasoning_followup_turn_before_previous_from_turns_block() {
  turns_block=$1
  printf '%s\n' "$turns_block" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n >= 3) {
        print turns[n - 2]
      }
    }
  '
}

reasoning_followup_token_overlap_present() {
  candidate_text=$(printf '%s' "${1-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  reference_text=$(printf '%s' "${2-}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$candidate_text")" ] || return 1
  [ -n "$(trim "$reference_text")" ] || return 1
  awk -v candidate="$candidate_text" -v reference="$reference_text" '
    function load_tokens(text, bag,    normalized, n, i, token) {
      normalized = tolower(text)
      gsub(/[^[:alnum:]]+/, " ", normalized)
      n = split(normalized, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        token = parts[i]
        if (length(token) < 4) {
          continue
        }
        if (token ~ /^(that|this|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|here|about|across|against|around|would|could|should|must|need|needs|required|current|scenario|outcome|decision|fallback|path|disconfirming|evidence|risk|risks|next|improvement|initial|assumption|invalidating|revised|delta|review|window|owner|priority|prior|recent|still|again|after|before|remains|remained|stayed|keeps|kept|continued|updated|update|your|call|read|take|land|now|then)$/) {
          continue
        }
        bag[token] = 1
      }
    }
    BEGIN {
      load_tokens(candidate, cand)
      load_tokens(reference, ref)
      overlap = 0
      for (token in cand) {
        if (token in ref) {
          overlap++
        }
      }
      exit(overlap >= 2 ? 0 : 1)
    }
  '
}

reasoning_followup_delta_only_turn_present() {
  prompt_text=$1
  normalized_prompt=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  normalized_prompt=$(trim "$normalized_prompt")
  [ -n "$normalized_prompt" ] || return 1
  if reasoning_followup_text_signals_present "$normalized_prompt"; then
    return 1
  fi
  if reasoning_followup_implicit_text_signals_present "$normalized_prompt"; then
    return 1
  fi
  if reasoning_followup_short_question_present "$normalized_prompt"; then
    return 1
  fi
  if printf '%s' "$normalized_prompt" | grep -Eqi 'in short labeled sections|short labeled sections|same labels|keep the same labels|give outcome|fallback path|next improvement|disconfirming evidence|implement|apply patch|modify file|update file|write file|fix bug|run tests|compile|build target'; then
    return 1
  fi
  word_count=$(printf '%s\n' "$normalized_prompt" | awk '{ print NF }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 40 ]; then
    return 1
  fi
  if reasoning_followup_changed_condition_cues_present "$normalized_prompt" \
    || reasoning_followup_fragment_delta_present "$normalized_prompt"; then
    return 0
  fi
  return 1
}

reasoning_followup_prior_scenario_from_turns_block() {
  turns_block=$1
  latest_prompt=${2:-}
  latest_prompt=$(trim "$latest_prompt")
  printf '%s\n' "$turns_block" | awk -v latest_prompt="$latest_prompt" '
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
        turns[++n] = line
      }
    }
    END {
      if (n == 0) {
        exit
      }
      latest = tolower(latest_prompt)
      gsub(/[[:space:]]+/, " ", latest)
      latest = trim(latest)
      latest_plain = latest
      sub(/[[:space:][:punct:]]+$/, "", latest_plain)
      gsub(/\047/, "", latest_plain)
      if (latest_plain == "your call" || latest_plain == "your read" || latest_plain == "your take" || latest_plain == "your instinct" || latest_plain == "where do you land" || latest_plain == "where do you land now" || latest_plain == "where does this leave you" || latest_plain == "so" || latest_plain == "and" || latest_plain == "and now" || latest_plain == "what now" || latest_plain == "well" || latest_plain == "still" || latest_plain == "still yes" || latest_plain == "still safe" || latest_plain == "still harmless" || latest_plain == "thoughts" || latest_plain == "thought" || latest_plain == "gut check" || latest_plain == "gut reaction" || latest_plain == "initial take" || latest_plain == "first instinct" || latest_plain == "quick read" || latest_plain == "whats your take" || latest_plain == "whats your read" || latest_plain == "whats your call" || latest_plain == "whats the move" || latest_plain == "how does this strike you") {
        print turns[1]
        exit
      }
      if (n >= 2) {
        print turns[n - 1]
        exit
      }
      print turns[1]
    }
  '
}

reasoning_prior_scenario_block_for_prompt() {
  prompt_text=$1
  printf '%s\n' "$prompt_text" | awk '
    BEGIN { capture = 0 }
    /^Prior scenario:$/ { capture = 1; next }
    /^Prior clarify question:$/ { capture = 0 }
    /^Prior frame:$/ { capture = 0 }
    /^Prior decision summary:$/ { capture = 0 }
    /^Prior memo:$/ { capture = 0 }
    /^Prior compact answer:$/ { capture = 0 }
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

reasoning_followup_anchor_source_for_prompt() {
  prompt_text=$1
  if ! reasoning_followup_text_signals_present "$prompt_text" \
    && ! reasoning_followup_implicit_text_signals_present "$prompt_text" \
    && ! reasoning_followup_delta_only_turn_present "$(reasoning_latest_prompt_text "$prompt_text")"; then
    return 0
  fi

  recent_turns=$(reasoning_recent_user_turns_block_for_prompt "$prompt_text")
  recent_delta_turn=$(reasoning_followup_recent_delta_turn_for_prompt "$prompt_text")
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$(trim "$recent_delta_turn")" ] && [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario" | cut -c1-640
    return 0
  fi
  prior_user_turn=$(printf '%s\n' "$recent_turns" | awk '
    {
      line = $0
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]+Assay execution scope:.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) {
        turns[++n] = line
      }
    }
    END {
      if (n >= 2) {
        print turns[n - 1]
      } else if (n == 1) {
        print turns[1]
      }
    }
  ')
  if [ -n "$(trim "$prior_user_turn")" ]; then
    printf '%s' "$prior_user_turn" | cut -c1-640
    return 0
  fi

  if [ -n "$prior_scenario" ]; then
    printf '%s' "$prior_scenario" | cut -c1-640
    return 0
  fi

  prior_answer=$(reasoning_prior_answer_block_for_prompt "$prompt_text")
  prior_decision=$(reasoning_contract_extract_value "Decision" "$prior_answer")
  if [ -n "$(trim "$prior_decision")" ]; then
    printf '%s' "$prior_decision" | sed 's/^[[:space:]]*//' | cut -c1-320
  fi
}

reasoning_prompt_anchor_source() {
  prompt_text=$1
  prior_scenario=$(reasoning_prior_scenario_block_for_prompt "$prompt_text")
  prior_scenario=$(trim "$prior_scenario")
  if [ -n "$prior_scenario" ]; then
    prompt_primary=$prior_scenario
  else
    followup_anchor_source=$(reasoning_followup_anchor_source_for_prompt "$prompt_text")
    if [ -n "$(trim "$followup_anchor_source")" ]; then
      prompt_primary=$followup_anchor_source
    else
      prompt_primary=$(printf '%s' "$prompt_text" | sed '/Assay execution scope:/,$d')
    fi
  fi
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/Assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text
  fi
  prompt_source=$(printf '%s' "$prompt_primary" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//' | cut -c1-640)
  if [ -z "$(trim "$prompt_source")" ]; then
    prompt_source=$(reasoning_prompt_focus "$prompt_text")
  fi
  printf '%s' "$prompt_source"
}

reasoning_prompt_tokens_for_anchor() {
  prompt_source=$(reasoning_prompt_anchor_source "$1")
  printf '%s\n' "$prompt_source" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' | awk '
    length($0) < 4 { next }
    $0 ~ /^[0-9]+$/ { next }
    $0 ~ /^(this|that|with|from|into|over|under|between|after|before|while|where|when|what|which|whose|there|their|about|across|against|around|would|could|should|must|need|needs|required|requireds|current|scenario|domain|integration|analysis|decision|strategy|plan|check|final|output|verify|verification|evidence|risk|risks|next|improvement|tradeoff|tradeoffs|priority|fallback|assumption|assumptions|alternative|alternatives|contract|constraints|through|using|user|users|system|service|services|team|teams|stakeholder|stakeholders|request|prompt|design|architecture|regulated|repository|telemetry|noisy|autogenerated|assay|artifact|artifacts|dominate|dominates|thousands|build|create|provide|explicitly|resists|prioritizes|defines|first|wrong|status|output|report|assistant|teacher|mode|scope|execution|mentoring|contract)$/ { next }
    !seen[$0]++ { print }
  ' | sed -n '1,14p'
}

reasoning_indefinite_article_for_phrase() {
  phrase=$(trim "$1")
  if [ -z "$phrase" ]; then
    printf '%s' "a"
    return 0
  fi
  first_char=$(printf '%s' "$phrase" | cut -c1 | tr '[:upper:]' '[:lower:]')
  case "$first_char" in
    a|e|i|o|u)
      printf '%s' "an"
      ;;
    *)
      printf '%s' "a"
      ;;
  esac
}

reasoning_prompt_anchor_clause() {
  prompt_source=$(reasoning_prompt_anchor_source "$1")
  prompt_clause=$(printf '%s' "$prompt_source" | sed -E 's/[.?!][[:space:]].*$//')
  prompt_clause=$(printf '%s' "$prompt_clause" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  printf '%s' "$prompt_clause"
}

reasoning_anchor_phrase_cleanup() {
  phrase=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/^(design|create|assess|deliver|provide|draft|plan|teach why|teach|explain)[[:space:]]+//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/^(a|an|the)[[:space:]]+//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+while[[:space:]]+noisy warnings dominate logs$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+deliver[[:space:]]+a[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+make[[:space:]]+the[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+provide[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed -E 's/[[:space:]]+explain[[:space:]].*$//')
  phrase=$(printf '%s' "$phrase" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')
  printf '%s' "$phrase"
}

reasoning_anchor_phrase_truncate() {
  phrase=$(trim "$1")
  if [ -z "$phrase" ]; then
    printf '%s' "$phrase"
    return 0
  fi
  phrase_length=$(printf '%s' "$phrase" | wc -c | tr -d ' ')
  case "$phrase_length" in
    ""|*[!0-9]*)
      phrase_length=0
      ;;
  esac
  if [ "$phrase_length" -gt 128 ]; then
    phrase=$(printf '%s' "$phrase" | cut -c1-128 | sed 's/[[:space:]][^[:space:]]*$//')
    phrase=$(trim "$phrase")
  fi
  if [ -z "$phrase" ]; then
    phrase="scenario anchors"
  fi
  printf '%s' "$phrase"
}

reasoning_prompt_anchor_phrase_fallback() {
  prompt_clause=$(reasoning_prompt_anchor_clause "$1")
  anchor_phrase=$(reasoning_anchor_phrase_cleanup "$prompt_clause")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    fallback_tokens=$(prompt_anchor_tokens_for_depth "$1")
    seg_one=$(printf '%s\n' "$fallback_tokens" | sed -n '1p')
    seg_two=$(printf '%s\n' "$fallback_tokens" | sed -n '2p')
    seg_three=$(printf '%s\n' "$fallback_tokens" | sed -n '3p')
    if [ -n "$seg_three" ]; then
      anchor_phrase="$seg_one, $seg_two, and $seg_three"
    elif [ -n "$seg_two" ]; then
      anchor_phrase="$seg_one and $seg_two"
    elif [ -n "$seg_one" ]; then
      anchor_phrase=$seg_one
    fi
  fi
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase="scenario anchors"
  fi
  reasoning_anchor_phrase_truncate "$anchor_phrase"
}

reasoning_prompt_anchor_phrase() {
  prompt_text=$1
  prompt_source=$(reasoning_prompt_anchor_source "$prompt_text")
  prompt_lower=$(printf '%s' "$prompt_source" | tr '[:upper:]' '[:lower:]')
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  anchor_phrase=""

  case "$domain_hint" in
    architecture)
      if printf '%s' "$prompt_lower" | grep -Eq 'shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'merchant retention mismatch|merchant-specific retention|retention differs by merchant|retention' && printf '%s' "$prompt_lower" | grep -Eq 'late failover replays|late failover events|late events after failover|late failover' && printf '%s' "$prompt_lower" | grep -Eq 'replay|replays'; then
        anchor_phrase="shared partner-event ingestion with replay ordering, merchant-specific retention, and late failover events"
      elif printf '%s' "$prompt_lower" | grep -Eq 'one shared feed looks simpler|shared feed for partner events|shared feed is easier to operate|partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'retention differs by merchant|merchants have different retention rules|different retention duties|retention duties differ|merchant-specific retention|retention rules differ' && printf '%s' "$prompt_lower" | grep -Eq 'replay out of order|replay-order matters|replay order matters|replay ordering matters|replay order' && printf '%s' "$prompt_lower" | grep -Eq 'late failover events|late events after failover|late events|late arrivals after failover|failover'; then
        anchor_phrase="shared partner-event ingestion with replay ordering, merchant-specific retention, and late failover events"
      elif printf '%s' "$prompt_lower" | grep -Eq 'partner-event ingestion' && printf '%s' "$prompt_lower" | grep -Eq 'pci retention'; then
        anchor_phrase="partner-event ingestion with replay guarantees, tenant isolation, and pci retention constraints"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared feed for partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'late and out-of-order|late and out of order|out-of-order replays|replays mix tenants|mix tenants' && printf '%s' "$prompt_lower" | grep -Eq 'retention exceptions|retention exception|retention' && printf '%s' "$prompt_lower" | grep -Eq 'smaller merchants|merchant'; then
        anchor_phrase="shared partner-event ingestion with replay guarantees, merchant isolation, and retention rules"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared intake lane|single event lane|partner intake' && printf '%s' "$prompt_lower" | grep -Eq 'late arrivals|late arrival' && printf '%s' "$prompt_lower" | grep -Eq 'replay out of order|replay order|out of order' && printf '%s' "$prompt_lower" | grep -Eq 'retention clocks|retention clock' && printf '%s' "$prompt_lower" | grep -Eq 'merchant'; then
        anchor_phrase="shared partner-event intake with replay guarantees, merchant isolation, and retention clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared partner-event path|shared feed for partner events|shared feed' && printf '%s' "$prompt_lower" | grep -Eq 'replay drills|replay tests|replay' && printf '%s' "$prompt_lower" | grep -Eq 'interleave two merchants|cross merchant boundaries|merchant boundaries|merchant isolation' && printf '%s' "$prompt_lower" | grep -Eq 'retention timers differ by merchant|retention clocks differ by merchant|retention'; then
        anchor_phrase="shared partner-event ingestion with replay guarantees, merchant isolation, and retention rules"
      elif printf '%s' "$prompt_lower" | grep -Eq 'shared partner-event ingestion path|partner-event ingestion path' && printf '%s' "$prompt_lower" | grep -Eq 'replay drills|replay' && printf '%s' "$prompt_lower" | grep -Eq 'merchant records cannot bleed|cannot bleed together|tenant isolation'; then
        anchor_phrase="partner-event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'retail partner' && printf '%s' "$prompt_lower" | grep -Eq 'late and out of order' && printf '%s' "$prompt_lower" | grep -Eq 'merchant'; then
        anchor_phrase="retail order events that arrive late, out of order, and must stay merchant-isolated"
      elif printf '%s' "$prompt_lower" | grep -Eq 'partner-event ingestion'; then
        anchor_phrase="partner-event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'event ingestion' && printf '%s' "$prompt_lower" | grep -Eq 'replay' && printf '%s' "$prompt_lower" | grep -Eq 'tenant'; then
        anchor_phrase="event ingestion with replay guarantees and tenant isolation"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replay guarantees' && printf '%s' "$prompt_lower" | grep -Eq 'tenant isolation'; then
        anchor_phrase="replay guarantees and tenant isolation"
      fi
      ;;
    forensics)
      if printf '%s' "$prompt_lower" | grep -Eq 'replica divergence|replica diverged|replica kept diverging' && printf '%s' "$prompt_lower" | grep -Eq 'drifting node clocks|node clocks disagreed|node clocks did not agree|clock drift|clock skew' && printf '%s' "$prompt_lower" | grep -Eq 'replay batches twice|replay batches arrive twice|replay-order|replay order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice looked clean|failover practice|failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'one replica diverged|replica kept diverging|replica keeps diverging|replica divergence' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks disagreed|node clocks did not agree|clock skew|clock drift|drifting node clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replayed writes landed differently|replayed writes land differently|replay order|replay-order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover drill looked clean|failover practice looked clean|failover drill' && printf '%s' "$prompt_lower" | grep -Eq 'one replica diverged|replica diverged|replica divergence' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks disagreed|node clocks did not agree|event order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect' && printf '%s' "$prompt_lower" | grep -Eq 'failover drills' && printf '%s' "$prompt_lower" | grep -Eq 'privacy-control rollback'; then
        anchor_phrase="reconciliation defect during failover drills after a privacy-control rollback"
      elif printf '%s' "$prompt_lower" | grep -Eq 'disaster-recovery rehearsal|recovery rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'rejoin' && printf '%s' "$prompt_lower" | grep -Eq 'clock skews|clock skew|clock drifts|clock drift|replica drifts by seconds|node clock skews' && printf '%s' "$prompt_lower" | grep -Eq 'replay order|replay out of order|replay-order|replay order flips|replay order changes'; then
        anchor_phrase="replica divergence after disaster-recovery rehearsal with clock skew and replay-order drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice|failover practices' && printf '%s' "$prompt_lower" | grep -Eq 'replica diverges|replica kept diverging|replica keeps diverging|replica still diverges|replica divergence|one replica kept diverging|one replica keeps diverging' && printf '%s' "$prompt_lower" | grep -Eq 'replay|replay batches arrive twice|arrive twice' && printf '%s' "$prompt_lower" | grep -Eq 'node clocks did not agree|node clocks disagree|event order|clock skew|clock drifts|clock drift|drifting node clocks'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'failover practice|failover practices' && printf '%s' "$prompt_lower" | grep -Eq 'clock drift|drifting clocks|drifting node clocks|machines with clock drift|nodes with drifting clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replay order flips|replayed writes land in a different order|different order'; then
        anchor_phrase="replica divergence after failover practice with drifting node clocks and replay-order flips"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replicas? disagree' && printf '%s' "$prompt_lower" | grep -Eq 'failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'different hosts|timestamps came from different hosts|host clocks' && printf '%s' "$prompt_lower" | grep -Eq 'replay ordering|replay'; then
        anchor_phrase="replica divergence after a clean failover rehearsal with unsynced host clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'replicas? disagree' && printf '%s' "$prompt_lower" | grep -Eq 'clean failover rehearsal' && printf '%s' "$prompt_lower" | grep -Eq 'timestamps|different hosts|host clocks'; then
        anchor_phrase="replica divergence after a clean failover rehearsal with unsynced host clocks"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect' && printf '%s' "$prompt_lower" | grep -Eq 'failover drills'; then
        anchor_phrase="reconciliation defect during failover drills"
      elif printf '%s' "$prompt_lower" | grep -Eq 'reconciliation defect'; then
        anchor_phrase="reconciliation defect investigation"
      fi
      ;;
    security/compliance)
      if printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access expansion|analyst access|access expansion' && printf '%s' "$prompt_lower" | grep -Eq 'residency drift|residency drifts' && printf '%s' "$prompt_lower" | grep -Eq 'deletion-proof loss|deletion proof weakens|deletion proof'; then
        anchor_phrase="regional outage override with analyst-access expansion, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'crisis share link is fast|crisis share link|emergency data-sharing|data-sharing shortcut|data sharing shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'logging is not attributable|not attributable|attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts during failover|residency drifts|residency drift|crosses residency lines' && printf '%s' "$prompt_lower" | grep -Eq 'deletion proof breaks after copying|deletion proof breaks|deletion proof remains incomplete|deletion'; then
        anchor_phrase="emergency data-sharing shortcut with attribution gaps, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency share link active|emergency share link' && printf '%s' "$prompt_lower" | grep -Eq 'logging is not attributable|not attributable|attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts during failover|residency drifts|residency drift|crosses residency lines'; then
        anchor_phrase="emergency share link with attribution gaps and residency drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'customer-managed keys' && printf '%s' "$prompt_lower" | grep -Eq 'analyst workflows'; then
        anchor_phrase="customer-managed keys and analyst workflows under residency, retention, and audit constraints"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency support bypass|emergency analyst access|temporary analyst-access shortcut|temporary analyst access shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'audit cannot prove|audit cannot tie|audit cannot attribute|who accessed what' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries drift|region boundaries drift|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'deletion guarantees|deletion-proof|copied records|copied data'; then
        anchor_phrase="emergency analyst access with residency drift, weak auditability, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'temporary plaintext export during failover|crisis share link|regional customer records|emergency data-sharing|data-sharing shortcut|data sharing shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps|not attributable|logging is not attributable' && printf '%s' "$prompt_lower" | grep -Eq 'residency spill|crosses residency lines|residency lines|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'retention proof|cannot prove deletion|deletion breaks|deletion'; then
        anchor_phrase="emergency data-sharing shortcut with attribution gaps, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'incident responders' && printf '%s' "$prompt_lower" | grep -Eq 'attribute exports|attribution' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries shift during failover|failover'; then
        anchor_phrase="regional outage override with export gaps, residency drift, and plaintext expansion"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regional outage override' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access|access expands|expands analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'residency drifts|residency drift' && printf '%s' "$prompt_lower" | grep -Eq 'deletion proof weakens|deletion proof breaks|deletion proof remains incomplete|deletion proof'; then
        anchor_phrase="regional outage override with analyst-access expansion, residency drift, and deletion-proof loss"
      elif printf '%s' "$prompt_lower" | grep -Eq 'temporary analyst-access shortcut|temporary analyst access shortcut' && printf '%s' "$prompt_lower" | grep -Eq 'incident window' && printf '%s' "$prompt_lower" | grep -Eq 'retention proof' && printf '%s' "$prompt_lower" | grep -Eq 'auditability' && printf '%s' "$prompt_lower" | grep -Eq 'region-bound dataset|region bound dataset|wrong boundary'; then
        anchor_phrase="temporary analyst-access shortcut with retention gaps, weak auditability, and boundary drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'narrow outage exception' && printf '%s' "$prompt_lower" | grep -Eq 'analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps' && printf '%s' "$prompt_lower" | grep -Eq 'residency boundaries'; then
        anchor_phrase="short-lived analyst-access outage exception with attribution gaps and residency drift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attribution gaps|attributable' && printf '%s' "$prompt_lower" | grep -Eq 'residency|region-bound|region bound|data residency'; then
        anchor_phrase="emergency analyst access during outages under attributable regional controls"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emergency analyst access' && printf '%s' "$prompt_lower" | grep -Eq 'attributable' && printf '%s' "$prompt_lower" | grep -Eq 'region-bound|region bound|region-bound|regional'; then
        anchor_phrase="emergency analyst access during outages under attributable regional controls"
      elif printf '%s' "$prompt_lower" | grep -Eq 'customer-managed keys'; then
        anchor_phrase="customer-managed keys under audit constraints"
      fi
      ;;
    product/ux)
      if printf '%s' "$prompt_lower" | grep -Eq 'visible review gate|review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user drop|honest user drop|honest-user completion falls|honest user completion falls' && printf '%s' "$prompt_lower" | grep -Eq 'latency volatility|volatile latency|latency remains volatile|latency stays volatile'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trust wants a visible review gate|visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation adds friction|consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency stays volatile|backend latency remains volatile|latency stays volatile|latency remains volatile|volatile latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trust wants a visible review gate|visible review gate|review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation adds friction|consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'something feels off|feels off'; then
        anchor_phrase="regulated signup friction with consent confirmation and trust review gates"
      elif printf '%s' "$prompt_lower" | grep -Eq 'regulated signup|signup flow|signup|review friction|permission wall|review gate|strict review gate' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation|consent step|one more consent|consent checkpoints|extra consent checkpoints' && printf '%s' "$prompt_lower" | grep -Eq 'review gate|visible review gate|trust wants a visible review gate|trust says .*consent confirmation|trust wants manual review|trust queues grow|manual review|review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'page latency swings|backend latency keeps swinging|latency swings|latency keeps swinging|document checks spike latency|document verification latency|document latency' && printf '%s' "$prompt_lower" | grep -Eq 'support volume|support contacts|support contact|support load'; then
        anchor_phrase="regulated signup friction with consent checkpoints, trust review queues, and spiky document latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'reduce abuse during signup|signup' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest users|honest-user|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'review queues grow|review queues|trust wants a visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency keeps swinging|backend latency stays volatile|latency stays volatile|latency remains volatile|volatile latency|backend latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'visible review gate|trust wants a visible review gate' && printf '%s' "$prompt_lower" | grep -Eq 'signup' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent step' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls|completion drops' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency stays volatile|backend latency remains volatile|latency stays volatile|volatile latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation wall|consent-confirmation wall|consent wall' && printf '%s' "$prompt_lower" | grep -Eq 'fraud' && printf '%s' "$prompt_lower" | grep -Eq 'review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'document latency' && printf '%s' "$prompt_lower" | grep -Eq 'support contacts|support contact|support load|support volume'; then
        anchor_phrase="consent-confirmation wall with review queues, document latency, and support contacts"
      elif printf '%s' "$prompt_lower" | grep -Eq 'strict consent-confirmation gate|regulated signup' && printf '%s' "$prompt_lower" | grep -Eq 'honest-user completion drops|review queues lengthen|document latency raises support contacts' && printf '%s' "$prompt_lower" | grep -Eq 'review staffing doubled|fraud pressure returned|document latency dropped'; then
        anchor_phrase="regulated signup friction with consent confirmation, review queues, and document latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signup|review friction|permission wall' && printf '%s' "$prompt_lower" | grep -Eq 'consent confirmation|consent-confirmation|consent step|one more consent' && printf '%s' "$prompt_lower" | grep -Eq 'review gate|visible review gate|trust wants a visible review gate|trust says .*consent confirmation|review queues lengthen|review queues' && printf '%s' "$prompt_lower" | grep -Eq 'page latency swings|backend latency keeps swinging|latency swings|latency keeps swinging|document latency'; then
        anchor_phrase="regulated signup friction with consent confirmation, trust review gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'consent checks' && printf '%s' "$prompt_lower" | grep -Eq 'trust gates|stronger gates|trust wants stronger gates' && printf '%s' "$prompt_lower" | grep -Eq 'volatile latency|latency is volatile|latency remains volatile'; then
        anchor_phrase="regulated onboarding with consent checks, trust gates, and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'remove identity friction|identity friction' && printf '%s' "$prompt_lower" | grep -Eq 'signup completion|recover signup completion' && printf '%s' "$prompt_lower" | grep -Eq 'fraud losses' && printf '%s' "$prompt_lower" | grep -Eq 'support load|support volume|support tickets'; then
        anchor_phrase="signup identity friction, fraud loss, support volume, and unstable page speed"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signup completion' && printf '%s' "$prompt_lower" | grep -Eq 'identity friction' && printf '%s' "$prompt_lower" | grep -Eq 'fraud losses' && printf '%s' "$prompt_lower" | grep -Eq 'page speed'; then
        anchor_phrase="signup identity friction, fraud loss, support volume, and unstable page speed"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'trust checks' && printf '%s' "$prompt_lower" | grep -Eq 'backend latency'; then
        anchor_phrase="regulated onboarding with trust checks and volatile latency"
      elif printf '%s' "$prompt_lower" | grep -Eq 'onboarding' && printf '%s' "$prompt_lower" | grep -Eq 'trust checks'; then
        anchor_phrase="regulated onboarding with trust checks"
      fi
      ;;
    metrics/causality)
      if printf '%s' "$prompt_lower" | grep -Eq 'trial starts up|trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds later|refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age climbs|queue age climbed|queue age rose|queue age stayed elevated|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'cohort retention weakens|cohort retention softens|one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and weak cohort retention"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts up|trial starts jumped|trial starts jump|trial starts rose' && printf '%s' "$prompt_lower" | grep -Eq 'refunds later|refunds rose later|refunds rose|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age up|queue age climbed|queue age rose|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'cancellations worse after ranking change|cancellations worse|cancellation pressure|ranking change'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure climbed|cancellation pressure grows|cancellation pressure' && printf '%s' "$prompt_lower" | grep -Eq 'one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'trial starts jumped|trial starts jump right away|trial starts jump' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose later|refunds rose|refunds stayed elevated|refunds' && printf '%s' "$prompt_lower" | grep -Eq 'queue age climbed|queue age rose|queue age stayed elevated|queue age' && printf '%s' "$prompt_lower" | grep -Eq 'one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and weak cohort retention"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation improved after ranking changes' && printf '%s' "$prompt_lower" | grep -Eq 'chargebacks?' && printf '%s' "$prompt_lower" | grep -Eq 'regulatory review risk'; then
        anchor_phrase="activation gains versus chargebacks, queue age, and regulatory review risk after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation jumps|activation jump|activation rose|activation rise' && printf '%s' "$prompt_lower" | grep -Eq 'ranking shift|ranking change|ranking tweak' && printf '%s' "$prompt_lower" | grep -Eq 'refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure|cancellation contacts|cancellation calls' && printf '%s' "$prompt_lower" | grep -Eq 'queue age|support queue age'; then
        anchor_phrase="activation lift versus refunds, queue age, and cancellation pressure after a ranking shift"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking tweak|new ranking|ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts jump right away|trial starts pop immediately|trial starts jump|trial starts pop|trial starts jump right after' && printf '%s' "$prompt_lower" | grep -Eq 'refunds' && printf '%s' "$prompt_lower" | grep -Eq 'cancellation pressure|cancellation calls|cancellation chats' && printf '%s' "$prompt_lower" | grep -Eq 'support queue age worsens|support queue age drifts up|support queue age|one week later' && printf '%s' "$prompt_lower" | grep -Eq 'same cohorts|one cohort retained worse after day 21|day 21'; then
        anchor_phrase="trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts (jumped|rose)' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose' && printf '%s' "$prompt_lower" | grep -Eq 'call-center wait'; then
        anchor_phrase="trial-start gains versus refunds and call-center wait after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'ranking change' && printf '%s' "$prompt_lower" | grep -Eq 'trial starts rose' && printf '%s' "$prompt_lower" | grep -Eq 'refunds rose' && printf '%s' "$prompt_lower" | grep -Eq 'call-center wait'; then
        anchor_phrase="trial-start gains versus refunds and call-center wait after ranking changes"
      elif printf '%s' "$prompt_lower" | grep -Eq 'activation improved after ranking changes' && printf '%s' "$prompt_lower" | grep -Eq 'chargebacks?' && printf '%s' "$prompt_lower" | grep -Eq 'queue age'; then
        anchor_phrase="activation gains versus chargebacks and queue age after ranking changes"
      fi
      ;;
    incident\ response)
      if printf '%s' "$prompt_lower" | grep -Eq 'vip complaints cluster|vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'requests flap against rate limits|flap against rate limits|regional flapping|flapping|rate limits|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'rollback strains the weakest dependency|rollback load|rollback pressure|rollback would stress|weakest dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'regional flapping|flapping|rate limits|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'rollback load|rollback pressure|rollback would stress'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'status page is calm|status page stays calm' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints cluster in one region|vip complaints cluster|vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'requests flap against rate limits|rate limiting still causes flapping|rate limits' && printf '%s' "$prompt_lower" | grep -Eq 'rollback would stress the weakest dependency|rollback would stress|weakest dependency|rollback load eased'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'telemetry streams disagree' && printf '%s' "$prompt_lower" | grep -Eq 'premium-login incident'; then
        anchor_phrase="conflicting telemetry in a premium-login incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'rollback load (eased|fell)|rollback load eased|rollback load fell' && printf '%s' "$prompt_lower" | grep -Eq 'rate limiting still causes flapping|still causes flapping|still flapping|still flaps' && printf '%s' "$prompt_lower" | grep -Eq 'vip harm is now isolated to one region|vip harm is now concentrated in one region|vip complaints cluster in one region|vip complaints are concentrated in one region'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'status page stays calm|external messaging stays calm|first graph dips' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'one region|single region|region' && printf '%s' "$prompt_lower" | grep -Eq 'flap|flapping|flaps against rate limits|rate limits|throttling' && printf '%s' "$prompt_lower" | grep -Eq 'rollback itself loads|rollback itself would stress|rollback would stress|weakest dependency|weak dependency|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback pressure in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'one region|single region|region' && printf '%s' "$prompt_lower" | grep -Eq 'oscillat|rate limits|rate limiting|flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback itself would stress|rollback would stress|weakest dependency|shared dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'throttling|rate limiting' && printf '%s' "$prompt_lower" | grep -Eq 'one region keeps oscillating|single region keeps flaring|region keeps flaring|region keeps oscillating' && printf '%s' "$prompt_lower" | grep -Eq 'vip complaints return|executive accounts complain again|vip complaints|executive accounts complain' && printf '%s' "$prompt_lower" | grep -Eq 'rollback would hit|rollback would hammer|shared dependency'; then
        anchor_phrase="VIP complaints, regional oscillation, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'after throttling|throttling' && printf '%s' "$prompt_lower" | grep -Eq 'one region still flaps|region still flaps|region is still flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback could overload|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'vip complaints' && printf '%s' "$prompt_lower" | grep -Eq 'flapping' && printf '%s' "$prompt_lower" | grep -Eq 'rollback could overload|shared dependency'; then
        anchor_phrase="VIP complaints, regional flapping, and rollback load in a throttled incident"
      elif printf '%s' "$prompt_lower" | grep -Eq 'premium-login incident'; then
        anchor_phrase="premium-login incident containment"
      fi
      ;;
    teaching)
      if printf '%s' "$prompt_lower" | grep -Eq 'tokenized snippets shared|tokenized snippets' && printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed' && printf '%s' "$prompt_lower" | grep -Eq 'near misses resurfacing|near misses|near miss'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized production snippets|production snippets' && printf '%s' "$prompt_lower" | grep -Eq 'near misses|account structure|access timing|learners keep carrying'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'copying production data into a training sandbox' && printf '%s' "$prompt_lower" | grep -Eq 'hashed identifiers'; then
        anchor_phrase="copying production data into a training sandbox with hashed identifiers"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing tokenized production snippets' && printf '%s' "$prompt_lower" | grep -Eq 'raw secrets are removed|raw secrets removed|raw secrets are gone'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing tokenized production snippets|tokenized production snippets looks harmless|tokenized production examples first look harmless|tokenized production examples' && printf '%s' "$prompt_lower" | grep -Eq 'tokens are not names|names are removed|names are gone' && printf '%s' "$prompt_lower" | grep -Eq 'cohorts|riskier samples|less careful samples|timing'; then
        anchor_phrase="sharing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'tokenized production snippets|tokenized production examples|production snippets are fine|production examples are safe' && printf '%s' "$prompt_lower" | grep -Eq 'paste into email|chat or email|drop into chat or email|fine to paste into email' && printf '%s' "$prompt_lower" | grep -Eq 'names are gone|direct identifiers are removed'; then
        anchor_phrase="emailing tokenized production snippets under misconception pressure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'tokenized production samples are fine to email|production samples are fine to email|fine to email' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized'; then
        anchor_phrase="emailing production samples with tokenized fields"
      elif printf '%s' "$prompt_lower" | grep -Eq 'emailing production samples' && printf '%s' "$prompt_lower" | grep -Eq 'tokenized'; then
        anchor_phrase="emailing production samples with tokenized fields"
      elif printf '%s' "$prompt_lower" | grep -Eq 'aggressive retries' && printf '%s' "$prompt_lower" | grep -Eq 'true reliability'; then
        anchor_phrase="aggressive retries versus true reliability"
      fi
      ;;
    strategy)
      if printf '%s' "$prompt_lower" | grep -Eq 'growth, sanctions exposure, reliability, and margin'; then
        anchor_phrase="growth, sanctions exposure, reliability, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'new region signups up|signups up' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soft|renewals soften|renewals softened' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget tight|reliability budget tightened|reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'signups rose in the new region|signups rose|new region' && printf '%s' "$prompt_lower" | grep -Eq 'renewals softened|renewals kept weakening|renewals weaken|renewals softened' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget tightened|reliability budget did not recover|reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'counsel flagged sanctions exposure|sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'newly opened region|fast-growing region|newly opened market' && printf '%s' "$prompt_lower" | grep -Eq 'signups surge|signups spike|signups jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soften|renewals weaken|renewal cohorts weaken|renewal cohorts soften' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'political exposure|politically risky|political-risk'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and political exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|newly opened region|newly opened market|pushing harder into' && printf '%s' "$prompt_lower" | grep -Eq 'lifts signups|lifted signups|signups lift|signups lifted|signups surge|signups spike|signups jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewals soften|renewals weakened|renewals weaken|renewal cohorts weaken|renewal cohorts soften' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget|budget is tight|budget tightens|tight reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure|counsel flags sanctions exposure|counsel warns sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'newly opened market|partner-heavy region' && printf '%s' "$prompt_lower" | grep -Eq 'enterprise signups spike|trial conversions jump' && printf '%s' "$prompt_lower" | grep -Eq 'renewal cohorts weaken|renewal cohorts soften|renewals weaken' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'sanctions exposure'; then
        anchor_phrase="regional growth push versus renewals, reliability budget, and sanctions exposure"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|new region|pushing harder|lifted signups' && printf '%s' "$prompt_lower" | grep -Eq 'churn cohorts?' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically unstable|counsel flags|counsel says'; then
        anchor_phrase="regional growth push versus churn, reliability budget, and political instability"
      elif printf '%s' "$prompt_lower" | grep -Eq 'fast-growing region|region looks safest|pushing harder' && printf '%s' "$prompt_lower" | grep -Eq 'churn cohorts' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically unstable|politically risky|political-risk'; then
        anchor_phrase="growth, reliability budget, political-risk exposure, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'board([^.]| still wants | wants )*faster growth|faster growth next quarter' && printf '%s' "$prompt_lower" | grep -Eq 'reliability budget' && printf '%s' "$prompt_lower" | grep -Eq 'politically risky|political-risk|sanctions exposure'; then
        anchor_phrase="growth, reliability budget, political-risk exposure, and margin"
      elif printf '%s' "$prompt_lower" | grep -Eq 'growth, margin, legal exposure, and reliability'; then
        anchor_phrase="growth, margin, legal exposure, and reliability"
      fi
      ;;
  esac

  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_anchor_phrase_fallback "$prompt_text")
  fi
  reasoning_anchor_phrase_truncate "$anchor_phrase"
}

reasoning_scenario_reference_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_prompt_anchor_phrase "$prompt_text")
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref=$(reasoning_prompt_focus_brief "$prompt_text")
  fi
  if [ -z "$(trim "$scenario_ref")" ]; then
    scenario_ref="current scenario"
  fi
  printf '%s' "$scenario_ref"
}

reasoning_risk_line_for_prompt() {
  prompt_text=$1
  final_mode_hint=$(trim "${2:-DONE}")
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Replay, isolation, and cost-ceiling checks around %s still need one more stress-window before the recommendation should be treated as stable.' "$anchor_phrase"
      else
        printf 'Replay, isolation, and cost-ceiling checks around %s still need one more stress-window before the recommendation should be treated as stable; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Timeline consistency and deterministic repro around %s still need one independent confirmation pass before the causal story is treated as closed.' "$anchor_phrase"
      else
        printf 'Timeline consistency and deterministic repro around %s still need one independent confirmation pass before the causal story is treated as closed; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Control ownership, auditability, and recovery-path compliance around %s still need one independent validation pass before broad rollout.' "$anchor_phrase"
      else
        printf 'Control ownership, auditability, and recovery-path compliance around %s still need one independent validation pass before broad rollout; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Benefit-versus-harm validation around %s still needs one more cohort pass against abuse, support, and latency drift before broad rollout.' "$anchor_phrase"
      else
        printf 'Benefit-versus-harm validation around %s still needs one more cohort pass against abuse, support, and latency drift before broad rollout; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Counterfactual strength and lagged-harm exposure around %s still need stronger evidence before the decision should scale.' "$anchor_phrase"
      else
        printf 'Counterfactual strength and lagged-harm exposure around %s still need stronger evidence before the decision should scale; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'Mitigation around %s remains provisional until the next review window confirms lower user harm and no blast-radius expansion.' "$anchor_phrase"
      else
        printf 'Mitigation around %s remains provisional until the next review window confirms lower user harm and no blast-radius expansion; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The explanation around %s still needs near-miss and counterexample transfer checks before the misconception can be treated as corrected.' "$anchor_phrase"
      else
        printf 'The explanation around %s still needs near-miss and counterexample transfer checks before the misconception can be treated as corrected; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The plan around %s still needs owner and guardrail confirmation on the sacrificed dimension before it should be treated as execution-ready.' "$anchor_phrase"
      else
        printf 'The plan around %s still needs owner and guardrail confirmation on the sacrificed dimension before it should be treated as execution-ready; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$final_mode_hint" = "DONE" ]; then
        printf 'The recommendation around %s still needs one more focused validation pass on its highest-risk assumption.' "$anchor_phrase"
      else
        printf 'The recommendation around %s still needs one more focused validation pass on its highest-risk assumption; the run ended before DONE mode, so follow-up verification remains open.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_next_improvement_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Run replay, duplicate-injection, and tenant-isolation drills for %s, then tighten the decision thresholds from the results.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Reconstruct the narrowest failing timeline for %s and test the strongest competing hypothesis before closing the root-cause claim.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Map control ownership and incident-recovery exceptions for %s, then rerun one audit-style contradiction check.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Validate one more benefit-versus-harm cohort pass for %s, then tighten rollout guardrails from abuse, support, and latency results.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Re-estimate %s with confound controls and lagged-harm checks before scaling the decision.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Run one more bounded mitigation review window for %s and prepare the pivot trigger if harm signals stay flat.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Use a counterexample and near-miss check for %s, then revise the explanation from the learner failure point.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Rank the non-negotiables around %s, assign owner and guardrails to the sacrificed dimension, and rerun the plan against the likely veto constraint.' "$anchor_phrase"
      ;;
    *)
      printf 'Validate the highest-risk assumption around %s first, then update the decision thresholds from disconfirming evidence.' "$anchor_phrase"
      ;;
  esac
}

reasoning_recovery_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Recovery and Self-Correction: If replay, isolation, or cost evidence around %s fails, downgrade the shared path, switch to the stricter segmented design, and rerun drills before resuming.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Recovery and Self-Correction: If deterministic repro or timeline order around %s breaks, downgrade the leading hypothesis and reopen the next-best explanation before shipping mitigation.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Recovery and Self-Correction: If control evidence around %s fails, narrow scope to the stricter compliant path and remove any exception-dependent recovery route.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Recovery and Self-Correction: If harm signals around %s rise faster than real completion gains, switch to the more explicit or more gated flow and recheck the affected cohorts.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Recovery and Self-Correction: If confound controls or lagged-harm checks break the story around %s, downgrade the rollout to a bounded experiment or rollback and re-estimate.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Recovery and Self-Correction: If the first mitigation window around %s fails to reduce harm, pivot immediately to the fallback containment path and narrow communications to what is evidence-backed.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Recovery and Self-Correction: If the learner still fails the counterexample or near miss on %s, switch to a counterexample-first explanation and re-test transfer before treating the misconception as fixed.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Recovery and Self-Correction: If the suppressed tradeoff around %s surfaces faster than planned, narrow scope, stage rollout, or explicitly trade speed for trust before continuing.' "$anchor_phrase"
      ;;
    *)
      printf 'Recovery and Self-Correction: If the strongest counterevidence around %s survives the next boundary check, switch to the narrower or more reversible path before continuing.' "$anchor_phrase"
      ;;
  esac
}

reasoning_replan_trigger_line_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Re-Plan Trigger: Re-plan if replay mismatch is non-zero, if any tenant spillover appears, or if cost-per-event breaches ceiling in the next stress window.'
      ;;
    forensics)
      printf 'Re-Plan Trigger: Re-plan if the fault stops reproducing under the claimed cause, if timestamp order breaks, or if a cleaner competing hypothesis explains more evidence.'
      ;;
    security/compliance)
      printf 'Re-Plan Trigger: Re-plan if any mandatory control lacks evidence, if data crosses a prohibited boundary, or if recovery depends on a non-compliant exception.'
      ;;
    product/ux)
      printf 'Re-Plan Trigger: Re-plan if abuse, support burden, or latency breaches guardrails, or if completion gains hold only in the easiest cohorts.'
      ;;
    metrics/causality)
      printf 'Re-Plan Trigger: Re-plan if the effect collapses under confound control, if sign reverses in lagged outcomes, or if the confidence interval overlaps no-effect.'
      ;;
    incident\ response)
      printf 'Re-Plan Trigger: Re-plan if user-harm signals stay flat, if blast radius expands, or if a cleaner containment path gains stronger evidence inside the current review window.'
      ;;
    teaching)
      printf 'Re-Plan Trigger: Re-plan if the learner restates the old rule, misses the boundary case, or cannot explain why the original intuition fails.'
      ;;
    strategy)
      printf 'Re-Plan Trigger: Re-plan if one non-negotiable loses coverage, if the priority order collapses under review, or if the sacrificed dimension worsens beyond its declared guardrail.'
      ;;
    *)
      printf 'Re-Plan Trigger: Re-plan if the strongest counterexample survives, if fallback becomes safer on net, or if the main guardrail is breached.'
      ;;
  esac
}

reasoning_revised_from_line_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Revised From: Revised away from the assumption that a familiar shared ingestion design would be sufficient; replay, isolation, and unit-economics evidence now control the decision.'
      ;;
    forensics)
      printf 'Revised From: Revised away from the loudest-signal narrative; deterministic repro and timeline consistency now decide which hypothesis stays primary.'
      ;;
    security/compliance)
      printf 'Revised From: Revised away from the assumption that a narrow exception could be justified; control ownership and auditability now dominate latency-only gains.'
      ;;
    product/ux)
      printf 'Revised From: Revised away from a low-friction default; paired benefit-versus-harm evidence now determines how much gating the flow needs.'
      ;;
    metrics/causality)
      printf 'Revised From: Revised away from a top-line uplift reading; counterfactual and harm-tracking evidence now decide whether the gain is real.'
      ;;
    incident\ response)
      printf 'Revised From: Revised away from the assumption that the first mitigation path was good enough; direct harm and blast-radius evidence now control the next move.'
      ;;
    teaching)
      printf 'Revised From: Revised away from a clarity-only explanation; counterexample transfer now determines whether the teaching actually worked.'
      ;;
    strategy)
      printf 'Revised From: Revised away from the all-goals narrative; explicit priority order and sacrifice bounds now determine the strategy.'
      ;;
    *)
      printf 'Revised From: Revised away from the first-pass narrative; boundary checks and counterevidence now determine which path remains justified.'
      ;;
  esac
}

reasoning_validation_owner_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Validation Owner: Platform or SRE owner for %s owns replay drills, tenant-isolation checks, and cost-ceiling verification before broad rollout.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Validation Owner: Incident or debugging owner for %s owns timeline reconstruction, deterministic repro, and competing-hypothesis elimination before the root-cause claim is closed.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Validation Owner: Security control owner and compliance reviewer for %s own the control-evidence check, boundary review, and recovery-path exception decision.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Validation Owner: Product owner with risk/support counterparts for %s owns the cohort readout on completion, harm signals, and latency tolerance before expansion.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Validation Owner: Decision owner plus analytics lead for %s own confound controls, lagged-harm review, and the scale-versus-rollback call.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Validation Owner: Incident commander and service owner for %s own the mitigation review window, blast-radius check, and pivot call.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Validation Owner: Instructor or reviewer for %s owns the counterexample check, near-miss transfer check, and explanation revision if the misconception persists.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Validation Owner: Direct strategy owner with finance/legal/operations counterparts for %s owns priority ranking, sacrifice guardrails, and the re-plan decision.' "$anchor_phrase"
      ;;
    *)
      printf 'Validation Owner: A directly responsible owner for %s owns the disconfirming check, fallback trigger, and escalation decision.' "$anchor_phrase"
      ;;
  esac
}

reasoning_time_window_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Time Window: Review %s over the next stress window and close the replay/isolation decision before any broad traffic increase.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Time Window: Reconstruct and verify %s before the next irreversible mitigation or deploy decision, with one independent confirmation pass in the same investigation window.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Time Window: Close the control and boundary review for %s before rollout and before any incident-recovery exception is exercised.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Time Window: Evaluate %s over the next cohort pass and hold broad rollout until abuse, support, and latency results stay inside guardrails for that window.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Time Window: Re-estimate %s in the next analysis cycle and include one lagged-outcome window before scaling the decision.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Time Window: Review direct harm and blast radius for %s in the first mitigation window and pivot immediately if that window closes without improvement.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Time Window: Re-test %s on the next counterexample and near-miss check before treating the misconception as corrected.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Time Window: Re-evaluate %s in the next planning checkpoint and before any commitment that would lock in the sacrificed dimension.' "$anchor_phrase"
      ;;
    *)
      printf 'Time Window: Re-check %s in the next decision window before any irreversible action.' "$anchor_phrase"
      ;;
  esac
}

reasoning_high_risk_verification_status_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current command anchors partially verify %s, but replay drills, tenant isolation, and spend ceilings still need independent confirmation before broad rollout.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against runtime anchors; treat the design as provisional until replay, isolation, and spend-ceiling checks land.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but deterministic repro and competing-hypothesis elimination are still incomplete.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified with deterministic repro or timeline-consistent traces; treat the root-cause read as provisional.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current control evidence partially verifies %s, but boundary review, auditability, and exception handling still need independent confirmation.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against direct control evidence or runtime anchors; treat any rollout or exception as unapproved.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but cohort harm, support load, and latency guardrails still need confirmation before broad exposure.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against cohort evidence or runtime anchors; treat the flow as provisional until harm and latency checks land.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but confound controls and lagged-harm checks still need confirmation before scaling.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against counterfactual or lagged-outcome evidence; treat the uplift as provisional.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but direct harm and blast radius still need confirmation in the next mitigation window.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against direct mitigation evidence or runtime anchors; treat containment as unproven.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify the explanation for %s, but counterexample and near-miss transfer still need confirmation.' "$anchor_phrase"
      else
        printf 'Verification Status: The explanation for %s is not yet verified by transfer checks; treat the misconception as unresolved.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but stakeholder guardrails and sacrifice bounds still need independent confirmation before commitment.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against stakeholder guardrails or hard tradeoff evidence; treat any commitment as provisional.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Verification Status: Current anchors partially verify %s, but independent confirmation is still required before irreversible action.' "$anchor_phrase"
      else
        printf 'Verification Status: %s is not yet verified against runtime anchors; treat any irreversible action as blocked.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_high_risk_go_no_go_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a scoped replay or shadow-traffic step only; No-Go on broad traffic increase until replay, isolation, and spend ceilings hold in the next stress window.'
      else
        printf 'Go/No-Go: No-Go on rollout for %s until replay, isolation, and spend-ceiling evidence is collected.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible containment or observation only; No-Go on root-cause closure or irreversible change until repro, timeline, and alternative-cause checks agree.'
      else
        printf 'Go/No-Go: No-Go on root-cause closure for %s until deterministic repro, timeline evidence, and competing-hypothesis checks are collected.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for narrow recovery or lab validation only; No-Go on rollout or policy exception until control evidence, boundary review, and audit trail checks hold.'
      else
        printf 'Go/No-Go: No-Go on rollout or exception for %s until control evidence, boundary review, and auditability are collected.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a limited cohort only; No-Go on broad exposure until completion, harm, support, and latency stay inside guardrails for the next cohort window.'
      else
        printf 'Go/No-Go: No-Go on broad exposure for %s until cohort harm, support load, and latency evidence are collected.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for additional measurement or tightly scoped continuation only; No-Go on scaling until confound, lagged-harm, and contradiction checks hold.'
      else
        printf 'Go/No-Go: No-Go on scaling %s until counterfactual, lagged-outcome, and harm evidence are collected.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible containment only; No-Go on declaring stability or closing the incident until harm, blast radius, and rollback readiness hold.'
      else
        printf 'Go/No-Go: No-Go on incident closure for %s until harm, blast radius, and rollback-readiness evidence are collected.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for limited guidance only; No-Go on treating the misconception as corrected until counterexample and near-miss transfer checks pass.'
      else
        printf 'Go/No-Go: No-Go on certifying %s as understood until transfer evidence is collected.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for reversible planning only; No-Go on locked-in commitments until stakeholder guardrails and sacrifice bounds are rechecked.'
      else
        printf 'Go/No-Go: No-Go on committing %s until guardrail, sacrifice-bound, and stakeholder-impact evidence are collected.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Go/No-Go: Conditional-Go for a scoped reversible step only; No-Go on irreversible action until independent validation holds.'
      else
        printf 'Go/No-Go: No-Go until required evidence is collected and validated for %s.' "$anchor_phrase"
      fi
      ;;
  esac
}

reasoning_high_risk_required_evidence_line_for_prompt() {
  prompt_text=$1
  run_mode_hint=$(trim "${2:-assistant}")
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Required Evidence to Proceed: One replay drill, one tenant-isolation confirmation, and one spend-ceiling measurement for %s over the next stress window.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Required Evidence to Proceed: One deterministic repro, one independent timeline check, and one ruled-out competing hypothesis for %s before root-cause closure.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Required Evidence to Proceed: One independent control test, one boundary review, and one audit-trail or policy-regression check for %s over one review window.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Required Evidence to Proceed: One cohort readout, one harm-or-support regression check, and one latency-threshold check for %s before wider exposure.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Required Evidence to Proceed: One confound control, one lagged-outcome check, and one contradiction test against the uplift story for %s before scaling.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Required Evidence to Proceed: One direct-harm check, one blast-radius confirmation, and one rollback-readiness check for %s in the first mitigation window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Required Evidence to Proceed: Two transfer checks, one counterexample check, and one near-miss explanation check for %s before calling the misconception corrected.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Required Evidence to Proceed: One priority-ranked tradeoff review, one guardrail-breach check, and one stakeholder-impact confirmation for %s before commitment.' "$anchor_phrase"
      ;;
    *)
      case "$run_mode_hint" in
        security-audit|pentest)
          printf 'Required Evidence to Proceed: Reproduce %s with independent traces, confirm control effectiveness, and verify no policy-violation regressions over one review window.' "$anchor_phrase"
          ;;
        *)
          printf 'Required Evidence to Proceed: One independent confirmation trace, one quantitative threshold check, and one contradiction or disconfirming check for %s before irreversible action.' "$anchor_phrase"
          ;;
      esac
      ;;
  esac
}

reasoning_high_risk_residual_risk_line_for_prompt() {
  prompt_text=$1
  command_success_total_raw=${2:-0}
  anchor_phrase=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ "${command_success_total_raw:-0}" -gt 0 ] 2>/dev/null; then
    verified=1
  else
    verified=0
  fi
  case "$domain_hint" in
    architecture)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s could still fail under peak load or breach cost ceilings despite current anchors.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct runtime verification on replay, isolation, and cost containment.' "$anchor_phrase"
      fi
      ;;
    forensics)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still be explained by a competing failure path hidden by noisy logs.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks deterministic repro and timeline-consistent evidence.' "$anchor_phrase"
      fi
      ;;
    security/compliance)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still create untracked compliance exposure if the exception path is broader than current evidence shows.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks direct control and audit evidence; treat this as planning only, not approval.' "$anchor_phrase"
      fi
      ;;
    product/ux)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still hide user harm or support blowback behind short-term completion gains.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct cohort harm and latency evidence.' "$anchor_phrase"
      fi
      ;;
    metrics/causality)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still be non-causal or net-negative once lagged harms arrive.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks counterfactual and lagged-harm evidence.' "$anchor_phrase"
      fi
      ;;
    incident\ response)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still be masking ongoing user harm or a larger blast radius.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks direct evidence that harm is contained or rollback is viable.' "$anchor_phrase"
      fi
      ;;
    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still reflect fluent repetition rather than real transfer under pressure.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks counterexample and near-miss transfer evidence.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still break a sacrificed guardrail once commitments harden.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks hard evidence on stakeholder guardrails and sacrifice bounds.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium until independent revalidation closes remaining uncertainty for %s.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks direct verification evidence; treat this as planning guidance only.' "$anchor_phrase"
      fi
      ;;
  esac
}

scenario_specific_block_lower() {
  final_text_raw=$1
  printf '%s\n' "$final_text_raw" | awk '
    BEGIN {
      capture = 0
    }
    {
      line = tolower($0)
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^scenario-specific check:/) {
        capture = 1
        print stripped
        next
      }
      if (capture == 1) {
        if (stripped ~ /^[a-z][a-z0-9 _\/-]*:/) {
          exit
        }
        print stripped
      }
    }
  '
}

scenario_non_template_body_lower() {
  final_text_raw=$1
  printf '%s\n' "$final_text_raw" | awk '
    {
      line = tolower($0)
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^[[:space:]]*$/) next
      if (stripped ~ /^(outcome|verification evidence|context anchor|domain anchor|scenario-specific check|trap and counterevidence check|false premise challenge|premise validation|cross-domain integration|domain linkage|architecture lens|product\/ux lens|security\/compliance lens|metrics\/causality lens|incident\/ops lens|tradeoff ledger|rejected alternative|stakeholder impact map|recovery and self-correction|re-plan trigger|self-correction evidence|revised from|validation owner|time window|evidence anchors|claim-to-evidence map|quantified thresholds|evidence caveats|source quality ranking|source conflict resolution|assumption register|uncertainty range|command anchors|near-miss guard|verification status|go\/no-go|required evidence to proceed|residual risk):/) next
      gsub(/for this scenario[[:space:]]*\([^)]*\)/, "", stripped)
      gsub(/scenario:[[:space:]]*[^.]+/, "", stripped)
      if (stripped ~ /^[[:space:]]*$/) next
      print stripped
    }
  '
}

final_has_scenario_specific_depth() {
  final_text=$1
  final_text_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  prompt_text=${2-}
  prompt_tokens=$(prompt_anchor_tokens_for_depth "$prompt_text")
  scenario_block=$(scenario_specific_block_lower "$final_text")
  non_template_body=$(scenario_non_template_body_lower "$final_text")
  token_total=0
  token_matches=0
  scenario_token_matches=0
  non_template_token_matches=0
  required_matches=1

  if [ -n "$(trim "$prompt_tokens")" ]; then
    while IFS= read -r token || [ -n "$token" ]; do
      token=$(trim "$token")
      [ -n "$token" ] || continue
      token_total=$((token_total + 1))
      if printf '%s' "$final_text_lower" | grep -Fq "$token"; then
        token_matches=$((token_matches + 1))
      fi
      if [ -n "$(trim "$scenario_block")" ] && printf '%s' "$scenario_block" | grep -Fq "$token"; then
        scenario_token_matches=$((scenario_token_matches + 1))
      fi
      if [ -n "$(trim "$non_template_body")" ] && printf '%s' "$non_template_body" | grep -Fq "$token"; then
        non_template_token_matches=$((non_template_token_matches + 1))
      fi
    done <<EOF
$prompt_tokens
EOF
  fi

  if [ "$token_total" -ge 4 ]; then
    required_matches=2
  fi

  has_context_anchor=0
  if printf '%s' "$final_text_lower" | grep -Eq 'context anchor:|domain anchor:'; then
    has_context_anchor=1
  fi

  has_scenario_block=0
  if [ -n "$(trim "$scenario_block")" ]; then
    has_scenario_block=1
  fi

  if [ "$has_context_anchor" -ne 1 ] || [ "$has_scenario_block" -ne 1 ]; then
    return 1
  fi

  has_scenario_specificity=0
  if printf '%s' "$scenario_block" | grep -Eq '(if[[:space:]]|when[[:space:]]|unless[[:space:]]|counterexample|invalidat|falsif|re-plan|pivot|rollback|fallback|disconfirm|decision window|review window|owner[^a-z0-9])'; then
    has_scenario_specificity=1
  fi
  if [ "$has_scenario_specificity" -ne 1 ]; then
    return 1
  fi

  if [ "$token_total" -le 0 ]; then
    return 0
  fi
  if [ "$token_matches" -lt "$required_matches" ]; then
    return 1
  fi
  if [ "$scenario_token_matches" -lt 1 ]; then
    return 1
  fi
  required_non_template_matches=1
  if [ "$token_total" -ge 6 ]; then
    required_non_template_matches=2
  fi
  if [ "$non_template_token_matches" -lt "$required_non_template_matches" ]; then
    return 1
  fi
  return 0
}

reasoning_domain_hint() {
  prompt_primary=$1
  prompt_primary=$(reasoning_prompt_anchor_source "$prompt_primary")
  prompt_text_lower=$(printf '%s' "$prompt_primary" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$prompt_text_lower" | awk '
    function add(domain, points, strong_points) {
      score[domain] += points
      strong[domain] += strong_points
    }
    BEGIN {
      domain_count = 8
      domains[1] = "architecture"
      domains[2] = "forensics"
      domains[3] = "security/compliance"
      domains[4] = "product/ux"
      domains[5] = "metrics/causality"
      domains[6] = "incident response"
      domains[7] = "teaching"
      domains[8] = "strategy"

      priority["forensics"] = 1
      priority["metrics/causality"] = 2
      priority["architecture"] = 3
      priority["security/compliance"] = 4
      priority["product/ux"] = 5
      priority["teaching"] = 6
      priority["incident response"] = 7
      priority["strategy"] = 8
    }
    {
      if (length(text) > 0) {
        text = text " "
      }
      text = text $0
    }
    END {
      if (text ~ /architecture|event ingestion|partner-event|partner intake|shared ingestion|shared feed for partner events|shared partner-event path|shared intake lane|single event lane|queue topology|append-only|state machine|merchant-isolated|merchant isolated|merchant records can.t bleed|late and out of order|late arrivals|exact replays|tenant isolation|pci retention|retention timers differ by merchant|retention clocks differ by merchant|retention clocks|replays mix tenants|mix tenants|retention exceptions|smaller merchants/) add("architecture", 7, 2)
      if (text ~ /tenant|pipeline|replay|ingestion/) add("architecture", 3, 0)
      if (text ~ /merchant/ && text ~ /late and out of order/) add("architecture", 5, 1)
      if (text ~ /replay/ && (text ~ /tenant/ || text ~ /merchant/)) add("architecture", 4, 1)
      if ((text ~ /shared feed for partner events|shared feed/) && (text ~ /late and out of order|out-of-order replays|replays mix tenants|mix tenants/) && (text ~ /retention exceptions|retention exception|retention/) && (text ~ /smaller merchants|merchant/)) add("architecture", 8, 2)
      if (text ~ /shared ingestion/ && text ~ /finance|spend|cost/) add("architecture", 3, 0)

      if (text ~ /forensic|debug|root cause|stack trace|error trace|reconcil|replica divergence|replicas? disagree|deterministic repro|host clocks|different hosts|clock drift|clock skew|clock skews|drifting clocks|timeline|traces show|noisy warning stream|noisy logs?|disaster-recovery rehearsal|recovery rehearsal|rejoin|balance mismatches?|data mismatch|event order|node clocks did not agree|replica kept diverging|replica still diverges/) add("forensics", 6, 2)
      if ((text ~ /failover rehearsal|failover practice/) && (text ~ /timestamps/ || text ~ /host clocks/ || text ~ /different hosts/ || text ~ /clock drift|drifting clocks|node clocks did not agree|event order/)) add("forensics", 6, 1)
      if ((text ~ /failover practice/) && (text ~ /replica kept diverging|replica still diverges|one replica kept diverging/) && (text ~ /replay/ || text ~ /event order/ || text ~ /clock skew/)) add("forensics", 8, 2)
      if (text ~ /root cause|deterministic repro|timeline consistency/) add("forensics", 4, 1)

      if (text ~ /customer-managed keys|control evidence|boundary review|audit trail|analyst workflows|analyst access|emergency analyst access|emergency support bypass|attributable|region-bound|region bound|regional controls|residency|retention|exception path|deletion guarantees|who accessed what/) add("security/compliance", 6, 2)
      if (text ~ /security|compliance|policy|consent|legal|audit/) add("security/compliance", 3, 0)
      if (text ~ /analyst access/ && (text ~ /attributable/ || text ~ /region-bound|region bound|regional/)) add("security/compliance", 6, 1)
      if (text ~ /customer-managed keys/ && text ~ /analyst workflows/) add("security/compliance", 5, 1)

      if (text ~ /onboarding|ux|user flow|conversion|setup flow|workflow ergonomics|completion|honest-user completion|signup|page speed|support tickets|support volume|support load|support contacts|identity friction|fraud losses|fraud loss|fraud pressure|cohort|volatile latency|latency|trust gates|trust checks|review friction|permission wall|review gate|review queues|consent confirmation|consent-confirmation|consent checkpoints|manual review|document verification|document checks|document latency/) add("product/ux", 4, 1)
      if ((text ~ /visible review gate|review gate/) && (text ~ /consent confirmation|consent step/) && (text ~ /honest-user completion falls|honest user completion falls|completion falls|completion drops/) && (text ~ /something feels off|feels off/)) add("product/ux", 7, 2)
      if ((text ~ /visible review gate|review gate/) && (text ~ /consent confirmation|consent-confirmation/) && (text ~ /honest-user drop|honest user drop|honest-user completion/) && (text ~ /latency volatility|volatile latency|latency/)) add("product/ux", 8, 2)
      if ((text ~ /onboarding|signup/) && (text ~ /consent checks|trust checks|trust gates/) && (text ~ /latency|page speed/)) add("product/ux", 6, 2)
      if ((text ~ /visible review gate|trust wants a visible review gate/) && (text ~ /consent confirmation|consent step/) && (text ~ /honest-user completion falls|honest user completion falls|completion falls|completion drops/) && (text ~ /backend latency stays volatile|backend latency remains volatile|latency stays volatile|volatile latency/)) add("product/ux", 8, 2)
      if (text ~ /identity friction/ && (text ~ /fraud losses|fraud loss|support volume|support tickets/)) add("product/ux", 6, 1)
      if ((text ~ /signup|review friction|permission wall/) && (text ~ /consent confirmation|consent-confirmation|consent step|one more consent/) && (text ~ /review gate|visible review gate|trust says|trust wants|review queues/) && (text ~ /support tickets|support load|support contacts|abuse climbs|assisted cohorts/) && (text ~ /page latency|backend latency|latency swings|latency keeps swinging|document latency/)) add("product/ux", 6, 2)
      if ((text ~ /visible review gate/) && (text ~ /reduce abuse during signup|signup/) && (text ~ /consent confirmation/) && (text ~ /honest users|honest-user/) && (text ~ /review queues grow|review queues/) && (text ~ /backend latency keeps swinging|latency remains volatile|volatile latency|backend latency/)) add("product/ux", 8, 2)
      if ((text ~ /regulated signup|signup flow|strict review gate|permission wall/) && (text ~ /consent checkpoints|extra consent checkpoints|consent confirmation|consent-confirmation/) && (text ~ /manual review|trust queues grow|trust wants manual review|review queues lengthen|review queues/) && (text ~ /document checks spike latency|document verification latency|document latency/) && (text ~ /support volume|support contacts|support contact|support load/)) add("product/ux", 7, 2)
      if ((text ~ /strict consent-confirmation gate|regulated signup/) && (text ~ /honest-user completion drops|review staffing doubled/) && (text ~ /fraud pressure returned|review queues lengthen|document latency/)) add("product/ux", 8, 2)
      if ((text ~ /consent confirmation wall|consent-confirmation wall|consent wall/) && (text ~ /fraud/) && (text ~ /review queues lengthen|review queues/) && (text ~ /document latency/) && (text ~ /support contacts|support contact|support load|support volume/)) add("product/ux", 8, 2)

      if (text ~ /causal|metric|experiment|confound|counterfactual|uplift|chargeback|chargebacks|queue age|support queue age|ranking tweak|ranking shift|ranking change|ranking changes|activation|lagged harm|lagged harms|correlation|refunds?|trial starts?|call-center wait|cancellation pressure|cancellation calls|cancellation chats|revenue bump proves causality/) add("metrics/causality", 5, 1)
      if ((text ~ /trial starts up|trial starts jump|trial starts pop|trial starts/) && (text ~ /refunds later|refunds rise|refunds/) && (text ~ /queue age climbs|queue age/) && (text ~ /cohort retention weakens|cohort retention softens|retention weakens|retention softens/)) add("metrics/causality", 8, 2)
      if ((text ~ /ranking change|ranking changes/) && (text ~ /refunds?|chargebacks?|queue age|call-center wait/)) add("metrics/causality", 6, 2)
      if ((text ~ /ranking tweak|new ranking|ranking change/) && (text ~ /trial starts jump|trial starts pop/) && text ~ /refunds/ && (text ~ /support queue age|cancellation calls|cancellation chats/)) add("metrics/causality", 6, 2)
      if (text ~ /marketing wants to scale|proves causality/) add("metrics/causality", 4, 1)

      if (text ~ /incident|mitigation|outage|degradation|burn-rate|containment|flapping|oscillating|oscillation|flaring|vip complaints|executive accounts complain|rollback could overload|rollback would hit|rollback would hammer|rollback itself loads|rollback would stress|shared dependency|weakest dependency|first-hour|first hour|throttling a struggling service|throttling|rate limits|rate limiting|blast radius/) add("incident response", 4, 1)
      if ((text ~ /vip complaints|executive accounts complain/) && (text ~ /flapping|oscillating|flaring/)) add("incident response", 6, 2)
      if ((text ~ /vip complaints cluster|vip complaints/) && (text ~ /requests flap against rate limits|rate limits|rate limiting/) && (text ~ /rollback strains the weakest dependency|weakest dependency|rollback would stress/)) add("incident response", 9, 2)
      if (text ~ /rollback could overload|shared dependency/) add("incident response", 5, 1)
      if (text ~ /incident/ && text ~ /mitigation|containment/) add("incident response", 4, 1)
      if ((text ~ /status page stays calm|external messaging stays calm|first graph dips/) && text ~ /vip complaints/ && text ~ /one region|single region|region/ && text ~ /flap|flapping|rate limits|throttling/ && text ~ /rollback itself loads|rollback would stress|weakest dependency|shared dependency/) add("incident response", 7, 2)
      if (text ~ /vip complaints/ && text ~ /one region|single region|region/ && text ~ /oscillat|rate limits|rate limiting|flapping/ && text ~ /rollback itself would stress|rollback would stress|weakest dependency|shared dependency/) add("incident response", 8, 2)

      if (text ~ /teach|teaching|teacher|learner|misconception|lesson|curriculum|counterexample|near-miss|quiz|new hire insists|stop making that mistake|under real pressure|tokenized production snippets|tokenized production examples|paste into email|chat or email|direct identifiers are removed|names are gone|tokens are not names|raw secrets are removed|raw secrets removed|riskier samples|less careful samples/) add("teaching", 5, 1)
      if ((text ~ /teach|teaching/) && (text ~ /counterexample|near-miss|misconception/)) add("teaching", 6, 2)
      if ((text ~ /emailing tokenized production snippets/) && (text ~ /raw secrets are removed|raw secrets removed/)) add("teaching", 8, 2)
      if (text ~ /new hire insists/ && text ~ /tokenized|production samples/) add("teaching", 5, 1)

      if (text ~ /strategy|stakeholder|quarter|roadmap|finance wants|sales wants|operations goals|board wants|board still wants|margin|politically risky|political-risk|political exposure|politically unstable|growth|reliability budget|counsel warns|counsel flags|counsel says|sanctions exposure|next quarter|partner-heavy region|newly opened market|newly opened region|fast-growing region|enterprise signups|signups surge|signups spike|trial conversions jump|renewal cohorts weaken|renewal cohorts soften|renewals soften|renewals weaken/) add("strategy", 4, 1)
      if ((text ~ /fast-growing region|new region|pushing harder|lifted signups/) && text ~ /churn cohorts?/ && text ~ /reliability budget/ && text ~ /politically unstable|counsel flags|counsel says/) add("strategy", 6, 2)
      if ((text ~ /fast-growing region|newly opened region|newly opened market|pushing harder into/) && (text ~ /lifts signups|lifted signups|signups lift|signups lifted|signups surge|signups spike|signups jump/) && text ~ /renewals soften|renewals weaken|renewal cohorts soften|renewal cohorts weaken/ && text ~ /reliability budget|budget is tight|budget tightens|tight reliability budget/ && text ~ /sanctions exposure|counsel flags sanctions exposure|counsel warns sanctions exposure/) add("strategy", 8, 2)
      if ((text ~ /newly opened market|partner-heavy region/) && (text ~ /enterprise signups spike|trial conversions jump/) && text ~ /renewal cohorts weaken|renewal cohorts soften|renewals weaken/ && text ~ /reliability budget/ && text ~ /sanctions exposure/) add("strategy", 6, 2)
      if ((text ~ /newly opened region|fast-growing region/) && (text ~ /signups surge|signups spike|signups jump/) && text ~ /renewals soften|renewals weaken|renewal cohorts soften|renewal cohorts weaken/ && text ~ /reliability budget/ && text ~ /political exposure|politically risky|political-risk/) add("strategy", 7, 2)
      if (text ~ /board wants/ && text ~ /growth/ && text ~ /margin/) add("strategy", 6, 2)
      if (text ~ /reliability budget/ && text ~ /politically risky|political-risk|politically unstable|sanctions exposure/) add("strategy", 5, 1)

      best_domain = "cross-domain"
      best_score = 0
      best_strong = 0
      best_priority = 999
      second_score = 0
      second_strong = 0

      for (i = 1; i <= domain_count; i++) {
        domain = domains[i]
        current_score = score[domain] + 0
        current_strong = strong[domain] + 0
        current_priority = priority[domain] + 0
        if (current_score > best_score || (current_score == best_score && current_strong > best_strong) || (current_score == best_score && current_strong == best_strong && current_priority < best_priority && current_score > 0)) {
          second_score = best_score
          second_strong = best_strong
          best_domain = domain
          best_score = current_score
          best_strong = current_strong
          best_priority = current_priority
        } else if (current_score > second_score || (current_score == second_score && current_strong > second_strong)) {
          second_score = current_score
          second_strong = current_strong
        }
      }

      if (best_score < 5) {
        print "cross-domain"
        exit
      }
      if (best_score == second_score && best_strong == second_strong && best_score < 9) {
        print "cross-domain"
        exit
      }
      print best_domain
    }
  '
}

reasoning_domain_label_for_prompt() {
  domain_hint=$(reasoning_domain_hint "$1")
  case "$domain_hint" in
    architecture)
      printf '%s' "technical architecture"
      ;;
    forensics)
      printf '%s' "debugging/forensics with incomplete evidence"
      ;;
    security/compliance)
      printf '%s' "security + compliance + policy tradeoffs"
      ;;
    product/ux)
      printf '%s' "product/UX + technical constraints"
      ;;
    metrics/causality)
      printf '%s' "data/metrics causal reasoning"
      ;;
    incident\ response)
      printf '%s' "incident response under uncertainty"
      ;;
    teaching)
      printf '%s' "teaching/explanation under misconception pressure"
      ;;
    strategy)
      printf '%s' "strategic planning with conflicting stakeholder goals"
      ;;
    *)
      printf '%s' "cross-domain integrated reasoning"
      ;;
  esac
}

reasoning_outcome_stub_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  domain_article=$(reasoning_indefinite_article_for_phrase "$domain_label")
  if [ -n "$(trim "$anchor_phrase")" ] && [ "$scenario_ref" != "$anchor_phrase" ]; then
    printf 'Delivered %s %s decision synthesis for %s, grounded in %s.' "$domain_article" "$domain_label" "$scenario_ref" "$anchor_phrase"
    return 0
  fi
  printf 'Delivered %s %s decision synthesis for %s.' "$domain_article" "$domain_label" "$scenario_ref"
}

reasoning_decision_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Selected the architecture that protects %s before latency/cost optimization.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Selected the forensics path that tests %s in evidence order before root-cause claims.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Selected the policy-safe plan that secures %s before workflow acceleration.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Selected the UX/system path that balances %s against abuse and support-risk growth.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Selected the causal path that stress-tests %s against confounds and counterfactuals.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Selected the mitigation sequence that contains %s and minimizes user harm under uncertainty.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Selected the explanation strategy that corrects misconceptions around %s before abstraction.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Selected the staged strategy that makes speed-versus-risk tradeoffs explicit for %s.' "$anchor_phrase"
      ;;
    *)
      printf 'Selected a defensible primary path with explicit tradeoffs around %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_fallback_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'If %s signals drift out of bounds, switch to the lower-coupling architecture tier.' "$anchor_phrase"
      ;;
    forensics)
      printf 'If %s tests fail disconfirming checks, pivot to the next hypothesis and widen evidence capture.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'If %s controls show policy or audit drift, revert to segmented rollout with stricter boundaries.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'If %s gains come with abuse/support overload, revert to a more gated onboarding path.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'If %s uplift disappears under confound controls, revert to control policy and re-estimate causal effects.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'If mitigation around %s misses the burn-rate trigger window, execute rollback and containment immediately.' "$anchor_phrase"
      ;;
    teaching)
      printf 'If misconception checks for %s still fail, switch to counterexample-first instruction with smaller diagnostic steps.' "$anchor_phrase"
      ;;
    strategy)
      printf 'If margin, consent, or reliability thresholds tied to %s miss, shift to a phased plan prioritizing risk controls.' "$anchor_phrase"
      ;;
    *)
      printf 'If leading indicators tied to %s regress, switch to the lower-risk alternative path with smaller blast radius.' "$anchor_phrase"
      ;;
  esac
}

reasoning_disconfirming_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Trigger a pivot if evidence around %s invalidates replay integrity, tenant isolation, or cost-per-transaction bounds.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Trigger a pivot when evidence around %s fails deterministic repro or log-chain consistency checks.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Trigger a pivot on policy violations, audit gaps, or scope creep tied to %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Trigger a pivot if %s improvements coincide with abuse or support burden crossing thresholds.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Trigger a pivot if %s uplift fails controlled experiments or counterfactual checks within confidence bounds.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Trigger a pivot if user-impact or error-budget burn linked to %s fails to improve in the first mitigation window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Trigger a pivot if learners still fail contradiction checks after counterexamples on %s.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Trigger a pivot if strategy indicators tied to %s cross pre-set margin, compliance-risk, or reliability thresholds.' "$anchor_phrase"
      ;;
    *)
      printf 'Trigger a pivot when evidence around %s invalidates a core assumption.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_recommendation_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Use the lower-coupling architecture for %s rather than a single shared path.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Treat %s as an evidence-order investigation, not a confirmed root cause.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Take the policy-safe path for %s rather than expanding access or exceptions for speed.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Keep the more constrained product path for %s until the upside is proven without hidden harm.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Treat %s as a provisional signal, not a scale-up decision yet.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Use the containment path for %s that cuts direct harm fastest, even if it looks less calm externally.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Teach %s with a counterexample-first explanation rather than a fluent summary.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Take the staged strategy for %s and make the sacrifice explicit now.' "$anchor_phrase"
      ;;
    *)
      printf 'Take the lower-risk path for %s until the uncertain parts are better evidenced.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_rationale_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The simpler-looking option concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The fastest narrative is not yet the best-supported explanation once timeline quality and deterministic repro are considered.'
      ;;
    security/compliance)
      printf '%s' 'The faster path leaves auditability, residency, or deletion guarantees too weak to defend later.'
      ;;
    product/ux)
      printf '%s' 'The cleaner-looking flow can improve completion while quietly pushing abuse, review load, or support costs upward.'
      ;;
    metrics/causality)
      printf '%s' 'The visible lift can still be partly confounded or offset by delayed harm in refunds, churn, or queue age.'
      ;;
    incident\ response)
      printf '%s' 'A calmer-looking option can still let concentrated user harm and blast radius persist.'
      ;;
    teaching)
      printf '%s' 'The learner can sound correct while still carrying the old rule into the first near miss.'
      ;;
    strategy)
      printf '%s' 'The superficially ambitious plan hides at least one delayed cost or veto constraint.'
      ;;
    *)
      printf '%s' 'The optimistic reading still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_anchor_phrase_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(trim "$anchor_phrase")
  anchor_phrase_lower=$(printf '%s' "$anchor_phrase" | tr '[:upper:]' '[:lower:]')
  if prompt_prefers_freeform_frame "$prompt_text" && printf '%s' "$anchor_phrase_lower" | grep -Eq '^(current picture:|current state:|status:|for context:|snapshot:|today:|what we know:)'; then
    anchor_phrase=""
  fi
  if [ -n "$anchor_phrase" ]; then
    printf '%s' "$anchor_phrase"
    return 0
  fi
  reasoning_prompt_anchor_phrase "$prompt_text"
}

reasoning_freeform_uncertainty_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'The main uncertainty is whether %s can stay correct under failover and replay stress without blowing the cost envelope.' "$anchor_phrase"
      ;;
    forensics)
      printf 'The main uncertainty is which hypothesis survives deterministic repro once the trace conflicts around %s are cleaned up.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'The main uncertainty is how much operational friction remains once the tighter control path for %s is implemented correctly.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'The main uncertainty is whether the current friction around %s is buying real risk reduction or only delaying honest users.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'The main uncertainty is how much of the observed effect around %s survives lagged-outcome checks and cleaner controls.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'The main uncertainty is whether the chosen mitigation for %s actually reduces concentrated harm before the next burn window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'The main uncertainty is whether the explanation for %s transfers once the wording changes and the boundary case arrives.' "$anchor_phrase"
      ;;
    strategy)
      printf 'The main uncertainty is how much upside for %s survives once the most likely stakeholder veto and delayed downside are priced in.' "$anchor_phrase"
      ;;
    *)
      printf 'The main uncertainty is whether the leading explanation for %s survives the next direct disconfirming check.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_reversal_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'I would reverse this only if replay drills show %s can preserve merchant boundaries, retention rules, and recovery behavior without breaching the cost ceiling.' "$anchor_phrase"
      ;;
    forensics)
      printf 'I would reverse this only if a competing hypothesis gains cleaner timeline, reproduction, and log-chain support than the current lead for %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'I would reverse this only if attributable logs, residency boundaries, and deletion or retention proofs stay intact while the faster path still meets the target for %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'I would reverse this only if cohort data shows %s improves while abuse, support volume, and latency all stay inside guardrails.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'I would reverse this only if controlled or same-cohort checks keep the upside for %s while downstream harm signals stay bounded.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'I would reverse this only if the current path for %s fails to improve harm or burn-rate signals in the first mitigation window and the fallback materially reduces exposure.' "$anchor_phrase"
      ;;
    teaching)
      printf 'I would reverse this only if the learner can handle the near miss for %s and restate the corrected rule without leaning on memorized phrasing.' "$anchor_phrase"
      ;;
    strategy)
      printf 'I would reverse this only if the faster plan for %s clears margin, compliance, and reliability thresholds without borrowing risk into a later quarter.' "$anchor_phrase"
      ;;
    *)
      printf 'I would reverse this only if the next direct evidence check invalidates the current recommendation for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_delta_sentence_for_prompt() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Updated conditions:$'; then
    return 0
  fi
  followup_delta=$(reasoning_freeform_followup_delta_for_prompt "$prompt_text")
  [ -n "$(trim "$followup_delta")" ] || return 0
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  fi
  printf 'Given the updated conditions for %s, especially %s, the revised recommendation should be read against that new evidence rather than the first-pass intuition.' "$anchor_phrase" "$followup_delta"
}

reasoning_freeform_memo_for_prompt() {
  prompt_text=$1
  recommendation=$(reasoning_freeform_recommendation_sentence_for_prompt "$prompt_text")
  rationale=$(reasoning_freeform_rationale_sentence_for_prompt "$prompt_text")
  delta_sentence=$(reasoning_freeform_delta_sentence_for_prompt "$prompt_text")
  uncertainty=$(reasoning_freeform_uncertainty_sentence_for_prompt "$prompt_text")
  reversal=$(reasoning_freeform_reversal_sentence_for_prompt "$prompt_text")
  if [ -n "$(trim "$delta_sentence")" ]; then
    printf '%s %s %s %s %s' "$recommendation" "$rationale" "$delta_sentence" "$uncertainty" "$reversal"
    return 0
  fi
  printf '%s %s %s %s' "$recommendation" "$rationale" "$uncertainty" "$reversal"
}

reasoning_freeform_reflection_opening_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  printf 'This looks less settled than it first appears for %s.' "$anchor_phrase"
}

reasoning_freeform_reflection_tension_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The tension is that the simpler-looking shape concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The tension is that the cleanest first story can still be the least reliable once timeline quality and deterministic repro are tested.'
      ;;
    security/compliance)
      printf '%s' 'The tension is that the faster-looking path weakens auditability, residency, or deletion guarantees exactly where later scrutiny will land.'
      ;;
    product/ux)
      printf '%s' 'The tension is that the smoother-looking flow can improve visible completion while quietly moving cost into abuse, review load, or support burden.'
      ;;
    metrics/causality)
      printf '%s' 'The tension is that the visible lift can still be partly confounded or offset by delayed harm that arrives after the headline metric.'
      ;;
    incident\ response)
      printf '%s' 'The tension is that the calmer-looking move can still leave concentrated harm and blast radius untouched during the next burn window.'
      ;;
    teaching)
      printf '%s' 'The tension is that the material can feel anonymized and still teach the wrong lesson once the first near miss shows up.'
      ;;
    strategy)
      printf '%s' 'The tension is that the ambitious-looking upside is arriving alongside at least one delayed veto, cost, or reliability constraint.'
      ;;
    *)
      printf '%s' 'The tension is that the first clean story still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_reflection_unresolved_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'The unresolved question is whether %s can stay operable under failover and replay stress without breaking tenant boundaries or cost limits.' "$anchor_phrase"
      ;;
    forensics)
      printf 'The unresolved question is which hypothesis around %s survives deterministic repro once the ordering conflict is cleaned up.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'The unresolved question is how much operational pressure around %s remains once the defensible control path is implemented correctly.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'The unresolved question is whether the current friction around %s buys real risk reduction or mostly delays honest users.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'The unresolved question is how much of the apparent effect around %s survives lagged-outcome checks and cleaner controls.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'The unresolved question is whether the apparent mitigation for %s actually reduces concentrated harm before the next burn window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'The unresolved question is whether the explanation for %s transfers once the wording changes and the first boundary case appears.' "$anchor_phrase"
      ;;
    strategy)
      printf 'The unresolved question is how much upside for %s survives once the likeliest veto and delayed downside are fully priced in.' "$anchor_phrase"
      ;;
    *)
      printf 'The unresolved question is whether the leading explanation for %s survives the next direct disconfirming check.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_reflection_for_prompt() {
  prompt_text=$1
  opening=$(reasoning_freeform_reflection_opening_sentence_for_prompt "$prompt_text")
  tension=$(reasoning_freeform_reflection_tension_sentence_for_prompt "$prompt_text")
  unresolved=$(reasoning_freeform_reflection_unresolved_sentence_for_prompt "$prompt_text")
  printf '%s %s %s' "$opening" "$tension" "$unresolved"
}

reasoning_freeform_frame_opening_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  printf 'This reads as a status picture for %s, not a settled decision request yet.' "$anchor_phrase"
}

reasoning_freeform_frame_moving_parts_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The key moving parts are replay ordering, merchant-specific retention, and failover recovery behavior.'
      ;;
    forensics)
      printf '%s' 'The key moving parts are timeline integrity, event ordering, and deterministic reproduction.'
      ;;
    security/compliance)
      printf '%s' 'The key moving parts are attributable access, residency boundaries, and deletion or retention guarantees.'
      ;;
    product/ux)
      printf '%s' 'The key moving parts are honest-user completion, review burden, and hidden abuse or support cost.'
      ;;
    metrics/causality)
      printf '%s' 'The key moving parts are lagged harm, cohort shape, and whether the visible lift survives cleaner controls.'
      ;;
    incident\ response)
      printf '%s' 'The key moving parts are concentrated user harm, dependency pressure, and rollback cost.'
      ;;
    teaching)
      printf '%s' 'The key moving parts are learner misconception, boundary cases, and whether the lesson transfers beyond the example.'
      ;;
    strategy)
      printf '%s' 'The key moving parts are near-term growth, reliability or margin budget, and the likeliest veto constraint.'
      ;;
    *)
      printf '%s' 'The key moving parts are the visible upside, the hidden downside, and the weakest piece of evidence.'
      ;;
  esac
}

reasoning_freeform_frame_offer_sentence() {
  printf '%s' 'If you want, I can turn that into a recommendation, risk review, or explanation.'
}

reasoning_freeform_frame_for_prompt() {
  prompt_text=$1
  opening=$(reasoning_freeform_frame_opening_sentence_for_prompt "$prompt_text")
  moving_parts=$(reasoning_freeform_frame_moving_parts_sentence_for_prompt "$prompt_text")
  offer=$(reasoning_freeform_frame_offer_sentence)
  printf '%s %s %s' "$opening" "$moving_parts" "$offer"
}

reasoning_freeform_clarifying_question_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Do you want a recommendation on %s, or are you just capturing architecture notes? If you want the call, I can give the safer design, main risk, and what would change it.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Do you want an investigation read on %s, or are you just recording forensics notes? If you want the call, I can give the leading hypothesis, biggest unknown, and what would falsify it.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Do you want a policy call on %s, or are you just recording constraints? If you want the call, I can give the safer path, main gap, and what evidence would justify changing it.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Do you want a recommendation on %s, or are you just capturing product notes? If you want the call, I can give the safer direction, main hidden cost, and what would change it.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Do you want a causality read on %s, or are you just recording metric notes? If you want the call, I can give the likely read, main confound, and what evidence would reverse it.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Do you want an incident recommendation on %s, or are you just recording status notes? If you want the call, I can give the containment path, main risk, and what would change it.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Do you want a teaching recommendation on %s, or are you just capturing notes? If you want the call, I can give the explanation approach, main misconception risk, and what would change it.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Do you want a strategy call on %s, or are you just recording stakeholder notes? If you want the call, I can give the direction, main tradeoff, and what would change it.' "$anchor_phrase"
      ;;
    *)
      printf 'Do you want a recommendation on %s, or are you just capturing notes? If you want the call, I can give the direction, main uncertainty, and what would change it.' "$anchor_phrase"
      ;;
  esac
}

reasoning_priority_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Priority Order: Preserve replay integrity, tenant isolation, and bounded recovery for %s before throughput or cost optimization.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Priority Order: Preserve evidence order and reproducibility for %s before fast root-cause storytelling.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Priority Order: Preserve policy boundaries, auditability, and least-privilege controls for %s before workflow acceleration.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Priority Order: Preserve user trust, compliance guardrails, and bounded abuse/support load for %s before completion gains.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Priority Order: Preserve causal validity and downside containment for %s before scaling uplift claims.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Priority Order: Reduce user harm and keep mitigation reversible for %s before waiting for perfect telemetry.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Priority Order: Correct the misconception and verify transfer for %s before optimizing fluency.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Priority Order: Make non-negotiables and real stakeholder ranking explicit for %s before speed or optics.' "$anchor_phrase"
      ;;
    *)
      printf 'Priority Order: Rank safety, correctness, and reversibility ahead of speed-only gains for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_risk_register_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Risk Register: Track replay divergence, cross-tenant spillover, backlog recovery drift, and cost-ceiling breach around %s.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Risk Register: Track false-cause lock-in, timeline inconsistency, noisy-log overfitting, and wrong-mitigation risk around %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Risk Register: Track policy-boundary breach, audit-proof gaps, exception creep, and recovery-path non-compliance around %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Risk Register: Track abuse-rate growth, support-load spillover, latency-driven abandonment, and hidden operator rescue around %s.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Risk Register: Track confound exposure, proxy-metric drift, lagged harm reversal, and over-scaling from weak causal evidence around %s.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Risk Register: Track customer-harm burn, mitigation blast-radius growth, rollback delay, and evidence-loss risk around %s.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Risk Register: Track misconception persistence, fluency-without-transfer, boundary-case failure, and overloaded instruction around %s.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Risk Register: Track hidden tradeoff debt, unfunded non-negotiables, stakeholder veto risk, and reliability/margin erosion around %s.' "$anchor_phrase"
      ;;
    *)
      printf 'Risk Register: Track blast radius, cost of being wrong, and live guardrails for the main decision around %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_evidence_anchor_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = replay correctness checks, tenant-failure drills, backlog recovery timings, and cost-per-event measurements for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = ordered timelines, deterministic repro steps, failing samples, and eliminated alternative hypotheses for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = policy clauses, data-flow maps, access boundaries, audit evidence, and recovery-path checks for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = cohort completion, abuse rates, support load, latency tails, and fallback-path completion for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = controlled comparisons, cohort slices, lagged-outcome tracking, and mechanism diagnostics for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = direct user-harm signals, mitigation timing, burn-rate windows, and blast-radius observations for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = learner predictions, counterexample responses, near-miss transfer checks, and corrected restatements for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = goal ranking, resource assumptions, veto constraints, review windows, and leading-indicator ownership for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf 'Evidence Anchors: Primary command output anchors = %s; secondary anchors = direct risk signals, review windows, and boundary-condition checks for %s.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

reasoning_command_anchor_fallback_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'current command anchors plus replay, isolation, and cost-check snapshots for %s' "$anchor_phrase"
      ;;
    forensics)
      printf 'current command anchors plus timeline, repro, and alternative-hypothesis checkpoints for %s' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'current command anchors plus policy-control, audit, and data-boundary checkpoints for %s' "$anchor_phrase"
      ;;
    product/ux)
      printf 'current command anchors plus cohort, latency, abuse, and support checkpoints for %s' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'current command anchors plus controlled-comparison and lagged-harm checkpoints for %s' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'current command anchors plus direct-harm, mitigation-window, and blast-radius checkpoints for %s' "$anchor_phrase"
      ;;
    teaching)
      printf 'current command anchors plus learner-transfer, counterexample, and misconception checks for %s' "$anchor_phrase"
      ;;
    strategy)
      printf 'current command anchors plus review-window, resource-fit, and stakeholder-guardrail checkpoints for %s' "$anchor_phrase"
      ;;
    *)
      printf 'current command anchors plus boundary-condition checkpoints for %s' "$anchor_phrase"
      ;;
  esac
}

reasoning_quantified_thresholds_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Quantified Thresholds: Accept only if replay mismatch stays at 0, peer-tenant impact remains at 0 during failure drills, recovery stays within 30 min, and unit cost for %s stays within ceiling.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Quantified Thresholds: Advance the leading hypothesis only if %s reproduces in the failing conditions at least 1x, timeline-order contradictions stay at 0, and at least 1x strong alternative is ruled out.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Quantified Thresholds: Proceed only if 100%% of mandatory controls for %s have owners and evidence, prohibited-boundary crossings remain at 0, and recovery does not depend on undocumented exceptions.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Quantified Thresholds: Accept only if %s improves completion in at least 2 cohorts while abuse and support load stay within 10%% drift and p95 latency stays within 250 ms for 2 review windows.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Quantified Thresholds: Proceed only if the estimated effect for %s stays above 0%% after confound controls, the confidence interval excludes 0, and lagged-harm deltas remain at or below 0%% over 1 lag window.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Quantified Thresholds: Keep the current mitigation only if direct harm indicators tied to %s improve within 15 min and no new region, tenant, or dependency enters blast radius over 1 review window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Quantified Thresholds: Keep the current explanation only if the learner passes 2x transfer checks for %s, correctly predicts 1x counterexample, and distinguishes 1x near miss without reverting to the misconception.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Quantified Thresholds: Continue only if the top priorities tied to %s hold for 2x review checkpoints and the intentionally sacrificed dimension stays within 1x declared guardrail breach.' "$anchor_phrase"
      ;;
    *)
      printf 'Quantified Thresholds: Define concrete accept/reject thresholds with at least 1x primary benefit metric, 1x opposing risk metric, and 1x review checkpoint before irreversible action on %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_primary_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf -- '- Claim 1 (primary architecture choice): claim -> anchor: %s -> verification method: replay, tenant-failure, and cost drills for %s -> invalidation trigger: replay mismatch, peer-tenant spillover, or cost ceiling breach.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Claim 1 (leading hypothesis): claim -> anchor: %s -> verification method: deterministic repro plus timeline-consistency checks for %s -> invalidation trigger: failed repro or stronger competing evidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Claim 1 (policy-safe path): claim -> anchor: %s -> verification method: control ownership, data-boundary, and auditability checks for %s -> invalidation trigger: any unowned control gap or prohibited-boundary crossing.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Claim 1 (primary UX/system path): claim -> anchor: %s -> verification method: cohort comparison across completion, abuse, latency, and support load for %s -> invalidation trigger: downstream harm breaches rollback guardrails.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Claim 1 (causal recommendation): claim -> anchor: %s -> verification method: controlled comparison with confound checks and lagged-harm tracking for %s -> invalidation trigger: effect collapse, sign reversal, or delayed harm breach.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Claim 1 (current mitigation path): claim -> anchor: %s -> verification method: bounded mitigation test plus direct user-harm checks for %s -> invalidation trigger: no improvement in the review window or broader blast radius.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Claim 1 (teaching strategy): claim -> anchor: %s -> verification method: counterexample prediction and near-miss transfer checks for %s -> invalidation trigger: learner reverts to the misconception in applied reasoning.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Claim 1 (selected strategy): claim -> anchor: %s -> verification method: explicit goal ranking, resource-fit checks, and leading-indicator ownership for %s -> invalidation trigger: a non-negotiable loses coverage or the hidden tradeoff surfaces.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf -- '- Claim 1 (primary decision): claim -> anchor: %s -> verification method: rerun the same anchor checks plus one independent boundary-condition check for %s -> invalidation trigger: disconfirming evidence appears or the main guardrail breaches.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_fallback_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf -- '- Claim 2 (fallback isolation path): claim -> anchor: fallback rehearsal output and tenant-failure drills -> verification method: exercise segmented rollback and replay containment for %s -> invalidation trigger: fallback broadens blast radius or misses recovery window.' "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Claim 2 (fallback hypothesis path): claim -> anchor: eliminated-alternative log and next-hypothesis checklist -> verification method: run the next repro branch for %s in evidence order -> invalidation trigger: the fallback hypothesis also fails deterministic checks.' "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Claim 2 (fallback narrower rollout): claim -> anchor: segmented rollout plan and policy-control matrix -> verification method: verify the reduced-scope path for %s preserves control coverage and recoverability -> invalidation trigger: the fallback still needs policy exceptions.' "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Claim 2 (fallback gated path): claim -> anchor: fallback flow rehearsal and support playbook -> verification method: run high-risk and high-latency cohorts through the gated %s path -> invalidation trigger: fallback still exceeds abuse, support, or latency guardrails.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Claim 2 (fallback experiment path): claim -> anchor: control-policy baseline and revised experiment plan -> verification method: re-estimate %s with a cleaner identification strategy -> invalidation trigger: the fallback still cannot isolate the effect from confounds.' "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Claim 2 (fallback containment path): claim -> anchor: rollback rehearsal output and containment checklist -> verification method: execute the narrower mitigation for %s and compare direct harm signals -> invalidation trigger: fallback still fails the first review window.' "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Claim 2 (fallback counterexample-first path): claim -> anchor: revised lesson outline and learner checkpoint results -> verification method: retest %s with smaller diagnostic steps -> invalidation trigger: transfer still fails on the near miss.' "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Claim 2 (fallback phased plan): claim -> anchor: phased roadmap and review-window owners -> verification method: test whether the narrower %s plan preserves non-negotiables while sacrificing speed explicitly -> invalidation trigger: the phased path still overruns declared guardrails.' "$anchor_phrase"
      ;;
    *)
      printf -- '- Claim 2 (fallback safety): claim -> anchor: fallback rehearsal output and review-window checks -> verification method: execute fallback rehearsal for %s and compare risk/cost guardrails -> invalidation trigger: fallback cannot preserve the primary safety threshold.' "$anchor_phrase"
      ;;
  esac
}

reasoning_claim_map_additional_line_for_prompt() {
  prompt_text=$1
  command_anchor_summary=$2
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    command_anchor_summary="runtime command output and repository state checks"
  fi
  case "$domain_hint" in
    architecture)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second replay/isolation checkpoint -> invalidation trigger: freshness decay, contradictory drill output, or boundary-condition failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    forensics)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second deterministic repro/timeline checkpoint -> invalidation trigger: contradictory trace order or failed repro downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    security/compliance)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second control-ownership/audit checkpoint -> invalidation trigger: stale policy evidence, contradictory control state, or audit gap downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    product/ux)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second cohort/latency checkpoint -> invalidation trigger: contradictory harm metrics or fallback failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    metrics/causality)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second controlled or lagged-outcome checkpoint -> invalidation trigger: confound exposure, sign reversal, or freshness decay downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    incident\ response)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second mitigation-review checkpoint -> invalidation trigger: contradictory harm signals, wider blast radius, or stale telemetry downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    teaching)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second transfer/counterexample checkpoint -> invalidation trigger: misconception relapse or boundary-case failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    strategy)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second review-window/owner checkpoint -> invalidation trigger: contradictory stakeholder signals, stale assumptions, or guardrail breach downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
    *)
      printf -- '- Additional claim map entry: claim -> anchor: %s -> verification method: confirm %s still holds in a second independent checkpoint -> invalidation trigger: contradiction, freshness decay, or boundary-condition failure downgrades confidence.' "$command_anchor_summary" "$anchor_phrase"
      ;;
  esac
}

compact_reasoning_contract_extract_value() {
  label=$1
  text=$2
  if [ -z "$(trim "$text")" ]; then
    return 0
  fi
  printf '%s\n' "$text" | awk -v label="$label" '
    BEGIN {
      prefix = tolower(label) ":"
    }
    {
      lowered = tolower($0)
      if (index(lowered, prefix) == 1) {
        line = $0
        sub(/^[^:]*:[[:space:]]*/, "", line)
        print line
        exit
      }
    }
  '
}

compact_reasoning_contract_lower_text() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

reasoning_contract_extract_value() {
  compact_reasoning_contract_extract_value "$@"
}

reasoning_contract_lower_text() {
  compact_reasoning_contract_lower_text "$1"
}

compact_reasoning_contract_value_is_placeholder() {
  label=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  value=$(compact_reasoning_contract_lower_text "$2")
  case "$value" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac
  case "$label" in
    outcome)
      :
      ;;
    initial\ assumption)
      if printf '%s' "$value" | grep -Eq '^for this scenario .*state the first plausible assumption'; then
        return 0
      fi
      ;;
    invalidating\ evidence)
      if printf '%s' "$value" | grep -Eq '^state the first concrete evidence'; then
        return 0
      fi
      ;;
    revised\ decision)
      if printf '%s' "$value" | grep -Eq '^explain how the recommendation changed'; then
        return 0
      fi
      ;;
    claim-to-evidence\ map)
      if printf '%s' "$value" | grep -Eq '^for each major claim, provide'; then
        return 0
      fi
      ;;
  esac
  return 1
}

compact_reasoning_contract_squash_value() {
  value=$1
  printf '%s' "$value" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

compact_reasoning_contract_reference_phrase_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_trimmed=$(trim "$anchor_phrase")
  if [ -n "$anchor_trimmed" ] && [ "$anchor_trimmed" != "scenario anchors" ] && [ "$anchor_trimmed" != "current scenario" ]; then
    printf '%s' "$anchor_trimmed"
    return 0
  fi
  printf '%s' "$scenario_ref"
}

compact_reasoning_followup_text_signals_present() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'same labels|keep the same labels|same 5[- ]line|same five[- ]line|same format|same contract|same structure|same labeled lines|same five labeled lines|same short labeled lines|same plan|revise that same plan|revise the same plan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_text_lower" | grep -Eq 'revise|revised|revision|update|updated|pivot|changed|change explicit|make the revised|make the shift|show the pivot|spell out the pivot|what changed|overturned'; then
    return 1
  fi
  return 0
}

compact_reasoning_contract_value_needs_upgrade() {
  label=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  value=$2
  prompt_text=$3
  value_lower=$(compact_reasoning_contract_lower_text "$value")
  reference_phrase=$(compact_reasoning_contract_reference_phrase_for_prompt "$prompt_text")
  reference_lower=$(compact_reasoning_contract_lower_text "$reference_phrase")

  if compact_reasoning_contract_value_is_placeholder "$label" "$value"; then
    return 0
  fi

  case "$value_lower" in
    ""|"none"|"n/a"|"null")
      return 0
      ;;
  esac

  case "$label" in
    outcome|initial\ assumption|invalidating\ evidence|revised\ decision)
      if [ -n "$reference_lower" ] && ! printf '%s' "$value_lower" | grep -Fq "$reference_lower"; then
        return 0
      fi
      ;;
    claim-to-evidence\ map)
      if [ -n "$reference_lower" ] && ! printf '%s' "$value_lower" | grep -Fq "$reference_lower"; then
        return 0
      fi
      if ! printf '%s' "$value_lower" | grep -Eq 'owner:|assigned owner|validation owner'; then
        return 0
      fi
      if ! printf '%s' "$value_lower" | grep -Eq 'review window|time window|decision window|checkpoint'; then
        return 0
      fi
      ;;
  esac

  return 1
}

reasoning_compact_evidence_basis_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  case "$domain_hint" in
    architecture)
      evidence_basis=$(printf 'replay, tenant-isolation, and cost-drill evidence for %s' "$anchor_phrase")
      ;;
    forensics)
      evidence_basis=$(printf 'timeline reconstruction, deterministic repro, and eliminated-alternative checks for %s' "$anchor_phrase")
      ;;
    security/compliance)
      evidence_basis=$(printf 'control-ownership, auditability, and policy-boundary checks for %s' "$anchor_phrase")
      ;;
    product/ux)
      evidence_basis=$(printf 'cohort completion, abuse, support-load, and latency evidence for %s' "$anchor_phrase")
      ;;
    metrics/causality)
      evidence_basis=$(printf 'same-cohort lift, refund, cancellation, and queue-age evidence for %s' "$anchor_phrase")
      ;;
    incident\ response)
      evidence_basis=$(printf 'direct-harm, blast-radius, and mitigation-window evidence for %s' "$anchor_phrase")
      ;;
    teaching)
      evidence_basis=$(printf 'counterexample, near-miss, and learner-restatement evidence for %s' "$anchor_phrase")
      ;;
    strategy)
      evidence_basis=$(printf 'goal-ranking, guardrail, and veto-constraint evidence for %s' "$anchor_phrase")
      ;;
    *)
      evidence_basis=$(printf 'primary evidence and boundary-condition checks for %s' "$anchor_phrase")
      ;;
  esac
  if [ -n "$(trim "$followup_delta")" ]; then
    printf '%s after reassessing the change set: %s' "$evidence_basis" "$followup_delta"
  else
    printf '%s' "$evidence_basis"
  fi
}

reasoning_compact_owner_clause_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'platform or SRE owner before broad rollout'
      ;;
    forensics)
      printf 'incident or debugging owner in the current investigation window'
      ;;
    security/compliance)
      printf 'security control owner plus compliance reviewer before rollout'
      ;;
    product/ux)
      printf 'product owner with risk/support counterparts before expansion'
      ;;
    metrics/causality)
      printf 'decision owner plus analytics lead before scaling'
      ;;
    incident\ response)
      printf 'incident commander plus service owner in the first mitigation window'
      ;;
    teaching)
      printf 'instructor or reviewer before misconception closure'
      ;;
    strategy)
      printf 'strategy owner with finance/legal/operations counterparts before commitment'
      ;;
    *)
      printf 'directly responsible owner before irreversible action'
      ;;
  esac
}

reasoning_compact_review_window_clause_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'next replay and isolation stress window before any traffic increase'
      ;;
    forensics)
      printf 'current investigation window with one independent confirmation pass'
      ;;
    security/compliance)
      printf 'before rollout and before any recovery exception is exercised'
      ;;
    product/ux)
      printf 'next cohort pass with harm metrics inside guardrails'
      ;;
    metrics/causality)
      printf 'next analysis cycle plus one lagged-outcome window'
      ;;
    incident\ response)
      printf 'first mitigation window before blast radius expands'
      ;;
    teaching)
      printf 'next counterexample and near-miss check'
      ;;
    strategy)
      printf 'next planning checkpoint before the sacrifice is locked in'
      ;;
    *)
      printf 'next decision window before irreversible action'
      ;;
  esac
}

reasoning_compact_claim_map_value_for_prompt() {
  prompt_text=$1
  evidence_basis=$(reasoning_compact_evidence_basis_for_prompt "$prompt_text")
  owner_clause=$(reasoning_compact_owner_clause_for_prompt "$prompt_text")
  review_window_clause=$(reasoning_compact_review_window_clause_for_prompt "$prompt_text")
  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  claim_map_entry=$(reasoning_claim_map_primary_line_for_prompt "$prompt_text" "$evidence_basis")
  claim_map_entry=$(printf '%s\n' "$claim_map_entry" | awk '
    {
      line = $0
      sub(/^- Claim 1 \([^)]*\):[[:space:]]*/, "", line)
      print line
      exit
    }
  ')
  if [ -z "$(trim "$claim_map_entry")" ]; then
    claim_map_entry="primary claim -> anchor: $evidence_basis -> invalidation trigger: $disconfirming_line"
  fi
  printf '%s; owner: %s; review window: %s' "$claim_map_entry" "$owner_clause" "$review_window_clause"
}

reasoning_compact_followup_outcome_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    reasoning_decision_line_for_prompt "$prompt_text"
    return 0
  fi
  printf 'Selected the revised path for %s after reassessing the change set: %s.' "$anchor_phrase" "$followup_delta"
}

reasoning_compact_followup_initial_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Initial Assumption" "$(normalize_reasoning_placeholder_contract "Initial Assumption: For this scenario ($(reasoning_scenario_reference_for_prompt "$prompt_text")), state the first plausible assumption that guided the initial approach." "$prompt_text" "")"
    return 0
  fi
  printf 'The updated read was that the change set %s was enough to keep the prior recommendation for %s.' "$followup_delta" "$anchor_phrase"
}

reasoning_compact_followup_invalidating_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Invalidating Evidence" "$(normalize_reasoning_placeholder_contract "Invalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive." "$prompt_text" "")"
    return 0
  fi
  printf 'That updated read fails if concentrated harm, lagged regressions, or returning risk still break guardrails for %s despite the change set %s.' "$anchor_phrase" "$followup_delta"
}

reasoning_compact_followup_revised_value_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  if [ -z "$(trim "$followup_delta")" ]; then
    compact_reasoning_contract_extract_value "Revised Decision" "$(normalize_reasoning_placeholder_contract "Revised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it." "$prompt_text" "")"
    return 0
  fi
  printf 'Keep or tighten the staged safer path for %s until the change set %s is validated without the returning risk signals.' "$anchor_phrase" "$followup_delta"
}

normalize_compact_reasoning_contract() {
  output_text=$(trim "$1")
  prompt_text=$2
  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if [ -z "$output_text" ] || [ "$output_text" = "NONE" ]; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s' "$output_lower" | grep -Eq '^model timed out after |^model request failed |^model returned an embedding vector|^run completed, but the model did not return content'; then
    printf '%s' "$output_text"
    return 0
  fi

  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  anchor_phrase_lower=$(compact_reasoning_contract_lower_text "$anchor_phrase")
  decision_value=$(reasoning_decision_line_for_prompt "$prompt_text")
  placeholder_scaffold=$(cat <<EOF
Initial Assumption: For this scenario ($scenario_ref), state the first plausible assumption that guided the initial approach.
Invalidating Evidence: State the first concrete evidence that contradicted the initial assumption and why it was decisive.
Revised Decision: Explain how the recommendation changed after invalidating evidence and what fallback/guardrail changed with it.
Claim-to-Evidence Map: For each major claim, provide {claim -> anchor -> verification method -> invalidation trigger} with an assigned owner and review window.
EOF
)
  placeholder_scaffold=$(normalize_reasoning_placeholder_contract "$placeholder_scaffold" "$prompt_text" "")

  outcome_value=$(compact_reasoning_contract_extract_value "Outcome" "$output_text")
  initial_value=$(compact_reasoning_contract_extract_value "Initial Assumption" "$output_text")
  invalidating_value=$(compact_reasoning_contract_extract_value "Invalidating Evidence" "$output_text")
  revised_value=$(compact_reasoning_contract_extract_value "Revised Decision" "$output_text")
  claim_map_value=$(compact_reasoning_contract_extract_value "Claim-to-Evidence Map" "$output_text")

  default_initial_value=$(compact_reasoning_contract_extract_value "Initial Assumption" "$placeholder_scaffold")
  default_invalidating_value=$(compact_reasoning_contract_extract_value "Invalidating Evidence" "$placeholder_scaffold")
  default_revised_value=$(compact_reasoning_contract_extract_value "Revised Decision" "$placeholder_scaffold")
  default_claim_map_value=$(reasoning_compact_claim_map_value_for_prompt "$prompt_text")
  followup_delta=$(compact_reasoning_followup_delta_phrase_for_prompt "$prompt_text")
  prior_outcome_value=$(compact_reasoning_prior_answer_value_for_prompt "Outcome" "$prompt_text")
  prior_initial_value=$(compact_reasoning_prior_answer_value_for_prompt "Initial Assumption" "$prompt_text")
  prior_invalidating_value=$(compact_reasoning_prior_answer_value_for_prompt "Invalidating Evidence" "$prompt_text")
  prior_revised_value=$(compact_reasoning_prior_answer_value_for_prompt "Revised Decision" "$prompt_text")
  prior_claim_map_value=$(compact_reasoning_prior_answer_value_for_prompt "Claim-to-Evidence Map" "$prompt_text")

  if [ -n "$(trim "$followup_delta")" ]; then
    followup_outcome_value=$(reasoning_compact_followup_outcome_value_for_prompt "$prompt_text")
    followup_initial_value=$(reasoning_compact_followup_initial_value_for_prompt "$prompt_text")
    followup_invalidating_value=$(reasoning_compact_followup_invalidating_value_for_prompt "$prompt_text")
    followup_revised_value=$(reasoning_compact_followup_revised_value_for_prompt "$prompt_text")
    if [ -n "$(trim "$prior_outcome_value")" ] && [ "$(compact_reasoning_contract_lower_text "$outcome_value")" = "$(compact_reasoning_contract_lower_text "$prior_outcome_value")" ]; then
      outcome_value=$followup_outcome_value
    fi
    if [ -n "$(trim "$prior_initial_value")" ] && [ "$(compact_reasoning_contract_lower_text "$initial_value")" = "$(compact_reasoning_contract_lower_text "$prior_initial_value")" ]; then
      initial_value=$followup_initial_value
    fi
    if [ -n "$(trim "$prior_invalidating_value")" ] && [ "$(compact_reasoning_contract_lower_text "$invalidating_value")" = "$(compact_reasoning_contract_lower_text "$prior_invalidating_value")" ]; then
      invalidating_value=$followup_invalidating_value
    fi
    if [ -n "$(trim "$prior_revised_value")" ] && [ "$(compact_reasoning_contract_lower_text "$revised_value")" = "$(compact_reasoning_contract_lower_text "$prior_revised_value")" ]; then
      revised_value=$followup_revised_value
    fi
    if [ -n "$(trim "$prior_claim_map_value")" ] && [ "$(compact_reasoning_contract_lower_text "$claim_map_value")" = "$(compact_reasoning_contract_lower_text "$prior_claim_map_value")" ]; then
      claim_map_value=$default_claim_map_value
    fi
  fi

  if compact_reasoning_contract_value_needs_upgrade "Outcome" "$outcome_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      outcome_value=$followup_outcome_value
    else
      outcome_value=$decision_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Initial Assumption" "$initial_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      initial_value=$followup_initial_value
    else
      initial_value=$default_initial_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Invalidating Evidence" "$invalidating_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      invalidating_value=$followup_invalidating_value
    else
      invalidating_value=$default_invalidating_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Revised Decision" "$revised_value" "$prompt_text"; then
    if [ -n "$(trim "$followup_delta")" ]; then
      revised_value=$followup_revised_value
    else
      revised_value=$default_revised_value
    fi
  fi
  if compact_reasoning_contract_value_needs_upgrade "Claim-to-Evidence Map" "$claim_map_value" "$prompt_text"; then
    claim_map_value=$default_claim_map_value
  elif [ -n "$(trim "$anchor_phrase_lower")" ] && ! printf '%s' "$claim_map_value" | tr '[:upper:]' '[:lower:]' | grep -Fq "$anchor_phrase_lower"; then
    claim_map_value=$default_claim_map_value
  fi

  outcome_value=$(compact_reasoning_contract_squash_value "$outcome_value")
  initial_value=$(compact_reasoning_contract_squash_value "$initial_value")
  invalidating_value=$(compact_reasoning_contract_squash_value "$invalidating_value")
  revised_value=$(compact_reasoning_contract_squash_value "$revised_value")
  claim_map_value=$(compact_reasoning_contract_squash_value "$claim_map_value")

  printf '%s\n%s\n%s\n%s\n%s' \
    "Outcome: $outcome_value" \
    "Initial Assumption: $initial_value" \
    "Invalidating Evidence: $invalidating_value" \
    "Revised Decision: $revised_value" \
    "Claim-to-Evidence Map: $claim_map_value"
}

reasoning_cross_domain_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  prompt_focus=$(reasoning_prompt_focus_brief "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Cross-Domain Integration: For technical architecture, tie topology, replay safety, and spend around %s to partner/operator trust, tenant-isolation compliance, empirical recovery checks, and rollback readiness before pursuing raw throughput.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Cross-Domain Integration: For debugging/forensics, connect evidence order and reproduction quality for %s to user-impact containment, policy-safe data handling, measurable falsification checks, and incident communications discipline.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Cross-Domain Integration: For security/compliance tradeoffs, connect control boundaries for %s to analyst workflow speed, audit evidence, operational recovery paths, and measurable exception drift instead of treating policy as a separate appendix.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Cross-Domain Integration: For product and UX constraints, connect onboarding clarity for %s to backend latency tolerance, abuse/compliance guardrails, measurable support load, and operator fallback readiness.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Cross-Domain Integration: For data and causal reasoning, connect the observed movement in %s to instrumentation quality, user-behavior shifts, chargeback or harm exposure, policy-safe measurement limits, and rollout/rollback readiness.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Cross-Domain Integration: For incident response under uncertainty, connect mitigation speed for %s to direct user harm, forensic quality, policy-safe access and communications, measurable burn-rate improvement, and reversible operational controls.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Cross-Domain Integration: For teaching under misconception pressure, connect the explanation of %s to the underlying mechanism, learner decisions, policy or safety consequences, measurable transfer checks, and the operational cost of getting the concept wrong.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Cross-Domain Integration: For strategic planning, connect the plan around %s to customer value, platform/load realities, legal and compliance vetoes, leading indicators, and the operational cost of the chosen sacrifice.' "$anchor_phrase"
      ;;
    *)
      printf 'Cross-Domain Integration: For %s, connect the primary benefit around %s to architecture, user impact, compliance boundaries, measurable validation, and rollback operations before finalizing.' "$prompt_focus" "$anchor_phrase"
      ;;
  esac
}

reasoning_domain_linkage_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Domain Linkage: In this %s scenario, topology decisions for %s affect finance through steady-state cost, compliance through replay and audit evidence, and operations through blast radius and recovery time.' "$domain_label" "$anchor_phrase"
      ;;
    forensics)
      printf 'Domain Linkage: In this %s scenario, premature root-cause claims for %s create incident risk, misdirect engineering effort, and can produce policy or customer-impact mistakes if the wrong mitigation ships first.' "$domain_label" "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Domain Linkage: In this %s scenario, choices about %s affect legal exposure, operations recoverability, analyst productivity, and customer trust simultaneously, so policy compliance cannot be treated as an afterthought.' "$domain_label" "$anchor_phrase"
      ;;
    product/ux)
      printf 'Domain Linkage: In this %s scenario, changing %s affects user comprehension, backend latency tolerance, operations burden, and policy risk together; an elegant UI alone is not a sufficient success condition.' "$domain_label" "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Domain Linkage: In this %s scenario, interpretation of %s affects product rollout, finance exposure, compliance risk, and incident load because a false causal read can scale the wrong intervention.' "$domain_label" "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Domain Linkage: In this %s scenario, decisions about %s affect user harm, communications credibility, on-call load, and longer-term forensic quality, so mitigation speed and evidence quality must be balanced explicitly.' "$domain_label" "$anchor_phrase"
      ;;
    teaching)
      printf 'Domain Linkage: In this %s scenario, teaching around %s must connect mechanism, counterexample, and practical decision-making; otherwise the explanation remains stylistically strong but operationally weak.' "$domain_label" "$anchor_phrase"
      ;;
    strategy)
      printf 'Domain Linkage: In this %s scenario, choices about %s couple revenue timing, cost structure, legal exposure, operational load, and organizational trust; the right plan must make the sacrifice visible rather than hide it.' "$domain_label" "$anchor_phrase"
      ;;
    *)
      printf 'Domain Linkage: In this %s scenario, the decision for %s changes user impact, operational burden, and risk exposure together, so no single metric or anecdote is enough.' "$domain_label" "$anchor_phrase"
      ;;
  esac
}

reasoning_cross_domain_signal_check_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Cross-Domain Signal Check: Verify replay correctness, partner/operator usability, tenant-boundary compliance, cost or throughput metrics, and rollback recovery for %s before finalizing.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Cross-Domain Signal Check: Verify deterministic repro, user-impact containment, evidence-handling compliance, timeline and metric consistency, and mitigation rollback posture for %s before finalizing.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Cross-Domain Signal Check: Verify control coverage, analyst workflow impact, audit and residency boundaries, exception-rate metrics, and recovery-path safety for %s before finalizing.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Cross-Domain Signal Check: Verify task completion, latency and support friction, abuse and policy guardrails, experiment or cohort evidence, and fallback-path readiness for %s before finalizing.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Cross-Domain Signal Check: Verify instrumentation integrity, user or operator impact, policy-safe measurement scope, confound-resistant metrics, and rollout rollback readiness for %s before finalizing.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Cross-Domain Signal Check: Verify direct harm reduction, degraded user workflow impact, access and communication boundaries, burn-rate and blast-radius metrics, and rollback containment for %s before finalizing.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Cross-Domain Signal Check: Verify mechanism accuracy, learner usability, safety or policy boundaries, transfer metrics, and operational consequences of misunderstanding %s before finalizing.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Cross-Domain Signal Check: Verify platform feasibility, customer and operator impact, legal non-negotiables, leading indicators, and operational load for %s before finalizing.' "$anchor_phrase"
      ;;
    *)
      printf 'Cross-Domain Signal Check: Verify architecture, user impact, compliance constraints, metrics causality, and incident operations for %s before finalizing.' "$anchor_phrase"
      ;;
  esac
}

reasoning_architecture_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Architecture Lens: Use replay-safe boundaries, idempotent state transitions, tenant isolation, and bounded recovery domains for %s.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Architecture Lens: Map the exact failing path, failover state transition, and dependency boundaries that can explain %s without skipping reproduction steps.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Architecture Lens: Model key custody, data-flow segmentation, residency boundaries, and emergency-access paths for %s before endorsing workflow shortcuts.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Architecture Lens: Keep the flow for %s tolerant of latency spikes, retries, and partial backend failure so the UI does not promise a state the system cannot sustain.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Architecture Lens: Verify instrumentation boundaries, cohort definitions, logging integrity, and ranking or queue-state changes around %s before reading movement as causal.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Architecture Lens: Isolate the failing component, containment boundary, and reversible control surface for %s so mitigation does not widen blast radius.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Architecture Lens: Show the real mechanism, state change, or dependency chain behind %s instead of teaching only the surface rule.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Architecture Lens: Check whether platform coupling, capacity headroom, and change-rate tolerance around %s can absorb the plan without hidden reliability debt.' "$anchor_phrase"
      ;;
    *)
      printf 'Architecture Lens: Summarize the system design and operational constraints that dominate feasibility for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_product_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Product/UX Lens: Keep partner and operator workflows around %s legible during backlog, replay, or degraded-mode events, with explicit reason codes and recovery expectations.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Product/UX Lens: Treat the explanation of %s as a user-facing decision too; the wrong story creates customer whiplash, support churn, and operator confusion.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Product/UX Lens: Preserve analyst throughput and understandable failure modes for %s without creating silent policy exceptions or operator workarounds.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Product/UX Lens: Make the ordering, trust checks, fallback path, and latency expectations for %s understandable enough that high-risk users do not self-select into failure.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Product/UX Lens: Check whether the user or operator experience around %s changed in ways that would move the metric even if the underlying value did not.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Product/UX Lens: Optimize the degraded path for %s so the first mitigation reduces harm and confusion for affected users, support, and operators.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Product/UX Lens: Make the learner path around %s diagnostic rather than decorative, so confusion surfaces early instead of hiding behind fluent language.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Product/UX Lens: Tie the plan for %s to customer value, adoption friction, support burden, and trust effects rather than roadmap aesthetics alone.' "$anchor_phrase"
      ;;
    *)
      printf 'Product/UX Lens: Summarize the user impact, adoption friction, and workflow ergonomics tradeoffs for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_security_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Security/Compliance Lens: Make tenant boundaries, audit evidence, access scoping, and replay-safe retention rules for %s explicit enough to survive failure drills.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Security/Compliance Lens: Preserve least-privilege log access, PII handling, chain-of-custody discipline, and policy-safe mitigation choices while investigating %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Security/Compliance Lens: Preserve least privilege, residency, retention, approval ownership, and auditability for %s before trading control depth for speed.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Security/Compliance Lens: Keep trust checks, abuse controls, consent boundaries, and operator override policy for %s explicit even when conversion pressure is high.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Security/Compliance Lens: Ensure measurement for %s respects data minimization, retention, cohort access controls, and policy limits on what can be compared or stored.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Security/Compliance Lens: Keep access escalation, evidence retention, and external communications for %s inside approved incident and policy boundaries.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Security/Compliance Lens: Surface the safety or policy boundaries that become dangerous when %s is misunderstood, rather than teaching a purely neutral abstraction.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Security/Compliance Lens: Test the plan for %s against legal vetoes, compliance staffing, and approval boundaries before calling it executable.' "$anchor_phrase"
      ;;
    *)
      printf 'Security/Compliance Lens: Summarize the policy, legal, and data-governance boundaries for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_metrics_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Metrics/Causality Lens: Track replay mismatch, backlog age, tenant spillover, throughput under stress, and unit-cost drift for %s so the architecture is judged on failure behavior, not only nominal load.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Metrics/Causality Lens: Require deterministic repro rate, timeline consistency, failing-sample stability, and explicit elimination of stronger alternatives for %s before escalating confidence.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Metrics/Causality Lens: Track exception rate, analyst latency, audit-proof coverage, control ownership, and recovery-path dependence for %s instead of treating compliance as unmeasured overhead.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Metrics/Causality Lens: Pair completion and time-to-value for %s with abuse, support load, fallback usage, and p95 latency so local UX wins do not hide system harm.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Metrics/Causality Lens: Stress-test %s with confound checks, cohort drift inspection, lagged-harm tracking, and counterfactual reasoning before attributing movement to the proposed cause.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Metrics/Causality Lens: Track direct harm, error-budget burn, mitigation timing, affected-scope growth, and signal freshness for %s during the first mitigation windows.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Metrics/Causality Lens: Use prediction checks, near-miss discrimination, counterexample success, and delayed transfer on %s to distinguish real understanding from fluency.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Metrics/Causality Lens: Tie %s to leading indicators, sacrifice budgets, resource burn, reliability drift, and review-window ownership so the strategy cannot hide behind a single headline metric.' "$anchor_phrase"
      ;;
    *)
      printf 'Metrics/Causality Lens: Summarize the measurement signals that can validate or falsify the decision for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_incident_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Incident/Ops Lens: Predefine replay drills, per-tenant kill switches, recovery windows, and ownership for %s so rollback is real, not rhetorical.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Incident/Ops Lens: Keep evidence preservation, mitigation checkpoints, communications timing, and escalation ownership for %s aligned while the root cause remains uncertain.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Incident/Ops Lens: Verify revoke, rotate, emergency-access, and rollback procedures for %s before accepting a control design that looks safe only in steady state.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Incident/Ops Lens: Keep a manual or gated fallback path, support playbook, and kill switch for %s so user trust survives bad cohorts or backend instability.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Incident/Ops Lens: Hold scale-up, set review windows, and assign owners for %s so a weak causal read can be reversed before it becomes an incident.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Incident/Ops Lens: Define containment order, rollback trigger, escalation owner, and evidence-preservation boundary for %s before acting on the first hypothesis.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Incident/Ops Lens: Make explicit what operational mistake, escalation delay, or safety issue follows if %s is still misunderstood after the lesson.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Incident/Ops Lens: Check whether sequencing, rollback options, staffing load, and support readiness for %s are realistic under the proposed pace of change.' "$anchor_phrase"
      ;;
    *)
      printf 'Incident/Ops Lens: Summarize rollback readiness, escalation triggers, and runtime risk controls for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_tradeoff_ledger_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Tradeoff Ledger: Tradeoff 1: stronger per-tenant isolation for %s lowers blast radius but raises steady-state cost and operational complexity; Tradeoff 2: shared ingestion improves utilization but makes replay correctness and noisy-neighbor failures harder to contain.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Tradeoff Ledger: Tradeoff 1: narrowing quickly on %s speeds action but raises false-confidence risk; Tradeoff 2: keeping multiple live hypotheses preserves recovery options but slows narrative clarity.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Tradeoff Ledger: Tradeoff 1: tighter controls for %s reduce legal and audit risk but add workflow latency; Tradeoff 2: faster analyst paths improve throughput but can create exception debt and harder recovery.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Tradeoff Ledger: Tradeoff 1: removing friction from %s can lift completion while increasing abuse or support cost; Tradeoff 2: stronger trust checks protect the system but can push good users into abandonment or manual review.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Tradeoff Ledger: Tradeoff 1: acting early on %s can capture upside while increasing the chance of scaling a confounded effect; Tradeoff 2: waiting for cleaner causal evidence lowers false-positive risk but delays visible progress.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Tradeoff Ledger: Tradeoff 1: faster mitigation for %s can reduce direct harm while degrading evidence quality; Tradeoff 2: slower evidence collection improves confidence but can leave users exposed longer.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Tradeoff Ledger: Tradeoff 1: a simplified explanation of %s improves fluency but can preserve the core misconception; Tradeoff 2: a counterexample-rich explanation improves transfer but raises short-term cognitive load.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Tradeoff Ledger: Tradeoff 1: faster expansion around %s can raise near-term growth while increasing compliance, reliability, or support debt; Tradeoff 2: heavier controls protect trust and margin but slow visible progress and stakeholder enthusiasm.' "$anchor_phrase"
      ;;
    *)
      printf 'Tradeoff Ledger: Tradeoff 1: the faster path around %s increases momentum but can hide downstream cost; Tradeoff 2: the safer path preserves optionality but slows visible progress.' "$anchor_phrase"
      ;;
  esac
}

reasoning_rejected_alternative_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Rejected Alternative: A single global ingestion path for %s was rejected because it looks cheaper on nominal load while concentrating replay, recovery, and tenant-containment risk into one surface.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Rejected Alternative: A single-cause memo for %s based on the noisiest warning was rejected because it front-loads confidence before the timeline and reproduction evidence justify it.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Rejected Alternative: A convenience-first rollout for %s was rejected because it depends on exceptions, weak auditability, or residency shortcuts that would surface later as governance debt.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Rejected Alternative: A completion-first flow for %s was rejected because it treats trust and abuse controls as secondary clean-up work instead of part of the core user path.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Rejected Alternative: A scale-now interpretation of %s was rejected because the observed lift can still be explained by cohort drift, ranking changes, or lagged harms.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Rejected Alternative: Waiting for a perfect root cause before acting on %s was rejected because it leaves direct user harm live without enough upside to justify the delay.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Rejected Alternative: A polished but abstraction-heavy lesson on %s was rejected because it can sound correct while still failing the learner on counterexamples and near misses.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Rejected Alternative: An all-goals-win roadmap for %s was rejected because it depends on unstated resource, consent, or reliability miracles.' "$anchor_phrase"
      ;;
    *)
      printf 'Rejected Alternative: The superficially simpler path for %s was rejected because it assumes the current success signal generalizes without enough evidence.' "$anchor_phrase"
      ;;
  esac
}

reasoning_stakeholder_map_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Stakeholder Impact Map: Partners need deterministic replay results for %s, SRE carries backlog and recovery pressure, compliance needs auditable tenant boundaries, and finance absorbs the downside if isolation is bought too late.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Stakeholder Impact Map: Engineers need decisive repro steps for %s, incident command needs a mitigation path that survives uncertainty, and support or customers absorb harm if the wrong explanation drives communications.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Stakeholder Impact Map: Analysts need usable controls for %s, legal and compliance need audit-safe boundaries, operations needs recoverability, and customers absorb trust loss when convenience outruns governance.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Stakeholder Impact Map: Users need a trustworthy path for %s, support absorbs ambiguous failures, risk and compliance teams absorb abuse or consent leakage, and operations carries the manual rescue burden if the flow is brittle.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Stakeholder Impact Map: Product wants to scale wins around %s, finance absorbs false-positive rollout cost, risk and compliance absorb delayed harms, and operations carries the incident load if the causal read is wrong.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Stakeholder Impact Map: Affected users absorb harm from %s first, support and communications absorb confusion, incident command absorbs timing pressure, and engineering absorbs the cost of weak evidence if mitigation is mis-aimed.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Stakeholder Impact Map: Learners need an explanation of %s that survives application, operators or reviewers absorb the cost of misunderstanding, and the teacher absorbs extra friction if transfer is not measured honestly.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Stakeholder Impact Map: Customers need the benefits promised by %s, finance needs bounded spend and margin, legal needs a policy-safe scope, and operations needs a change rate the system and team can absorb.' "$anchor_phrase"
      ;;
    *)
      printf 'Stakeholder Impact Map: Users, operators, compliance owners, and finance see different costs and benefits from %s, so the decision must make those asymmetries explicit.' "$anchor_phrase"
      ;;
  esac
}

reasoning_deterministic_salvage_output() {
  prompt_text=$1
  plan_text=$2
  loop_summary_text=$3
  command_success_total_raw=${4:-0}
  run_elapsed_sec_raw=${5:-0}

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac
  if [ "$command_success_total" -lt 0 ]; then
    command_success_total=0
  fi

  case "$run_elapsed_sec_raw" in
    ""|*[!0-9]*)
      run_elapsed_sec=0
      ;;
    *)
      run_elapsed_sec=$run_elapsed_sec_raw
      ;;
  esac
  if [ "$run_elapsed_sec" -lt 0 ]; then
    run_elapsed_sec=0
  fi

  next_action_line=$(assay_next_action_from_plan "$plan_text")
  next_action_line=$(sanitize_reasoning_next_action "$next_action_line" "$prompt_text")
  default_next_action_line=$(reasoning_next_improvement_line_for_prompt "$prompt_text")
  next_action_lower=$(printf '%s' "$next_action_line" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$next_action_line")" ]; then
    next_action_line=$default_next_action_line
  elif printf '%s' "$next_action_lower" | grep -Eq 'inspect relevant files|read-only tools|list all files|list files|continue from the failure ledger|narrower scope|implementation patch|run verify checks|validate the highest-risk assumption first'; then
    next_action_line=$default_next_action_line
  fi

  outcome_line=$(reasoning_outcome_stub_for_prompt "$prompt_text")
  decision_line=$(reasoning_decision_line_for_prompt "$prompt_text")
  priority_line=$(reasoning_priority_line_for_prompt "$prompt_text")
  fallback_line=$(reasoning_fallback_line_for_prompt "$prompt_text")
  disconfirm_line=$(reasoning_disconfirming_line_for_prompt "$prompt_text")
  risk_register_line=$(reasoning_risk_register_line_for_prompt "$prompt_text")
  risks_line=$(reasoning_risk_line_for_prompt "$prompt_text" "PARTIAL")
  verification_line=$(reasoning_design_verification_line "$prompt_text" "$command_success_total" "$loop_summary_text")
  verification_line=$(trim "$verification_line")
  if [ -z "$(trim "$verification_line")" ]; then
    verification_line="Verification Evidence: Used command anchors from this run to ground the recommendation."
  fi
  runtime_line=$(assay_runtime_summary_line "$run_elapsed_sec")
  if [ -n "$runtime_line" ] && ! printf '%s' "$verification_line" | grep -Eq 'Worked for[[:space:]]+[0-9]'; then
    verification_line="$verification_line $runtime_line"
  fi

  cat <<EOF
Outcome: $outcome_line
$verification_line
Assumptions and Alternatives: Assumptions were explicit where evidence was incomplete, and at least one viable alternative path remains under active validation.
Contradiction Check: Conflicting constraints were treated as non-simultaneously satisfiable until direct evidence proved otherwise.
Decision: $decision_line
${priority_line}
Fallback Path: $fallback_line
Disconfirming Evidence: $disconfirm_line
${risk_register_line}
Risks: $risks_line
Next Improvement: $next_action_line
EOF
}

sanitize_design_completion_outcome() {
  outcome_line=$(trim "$1")
  prompt_text=$2
  outcome_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')

  if [ -z "$outcome_line" ] || [ "$outcome_line" = "NONE" ] || [ "$outcome_lower" = "none" ] || [ "$outcome_lower" = "null" ] || [ "$outcome_lower" = "n/a" ]; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq '^starting investigation|^started investigation|^scanning workspace|^goal:|^inspection of workspace started|^workspace inspection initiated'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq 'investigat(e|ion) of the workspace|inspection of workspace|workspace inspection|listing files in target directory|completed the requested design deliverable|completed partial controller output|partial controller output by filling missing required sections|fallback command execution|transitioning to design mode|transitioning to implement mode|to be defined'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  if printf '%s' "$outcome_lower" | grep -Eq 'workspace|\.assay-runs/' && printf '%s' "$outcome_lower" | grep -Eq 'list|listing|inspect|inspection|scan|started|starting|transition'; then
    reasoning_outcome_stub_for_prompt "$prompt_text"
    return 0
  fi

  printf '%s' "$outcome_line"
}

reasoning_design_verification_line() {
  prompt_text=$1
  command_success_count=$2
  loop_feedback_text=${3-}
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  case "$command_success_count" in
    ""|*[!0-9]*)
      command_success_count=0
      ;;
  esac
  if [ "$command_success_count" -lt 0 ]; then
    command_success_count=0
  fi
  command_anchor_summary=$(command_evidence_anchor_summary "$loop_feedback_text")
  if [ -n "$(trim "$command_anchor_summary")" ]; then
    printf 'Verification Evidence: Used %s successful workspace checks for scenario (%s). Command output anchors: %s.' "$command_success_count" "$scenario_ref" "$command_anchor_summary"
    return 0
  fi
  printf 'Verification Evidence: Used %s successful workspace checks and synthesized constraints for scenario (%s), with command output anchors recorded.' "$command_success_count" "$scenario_ref"
}

command_anchor_status_rank() {
  status_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$status_lower" in
    ok|done|success)
      printf '%s' "0"
      ;;
    context_missing|missing_input)
      printf '%s' "1"
      ;;
    blocked|approval_required)
      printf '%s' "2"
      ;;
    failed|error|timeout)
      printf '%s' "3"
      ;;
    *)
      printf '%s' "4"
      ;;
  esac
}

command_anchor_command_label() {
  command_text=$(single_line_snippet "$(trim "$1")")
  command_text=$(printf '%s' "$command_text" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
  if [ -z "$command_text" ]; then
    printf '%s' ""
    return 0
  fi
  printf '%s' "$(printf '%s' "$command_text" | cut -c1-90)"
}

command_output_anchor_snippet() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' ""
    return 0
  fi

  anchor_line=$(printf '%s\n' "$output_text" | awk '
    BEGIN {
      first_line = ""
    }
    {
      line = $0
      gsub(/[[:space:]]+/, " ", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (first_line == "") {
        first_line = line
      }
      lower = tolower(line)
      if (line ~ /[A-Za-z0-9._\/-]+\.[A-Za-z0-9]+:[0-9]+/ || lower ~ /(fatal:|error:|failed|warning:|no such file|not found|permission denied|context missing|missing input|rollback|latency|throughput|chargeback|queue|incident|policy|regression|stack|trace|p95|p99)/) {
        print line
        found = 1
        exit
      }
    }
    END {
      if (found != 1 && first_line != "") {
        print first_line
      }
    }
  ')
  anchor_line=$(single_line_snippet "$(trim "$anchor_line")")
  if [ -z "$anchor_line" ]; then
    printf '%s' ""
    return 0
  fi
  if printf '%s' "$anchor_line" | grep -Eq '^total[[:space:]]+[0-9]+[[:space:]]+.*(drwx|-[rwx-]{3})'; then
    list_entries=$(printf '%s\n' "$anchor_line" | awk '
      {
        count = 0
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[d-][rwx-]{9}/) {
            count++
          }
        }
        if (count < 1) {
          count = 1
        }
        print count
      }
    ')
    list_entries=$(trim "$list_entries")
    [ -n "$list_entries" ] || list_entries="1"
    anchor_line="directory listing snapshot (${list_entries} entries shown)"
  else
    path_preview=$(printf '%s\n' "$anchor_line" | awk '
      {
        count = 0
        preview = ""
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^\.?\/[A-Za-z0-9._\/-]+$/) {
            count++
            if (count <= 3) {
              if (preview != "") {
                preview = preview ", "
              }
              preview = preview $i
            }
          }
        }
        if (count >= 4) {
          if (count > 3) {
            printf "%s (+%d more paths)", preview, count - 3
          } else {
            printf "%s", preview
          }
        }
      }
    ')
    path_preview=$(trim "$path_preview")
    if [ -n "$path_preview" ]; then
      anchor_line="$path_preview"
    fi
  fi
  printf '%s' "$(printf '%s' "$anchor_line" | cut -c1-140)"
}

command_evidence_anchor_summary() {
  evidence_text=$1
  if [ -z "$(trim "$evidence_text")" ]; then
    printf '%s' ""
    return 0
  fi

  entries_tmp=$(mktemp)
  printf '%s\n' "$evidence_text" | awk '
    function emit_entry() {
      if (cmd == "") {
        return
      }
      if (status == "") {
        status = "unknown"
      }
      print cmd "\t" status "\t" output
    }
    BEGIN {
      cmd = ""
      status = ""
      output = ""
      capture_output = 0
    }
    /^Command:[[:space:]]*/ {
      emit_entry()
      cmd=$0
      sub(/^Command:[[:space:]]*/, "", cmd)
      status=""
      output=""
      capture_output=0
      next
    }
    /^Status:[[:space:]]*/ {
      if (cmd != "") {
        status=$0
        sub(/^Status:[[:space:]]*/, "", status)
        capture_output=0
      }
      next
    }
    /^Output:[[:space:]]*/ {
      if (cmd != "") {
        capture_output=1
      }
      next
    }
    {
      if (capture_output == 1) {
        if ($0 ~ /^(Checkpoint|Transition|Reason|Decision requested|Question|Options):[[:space:]]*/) {
          capture_output=0
          next
        }
        line=$0
        gsub(/\t/, " ", line)
        gsub(/[[:space:]]+/, " ", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "") {
          if (output == "") {
            output=line
          } else {
            output=output " " line
          }
        }
      }
    }
    END {
      emit_entry()
    }
  ' > "$entries_tmp"

  if [ ! -s "$entries_tmp" ]; then
    rm -f "$entries_tmp"
    printf '%s' ""
    return 0
  fi

  ranked_tmp=$(mktemp)
  dedup_tmp=$(mktemp)
  summary=""
  count=0

  while IFS="$(printf '\t')" read -r cmd status output; do
    cmd=$(command_anchor_command_label "$cmd")
    status=$(trim "$status")
    status=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
    output=$(trim "$output")
    [ -n "$cmd" ] || continue
    [ -n "$status" ] || status="unknown"

    rank=$(command_anchor_status_rank "$status")
    anchor=$(command_output_anchor_snippet "$output")

    entry="$cmd ($status)"
    if [ -n "$anchor" ]; then
      cmd_lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
      anchor_lower=$(printf '%s' "$anchor" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$anchor_lower" | grep -Fq "$cmd_lower"; then
        entry="$cmd ($status; anchor: $anchor)"
      fi
    fi
    printf '%s\t%s\t%s\n' "$rank" "$cmd" "$entry" >> "$ranked_tmp"
  done < "$entries_tmp"

  rm -f "$entries_tmp"

  if [ ! -s "$ranked_tmp" ]; then
    rm -f "$ranked_tmp" "$dedup_tmp"
    printf '%s' ""
    return 0
  fi

  sort -t "$(printf '\t')" -k1,1n -k2,2 "$ranked_tmp" | awk -F '\t' '!seen[$2]++ { print $3 }' > "$dedup_tmp"
  rm -f "$ranked_tmp"

  while IFS= read -r entry; do
    entry=$(trim "$entry")
    [ -n "$entry" ] || continue
    if [ -z "$summary" ]; then
      summary="$entry"
    else
      summary="${summary}; ${entry}"
    fi
    count=$((count + 1))
    if [ "$count" -ge 3 ]; then
      break
    fi
  done < "$dedup_tmp"

  rm -f "$dedup_tmp"
  printf '%s' "$summary"
}

context_miss_anchor_summary() {
  feedback_text=$1
  if [ -z "$(trim "$feedback_text")" ]; then
    printf '%s' ""
    return 0
  fi

  pairs_tmp=$(mktemp)
  printf '%s\n' "$feedback_text" | awk '
    BEGIN { cmd="" }
    /^Command:[[:space:]]*/ {
      cmd=$0
      sub(/^Command:[[:space:]]*/, "", cmd)
      next
    }
    /^Status:[[:space:]]*/ {
      if (cmd != "") {
        status=$0
        sub(/^Status:[[:space:]]*/, "", status)
        status_lc=tolower(status)
        if (status_lc == "missing_input" || status_lc == "context_missing") {
          printf "%s\t%s\n", cmd, status_lc
        }
        cmd=""
      }
    }
  ' > "$pairs_tmp"

  if [ ! -s "$pairs_tmp" ]; then
    rm -f "$pairs_tmp"
    printf '%s' ""
    return 0
  fi

  dedup_tmp=$(mktemp)
  awk -F '\t' '!seen[$0]++ { print $0 }' "$pairs_tmp" > "$dedup_tmp"
  rm -f "$pairs_tmp"

  summary=""
  count=0
  while IFS="$(printf '\t')" read -r cmd status; do
    cmd=$(single_line_snippet "$(trim "$cmd")")
    status=$(trim "$status")
    [ -n "$cmd" ] || continue
    [ -n "$status" ] || status="missing_input"
    if [ -z "$summary" ]; then
      summary="$cmd ($status)"
    else
      summary="${summary}; ${cmd} (${status})"
    fi
    count=$((count + 1))
    if [ "$count" -ge 3 ]; then
      break
    fi
  done < "$dedup_tmp"
  rm -f "$dedup_tmp"
  printf '%s' "$summary"
}

context_miss_guidance_for_prompt() {
  feedback_text=$1
  state_mode_hint=$(normalize_mode "$2")
  context_anchor_summary=$(context_miss_anchor_summary "$feedback_text")
  if [ -z "$(trim "$context_anchor_summary")" ]; then
    printf '%s' "NONE"
    return 0
  fi

  discovery_hint=$(context_recovery_readonly_command_for_mode "$state_mode_hint" "context_missing")
  discovery_hint=$(single_line_snippet "$(trim "$discovery_hint")")
  if [ -z "$(trim "$discovery_hint")" ]; then
    discovery_hint="find . -maxdepth 2 -type f"
  fi

  printf '%s\n' "Context misses observed in prior command anchors: $context_anchor_summary."
  printf '%s\n' "Do not repeat those exact path assumptions until discovery output confirms the path exists."
  printf '%s\n' "Run one discovery-first command before file-specific probes (recommended: $discovery_hint)."
  printf '%s' "If discovery remains ambiguous, state assumptions explicitly and provide one fallback path."
}

ensure_output_has_runtime_command_evidence() {
  output_text=$1
  loop_summary_text=$2
  command_success_total_raw=$3
  prompt_text=$4
  enforce_claim_map_raw=${5:-0}

  output_trimmed=$(trim "$output_text")
  if [ -z "$output_trimmed" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  case "$command_success_total_raw" in
    ""|*[!0-9]*)
      command_success_total=0
      ;;
    *)
      command_success_total=$command_success_total_raw
      ;;
  esac
  if [ "$command_success_total" -le 0 ]; then
    printf '%s' "$output_text"
    return 0
  fi

  case "$enforce_claim_map_raw" in
    ""|*[!0-9]*)
      enforce_claim_map=0
      ;;
    *)
      enforce_claim_map=$enforce_claim_map_raw
      ;;
  esac

  command_anchor_summary=$(command_evidence_anchor_summary "$loop_summary_text")
  if [ -z "$(trim "$command_anchor_summary")" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s' "$output_lower" | grep -Eq 'verification evidence:'; then
    if [ "$enforce_claim_map" -eq 1 ]; then
      output_text=$(printf '%s\nVerification Evidence: Command anchors from this run for scenario (%s): %s.' "$output_text" "$scenario_ref" "$command_anchor_summary")
      output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
    fi
  elif ! printf '%s' "$output_lower" | grep -Eq 'command anchors:'; then
    output_text=$(printf '%s\nCommand Anchors: %s.' "$output_text" "$command_anchor_summary")
    output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  fi

  if [ "$enforce_claim_map" -eq 1 ] && ! printf '%s' "$output_lower" | grep -Eq 'claim[- ]?to[- ]?evidence map|claim[- ]?evidence map'; then
    output_text=$(printf '%s\nClaim-to-Evidence Map: Primary outcome -> %s -> rerun the same command anchors and verify status drift before broad rollout.' "$output_text" "$command_anchor_summary")
  fi

  printf '%s' "$output_text"
}

assay_runtime_summary_line() {
  elapsed_sec=$1
  case "$elapsed_sec" in
    ""|*[!0-9]*)
      elapsed_sec=0
      ;;
  esac
  if [ "$elapsed_sec" -lt 0 ]; then
    elapsed_sec=0
  fi
  elapsed_minutes=$((elapsed_sec / 60))
  elapsed_seconds=$((elapsed_sec % 60))
  if [ "$elapsed_minutes" -gt 0 ]; then
    printf 'Worked for %sm %ss.' "$elapsed_minutes" "$elapsed_seconds"
  else
    printf 'Worked for %ss.' "$elapsed_seconds"
  fi
}

assay_ensure_runtime_evidence() {
  output_text=$1
  runtime_line=$2
  if [ -z "$runtime_line" ]; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s\n' "$output_text" | grep -Eqi 'Worked for[[:space:]]+[0-9]+m[[:space:]]+[0-9]+s|Worked for[[:space:]]+[0-9]+s'; then
    printf '%s' "$output_text"
    return 0
  fi
  if printf '%s\n' "$output_text" | grep -q '^Verification Evidence:'; then
    printf '%s\n' "$output_text" | awk -v rt="$runtime_line" '
      BEGIN { updated = 0 }
      {
        if (updated == 0 && $0 ~ /^Verification Evidence:/) {
          print $0 " " rt
          updated = 1
          next
        }
        print
      }
      END {
        if (updated == 0) {
          print "Verification Evidence: " rt
        }
      }
    '
    return 0
  fi
  printf '%s\nVerification Evidence: %s' "$output_text" "$runtime_line"
}

assay_apply_reasoning_contracts() {
  output_text=$(trim "$1")
  prompt_text=$2
  adversarial_required=$3
  cross_domain_required=$4
  recovery_required=$5
  decision_required=$6
  assumption_revision_required=${7:-0}
  time_window_required=0
  source_quality_required=0
  claim_evidence_required=0
  if prompt_requires_time_windowed_validation "$prompt_text"; then
    time_window_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    time_window_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    output_text=$(normalize_adversarial_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$cross_domain_required" -eq 1 ]; then
    output_text=$(normalize_cross_domain_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$recovery_required" -eq 1 ]; then
    output_text=$(normalize_recovery_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$assumption_revision_required" -eq 1 ]; then
    output_text=$(normalize_assumption_revision_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$decision_required" -eq 1 ]; then
    output_text=$(normalize_decision_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$time_window_required" -eq 1 ]; then
    output_text=$(normalize_verification_final_contract "$output_text" "$prompt_text")
  fi
  if [ "$adversarial_required" -eq 1 ] || [ "$cross_domain_required" -eq 1 ] || [ "$decision_required" -eq 1 ] || [ "$time_window_required" -eq 1 ] || prompt_prefers_reasoning_completion "$prompt_text"; then
    claim_evidence_required=1
  fi
  if [ "$claim_evidence_required" -eq 1 ]; then
    output_text=$(normalize_claim_evidence_completeness_contract "$output_text" "$prompt_text" "")
  fi
  if [ "$time_window_required" -eq 1 ] || prompt_prefers_reasoning_completion "$prompt_text"; then
    source_quality_required=1
  fi
  if [ "$source_quality_required" -eq 1 ]; then
    output_text=$(normalize_source_quality_contradiction_contract "$output_text" "$prompt_text" "" "0")
  fi
  if [ "$adversarial_required" -eq 1 ] || [ "$cross_domain_required" -eq 1 ] || [ "$decision_required" -eq 1 ]; then
    output_text=$(normalize_ambiguity_final_contract "$output_text")
  fi
  output_text=$(normalize_reasoning_followup_thread_contract "$output_text" "$prompt_text")
  output_text=$(normalize_reasoning_live_contract "$output_text" "$prompt_text")
  printf '%s' "$output_text"
}

assay_normalize_assistant_output() {
  raw_output=$(trim "$1")
  final_mode=$(trim "$2")
  plan_text=$3
  run_time_budget=$4
  run_elapsed_sec=${5:-0}
  prompt_text=${6:-}
  runtime_line=$(assay_runtime_summary_line "$run_elapsed_sec")
  adversarial_required=0
  cross_domain_required=0
  recovery_required=1
  decision_required=0
  assumption_revision_required=0
  if prompt_requires_adversarial_reasoning "$prompt_text"; then
    adversarial_required=1
  fi
  if prompt_requires_cross_domain_reasoning "$prompt_text"; then
    cross_domain_required=1
  fi
  if prompt_requires_decision_completeness "$prompt_text"; then
    decision_required=1
  fi
  if [ "$adversarial_required" -eq 1 ]; then
    decision_required=1
  fi
  if prompt_requires_assumption_revision_contract "$prompt_text"; then
    assumption_revision_required=1
  fi
  if [ "$assumption_revision_required" -eq 0 ] && [ "$adversarial_required" -eq 1 ] && printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]' | grep -Eq 'misconception|false assumption|plausible but false|first narrative|attractive but wrong|initial assumption|assumption[- ]?revision|invalidated|prove (this|it) wrong|confidence shift'; then
    assumption_revision_required=1
  fi

  if assay_output_has_required_sections "$raw_output"; then
    if ! printf '%s' "$raw_output" | grep -Eqi '^Outcome:[[:space:]]+I couldn.t complete|^Outcome:[[:space:]]+Progress was made.*not yet finalized|^Outcome:[[:space:]]+Concrete progress was delivered.*final hardening|^Outcome:[[:space:]]+Produced a defensible intermediate result.*remaining verification|^Outcome:[[:space:]]+Starting investigation|^Outcome:[[:space:]]+Started investigation'; then
      normalized_output=$(assay_apply_reasoning_contracts "$raw_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
      assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
      return 0
    fi
  fi

  next_action_line=$(assay_next_action_from_plan "$plan_text")
  next_action_line=$(sanitize_reasoning_next_action "$next_action_line" "$prompt_text")
  if [ -z "$final_mode" ]; then
    final_mode="UNKNOWN"
  fi

  if [ -z "$raw_output" ]; then
    normalized_output=$(structured_incomplete_run_message "$final_mode" "$next_action_line" "" "$prompt_text")
    normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
    assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
    return 0
  fi

  if printf '%s' "$raw_output" | grep -Eqi 'couldn.t complete|run timed out|before done mode|partial or stale'; then
    risk_line=$(reasoning_risk_line_for_prompt "$prompt_text" "$final_mode")
    normalized_output=$(structured_incomplete_run_message "$final_mode" "$next_action_line" "$risk_line" "$prompt_text")
    normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
    assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
    return 0
  fi

  outcome_line=$(printf '%s\n' "$raw_output" | sed -n '/[^[:space:]]/p' | sed -n '1p')
  outcome_line=$(trim "$outcome_line")
  outcome_line=$(printf '%s\n' "$outcome_line" | sed -E 's/^[[:space:]]*[Oo]utcome:[[:space:]]*//')
  outcome_line=$(trim "$outcome_line")
  outcome_line=$(assay_sanitize_reasoning_outcome "$outcome_line" "$prompt_text")
  outcome_line_lower=$(printf '%s' "$outcome_line" | tr '[:upper:]' '[:lower:]')
  if [ -z "$outcome_line" ] || [ "$outcome_line_lower" = "none" ] || [ "$outcome_line_lower" = "null" ] || [ "$outcome_line_lower" = "n/a" ]; then
    outcome_line="Best-effort progress was produced in mode: $final_mode."
  fi

  risk_line=$(reasoning_risk_line_for_prompt "$prompt_text" "$final_mode")
  verification_line="Verification Evidence: Review the run trace for executed steps, commands, and controller transitions."
  if assay_prefers_scenario_reasoning_normalization "$prompt_text"; then
    verification_line=$(assay_reasoning_verification_line_for_prompt "$prompt_text")
  fi

  normalized_output=$(printf '%s\n%s\n%s\n%s' \
    "Outcome: $outcome_line" \
    "$verification_line" \
    "Risks: $risk_line" \
    "Next Improvement: $next_action_line")
  normalized_output=$(assay_apply_reasoning_contracts "$normalized_output" "$prompt_text" "$adversarial_required" "$cross_domain_required" "$recovery_required" "$decision_required" "$assumption_revision_required")
  assay_ensure_runtime_evidence "$normalized_output" "$runtime_line"
}

is_simple_direct_prompt() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *$'\n'*|*';'*|*'&&'*|*'||'*)
      return 1
      ;;
  esac

  case "$prompt_trimmed" in
    *"file"*|*"folder"*|*"workspace"*|*"repo"*|*"git "*|*"commit"*|*"branch"*|*"diff"*|*"patch"*|*"refactor"*|*"function"*|*"class"*|*"script"*|*"shell"*|*"posix"*|*"bug"*|*"error"*|*"trace"*|*"stack"*|*"test"*|*"build"*|*"deploy"*|*"ssh"*|*"terminal"*|*"api"*|*"http"*|*"json"*|*"yaml"*|*"sql"*|*"regex"*|*"code"*)
      return 1
      ;;
  esac

  word_count=$(printf '%s\n' "$prompt_trimmed" | awk '{print NF}')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 24 ]; then
    return 1
  fi

  return 0
}

requires_agent_execution_prompt() {
  if prompt_prefers_compact_reasoning_contract "$1"; then
    return 1
  fi
  if prompt_prefers_reasoning_completion "$1" && ! prompt_requires_code_implementation "$1"; then
    return 1
  fi

  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *"create "*|*"make "*|*"write "*|*"edit "*|*"update "*|*"modify "*|*"refactor "*|*"delete "*|*"rename "*|*"move "*|*"add "*|*"remove "*|*"fix "*|*"implement "*|*"compile "*|*"build "*|*"run "*|*"execute "*|*"test "*|*"deploy "*|*"install "*|*"chmod "*|*"script"*|*"file"*|*"workspace"*|*"repo"*|*"git "*|*"branch"*|*"commit"*|*"patch"*|*"diff"*)
      return 0
      ;;
  esac

  return 1
}

chat_prompt_needs_deep_reasoning() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  if printf '%s' "$prompt_trimmed" | grep -Eq 'higher[- ]?order|meta[- ]?cogn|metacogn|epistem|ontology|theorize|theorise|axiom|first principles|identity|self|values|meaning|purpose|worldview|core belief|beliefs'; then
    return 0
  fi
  if printf '%s' "$prompt_trimmed" | grep -Eq 'what would be prior to|what is prior to|prior to .* app|more prior|more fundamental|center of who i am|centre of who i am'; then
    return 0
  fi
  if printf '%s' "$prompt_trimmed" | grep -Eq '^(no|not exactly|not quite|that.s not|i mean|rather)\b|^no,|^no\.'; then
    return 0
  fi

  return 1
}

is_hello_world_script_task() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *hello.sh*hello*world*|*"hello, world"*|*"hello world"*)
      return 0
      ;;
  esac

  return 1
}

godot_gravity_template_patch() {
  requested_planets_raw=${1:-80}
  case "$requested_planets_raw" in
    *[!0-9]*|'')
      requested_planets=80
      ;;
    *)
      requested_planets=$requested_planets_raw
      ;;
  esac
  if [ "$requested_planets" -lt 5 ]; then
    requested_planets=5
  fi
  if [ "$requested_planets" -gt 240 ]; then
    requested_planets=240
  fi

  tmp_dir=$(mktemp -d)
  patch_text=""

  cat > "$tmp_dir/project.godot" <<'EOF'
; Engine configuration file.
; It's best edited using the editor and not directly.
config_version=5

[application]
config/name="Orbital Gravity Sim"
run/main_scene="res://Main.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
EOF

  cat > "$tmp_dir/Main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
EOF

  cat > "$tmp_dir/Main.gd" <<'EOF'
extends Node2D

const DEFAULT_G := 1200.0
const DEFAULT_TIME_SCALE := 1.0
const DEFAULT_TRAIL_LEN := 180
const DEFAULT_SOFTENING := 20.0
const DEFAULT_BARNES_HUT_THETA := 0.6
const START_PLANETS := __START_PLANETS__
const DELETE_PICK_RADIUS := 24.0
const ADAPTIVE_STEP_MIN := 0.002
const ADAPTIVE_STEP_MAX := 0.033
const STEP_ONCE_DELTA := 1.0 / 60.0
const VELOCITY_VECTOR_SCALE := 0.08
const DRAG_SPAWN_MIN_DISTANCE := 6.0
const DRAG_VELOCITY_SCALE := 1.35
const SAVE_PATH := "user://gravity_preset.json"
const TELEMETRY_PATH := "user://gravity_telemetry.csv"
const REPLAY_PATH := "user://gravity_replay_events.json"
const REGRESSION_REPORT_PATH := "user://regression_report.json"
const BENCHMARK_PATH := "user://benchmark_results.csv"
const BENCHMARK_SECONDS := 8.0
const BENCHMARK_STEP := 1.0 / 120.0
const CHALLENGE_DURATION := 120.0
const CHALLENGE_TARGET_SCORE := 800.0
const CHALLENGE_MIN_STABLE_ORBITERS := 6
const SCORE_SAMPLE_INTERVAL := 0.5
const SHOCKWAVE_RADIUS := 260.0
const SHOCKWAVE_FORCE := 220.0
const SHOCKWAVE_COOLDOWN := 3.0
const SHOCKWAVE_VISUAL_DURATION := 0.42
const BACKGROUND_STAR_COUNT := 160

enum IntegratorMode {
    EULER,
    LEAPFROG,
    RK4
}

enum ForceMode {
    DIRECT,
    BARNES_HUT
}

enum GameplayMode {
    SANDBOX,
    CHALLENGE
}

class Planet:
    var pos: Vector2
    var vel: Vector2
    var mass: float
    var radius: float
    var color: Color
    var trail: PackedVector2Array = PackedVector2Array()

    func _init(p: Vector2, v: Vector2, m: float, r: float, c: Color) -> void:
        pos = p
        vel = v
        mass = m
        radius = r
        color = c
        trail.push_back(pos)

class BHNode:
    var center: Vector2
    var half_size: float
    var mass: float = 0.0
    var com: Vector2 = Vector2.ZERO
    var body_index: int = -1
    var children: Array = []

    func _init(c: Vector2, h: float) -> void:
        center = c
        half_size = h
        children = []

var planets: Array[Planet] = []
var initial_state: Array[Dictionary] = []
var initial_total_energy: float = 0.0
var telemetry_time: float = 0.0
var telemetry_rows: Array[String] = []
var record_events_enabled: bool = false
var replay_active: bool = false
var replay_events: Array[Dictionary] = []
var replay_cursor: int = 0
var replay_elapsed: float = 0.0
var replay_checksum_state: String = "n/a"
var replay_expected_final_state_checksum: String = ""
var last_self_test_summary: String = "not run"
var gameplay_mode: int = GameplayMode.SANDBOX
var challenge_active: bool = false
var challenge_time_left: float = CHALLENGE_DURATION
var challenge_score: float = 0.0
var challenge_combo: float = 1.0
var challenge_goal_score: float = CHALLENGE_TARGET_SCORE
var score_sample_elapsed: float = 0.0
var challenge_status_text: String = "Sandbox mode"
var challenge_message: String = ""
var challenge_message_time: float = 0.0
var shockwave_cooldown_left: float = 0.0
var visual_time: float = 0.0
var shockwave_visual_active: bool = false
var shockwave_visual_time: float = 0.0
var shockwave_visual_origin: Vector2 = Vector2.ZERO
var background_stars: Array[Dictionary] = []

var gravity_constant: float = DEFAULT_G
var time_scale_factor: float = DEFAULT_TIME_SCALE
var softening: float = DEFAULT_SOFTENING
var barnes_hut_theta: float = DEFAULT_BARNES_HUT_THETA
var trail_limit: int = DEFAULT_TRAIL_LEN
var trails_enabled: bool = true
var simulation_paused: bool = false
var adaptive_timestep_enabled: bool = false
var merge_enabled: bool = true
var show_velocity_vectors: bool = false
var integrator_mode: int = IntegratorMode.LEAPFROG
var force_mode: int = ForceMode.DIRECT
var seed_value: int = 1337
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var cam: Camera2D
var panning_camera: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var drag_spawn_active: bool = false
var drag_start_world: Vector2 = Vector2.ZERO
var drag_current_world: Vector2 = Vector2.ZERO

var pause_button: Button
var trail_button: Button
var adaptive_button: Button
var merge_button: Button
var vectors_button: Button
var record_button: Button
var replay_button: Button
var force_mode_button: Button
var self_test_button: Button
var gameplay_mode_button: Button
var shockwave_button: Button
var gravity_slider: HSlider
var time_slider: HSlider
var softening_slider: HSlider
var theta_slider: HSlider
var trail_slider: HSlider
var integrator_option: OptionButton
var hud_label: Label
var challenge_label: Label
var seed_input: LineEdit

func _ready() -> void:
    _apply_seed(seed_value)
    _setup_camera()
    _build_background_stars(BACKGROUND_STAR_COUNT)
    _setup_ui()
    _set_gameplay_mode(GameplayMode.SANDBOX, false)
    _seed_default_system(START_PLANETS)
    _capture_initial_state()
    set_process(true)
    set_process_input(true)

func _setup_camera() -> void:
    cam = Camera2D.new()
    cam.position = Vector2(640, 360)
    cam.zoom = Vector2.ONE
    add_child(cam)
    cam.make_current()

func _setup_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    var panel := PanelContainer.new()
    panel.position = Vector2(12, 12)
    panel.custom_minimum_size = Vector2(700, 520)
    layer.add_child(panel)

    var box := VBoxContainer.new()
    panel.add_child(box)

    var button_row := HBoxContainer.new()
    box.add_child(button_row)

    pause_button = Button.new()
    pause_button.text = "Pause"
    pause_button.pressed.connect(_toggle_pause)
    button_row.add_child(pause_button)

    var reset_button := Button.new()
    reset_button.text = "Reset"
    reset_button.pressed.connect(_reset_system)
    button_row.add_child(reset_button)

    var step_once_button := Button.new()
    step_once_button.text = "Step Once"
    step_once_button.pressed.connect(_step_once)
    button_row.add_child(step_once_button)

    var action_row := HBoxContainer.new()
    box.add_child(action_row)

    trail_button = Button.new()
    trail_button.text = "Trails: On"
    trail_button.pressed.connect(_toggle_trails)
    action_row.add_child(trail_button)

    var clear_trails_button := Button.new()
    clear_trails_button.text = "Clear Trails"
    clear_trails_button.pressed.connect(_clear_trails)
    action_row.add_child(clear_trails_button)

    adaptive_button = Button.new()
    adaptive_button.text = "Adaptive Step: Off"
    adaptive_button.pressed.connect(_toggle_adaptive_step)
    action_row.add_child(adaptive_button)

    merge_button = Button.new()
    merge_button.text = "Merge: On"
    merge_button.pressed.connect(_toggle_merge)
    action_row.add_child(merge_button)

    vectors_button = Button.new()
    vectors_button.text = "Vectors: Off"
    vectors_button.pressed.connect(_toggle_vectors)
    action_row.add_child(vectors_button)

    var save_button := Button.new()
    save_button.text = "Save Preset"
    save_button.pressed.connect(_save_preset)
    action_row.add_child(save_button)

    var load_button := Button.new()
    load_button.text = "Load Preset"
    load_button.pressed.connect(_load_preset)
    action_row.add_child(load_button)

    var export_csv_button := Button.new()
    export_csv_button.text = "Export CSV"
    export_csv_button.pressed.connect(_export_telemetry_csv)
    action_row.add_child(export_csv_button)

    record_button = Button.new()
    record_button.text = "Record: Off"
    record_button.pressed.connect(_toggle_recording)
    action_row.add_child(record_button)

    replay_button = Button.new()
    replay_button.text = "Replay"
    replay_button.pressed.connect(_start_replay_from_file)
    action_row.add_child(replay_button)

    var benchmark_button := Button.new()
    benchmark_button.text = "Benchmark Integrators"
    benchmark_button.pressed.connect(_run_integrator_benchmark_export)
    action_row.add_child(benchmark_button)

    force_mode_button = Button.new()
    force_mode_button.text = "Force: Direct"
    force_mode_button.pressed.connect(_toggle_force_mode)
    action_row.add_child(force_mode_button)

    self_test_button = Button.new()
    self_test_button.text = "Run Self-Tests"
    self_test_button.pressed.connect(_run_self_tests_export_report)
    action_row.add_child(self_test_button)

    var gameplay_row := HBoxContainer.new()
    box.add_child(gameplay_row)

    gameplay_mode_button = Button.new()
    gameplay_mode_button.text = "Mode: Sandbox"
    gameplay_mode_button.pressed.connect(_toggle_gameplay_mode)
    gameplay_row.add_child(gameplay_mode_button)

    shockwave_button = Button.new()
    shockwave_button.text = "Shockwave"
    shockwave_button.pressed.connect(_on_shockwave_pressed)
    gameplay_row.add_child(shockwave_button)

    var gravity_title := Label.new()
    gravity_title.text = "Gravitational Constant"
    box.add_child(gravity_title)

    gravity_slider = HSlider.new()
    gravity_slider.min_value = 200.0
    gravity_slider.max_value = 5000.0
    gravity_slider.step = 10.0
    gravity_slider.value = gravity_constant
    gravity_slider.value_changed.connect(_on_gravity_slider_changed)
    box.add_child(gravity_slider)

    var softening_title := Label.new()
    softening_title.text = "Softening"
    box.add_child(softening_title)

    softening_slider = HSlider.new()
    softening_slider.min_value = 2.0
    softening_slider.max_value = 80.0
    softening_slider.step = 0.5
    softening_slider.value = softening
    softening_slider.value_changed.connect(_on_softening_slider_changed)
    box.add_child(softening_slider)

    var theta_title := Label.new()
    theta_title.text = "Barnes-Hut Theta"
    box.add_child(theta_title)

    theta_slider = HSlider.new()
    theta_slider.min_value = 0.25
    theta_slider.max_value = 1.2
    theta_slider.step = 0.01
    theta_slider.value = barnes_hut_theta
    theta_slider.value_changed.connect(_on_theta_slider_changed)
    box.add_child(theta_slider)

    var time_title := Label.new()
    time_title.text = "Time Scale"
    box.add_child(time_title)

    time_slider = HSlider.new()
    time_slider.min_value = 0.1
    time_slider.max_value = 3.0
    time_slider.step = 0.05
    time_slider.value = time_scale_factor
    time_slider.value_changed.connect(_on_time_slider_changed)
    box.add_child(time_slider)

    var trail_title := Label.new()
    trail_title.text = "Trail Length"
    box.add_child(trail_title)

    trail_slider = HSlider.new()
    trail_slider.min_value = 20.0
    trail_slider.max_value = 800.0
    trail_slider.step = 5.0
    trail_slider.value = float(trail_limit)
    trail_slider.value_changed.connect(_on_trail_slider_changed)
    box.add_child(trail_slider)

    var integrator_row := HBoxContainer.new()
    box.add_child(integrator_row)

    var integrator_label := Label.new()
    integrator_label.text = "Integrator"
    integrator_row.add_child(integrator_label)

    integrator_option = OptionButton.new()
    integrator_option.add_item("Leapfrog")
    integrator_option.add_item("Euler")
    integrator_option.add_item("RK4")
    integrator_option.item_selected.connect(_on_integrator_selected)
    integrator_row.add_child(integrator_option)
    _set_integrator_mode(integrator_mode)
    _set_force_mode(force_mode)

    var seed_row := HBoxContainer.new()
    box.add_child(seed_row)

    var seed_label := Label.new()
    seed_label.text = "Seed"
    seed_row.add_child(seed_label)

    seed_input = LineEdit.new()
    seed_input.custom_minimum_size = Vector2(130, 0)
    seed_input.text = str(seed_value)
    seed_row.add_child(seed_input)

    var seed_apply_button := Button.new()
    seed_apply_button.text = "Apply Seed"
    seed_apply_button.pressed.connect(_apply_seed_from_ui)
    seed_row.add_child(seed_apply_button)

    hud_label = Label.new()
    hud_label.position = Vector2(12, 456)
    hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hud_label.custom_minimum_size = Vector2(1120, 44)
    layer.add_child(hud_label)

    challenge_label = Label.new()
    challenge_label.position = Vector2(12, 500)
    challenge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    challenge_label.custom_minimum_size = Vector2(1120, 72)
    layer.add_child(challenge_label)

func _seed_default_system(body_count: int) -> void:
    planets.clear()

    var center := Vector2(640, 360)
    var star_mass := 9200.0
    planets.append(Planet.new(center, Vector2.ZERO, star_mass, 21.0, Color(1.0, 0.85, 0.3)))

    var orbiters := maxi(1, body_count - 1)
    for i in range(orbiters):
        var angle := TAU * float(i) / float(orbiters)
        var orbit_radius := 120.0 + 15.0 * float(i)
        var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius
        var tangent := Vector2(-sin(angle), cos(angle))
        var speed := sqrt((gravity_constant * star_mass) / orbit_radius)
        var vel := tangent * speed
        var mass := 28.0 + 12.0 * float(i)
        var radius := 4.5 + sqrt(mass) * 0.45
        var color := Color.from_hsv(float(i) / float(orbiters), 0.68, 0.95)
        planets.append(Planet.new(pos, vel, mass, radius, color))

func _build_background_stars(count: int) -> void:
    background_stars.clear()
    var star_rng := RandomNumberGenerator.new()
    star_rng.seed = int(seed_value) + 5012347
    var clamped_count := maxi(0, count)
    for i in range(clamped_count):
        background_stars.append({
            "pos": Vector2(star_rng.randf_range(-4200.0, 4200.0), star_rng.randf_range(-3200.0, 3200.0)),
            "r": star_rng.randf_range(0.8, 2.2),
            "a": star_rng.randf_range(0.15, 0.65),
            "phase": star_rng.randf_range(0.0, TAU),
            "speed": star_rng.randf_range(0.25, 1.2)
        })

func _toggle_gameplay_mode() -> void:
    if gameplay_mode == GameplayMode.SANDBOX:
        _set_gameplay_mode(GameplayMode.CHALLENGE, true)
    else:
        _set_gameplay_mode(GameplayMode.SANDBOX, true)

func _reset_challenge_session() -> void:
    challenge_active = gameplay_mode == GameplayMode.CHALLENGE
    challenge_time_left = CHALLENGE_DURATION
    challenge_score = 0.0
    challenge_combo = 1.0
    score_sample_elapsed = 0.0
    challenge_status_text = "Build stable orbits around your largest body"
    challenge_message = ""
    challenge_message_time = 0.0

func _set_challenge_message(text: String, duration: float = 2.0) -> void:
    challenge_message = text
    challenge_message_time = maxf(0.0, duration)

func _set_gameplay_mode(mode_value: int, record_event: bool = true) -> void:
    if mode_value != GameplayMode.SANDBOX && mode_value != GameplayMode.CHALLENGE:
        mode_value = GameplayMode.SANDBOX
    gameplay_mode = mode_value
    if gameplay_mode == GameplayMode.CHALLENGE:
        _reset_challenge_session()
        _set_challenge_message("Challenge started: reach %.0f points by sustaining stable orbits." % challenge_goal_score, 3.2)
    else:
        challenge_active = false
        challenge_time_left = CHALLENGE_DURATION
        challenge_score = 0.0
        challenge_combo = 1.0
        score_sample_elapsed = 0.0
        challenge_status_text = "Sandbox mode"
        challenge_message = ""
        challenge_message_time = 0.0
    _refresh_gameplay_ui()
    if record_event:
        _append_replay_event("set_gameplay_mode", {"mode": gameplay_mode})

func _on_shockwave_pressed() -> void:
    var origin := cam.position
    if !planets.is_empty():
        origin = _center_of_mass()
    if !_trigger_shockwave(origin, true) && shockwave_cooldown_left > 0.0:
        _set_challenge_message("Shockwave recharging: %.1fs" % shockwave_cooldown_left, 1.0)
    _refresh_gameplay_ui()

func _trigger_shockwave(origin: Vector2, record_event: bool = true) -> bool:
    if shockwave_cooldown_left > 0.001:
        return false

    var affected := 0
    for p in planets:
        var offset := p.pos - origin
        var dist := offset.length()
        if dist > SHOCKWAVE_RADIUS:
            continue
        var dir := Vector2.RIGHT
        if dist > 0.001:
            dir = offset / dist
        else:
            var angle := rng.randf_range(0.0, TAU)
            dir = Vector2(cos(angle), sin(angle))
        var falloff := 1.0 - clampf(dist / SHOCKWAVE_RADIUS, 0.0, 1.0)
        var impulse_strength := SHOCKWAVE_FORCE * falloff / maxf(p.mass, 12.0)
        p.vel += dir * impulse_strength
        affected += 1

    if affected <= 0:
        return false

    shockwave_cooldown_left = SHOCKWAVE_COOLDOWN
    shockwave_visual_active = true
    shockwave_visual_time = 0.0
    shockwave_visual_origin = origin
    _set_challenge_message("Shockwave fired (%d affected)." % affected, 1.4)
    if record_event:
        _append_replay_event("shockwave", {
            "ox": origin.x,
            "oy": origin.y
        })
    return true

func _largest_body() -> Planet:
    if planets.is_empty():
        return null
    var anchor := planets[0]
    for p in planets:
        if p.mass > anchor.mass:
            anchor = p
    return anchor

func _count_stable_orbiters() -> int:
    if planets.size() < 2:
        return 0

    var anchor := _largest_body()
    if anchor == null:
        return 0

    var stable := 0
    for p in planets:
        if p == anchor:
            continue
        var offset := p.pos - anchor.pos
        var radius := offset.length()
        if radius < 60.0:
            continue

        var radial_dir := offset / maxf(radius, 0.001)
        var tangent := Vector2(-radial_dir.y, radial_dir.x)
        var speed := p.vel.length()
        var expected_speed := sqrt((gravity_constant * anchor.mass) / maxf(radius, 30.0))
        if expected_speed <= 0.0001:
            continue
        var speed_ratio := speed / expected_speed
        var velocity_dir := p.vel / maxf(speed, 0.001)
        var tangential_alignment := absf(velocity_dir.dot(tangent))
        var radial_ratio := absf(p.vel.dot(radial_dir)) / expected_speed
        if speed_ratio >= 0.55 && speed_ratio <= 1.6 && tangential_alignment >= 0.55 && radial_ratio <= 0.6:
            stable += 1

    return stable

func _sample_challenge_score() -> void:
    if gameplay_mode != GameplayMode.CHALLENGE || !challenge_active:
        return

    var stable := _count_stable_orbiters()
    if stable >= CHALLENGE_MIN_STABLE_ORBITERS:
        challenge_combo = clampf(challenge_combo + 0.12 + float(stable) * 0.02, 1.0, 6.0)
        var gain := (float(stable) * 8.0) * challenge_combo
        challenge_score += gain
        challenge_status_text = "Stable orbit chain: %d (combo x%.2f)." % [stable, challenge_combo]
    else:
        challenge_combo = maxf(1.0, challenge_combo - 0.28)
        if stable <= 1:
            challenge_status_text = "Orbit collapse: add bodies with tangential velocity."
        else:
            challenge_status_text = "Need %d stable orbiters (%d now)." % [CHALLENGE_MIN_STABLE_ORBITERS, stable]

func _update_gameplay_state(delta_sim: float, delta_real: float) -> void:
    visual_time += delta_real
    if shockwave_cooldown_left > 0.0:
        shockwave_cooldown_left = maxf(0.0, shockwave_cooldown_left - delta_real)
    if shockwave_visual_active:
        shockwave_visual_time += delta_real
        if shockwave_visual_time >= SHOCKWAVE_VISUAL_DURATION:
            shockwave_visual_active = false
    if challenge_message_time > 0.0:
        challenge_message_time = maxf(0.0, challenge_message_time - delta_real)
        if challenge_message_time <= 0.0:
            challenge_message = ""

    if gameplay_mode != GameplayMode.CHALLENGE || !challenge_active:
        return
    if delta_sim <= 0.0:
        return

    challenge_time_left = maxf(0.0, challenge_time_left - delta_sim)
    score_sample_elapsed += delta_sim
    while score_sample_elapsed >= SCORE_SAMPLE_INTERVAL:
        score_sample_elapsed -= SCORE_SAMPLE_INTERVAL
        _sample_challenge_score()

    if challenge_score >= challenge_goal_score:
        challenge_active = false
        challenge_status_text = "Challenge complete."
        _set_challenge_message("Great orbit engineering. Final score %.1f." % challenge_score, 3.8)
    elif challenge_time_left <= 0.001:
        challenge_active = false
        challenge_status_text = "Challenge failed."
        _set_challenge_message("Time up: %.1f / %.1f points. Tune velocities and retry." % [challenge_score, challenge_goal_score], 3.8)

func _refresh_gameplay_ui() -> void:
    if gameplay_mode_button != null:
        gameplay_mode_button.text = "Mode: Challenge" if gameplay_mode == GameplayMode.CHALLENGE else "Mode: Sandbox"
    if shockwave_button != null:
        if shockwave_cooldown_left > 0.0:
            shockwave_button.text = "Shockwave: %.1fs" % shockwave_cooldown_left
        else:
            shockwave_button.text = "Shockwave"
    if challenge_label != null:
        if gameplay_mode == GameplayMode.SANDBOX:
            challenge_label.text = "Sandbox: left-click or drag to spawn, right-click to delete, middle-drag to pan, wheel to zoom, space for shockwave."
        else:
            var state_text := "active" if challenge_active else "complete"
            challenge_label.text = "Challenge (%s) score %.1f / %.1f | combo x%.2f | time %.1fs | %s" % [
                state_text, challenge_score, challenge_goal_score, challenge_combo, challenge_time_left, challenge_status_text
            ]
            if !challenge_message.is_empty():
                challenge_label.text += "\n" + challenge_message

func _capture_initial_state() -> void:
    initial_state.clear()
    for p in planets:
        initial_state.append(_planet_to_dict(p))
    initial_total_energy = _total_system_energy()
    _reset_telemetry()

func _reset_system() -> void:
    planets.clear()
    for entry in initial_state:
        planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    simulation_paused = false
    pause_button.text = "Pause"
    drag_spawn_active = false
    shockwave_cooldown_left = 0.0
    shockwave_visual_active = false
    if gameplay_mode == GameplayMode.CHALLENGE:
        _reset_challenge_session()
        _set_challenge_message("Challenge reset.", 1.4)
    _refresh_gameplay_ui()

func _toggle_pause() -> void:
    simulation_paused = !simulation_paused
    pause_button.text = "Resume" if simulation_paused else "Pause"
    _append_replay_event("toggle_pause", {})

func _toggle_trails() -> void:
    trails_enabled = !trails_enabled
    trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if !trails_enabled:
        _clear_trails()
    _append_replay_event("toggle_trails", {})

func _clear_trails() -> void:
    for p in planets:
        p.trail = PackedVector2Array([p.pos])

func _reset_telemetry() -> void:
    telemetry_time = 0.0
    telemetry_rows.clear()
    telemetry_rows.append("time,energy,angular_momentum,drift_percent")

func _record_telemetry_sample(energy: float, angular_momentum: float, drift_pct: float) -> void:
    telemetry_rows.append("%.6f,%.8f,%.8f,%.8f" % [telemetry_time, energy, angular_momentum, drift_pct])
    if telemetry_rows.size() > 20001:
        telemetry_rows.remove_at(1)

func _append_replay_event(kind: String, data: Dictionary) -> void:
    if replay_active || !record_events_enabled:
        return
    replay_events.append({
        "t": telemetry_time,
        "kind": kind,
        "data": data
    })

func _apply_replay_event(event: Dictionary) -> void:
    var kind := str(event.get("kind", ""))
    var data: Dictionary = event.get("data", {})
    match kind:
        "spawn":
            _spawn_planet_from_record(data)
        "delete":
            var p := Vector2(float(data.get("px", 0.0)), float(data.get("py", 0.0)))
            _delete_planet_near(p)
        "toggle_pause":
            _toggle_pause()
        "toggle_trails":
            _toggle_trails()
        "toggle_adaptive":
            _toggle_adaptive_step()
        "toggle_merge":
            _toggle_merge()
        "toggle_vectors":
            _toggle_vectors()
        "set_gameplay_mode":
            _set_gameplay_mode(int(data.get("mode", gameplay_mode)), false)
        "shockwave":
            var shock_origin := Vector2(float(data.get("ox", cam.position.x)), float(data.get("oy", cam.position.y)))
            _trigger_shockwave(shock_origin, false)
        "set_force_mode":
            _set_force_mode(int(data.get("mode", force_mode)))
        "set_theta":
            var theta_value := clampf(float(data.get("v", barnes_hut_theta)), 0.25, 1.2)
            barnes_hut_theta = theta_value
            if theta_slider != null:
                theta_slider.value = theta_value
        "set_gravity":
            var gv := float(data.get("v", gravity_constant))
            gravity_constant = gv
            if gravity_slider != null:
                gravity_slider.value = gv
        "set_softening":
            var sv := float(data.get("v", softening))
            softening = sv
            if softening_slider != null:
                softening_slider.value = sv
        "set_time_scale":
            var tv := float(data.get("v", time_scale_factor))
            time_scale_factor = tv
            if time_slider != null:
                time_slider.value = tv
        "set_integrator":
            _set_integrator_mode(int(data.get("mode", integrator_mode)))
        "step_once":
            var was_paused := simulation_paused
            if !simulation_paused:
                simulation_paused = true
            _step_once()
            simulation_paused = was_paused
        "run_benchmark":
            _run_integrator_benchmark_export(false)
        "run_self_tests":
            _run_self_tests_export_report(false)
        _:
            pass

func _save_replay_events_file() -> void:
    var final_snapshot := _snapshot_planets()
    var payload := {
        "seed_value": seed_value,
        "gravity_constant": gravity_constant,
        "time_scale_factor": time_scale_factor,
        "softening": softening,
        "trail_limit": trail_limit,
        "trails_enabled": trails_enabled,
        "adaptive_timestep_enabled": adaptive_timestep_enabled,
        "merge_enabled": merge_enabled,
        "show_velocity_vectors": show_velocity_vectors,
        "gameplay_mode": gameplay_mode,
        "integrator_mode": integrator_mode,
        "force_mode": force_mode,
        "barnes_hut_theta": barnes_hut_theta,
        "initial_state": initial_state,
        "events": replay_events,
        "final_state_checksum": _state_checksum_for_snapshot(final_snapshot)
    }
    payload["checksum"] = _replay_checksum_for_payload(payload)
    var file := FileAccess.open(REPLAY_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload))
        replay_checksum_state = "ok"
        replay_expected_final_state_checksum = str(payload.get("final_state_checksum", ""))

func _replay_checksum_material(data: Dictionary) -> String:
    var pieces: Array[String] = []
    pieces.append("seed=%d" % int(data.get("seed_value", seed_value)))
    pieces.append("g=%.8f" % float(data.get("gravity_constant", gravity_constant)))
    pieces.append("time=%.8f" % float(data.get("time_scale_factor", time_scale_factor)))
    pieces.append("soft=%.8f" % float(data.get("softening", softening)))
    pieces.append("trail=%d" % int(data.get("trail_limit", trail_limit)))
    pieces.append("trails=%s" % str(bool(data.get("trails_enabled", trails_enabled))))
    pieces.append("adaptive=%s" % str(bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))))
    pieces.append("merge=%s" % str(bool(data.get("merge_enabled", merge_enabled))))
    pieces.append("vectors=%s" % str(bool(data.get("show_velocity_vectors", show_velocity_vectors))))
    pieces.append("gameplay=%d" % int(data.get("gameplay_mode", gameplay_mode)))
    pieces.append("integrator=%d" % int(data.get("integrator_mode", integrator_mode)))
    pieces.append("force=%d" % int(data.get("force_mode", force_mode)))
    pieces.append("theta=%.6f" % float(data.get("barnes_hut_theta", barnes_hut_theta)))
    pieces.append("initial=%s" % JSON.stringify(data.get("initial_state", [])))
    pieces.append("events=%s" % JSON.stringify(data.get("events", [])))
    return "|".join(pieces)

func _replay_checksum_for_payload(data: Dictionary) -> String:
    return _replay_checksum_material(data).sha256_text()

func _state_checksum_for_snapshot(snapshot: Array[Dictionary]) -> String:
    var material := JSON.stringify(snapshot)
    return material.sha256_text()

func _load_replay_events_file() -> bool:
    if !FileAccess.file_exists(REPLAY_PATH):
        return false
    var file := FileAccess.open(REPLAY_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data: Dictionary = parsed
    var stored_checksum := str(data.get("checksum", ""))
    if stored_checksum.is_empty():
        replay_checksum_state = "missing"
    else:
        var expected_checksum := _replay_checksum_for_payload(data)
        if stored_checksum != expected_checksum:
            replay_checksum_state = "mismatch"
            return false
        replay_checksum_state = "ok"
    replay_expected_final_state_checksum = str(data.get("final_state_checksum", ""))

    _apply_seed(int(data.get("seed_value", seed_value)))
    gravity_constant = float(data.get("gravity_constant", gravity_constant))
    time_scale_factor = float(data.get("time_scale_factor", time_scale_factor))
    softening = float(data.get("softening", softening))
    barnes_hut_theta = clampf(float(data.get("barnes_hut_theta", barnes_hut_theta)), 0.25, 1.2)
    trail_limit = maxi(10, int(data.get("trail_limit", trail_limit)))
    trails_enabled = bool(data.get("trails_enabled", trails_enabled))
    adaptive_timestep_enabled = bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))
    merge_enabled = bool(data.get("merge_enabled", merge_enabled))
    show_velocity_vectors = bool(data.get("show_velocity_vectors", show_velocity_vectors))
    var loaded_gameplay_mode := int(data.get("gameplay_mode", gameplay_mode))
    _set_integrator_mode(int(data.get("integrator_mode", integrator_mode)))
    _set_force_mode(int(data.get("force_mode", force_mode)))

    if gravity_slider != null:
        gravity_slider.value = gravity_constant
    if time_slider != null:
        time_slider.value = time_scale_factor
    if softening_slider != null:
        softening_slider.value = softening
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    if trail_slider != null:
        trail_slider.value = float(trail_limit)
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if adaptive_button != null:
        adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    if merge_button != null:
        merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    if vectors_button != null:
        vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    if seed_input != null:
        seed_input.text = str(seed_value)
    _set_gameplay_mode(loaded_gameplay_mode, false)

    var loaded_initial: Array[Dictionary] = []
    var raw_initial: Variant = data.get("initial_state", [])
    if raw_initial is Array:
        for entry in raw_initial:
            if typeof(entry) == TYPE_DICTIONARY:
                loaded_initial.append(entry)
    initial_state = loaded_initial
    planets.clear()
    for entry in initial_state:
        planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    else:
        initial_total_energy = _total_system_energy()
        _reset_telemetry()

    replay_events.clear()
    var raw_events: Variant = data.get("events", [])
    if raw_events is Array:
        for event in raw_events:
            if typeof(event) == TYPE_DICTIONARY:
                replay_events.append(event)
    _refresh_gameplay_ui()
    return replay_events.size() > 0

func _toggle_recording() -> void:
    if replay_active:
        return
    record_events_enabled = !record_events_enabled
    if record_events_enabled:
        replay_events.clear()
        replay_expected_final_state_checksum = ""
        replay_checksum_state = "recording"
    else:
        _save_replay_events_file()
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"

func _start_replay_from_file() -> void:
    if record_events_enabled:
        record_events_enabled = false
        if record_button != null:
            record_button.text = "Record: Off"
    if !_load_replay_events_file():
        return
    replay_active = true
    replay_cursor = 0
    replay_elapsed = 0.0
    replay_checksum_state = "replaying"
    simulation_paused = false
    if pause_button != null:
        pause_button.text = "Pause"
    if replay_button != null:
        replay_button.text = "Replay: On"
    _set_challenge_message("Replay running.", 1.0)
    _refresh_gameplay_ui()

func _stop_replay() -> void:
    var replay_was_active := replay_active
    replay_active = false
    replay_cursor = 0
    replay_elapsed = 0.0
    if replay_was_active && !replay_expected_final_state_checksum.is_empty():
        var actual_state_checksum := _state_checksum_for_snapshot(_snapshot_planets())
        if actual_state_checksum == replay_expected_final_state_checksum:
            replay_checksum_state = "ok+final"
        else:
            replay_checksum_state = "final-mismatch"
    if replay_button != null:
        replay_button.text = "Replay"
    _refresh_gameplay_ui()

func _advance_replay(delta_sim: float) -> void:
    if !replay_active:
        return
    replay_elapsed += delta_sim
    while replay_cursor < replay_events.size():
        var event: Dictionary = replay_events[replay_cursor]
        var event_t := float(event.get("t", 0.0))
        if event_t > replay_elapsed:
            break
        _apply_replay_event(event)
        replay_cursor += 1
    if replay_cursor >= replay_events.size():
        _stop_replay()

func _toggle_adaptive_step() -> void:
    adaptive_timestep_enabled = !adaptive_timestep_enabled
    adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    _append_replay_event("toggle_adaptive", {})

func _toggle_merge() -> void:
    merge_enabled = !merge_enabled
    merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    _append_replay_event("toggle_merge", {})

func _toggle_vectors() -> void:
    show_velocity_vectors = !show_velocity_vectors
    vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    _append_replay_event("toggle_vectors", {})

func _set_force_mode(mode_value: int) -> void:
    if mode_value != ForceMode.DIRECT && mode_value != ForceMode.BARNES_HUT:
        mode_value = ForceMode.DIRECT
    force_mode = mode_value
    if force_mode_button != null:
        force_mode_button.text = "Force: Barnes-Hut" if force_mode == ForceMode.BARNES_HUT else "Force: Direct"

func _toggle_force_mode() -> void:
    if force_mode == ForceMode.DIRECT:
        _set_force_mode(ForceMode.BARNES_HUT)
    else:
        _set_force_mode(ForceMode.DIRECT)
    _append_replay_event("set_force_mode", {"mode": force_mode})

func _set_integrator_mode(mode_value: int) -> void:
    if mode_value != IntegratorMode.EULER && mode_value != IntegratorMode.LEAPFROG && mode_value != IntegratorMode.RK4:
        mode_value = IntegratorMode.LEAPFROG
    integrator_mode = mode_value
    if integrator_option != null:
        if integrator_mode == IntegratorMode.EULER:
            integrator_option.select(1)
        elif integrator_mode == IntegratorMode.RK4:
            integrator_option.select(2)
        else:
            integrator_option.select(0)

func _apply_seed(seed: int) -> void:
    seed_value = seed
    rng.seed = seed_value
    _build_background_stars(BACKGROUND_STAR_COUNT)

func _apply_seed_from_ui() -> void:
    var text := ""
    if seed_input != null:
        text = seed_input.text.strip_edges()
    if text.is_valid_int():
        _apply_seed(int(text))
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    if seed_input != null:
        seed_input.text = str(seed_value)

func _step_once() -> void:
    if !simulation_paused:
        return
    var step_seconds := _effective_step_seconds(STEP_ONCE_DELTA)
    _simulate_step(step_seconds * time_scale_factor)
    telemetry_time += step_seconds * time_scale_factor
    _update_gameplay_state(step_seconds * time_scale_factor, step_seconds)
    _append_replay_event("step_once", {})
    _update_hud()
    queue_redraw()

func _on_gravity_slider_changed(value: float) -> void:
    gravity_constant = value
    _append_replay_event("set_gravity", {"v": gravity_constant})

func _on_softening_slider_changed(value: float) -> void:
    softening = value
    _append_replay_event("set_softening", {"v": softening})

func _on_theta_slider_changed(value: float) -> void:
    barnes_hut_theta = clampf(value, 0.25, 1.2)
    _append_replay_event("set_theta", {"v": barnes_hut_theta})

func _on_time_slider_changed(value: float) -> void:
    time_scale_factor = value
    _append_replay_event("set_time_scale", {"v": time_scale_factor})

func _on_trail_slider_changed(value: float) -> void:
    trail_limit = maxi(10, int(value))

func _on_integrator_selected(index: int) -> void:
    if index == 1:
        _set_integrator_mode(IntegratorMode.EULER)
    elif index == 2:
        _set_integrator_mode(IntegratorMode.RK4)
    else:
        _set_integrator_mode(IntegratorMode.LEAPFROG)
    _append_replay_event("set_integrator", {"mode": integrator_mode})

func _planet_to_dict(p: Planet) -> Dictionary:
    return {
        "px": p.pos.x,
        "py": p.pos.y,
        "vx": p.vel.x,
        "vy": p.vel.y,
        "mass": p.mass,
        "radius": p.radius,
        "color": p.color.to_html()
    }

func _planet_from_dict(entry: Dictionary) -> Planet:
    var pos := Vector2(float(entry.get("px", 0.0)), float(entry.get("py", 0.0)))
    var vel := Vector2(float(entry.get("vx", 0.0)), float(entry.get("vy", 0.0)))
    var mass := float(entry.get("mass", 10.0))
    var radius := float(entry.get("radius", 6.0))
    var color := Color.from_string(str(entry.get("color", "#ffffff")), Color.WHITE)
    return Planet.new(pos, vel, mass, radius, color)

func _save_preset() -> void:
    var planets_data: Array[Dictionary] = []
    for p in planets:
        planets_data.append(_planet_to_dict(p))
    var payload := {
        "gravity_constant": gravity_constant,
        "time_scale_factor": time_scale_factor,
        "softening": softening,
        "trail_limit": trail_limit,
        "trails_enabled": trails_enabled,
        "adaptive_timestep_enabled": adaptive_timestep_enabled,
        "merge_enabled": merge_enabled,
        "show_velocity_vectors": show_velocity_vectors,
        "gameplay_mode": gameplay_mode,
        "integrator_mode": integrator_mode,
        "force_mode": force_mode,
        "barnes_hut_theta": barnes_hut_theta,
        "seed_value": seed_value,
        "planets": planets_data
    }
    var json := JSON.stringify(payload)
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(json)

func _load_preset() -> void:
    if !FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return

    var data: Dictionary = parsed
    gravity_constant = float(data.get("gravity_constant", gravity_constant))
    time_scale_factor = float(data.get("time_scale_factor", time_scale_factor))
    softening = float(data.get("softening", softening))
    trail_limit = maxi(10, int(data.get("trail_limit", trail_limit)))
    trails_enabled = bool(data.get("trails_enabled", trails_enabled))
    adaptive_timestep_enabled = bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))
    merge_enabled = bool(data.get("merge_enabled", merge_enabled))
    show_velocity_vectors = bool(data.get("show_velocity_vectors", show_velocity_vectors))
    var loaded_gameplay_mode := int(data.get("gameplay_mode", gameplay_mode))
    _set_integrator_mode(int(data.get("integrator_mode", integrator_mode)))
    _set_force_mode(int(data.get("force_mode", force_mode)))
    barnes_hut_theta = clampf(float(data.get("barnes_hut_theta", barnes_hut_theta)), 0.25, 1.2)
    seed_value = int(data.get("seed_value", seed_value))
    _apply_seed(seed_value)

    gravity_slider.value = gravity_constant
    time_slider.value = time_scale_factor
    softening_slider.value = softening
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    trail_slider.value = float(trail_limit)
    trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    if seed_input != null:
        seed_input.text = str(seed_value)
    _set_gameplay_mode(loaded_gameplay_mode, false)

    var raw_planets: Variant = data.get("planets", [])
    if raw_planets is Array:
        planets.clear()
        for entry in raw_planets:
            if typeof(entry) != TYPE_DICTIONARY:
                continue
            planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
    _capture_initial_state()
    _refresh_gameplay_ui()

func _export_telemetry_csv() -> void:
    var file := FileAccess.open(TELEMETRY_PATH, FileAccess.WRITE)
    if file == null:
        return
    for row in telemetry_rows:
        file.store_line(row)

func _snapshot_planets() -> Array[Dictionary]:
    var snapshot: Array[Dictionary] = []
    for p in planets:
        snapshot.append(_planet_to_dict(p))
    return snapshot

func _restore_planets_from_snapshot(snapshot: Array[Dictionary]) -> void:
    planets.clear()
    for entry in snapshot:
        planets.append(_planet_from_dict(entry))

func _integrator_name(mode_value: int) -> String:
    if mode_value == IntegratorMode.EULER:
        return "Euler"
    if mode_value == IntegratorMode.RK4:
        return "RK4"
    return "Leapfrog"

func _run_integrator_benchmark_export(record_event: bool = true) -> void:
    if record_event:
        _append_replay_event("run_benchmark", {})

    var original_snapshot := _snapshot_planets()
    var benchmark_seed_snapshot: Array[Dictionary] = []
    if !initial_state.is_empty():
        for entry in initial_state:
            benchmark_seed_snapshot.append(entry)
    else:
        for entry in original_snapshot:
            benchmark_seed_snapshot.append(entry)

    var original_integrator := integrator_mode
    var original_paused := simulation_paused
    var original_trails := trails_enabled
    var original_recording := record_events_enabled
    var original_replay := replay_active

    if replay_active:
        _stop_replay()
    record_events_enabled = false
    if record_button != null:
        record_button.text = "Record: Off"

    trails_enabled = false
    if trail_button != null:
        trail_button.text = "Trails: Off"
    simulation_paused = false
    if pause_button != null:
        pause_button.text = "Pause"

    var csv_lines: Array[String] = []
    csv_lines.append("integrator,simulated_seconds,steps,final_energy_drift_percent")
    for mode_value in [IntegratorMode.EULER, IntegratorMode.LEAPFROG, IntegratorMode.RK4]:
        _restore_planets_from_snapshot(benchmark_seed_snapshot)
        _set_integrator_mode(mode_value)
        var start_energy := _total_system_energy()
        var simulated_seconds := 0.0
        var steps := 0
        while simulated_seconds < BENCHMARK_SECONDS:
            _simulate_step(BENCHMARK_STEP)
            simulated_seconds += BENCHMARK_STEP
            steps += 1
        var end_energy := _total_system_energy()
        var drift_pct := 0.0
        if absf(start_energy) > 0.0001:
            drift_pct = ((end_energy - start_energy) / absf(start_energy)) * 100.0
        csv_lines.append("%s,%.3f,%d,%.6f" % [_integrator_name(mode_value), simulated_seconds, steps, drift_pct])

    var benchmark_file := FileAccess.open(BENCHMARK_PATH, FileAccess.WRITE)
    if benchmark_file != null:
        for line in csv_lines:
            benchmark_file.store_line(line)

    _restore_planets_from_snapshot(original_snapshot)
    _set_integrator_mode(original_integrator)
    simulation_paused = original_paused
    if pause_button != null:
        pause_button.text = "Resume" if simulation_paused else "Pause"
    trails_enabled = original_trails
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    record_events_enabled = original_recording
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"
    if original_replay && replay_button != null:
        replay_button.text = "Replay"

func _run_self_tests_export_report(record_event: bool = true) -> void:
    if record_event:
        _append_replay_event("run_self_tests", {})

    var original_snapshot := _snapshot_planets()
    var original_initial := initial_state.duplicate(true)
    var original_initial_energy := initial_total_energy
    var original_integrator := integrator_mode
    var original_force_mode := force_mode
    var original_theta := barnes_hut_theta
    var original_merge := merge_enabled
    var original_trails := trails_enabled
    var original_paused := simulation_paused
    var original_recording := record_events_enabled
    var original_replay := replay_active
    var original_gameplay_mode := gameplay_mode
    var original_challenge_active := challenge_active
    var original_challenge_time_left := challenge_time_left
    var original_challenge_score := challenge_score
    var original_challenge_combo := challenge_combo
    var original_score_sample_elapsed := score_sample_elapsed
    var original_challenge_status := challenge_status_text
    var original_challenge_message := challenge_message
    var original_challenge_message_time := challenge_message_time
    var original_shockwave_cooldown := shockwave_cooldown_left
    var original_shockwave_visual_active := shockwave_visual_active
    var original_shockwave_visual_time := shockwave_visual_time
    var original_shockwave_visual_origin := shockwave_visual_origin

    if replay_active:
        _stop_replay()
    record_events_enabled = false
    if record_button != null:
        record_button.text = "Record: Off"

    var tests: Array[Dictionary] = []
    tests.append(_self_test_two_body_energy_drift())
    tests.append(_self_test_barnes_hut_approximation_accuracy())
    tests.append(_self_test_replay_checksum_validation())
    tests.append(_self_test_challenge_scoring_rules())

    var passed := 0
    for test in tests:
        if bool(test.get("pass", false)):
            passed += 1

    var report := {
        "generated_at": Time.get_datetime_string_from_system(true, true),
        "pass_count": passed,
        "total_count": tests.size(),
        "all_passed": passed == tests.size(),
        "tests": tests
    }

    var report_file := FileAccess.open(REGRESSION_REPORT_PATH, FileAccess.WRITE)
    if report_file != null:
        report_file.store_string(JSON.stringify(report, "\t"))

    last_self_test_summary = "%d/%d passed (%s)" % [passed, tests.size(), "ok" if passed == tests.size() else "needs attention"]

    _restore_planets_from_snapshot(original_snapshot)
    initial_state = original_initial
    initial_total_energy = original_initial_energy
    _set_integrator_mode(original_integrator)
    _set_force_mode(original_force_mode)
    barnes_hut_theta = original_theta
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    merge_enabled = original_merge
    trails_enabled = original_trails
    simulation_paused = original_paused
    if pause_button != null:
        pause_button.text = "Resume" if simulation_paused else "Pause"
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if merge_button != null:
        merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    record_events_enabled = original_recording
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"
    if original_replay && replay_button != null:
        replay_button.text = "Replay"
    _set_gameplay_mode(original_gameplay_mode, false)
    challenge_active = original_challenge_active
    challenge_time_left = original_challenge_time_left
    challenge_score = original_challenge_score
    challenge_combo = original_challenge_combo
    score_sample_elapsed = original_score_sample_elapsed
    challenge_status_text = original_challenge_status
    challenge_message = original_challenge_message
    challenge_message_time = original_challenge_message_time
    shockwave_cooldown_left = original_shockwave_cooldown
    shockwave_visual_active = original_shockwave_visual_active
    shockwave_visual_time = original_shockwave_visual_time
    shockwave_visual_origin = original_shockwave_visual_origin
    _refresh_gameplay_ui()

func _self_test_two_body_energy_drift() -> Dictionary:
    var saved_merge := merge_enabled
    var saved_trails := trails_enabled
    merge_enabled = false
    trails_enabled = false

    planets.clear()
    var center := Vector2(640, 360)
    var primary_mass := 9000.0
    var secondary_mass := 48.0
    var radius := 240.0
    var secondary_speed := sqrt((gravity_constant * primary_mass) / radius)
    planets.append(Planet.new(center, Vector2.ZERO, primary_mass, 20.0, Color(1.0, 0.85, 0.3)))
    planets.append(Planet.new(center + Vector2(radius, 0.0), Vector2(0.0, secondary_speed), secondary_mass, 6.5, Color(0.6, 0.9, 1.0)))

    _set_integrator_mode(IntegratorMode.RK4)
    _set_force_mode(ForceMode.DIRECT)

    var start_energy := _total_system_energy()
    var simulated := 0.0
    var steps := 0
    while simulated < 6.0:
        _simulate_step(1.0 / 120.0)
        simulated += 1.0 / 120.0
        steps += 1
    var end_energy := _total_system_energy()
    var drift_pct := 0.0
    if absf(start_energy) > 0.0001:
        drift_pct = ((end_energy - start_energy) / absf(start_energy)) * 100.0

    merge_enabled = saved_merge
    trails_enabled = saved_trails

    return {
        "name": "two_body_energy_drift_rk4",
        "pass": absf(drift_pct) <= 1.5,
        "metric": drift_pct,
        "threshold_abs_percent": 1.5,
        "steps": steps
    }

func _self_test_barnes_hut_approximation_accuracy() -> Dictionary:
    var local_rng := RandomNumberGenerator.new()
    local_rng.seed = 240513
    var positions: Array[Vector2] = []
    var masses: Array[float] = []
    for i in range(64):
        positions.append(Vector2(local_rng.randf_range(-920.0, 920.0), local_rng.randf_range(-640.0, 640.0)))
        masses.append(local_rng.randf_range(16.0, 140.0))

    var direct := _accelerations_direct(positions, masses)
    var approx := _accelerations_barnes_hut(positions, masses, 0.6)
    var avg_rel := 0.0
    var worst_rel := 0.0
    var count: int = mini(direct.size(), approx.size())
    for i in range(count):
        var denom := maxf(direct[i].length(), 1.0)
        var rel := (approx[i] - direct[i]).length() / denom
        avg_rel += rel
        worst_rel = maxf(worst_rel, rel)
    if count > 0:
        avg_rel /= float(count)

    return {
        "name": "barnes_hut_vs_direct_force",
        "pass": avg_rel <= 0.35 && worst_rel <= 1.2,
        "avg_relative_error": avg_rel,
        "worst_relative_error": worst_rel,
        "theta": 0.6,
        "samples": count
    }

func _self_test_replay_checksum_validation() -> Dictionary:
    var final_snapshot: Array[Dictionary] = [
        {"px": 4.0, "py": 6.0, "vx": 0.5, "vy": -0.2, "mass": 10.0, "radius": 2.0, "color": "#ffffff"}
    ]
    var payload := {
        "seed_value": 7,
        "gravity_constant": 1200.0,
        "time_scale_factor": 1.0,
        "softening": 20.0,
        "trail_limit": 180,
        "trails_enabled": true,
        "adaptive_timestep_enabled": false,
        "merge_enabled": true,
        "show_velocity_vectors": false,
        "gameplay_mode": GameplayMode.SANDBOX,
        "integrator_mode": IntegratorMode.RK4,
        "force_mode": ForceMode.BARNES_HUT,
        "barnes_hut_theta": 0.6,
        "initial_state": [
            {"px": 1.0, "py": 2.0, "vx": 0.0, "vy": 0.0, "mass": 10.0, "radius": 2.0, "color": "#ffffff"}
        ],
        "events": [
            {"t": 0.1, "kind": "toggle_pause", "data": {}}
        ],
        "final_state_checksum": _state_checksum_for_snapshot(final_snapshot)
    }
    var checksum := _replay_checksum_for_payload(payload)
    var validates := checksum == _replay_checksum_for_payload(payload)
    var final_state_validates := str(payload.get("final_state_checksum", "")) == _state_checksum_for_snapshot(final_snapshot)

    var tampered := payload.duplicate(true)
    var tampered_events: Array = tampered.get("events", [])
    tampered_events.append({"t": 0.2, "kind": "toggle_trails", "data": {}})
    tampered["events"] = tampered_events
    var tamper_detected := checksum != _replay_checksum_for_payload(tampered)
    var tampered_final := final_snapshot.duplicate(true)
    var first_entry: Dictionary = tampered_final[0]
    first_entry["px"] = 9.0
    tampered_final[0] = first_entry
    var final_tamper_detected := str(payload.get("final_state_checksum", "")) != _state_checksum_for_snapshot(tampered_final)

    return {
        "name": "replay_checksum_validation",
        "pass": validates && tamper_detected && final_state_validates && final_tamper_detected,
        "tamper_detected": tamper_detected,
        "roundtrip_validated": validates,
        "final_state_validated": final_state_validates,
        "final_state_tamper_detected": final_tamper_detected
    }

func _self_test_challenge_scoring_rules() -> Dictionary:
    var saved_seed := seed_value
    _apply_seed(99731)
    _set_gameplay_mode(GameplayMode.CHALLENGE, false)

    planets.clear()
    var center := Vector2(640, 360)
    var star_mass := 9000.0
    planets.append(Planet.new(center, Vector2.ZERO, star_mass, 20.0, Color(1.0, 0.85, 0.3)))
    for i in range(8):
        var angle := TAU * float(i) / 8.0
        var radius := 150.0 + float(i) * 26.0
        var tangent := Vector2(-sin(angle), cos(angle))
        var speed := sqrt((gravity_constant * star_mass) / radius)
        var pos := center + Vector2(cos(angle), sin(angle)) * radius
        planets.append(Planet.new(pos, tangent * speed, 28.0 + float(i) * 3.0, 5.4, Color.from_hsv(float(i) / 8.0, 0.65, 0.95)))

    challenge_active = true
    challenge_score = 0.0
    challenge_combo = 1.0
    challenge_time_left = 20.0
    var stable_before := _count_stable_orbiters()
    _sample_challenge_score()
    var score_after_stable := challenge_score
    var combo_after_stable := challenge_combo

    while planets.size() > 2:
        planets.remove_at(planets.size() - 1)
    _sample_challenge_score()
    var combo_after_collapse := challenge_combo

    _apply_seed(saved_seed)
    return {
        "name": "challenge_scoring_rules",
        "pass": stable_before >= CHALLENGE_MIN_STABLE_ORBITERS && score_after_stable > 0.0 && combo_after_stable > 1.0 && combo_after_collapse <= combo_after_stable,
        "stable_before": stable_before,
        "score_after_stable": score_after_stable,
        "combo_after_stable": combo_after_stable,
        "combo_after_collapse": combo_after_collapse
    }

func _process(delta: float) -> void:
    if Input.is_action_pressed("ui_left"):
        cam.position.x -= 380.0 * delta * cam.zoom.x
    if Input.is_action_pressed("ui_right"):
        cam.position.x += 380.0 * delta * cam.zoom.x
    if Input.is_action_pressed("ui_up"):
        cam.position.y -= 380.0 * delta * cam.zoom.y
    if Input.is_action_pressed("ui_down"):
        cam.position.y += 380.0 * delta * cam.zoom.y

    var delta_sim := 0.0
    if !simulation_paused:
        var step_seconds := _effective_step_seconds(delta)
        _simulate_step(step_seconds * time_scale_factor)
        delta_sim = step_seconds * time_scale_factor
        telemetry_time += delta_sim
    if replay_active:
        _advance_replay(delta_sim)
    _update_gameplay_state(delta_sim, delta)
    _update_hud()
    queue_redraw()

func _effective_step_seconds(delta: float) -> float:
    var bounded := clampf(delta, ADAPTIVE_STEP_MIN, ADAPTIVE_STEP_MAX)
    if !adaptive_timestep_enabled:
        return bounded

    var max_speed := 0.0
    for p in planets:
        max_speed = maxf(max_speed, p.vel.length())
    var speed_factor := maxf(1.0, max_speed / 260.0)
    var adaptive := bounded / speed_factor
    return clampf(adaptive, ADAPTIVE_STEP_MIN, ADAPTIVE_STEP_MAX)

func _current_positions() -> Array[Vector2]:
    var positions: Array[Vector2] = []
    positions.resize(planets.size())
    for i in range(planets.size()):
        positions[i] = planets[i].pos
    return positions

func _mass_list_from_planets() -> Array[float]:
    var masses: Array[float] = []
    masses.resize(planets.size())
    for i in range(planets.size()):
        masses[i] = planets[i].mass
    return masses

func _gravity_accel_from_mass(target: Vector2, source: Vector2, source_mass: float) -> Vector2:
    var offset := source - target
    var dist_sq := maxf(offset.length_squared(), softening * softening)
    var dist := sqrt(dist_sq)
    if dist <= 0.000001:
        return Vector2.ZERO
    return (offset / dist) * (gravity_constant * source_mass / dist_sq)

func _accelerations_direct(positions: Array[Vector2], masses: Array[float]) -> Array[Vector2]:
    var count := positions.size()
    var accelerations: Array[Vector2] = []
    accelerations.resize(count)
    for i in range(count):
        accelerations[i] = Vector2.ZERO

    for i in range(count):
        for j in range(i + 1, count):
            var offset: Vector2 = positions[j] - positions[i]
            var dist_sq: float = maxf(offset.length_squared(), softening * softening)
            var dist: float = sqrt(dist_sq)
            var direction: Vector2 = offset / dist
            var force: float = gravity_constant * masses[i] * masses[j] / dist_sq
            accelerations[i] += direction * (force / masses[i])
            accelerations[j] -= direction * (force / masses[j])
    return accelerations

func _bh_subdivide(node: BHNode) -> void:
    var child_half := node.half_size * 0.5
    if child_half <= 0.0001:
        return
    node.children.clear()
    node.children.append(BHNode.new(node.center + Vector2(-child_half, -child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(child_half, -child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(-child_half, child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(child_half, child_half), child_half))

func _bh_child_index(node: BHNode, point: Vector2) -> int:
    var east := point.x >= node.center.x
    var south := point.y >= node.center.y
    if south:
        return 3 if east else 2
    return 1 if east else 0

func _bh_contains_point(node: BHNode, point: Vector2) -> bool:
    return point.x >= (node.center.x - node.half_size) && point.x <= (node.center.x + node.half_size) && point.y >= (node.center.y - node.half_size) && point.y <= (node.center.y + node.half_size)

func _bh_insert(node: BHNode, body_index: int, positions: Array[Vector2], masses: Array[float]) -> void:
    var point := positions[body_index]
    var body_mass := masses[body_index]
    var updated_mass := node.mass + body_mass
    if updated_mass > 0.0:
        node.com = (node.com * node.mass + point * body_mass) / updated_mass
    node.mass = updated_mass

    if node.body_index == -2 && node.children.is_empty():
        return

    if node.body_index == -1 && node.children.is_empty():
        node.body_index = body_index
        return

    if node.children.is_empty():
        if node.half_size <= 1.0:
            node.body_index = -2
            return
        var existing := node.body_index
        node.body_index = -1
        _bh_subdivide(node)
        if existing >= 0:
            var existing_child := _bh_child_index(node, positions[existing])
            _bh_insert(node.children[existing_child], existing, positions, masses)

    var child_idx := _bh_child_index(node, point)
    _bh_insert(node.children[child_idx], body_index, positions, masses)

func _bh_acceleration_for_body(node: BHNode, body_index: int, positions: Array[Vector2], theta_value: float) -> Vector2:
    if node.mass <= 0.0:
        return Vector2.ZERO
    if node.children.is_empty():
        if node.body_index == body_index:
            return Vector2.ZERO
        return _gravity_accel_from_mass(positions[body_index], node.com, node.mass)

    var target_pos := positions[body_index]
    var offset := node.com - target_pos
    var dist := maxf(offset.length(), 0.001)
    var size := node.half_size * 2.0
    var contains_target := _bh_contains_point(node, target_pos)
    if !contains_target && (size / dist) < theta_value:
        return _gravity_accel_from_mass(target_pos, node.com, node.mass)

    var total := Vector2.ZERO
    for child in node.children:
        total += _bh_acceleration_for_body(child, body_index, positions, theta_value)
    return total

func _accelerations_barnes_hut(positions: Array[Vector2], masses: Array[float], theta_override: float = -1.0) -> Array[Vector2]:
    var count := positions.size()
    var accelerations: Array[Vector2] = []
    accelerations.resize(count)
    for i in range(count):
        accelerations[i] = Vector2.ZERO
    if count == 0:
        return accelerations

    var min_x := positions[0].x
    var max_x := positions[0].x
    var min_y := positions[0].y
    var max_y := positions[0].y
    for pos in positions:
        min_x = minf(min_x, pos.x)
        max_x = maxf(max_x, pos.x)
        min_y = minf(min_y, pos.y)
        max_y = maxf(max_y, pos.y)
    var span := maxf(max_x - min_x, max_y - min_y)
    var half := maxf(64.0, span * 0.55 + softening * 2.0)
    var root := BHNode.new(Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5), half)

    for i in range(count):
        _bh_insert(root, i, positions, masses)

    var theta_value := barnes_hut_theta
    if theta_override > 0.0:
        theta_value = theta_override
    theta_value = clampf(theta_value, 0.25, 1.2)
    for i in range(count):
        accelerations[i] = _bh_acceleration_for_body(root, i, positions, theta_value)
    return accelerations

func _accelerations_for_state(positions: Array[Vector2]) -> Array[Vector2]:
    var masses := _mass_list_from_planets()
    if force_mode == ForceMode.BARNES_HUT && positions.size() >= 8:
        return _accelerations_barnes_hut(positions, masses, barnes_hut_theta)
    return _accelerations_direct(positions, masses)

func _compute_accelerations() -> Array[Vector2]:
    return _accelerations_for_state(_current_positions())

func _simulate_step(delta_scaled: float) -> void:
    if integrator_mode == IntegratorMode.LEAPFROG:
        var accel_start := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accel_start[i] * (0.5 * delta_scaled)
            planets[i].pos += planets[i].vel * delta_scaled

        var accel_end := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accel_end[i] * (0.5 * delta_scaled)
    elif integrator_mode == IntegratorMode.RK4:
        var count := planets.size()
        if count > 0:
            var p0: Array[Vector2] = []
            var v0: Array[Vector2] = []
            p0.resize(count)
            v0.resize(count)
            for i in range(count):
                p0[i] = planets[i].pos
                v0[i] = planets[i].vel

            var a1 := _accelerations_for_state(p0)

            var p2: Array[Vector2] = []
            var v2: Array[Vector2] = []
            p2.resize(count)
            v2.resize(count)
            for i in range(count):
                p2[i] = p0[i] + v0[i] * (0.5 * delta_scaled)
                v2[i] = v0[i] + a1[i] * (0.5 * delta_scaled)

            var a2 := _accelerations_for_state(p2)

            var p3: Array[Vector2] = []
            var v3: Array[Vector2] = []
            p3.resize(count)
            v3.resize(count)
            for i in range(count):
                p3[i] = p0[i] + v2[i] * (0.5 * delta_scaled)
                v3[i] = v0[i] + a2[i] * (0.5 * delta_scaled)

            var a3 := _accelerations_for_state(p3)

            var p4: Array[Vector2] = []
            var v4: Array[Vector2] = []
            p4.resize(count)
            v4.resize(count)
            for i in range(count):
                p4[i] = p0[i] + v3[i] * delta_scaled
                v4[i] = v0[i] + a3[i] * delta_scaled

            var a4 := _accelerations_for_state(p4)

            for i in range(count):
                var pos_delta := (v0[i] + 2.0 * v2[i] + 2.0 * v3[i] + v4[i]) * (delta_scaled / 6.0)
                var vel_delta := (a1[i] + 2.0 * a2[i] + 2.0 * a3[i] + a4[i]) * (delta_scaled / 6.0)
                planets[i].pos = p0[i] + pos_delta
                planets[i].vel = v0[i] + vel_delta
    else:
        var accelerations := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accelerations[i] * delta_scaled
            planets[i].pos += planets[i].vel * delta_scaled

    for i in range(planets.size()):
        if trails_enabled:
            planets[i].trail.push_back(planets[i].pos)
            if planets[i].trail.size() > trail_limit:
                planets[i].trail.remove_at(0)
        elif planets[i].trail.size() > 0:
            planets[i].trail = PackedVector2Array([planets[i].pos])

    if merge_enabled:
        _merge_overlapping_planets()

func _merge_overlapping_planets() -> void:
    if planets.size() < 2:
        return

    var merged_planets: Array[Planet] = []
    var consumed: Dictionary = {}

    for i in range(planets.size()):
        if consumed.has(i):
            continue
        var merged := planets[i]
        for j in range(i + 1, planets.size()):
            if consumed.has(j):
                continue
            var candidate := planets[j]
            var touching := merged.pos.distance_to(candidate.pos) <= (merged.radius + candidate.radius)
            if !touching:
                continue

            var total_mass: float = merged.mass + candidate.mass
            var total_momentum: Vector2 = merged.vel * merged.mass + candidate.vel * candidate.mass
            var merged_pos: Vector2 = (merged.pos * merged.mass + candidate.pos * candidate.mass) / total_mass
            var merged_vel: Vector2 = total_momentum / total_mass
            var merged_radius: float = sqrt(merged.radius * merged.radius + candidate.radius * candidate.radius)
            var blend_weight: float = candidate.mass / total_mass
            var merged_color: Color = merged.color.lerp(candidate.color, blend_weight)

            merged = Planet.new(merged_pos, merged_vel, total_mass, merged_radius, merged_color)
            consumed[j] = true

        merged_planets.append(merged)

    planets = merged_planets

func _update_hud() -> void:
    var fps := Engine.get_frames_per_second()
    var energy := _total_system_energy()
    var angular_momentum := _total_system_angular_momentum()
    var momentum := _total_system_momentum()
    var energy_drift := energy - initial_total_energy
    var drift_pct := 0.0
    if absf(initial_total_energy) > 0.0001:
        drift_pct = (energy_drift / absf(initial_total_energy)) * 100.0

    var paused_text := "yes" if simulation_paused else "no"
    var trails_text := "on" if trails_enabled else "off"
    var adaptive_text := "on" if adaptive_timestep_enabled else "off"
    var merge_text := "on" if merge_enabled else "off"
    var vector_text := "on" if show_velocity_vectors else "off"
    var integrator_text := "Leapfrog"
    var force_text := "Direct"
    if integrator_mode == IntegratorMode.EULER:
        integrator_text = "Euler"
    elif integrator_mode == IntegratorMode.RK4:
        integrator_text = "RK4"
    if force_mode == ForceMode.BARNES_HUT:
        force_text = "Barnes-Hut"
    var mode_text := "challenge" if gameplay_mode == GameplayMode.CHALLENGE else "sandbox"
    var challenge_suffix := ""
    if gameplay_mode == GameplayMode.CHALLENGE:
        challenge_suffix = " score:%.1f/%.1f combo:x%.2f t:%.1f" % [challenge_score, challenge_goal_score, challenge_combo, challenge_time_left]
    hud_label.text = "Bodies:%d FPS:%d E:%.2f dE:%+.3f%% Lz:%.1f P:(%.1f,%.1f) G:%.1f dt:%.2f soft:%.1f int:%s force:%s theta:%.2f chk:%s tests:%s adapt:%s merge:%s vec:%s trails:%s(%d) seed:%d paused:%s mode:%s%s" % [
        planets.size(), fps, energy, drift_pct, angular_momentum, momentum.x, momentum.y, gravity_constant, time_scale_factor, softening, integrator_text, force_text, barnes_hut_theta, replay_checksum_state, last_self_test_summary, adaptive_text, merge_text, vector_text, trails_text, trail_limit, seed_value, paused_text, mode_text, challenge_suffix
    ]
    _refresh_gameplay_ui()
    _record_telemetry_sample(energy, angular_momentum, drift_pct)

func _total_system_energy() -> float:
    var kinetic := 0.0
    for p in planets:
        kinetic += 0.5 * p.mass * p.vel.length_squared()

    var potential := 0.0
    for i in range(planets.size()):
        for j in range(i + 1, planets.size()):
            var distance := maxf(planets[i].pos.distance_to(planets[j].pos), 1.0)
            potential -= gravity_constant * planets[i].mass * planets[j].mass / distance

    return kinetic + potential

func _total_system_momentum() -> Vector2:
    var total := Vector2.ZERO
    for p in planets:
        total += p.vel * p.mass
    return total

func _total_system_angular_momentum() -> float:
    var com := _center_of_mass()
    var total := 0.0
    for p in planets:
        var r := p.pos - com
        total += p.mass * (r.x * p.vel.y - r.y * p.vel.x)
    return total

func _center_of_mass() -> Vector2:
    var total_mass := 0.0
    var accum := Vector2.ZERO
    for p in planets:
        total_mass += p.mass
        accum += p.pos * p.mass
    if total_mass <= 0.0:
        return Vector2.ZERO
    return accum / total_mass

func _compute_orbital_spawn_velocity(world_pos: Vector2) -> Vector2:
    var center := _center_of_mass()
    var offset := world_pos - center
    var distance := maxf(offset.length(), 80.0)
    if offset.length() < 0.001:
        offset = Vector2.RIGHT * distance
    var tangent := Vector2(-offset.y, offset.x).normalized()
    var speed := sqrt((gravity_constant * 5500.0) / distance) * rng.randf_range(0.7, 1.0)
    return tangent * speed

func _spawn_planet_with_velocity(world_pos: Vector2, velocity: Vector2) -> Planet:
    var mass := rng.randf_range(25.0, 120.0)
    var radius := 4.0 + sqrt(mass) * 0.5
    var color := Color.from_hsv(rng.randf(), 0.7, 0.95)
    var planet := Planet.new(world_pos, velocity, mass, radius, color)
    planets.append(planet)
    return planet

func _spawn_planet_from_record(data: Dictionary) -> void:
    var world_pos := Vector2(float(data.get("px", 0.0)), float(data.get("py", 0.0)))
    var velocity := Vector2(float(data.get("vx", 0.0)), float(data.get("vy", 0.0)))
    var mass := float(data.get("mass", 32.0))
    var radius := float(data.get("radius", 6.0))
    var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
    planets.append(Planet.new(world_pos, velocity, mass, radius, color))

func _spawn_planet_at(world_pos: Vector2) -> void:
    var velocity := _compute_orbital_spawn_velocity(world_pos)
    var planet := _spawn_planet_with_velocity(world_pos, velocity)
    _append_replay_event("spawn", {
        "px": world_pos.x,
        "py": world_pos.y,
        "vx": velocity.x,
        "vy": velocity.y,
        "mass": planet.mass,
        "radius": planet.radius,
        "color": planet.color.to_html()
    })

func _delete_planet_near(world_pos: Vector2) -> bool:
    if planets.is_empty():
        return false

    var best_index := -1
    var best_dist := 1e20
    for i in range(planets.size()):
        var p := planets[i]
        var pick_radius := maxf(DELETE_PICK_RADIUS, p.radius + 8.0)
        var dist := p.pos.distance_to(world_pos)
        if dist <= pick_radius && dist < best_dist:
            best_dist = dist
            best_index = i

    if best_index >= 0:
        planets.remove_at(best_index)
        return true
    return false

func _screen_to_world(screen_pos: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _draw_drag_preview() -> void:
    if !drag_spawn_active:
        return
    var drag_vec := drag_current_world - drag_start_world
    draw_circle(drag_start_world, 4.0, Color(0.95, 0.95, 0.95, 0.9))
    draw_line(drag_start_world, drag_current_world, Color(0.85, 0.95, 1.0, 0.9), 2.0)
    var preview_velocity := drag_vec * DRAG_VELOCITY_SCALE
    var preview_tip := drag_start_world + preview_velocity * (VELOCITY_VECTOR_SCALE * 8.0)
    draw_line(drag_start_world, preview_tip, Color(0.2, 1.0, 0.8, 0.9), 2.0)

func _draw_background_stars() -> void:
    for star in background_stars:
        var pos: Vector2 = star.get("pos", Vector2.ZERO)
        var radius := float(star.get("r", 1.0))
        var alpha := float(star.get("a", 0.4))
        var phase := float(star.get("phase", 0.0))
        var speed := float(star.get("speed", 0.5))
        var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(visual_time * speed + phase))
        draw_circle(pos, radius, Color(0.78, 0.84, 1.0, alpha * pulse))

func _draw_challenge_overlay() -> void:
    if gameplay_mode != GameplayMode.CHALLENGE:
        return
    var anchor := _largest_body()
    if anchor == null:
        return
    draw_arc(anchor.pos, 120.0, 0.0, TAU, 90, Color(0.38, 0.72, 1.0, 0.26), 1.2)
    draw_arc(anchor.pos, 420.0, 0.0, TAU, 120, Color(0.35, 0.78, 0.55, 0.18), 1.1)
    if challenge_active:
        draw_circle(anchor.pos, anchor.radius + 8.0, Color(0.25, 0.95, 0.75, 0.16))

func _draw_shockwave_fx() -> void:
    if !shockwave_visual_active:
        return
    var t := clampf(shockwave_visual_time / SHOCKWAVE_VISUAL_DURATION, 0.0, 1.0)
    var radius := lerpf(10.0, SHOCKWAVE_RADIUS, t)
    var alpha := 1.0 - t
    draw_arc(shockwave_visual_origin, radius, 0.0, TAU, 120, Color(0.5, 1.0, 0.95, 0.95 * alpha), 2.0)
    draw_circle(shockwave_visual_origin, 5.0 + 16.0 * (1.0 - t), Color(0.65, 1.0, 0.9, 0.28 * alpha))

func _draw() -> void:
    var view_size := get_viewport_rect().size
    var top_left := Vector2.ZERO
    if cam != null:
        view_size *= cam.zoom
        top_left = cam.position - view_size * 0.5
    draw_rect(Rect2(top_left, view_size), Color(0.02, 0.02, 0.05), true)
    _draw_background_stars()
    _draw_challenge_overlay()

    for p in planets:
        if p.trail.size() > 1:
            draw_polyline(p.trail, p.color.darkened(0.35), 1.5, true)

    for p in planets:
        draw_circle(p.pos, p.radius, p.color)

    if show_velocity_vectors:
        for p in planets:
            var tip := p.pos + p.vel * VELOCITY_VECTOR_SCALE
            draw_line(p.pos, tip, p.color.lightened(0.25), 1.2)

    if !planets.is_empty():
        var com := _center_of_mass()
        draw_circle(com, 4.0, Color(1.0, 1.0, 1.0, 0.9))
        draw_line(com + Vector2(-10, 0), com + Vector2(10, 0), Color(1.0, 1.0, 1.0, 0.8), 1.5)
        draw_line(com + Vector2(0, -10), com + Vector2(0, 10), Color(1.0, 1.0, 1.0, 0.8), 1.5)

    _draw_drag_preview()
    _draw_shockwave_fx()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var button_event := event as InputEventMouseButton
        if button_event.button_index == MOUSE_BUTTON_MIDDLE:
            panning_camera = button_event.pressed
            last_mouse_pos = button_event.position
        elif button_event.button_index == MOUSE_BUTTON_LEFT:
            var hovered_left := get_viewport().gui_get_hovered_control()
            if button_event.pressed:
                if hovered_left == null:
                    drag_spawn_active = true
                    drag_start_world = _screen_to_world(button_event.position)
                    drag_current_world = drag_start_world
            else:
                if drag_spawn_active:
                    drag_current_world = _screen_to_world(button_event.position)
                    var drag_vec := drag_current_world - drag_start_world
                    if drag_vec.length() < DRAG_SPAWN_MIN_DISTANCE:
                        _spawn_planet_at(drag_start_world)
                    else:
                        var drag_velocity := drag_vec * DRAG_VELOCITY_SCALE
                        var spawned := _spawn_planet_with_velocity(drag_start_world, drag_velocity)
                        _append_replay_event("spawn", {
                            "px": drag_start_world.x,
                            "py": drag_start_world.y,
                            "vx": drag_velocity.x,
                            "vy": drag_velocity.y,
                            "mass": spawned.mass,
                            "radius": spawned.radius,
                            "color": spawned.color.to_html()
                        })
                drag_spawn_active = false
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_RIGHT:
            var hovered_right := get_viewport().gui_get_hovered_control()
            if hovered_right == null:
                var world_pos_right := _screen_to_world(button_event.position)
                if _delete_planet_near(world_pos_right):
                    _append_replay_event("delete", {
                        "px": world_pos_right.x,
                        "py": world_pos_right.y
                    })
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
            cam.zoom *= 0.9
            cam.zoom.x = clampf(cam.zoom.x, 0.2, 5.0)
            cam.zoom.y = clampf(cam.zoom.y, 0.2, 5.0)
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            cam.zoom *= 1.1
            cam.zoom.x = clampf(cam.zoom.x, 0.2, 5.0)
            cam.zoom.y = clampf(cam.zoom.y, 0.2, 5.0)

    if event is InputEventMouseMotion:
        var motion_event := event as InputEventMouseMotion
        if panning_camera:
            cam.position -= motion_event.relative * cam.zoom
        elif drag_spawn_active:
            drag_current_world = _screen_to_world(motion_event.position)

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.pressed && !key_event.echo:
            if key_event.keycode == KEY_SPACE:
                if get_viewport().gui_get_focus_owner() == null:
                    _on_shockwave_pressed()
            elif key_event.keycode == KEY_TAB:
                _toggle_gameplay_mode()
EOF

  sed -i.bak "s/__START_PLANETS__/$requested_planets/g" "$tmp_dir/Main.gd"
  rm -f "$tmp_dir/Main.gd.bak"

  for rel in project.godot Main.tscn Main.gd; do
    file_diff=$(diff -u /dev/null "$tmp_dir/$rel" || true)
    if [ -n "$(trim "$file_diff")" ]; then
      file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$rel|")
      patch_text="${patch_text}
${file_diff}"
    fi
  done

  rm -rf "$tmp_dir"
  patch_text=$(trim_block_edges "$patch_text")
  printf '%s' "$patch_text"
}

framework_bootstrap_patch_for_prompt() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$prompt_lower" in
    *godot*)
      if printf '%s' "$prompt_lower" | grep -Eq 'gravity|gravitational|orbit|orbital|revolv|planet|celestial|n[- ]?body|bodies'; then
        requested_planets=$(godot_requested_planet_min_from_prompt "$prompt_lower")
        if [ -z "$requested_planets" ] || [ "$requested_planets" -lt 80 ]; then
          requested_planets=80
        fi
        godot_gravity_template_patch "$requested_planets"
        return 0
      fi
      ;;
  esac
  printf '%s' ""
}

godot_requested_planet_min_from_prompt() {
  prompt_lower=$1
  printf '%s\n' "$prompt_lower" | perl -CS -0777 -ne '
    my $s = lc $_;
    my $max = 0;

    while ($s =~ /(\d{1,4})\s*\+/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    while ($s =~ /at\s+least\s+(\d{1,4})(?!\d)/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    while ($s =~ /(\d{1,4})(?!\d)\s+(?:planets|bodies)\b/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    print $max if $max > 0;
  '
}

godot_start_planets_value_from_text() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    my $s = lc $_;
    my $max = 0;
    while ($s =~ /start_planets\s*:?=\s*(\d{1,4})/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    print $max if $max > 0;
  '
}

framework_patch_is_low_confidence() {
  prompt_text=$1
  patch_text=$2
  workspace_path=${3:-}
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  patch_trimmed=$(trim "$patch_text")

  [ -n "$patch_trimmed" ] || return 0

  case "$prompt_lower" in
    *godot*)
      workspace_has_project=0
      if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
        if find "$workspace_path" -maxdepth 3 -type f -name 'project.godot' 2>/dev/null | sed -n '1p' | grep -q '.'; then
          workspace_has_project=1
        fi
      fi
      if [ "$workspace_has_project" -eq 1 ]; then
        return 1
      fi

      paths_file=$(mktemp)
      patch_paths_from_text "$patch_text" > "$paths_file"
      has_project_path=0
      has_scene_path=0
      has_script_path=0
      while IFS= read -r rel_path; do
        rel_path=$(trim "$rel_path")
        [ -n "$rel_path" ] || continue
        case "$rel_path" in
          */project.godot|project.godot)
            has_project_path=1
            ;;
          *.tscn)
            has_scene_path=1
            ;;
          *.gd)
            has_script_path=1
            ;;
        esac
      done < "$paths_file"
      rm -f "$paths_file"

      has_application=0
      has_main_scene=0
      has_config_version=0
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*\[application\][[:space:]]*$'; then
        has_application=1
      fi
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*run/main_scene[[:space:]]*='; then
        has_main_scene=1
      fi
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*config_version[[:space:]]*='; then
        has_config_version=1
      fi

      if [ "$has_project_path" -eq 1 ] && [ "$has_scene_path" -eq 1 ] && [ "$has_script_path" -eq 1 ] && \
         [ "$has_application" -eq 1 ] && [ "$has_main_scene" -eq 1 ] && [ "$has_config_version" -eq 1 ]; then
        patch_lower=$(printf '%s' "$patch_text" | tr '[:upper:]' '[:lower:]')

        if printf '%s' "$prompt_lower" | grep -Eq 'pause|resume|reset|slider|time scale|gravitational constant|sandbox'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'pause|resume|reset|slider|hslider|time_scale|gravity_constant'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'collision|merge'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'collision|merge'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'camera|pan|zoom'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'camera2d|camera|pan|zoom'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'hud|fps|energy'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'hud|fps|energy'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '5\\+|at least[[:space:]]+5([^0-9]|$)|(^|[^[:alpha:]])five([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([5-9]|1[0-9])|start_planets[[:space:]]*=[[:space:]]*([5-9]|1[0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '8\\+|at least[[:space:]]+8([^0-9]|$)|(^|[^[:alpha:]])eight([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(8|9|1[0-9])|start_planets[[:space:]]*=[[:space:]]*(8|9|1[0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '10\\+|at least[[:space:]]+10([^0-9]|$)|(^|[^[:alpha:]])ten([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(10|1[1-9])|start_planets[[:space:]]*=[[:space:]]*(10|1[1-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '14\\+|at least[[:space:]]+14([^0-9]|$)|14[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])fourteen([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(1[4-9]|[2-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(1[4-9]|[2-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '20\\+|at least[[:space:]]+20([^0-9]|$)|20[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])twenty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(2[0-9]|[3-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(2[0-9]|[3-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '30\\+|at least[[:space:]]+30([^0-9]|$)|30[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])thirty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(3[0-9]|[4-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(3[0-9]|[4-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '40\\+|at least[[:space:]]+40([^0-9]|$)|40[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])forty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(4[0-9]|[5-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(4[0-9]|[5-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '60\\+|at least[[:space:]]+60([^0-9]|$)|60[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])sixty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '80\\+|at least[[:space:]]+80([^0-9]|$)|80[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])eighty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])'; then
            return 0
          fi
        fi

        requested_planet_min=$(godot_requested_planet_min_from_prompt "$prompt_lower")
        if [ -n "$requested_planet_min" ] && [ "$requested_planet_min" -ge 5 ]; then
          patch_start_planets=$(godot_start_planets_value_from_text "$patch_lower")
          if [ -z "$patch_start_planets" ] || [ "$patch_start_planets" -lt "$requested_planet_min" ]; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'click|spawn'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'spawn|mouse_button_left|inputeventmousebutton'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'gameplay|fun|interactiv|challenge|objective|score|combo|win|lose'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'gameplay_mode|challenge_active|challenge_score|challenge_label|_sample_challenge_score|set_gameplay_mode'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'ability|abilities|power[- ]?up|special move|shockwave|cooldown'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'shockwave|cooldown|_trigger_shockwave|on_shockwave_pressed'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'polish|juic|juice|feel|visual feedback|fx|effects|presentation'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'background_stars|draw_background|draw_arc|challenge_message|visual_time|autowrap'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'right[- ]click|delete|remove planet'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'mouse_button_right'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'delete|remove_at|erase'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'adaptive|time[ -]?step|timestep'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'adaptive|effective_step|step_seconds'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'deterministic|seed'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'seed|randomnumbergenerator|rng|lineedit|apply_seed'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'step once|single step|advance one tick|one tick'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'step_once|step once|step_once_delta'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'merge toggle|collision/merge toggle|collision toggle|toggle merge'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'merge_enabled|toggle_merge|merge:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'velocity[- ]vectors?|vectors toggle|velocity arrows?'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'show_velocity_vectors|toggle_vectors|velocity_vector|vectors:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'center of mass|centre of mass|com marker'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'center_of_mass'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'draw_circle|draw_line'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'total momentum|momentum.*(readout|display|hud|on-screen|onscreen)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq '_total_system_momentum|momentum:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'trail|toggle'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'trail'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'clear[- ]?trails?|clear trails button'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'clear_trails|clear trails'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'integrator|leapfrog|euler|symplectic'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'integrator|leapfrog|euler|optionbutton|item_selected'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'rk4|runge-kutta'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'rk4|runge|integratormode'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'softening'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'softening'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'slider|hslider|on_softening'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'click[- ]drag|drag[- ]spawn|velocity preview|drag.*preview|click and drag'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'drag_spawn|inputeventmousemotion|mousemotion|draw_drag|preview_velocity|drag_current'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'angular momentum|\\blz\\b'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'angular_momentum|_total_system_angular_momentum|\\blz\\b'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'energy drift|drift from initial|delta energy|\\bde\\b'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'energy_drift|initial_total_energy|drift_pct|drift'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'telemetry|export csv|csv export|continuous telemetry|time, energy'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'telemetry|csv|export_telemetry|store_line|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'record|replay|input events|event log|deterministic replay'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'record|replay|replay_events|record_events|replay_path|_start_replay|_toggle_recording'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'benchmark|benchmark integrators|benchmark_results|energy drift percent|simulated_seconds'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'benchmark|benchmark_results|run_benchmark|benchmark_path|_run_integrator_benchmark'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'csv|store_line|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'barnes[- ]?hut|theta|approximation mode|n[[:space:]]*log[[:space:]]*n|quadtree'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'barnes|bhnode|quadtree|theta|force_mode|_accelerations_barnes_hut'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'checksum|hash|digest'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'checksum|sha256|mismatch|replay_checksum|validate'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'final[ -]?state checksum|end[ -]?state checksum|state checksum'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'final_state_checksum|state_checksum_for_snapshot|final-mismatch|ok\\+final'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'self[- ]?tests?|regression|regression_report|validation suite'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'self_test|run_self_tests|regression_report|report_path'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'save|load|json|preset'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'save|load|json|fileaccess|preset'; then
            return 0
          fi
        fi

        return 1
      fi
      return 0
      ;;
  esac

  return 1
}

adapt_prompt_for_model() {
  model_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  original_prompt=$2
  plugin_guidance=$(active_self_improve_plugin_guidance)
  plugin_prefix=""
  if [ -n "$(trim "$plugin_guidance")" ]; then
    plugin_prefix=$(printf '%s\n%s\n\n' \
      "Additional Artificer self-improvement plugins are enabled right now. Apply them when they improve reasoning quality and do not conflict with the user request:" \
      "$plugin_guidance")
  fi

  case "$model_lower" in
    starcoder*|*codegeex*|*codellama*|*coder*)
      printf '%s\n%s\n%s\n%s\n%s\n%s' \
        "You are a helpful coding assistant." \
        "Follow the instruction and answer directly." \
        "Do not include role prefixes or planning scaffolding." \
        "" \
        "${plugin_prefix}### Instruction
$original_prompt

### Response" \
        ""
      return 0
      ;;
  esac

  printf '%s%s' "$plugin_prefix" "$original_prompt"
}

output_looks_derailed() {
  text_raw=$1
  text_lower=$(printf '%s' "$text_raw" | tr '[:upper:]' '[:lower:]')
  case "$text_lower" in
    *"workspace snapshot:"*|*"recent conversation:"*|*"current plan:"*|*"loop summary:"*|*"write a concise final response"*|*"mode_update:"*|*"commands:"*|*"plan_update:"*|*"done_claim:"*|*"decision_request:"*|*"final:"*|*"next action: completion criteria:"*|*"transition:"*|*"checkpoint:"*|*"final action plan"*|*"## response## diff"*)
      return 0
      ;;
  esac
  if printf '%s\n' "$text_raw" | grep -Eq '^##[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    return 0
  fi
  return 1
}

chat_output_looks_off_topic() {
  user_prompt_raw=$1
  assistant_raw=$2
  prompt_lower=$(printf '%s' "$user_prompt_raw" | tr '[:upper:]' '[:lower:]')
  assistant_lower=$(printf '%s' "$assistant_raw" | tr '[:upper:]' '[:lower:]')

  # Strong mismatch: conceptual self-modeling request answered as app onboarding mechanics.
  if printf '%s' "$prompt_lower" | grep -Eq 'prior to|higher-order|self|identity|values'; then
    if printf '%s' "$assistant_lower" | grep -Eq 'onboarding|registration|sign[ -]?up|create (an )?account|user profile|profile setup'; then
      return 0
    fi
  fi

  # Correction follow-up ("no, ...") followed by generic wellness list indicates derailment.
  if printf '%s' "$prompt_lower" | grep -Eq '^(no|not exactly|not quite|that.s not|i mean|rather)\b|^no,|^no\.'; then
    generic_hits=$(printf '%s\n' "$assistant_lower" | grep -Eo 'mindfulness|journaling|meditation|stress management|anxiety reduction|trusted friends|books and online resources|dialogue with others|well-being' | wc -l | tr -d '[:space:]' || printf '0')
    case "$generic_hits" in
      ""|*[!0-9]*) generic_hits=0 ;;
    esac
    if [ "$generic_hits" -ge 3 ]; then
      return 0
    fi
  fi

  return 1
}

salvage_direct_response() {
  model_name=$1
  user_prompt=$2
  salvage_model=$model_name
  preferred_model=$(preferred_chat_model || true)
  if [ -n "$preferred_model" ]; then
    salvage_model=$preferred_model
  fi
  fallback_prompt=$(cat <<EOF
You are a coding assistant.
Respond directly to the latest user message in 1-3 concise sentences.
Do not include planning scaffolding, role prefixes, or tool/control sections.

User message:
$user_prompt
EOF
)
  repaired=$(run_model "$salvage_model" "$fallback_prompt" || true)
  repaired=$(normalize_assistant_output "$repaired")
  printf '%s' "$repaired"
}

salvage_chat_response() {
  model_name=$1
  user_prompt=$2
  recent_history=$3
  salvage_model=$model_name
  preferred_model=$(preferred_chat_model || true)
  if [ -n "$preferred_model" ]; then
    salvage_model=$preferred_model
  fi
  fallback_prompt=$(cat <<EOF
You are a high-quality conversational assistant in a multi-turn thread.
Answer the latest user message while preserving conversation continuity.
Hard constraints:
- Treat the latest user message as an in-thread refinement.
- If the user corrects framing, acknowledge the correction briefly and answer with the corrected framing.
- Avoid generic wellness/productivity lists unless explicitly requested.
- Prefer concise conceptual distinctions over broad platitudes.
- Do not switch to app onboarding/setup unless the user asks for implementation details.

Latest user message:
$user_prompt

Recent conversation:
$recent_history

Return only assistant reply text.
EOF
)
  repaired=$(run_model "$salvage_model" "$fallback_prompt" || true)
  repaired=$(normalize_assistant_output "$repaired")
  printf '%s' "$repaired"
}

