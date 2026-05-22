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
      .git/*)
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
