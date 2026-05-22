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
  printf '%s' "$1" | awk '
    {
      lines[NR] = $0
    }
    END {
      if (NR == 0) {
        exit 0
      }
      first = 1
      while (first <= NR && lines[first] ~ /^[[:space:]]*$/) {
        first += 1
      }
      if (first > NR) {
        exit 0
      }
      last = NR
      while (last >= first && lines[last] ~ /^[[:space:]]*$/) {
        last -= 1
      }
      for (i = first; i <= last; i += 1) {
        line = lines[i]
        if (i == first) {
          sub(/^[[:space:]]+/, "", line)
        }
        if (i == last) {
          sub(/[[:space:]]+$/, "", line)
        }
        printf "%s", line
        if (i < last) {
          printf "\n"
        }
      }
    }
  '
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
