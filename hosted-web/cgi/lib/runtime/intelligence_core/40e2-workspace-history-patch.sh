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

  replacement=$(resolve_relative_path_case_insensitive "$workspace_root" "$first_arg" || true)
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
