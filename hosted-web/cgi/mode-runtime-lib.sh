#!/bin/sh

mr_runtime_root() {
  printf '%s' "$mode_runtime_root"
}

mr_modes_dir() {
  printf '%s/modes' "$(mr_runtime_root)"
}

mr_skills_dir() {
  printf '%s/skills' "$(mr_runtime_root)"
}

mr_bus_dir() {
  printf '%s/invocation-bus' "$(mr_runtime_root)"
}

mr_dashboard_dir() {
  printf '%s/dashboard' "$(mr_runtime_root)"
}

mr_scheduler_dir() {
  printf '%s/scheduler' "$(mr_runtime_root)"
}

mr_telemetry_dir() {
  printf '%s/telemetry' "$(mr_runtime_root)"
}

mr_interrupts_dir() {
  printf '%s/interrupts' "$(mr_runtime_root)"
}

mr_failure_taxonomy_dir() {
  printf '%s/failure-taxonomy' "$(mr_runtime_root)"
}

mr_failure_taxonomy_events_file() {
  printf '%s/events.tsv' "$(mr_failure_taxonomy_dir)"
}

mr_improvement_proposals_dir() {
  printf '%s/improvement-proposals' "$(mr_runtime_root)"
}

mr_improvement_proposal_dir_for() {
  proposal_id=$1
  printf '%s/%s' "$(mr_improvement_proposals_dir)" "$proposal_id"
}

mr_improvement_proposal_meta_file() {
  proposal_id=$1
  printf '%s/meta.env' "$(mr_improvement_proposal_dir_for "$proposal_id")"
}

mr_improvement_proposal_body_file() {
  proposal_id=$1
  printf '%s/proposal.md' "$(mr_improvement_proposal_dir_for "$proposal_id")"
}

mr_controller_variants_root() {
  printf '%s/controller-variants' "$(mr_runtime_root)"
}

mr_controller_variants_dir() {
  printf '%s/variants' "$(mr_controller_variants_root)"
}

mr_controller_variants_state_file() {
  printf '%s/state.env' "$(mr_controller_variants_root)"
}

mr_controller_variants_telemetry_file() {
  printf '%s/telemetry.tsv' "$(mr_controller_variants_root)"
}

mr_controller_variant_dir_for() {
  variant_id=$1
  printf '%s/%s' "$(mr_controller_variants_dir)" "$variant_id"
}

mr_controller_variant_meta_file() {
  variant_id=$1
  printf '%s/meta.env' "$(mr_controller_variant_dir_for "$variant_id")"
}

mr_controller_variant_notes_file() {
  variant_id=$1
  printf '%s/guidance.md' "$(mr_controller_variant_dir_for "$variant_id")"
}

mr_quality_scorecard_dir() {
  printf '%s/quality-scorecard' "$(mr_runtime_root)"
}

mr_quality_scorecard_entries_file() {
  printf '%s/entries.tsv' "$(mr_quality_scorecard_dir)"
}

mr_quality_scorecard_markdown_file() {
  printf '%s/scorecard.md' "$(mr_quality_scorecard_dir)"
}

mr_quality_scorecard_regression_cooldowns_file() {
  printf '%s/regression-proposal-cooldowns.tsv' "$(mr_quality_scorecard_dir)"
}

mr_scheduler_state_file() {
  printf '%s/state.env' "$(mr_scheduler_dir)"
}

mr_now_epoch() {
  date +%s 2>/dev/null || printf '0'
}

mr_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date
}

mr_sanitize_inline() {
  printf '%s' "$1" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//'
}

mr_bool_norm() {
  value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    1|true|yes|on|enabled)
      printf '%s' "1"
      ;;
    *)
      printf '%s' "0"
      ;;
  esac
}

mr_positive_int_or() {
  value=$(trim "$1")
  fallback=$2
  case "$value" in
    ""|*[!0-9]*)
      printf '%s' "$fallback"
      ;;
    *)
      if [ "$value" -le 0 ]; then
        printf '%s' "$fallback"
      else
        printf '%s' "$value"
      fi
      ;;
  esac
}

mr_nonnegative_int_or() {
  value=$(trim "$1")
  fallback=$2
  case "$value" in
    ""|*[!0-9]*)
      printf '%s' "$fallback"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

mr_mode_dir_for() {
  mode_id=$1
  printf '%s/%s' "$(mr_modes_dir)" "$mode_id"
}

mr_skill_dir_for() {
  skill_id=$1
  printf '%s/%s' "$(mr_skills_dir)" "$skill_id"
}

mr_mode_manifest_file() {
  mode_id=$1
  printf '%s/manifest.env' "$(mr_mode_dir_for "$mode_id")"
}

mr_mode_state_file() {
  mode_id=$1
  printf '%s/state.env' "$(mr_mode_dir_for "$mode_id")"
}

mr_mode_policy_file() {
  mode_id=$1
  printf '%s/policy.md' "$(mr_mode_dir_for "$mode_id")"
}

mr_mode_memory_dir() {
  mode_id=$1
  printf '%s/memory' "$(mr_mode_dir_for "$mode_id")"
}

mr_mode_goal_file() {
  mode_id=$1
  printf '%s/goal_state.md' "$(mr_mode_memory_dir "$mode_id")"
}

mr_mode_long_horizon_file() {
  mode_id=$1
  printf '%s/long_horizon.md' "$(mr_mode_memory_dir "$mode_id")"
}

mr_mode_log_file() {
  mode_id=$1
  printf '%s/mode.log.md' "$(mr_mode_memory_dir "$mode_id")"
}

mr_mode_subscriptions_file() {
  mode_id=$1
  printf '%s/subscriptions.list' "$(mr_mode_memory_dir "$mode_id")"
}

mr_mode_last_telemetry_file() {
  mode_id=$1
  printf '%s/%s.last.log' "$(mr_telemetry_dir)" "$mode_id"
}

mr_skill_meta_file() {
  skill_id=$1
  printf '%s/skill.meta' "$(mr_skill_dir_for "$skill_id")"
}

mr_mode_ledgers_file() {
  mode_id=$1
  printf '%s/governance.log' "$(mr_mode_dir_for "$mode_id")"
}

mr_mode_event_queue_file() {
  mode_id=$1
  printf '%s/%s.events.log' "$(mr_bus_dir)" "$mode_id"
}

mr_directives_dir() {
  printf '%s/directives' "$(mr_bus_dir)"
}

mr_cooperation_log_file() {
  printf '%s/cooperation.log' "$(mr_bus_dir)"
}

mr_mode_directive_inbox_file() {
  mode_id=$1
  printf '%s/%s.inbox.log' "$(mr_directives_dir)" "$mode_id"
}

mr_mode_directive_cursor_file() {
  mode_id=$1
  printf '%s/directive.cursor' "$(mr_mode_dir_for "$mode_id")"
}

mr_env_get() {
  env_file=$1
  key=$2
  fallback=${3:-}
  if [ ! -f "$env_file" ]; then
    printf '%s' "$fallback"
    return 0
  fi
  value=$(sed -n "s/^${key}=//p" "$env_file" | sed -n '1p')
  if [ -z "$(trim "$value")" ]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$value"
  fi
}

mr_env_set() {
  env_file=$1
  key=$2
  value=$(mr_sanitize_inline "$3")
  tmp_file=$(mktemp)
  found=0
  if [ -f "$env_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "${key}="*)
          printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
          found=1
          ;;
        *)
          printf '%s\n' "$line" >> "$tmp_file"
          ;;
      esac
    done < "$env_file"
  fi
  if [ "$found" -ne 1 ]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  fi
  mv "$tmp_file" "$env_file"
}

mr_csv_normalize() {
  csv_raw=$1
  printf '%s' "$csv_raw" | tr ';' ',' | tr '\n\r' ',' | awk -F',' '
    {
      out_count = 0
      for (i = 1; i <= NF; i++) {
        item = $i
        gsub(/^[[:space:]]+/, "", item)
        gsub(/[[:space:]]+$/, "", item)
        if (item == "") {
          continue
        }
        key = tolower(item)
        if (seen[key] == 1) {
          continue
        }
        seen[key] = 1
        out[++out_count] = item
      }
    }
    END {
      for (i = 1; i <= out_count; i++) {
        if (i > 1) {
          printf ","
        }
        printf "%s", out[i]
      }
    }
  '
}

mr_csv_to_json_array() {
  csv_raw=$1
  csv_norm=$(mr_csv_normalize "$csv_raw")
  printf '['
  first=1
  old_ifs=$IFS
  IFS=','
  for entry in $csv_norm; do
    clean=$(trim "$entry")
    [ -n "$clean" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$clean")"
  done
  IFS=$old_ifs
  printf ']'
}

mr_new_id() {
  if command -v new_id >/dev/null 2>&1; then
    new_id
    return 0
  fi
  now=$(mr_now_epoch)
  rand=$(awk 'BEGIN { srand(); printf "%06d", rand()*1000000 }')
  printf '%s-%s-%s' "$now" "$$" "$rand"
}

mr_failure_taxonomy_category_for_entry() {
  action_text=$(mr_sanitize_inline "$1")
  error_text=$(mr_sanitize_inline "$2")
  hypothesis_text=$(mr_sanitize_inline "$3")
  next_text=$(mr_sanitize_inline "$4")
  mode_text=$(mr_sanitize_inline "${5:-}")
  combined=$(printf '%s %s %s %s %s' "$action_text" "$error_text" "$hypothesis_text" "$next_text" "$mode_text" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined" | grep -Eq 'safety policy|blocked by safety|approval required|approval_required|permission denied'; then
    printf '%s' "command-policy-block"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'run-time budget|timed out|timeout|stale timeout|exceeded'; then
    printf '%s' "timeout-budget"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'stagnation|repeated transition signature|loop repeating|no forward progress|anti-repeat guardrail'; then
    printf '%s' "controller-stagnation"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'decision required|decision-request|decision request|required-input-missing|external-action-gate|destructive-action-gate'; then
    printf '%s' "decision-gate"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'controller-format|command-parse|parse|schema|malformed|invalid format'; then
    printf '%s' "parser-contract"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'verify-|verification|regression|test failed|assert'; then
    printf '%s' "verification-regression"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'implement-iteration|patch|promotion|scratch|write failed|apply'; then
    printf '%s' "implementation-failure"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'not found|no such file|missing|unavailable'; then
    printf '%s' "missing-artifact"
    return 0
  fi
  if printf '%s' "$combined" | grep -Eq 'network|dns|http|fetch|ssl|connection'; then
    printf '%s' "external-dependency"
    return 0
  fi
  printf '%s' "unknown"
}

mr_failure_taxonomy_category_label() {
  category_id=$1
  case "$category_id" in
    command-policy-block) printf '%s' "Command policy / approval gate" ;;
    timeout-budget) printf '%s' "Run timeout / budget exhaustion" ;;
    controller-stagnation) printf '%s' "Controller loop stagnation" ;;
    decision-gate) printf '%s' "Decision surfacing gate" ;;
    parser-contract) printf '%s' "Controller parse/contract failure" ;;
    verification-regression) printf '%s' "Verification regression" ;;
    implementation-failure) printf '%s' "Implementation failure" ;;
    missing-artifact) printf '%s' "Missing artifact or context" ;;
    external-dependency) printf '%s' "External dependency failure" ;;
    *) printf '%s' "Uncategorized failure" ;;
  esac
}

mr_failure_taxonomy_surface_for_category() {
  category_id=$1
  case "$category_id" in
    command-policy-block) printf '%s' "policy" ;;
    timeout-budget) printf '%s' "runtime" ;;
    controller-stagnation) printf '%s' "reasoning" ;;
    decision-gate) printf '%s' "governance" ;;
    parser-contract) printf '%s' "reasoning" ;;
    verification-regression) printf '%s' "verification" ;;
    implementation-failure) printf '%s' "implementation" ;;
    missing-artifact) printf '%s' "context" ;;
    external-dependency) printf '%s' "environment" ;;
    *) printf '%s' "unknown" ;;
  esac
}

mr_failure_taxonomy_severity_for_category() {
  category_id=$1
  case "$category_id" in
    timeout-budget|verification-regression|implementation-failure|controller-stagnation)
      printf '%s' "high"
      ;;
    decision-gate|parser-contract|missing-artifact|external-dependency)
      printf '%s' "medium"
      ;;
    command-policy-block)
      printf '%s' "low"
      ;;
    *)
      printf '%s' "low"
      ;;
  esac
}

mr_failure_taxonomy_record() {
  action_text=$(mr_sanitize_inline "$1")
  error_text=$(mr_sanitize_inline "$2")
  hypothesis_text=$(mr_sanitize_inline "$3")
  next_text=$(mr_sanitize_inline "$4")
  mode_text=$(mr_sanitize_inline "${5:-unknown}")

  category_id=$(mr_failure_taxonomy_category_for_entry "$action_text" "$error_text" "$hypothesis_text" "$next_text" "$mode_text")
  surface_value=$(mr_failure_taxonomy_surface_for_category "$category_id")
  severity_value=$(mr_failure_taxonomy_severity_for_category "$category_id")

  mkdir -p "$(mr_failure_taxonomy_dir)"
  events_file=$(mr_failure_taxonomy_events_file)
  [ -f "$events_file" ] || : > "$events_file"

  now_epoch=$(mr_now_epoch)
  now_iso=$(mr_now_iso)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" \
    "$now_iso" \
    "$category_id" \
    "$surface_value" \
    "$severity_value" \
    "$mode_text" \
    "$action_text" \
    "$error_text" \
    "$hypothesis_text" \
    "$next_text" >> "$events_file"
}

mr_failure_taxonomy_categories_json() {
  max_categories=$1
  case "$max_categories" in
    ""|*[!0-9]*) max_categories=12 ;;
  esac
  if [ "$max_categories" -lt 1 ]; then
    max_categories=1
  fi

  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '[]'
    return 0
  fi

  tab_char=$(printf '\t')
  stats_file=$(mktemp)
  awk -F'\t' '
    NF >= 6 {
      category = $3
      if (category == "") {
        category = "unknown"
      }
      counts[category] += 1
      last_seen[category] = $2
      surface[category] = $4
      severity[category] = $5
    }
    END {
      for (category in counts) {
        printf "%s\t%s\t%s\t%s\t%s\n", counts[category], category, last_seen[category], surface[category], severity[category]
      }
    }
  ' "$events_file" | sort -t "$tab_char" -k1,1nr -k2,2 > "$stats_file"

  printf '['
  first=1
  shown=0
  while IFS="$tab_char" read -r count category_id last_seen surface_value severity_value || [ -n "$category_id" ]; do
    [ -n "$category_id" ] || continue
    shown=$((shown + 1))
    if [ "$shown" -gt "$max_categories" ]; then
      break
    fi
    category_label=$(mr_failure_taxonomy_category_label "$category_id")
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"id":"%s","label":"%s","count":"%s","last_seen":"%s","surface":"%s","severity":"%s"}' \
      "$(json_escape "$category_id")" \
      "$(json_escape "$category_label")" \
      "$(json_escape "$count")" \
      "$(json_escape "$last_seen")" \
      "$(json_escape "$surface_value")" \
      "$(json_escape "$severity_value")"
  done < "$stats_file"
  printf ']'
  rm -f "$stats_file"
}

mr_failure_taxonomy_recent_json() {
  max_rows=$1
  case "$max_rows" in
    ""|*[!0-9]*) max_rows=16 ;;
  esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '[]'
    return 0
  fi

  recent_file=$(mktemp)
  tail -n "$max_rows" "$events_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  rows_json=$(mr_failure_taxonomy_rows_file_to_json "$recent_file")
  rm -f "$recent_file"
  printf '%s' "$rows_json"
}

mr_failure_taxonomy_rows_file_to_json() {
  rows_file=$1
  if [ ! -s "$rows_file" ]; then
    printf '[]'
    return 0
  fi
  tab_char=$(printf '\t')

  printf '['
  first=1
  while IFS="$tab_char" read -r epoch_value iso_value category_id surface_value severity_value mode_value action_text error_text hypothesis_text next_text || [ -n "$iso_value$category_id$action_text$error_text" ]; do
    [ -n "$category_id$action_text$error_text$next_text" ] || continue
    category_label=$(mr_failure_taxonomy_category_label "$category_id")
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"timestamp":"%s","epoch":"%s","category":"%s","category_label":"%s","surface":"%s","severity":"%s","mode":"%s","action":"%s","error":"%s","hypothesis":"%s","next_attempt":"%s"}' \
      "$(json_escape "$iso_value")" \
      "$(json_escape "$epoch_value")" \
      "$(json_escape "$category_id")" \
      "$(json_escape "$category_label")" \
      "$(json_escape "$surface_value")" \
      "$(json_escape "$severity_value")" \
      "$(json_escape "$mode_value")" \
      "$(json_escape "$action_text")" \
      "$(json_escape "$error_text")" \
      "$(json_escape "$hypothesis_text")" \
      "$(json_escape "$next_text")"
  done < "$rows_file"
  printf ']'
}

mr_failure_taxonomy_state_json() {
  events_file=$(mr_failure_taxonomy_events_file)
  events_path="$events_file"
  total_entries=0
  last_recorded_at=""
  if [ -f "$events_file" ]; then
    total_entries=$(wc -l < "$events_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
    case "$total_entries" in
      ""|*[!0-9]*) total_entries=0 ;;
    esac
    if [ "$total_entries" -gt 0 ]; then
      tab_char=$(printf '\t')
      last_recorded_at=$(tail -n 1 "$events_file" 2>/dev/null | awk -F"$tab_char" '{ print $2 }')
    fi
  fi

  printf '{"total":"%s","last_recorded_at":"%s","events_path":"%s","categories":%s,"recent":%s}' \
    "$(json_escape "$total_entries")" \
    "$(json_escape "$last_recorded_at")" \
    "$(json_escape "$events_path")" \
    "$(mr_failure_taxonomy_categories_json "12")" \
    "$(mr_failure_taxonomy_recent_json "16")"
}

mr_failure_taxonomy_query_json() {
  category_filter=$(trim "${1:-}")
  severity_filter=$(trim "${2:-}")
  surface_filter=$(trim "${3:-}")
  mode_filter=$(trim "${4:-}")
  since_epoch_raw=$(trim "${5:-}")
  limit_raw=$(trim "${6:-50}")

  category_filter=$(printf '%s' "$category_filter" | tr '[:upper:]' '[:lower:]')
  severity_filter=$(printf '%s' "$severity_filter" | tr '[:upper:]' '[:lower:]')
  surface_filter=$(printf '%s' "$surface_filter" | tr '[:upper:]' '[:lower:]')
  mode_filter=$(printf '%s' "$mode_filter" | tr '[:upper:]' '[:lower:]')
  case "$category_filter" in
    ""|all) category_filter="" ;;
  esac
  case "$severity_filter" in
    ""|all|low|medium|high) ;;
    *) severity_filter="" ;;
  esac
  case "$surface_filter" in
    ""|all) surface_filter="" ;;
  esac
  case "$mode_filter" in
    ""|all) mode_filter="" ;;
  esac

  since_epoch=$(mr_nonnegative_int_or "$since_epoch_raw" "0")
  limit_value=$(mr_positive_int_or "$limit_raw" "50")
  if [ "$limit_value" -gt 250 ]; then
    limit_value=250
  fi

  events_file=$(mr_failure_taxonomy_events_file)
  events_path="$events_file"
  if [ ! -s "$events_file" ]; then
    printf '{"filters":{"category":"%s","severity":"%s","surface":"%s","mode":"%s","since_epoch":"%s","limit":"%s"},"events_path":"%s","matched_total":"0","returned":"0","events":[]}' \
      "$(json_escape "$category_filter")" \
      "$(json_escape "$severity_filter")" \
      "$(json_escape "$surface_filter")" \
      "$(json_escape "$mode_filter")" \
      "$(json_escape "$since_epoch")" \
      "$(json_escape "$limit_value")" \
      "$(json_escape "$events_path")"
    return 0
  fi

  tab_char=$(printf '\t')
  matched_file=$(mktemp)
  sliced_file=$(mktemp)
  ordered_file=$(mktemp)

  awk -F"$tab_char" \
    -v category_filter="$category_filter" \
    -v severity_filter="$severity_filter" \
    -v surface_filter="$surface_filter" \
    -v mode_filter="$mode_filter" \
    -v since_epoch="$since_epoch" '
    NF >= 10 {
      epoch_value = $1 + 0
      category_value = tolower($3)
      surface_value = tolower($4)
      severity_value = tolower($5)
      mode_value = tolower($6)

      if (since_epoch > 0 && epoch_value < since_epoch) {
        next
      }
      if (category_filter != "" && category_value != category_filter) {
        next
      }
      if (severity_filter != "" && severity_value != severity_filter) {
        next
      }
      if (surface_filter != "" && surface_value != surface_filter) {
        next
      }
      if (mode_filter != "" && mode_value != mode_filter) {
        next
      }
      print $0
    }
  ' "$events_file" > "$matched_file"

  matched_total=$(wc -l < "$matched_file" 2>/dev/null | tr -d '[:space:]')
  case "$matched_total" in
    ""|*[!0-9]*) matched_total=0 ;;
  esac

  if [ "$matched_total" -gt 0 ]; then
    tail -n "$limit_value" "$matched_file" > "$sliced_file" 2>/dev/null || : > "$sliced_file"
    awk '
      { rows[NR] = $0 }
      END {
        for (i = NR; i >= 1; i--) {
          print rows[i]
        }
      }
    ' "$sliced_file" > "$ordered_file"
  else
    : > "$ordered_file"
  fi

  returned_total=$(wc -l < "$ordered_file" 2>/dev/null | tr -d '[:space:]')
  case "$returned_total" in
    ""|*[!0-9]*) returned_total=0 ;;
  esac

  events_json=$(mr_failure_taxonomy_rows_file_to_json "$ordered_file")
  rm -f "$matched_file" "$sliced_file" "$ordered_file"

  printf '{"filters":{"category":"%s","severity":"%s","surface":"%s","mode":"%s","since_epoch":"%s","limit":"%s"},"events_path":"%s","matched_total":"%s","returned":"%s","events":%s}' \
    "$(json_escape "$category_filter")" \
    "$(json_escape "$severity_filter")" \
    "$(json_escape "$surface_filter")" \
    "$(json_escape "$mode_filter")" \
    "$(json_escape "$since_epoch")" \
    "$(json_escape "$limit_value")" \
    "$(json_escape "$events_path")" \
    "$(json_escape "$matched_total")" \
    "$(json_escape "$returned_total")" \
    "$events_json"
}

mr_failure_taxonomy_recent_summary_text() {
  max_rows=$1
  case "$max_rows" in ""|*[!0-9]*) max_rows=6 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '%s' "none"
    return 0
  fi

  tab_char=$(printf '\t')
  latest_row=$(tail -n 1 "$events_file" 2>/dev/null || true)
  latest_category=$(printf '%s' "$latest_row" | awk -F"$tab_char" '{ print $3 }')
  latest_severity=$(printf '%s' "$latest_row" | awk -F"$tab_char" '{ print $5 }')
  latest_mode=$(printf '%s' "$latest_row" | awk -F"$tab_char" '{ print $6 }')
  latest_category=$(trim "$latest_category")
  latest_severity=$(trim "$latest_severity")
  latest_mode=$(trim "$latest_mode")
  [ -n "$latest_category" ] || latest_category="unknown"
  [ -n "$latest_severity" ] || latest_severity="unknown"
  [ -n "$latest_mode" ] || latest_mode="unknown"
  latest_label=$(mr_failure_taxonomy_category_label "$latest_category")

  recent_file=$(mktemp)
  tail -n "$max_rows" "$events_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  top_categories=$(awk -F"$tab_char" '
    NF >= 3 {
      category = $3
      if (category == "") {
        category = "unknown"
      }
      counts[category] += 1
    }
    END {
      for (category in counts) {
        printf "%s\t%s\n", counts[category], category
      }
    }
  ' "$recent_file" | sort -t "$tab_char" -k1,1nr -k2,2 | head -n 2 | awk -F"$tab_char" '
    BEGIN { out = "" }
    NF >= 2 {
      if (out != "") {
        out = out ", "
      }
      out = out $2 "=" $1
    }
    END { printf "%s", out }
  ')
  rm -f "$recent_file"
  [ -n "$top_categories" ] || top_categories="none"

  printf '%s' "latest=${latest_label} (severity=${latest_severity}, mode=${latest_mode}); recent_top=${top_categories}"
}

mr_failure_taxonomy_guardrail_for_category() {
  category_id=$1
  case "$category_id" in
    command-policy-block)
      printf '%s' "Front-load read-only reconnaissance and state approval-required actions before attempting them."
      ;;
    timeout-budget)
      printf '%s' "Reduce scope per iteration and prioritize a verifiable partial completion over broad unfinished work."
      ;;
    controller-stagnation)
      printf '%s' "Do not repeat the prior transition/plan pattern; switch strategy by making explicit assumptions or surfacing a concrete decision gate."
      ;;
    decision-gate)
      printf '%s' "Surface high-impact user decisions early with concrete options before implementation proceeds."
      ;;
    parser-contract)
      printf '%s' "Keep controller output strictly section-structured and schema-compliant to avoid orchestration recovery paths."
      ;;
    verification-regression)
      printf '%s' "Increase verification density after each change and do not claim completion without passing evidence."
      ;;
    implementation-failure)
      printf '%s' "Constrain patch surface area and validate target files/paths before writing changes."
      ;;
    missing-artifact)
      printf '%s' "Confirm required files/paths and context up front instead of assuming artifact availability."
      ;;
    external-dependency)
      printf '%s' "Isolate dependency-sensitive steps and provide graceful fallback plans when environment/network calls fail."
      ;;
    *)
      printf '%s' "Maintain small verifiable steps and explicit assumptions to reduce repeated failure loops."
      ;;
  esac
}

mr_failure_taxonomy_recent_guardrails_text() {
  max_rows=$1
  max_items=$2
  case "$max_rows" in ""|*[!0-9]*) max_rows=8 ;; esac
  case "$max_items" in ""|*[!0-9]*) max_items=2 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi
  if [ "$max_items" -lt 1 ]; then
    max_items=1
  fi

  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '%s' "none"
    return 0
  fi

  tab_char=$(printf '\t')
  recent_file=$(mktemp)
  top_file=$(mktemp)
  tail -n "$max_rows" "$events_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  awk -F"$tab_char" '
    NF >= 3 {
      category = $3
      if (category == "") {
        category = "unknown"
      }
      counts[category] += 1
    }
    END {
      for (category in counts) {
        printf "%s\t%s\n", counts[category], category
      }
    }
  ' "$recent_file" | sort -t "$tab_char" -k1,1nr -k2,2 > "$top_file"

  out=""
  shown=0
  while IFS="$tab_char" read -r count category_id || [ -n "$category_id" ]; do
    [ -n "$category_id" ] || continue
    hint=$(mr_failure_taxonomy_guardrail_for_category "$category_id")
    hint=$(trim "$hint")
    [ -n "$hint" ] || continue
    if [ -n "$out" ]; then
      out="${out}; "
    fi
    out="${out}${category_id}: ${hint}"
    shown=$((shown + 1))
    if [ "$shown" -ge "$max_items" ]; then
      break
    fi
  done < "$top_file"

  rm -f "$recent_file" "$top_file"
  if [ -z "$out" ]; then
    out="none"
  fi
  printf '%s' "$out"
}

mr_improvement_proposal_exists_for_category_and_mode() {
  category_id=$(trim "${1:-}")
  mode_filter=$(trim "${2:-}")
  source_filter=$(trim "${3:-}")
  [ -n "$category_id$mode_filter$source_filter" ] || return 1
  for proposal_dir in "$(mr_improvement_proposals_dir)"/*; do
    [ -d "$proposal_dir" ] || continue
    meta_file="$proposal_dir/meta.env"
    [ -f "$meta_file" ] || continue
    proposal_category=$(mr_env_get "$meta_file" "taxonomy_category" "")
    proposal_status=$(mr_env_get "$meta_file" "status" "proposed")
    proposal_source=$(mr_env_get "$meta_file" "source" "manual")
    proposal_mode=$(mr_env_get "$meta_file" "source_mode" "")
    proposal_title=$(mr_env_get "$meta_file" "title" "")
    case "$proposal_status" in
      proposed|accepted|applied) ;;
      *)
        continue
        ;;
    esac
    if [ -n "$source_filter" ] && [ "$proposal_source" != "$source_filter" ]; then
      continue
    fi
    if [ -n "$category_id" ] && [ "$proposal_category" != "$category_id" ]; then
      continue
    fi
    if [ -n "$mode_filter" ]; then
      if [ -n "$proposal_mode" ]; then
        if [ "$proposal_mode" != "$mode_filter" ]; then
          continue
        fi
      else
        case "$proposal_title" in
          *"in ${mode_filter} mode"*) ;;
          *)
            continue
            ;;
        esac
      fi
    fi
    return 0
  done
  return 1
}

mr_improvement_proposal_exists_for_category() {
  category_id=$1
  [ -n "$category_id" ] || return 1
  mr_improvement_proposal_exists_for_category_and_mode "$category_id" "" ""
}

mr_improvement_proposal_create() {
  title_text=$(mr_sanitize_inline "$1")
  rationale_text=$(mr_sanitize_inline "$2")
  proposed_change_text=$(mr_sanitize_inline "$3")
  scope_text=$(mr_sanitize_inline "$4")
  risk_level_text=$(mr_sanitize_inline "$5")
  source_text=$(mr_sanitize_inline "$6")
  category_id=$(trim "${7:-}")
  source_mode=$(mr_sanitize_inline "${8:-}")

  [ -n "$title_text" ] || title_text="Untitled improvement proposal"
  [ -n "$rationale_text" ] || rationale_text="No rationale supplied."
  [ -n "$proposed_change_text" ] || proposed_change_text="No change proposal supplied."
  [ -n "$source_text" ] || source_text="manual"

  case "$scope_text" in
    controller-loop|conversation-flow|decision-surfacing|verification|tooling|other) ;;
    *) scope_text="other" ;;
  esac
  case "$risk_level_text" in
    low|medium|high) ;;
    *) risk_level_text="medium" ;;
  esac
  if [ -n "$category_id" ] && ! valid_id "$category_id"; then
    category_id=""
  fi
  if [ -n "$source_mode" ] && ! valid_id "$source_mode"; then
    source_mode=""
  fi

  proposal_id=$(printf '%s' "proposal-$(mr_new_id)" | tr -cd 'a-zA-Z0-9._-')
  [ -n "$proposal_id" ] || proposal_id="proposal-$(mr_now_epoch)-$$"

  proposal_dir=$(mr_improvement_proposal_dir_for "$proposal_id")
  if [ -d "$proposal_dir" ]; then
    proposal_id="${proposal_id}-$(awk 'BEGIN { srand(); printf "%04d", rand()*10000 }')"
    proposal_dir=$(mr_improvement_proposal_dir_for "$proposal_id")
  fi
  mkdir -p "$proposal_dir"

  now_iso=$(mr_now_iso)
  meta_file=$(mr_improvement_proposal_meta_file "$proposal_id")
  {
    printf 'id=%s\n' "$proposal_id"
    printf 'title=%s\n' "$title_text"
    printf 'scope=%s\n' "$scope_text"
    printf 'risk_level=%s\n' "$risk_level_text"
    printf 'source=%s\n' "$source_text"
    printf 'status=proposed\n'
    printf 'created_at=%s\n' "$now_iso"
    printf 'updated_at=%s\n' "$now_iso"
    printf 'applied_at=\n'
    printf 'taxonomy_category=%s\n' "$category_id"
    printf 'source_mode=%s\n' "$source_mode"
    printf 'rationale=%s\n' "$rationale_text"
    printf 'proposed_change=%s\n' "$proposed_change_text"
  } > "$meta_file"

  proposal_file=$(mr_improvement_proposal_body_file "$proposal_id")
  {
    printf '# %s\n\n' "$title_text"
    printf 'Status: proposed\n'
    printf 'Scope: %s\n' "$scope_text"
    printf 'Risk: %s\n' "$risk_level_text"
    printf 'Source: %s\n' "$source_text"
    if [ -n "$category_id" ]; then
      printf 'Taxonomy category: %s\n' "$category_id"
    fi
    if [ -n "$source_mode" ]; then
      printf 'Source mode: %s\n' "$source_mode"
    fi
    printf 'Created: %s\n\n' "$now_iso"
    printf '## Rationale\n- %s\n\n' "$rationale_text"
    printf '## Proposed Change\n- %s\n\n' "$proposed_change_text"
    printf '## Safety Gate\n- Manual apply only. This proposal does not auto-edit execution pipelines.\n'
  } > "$proposal_file"

  printf '%s' "$proposal_id"
}

mr_improvement_proposal_status_counts_json() {
  proposed_count=0
  accepted_count=0
  applied_count=0
  rejected_count=0
  total_count=0

  for proposal_dir in "$(mr_improvement_proposals_dir)"/*; do
    [ -d "$proposal_dir" ] || continue
    meta_file="$proposal_dir/meta.env"
    [ -f "$meta_file" ] || continue
    total_count=$((total_count + 1))
    status_value=$(mr_env_get "$meta_file" "status" "proposed")
    case "$status_value" in
      accepted)
        accepted_count=$((accepted_count + 1))
        ;;
      applied)
        applied_count=$((applied_count + 1))
        ;;
      rejected)
        rejected_count=$((rejected_count + 1))
        ;;
      *)
        proposed_count=$((proposed_count + 1))
        ;;
    esac
  done

  printf '{"total":"%s","proposed":"%s","accepted":"%s","applied":"%s","rejected":"%s"}' \
    "$(json_escape "$total_count")" \
    "$(json_escape "$proposed_count")" \
    "$(json_escape "$accepted_count")" \
    "$(json_escape "$applied_count")" \
    "$(json_escape "$rejected_count")"
}

mr_improvement_proposals_items_json() {
  max_rows=$1
  case "$max_rows" in
    ""|*[!0-9]*) max_rows=40 ;;
  esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  proposal_dirs=$(find "$(mr_improvement_proposals_dir)" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  printf '['
  first=1
  shown=0
  if [ -n "$proposal_dirs" ]; then
    printf '%s\n' "$proposal_dirs" | while IFS= read -r proposal_dir; do
      [ -d "$proposal_dir" ] || continue
      meta_file="$proposal_dir/meta.env"
      [ -f "$meta_file" ] || continue
      shown=$((shown + 1))
      if [ "$shown" -gt "$max_rows" ]; then
        break
      fi
      proposal_id=$(mr_env_get "$meta_file" "id" "$(basename "$proposal_dir")")
      title_text=$(mr_env_get "$meta_file" "title" "$proposal_id")
      scope_text=$(mr_env_get "$meta_file" "scope" "other")
      risk_level_text=$(mr_env_get "$meta_file" "risk_level" "medium")
      status_value=$(mr_env_get "$meta_file" "status" "proposed")
      source_text=$(mr_env_get "$meta_file" "source" "manual")
      source_mode=$(mr_env_get "$meta_file" "source_mode" "")
      created_at=$(mr_env_get "$meta_file" "created_at" "")
      updated_at=$(mr_env_get "$meta_file" "updated_at" "")
      applied_at=$(mr_env_get "$meta_file" "applied_at" "")
      category_id=$(mr_env_get "$meta_file" "taxonomy_category" "")
      rationale_text=$(mr_env_get "$meta_file" "rationale" "")
      proposed_change_text=$(mr_env_get "$meta_file" "proposed_change" "")
      category_label=$(mr_failure_taxonomy_category_label "$category_id")
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"id":"%s","title":"%s","scope":"%s","risk_level":"%s","status":"%s","source":"%s","source_mode":"%s","created_at":"%s","updated_at":"%s","applied_at":"%s","taxonomy_category":"%s","taxonomy_category_label":"%s","rationale":"%s","proposed_change":"%s"}' \
        "$(json_escape "$proposal_id")" \
        "$(json_escape "$title_text")" \
        "$(json_escape "$scope_text")" \
        "$(json_escape "$risk_level_text")" \
        "$(json_escape "$status_value")" \
        "$(json_escape "$source_text")" \
        "$(json_escape "$source_mode")" \
        "$(json_escape "$created_at")" \
        "$(json_escape "$updated_at")" \
        "$(json_escape "$applied_at")" \
        "$(json_escape "$category_id")" \
        "$(json_escape "$category_label")" \
        "$(json_escape "$rationale_text")" \
        "$(json_escape "$proposed_change_text")"
    done
  fi
  printf ']'
}

mr_improvement_proposals_state_json() {
  printf '{"manual_apply_only":true,"counts":%s,"items":%s}' \
    "$(mr_improvement_proposal_status_counts_json)" \
    "$(mr_improvement_proposals_items_json "40")"
}

mr_improvement_proposals_recent_summary_text() {
  run_mode_filter=$(trim "${1:-}")
  max_rows_raw=${2:-12}
  max_items_raw=${3:-3}
  max_rows=$(mr_positive_int_or "$max_rows_raw" "12")
  max_items=$(mr_positive_int_or "$max_items_raw" "3")
  if [ "$max_rows" -gt 120 ]; then
    max_rows=120
  fi
  if [ "$max_items" -gt 8 ]; then
    max_items=8
  fi

  proposals_dir=$(mr_improvement_proposals_dir)
  if [ ! -d "$proposals_dir" ]; then
    printf '%s' "none"
    return 0
  fi

  mode_filter_lc=$(printf '%s' "$run_mode_filter" | tr '[:upper:]' '[:lower:]')
  dirs_file=$(mktemp)
  find "$proposals_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r > "$dirs_file"

  accepted_count=0
  applied_count=0
  scanned=0
  shown=0
  out=""
  while IFS= read -r proposal_dir || [ -n "$proposal_dir" ]; do
    [ -d "$proposal_dir" ] || continue
    meta_file="$proposal_dir/meta.env"
    [ -f "$meta_file" ] || continue
    scanned=$((scanned + 1))
    if [ "$scanned" -gt "$max_rows" ]; then
      break
    fi

    status_value=$(mr_env_get "$meta_file" "status" "proposed")
    case "$status_value" in
      accepted|applied) ;;
      *)
        continue
        ;;
    esac

    proposal_mode=$(trim "$(mr_env_get "$meta_file" "source_mode" "")")
    proposal_mode_lc=$(printf '%s' "$proposal_mode" | tr '[:upper:]' '[:lower:]')
    proposal_title=$(mr_env_get "$meta_file" "title" "")
    if [ -n "$mode_filter_lc" ] && [ "$mode_filter_lc" != "unknown" ]; then
      if [ -n "$proposal_mode_lc" ]; then
        if [ "$proposal_mode_lc" != "$mode_filter_lc" ]; then
          continue
        fi
      else
        case "$proposal_title" in
          *"in ${mode_filter_lc} mode"*) ;;
          *"in ${run_mode_filter} mode"*) ;;
          *)
            continue
            ;;
        esac
      fi
    fi

    if [ "$status_value" = "accepted" ]; then
      accepted_count=$((accepted_count + 1))
    else
      applied_count=$((applied_count + 1))
    fi

    if [ "$shown" -lt "$max_items" ]; then
      scope_value=$(mr_env_get "$meta_file" "scope" "other")
      risk_value=$(mr_env_get "$meta_file" "risk_level" "medium")
      source_value=$(mr_env_get "$meta_file" "source" "manual")
      category_value=$(trim "$(mr_env_get "$meta_file" "taxonomy_category" "")")
      if [ -z "$category_value" ]; then
        category_value="unknown"
      fi
      entry_mode="$proposal_mode_lc"
      if [ -z "$entry_mode" ]; then
        if [ -n "$mode_filter_lc" ] && [ "$mode_filter_lc" != "unknown" ]; then
          entry_mode="$mode_filter_lc"
        else
          entry_mode="unknown"
        fi
      fi
      entry_text="${status_value}:${scope_value}/${risk_value}@${category_value}[${source_value}|mode=${entry_mode}]"
      if [ -n "$out" ]; then
        out="${out}; "
      fi
      out="${out}${entry_text}"
      shown=$((shown + 1))
    fi
  done < "$dirs_file"
  rm -f "$dirs_file"

  if [ "$accepted_count" -eq 0 ] && [ "$applied_count" -eq 0 ]; then
    printf '%s' "none"
    return 0
  fi
  if [ -z "$out" ]; then
    out="none"
  fi
  printf 'accepted=%s; applied=%s; recent=%s' "$accepted_count" "$applied_count" "$out"
}

mr_improvement_proposal_template_for_category() {
  category_id=$1
  case "$category_id" in
    timeout-budget)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Reduce run timeout failures via earlier decomposition" \
        "Runs are spending too much budget before producing stable partial output." \
        "Add an early decomposition checkpoint and emit partial-deliverable summaries before heavy implementation phases." \
        "controller-loop" \
        "low"
      ;;
    controller-stagnation)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Break repeated controller-loop stagnation patterns" \
        "Consecutive iterations are repeating the same transition signature without forward progress." \
        "Add anti-repeat guardrails that force either explicit assumptions with verifiable progress or an early decision checkpoint." \
        "controller-loop" \
        "medium"
      ;;
    command-policy-block)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Improve command preflight to reduce approval deadlocks" \
        "Frequent policy blocks indicate command plans are not preflighted early enough." \
        "Add preflight command planning that rewrites unsafe command intents into policy-compliant alternatives before execution." \
        "decision-surfacing" \
        "medium"
      ;;
    decision-gate)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Surface high-impact decisions earlier in runs" \
        "Decision requests are appearing late, causing rework." \
        "Promote an early decision-checkpoint that requests missing high-impact choices before implementation starts." \
        "decision-surfacing" \
        "low"
      ;;
    parser-contract)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Harden controller output parsing contract" \
        "Parser/format failures reduce iteration quality and waste context." \
        "Strengthen parser guards and add fallback normalization for malformed controller sections." \
        "tooling" \
        "medium"
      ;;
    verification-regression)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Tighten verification-first loop behavior" \
        "Verification regressions suggest tests are not leading implementation flow enough." \
        "Require verification plan refresh before each implementation step and block promotion when test evidence is stale." \
        "verification" \
        "medium"
      ;;
    implementation-failure)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Shrink implementation batch size after repeated failures" \
        "Implementation failures indicate overly large patch scope per iteration." \
        "Automatically split implementation tasks into smaller files/steps when failures repeat within the same run." \
        "controller-loop" \
        "medium"
      ;;
    missing-artifact)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Strengthen context acquisition for missing artifacts" \
        "Missing-file/context failures indicate weak discovery before edits." \
        "Add a mandatory context probe phase when referenced files cannot be found, then regenerate the plan from discovered paths." \
        "conversation-flow" \
        "low"
      ;;
    external-dependency)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Add resilient fallback for external dependency failures" \
        "External dependency failures can stall runs that would otherwise make progress offline." \
        "Add offline fallback behavior and explicit uncertainty messaging when network/external dependencies fail." \
        "controller-loop" \
        "low"
      ;;
    *)
      printf '%s\t%s\t%s\t%s\t%s' \
        "Investigate uncategorized failure cluster" \
        "A recurring uncategorized failure pattern needs explicit handling." \
        "Capture exemplar failures and define a dedicated category plus mitigation strategy." \
        "other" \
        "low"
      ;;
  esac
}

mr_improvement_proposal_generate_from_taxonomy_json() {
  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '{"created":[],"skipped":[],"note":"No failures recorded yet."}'
    return 0
  fi

  tab_char=$(printf '\t')
  stats_file=$(mktemp)
  awk -F'\t' '
    NF >= 3 {
      category = $3
      if (category == "") {
        category = "unknown"
      }
      counts[category] += 1
    }
    END {
      for (category in counts) {
        printf "%s\t%s\n", counts[category], category
      }
    }
  ' "$events_file" | sort -t "$tab_char" -k1,1nr -k2,2 > "$stats_file"

  created_csv=""
  skipped_csv=""
  generated_count=0
  while IFS="$tab_char" read -r count_value category_id || [ -n "$category_id" ]; do
    [ -n "$category_id" ] || continue
    case "$count_value" in
      ""|*[!0-9]*) count_value=0 ;;
    esac
    if [ "$count_value" -lt 2 ]; then
      continue
    fi
    if [ "$generated_count" -ge 4 ]; then
      break
    fi
    if mr_improvement_proposal_exists_for_category "$category_id"; then
      if [ -n "$skipped_csv" ]; then
        skipped_csv="$skipped_csv,$category_id"
      else
        skipped_csv="$category_id"
      fi
      continue
    fi
    template_row=$(mr_improvement_proposal_template_for_category "$category_id")
    title_text=$(printf '%s' "$template_row" | awk -F"$tab_char" '{ print $1 }')
    rationale_text=$(printf '%s' "$template_row" | awk -F"$tab_char" '{ print $2 }')
    change_text=$(printf '%s' "$template_row" | awk -F"$tab_char" '{ print $3 }')
    scope_text=$(printf '%s' "$template_row" | awk -F"$tab_char" '{ print $4 }')
    risk_text=$(printf '%s' "$template_row" | awk -F"$tab_char" '{ print $5 }')
    proposal_id=$(mr_improvement_proposal_create "$title_text" "$rationale_text" "$change_text" "$scope_text" "$risk_text" "failure-taxonomy" "$category_id")
    if [ -n "$proposal_id" ]; then
      generated_count=$((generated_count + 1))
      if [ -n "$created_csv" ]; then
        created_csv="$created_csv,$proposal_id"
      else
        created_csv="$proposal_id"
      fi
    fi
  done < "$stats_file"
  rm -f "$stats_file"

  printf '{"created":%s,"skipped":%s}' \
    "$(mr_csv_to_json_array "$created_csv")" \
    "$(mr_csv_to_json_array "$skipped_csv")"
}

mr_improvement_proposal_set_status() {
  proposal_id=$(trim "$1")
  status_value=$(trim "$2")
  note_text=$(mr_sanitize_inline "${3:-}")
  if ! valid_id "$proposal_id"; then
    return 1
  fi
  case "$status_value" in
    accepted|applied|rejected) ;;
    *) return 1 ;;
  esac
  proposal_dir=$(mr_improvement_proposal_dir_for "$proposal_id")
  if [ ! -d "$proposal_dir" ]; then
    return 1
  fi
  meta_file=$(mr_improvement_proposal_meta_file "$proposal_id")
  [ -f "$meta_file" ] || return 1

  now_iso=$(mr_now_iso)
  mr_env_set "$meta_file" "status" "$status_value"
  mr_env_set "$meta_file" "updated_at" "$now_iso"
  if [ "$status_value" = "applied" ]; then
    mr_env_set "$meta_file" "applied_at" "$now_iso"
  fi

  decisions_file="$(mr_improvement_proposals_dir)/decisions.tsv"
  [ -f "$decisions_file" ] || : > "$decisions_file"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(mr_now_epoch)" "$now_iso" "$proposal_id" "$status_value" "$note_text" >> "$decisions_file"

  if [ "$status_value" = "accepted" ] || [ "$status_value" = "applied" ]; then
    mr_controller_variant_create_from_proposal "$proposal_id" >/dev/null 2>&1 || true
  fi
  return 0
}

mr_controller_variant_default_id() {
  printf '%s' "controller-default"
}

mr_controller_variant_exists() {
  variant_id=$1
  if ! valid_id "$variant_id"; then
    return 1
  fi
  [ -f "$(mr_controller_variant_meta_file "$variant_id")" ]
}

mr_controller_variant_active_id() {
  state_file=$(mr_controller_variants_state_file)
  active_id=$(mr_env_get "$state_file" "active_variant_id" "$(mr_controller_variant_default_id)")
  if ! valid_id "$active_id"; then
    active_id=$(mr_controller_variant_default_id)
  fi
  if ! mr_controller_variant_exists "$active_id"; then
    active_id=$(mr_controller_variant_default_id)
  fi
  printf '%s' "$active_id"
}

mr_controller_variant_previous_active_id() {
  state_file=$(mr_controller_variants_state_file)
  previous_id=$(mr_env_get "$state_file" "previous_active_variant_id" "")
  if ! valid_id "$previous_id"; then
    previous_id=""
  fi
  if [ -n "$previous_id" ] && ! mr_controller_variant_exists "$previous_id"; then
    previous_id=""
  fi
  printf '%s' "$previous_id"
}

mr_controller_variant_sample_rate_percent() {
  state_file=$(mr_controller_variants_state_file)
  raw_value=$(mr_env_get "$state_file" "sample_rate_percent" "35")
  sample_rate=$(mr_nonnegative_int_or "$raw_value" "35")
  if [ "$sample_rate" -gt 100 ]; then
    sample_rate=100
  fi
  printf '%s' "$sample_rate"
}

mr_controller_variant_max_sample_size() {
  state_file=$(mr_controller_variants_state_file)
  raw_value=$(mr_env_get "$state_file" "max_sample_size" "40")
  max_sample_size=$(mr_positive_int_or "$raw_value" "40")
  printf '%s' "$max_sample_size"
}

mr_controller_variant_sample_min_runs_for_promotion() {
  state_file=$(mr_controller_variants_state_file)
  raw_value=$(mr_env_get "$state_file" "sample_min_runs_for_promotion" "6")
  min_runs=$(mr_positive_int_or "$raw_value" "6")
  printf '%s' "$min_runs"
}

mr_controller_variant_status_set() {
  variant_id=$1
  status_value=$2
  if ! mr_controller_variant_exists "$variant_id"; then
    return 1
  fi
  case "$status_value" in
    active|candidate|standby|retired) ;;
    *) return 1 ;;
  esac
  meta_file=$(mr_controller_variant_meta_file "$variant_id")
  mr_env_set "$meta_file" "status" "$status_value"
  mr_env_set "$meta_file" "updated_at" "$(mr_now_iso)"
  return 0
}

mr_controller_variant_id_for_proposal() {
  proposal_id=$1
  if ! valid_id "$proposal_id"; then
    printf '%s' ""
    return 0
  fi
  for variant_dir in "$(mr_controller_variants_dir)"/*; do
    [ -d "$variant_dir" ] || continue
    meta_file="$variant_dir/meta.env"
    [ -f "$meta_file" ] || continue
    source_proposal=$(mr_env_get "$meta_file" "source_proposal" "")
    if [ "$source_proposal" = "$proposal_id" ]; then
      printf '%s' "$(basename "$variant_dir")"
      return 0
    fi
  done
  printf '%s' ""
}

mr_controller_variant_create_from_proposal() {
  proposal_id=$(trim "$1")
  if ! valid_id "$proposal_id"; then
    printf '%s' ""
    return 0
  fi

  proposal_meta=$(mr_improvement_proposal_meta_file "$proposal_id")
  if [ ! -f "$proposal_meta" ]; then
    printf '%s' ""
    return 0
  fi

  existing_variant_id=$(mr_controller_variant_id_for_proposal "$proposal_id")
  if [ -n "$existing_variant_id" ] && mr_controller_variant_exists "$existing_variant_id"; then
    printf '%s' "$existing_variant_id"
    return 0
  fi

  proposal_title=$(mr_env_get "$proposal_meta" "title" "$proposal_id")
  proposal_scope=$(mr_env_get "$proposal_meta" "scope" "other")
  proposal_risk=$(mr_env_get "$proposal_meta" "risk_level" "medium")
  proposal_rationale=$(mr_env_get "$proposal_meta" "rationale" "")
  proposal_change=$(mr_env_get "$proposal_meta" "proposed_change" "")
  parent_id=$(mr_controller_variant_active_id)

  variant_id=$(printf '%s' "controller-variant-$(mr_new_id)" | tr -cd 'a-zA-Z0-9._-')
  [ -n "$variant_id" ] || variant_id="controller-variant-$(mr_now_epoch)-$$"
  variant_dir=$(mr_controller_variant_dir_for "$variant_id")
  if [ -d "$variant_dir" ]; then
    variant_id="${variant_id}-$(awk 'BEGIN { srand(); printf "%04d", rand()*10000 }')"
    variant_dir=$(mr_controller_variant_dir_for "$variant_id")
  fi

  now_iso=$(mr_now_iso)
  guidance_text=$(mr_sanitize_inline "$(cat <<EOF
Source proposal: $proposal_title. Scope: $proposal_scope. Proposed controller adaptation: $proposal_change. Rationale: $proposal_rationale. Keep safety, deterministic section formatting, verifiable execution, and concise user-facing synthesis.
EOF
)")
  if [ -z "$guidance_text" ]; then
    guidance_text="Source proposal: $proposal_title. Keep safety, deterministic section formatting, and verifiable delivery."
  fi

  mkdir -p "$variant_dir"
  meta_file=$(mr_controller_variant_meta_file "$variant_id")
  {
    printf 'id=%s\n' "$variant_id"
    printf 'name=%s\n' "$(mr_sanitize_inline "Variant from $proposal_title")"
    printf 'status=candidate\n'
    printf 'kind=proposal-derived\n'
    printf 'parent_id=%s\n' "$parent_id"
    printf 'source_proposal=%s\n' "$proposal_id"
    printf 'scope=%s\n' "$proposal_scope"
    printf 'risk_level=%s\n' "$proposal_risk"
    printf 'created_at=%s\n' "$now_iso"
    printf 'updated_at=%s\n' "$now_iso"
    printf 'last_seen_at=\n'
    printf 'instructions=%s\n' "$guidance_text"
    printf 'runs=0\n'
    printf 'successes=0\n'
    printf 'avg_quality=0.000\n'
  } > "$meta_file"

  notes_file=$(mr_controller_variant_notes_file "$variant_id")
  {
    printf '# Controller Variant: %s\n\n' "$variant_id"
    printf 'Source proposal: %s\n' "$proposal_id"
    printf 'Parent variant: %s\n' "$parent_id"
    printf 'Created: %s\n\n' "$now_iso"
    printf '## Guidance\n- %s\n' "$guidance_text"
  } > "$notes_file"

  printf '%s' "$variant_id"
}

mr_controller_variant_latest_candidate_id() {
  latest_id=""
  for variant_dir in "$(mr_controller_variants_dir)"/*; do
    [ -d "$variant_dir" ] || continue
    meta_file="$variant_dir/meta.env"
    [ -f "$meta_file" ] || continue
    status_value=$(mr_env_get "$meta_file" "status" "standby")
    case "$status_value" in
      candidate)
        latest_id=$(basename "$variant_dir")
        ;;
    esac
  done
  if [ -n "$latest_id" ] && ! mr_controller_variant_exists "$latest_id"; then
    latest_id=""
  fi
  printf '%s' "$latest_id"
}

mr_controller_variant_promote() {
  variant_id=$(trim "$1")
  if ! valid_id "$variant_id"; then
    return 1
  fi
  if ! mr_controller_variant_exists "$variant_id"; then
    return 1
  fi
  state_file=$(mr_controller_variants_state_file)
  current_active=$(mr_controller_variant_active_id)
  if [ "$current_active" = "$variant_id" ]; then
    return 0
  fi

  mr_env_set "$state_file" "previous_active_variant_id" "$current_active"
  mr_env_set "$state_file" "active_variant_id" "$variant_id"
  mr_env_set "$state_file" "updated_at" "$(mr_now_iso)"
  if [ -n "$current_active" ] && mr_controller_variant_exists "$current_active"; then
    mr_controller_variant_status_set "$current_active" "standby" >/dev/null 2>&1 || true
  fi
  mr_controller_variant_status_set "$variant_id" "active" >/dev/null 2>&1 || true
  return 0
}

mr_controller_variant_rollback() {
  state_file=$(mr_controller_variants_state_file)
  current_active=$(mr_controller_variant_active_id)
  rollback_target=$(mr_controller_variant_previous_active_id)
  if [ -z "$rollback_target" ]; then
    rollback_target=$(mr_controller_variant_default_id)
  fi
  if ! mr_controller_variant_exists "$rollback_target"; then
    rollback_target=$(mr_controller_variant_default_id)
  fi
  if ! mr_controller_variant_exists "$rollback_target"; then
    return 1
  fi
  mr_env_set "$state_file" "previous_active_variant_id" "$current_active"
  mr_env_set "$state_file" "active_variant_id" "$rollback_target"
  mr_env_set "$state_file" "updated_at" "$(mr_now_iso)"
  if [ -n "$current_active" ] && [ "$current_active" != "$rollback_target" ] && mr_controller_variant_exists "$current_active"; then
    mr_controller_variant_status_set "$current_active" "standby" >/dev/null 2>&1 || true
  fi
  mr_controller_variant_status_set "$rollback_target" "active" >/dev/null 2>&1 || true
  return 0
}

mr_controller_variant_guidance_for() {
  variant_id=$(trim "$1")
  if ! mr_controller_variant_exists "$variant_id"; then
    printf '%s' ""
    return 0
  fi
  meta_file=$(mr_controller_variant_meta_file "$variant_id")
  printf '%s' "$(mr_env_get "$meta_file" "instructions" "")"
}

mr_controller_variant_select_for_run() {
  run_id=$(trim "$1")
  active_id=$(mr_controller_variant_active_id)
  selected_id=$active_id
  sample_bucket=0
  candidate_id=$(mr_controller_variant_latest_candidate_id)
  if [ -n "$candidate_id" ] && [ "$candidate_id" != "$active_id" ] && mr_controller_variant_exists "$candidate_id"; then
    sample_rate=$(mr_controller_variant_sample_rate_percent)
    max_sample_size=$(mr_controller_variant_max_sample_size)
    candidate_meta=$(mr_controller_variant_meta_file "$candidate_id")
    candidate_runs=$(mr_nonnegative_int_or "$(mr_env_get "$candidate_meta" "runs" "0")" "0")
    if [ "$candidate_runs" -lt "$max_sample_size" ] && [ "$sample_rate" -gt 0 ]; then
      if [ -z "$run_id" ]; then
        run_id="$(mr_now_epoch)-$$"
      fi
      sample_bucket=$(printf '%s' "$run_id" | cksum | awk '{ print $1 % 100 }')
      case "$sample_bucket" in ""|*[!0-9]*) sample_bucket=0 ;; esac
      if [ "$sample_bucket" -lt "$sample_rate" ]; then
        selected_id=$candidate_id
      fi
    fi
  fi
  printf '%s|%s|%s|%s' "$selected_id" "$sample_bucket" "$active_id" "$candidate_id"
}

mr_controller_variant_quality_score() {
  queue_status=$(trim "$1")
  final_state=$(trim "$2")
  run_elapsed_sec=$(mr_nonnegative_int_or "$3" "0")
  decision_requested=$(mr_bool_norm "$4")
  failure_count=$(mr_nonnegative_int_or "$5" "0")
  awk -v queue_status="$queue_status" -v final_state="$final_state" -v run_elapsed_sec="$run_elapsed_sec" -v decision_requested="$decision_requested" -v failure_count="$failure_count" '
    BEGIN {
      score = 0.15
      if (queue_status == "done") {
        score += 0.45
      } else if (queue_status == "awaiting_decision") {
        score += 0.18
      } else if (queue_status == "awaiting_approval") {
        score += 0.22
      } else {
        score += 0.05
      }
      if (final_state == "DONE") {
        score += 0.25
      } else {
        score -= 0.08
      }
      if (decision_requested == "1") {
        score -= 0.04
      }
      penalty = failure_count * 0.035
      if (penalty > 0.30) {
        penalty = 0.30
      }
      score -= penalty
      if (run_elapsed_sec > 0 && run_elapsed_sec < 180) {
        score += 0.05
      } else if (run_elapsed_sec > 900) {
        score -= 0.04
      }
      if (score < 0) {
        score = 0
      }
      if (score > 1) {
        score = 1
      }
      printf "%.3f", score
    }
  '
}

mr_controller_variant_record_run() {
  variant_id=$(trim "$1")
  run_id=$(trim "$2")
  queue_status=$(mr_sanitize_inline "$3")
  final_state=$(mr_sanitize_inline "$4")
  run_elapsed_sec=$(mr_nonnegative_int_or "$5" "0")
  iteration_count=$(mr_nonnegative_int_or "$6" "0")
  decision_requested=$(mr_bool_norm "$7")
  failure_count=$(mr_nonnegative_int_or "$8" "0")
  run_mode=$(mr_sanitize_inline "$9")
  model_name=$(mr_sanitize_inline "${10}")

  if ! valid_id "$variant_id" || ! mr_controller_variant_exists "$variant_id"; then
    variant_id=$(mr_controller_variant_active_id)
  fi
  if [ -z "$run_id" ]; then
    run_id="$(mr_now_epoch)-$$"
  fi
  if ! valid_id "$run_id"; then
    run_id=$(printf '%s' "$run_id" | tr -cd 'a-zA-Z0-9._-')
  fi
  [ -n "$run_id" ] || run_id="$(mr_now_epoch)-$$"

  quality_score=$(mr_controller_variant_quality_score "$queue_status" "$final_state" "$run_elapsed_sec" "$decision_requested" "$failure_count")
  now_epoch=$(mr_now_epoch)
  now_iso=$(mr_now_iso)

  telemetry_file=$(mr_controller_variants_telemetry_file)
  [ -f "$telemetry_file" ] || : > "$telemetry_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" \
    "$now_iso" \
    "$variant_id" \
    "$run_id" \
    "$queue_status" \
    "$final_state" \
    "$run_mode" \
    "$model_name" \
    "$iteration_count" \
    "$run_elapsed_sec" \
    "$decision_requested" \
    "$quality_score" >> "$telemetry_file"

  meta_file=$(mr_controller_variant_meta_file "$variant_id")
  current_runs=$(mr_nonnegative_int_or "$(mr_env_get "$meta_file" "runs" "0")" "0")
  current_successes=$(mr_nonnegative_int_or "$(mr_env_get "$meta_file" "successes" "0")" "0")
  current_avg=$(mr_env_get "$meta_file" "avg_quality" "0.000")
  new_runs=$((current_runs + 1))
  run_success=0
  if [ "$queue_status" = "done" ] && [ "$final_state" = "DONE" ]; then
    run_success=1
  fi
  new_successes=$((current_successes + run_success))
  new_avg=$(awk -v current_avg="$current_avg" -v current_runs="$current_runs" -v quality_score="$quality_score" '
    BEGIN {
      if (current_runs <= 0) {
        avg = quality_score + 0.0
      } else {
        avg = ((current_avg + 0.0) * current_runs + (quality_score + 0.0)) / (current_runs + 1)
      }
      if (avg < 0) {
        avg = 0
      }
      if (avg > 1) {
        avg = 1
      }
      printf "%.3f", avg
    }
  ')

  mr_env_set "$meta_file" "runs" "$new_runs"
  mr_env_set "$meta_file" "successes" "$new_successes"
  mr_env_set "$meta_file" "avg_quality" "$new_avg"
  mr_env_set "$meta_file" "last_seen_at" "$now_iso"
  mr_env_set "$meta_file" "updated_at" "$now_iso"

  if command -v mr_quality_scorecard_record_entry >/dev/null 2>&1; then
    mr_quality_scorecard_record_entry \
      "$variant_id" \
      "$run_id" \
      "$run_mode" \
      "$queue_status" \
      "$final_state" \
      "$quality_score" \
      "$run_elapsed_sec" \
      "$iteration_count" \
      "$decision_requested" \
      "$failure_count" >/dev/null 2>&1 || true
  fi
}

mr_failure_taxonomy_latest_category_id() {
  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '%s' "unknown"
    return 0
  fi
  tab_char=$(printf '\t')
  category_id=$(tail -n 1 "$events_file" 2>/dev/null | awk -F"$tab_char" '{ print $3 }')
  category_id=$(trim "$category_id")
  if [ -z "$category_id" ]; then
    category_id="unknown"
  fi
  printf '%s' "$category_id"
}

mr_failure_taxonomy_top_category_for_mode() {
  run_mode_filter=$(trim "${1:-}")
  max_rows_raw=${2:-24}
  max_rows=$(mr_positive_int_or "$max_rows_raw" "24")
  if [ "$max_rows" -gt 120 ]; then
    max_rows=120
  fi
  events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -s "$events_file" ]; then
    printf '%s' "unknown"
    return 0
  fi
  if [ -z "$run_mode_filter" ] || [ "$run_mode_filter" = "unknown" ]; then
    mr_failure_taxonomy_latest_category_id
    return 0
  fi
  run_mode_filter=$(printf '%s' "$run_mode_filter" | tr '[:upper:]' '[:lower:]')
  recent_file=$(mktemp)
  mode_events_file=$(mktemp)
  stats_file=$(mktemp)
  tab_char=$(printf '\t')
  awk -F"$tab_char" -v run_mode_filter="$run_mode_filter" '
    NF >= 6 {
      mode_value = tolower($6)
      if (mode_value == run_mode_filter) {
        print
      }
    }
  ' "$events_file" > "$mode_events_file"
  if [ -s "$mode_events_file" ]; then
    tail -n "$max_rows" "$mode_events_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  else
    : > "$recent_file"
  fi
  awk -F"$tab_char" -v run_mode_filter="$run_mode_filter" '
    NF >= 6 {
      mode_value = tolower($6)
      if (mode_value != run_mode_filter) {
        next
      }
      category = $3
      if (category == "") {
        category = "unknown"
      }
      severity = tolower($5)
      sev_rank = 1
      if (severity == "high") {
        sev_rank = 3
      } else if (severity == "medium") {
        sev_rank = 2
      }
      counts[category] += 1
      if (sev_rank > sev[category]) {
        sev[category] = sev_rank
      }
      epoch_value = $1 + 0
      if (epoch_value > last_epoch[category]) {
        last_epoch[category] = epoch_value
      }
    }
    END {
      for (category in counts) {
        printf "%s\t%s\t%s\t%s\n", counts[category], sev[category], last_epoch[category], category
      }
    }
  ' "$recent_file" | sort -t "$tab_char" -k1,1nr -k2,2nr -k3,3nr -k4,4 > "$stats_file"

  top_category=""
  if [ -s "$stats_file" ]; then
    top_category=$(awk -F"$tab_char" 'NF >= 4 { print $4; exit }' "$stats_file")
  fi
  rm -f "$recent_file" "$mode_events_file" "$stats_file"
  top_category=$(trim "$top_category")
  if [ -z "$top_category" ]; then
    top_category="unknown"
  fi
  printf '%s' "$top_category"
}

mr_quality_scorecard_last_quality_for_mode() {
  run_mode=$1
  run_id_exclude=$2
  entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -s "$entries_file" ]; then
    printf '%s' ""
    return 0
  fi
  tab_char=$(printf '\t')
  awk -F"$tab_char" -v run_mode="$run_mode" -v run_id_exclude="$run_id_exclude" '
    NF >= 12 {
      entry_mode = $5
      entry_run_id = $4
      quality = $8
      if (entry_mode != run_mode) {
        next
      }
      if (run_id_exclude != "" && entry_run_id == run_id_exclude) {
        next
      }
      last = quality
    }
    END {
      if (last != "") {
        printf "%s", last
      }
    }
  ' "$entries_file"
}

mr_quality_scorecard_recent_regression_stats_for_mode() {
  run_mode=$1
  window_raw=${2:-6}
  case "$run_mode" in
    "")
      printf '%s\t%s\t%s\t%s' "0" "0" "0" "0.000"
      return 0
      ;;
  esac
  window_size=$(mr_positive_int_or "$window_raw" "6")
  if [ "$window_size" -gt 24 ]; then
    window_size=24
  fi
  entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -s "$entries_file" ]; then
    printf '%s\t%s\t%s\t%s' "0" "0" "0" "0.000"
    return 0
  fi
  tab_char=$(printf '\t')
  awk -F"$tab_char" -v run_mode="$run_mode" -v window_size="$window_size" '
    NF >= 10 {
      entry_mode = $5
      if (entry_mode != run_mode) {
        next
      }
      rows[++row_count] = $0
    }
    END {
      if (row_count <= 0) {
        printf "0\t0\t0\t0.000"
        exit
      }
      start = row_count - window_size + 1
      if (start < 1) {
        start = 1
      }
      total = 0
      regressive = 0
      severe = 0
      sum_delta = 0.0
      for (i = start; i <= row_count; i++) {
        split(rows[i], fields, "\t")
        final_state = fields[7]
        quality = fields[8] + 0.0
        delta = fields[9] + 0.0
        total += 1
        sum_delta += delta
        if ((final_state != "DONE" && quality < 0.55) || (delta <= -0.080 && quality < 0.60)) {
          regressive += 1
        }
        if ((final_state != "DONE" && quality < 0.50) || (delta <= -0.120 && quality < 0.55)) {
          severe += 1
        }
      }
      avg_delta = 0.0
      if (total > 0) {
        avg_delta = sum_delta / total
      }
      printf "%s\t%s\t%s\t%.3f", total, regressive, severe, avg_delta
    }
  ' "$entries_file"
}

mr_quality_scorecard_regression_cooldown_last_epoch_for_mode() {
  run_mode=$1
  cooldowns_file=$(mr_quality_scorecard_regression_cooldowns_file)
  if [ ! -s "$cooldowns_file" ]; then
    printf '%s' "0"
    return 0
  fi
  tab_char=$(printf '\t')
  last_epoch=$(awk -F"$tab_char" -v run_mode="$run_mode" '
    NF >= 1 {
      mode_value = $1
      epoch_value = $2
      if (mode_value != run_mode) {
        next
      }
      if (epoch_value ~ /^[0-9]+$/) {
        last = epoch_value
      }
    }
    END {
      if (last == "") {
        printf "0"
      } else {
        printf "%s", last
      }
    }
  ' "$cooldowns_file")
  case "$last_epoch" in
    ""|*[!0-9]*) last_epoch="0" ;;
  esac
  printf '%s' "$last_epoch"
}

mr_quality_scorecard_set_regression_cooldown_for_mode() {
  run_mode=$1
  now_epoch_raw=${2:-}
  case "$run_mode" in
    "") return 0 ;;
  esac
  now_epoch=$(mr_nonnegative_int_or "$now_epoch_raw" "$(mr_now_epoch)")
  now_iso=$(mr_now_iso)
  cooldowns_file=$(mr_quality_scorecard_regression_cooldowns_file)
  [ -f "$cooldowns_file" ] || : > "$cooldowns_file"
  tab_char=$(printf '\t')
  tmp_file=$(mktemp)
  while IFS="$tab_char" read -r mode_value epoch_value iso_value || [ -n "$mode_value$epoch_value$iso_value" ]; do
    [ -n "$mode_value$epoch_value$iso_value" ] || continue
    if [ "$mode_value" = "$run_mode" ]; then
      continue
    fi
    printf '%s\t%s\t%s\n' "$mode_value" "$epoch_value" "$iso_value" >> "$tmp_file"
  done < "$cooldowns_file"
  printf '%s\t%s\t%s\n' "$run_mode" "$now_epoch" "$now_iso" >> "$tmp_file"
  mv "$tmp_file" "$cooldowns_file"
}

mr_quality_scorecard_regression_cooldown_remaining_sec() {
  run_mode=$1
  cooldown_sec_raw=${2:-3600}
  now_epoch_raw=${3:-}
  case "$run_mode" in
    "")
      printf '%s' "0"
      return 0
      ;;
  esac
  cooldown_sec=$(mr_positive_int_or "$cooldown_sec_raw" "3600")
  now_epoch=$(mr_nonnegative_int_or "$now_epoch_raw" "$(mr_now_epoch)")
  last_epoch=$(mr_quality_scorecard_regression_cooldown_last_epoch_for_mode "$run_mode")
  case "$last_epoch" in
    ""|*[!0-9]*) last_epoch="0" ;;
  esac
  if [ "$last_epoch" -le 0 ]; then
    printf '%s' "0"
    return 0
  fi
  elapsed=$((now_epoch - last_epoch))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi
  remaining=$((cooldown_sec - elapsed))
  if [ "$remaining" -lt 0 ]; then
    remaining=0
  fi
  printf '%s' "$remaining"
}

mr_quality_scorecard_refresh_markdown() {
  entries_file=$(mr_quality_scorecard_entries_file)
  markdown_file=$(mr_quality_scorecard_markdown_file)
  now_iso=$(mr_now_iso)
  if [ ! -s "$entries_file" ]; then
    cat > "$markdown_file" <<EOF
# Intelligence Quality Scorecard

Updated: $now_iso

- No scorecard entries recorded yet.
EOF
    return 0
  fi

  tab_char=$(printf '\t')
  total_runs=$(wc -l < "$entries_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
  case "$total_runs" in ""|*[!0-9]*) total_runs=0 ;; esac

  overall_avg=$(awk -F"$tab_char" '
    NF >= 8 {
      sum += ($8 + 0.0)
      count += 1
    }
    END {
      if (count <= 0) {
        printf "0.000"
      } else {
        printf "%.3f", sum / count
      }
    }
  ' "$entries_file")

  recent_file=$(mktemp)
  tail -n 8 "$entries_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  top_modes_file=$(mktemp)
  awk -F"$tab_char" '
    NF >= 8 {
      mode = $5
      if (mode == "") {
        mode = "unknown"
      }
      sum[mode] += ($8 + 0.0)
      count[mode] += 1
    }
    END {
      for (mode in count) {
        avg = 0.0
        if (count[mode] > 0) {
          avg = sum[mode] / count[mode]
        }
        printf "%s\t%s\t%.3f\n", count[mode], mode, avg
      }
    }
  ' "$entries_file" | sort -t "$tab_char" -k1,1nr -k2,2 > "$top_modes_file"

  {
    printf '# Intelligence Quality Scorecard\n\n'
    printf 'Updated: %s\n\n' "$now_iso"
    printf '## Summary\n'
    printf -- '- Total runs scored: %s\n' "$total_runs"
    printf -- '- Overall average quality: %s\n\n' "$overall_avg"
    printf '## Top Modes by Volume\n'
    modes_shown=0
    while IFS="$tab_char" read -r mode_count mode_name mode_avg || [ -n "$mode_name" ]; do
      [ -n "$mode_name" ] || continue
      modes_shown=$((modes_shown + 1))
      if [ "$modes_shown" -gt 6 ]; then
        break
      fi
      printf -- '- %s: avg %s (n=%s)\n' "$mode_name" "$mode_avg" "$mode_count"
    done < "$top_modes_file"
    if [ "$modes_shown" -eq 0 ]; then
      printf -- '- none\n'
    fi
    printf '\n## Recent Entries\n'
    recent_shown=0
    while IFS="$tab_char" read -r epoch_value iso_value variant_id run_id run_mode queue_status final_state quality_score delta_score run_elapsed iteration_count failure_count || [ -n "$iso_value$run_mode$quality_score" ]; do
      [ -n "$iso_value$run_mode$quality_score" ] || continue
      recent_shown=$((recent_shown + 1))
      printf -- '- %s | mode=%s | quality=%s | delta=%s | status=%s/%s | variant=%s\n' \
        "$iso_value" "$run_mode" "$quality_score" "$delta_score" "$queue_status" "$final_state" "$variant_id"
    done < "$recent_file"
    if [ "$recent_shown" -eq 0 ]; then
      printf -- '- none\n'
    fi
  } > "$markdown_file"

  rm -f "$recent_file" "$top_modes_file"
}

mr_quality_scorecard_maybe_raise_regression_proposal() {
  run_mode=$1
  quality_score=$2
  delta_score=$3
  queue_status=$4
  final_state=$5
  regression_window=6
  regression_cooldown_sec=3600
  case "$run_mode" in
    ""|unknown)
      return 0
      ;;
  esac
  if [ "$queue_status" = "awaiting_decision" ] || [ "$queue_status" = "awaiting_approval" ]; then
    return 0
  fi
  should_raise=$(awk -v quality_score="$quality_score" -v delta_score="$delta_score" -v final_state="$final_state" '
    BEGIN {
      q = quality_score + 0.0
      d = delta_score + 0.0
      if (final_state != "DONE" && q < 0.55) {
        print "1"
      } else if (d <= -0.080 && q < 0.60) {
        print "1"
      } else {
        print "0"
      }
    }
  ')
  if [ "$should_raise" != "1" ]; then
    return 0
  fi

  current_severe=$(awk -v quality_score="$quality_score" -v delta_score="$delta_score" -v final_state="$final_state" '
    BEGIN {
      q = quality_score + 0.0
      d = delta_score + 0.0
      if ((final_state != "DONE" && q < 0.50) || (d <= -0.120 && q < 0.55)) {
        print "1"
      } else {
        print "0"
      }
    }
  ')
  if [ "$current_severe" != "1" ]; then
    stats_row=$(mr_quality_scorecard_recent_regression_stats_for_mode "$run_mode" "$regression_window")
    tab_char=$(printf '\t')
    recent_total=0
    recent_regressive=0
    recent_severe=0
    recent_avg_delta="0.000"
    old_ifs=$IFS
    IFS="$tab_char"
    set -- $stats_row
    IFS=$old_ifs
    recent_total=$(mr_nonnegative_int_or "${1:-0}" "0")
    recent_regressive=$(mr_nonnegative_int_or "${2:-0}" "0")
    recent_severe=$(mr_nonnegative_int_or "${3:-0}" "0")
    recent_avg_delta=$(trim "${4:-0.000}")
    if [ "$recent_total" -lt 4 ] || [ "$recent_regressive" -lt 2 ]; then
      return 0
    fi
  else
    recent_total=0
    recent_regressive=0
    recent_severe=0
    recent_avg_delta="0.000"
  fi

  cooldown_remaining=$(mr_quality_scorecard_regression_cooldown_remaining_sec "$run_mode" "$regression_cooldown_sec")
  case "$cooldown_remaining" in
    ""|*[!0-9]*) cooldown_remaining=0 ;;
  esac
  if [ "$cooldown_remaining" -gt 0 ]; then
    return 0
  fi

  category_id=$(mr_failure_taxonomy_top_category_for_mode "$run_mode" "24")
  category_id=$(trim "$category_id")
  if [ "$category_id" = "unknown" ]; then
    category_id=""
  fi
  if [ -n "$category_id" ] && mr_improvement_proposal_exists_for_category_and_mode "$category_id" "$run_mode" "quality-scorecard"; then
    return 0
  fi
  title_text="Investigate quality regression in ${run_mode} mode"
  rationale_text="Quality score regressed (quality=${quality_score}, delta=${delta_score}) with final_state=${final_state}; recent_window=${regression_window} total=${recent_total} regressive=${recent_regressive} severe=${recent_severe} avg_delta=${recent_avg_delta}."
  change_text="Review recent failures and tighten controller policy/verification flow for ${run_mode} mode to recover quality and reduce repeated breakdowns."
  scope_text="controller-loop"
  if [ "$category_id" = "verification-regression" ]; then
    scope_text="verification"
  fi
  risk_text="medium"
  if [ "$current_severe" = "1" ]; then
    risk_text="high"
  fi
  proposal_id=$(mr_improvement_proposal_create "$title_text" "$rationale_text" "$change_text" "$scope_text" "$risk_text" "quality-scorecard" "$category_id" "$run_mode" 2>/dev/null || true)
  if [ -n "$proposal_id" ]; then
    mr_quality_scorecard_set_regression_cooldown_for_mode "$run_mode" >/dev/null 2>&1 || true
  fi
}

mr_quality_scorecard_record_entry() {
  variant_id=$(mr_sanitize_inline "$1")
  run_id=$(trim "$2")
  run_mode=$(mr_sanitize_inline "$3")
  queue_status=$(mr_sanitize_inline "$4")
  final_state=$(mr_sanitize_inline "$5")
  quality_score=$(trim "$6")
  run_elapsed_sec=$(mr_nonnegative_int_or "$7" "0")
  iteration_count=$(mr_nonnegative_int_or "$8" "0")
  decision_requested=$(mr_bool_norm "$9")
  failure_count=$(mr_nonnegative_int_or "${10}" "0")

  [ -n "$variant_id" ] || variant_id="$(mr_controller_variant_active_id)"
  [ -n "$run_mode" ] || run_mode="unknown"
  case "$quality_score" in
    ""|*[!0-9.]*)
      quality_score="0.000"
      ;;
  esac

  entries_file=$(mr_quality_scorecard_entries_file)
  [ -f "$entries_file" ] || : > "$entries_file"
  previous_quality=$(mr_quality_scorecard_last_quality_for_mode "$run_mode" "$run_id")
  if [ -z "$previous_quality" ]; then
    previous_quality="0.000"
  fi
  delta_score=$(awk -v quality_score="$quality_score" -v previous_quality="$previous_quality" '
    BEGIN {
      delta = (quality_score + 0.0) - (previous_quality + 0.0)
      printf "%.3f", delta
    }
  ')

  now_epoch=$(mr_now_epoch)
  now_iso=$(mr_now_iso)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" \
    "$now_iso" \
    "$variant_id" \
    "$run_id" \
    "$run_mode" \
    "$queue_status" \
    "$final_state" \
    "$quality_score" \
    "$delta_score" \
    "$run_elapsed_sec" \
    "$iteration_count" \
    "$failure_count" \
    "$decision_requested" >> "$entries_file"

  mr_quality_scorecard_refresh_markdown
  mr_quality_scorecard_maybe_raise_regression_proposal "$run_mode" "$quality_score" "$delta_score" "$queue_status" "$final_state"
}

mr_controller_variants_items_json() {
  max_rows=$1
  case "$max_rows" in
    ""|*[!0-9]*) max_rows=30 ;;
  esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  variant_dirs=$(find "$(mr_controller_variants_dir)" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  printf '['
  first=1
  shown=0
  if [ -n "$variant_dirs" ]; then
    printf '%s\n' "$variant_dirs" | while IFS= read -r variant_dir; do
      [ -d "$variant_dir" ] || continue
      meta_file="$variant_dir/meta.env"
      [ -f "$meta_file" ] || continue
      shown=$((shown + 1))
      if [ "$shown" -gt "$max_rows" ]; then
        break
      fi
      variant_id=$(mr_env_get "$meta_file" "id" "$(basename "$variant_dir")")
      variant_name=$(mr_env_get "$meta_file" "name" "$variant_id")
      variant_status=$(mr_env_get "$meta_file" "status" "standby")
      variant_kind=$(mr_env_get "$meta_file" "kind" "manual")
      parent_id=$(mr_env_get "$meta_file" "parent_id" "")
      source_proposal=$(mr_env_get "$meta_file" "source_proposal" "")
      scope_value=$(mr_env_get "$meta_file" "scope" "other")
      risk_value=$(mr_env_get "$meta_file" "risk_level" "medium")
      created_at=$(mr_env_get "$meta_file" "created_at" "")
      updated_at=$(mr_env_get "$meta_file" "updated_at" "")
      last_seen_at=$(mr_env_get "$meta_file" "last_seen_at" "")
      instructions=$(mr_env_get "$meta_file" "instructions" "")
      runs=$(mr_nonnegative_int_or "$(mr_env_get "$meta_file" "runs" "0")" "0")
      successes=$(mr_nonnegative_int_or "$(mr_env_get "$meta_file" "successes" "0")" "0")
      avg_quality=$(mr_env_get "$meta_file" "avg_quality" "0.000")
      success_rate=$(awk -v runs="$runs" -v successes="$successes" '
        BEGIN {
          if (runs <= 0) {
            printf "0.0"
          } else {
            printf "%.1f", (successes * 100.0) / runs
          }
        }
      ')
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"id":"%s","name":"%s","status":"%s","kind":"%s","parent_id":"%s","source_proposal":"%s","scope":"%s","risk_level":"%s","created_at":"%s","updated_at":"%s","last_seen_at":"%s","instructions":"%s","runs":"%s","successes":"%s","avg_quality":"%s","success_rate_pct":"%s"}' \
        "$(json_escape "$variant_id")" \
        "$(json_escape "$variant_name")" \
        "$(json_escape "$variant_status")" \
        "$(json_escape "$variant_kind")" \
        "$(json_escape "$parent_id")" \
        "$(json_escape "$source_proposal")" \
        "$(json_escape "$scope_value")" \
        "$(json_escape "$risk_value")" \
        "$(json_escape "$created_at")" \
        "$(json_escape "$updated_at")" \
        "$(json_escape "$last_seen_at")" \
        "$(json_escape "$instructions")" \
        "$(json_escape "$runs")" \
        "$(json_escape "$successes")" \
        "$(json_escape "$avg_quality")" \
        "$(json_escape "$success_rate")"
    done
  fi
  printf ']'
}

mr_controller_variants_compare_json() {
  active_id=$(mr_controller_variant_active_id)
  candidate_id=$(mr_controller_variant_latest_candidate_id)
  min_runs=$(mr_controller_variant_sample_min_runs_for_promotion)

  active_runs=0
  active_avg="0.000"
  if mr_controller_variant_exists "$active_id"; then
    active_meta=$(mr_controller_variant_meta_file "$active_id")
    active_runs=$(mr_nonnegative_int_or "$(mr_env_get "$active_meta" "runs" "0")" "0")
    active_avg=$(mr_env_get "$active_meta" "avg_quality" "0.000")
  fi

  candidate_runs=0
  candidate_avg="0.000"
  if [ -n "$candidate_id" ] && mr_controller_variant_exists "$candidate_id"; then
    candidate_meta=$(mr_controller_variant_meta_file "$candidate_id")
    candidate_runs=$(mr_nonnegative_int_or "$(mr_env_get "$candidate_meta" "runs" "0")" "0")
    candidate_avg=$(mr_env_get "$candidate_meta" "avg_quality" "0.000")
  fi

  quality_delta=$(awk -v candidate_avg="$candidate_avg" -v active_avg="$active_avg" '
    BEGIN {
      delta = (candidate_avg + 0.0) - (active_avg + 0.0)
      printf "%.3f", delta
    }
  ')
  recommendation="insufficient-data"
  if [ -z "$candidate_id" ]; then
    recommendation="no-candidate"
  elif [ "$candidate_runs" -lt "$min_runs" ]; then
    recommendation="collect-more-samples"
  else
    recommendation=$(awk -v quality_delta="$quality_delta" '
      BEGIN {
        if ((quality_delta + 0.0) >= 0.03) {
          printf "promote-candidate"
        } else if ((quality_delta + 0.0) <= -0.03) {
          printf "rollback-candidate"
        } else {
          printf "hold"
        }
      }
    ')
  fi

  printf '{"active_id":"%s","candidate_id":"%s","active_runs":"%s","candidate_runs":"%s","active_avg_quality":"%s","candidate_avg_quality":"%s","quality_delta":"%s","sample_min_runs_for_promotion":"%s","recommendation":"%s"}' \
    "$(json_escape "$active_id")" \
    "$(json_escape "$candidate_id")" \
    "$(json_escape "$active_runs")" \
    "$(json_escape "$candidate_runs")" \
    "$(json_escape "$active_avg")" \
    "$(json_escape "$candidate_avg")" \
    "$(json_escape "$quality_delta")" \
    "$(json_escape "$min_runs")" \
    "$(json_escape "$recommendation")"
}

mr_controller_variants_state_json() {
  state_file=$(mr_controller_variants_state_file)
  active_variant_id=$(mr_controller_variant_active_id)
  previous_variant_id=$(mr_controller_variant_previous_active_id)
  sample_rate_percent=$(mr_controller_variant_sample_rate_percent)
  max_sample_size=$(mr_controller_variant_max_sample_size)
  min_runs_for_promotion=$(mr_controller_variant_sample_min_runs_for_promotion)
  updated_at=$(mr_env_get "$state_file" "updated_at" "")
  printf '{"active_variant_id":"%s","previous_active_variant_id":"%s","sample_rate_percent":"%s","max_sample_size":"%s","sample_min_runs_for_promotion":"%s","updated_at":"%s","quality_compare":%s,"items":%s}' \
    "$(json_escape "$active_variant_id")" \
    "$(json_escape "$previous_variant_id")" \
    "$(json_escape "$sample_rate_percent")" \
    "$(json_escape "$max_sample_size")" \
    "$(json_escape "$min_runs_for_promotion")" \
    "$(json_escape "$updated_at")" \
    "$(mr_controller_variants_compare_json)" \
    "$(mr_controller_variants_items_json "30")"
}

mr_quality_scorecard_recent_json() {
  max_rows=$1
  case "$max_rows" in ""|*[!0-9]*) max_rows=8 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi
  entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -s "$entries_file" ]; then
    printf '[]'
    return 0
  fi
  recent_file=$(mktemp)
  tail -n "$max_rows" "$entries_file" > "$recent_file" 2>/dev/null || : > "$recent_file"
  tab_char=$(printf '\t')
  printf '['
  first=1
  while IFS="$tab_char" read -r epoch_value iso_value variant_id run_id run_mode queue_status final_state quality_score delta_score run_elapsed iteration_count failure_count decision_requested || [ -n "$iso_value$run_mode$quality_score" ]; do
    [ -n "$iso_value$run_mode$quality_score" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"timestamp":"%s","variant_id":"%s","run_id":"%s","run_mode":"%s","queue_status":"%s","final_state":"%s","quality_score":"%s","delta_score":"%s","run_elapsed_sec":"%s","iteration_count":"%s","failure_count":"%s","decision_requested":%s}' \
      "$(json_escape "$iso_value")" \
      "$(json_escape "$variant_id")" \
      "$(json_escape "$run_id")" \
      "$(json_escape "$run_mode")" \
      "$(json_escape "$queue_status")" \
      "$(json_escape "$final_state")" \
      "$(json_escape "$quality_score")" \
      "$(json_escape "$delta_score")" \
      "$(json_escape "$run_elapsed")" \
      "$(json_escape "$iteration_count")" \
      "$(json_escape "$failure_count")" \
      "$(mr_bool_norm "$decision_requested")"
  done < "$recent_file"
  printf ']'
  rm -f "$recent_file"
}

mr_quality_scorecard_state_json() {
  entries_file=$(mr_quality_scorecard_entries_file)
  markdown_file=$(mr_quality_scorecard_markdown_file)
  total_runs=0
  overall_avg="0.000"
  last_updated=""
  if [ -f "$entries_file" ]; then
    total_runs=$(wc -l < "$entries_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
    case "$total_runs" in ""|*[!0-9]*) total_runs=0 ;; esac
    if [ "$total_runs" -gt 0 ]; then
      tab_char=$(printf '\t')
      last_updated=$(tail -n 1 "$entries_file" 2>/dev/null | awk -F"$tab_char" '{ print $2 }')
      overall_avg=$(awk -F"$tab_char" '
        NF >= 8 { sum += ($8 + 0.0); count += 1 }
        END {
          if (count <= 0) {
            printf "0.000"
          } else {
            printf "%.3f", sum / count
          }
        }
      ' "$entries_file")
    fi
  fi
  markdown_preview=""
  if [ -f "$markdown_file" ]; then
    markdown_preview=$(sed -n '1,80p' "$markdown_file" 2>/dev/null || true)
  fi
  printf '{"total_runs":"%s","overall_avg_quality":"%s","last_updated":"%s","scorecard_path":"%s","markdown_preview":"%s","recent":%s}' \
    "$(json_escape "$total_runs")" \
    "$(json_escape "$overall_avg")" \
    "$(json_escape "$last_updated")" \
    "$(json_escape "$markdown_file")" \
    "$(json_escape "$markdown_preview")" \
    "$(mr_quality_scorecard_recent_json "8")"
}

mr_quality_scorecard_recent_summary_text() {
  max_rows=$1
  case "$max_rows" in ""|*[!0-9]*) max_rows=8 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -s "$entries_file" ]; then
    printf '%s' "none"
    return 0
  fi

  tab_char=$(printf '\t')
  last_row=$(tail -n 1 "$entries_file" 2>/dev/null || true)
  last_mode=$(printf '%s' "$last_row" | awk -F"$tab_char" '{ print $5 }')
  last_queue_status=$(printf '%s' "$last_row" | awk -F"$tab_char" '{ print $6 }')
  last_final_state=$(printf '%s' "$last_row" | awk -F"$tab_char" '{ print $7 }')
  last_quality=$(printf '%s' "$last_row" | awk -F"$tab_char" '{ print $8 }')
  last_delta=$(printf '%s' "$last_row" | awk -F"$tab_char" '{ print $9 }')
  last_mode=$(trim "$last_mode")
  last_queue_status=$(trim "$last_queue_status")
  last_final_state=$(trim "$last_final_state")
  last_quality=$(trim "$last_quality")
  last_delta=$(trim "$last_delta")
  [ -n "$last_mode" ] || last_mode="unknown"
  [ -n "$last_queue_status" ] || last_queue_status="unknown"
  [ -n "$last_final_state" ] || last_final_state="unknown"
  [ -n "$last_quality" ] || last_quality="0.000"
  [ -n "$last_delta" ] || last_delta="0.000"

  recent_avg=$(tail -n "$max_rows" "$entries_file" 2>/dev/null | awk -F"$tab_char" '
    NF >= 8 {
      sum += ($8 + 0.0)
      count += 1
    }
    END {
      if (count <= 0) {
        printf "0.000"
      } else {
        printf "%.3f", sum / count
      }
    }
  ')
  recent_count=$(tail -n "$max_rows" "$entries_file" 2>/dev/null | wc -l | tr -d '[:space:]')
  case "$recent_count" in ""|*[!0-9]*) recent_count=0 ;; esac

  printf '%s' "last_mode=${last_mode}; last_quality=${last_quality}; last_delta=${last_delta}; last_status=${last_queue_status}/${last_final_state}; recent_avg=${recent_avg} (n=${recent_count})"
}

mr_quality_scorecard_guardrail_text() {
  max_rows=$1
  case "$max_rows" in ""|*[!0-9]*) max_rows=8 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi

  entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -s "$entries_file" ]; then
    printf '%s' "none"
    return 0
  fi

  tab_char=$(printf '\t')
  metrics=$(tail -n "$max_rows" "$entries_file" 2>/dev/null | awk -F"$tab_char" '
    NF >= 9 {
      sum += ($8 + 0.0)
      count += 1
      if (($9 + 0.0) < 0) {
        neg += 1
      }
      last_quality = ($8 + 0.0)
      last_delta = ($9 + 0.0)
      last_queue = $6
      last_final = $7
    }
    END {
      if (count <= 0) {
        printf "0.000\t0\t0\t0.000\t0.000\tunknown\tunknown"
      } else {
        printf "%.3f\t%d\t%d\t%.3f\t%.3f\t%s\t%s", sum / count, count, neg, last_quality, last_delta, last_queue, last_final
      }
    }
  ')

  avg_quality="0.000"
  count_rows=0
  neg_count=0
  last_quality="0.000"
  last_delta="0.000"
  last_queue="unknown"
  last_final="unknown"
  IFS="$(printf '\t')" read -r avg_quality count_rows neg_count last_quality last_delta last_queue last_final <<EOF
$metrics
EOF

  concern=0
  reasons=""
  if awk -v q="$last_quality" 'BEGIN { exit ((q + 0.0) < 0.55 ? 0 : 1) }'; then
    concern=1
    reasons="last_quality<0.55"
  fi
  if awk -v d="$last_delta" 'BEGIN { exit ((d + 0.0) <= -0.080 ? 0 : 1) }'; then
    concern=1
    if [ -n "$reasons" ]; then
      reasons="${reasons},"
    fi
    reasons="${reasons}last_delta<=-0.080"
  fi
  if [ "$count_rows" -gt 0 ] && [ $((neg_count * 2)) -ge "$count_rows" ]; then
    concern=1
    if [ -n "$reasons" ]; then
      reasons="${reasons},"
    fi
    reasons="${reasons}negative-delta-majority"
  fi
  if awk -v q="$avg_quality" 'BEGIN { exit ((q + 0.0) < 0.62 ? 0 : 1) }'; then
    concern=1
    if [ -n "$reasons" ]; then
      reasons="${reasons},"
    fi
    reasons="${reasons}recent_avg<0.62"
  fi

  if [ "$concern" != "1" ]; then
    printf '%s' "none"
    return 0
  fi

  printf '%s' "Quality regression pressure (${reasons}). Tighten completion criteria, verify each change slice, and avoid DONE_CLAIM until evidence is explicit."
}

mr_runtime_learning_guardrails_text() {
  failure_guardrails=$(mr_failure_taxonomy_recent_guardrails_text "8" "2")
  quality_guardrail=$(mr_quality_scorecard_guardrail_text "8")
  failure_guardrails=$(trim "$failure_guardrails")
  quality_guardrail=$(trim "$quality_guardrail")

  if [ -z "$failure_guardrails" ] || [ "$failure_guardrails" = "none" ]; then
    failure_guardrails=""
  fi
  if [ -z "$quality_guardrail" ] || [ "$quality_guardrail" = "none" ]; then
    quality_guardrail=""
  fi

  if [ -z "$failure_guardrails$quality_guardrail" ]; then
    printf '%s' "none"
    return 0
  fi

  if [ -n "$failure_guardrails" ] && [ -n "$quality_guardrail" ]; then
    printf '%s' "failure=${failure_guardrails}; quality=${quality_guardrail}"
    return 0
  fi

  if [ -n "$failure_guardrails" ]; then
    printf '%s' "failure=${failure_guardrails}"
    return 0
  fi
  printf '%s' "quality=${quality_guardrail}"
}

mr_controller_variant_bootstrap_default() {
  default_id=$(mr_controller_variant_default_id)
  if mr_controller_variant_exists "$default_id"; then
    return 0
  fi
  default_dir=$(mr_controller_variant_dir_for "$default_id")
  mkdir -p "$default_dir"
  now_iso=$(mr_now_iso)
  default_guidance=$(mr_sanitize_inline "Baseline typed-state controller policy: keep deterministic section formatting, safe mediated commands, small verifiable steps, and concise user-facing synthesis.")
  default_meta=$(mr_controller_variant_meta_file "$default_id")
  {
    printf 'id=%s\n' "$default_id"
    printf 'name=%s\n' "Default controller baseline"
    printf 'status=active\n'
    printf 'kind=baseline\n'
    printf 'parent_id=\n'
    printf 'source_proposal=\n'
    printf 'scope=controller-loop\n'
    printf 'risk_level=low\n'
    printf 'created_at=%s\n' "$now_iso"
    printf 'updated_at=%s\n' "$now_iso"
    printf 'last_seen_at=\n'
    printf 'instructions=%s\n' "$default_guidance"
    printf 'runs=0\n'
    printf 'successes=0\n'
    printf 'avg_quality=0.000\n'
  } > "$default_meta"
  default_notes=$(mr_controller_variant_notes_file "$default_id")
  {
    printf '# Controller Variant: %s\n\n' "$default_id"
    printf 'Created: %s\n\n' "$now_iso"
    printf '## Guidance\n- %s\n' "$default_guidance"
  } > "$default_notes"
}

mr_mode_seed_rows() {
  cat <<'EOF_ROWS'
mastermind-agency-composer|Mastermind / Agency-Composer|9|900|1|Allocates and composes agencies, dashboards, and cross-mode orchestration.|queue,git,run_events,mode_runtime|filesystem,network,agent_spawn|agent-spawner,panel-integrator,dashboard-builder
continuity-of-intention|Continuity-of-Intention|8|600|1|Maintains cross-session teleological alignment and corrects execution drift.|queue,run_events,mode_runtime,assumptions|filesystem|proceduralization,shadow-documentation,report-synthesizer
semantic-watchtower|Semantic Watchtower|7|1200|1|Monitors domains for semantic drift and emergent conceptual bifurcations.|queue,git,run_events,mode_runtime|network|market-research,report-synthesizer,latent-opportunity-harvester
ethical-statutory-compliance|Ethical / Statutory Compliance|10|900|1|Tracks legal and platform constraints and gates risky action chains.|queue,run_events,compliance,mode_runtime|network,filesystem|compliance-lookup,contract-analyzer,report-synthesizer
reputation-thermostat|Reputation Thermostat|6|1500|1|Models signal dilution and tunes costly-signal thresholds dynamically.|queue,run_events,mode_runtime|network|market-research,pitch-drafter,report-synthesizer
failure-mode-simulator|Failure-Mode Simulator|7|1200|1|Evolves collapse scenarios and stress-tests systemic resilience.|queue,git,run_events,mode_runtime|filesystem|simulation-runner,report-synthesizer,devils-liquidity-provider
epistemic-calibration|Epistemic Calibration|6|1800|0|Tracks forecast accuracy and updates strategic priors longitudinally.|run_events,mode_runtime,telemetry|filesystem|report-synthesizer,simulation-runner
adversarial-red-team-twin|Adversarial Red-Team Twin|9|900|1|Attempts to falsify system designs and surfaces exploit strategies.|queue,git,run_events,mode_runtime|filesystem,network|contract-analyzer,simulation-runner,proceduralization
narrative-coherence-engine|Narrative Coherence Engine|5|1800|0|Harmonizes symbolic and terminological consistency across artifacts.|run_events,mode_runtime|filesystem|shadow-documentation,pitch-drafter,report-synthesizer
chrono-budgeter|Chrono-Budgeter|5|900|0|Allocates cognitive labor based on lagged ROI and queue pressure.|queue,run_events,mode_runtime|filesystem|devils-liquidity-provider,proceduralization,report-synthesizer
EOF_ROWS
}

mr_skill_seed_rows() {
  cat <<'EOF_ROWS'
proceduralization|Proceduralization|when manual success patterns repeat|filesystem|Observes repeatable workflows and codifies reusable scripts and runbooks.
grant-hunter|Grant-Hunter|when funding search is requested|network|Tracks funding opportunities and drafts submission-ready packages.
negotiation-doppelganger|Negotiation Doppelganger|when negotiation strategy is requested|filesystem|Simulates counterparties and generates BATNA trees.
devils-liquidity-provider|Devils Liquidity Provider|when execution stalls|filesystem|Injects substitute actions to unblock delivery.
shadow-documentation|Shadow Documentation|when implementation changes frequently|filesystem|Continuously maintains READMEs and architecture diagrams.
latent-opportunity-harvester|Latent Opportunity Harvester|when cross-domain synthesis is valuable|network|Scans for complementarities and latent slack opportunities.
dashboard-builder|Dashboard Builder|when telemetry needs visualization|filesystem|Builds modular synoptic dashboard definitions.
agent-spawner|Agent Spawner|when sub-agents are needed|agent_spawn,filesystem|Instantiates scoped child agents from templates.
panel-integrator|Panel Integrator|when multi-agent telemetry should unify|filesystem|Binds multi-agent telemetry streams into unified panels.
compliance-lookup|Compliance Lookup|when legal or policy checks are needed|network|Retrieves statutory and platform-policy constraints on demand.
report-synthesizer|Report Synthesizer|when structured reporting is needed|filesystem|Produces concise structured summaries from multi-agent outputs.
market-research|Market Research|when demand or competition scans are requested|network|Runs bounded demand and competitor analyses.
contract-analyzer|Contract Analyzer|when agreement risk review is needed|filesystem|Parses agreements for obligations and risk surfaces.
pitch-drafter|Pitch Drafter|when stakeholder narrative is needed|filesystem|Drafts tailored pitches for specific audiences.
data-etl|Data ETL|when data routing or ingestion is needed|filesystem,network|Ingests, normalizes, and routes structured or unstructured data.
web-scraper|Web-Scraper|when external stream extraction is needed|network|Extracts web data under policy constraints.
simulation-runner|Simulation Runner|when scenario analysis is requested|filesystem|Executes bounded scenario and stress simulations.
codegen-infra-spin-up|Codegen / Infra Spin-Up|when infrastructure artifacts are requested|filesystem,network,agent_spawn|Generates infrastructure code and deployment scaffolds.
EOF_ROWS
}

mr_mode_policy_template() {
  mode_name=$1
  mode_desc=$2
  cat <<EOF_POLICY
# $mode_name Policy

## Intent
$mode_desc

## Governance
- This Mode is stateful and acts as a governor.
- It may orchestrate Skills under explicit policy constraints.
- It maintains persistent goal-state and long-horizon memory in its namespace.
- It may emit interrupt requests when interrupt rights are enabled.

## Constraints
- Respect legal, ethical, and platform policy boundaries.
- Prefer reversible actions unless explicit authorization is present.
- Record every scheduler iteration in governance logs.
EOF_POLICY
}

mr_skill_policy_template() {
  skill_name=$1
  skill_desc=$2
  cat <<EOF_POLICY
# $skill_name

## Purpose
$skill_desc

## Skill Contract
- Stateless actuator: no long-term memory persistence.
- No interrupt authority.
- Bounded execution within declared tools and mode policy constraints.
- Inputs and outputs must conform to the declared schema.
EOF_POLICY
}

mr_seed_mode_bundle() {
  mode_id=$1
  mode_name=$2
  mode_priority=$3
  mode_cadence=$4
  mode_interrupt=$5
  mode_desc=$6
  mode_subscriptions=$7
  mode_caps=$8
  mode_skills=$9

  mode_dir=$(mr_mode_dir_for "$mode_id")
  manifest_file=$(mr_mode_manifest_file "$mode_id")
  state_file=$(mr_mode_state_file "$mode_id")
  policy_file=$(mr_mode_policy_file "$mode_id")
  memory_dir=$(mr_mode_memory_dir "$mode_id")

  mkdir -p "$mode_dir"
  mkdir -p "$memory_dir"

  if [ ! -f "$manifest_file" ]; then
    {
      printf 'id=%s\n' "$mode_id"
      printf 'name=%s\n' "$(mr_sanitize_inline "$mode_name")"
      printf 'description=%s\n' "$(mr_sanitize_inline "$mode_desc")"
      printf 'default_priority=%s\n' "$(mr_positive_int_or "$mode_priority" "5")"
      printf 'default_cadence_sec=%s\n' "$(mr_positive_int_or "$mode_cadence" "900")"
      printf 'default_interrupt_rights=%s\n' "$(mr_bool_norm "$mode_interrupt")"
      printf 'default_subscriptions=%s\n' "$(mr_csv_normalize "$mode_subscriptions")"
      printf 'allowed_capabilities=%s\n' "$(mr_csv_normalize "$mode_caps")"
      printf 'recommended_skills=%s\n' "$(mr_csv_normalize "$mode_skills")"
      printf 'memory_namespace=%s\n' "$mode_id"
    } > "$manifest_file"
  fi

  if [ ! -f "$state_file" ]; then
    enabled_default=0
    case "$mode_id" in
      continuity-of-intention|ethical-statutory-compliance)
        enabled_default=1
        ;;
    esac
    {
      printf 'enabled=%s\n' "$enabled_default"
      printf 'priority=%s\n' "$(mr_env_get "$manifest_file" "default_priority" "5")"
      printf 'cadence_sec=%s\n' "$(mr_env_get "$manifest_file" "default_cadence_sec" "900")"
      printf 'interrupt_rights=%s\n' "$(mr_env_get "$manifest_file" "default_interrupt_rights" "0")"
      printf 'allow_queue_injection=0\n'
      printf 'goal_state=\n'
      printf 'status=idle\n'
      printf 'drift_score=0.00\n'
      printf 'last_tick=0\n'
      printf 'next_tick=0\n'
      printf 'last_skill_plan=\n'
      printf 'last_directive_count=0\n'
      printf 'last_directive_emits=0\n'
      printf 'last_directive_summary=none\n'
    } > "$state_file"
  fi

  if [ ! -f "$policy_file" ]; then
    mr_mode_policy_template "$mode_name" "$mode_desc" > "$policy_file"
  fi

  goal_file=$(mr_mode_goal_file "$mode_id")
  if [ ! -f "$goal_file" ]; then
    cat > "$goal_file" <<'EOF_GOAL'
# Goal State

- Pending explicit objective.
EOF_GOAL
  fi

  long_horizon_file=$(mr_mode_long_horizon_file "$mode_id")
  if [ ! -f "$long_horizon_file" ]; then
    cat > "$long_horizon_file" <<'EOF_LONG'
# Long-Horizon Memory

EOF_LONG
  fi

  mode_log_file=$(mr_mode_log_file "$mode_id")
  if [ ! -f "$mode_log_file" ]; then
    cat > "$mode_log_file" <<'EOF_LOG'
# Mode Log

EOF_LOG
  fi

  subscriptions_file=$(mr_mode_subscriptions_file "$mode_id")
  if [ ! -f "$subscriptions_file" ]; then
    printf '%s\n' "$(mr_env_get "$manifest_file" "default_subscriptions" "queue,run_events,mode_runtime")" > "$subscriptions_file"
  fi

  governance_file=$(mr_mode_ledgers_file "$mode_id")
  if [ ! -f "$governance_file" ]; then
    cat > "$governance_file" <<'EOF_GOV'
# Governance Ledger

EOF_GOV
  fi

  mode_events=$(mr_mode_event_queue_file "$mode_id")
  if [ ! -f "$mode_events" ]; then
    : > "$mode_events"
  fi

  mode_inbox_file=$(mr_mode_directive_inbox_file "$mode_id")
  if [ ! -f "$mode_inbox_file" ]; then
    : > "$mode_inbox_file"
  fi
  mode_cursor_file=$(mr_mode_directive_cursor_file "$mode_id")
  if [ ! -f "$mode_cursor_file" ]; then
    printf '0\n' > "$mode_cursor_file"
  fi
}

mr_seed_skill_bundle() {
  skill_id=$1
  skill_name=$2
  trigger_text=$3
  capabilities=$4
  description_text=$5

  skill_dir=$(mr_skill_dir_for "$skill_id")
  mkdir -p "$skill_dir"

  policy_file="$skill_dir/policy.md"
  trigger_file="$skill_dir/trigger.yaml"
  tools_file="$skill_dir/tools.json"
  schema_file="$skill_dir/output.schema.json"
  meta_file=$(mr_skill_meta_file "$skill_id")

  if [ ! -f "$policy_file" ]; then
    mr_skill_policy_template "$skill_name" "$description_text" > "$policy_file"
  fi

  if [ ! -f "$trigger_file" ]; then
    cat > "$trigger_file" <<EOF_TRIGGER
id: $skill_id
name: "$skill_name"
trigger:
  - "$trigger_text"
mode_required: true
stateless: true
interrupt_authority: false
EOF_TRIGGER
  fi

  if [ ! -f "$tools_file" ]; then
    tools_json=$(mr_csv_to_json_array "$capabilities")
    cat > "$tools_file" <<EOF_TOOLS
{
  "tools": $tools_json,
  "requires_mode_authorization": true,
  "stateless": true,
  "interrupt_authority": false,
  "persistent_memory": false
}
EOF_TOOLS
  fi

  if [ ! -f "$schema_file" ]; then
    cat > "$schema_file" <<EOF_SCHEMA
{
  "\$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "$skill_name output",
  "type": "object",
  "required": ["skill_id", "status", "summary", "actions"],
  "properties": {
    "skill_id": { "type": "string", "const": "$skill_id" },
    "status": { "type": "string", "enum": ["ok", "blocked", "needs_auth"] },
    "summary": { "type": "string" },
    "actions": { "type": "array", "items": { "type": "string" } },
    "artifacts": { "type": "array", "items": { "type": "string" } },
    "notes": { "type": "string" }
  },
  "additionalProperties": true
}
EOF_SCHEMA
  fi

  if [ ! -f "$meta_file" ]; then
    {
      printf 'id=%s\n' "$skill_id"
      printf 'name=%s\n' "$(mr_sanitize_inline "$skill_name")"
      printf 'trigger=%s\n' "$(mr_sanitize_inline "$trigger_text")"
      printf 'capabilities=%s\n' "$(mr_csv_normalize "$capabilities")"
      printf 'description=%s\n' "$(mr_sanitize_inline "$description_text")"
      printf 'stateless=1\n'
      printf 'interrupt_authority=0\n'
    } > "$meta_file"
  fi
}

mr_seed_dashboards() {
  dashboard_root=$(mr_dashboard_dir)
  mkdir -p "$dashboard_root"
  composites_file="$dashboard_root/composites.md"
  if [ ! -f "$composites_file" ]; then
    cat > "$composites_file" <<'EOF_COMP'
# Composite Dashboards

- Reputation Monitoring Panel
- Grant / Income Panel
- Oracle / Intel Panel
- Global Dashboard
EOF_COMP
  fi
}

mode_runtime_bootstrap() {
  mkdir -p "$(mr_modes_dir)"
  mkdir -p "$(mr_skills_dir)"
  mkdir -p "$(mr_bus_dir)"
  mkdir -p "$(mr_directives_dir)"
  mkdir -p "$(mr_dashboard_dir)"
  mkdir -p "$(mr_scheduler_dir)"
  mkdir -p "$(mr_telemetry_dir)"
  mkdir -p "$(mr_interrupts_dir)"
  mkdir -p "$(mr_failure_taxonomy_dir)"
  mkdir -p "$(mr_improvement_proposals_dir)"
  mkdir -p "$(mr_controller_variants_root)"
  mkdir -p "$(mr_controller_variants_dir)"
  mkdir -p "$(mr_quality_scorecard_dir)"

  scheduler_state=$(mr_scheduler_state_file)
  if [ ! -f "$scheduler_state" ]; then
    {
      printf 'last_tick=0\n'
      printf 'last_tick_iso=\n'
      printf 'ticks=0\n'
      printf 'last_due_modes=0\n'
      printf 'last_injections=0\n'
      printf 'last_directives_received=0\n'
      printf 'last_directives_emitted=0\n'
      printf 'last_summary=Scheduler initialized\n'
    } > "$scheduler_state"
  fi

  cooperation_log=$(mr_cooperation_log_file)
  if [ ! -f "$cooperation_log" ]; then
    : > "$cooperation_log"
  fi

  failure_events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -f "$failure_events_file" ]; then
    : > "$failure_events_file"
  fi

  failure_readme_file="$(mr_failure_taxonomy_dir)/README.md"
  if [ ! -f "$failure_readme_file" ]; then
    cat > "$failure_readme_file" <<'EOF_FAIL'
# Failure Taxonomy Store

- `events.tsv` stores normalized failure records from run loops.
- Rows are tab-separated: epoch, timestamp, category, surface, severity, mode, action, error, hypothesis, next-attempt.
- This store is read-only from the user UI and used to derive improvement proposals.
EOF_FAIL
  fi

  proposals_readme_file="$(mr_improvement_proposals_dir)/README.md"
  if [ ! -f "$proposals_readme_file" ]; then
    cat > "$proposals_readme_file" <<'EOF_PROP'
# Improvement Proposals Store

- Each proposal lives in `<proposal-id>/` with `meta.env` and `proposal.md`.
- Proposals are manually reviewed and manually applied from the UI.
- This subsystem does not auto-edit execution pipelines.
EOF_PROP
  fi

  controller_state_file=$(mr_controller_variants_state_file)
  if [ ! -f "$controller_state_file" ]; then
    {
      printf 'active_variant_id=%s\n' "$(mr_controller_variant_default_id)"
      printf 'previous_active_variant_id=\n'
      printf 'sample_rate_percent=35\n'
      printf 'max_sample_size=40\n'
      printf 'sample_min_runs_for_promotion=6\n'
      printf 'updated_at=%s\n' "$(mr_now_iso)"
    } > "$controller_state_file"
  fi

  controller_telemetry_file=$(mr_controller_variants_telemetry_file)
  if [ ! -f "$controller_telemetry_file" ]; then
    : > "$controller_telemetry_file"
  fi

  controller_readme_file="$(mr_controller_variants_root)/README.md"
  if [ ! -f "$controller_readme_file" ]; then
    cat > "$controller_readme_file" <<'EOF_CTRL'
# Controller Variants Store

- `variants/<variant-id>/meta.env` stores versioned controller prompt-variant metadata and quality aggregates.
- `variants/<variant-id>/guidance.md` stores human-readable variant intent.
- `state.env` stores active/previous variant ids plus A/B sampling configuration.
- `telemetry.tsv` stores run-level quality telemetry for before/after comparison.
EOF_CTRL
  fi

  quality_entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -f "$quality_entries_file" ]; then
    : > "$quality_entries_file"
  fi
  quality_cooldowns_file=$(mr_quality_scorecard_regression_cooldowns_file)
  if [ ! -f "$quality_cooldowns_file" ]; then
    : > "$quality_cooldowns_file"
  fi

  quality_readme_file="$(mr_quality_scorecard_dir)/README.md"
  if [ ! -f "$quality_readme_file" ]; then
    cat > "$quality_readme_file" <<'EOF_SCORE'
# Quality Scorecard Store

- `entries.tsv` stores run-level intelligence quality snapshots and deltas.
- `scorecard.md` stores a human-readable summary of trends and recent runs.
- `regression-proposal-cooldowns.tsv` stores per-mode cooldown state that prevents repeated proposal spam.
- Regressions can trigger manually-reviewable improvement proposals tagged to recent failure categories.
EOF_SCORE
  fi

  mr_controller_variant_bootstrap_default
  mr_quality_scorecard_refresh_markdown >/dev/null 2>&1 || true

  mr_mode_seed_rows | while IFS='|' read -r mode_id mode_name mode_priority mode_cadence mode_interrupt mode_desc mode_subscriptions mode_caps mode_skills; do
    [ -n "$mode_id" ] || continue
    mr_seed_mode_bundle "$mode_id" "$mode_name" "$mode_priority" "$mode_cadence" "$mode_interrupt" "$mode_desc" "$mode_subscriptions" "$mode_caps" "$mode_skills"
  done

  mr_skill_seed_rows | while IFS='|' read -r skill_id skill_name trigger_text capabilities description_text; do
    [ -n "$skill_id" ] || continue
    mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  done

  mr_seed_dashboards
}

mr_mode_exists() {
  mode_id=$1
  mode_dir=$(mr_mode_dir_for "$mode_id")
  [ -d "$mode_dir" ]
}

mr_skill_exists() {
  skill_id=$1
  skill_dir=$(mr_skill_dir_for "$skill_id")
  [ -d "$skill_dir" ]
}

mr_mode_allowed_capabilities() {
  mode_id=$1
  manifest_file=$(mr_mode_manifest_file "$mode_id")
  mr_env_get "$manifest_file" "allowed_capabilities" ""
}

mr_mode_recommended_skills() {
  mode_id=$1
  manifest_file=$(mr_mode_manifest_file "$mode_id")
  mr_env_get "$manifest_file" "recommended_skills" ""
}

mr_mode_subscriptions_current() {
  mode_id=$1
  subs_file=$(mr_mode_subscriptions_file "$mode_id")
  if [ -f "$subs_file" ]; then
    mr_csv_normalize "$(cat "$subs_file" 2>/dev/null || true)"
    return 0
  fi
  manifest_file=$(mr_mode_manifest_file "$mode_id")
  mr_env_get "$manifest_file" "default_subscriptions" "queue,run_events,mode_runtime"
}

mr_list_mode_ids() {
  for mode_dir in "$(mr_modes_dir)"/*; do
    [ -d "$mode_dir" ] || continue
    basename "$mode_dir"
  done | sort
}

mr_list_skill_ids() {
  for skill_dir in "$(mr_skills_dir)"/*; do
    [ -d "$skill_dir" ] || continue
    basename "$skill_dir"
  done | sort
}

mr_queue_metrics() {
  workspaces=0
  conversations=0
  pending=0
  running=0
  done=0
  errors=0

  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    workspaces=$((workspaces + 1))
    conv_root="$ws_dir/conversations"
    [ -d "$conv_root" ] || continue
    for conv_dir in "$conv_root"/*; do
      [ -d "$conv_dir" ] || continue
      conversations=$((conversations + 1))
      queue_info=$(queue_state_for_conversation "$conv_dir")
      q_pending=$(kv_get "pending" "$queue_info")
      q_running=$(kv_get "running" "$queue_info")
      q_done=$(kv_get "done" "$queue_info")
      q_status=$(kv_get "last_status" "$queue_info")
      case "$q_pending" in ""|*[!0-9]*) q_pending=0 ;; esac
      case "$q_running" in ""|*[!0-9]*) q_running=0 ;; esac
      case "$q_done" in ""|*[!0-9]*) q_done=0 ;; esac
      pending=$((pending + q_pending))
      running=$((running + q_running))
      done=$((done + q_done))
      case "$q_status" in
        error)
          errors=$((errors + 1))
          ;;
      esac
    done
  done

  {
    printf 'workspaces=%s\n' "$workspaces"
    printf 'conversations=%s\n' "$conversations"
    printf 'pending=%s\n' "$pending"
    printf 'running=%s\n' "$running"
    printf 'done=%s\n' "$done"
    printf 'errors=%s\n' "$errors"
  }
}

mr_feed_payload() {
  feed_id=$1
  timestamp=$2

  case "$feed_id" in
    queue)
      metrics=$(mr_queue_metrics)
      pending=$(printf '%s\n' "$metrics" | sed -n 's/^pending=//p' | sed -n '1p')
      running=$(printf '%s\n' "$metrics" | sed -n 's/^running=//p' | sed -n '1p')
      errors=$(printf '%s\n' "$metrics" | sed -n 's/^errors=//p' | sed -n '1p')
      printf '[%s] queue pending=%s running=%s errors=%s' "$timestamp" "${pending:-0}" "${running:-0}" "${errors:-0}"
      ;;
    git)
      dirty_count=0
      for ws_dir in "$workspaces_dir"/*; do
        [ -d "$ws_dir" ] || continue
        ws_path=$(read_file_line "$ws_dir/path" "")
        if [ -n "$ws_path" ] && [ -d "$ws_path/.git" ]; then
          status_out=$( (cd "$ws_path" && git status --short 2>/dev/null) || true )
          if [ -n "$(trim "$status_out")" ]; then
            dirty_count=$((dirty_count + 1))
          fi
        fi
      done
      printf '[%s] git dirty_workspaces=%s' "$timestamp" "$dirty_count"
      ;;
    run_events)
      run_event_count=0
      for ws_dir in "$workspaces_dir"/*; do
        [ -d "$ws_dir" ] || continue
        conv_root="$ws_dir/conversations"
        [ -d "$conv_root" ] || continue
        for conv_dir in "$conv_root"/*; do
          [ -d "$conv_dir" ] || continue
          run_events_file="$conv_dir/run_events.ndjson"
          if [ -f "$run_events_file" ]; then
            count=$(wc -l < "$run_events_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
            case "$count" in ""|*[!0-9]*) count=0 ;; esac
            run_event_count=$((run_event_count + count))
          fi
        done
      done
      printf '[%s] run_events total=%s' "$timestamp" "$run_event_count"
      ;;
    mode_runtime)
      ticks=$(mr_env_get "$(mr_scheduler_state_file)" "ticks" "0")
      summary=$(mr_env_get "$(mr_scheduler_state_file)" "last_summary" "none")
      printf '[%s] scheduler ticks=%s summary=%s' "$timestamp" "$ticks" "$summary"
      ;;
    assumptions)
      printf '[%s] assumptions feed: active' "$timestamp"
      ;;
    telemetry)
      printf '[%s] telemetry feed: active' "$timestamp"
      ;;
    compliance)
      printf '[%s] compliance feed: active' "$timestamp"
      ;;
    *)
      printf '[%s] %s feed: no adapter' "$timestamp" "$feed_id"
      ;;
  esac
}

mr_log_mode_iteration() {
  mode_id=$1
  status_text=$2
  drift_score=$3
  skills_text=$4
  telemetry_text=$5
  injected_item=$6
  directives_received=${7:-0}
  directives_emitted=${8:-0}
  directive_summary=${9:-none}

  timestamp=$(mr_now_iso)
  mode_log_file=$(mr_mode_log_file "$mode_id")
  long_file=$(mr_mode_long_horizon_file "$mode_id")
  governance_file=$(mr_mode_ledgers_file "$mode_id")

  {
    printf '## %s\n' "$timestamp"
    printf 'Status: %s\n' "$status_text"
    printf 'Drift score: %s\n' "$drift_score"
    printf 'Skill plan: %s\n' "$skills_text"
    printf 'Telemetry: %s\n' "$telemetry_text"
    printf 'Directives received: %s\n' "$directives_received"
    printf 'Directives emitted: %s\n' "$directives_emitted"
    printf 'Directive summary: %s\n' "$directive_summary"
    if [ -n "$(trim "$injected_item")" ]; then
      printf 'Queue injection: %s\n' "$injected_item"
    fi
    printf '\n'
  } >> "$mode_log_file"

  {
    printf -- '- %s status=%s drift=%s skills=%s directives_in=%s directives_out=%s\n' \
      "$timestamp" "$status_text" "$drift_score" "$skills_text" "$directives_received" "$directives_emitted"
  } >> "$long_file"

  {
    printf '%s\tmode=%s\tstatus=%s\tdrift=%s\tskills=%s\tdirectives_in=%s\tdirectives_out=%s\tinjected=%s\n' \
      "$timestamp" "$mode_id" "$status_text" "$drift_score" "$skills_text" "$directives_received" "$directives_emitted" "${injected_item:-none}"
  } >> "$governance_file"
}

mr_queue_signals_triplet() {
  if [ -n "${MR_QUEUE_SIGNALS_OVERRIDE:-}" ]; then
    printf '%s' "$MR_QUEUE_SIGNALS_OVERRIDE"
    return 0
  fi
  metrics=$(mr_queue_metrics)
  pending=$(printf '%s\n' "$metrics" | sed -n 's/^pending=//p' | sed -n '1p')
  running=$(printf '%s\n' "$metrics" | sed -n 's/^running=//p' | sed -n '1p')
  errors=$(printf '%s\n' "$metrics" | sed -n 's/^errors=//p' | sed -n '1p')
  case "$pending" in ""|*[!0-9]*) pending=0 ;; esac
  case "$running" in ""|*[!0-9]*) running=0 ;; esac
  case "$errors" in ""|*[!0-9]*) errors=0 ;; esac
  printf '%s|%s|%s' "$pending" "$running" "$errors"
}

mr_csv_first_n() {
  csv_raw=$1
  max_items=$2
  case "$max_items" in ""|*[!0-9]*) max_items=4 ;; esac
  if [ "$max_items" -le 0 ]; then
    printf '%s' ""
    return 0
  fi
  norm=$(mr_csv_normalize "$csv_raw")
  out=""
  count=0
  old_ifs=$IFS
  IFS=','
  for entry in $norm; do
    clean=$(trim "$entry")
    [ -n "$clean" ] || continue
    count=$((count + 1))
    if [ "$count" -gt "$max_items" ]; then
      break
    fi
    if [ -n "$out" ]; then
      out="$out,$clean"
    else
      out="$clean"
    fi
  done
  IFS=$old_ifs
  printf '%s' "$out"
}

mr_directive_payload_clean() {
  payload_raw=$1
  payload_clean=$(mr_sanitize_inline "$payload_raw" | tr '\t' ' ' | tr '|' '/' | sed 's/[[:space:]]\+/ /g')
  payload_clean=$(trim "$payload_clean")
  if [ -z "$payload_clean" ]; then
    payload_clean="no-payload"
  fi
  printf '%s' "$payload_clean" | awk 'BEGIN { ORS="" } { print substr($0, 1, 240) }'
}

mr_mode_recent_directive_exists() {
  from_mode=$1
  to_mode=$2
  directive_kind=$3
  directive_payload=$4
  max_age_sec=$5

  case "$max_age_sec" in
    ""|*[!0-9]*) max_age_sec=300 ;;
  esac

  coop_log=$(mr_cooperation_log_file)
  [ -f "$coop_log" ] || return 1

  now_epoch=$(mr_now_epoch)
  case "$now_epoch" in ""|*[!0-9]*) now_epoch=0 ;; esac

  tail -n 240 "$coop_log" 2>/dev/null | awk -F'\t' \
    -v now="$now_epoch" \
    -v max_age="$max_age_sec" \
    -v from="$from_mode" \
    -v to="$to_mode" \
    -v kind="$directive_kind" \
    -v payload="$directive_payload" '
      {
        epoch = $1 + 0
        if ($3 != from || $4 != to || $5 != kind || $7 != payload) {
          next
        }
        if (now <= 0) {
          print "1"
          exit 0
        }
        if (now - epoch <= max_age) {
          print "1"
          exit 0
        }
      }
    ' | grep -q '^1$'
}

mr_mode_emit_directive() {
  from_mode=$1
  to_mode=$2
  directive_kind=$3
  directive_priority=$4
  directive_payload_raw=$5
  ttl_sec=$6

  if ! valid_id "$from_mode" || ! valid_id "$to_mode"; then
    printf '%s' ""
    return 0
  fi
  if [ "$from_mode" = "$to_mode" ]; then
    printf '%s' ""
    return 0
  fi
  if ! mr_mode_exists "$from_mode" || ! mr_mode_exists "$to_mode"; then
    printf '%s' ""
    return 0
  fi

  directive_kind=$(printf '%s' "$directive_kind" | tr '[:upper:]' '[:lower:]')
  if [ -z "$(trim "$directive_kind")" ]; then
    directive_kind="coordination-note"
  fi

  case "$directive_priority" in
    ""|*[!0-9]*) directive_priority=5 ;;
  esac
  if [ "$directive_priority" -lt 1 ]; then
    directive_priority=1
  fi
  if [ "$directive_priority" -gt 10 ]; then
    directive_priority=10
  fi

  case "$ttl_sec" in
    ""|*[!0-9]*) ttl_sec=3600 ;;
  esac
  if [ "$ttl_sec" -lt 60 ]; then
    ttl_sec=60
  fi
  if [ "$ttl_sec" -gt 86400 ]; then
    ttl_sec=86400
  fi

  directive_payload=$(mr_directive_payload_clean "$directive_payload_raw")
  if mr_mode_recent_directive_exists "$from_mode" "$to_mode" "$directive_kind" "$directive_payload" "300"; then
    printf '%s' ""
    return 0
  fi

  now_epoch=$(mr_now_epoch)
  case "$now_epoch" in ""|*[!0-9]*) now_epoch=0 ;; esac
  now_iso=$(mr_now_iso)
  expires_epoch=$((now_epoch + ttl_sec))

  target_inbox=$(mr_mode_directive_inbox_file "$to_mode")
  coop_log=$(mr_cooperation_log_file)
  mkdir -p "$(mr_directives_dir)"
  [ -f "$target_inbox" ] || : > "$target_inbox"
  [ -f "$coop_log" ] || : > "$coop_log"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" "$now_iso" "$from_mode" "$directive_kind" "$directive_priority" "$directive_payload" "$expires_epoch" >> "$target_inbox"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now_epoch" "$now_iso" "$from_mode" "$to_mode" "$directive_kind" "$directive_priority" "$directive_payload" "$expires_epoch" >> "$coop_log"

  printf '%s' "${now_epoch}:${from_mode}->${to_mode}:${directive_kind}"
}

mr_mode_directive_hints_from_kind() {
  directive_kind=$1
  case "$directive_kind" in
    compliance-gate|risk-surface)
      printf '%s' "compliance-lookup,contract-analyzer,report-synthesizer"
      ;;
    throughput-rebalance|throttle-guidance)
      printf '%s' "devils-liquidity-provider,data-etl,proceduralization"
      ;;
    narrative-alignment|brand-coherence)
      printf '%s' "shadow-documentation,pitch-drafter,report-synthesizer"
      ;;
    resilience-probe|adversarial-probe)
      printf '%s' "simulation-runner,contract-analyzer,report-synthesizer"
      ;;
    intel-refresh|opportunity-scan)
      printf '%s' "market-research,latent-opportunity-harvester,report-synthesizer"
      ;;
    priority-escalation|trajectory-update)
      printf '%s' "report-synthesizer,proceduralization"
      ;;
    *)
      printf '%s' "report-synthesizer"
      ;;
  esac
}

mr_mode_consume_directives() {
  mode_id=$1
  max_items=$2
  case "$max_items" in
    ""|*[!0-9]*) max_items=8 ;;
  esac
  if [ "$max_items" -lt 1 ]; then
    max_items=1
  fi

  inbox_file=$(mr_mode_directive_inbox_file "$mode_id")
  cursor_file=$(mr_mode_directive_cursor_file "$mode_id")
  [ -f "$inbox_file" ] || {
    printf '%s' "0|none||0"
    return 0
  }
  [ -f "$cursor_file" ] || printf '0\n' > "$cursor_file"

  total_lines=$(wc -l < "$inbox_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
  case "$total_lines" in ""|*[!0-9]*) total_lines=0 ;; esac
  cursor_line=$(read_file_line "$cursor_file" "0")
  case "$cursor_line" in ""|*[!0-9]*) cursor_line=0 ;; esac

  if [ "$total_lines" -le "$cursor_line" ]; then
    printf '%s' "0|none||0"
    return 0
  fi

  start_line=$((cursor_line + 1))
  delta_file=$(mktemp)
  sed -n "${start_line},${total_lines}p" "$inbox_file" > "$delta_file"
  printf '%s\n' "$total_lines" > "$cursor_file"

  now_epoch=$(mr_now_epoch)
  case "$now_epoch" in ""|*[!0-9]*) now_epoch=0 ;; esac
  mode_events_file=$(mr_mode_event_queue_file "$mode_id")
  [ -f "$mode_events_file" ] || : > "$mode_events_file"

  directive_count=0
  summary=""
  skill_hints=""
  priority_boost=0
  summary_count=0

  while IFS="$(printf '\t')" read -r directive_epoch directive_iso from_mode directive_kind directive_priority directive_payload expires_epoch || [ -n "$directive_epoch$directive_kind$directive_payload" ]; do
    [ -n "$(trim "$directive_kind")" ] || continue
    case "$expires_epoch" in ""|*[!0-9]*) expires_epoch=0 ;; esac
    if [ "$expires_epoch" -gt 0 ] && [ "$now_epoch" -gt 0 ] && [ "$expires_epoch" -lt "$now_epoch" ]; then
      continue
    fi

    directive_count=$((directive_count + 1))
    if [ "$summary_count" -lt "$max_items" ]; then
      snippet=$(mr_directive_payload_clean "$directive_payload")
      summary_piece="${from_mode}:${directive_kind}(${snippet})"
      if [ -n "$summary" ]; then
        summary="$summary; $summary_piece"
      else
        summary="$summary_piece"
      fi
      summary_count=$((summary_count + 1))
    fi

    kind_hints=$(mr_mode_directive_hints_from_kind "$directive_kind")
    skill_hints=$(mr_csv_normalize "$skill_hints,$kind_hints")

    case "$directive_kind" in
      priority-escalation|compliance-gate|interrupt-request)
        if [ "$priority_boost" -lt 3 ]; then
          priority_boost=$((priority_boost + 1))
        fi
        ;;
    esac

    printf '%s\tevent=directive_received\tfrom=%s\tkind=%s\tpriority=%s\tpayload=%s\n' \
      "$(mr_now_iso)" "$from_mode" "$directive_kind" "$directive_priority" "$(mr_directive_payload_clean "$directive_payload")" >> "$mode_events_file"
  done < "$delta_file"
  rm -f "$delta_file"

  if [ -z "$(trim "$summary")" ]; then
    summary="none"
  fi

  printf '%s|%s|%s|%s' "$directive_count" "$summary" "$skill_hints" "$priority_boost"
}

mr_mode_cooperation_plan_lines() {
  mode_id=$1
  status_text=$2
  drift_score=$3
  q_pending=$4
  q_running=$5
  q_errors=$6
  directives_in=$7

  drift_bucket=0
  if awk -v v="$drift_score" 'BEGIN { exit (v >= 0.70 ? 0 : 1) }'; then
    drift_bucket=2
  elif awk -v v="$drift_score" 'BEGIN { exit (v >= 0.45 ? 0 : 1) }'; then
    drift_bucket=1
  fi

  if [ "$q_errors" -gt 0 ]; then
    printf '%s\n' "ethical-statutory-compliance|compliance-gate|9|Queue errors detected; run compliance gating and mitigation checks.|5400"
  fi
  if [ "$q_pending" -gt 10 ]; then
    printf '%s\n' "chrono-budgeter|throughput-rebalance|8|Queue backlog is elevated; rebalance cadence and propose throughput recovery actions.|3600"
  fi
  if [ "$drift_bucket" -ge 2 ]; then
    printf '%s\n' "continuity-of-intention|priority-escalation|9|High drift detected; enforce continuity guardrails and stabilize execution trajectory.|3600"
  fi

  case "$mode_id" in
    mastermind-agency-composer)
      if [ "$q_pending" -eq 0 ] && [ "$q_running" -eq 0 ]; then
        printf '%s\n' "semantic-watchtower|intel-refresh|6|Queue is idle; refresh opportunity and semantic-intel scan for next strategic moves.|5400"
      fi
      ;;
    semantic-watchtower)
      if [ "$q_pending" -le 2 ] && [ "$q_errors" -eq 0 ]; then
        printf '%s\n' "mastermind-agency-composer|opportunity-scan|5|Semantic monitoring is stable; synthesize candidate opportunities for orchestration.|7200"
      fi
      ;;
    failure-mode-simulator)
      if [ "$q_errors" -gt 0 ] || [ "$drift_bucket" -ge 1 ]; then
        printf '%s\n' "adversarial-red-team-twin|resilience-probe|8|Failure pressure observed; run adversarial stress probes against current strategy.|3600"
      fi
      ;;
    adversarial-red-team-twin)
      if [ "$q_errors" -gt 0 ]; then
        printf '%s\n' "ethical-statutory-compliance|risk-surface|8|Adversarial pressure surfaced elevated risk; run policy/legal risk-surface review.|3600"
      fi
      ;;
    narrative-coherence-engine)
      if [ "$status_text" = "alignment-repair" ]; then
        printf '%s\n' "continuity-of-intention|narrative-alignment|7|Narrative alignment degraded; harmonize terminology with active objectives.|3600"
      fi
      ;;
    reputation-thermostat)
      if [ "$q_errors" -gt 0 ] || [ "$drift_bucket" -ge 1 ]; then
        printf '%s\n' "narrative-coherence-engine|brand-coherence|6|Reputation pressure elevated; reinforce coherent narrative and terminology controls.|5400"
      fi
      ;;
    chrono-budgeter)
      if [ "$status_text" = "throttle-recommend" ] || [ "$q_pending" -gt 12 ]; then
        printf '%s\n' "continuity-of-intention|throttle-guidance|7|Chrono budget indicates overload; tighten scope and rebalance objective sequencing.|3600"
      fi
      ;;
    continuity-of-intention)
      if [ "$directives_in" -gt 0 ]; then
        printf '%s\n' "mastermind-agency-composer|trajectory-update|6|Integrated cross-mode directives; update global execution trajectory accordingly.|5400"
      fi
      ;;
  esac
}

mr_mode_focus_text() {
  mode_id=$1
  case "$mode_id" in
    mastermind-agency-composer)
      printf '%s' "agency composition and multi-panel orchestration"
      ;;
    continuity-of-intention)
      printf '%s' "cross-session objective continuity and drift correction"
      ;;
    semantic-watchtower)
      printf '%s' "semantic drift detection and conceptual bifurcation tracking"
      ;;
    ethical-statutory-compliance)
      printf '%s' "legal/platform compliance gating and constraint enforcement"
      ;;
    reputation-thermostat)
      printf '%s' "reputation signal-cost control and trust preservation"
      ;;
    failure-mode-simulator)
      printf '%s' "collapse scenario simulation and resilience stress-testing"
      ;;
    epistemic-calibration)
      printf '%s' "forecast calibration and longitudinal prior updates"
      ;;
    adversarial-red-team-twin)
      printf '%s' "adversarial falsification and exploit surface probing"
      ;;
    narrative-coherence-engine)
      printf '%s' "terminology consistency and narrative coherence"
      ;;
    chrono-budgeter)
      printf '%s' "effort allocation and queue-time ROI optimization"
      ;;
    *)
      printf '%s' "bounded multi-step execution"
      ;;
  esac
}

mr_policy_skill_plan() {
  mode_id=$1
  base=$(mr_mode_recommended_skills "$mode_id")
  [ -n "$(trim "$base")" ] || base="report-synthesizer"

  signals=$(mr_queue_signals_triplet)
  q_pending=$(printf '%s' "$signals" | cut -d'|' -f1)
  q_running=$(printf '%s' "$signals" | cut -d'|' -f2)
  q_errors=$(printf '%s' "$signals" | cut -d'|' -f3)

  dynamic=""
  case "$mode_id" in
    ethical-statutory-compliance)
      dynamic="compliance-lookup,contract-analyzer,report-synthesizer"
      ;;
    semantic-watchtower)
      dynamic="market-research,latent-opportunity-harvester,report-synthesizer"
      ;;
    continuity-of-intention)
      dynamic="proceduralization,shadow-documentation,report-synthesizer"
      ;;
    mastermind-agency-composer)
      dynamic="agent-spawner,panel-integrator,dashboard-builder"
      if [ "$q_pending" -eq 0 ] && [ "$q_running" -eq 0 ]; then
        dynamic="$dynamic,latent-opportunity-harvester"
      fi
      ;;
    failure-mode-simulator)
      dynamic="simulation-runner,contract-analyzer,report-synthesizer"
      ;;
    narrative-coherence-engine)
      dynamic="shadow-documentation,pitch-drafter,report-synthesizer"
      ;;
    adversarial-red-team-twin)
      dynamic="contract-analyzer,simulation-runner,proceduralization"
      ;;
    reputation-thermostat)
      dynamic="market-research,pitch-drafter,report-synthesizer"
      ;;
    chrono-budgeter)
      dynamic="devils-liquidity-provider,proceduralization,data-etl"
      ;;
    epistemic-calibration)
      dynamic="report-synthesizer,simulation-runner,market-research"
      ;;
  esac

  if [ "$q_errors" -gt 0 ]; then
    dynamic="$dynamic,devils-liquidity-provider,compliance-lookup"
  fi
  if [ "$q_pending" -gt 8 ]; then
    dynamic="$dynamic,data-etl,devils-liquidity-provider"
  fi
  if [ "$q_running" -gt 4 ]; then
    dynamic="$dynamic,report-synthesizer"
  fi

  merged=$(mr_csv_normalize "$base,$dynamic")
  limited=$(mr_csv_first_n "$merged" "5")
  [ -n "$(trim "$limited")" ] || limited="report-synthesizer"
  printf '%s' "$limited"
}

mr_capability_in_list() {
  cap_list=$1
  capability=$2
  norm_list=",$(mr_csv_normalize "$cap_list"),"
  norm_cap=$(trim "$capability")
  [ -n "$norm_cap" ] || return 1
  case "$norm_list" in
    *",$norm_cap,"*) return 0 ;;
  esac
  return 1
}

mr_mode_authorizes_capabilities() {
  mode_id=$1
  requested_caps=$2
  allowed_caps=$(mr_mode_allowed_capabilities "$mode_id")
  req_norm=$(mr_csv_normalize "$requested_caps")
  old_ifs=$IFS
  IFS=','
  for cap in $req_norm; do
    clean=$(trim "$cap")
    [ -n "$clean" ] || continue
    case "$clean" in
      filesystem|network|agent_spawn)
        if ! mr_capability_in_list "$allowed_caps" "$clean"; then
          IFS=$old_ifs
          return 1
        fi
        ;;
    esac
  done
  IFS=$old_ifs
  return 0
}

mr_find_default_target() {
  selected_ws=""
  selected_conv=""
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    ws_id=$(basename "$ws_dir")
    conv_root="$ws_dir/conversations"
    [ -d "$conv_root" ] || continue
    for conv_dir in "$conv_root"/*; do
      [ -d "$conv_dir" ] || continue
      selected_ws=$ws_id
      selected_conv=$(basename "$conv_dir")
      printf '%s|%s' "$selected_ws" "$selected_conv"
      return 0
    done
  done
  printf '%s|%s' "$selected_ws" "$selected_conv"
}

mr_try_queue_injection() {
  mode_id=$1
  ws_id=$2
  conv_id=$3
  injection_prompt=$4

  [ -n "$(trim "$injection_prompt")" ] || {
    printf '%s' ""
    return 0
  }

  if [ -z "$ws_id" ] || [ -z "$conv_id" ]; then
    pair=$(mr_find_default_target)
    ws_id=$(printf '%s' "$pair" | cut -d'|' -f1)
    conv_id=$(printf '%s' "$pair" | cut -d'|' -f2)
  fi

  if [ -z "$ws_id" ] || [ -z "$conv_id" ]; then
    printf '%s' ""
    return 0
  fi

  if ! valid_id "$ws_id" || ! valid_id "$conv_id"; then
    printf '%s' ""
    return 0
  fi

  conv_dir=$(conversation_dir_for "$ws_id" "$conv_id")
  if [ ! -d "$conv_dir" ]; then
    printf '%s' ""
    return 0
  fi

  ensure_queue_layout "$conv_dir"
  item_id=$(new_id)
  order=$(queue_allocate_order "$conv_dir" "tail")
  queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
  queue_item_meta=$(queue_item_meta_for_path "$queue_item_file")

  printf '%s\n\n[mode:%s]' "$injection_prompt" "$mode_id" > "$queue_item_file"
  empty_attachment_ids=$(mktemp)
  empty_skill_ids=$(mktemp)
  : > "$empty_attachment_ids"
  : > "$empty_skill_ids"
  queue_meta_write "$queue_item_meta" "assistant" "$mode_id" "auto" "$empty_skill_ids" "$empty_attachment_ids"
  rm -f "$empty_attachment_ids" "$empty_skill_ids"

  printf '%s' "$item_id"
}

mr_mode_tick_one() {
  mode_id=$1
  workspace_id=$2
  conversation_id=$3

  state_file=$(mr_mode_state_file "$mode_id")
  manifest_file=$(mr_mode_manifest_file "$mode_id")

  cadence=$(mr_positive_int_or "$(mr_env_get "$state_file" "cadence_sec" "$(mr_env_get "$manifest_file" "default_cadence_sec" "900")")" "900")
  interrupt_rights=$(mr_bool_norm "$(mr_env_get "$state_file" "interrupt_rights" "$(mr_env_get "$manifest_file" "default_interrupt_rights" "0")")")
  allow_queue_injection=$(mr_bool_norm "$(mr_env_get "$state_file" "allow_queue_injection" "0")")
  directives_feedback=$(mr_mode_consume_directives "$mode_id" "8")
  directives_received=$(printf '%s' "$directives_feedback" | cut -d'|' -f1)
  directives_summary=$(printf '%s' "$directives_feedback" | cut -d'|' -f2)
  directives_skill_hints=$(printf '%s' "$directives_feedback" | cut -d'|' -f3)
  directives_priority_boost=$(printf '%s' "$directives_feedback" | cut -d'|' -f4)
  case "$directives_received" in ""|*[!0-9]*) directives_received=0 ;; esac
  case "$directives_priority_boost" in ""|*[!0-9]*) directives_priority_boost=0 ;; esac
  if [ "$directives_priority_boost" -lt 0 ]; then
    directives_priority_boost=0
  fi

  queue_signals=$(mr_queue_signals_triplet)
  q_pending=$(printf '%s' "$queue_signals" | cut -d'|' -f1)
  q_running=$(printf '%s' "$queue_signals" | cut -d'|' -f2)
  q_errors=$(printf '%s' "$queue_signals" | cut -d'|' -f3)

  case "$q_pending" in ""|*[!0-9]*) q_pending=0 ;; esac
  case "$q_running" in ""|*[!0-9]*) q_running=0 ;; esac
  case "$q_errors" in ""|*[!0-9]*) q_errors=0 ;; esac

  drift_tenths=$((q_errors * 4 + q_pending + q_running * 2))
  if [ "$drift_tenths" -gt 10 ]; then
    drift_tenths=10
  fi
  drift_score=$(awk -v d="$drift_tenths" 'BEGIN { printf "%.2f", d / 10.0 }')

  status_text="healthy"
  if [ "$q_errors" -gt 0 ]; then
    status_text="degraded"
  elif [ "$q_pending" -gt 6 ]; then
    status_text="saturated"
  fi
  case "$mode_id" in
    ethical-statutory-compliance)
      if [ "$q_errors" -gt 0 ]; then
        status_text="intervention-required"
      elif [ "$q_pending" -gt 6 ]; then
        status_text="preemptive-review"
      fi
      ;;
    chrono-budgeter)
      if [ "$q_pending" -gt 12 ]; then
        status_text="throttle-recommend"
      elif [ "$q_pending" -gt 6 ]; then
        status_text="rebalance"
      fi
      ;;
    mastermind-agency-composer)
      if [ "$q_pending" -eq 0 ] && [ "$q_running" -eq 0 ]; then
        status_text="opportunity-scan"
      fi
      ;;
    narrative-coherence-engine)
      if [ "$q_errors" -gt 0 ]; then
        status_text="alignment-repair"
      fi
      ;;
  esac

  if [ "$directives_received" -gt 0 ] && [ "$status_text" = "healthy" ]; then
    status_text="coordinating"
  fi
  if [ "$directives_priority_boost" -ge 2 ] && [ "$q_errors" -eq 0 ] && [ "$q_pending" -le 2 ]; then
    status_text="priority-sync"
  fi

  subscriptions=$(mr_mode_subscriptions_current "$mode_id")
  telemetry_summary=""
  first_feed=1
  old_ifs=$IFS
  IFS=','
  for feed in $subscriptions; do
    feed_clean=$(trim "$feed")
    [ -n "$feed_clean" ] || continue
    feed_payload=$(mr_feed_payload "$feed_clean" "$(mr_now_iso)")
    if [ "$first_feed" -eq 0 ]; then
      telemetry_summary="$telemetry_summary | "
    fi
    first_feed=0
    telemetry_summary="$telemetry_summary$feed_payload"
  done
  IFS=$old_ifs

  if [ -z "$(trim "$telemetry_summary")" ]; then
    telemetry_summary="no telemetry"
  fi

  skill_plan=$(mr_policy_skill_plan "$mode_id")
  if [ -n "$(trim "$directives_skill_hints")" ]; then
    skill_plan=$(mr_csv_normalize "$skill_plan,$directives_skill_hints")
  fi
  skill_plan=$(mr_csv_first_n "$skill_plan" "5")
  [ -n "$(trim "$skill_plan")" ] || skill_plan="report-synthesizer"
  mode_events_file=$(mr_mode_event_queue_file "$mode_id")
  old_ifs=$IFS
  IFS=','
  for suggested_skill in $skill_plan; do
    suggested_skill=$(trim "$suggested_skill")
    [ -n "$suggested_skill" ] || continue
    printf '%s\tevent=skill_suggested\tskill=%s\n' "$(mr_now_iso)" "$suggested_skill" >> "$mode_events_file"
  done
  IFS=$old_ifs

  directives_emitted=0
  cooperation_lines=$(mr_mode_cooperation_plan_lines "$mode_id" "$status_text" "$drift_score" "$q_pending" "$q_running" "$q_errors" "$directives_received")
  if [ -n "$(trim "$cooperation_lines")" ]; then
    emit_guard=0
    while IFS='|' read -r target_mode directive_kind directive_priority directive_payload directive_ttl; do
      [ -n "$(trim "$target_mode")" ] || continue
      emit_guard=$((emit_guard + 1))
      if [ "$emit_guard" -gt 3 ]; then
        break
      fi
      emitted_id=$(mr_mode_emit_directive "$mode_id" "$target_mode" "$directive_kind" "$directive_priority" "$directive_payload" "$directive_ttl")
      if [ -n "$(trim "$emitted_id")" ]; then
        directives_emitted=$((directives_emitted + 1))
        printf '%s\tevent=directive_emitted\tto=%s\tkind=%s\tpriority=%s\tpayload=%s\n' \
          "$(mr_now_iso)" "$target_mode" "$directive_kind" "$directive_priority" "$(mr_directive_payload_clean "$directive_payload")" >> "$mode_events_file"
      fi
    done <<EOF_DIRECTIVES
$cooperation_lines
EOF_DIRECTIVES
  fi

  injection_item=""
  if [ "$allow_queue_injection" = "1" ]; then
    if mr_mode_authorizes_capabilities "$mode_id" "agent_spawn"; then
      injection_item=$(mr_try_queue_injection "$mode_id" "$workspace_id" "$conversation_id" "[Autonomous injection] $mode_id suggests a next-step execution cycle based on current telemetry.")
    fi
  fi

  now_epoch=$(mr_now_epoch)
  next_tick=$((now_epoch + cadence))
  mr_env_set "$state_file" "last_tick" "$now_epoch"
  mr_env_set "$state_file" "next_tick" "$next_tick"
  mr_env_set "$state_file" "status" "$status_text"
  mr_env_set "$state_file" "drift_score" "$drift_score"
  mr_env_set "$state_file" "last_skill_plan" "$skill_plan"
  mr_env_set "$state_file" "last_directive_count" "$directives_received"
  mr_env_set "$state_file" "last_directive_emits" "$directives_emitted"
  mr_env_set "$state_file" "last_directive_summary" "$(mr_directive_payload_clean "$directives_summary")"

  mode_telemetry_file=$(mr_mode_last_telemetry_file "$mode_id")
  {
    printf '%s\n' "$telemetry_summary"
  } >> "$mode_telemetry_file"

  mr_log_mode_iteration "$mode_id" "$status_text" "$drift_score" "$skill_plan" "$telemetry_summary" "$injection_item" "$directives_received" "$directives_emitted" "$directives_summary"

  if [ "$interrupt_rights" = "1" ] && awk -v v="$drift_score" 'BEGIN { exit (v >= 0.70 ? 0 : 1) }'; then
    interrupt_file="$(mr_interrupts_dir)/$(mr_now_epoch)-${mode_id}.json"
    cat > "$interrupt_file" <<EOF_INTERRUPT
{"mode_id":"$(json_escape "$mode_id")","timestamp":"$(json_escape "$(mr_now_iso)")","reason":"drift threshold exceeded","drift_score":"$(json_escape "$drift_score")"}
EOF_INTERRUPT
  fi

  printf '%s|%s|%s|%s|%s|%s|%s|%s' \
    "$mode_id" "$status_text" "$drift_score" "$skill_plan" "$injection_item" "$directives_received" "$directives_emitted" "$(mr_directive_payload_clean "$directives_summary")"
}

mr_mode_scheduler_tick_json() {
  workspace_id=$1
  conversation_id=$2

  now_epoch=$(mr_now_epoch)
  now_iso=$(mr_now_iso)
  tick_queue_signals=$(mr_queue_signals_triplet)
  MR_QUEUE_SIGNALS_OVERRIDE=$tick_queue_signals
  export MR_QUEUE_SIGNALS_OVERRIDE
  active_modes=0
  due_modes=0
  injections=0
  directives_received_total=0
  directives_emitted_total=0

  processed_json=''
  processed_first=1
  due_mode_order_file=$(mktemp)
  : > "$due_mode_order_file"

  for mode_id in $(mr_list_mode_ids); do
    state_file=$(mr_mode_state_file "$mode_id")
    manifest_file=$(mr_mode_manifest_file "$mode_id")
    enabled=$(mr_bool_norm "$(mr_env_get "$state_file" "enabled" "0")")
    [ "$enabled" = "1" ] || continue
    active_modes=$((active_modes + 1))

    next_tick=$(mr_env_get "$state_file" "next_tick" "0")
    case "$next_tick" in ""|*[!0-9]*) next_tick=0 ;; esac
    if [ "$next_tick" -gt "$now_epoch" ]; then
      continue
    fi
    mode_priority=$(mr_positive_int_or "$(mr_env_get "$state_file" "priority" "$(mr_env_get "$manifest_file" "default_priority" "5")")" "5")
    printf '%s|%s\n' "$mode_priority" "$mode_id" >> "$due_mode_order_file"
  done

  while IFS='|' read -r _prio mode_id; do
    [ -n "$mode_id" ] || continue
    due_modes=$((due_modes + 1))
    tick_result=$(mr_mode_tick_one "$mode_id" "$workspace_id" "$conversation_id")
    result_mode=$(printf '%s' "$tick_result" | cut -d'|' -f1)
    result_status=$(printf '%s' "$tick_result" | cut -d'|' -f2)
    result_drift=$(printf '%s' "$tick_result" | cut -d'|' -f3)
    result_skills=$(printf '%s' "$tick_result" | cut -d'|' -f4)
    result_injection=$(printf '%s' "$tick_result" | cut -d'|' -f5)
    result_directives_received=$(printf '%s' "$tick_result" | cut -d'|' -f6)
    result_directives_emitted=$(printf '%s' "$tick_result" | cut -d'|' -f7)
    result_directive_summary=$(printf '%s' "$tick_result" | cut -d'|' -f8-)

    case "$result_directives_received" in ""|*[!0-9]*) result_directives_received=0 ;; esac
    case "$result_directives_emitted" in ""|*[!0-9]*) result_directives_emitted=0 ;; esac
    directives_received_total=$((directives_received_total + result_directives_received))
    directives_emitted_total=$((directives_emitted_total + result_directives_emitted))

    if [ -n "$(trim "$result_injection")" ]; then
      injections=$((injections + 1))
    fi

    if [ "$processed_first" -eq 0 ]; then
      processed_json="$processed_json,"
    fi
    processed_first=0

    processed_json="$processed_json{\"mode_id\":\"$(json_escape "$result_mode")\",\"status\":\"$(json_escape "$result_status")\",\"drift_score\":\"$(json_escape "$result_drift")\",\"skills\":$(mr_csv_to_json_array "$result_skills"),\"injected_queue_item\":\"$(json_escape "$result_injection")\",\"directives_received\":\"$(json_escape "$result_directives_received")\",\"directives_emitted\":\"$(json_escape "$result_directives_emitted")\",\"directive_summary\":\"$(json_escape "$result_directive_summary")\"}"
  done <<EOF_DUE
$(sort -t'|' -k1,1nr -k2,2 "$due_mode_order_file")
EOF_DUE
  rm -f "$due_mode_order_file"
  unset MR_QUEUE_SIGNALS_OVERRIDE 2>/dev/null || true

  scheduler_state=$(mr_scheduler_state_file)
  prev_ticks=$(mr_env_get "$scheduler_state" "ticks" "0")
  case "$prev_ticks" in ""|*[!0-9]*) prev_ticks=0 ;; esac
  ticks=$((prev_ticks + 1))
  summary="tick active=$active_modes due=$due_modes injections=$injections directives_in=$directives_received_total directives_out=$directives_emitted_total"
  mr_env_set "$scheduler_state" "last_tick" "$now_epoch"
  mr_env_set "$scheduler_state" "last_tick_iso" "$now_iso"
  mr_env_set "$scheduler_state" "ticks" "$ticks"
  mr_env_set "$scheduler_state" "last_due_modes" "$due_modes"
  mr_env_set "$scheduler_state" "last_injections" "$injections"
  mr_env_set "$scheduler_state" "last_directives_received" "$directives_received_total"
  mr_env_set "$scheduler_state" "last_directives_emitted" "$directives_emitted_total"
  mr_env_set "$scheduler_state" "last_summary" "$summary"

  printf '{"timestamp":"%s","active_modes":%s,"due_modes":%s,"injections":%s,"directives_received":%s,"directives_emitted":%s,"processed":[%s],"summary":"%s"}' \
    "$(json_escape "$now_iso")" "$active_modes" "$due_modes" "$injections" "$directives_received_total" "$directives_emitted_total" "$processed_json" "$(json_escape "$summary")"
}

mr_mode_json_array() {
  printf '['
  first=1
  for mode_id in $(mr_list_mode_ids); do
    manifest_file=$(mr_mode_manifest_file "$mode_id")
    state_file=$(mr_mode_state_file "$mode_id")

    mode_name=$(mr_env_get "$manifest_file" "name" "$mode_id")
    mode_desc=$(mr_env_get "$manifest_file" "description" "")
    mode_priority=$(mr_env_get "$state_file" "priority" "$(mr_env_get "$manifest_file" "default_priority" "5")")
    mode_cadence=$(mr_env_get "$state_file" "cadence_sec" "$(mr_env_get "$manifest_file" "default_cadence_sec" "900")")
    mode_enabled=$(mr_bool_norm "$(mr_env_get "$state_file" "enabled" "0")")
    mode_interrupt=$(mr_bool_norm "$(mr_env_get "$state_file" "interrupt_rights" "$(mr_env_get "$manifest_file" "default_interrupt_rights" "0")")")
    mode_queue_injection=$(mr_bool_norm "$(mr_env_get "$state_file" "allow_queue_injection" "0")")
    mode_status=$(mr_env_get "$state_file" "status" "idle")
    mode_drift=$(mr_env_get "$state_file" "drift_score" "0.00")
    mode_last_tick=$(mr_env_get "$state_file" "last_tick" "0")
    mode_next_tick=$(mr_env_get "$state_file" "next_tick" "0")
    mode_goal=$(mr_env_get "$state_file" "goal_state" "")
    mode_skills=$(mr_env_get "$state_file" "last_skill_plan" "")
    mode_directive_count=$(mr_env_get "$state_file" "last_directive_count" "0")
    mode_directive_emits=$(mr_env_get "$state_file" "last_directive_emits" "0")
    mode_directive_summary=$(mr_env_get "$state_file" "last_directive_summary" "none")
    mode_subs=$(mr_mode_subscriptions_current "$mode_id")
    mode_caps=$(mr_env_get "$manifest_file" "allowed_capabilities" "")

    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0

    printf '{"id":"%s","name":"%s","description":"%s","enabled":%s,"priority":%s,"cadence_sec":%s,"interrupt_rights":%s,"allow_queue_injection":%s,"status":"%s","drift_score":"%s","last_tick":"%s","next_tick":"%s","goal_state":"%s","last_skill_plan":%s,"last_directive_count":"%s","last_directive_emits":"%s","last_directive_summary":"%s","telemetry_subscriptions":%s,"allowed_capabilities":%s}' \
      "$(json_escape "$mode_id")" \
      "$(json_escape "$mode_name")" \
      "$(json_escape "$mode_desc")" \
      "$mode_enabled" \
      "$(mr_positive_int_or "$mode_priority" "5")" \
      "$(mr_positive_int_or "$mode_cadence" "900")" \
      "$mode_interrupt" \
      "$mode_queue_injection" \
      "$(json_escape "$mode_status")" \
      "$(json_escape "$mode_drift")" \
      "$(json_escape "$mode_last_tick")" \
      "$(json_escape "$mode_next_tick")" \
      "$(json_escape "$mode_goal")" \
      "$(mr_csv_to_json_array "$mode_skills")" \
      "$(json_escape "$mode_directive_count")" \
      "$(json_escape "$mode_directive_emits")" \
      "$(json_escape "$mode_directive_summary")" \
      "$(mr_csv_to_json_array "$mode_subs")" \
      "$(mr_csv_to_json_array "$mode_caps")"
  done
  printf ']'
}

mr_skill_json_array() {
  printf '['
  first=1
  for skill_id in $(mr_list_skill_ids); do
    meta_file=$(mr_skill_meta_file "$skill_id")
    skill_name=$(mr_env_get "$meta_file" "name" "$skill_id")
    skill_trigger=$(mr_env_get "$meta_file" "trigger" "")
    skill_caps=$(mr_env_get "$meta_file" "capabilities" "")
    skill_desc=$(mr_env_get "$meta_file" "description" "")

    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0

    printf '{"id":"%s","name":"%s","description":"%s","trigger":"%s","capabilities":%s,"stateless":true,"interrupt_authority":false,"files":{"policy_md":true,"trigger_yaml":true,"tools_json":true,"output_schema_json":true}}' \
      "$(json_escape "$skill_id")" \
      "$(json_escape "$skill_name")" \
      "$(json_escape "$skill_desc")" \
      "$(json_escape "$skill_trigger")" \
      "$(mr_csv_to_json_array "$skill_caps")"
  done
  printf ']'
}

mr_dashboard_panels_json() {
  scheduler_state=$(mr_scheduler_state_file)
  sched_last_tick=$(mr_env_get "$scheduler_state" "last_tick_iso" "")
  sched_summary=$(mr_env_get "$scheduler_state" "last_summary" "")

  metrics=$(mr_queue_metrics)
  pending=$(printf '%s\n' "$metrics" | sed -n 's/^pending=//p' | sed -n '1p')
  running=$(printf '%s\n' "$metrics" | sed -n 's/^running=//p' | sed -n '1p')
  errors=$(printf '%s\n' "$metrics" | sed -n 's/^errors=//p' | sed -n '1p')

  active_modes=0
  for mode_id in $(mr_list_mode_ids); do
    enabled=$(mr_bool_norm "$(mr_env_get "$(mr_mode_state_file "$mode_id")" "enabled" "0")")
    if [ "$enabled" = "1" ]; then
      active_modes=$((active_modes + 1))
    fi
  done

  printf '['
  printf '{"id":"global-dashboard","title":"Global Dashboard","summary":"Unified multi-mode telemetry overview.","metrics":[{"label":"Active modes","value":"%s"},{"label":"Queue pending","value":"%s"},{"label":"Queue running","value":"%s"},{"label":"Queue errors","value":"%s"}],"stream":"%s"},' \
    "$(json_escape "$active_modes")" "$(json_escape "$pending")" "$(json_escape "$running")" "$(json_escape "$errors")" "$(json_escape "$sched_summary")"

  printf '{"id":"oracle-intel-panel","title":"Oracle / Intel Panel","summary":"Watchtower and calibration signals for situational awareness.","metrics":[{"label":"Semantic drift","value":"tracked"},{"label":"Calibration","value":"longitudinal"}],"stream":"%s"},' \
    "$(json_escape "Last scheduler tick: ${sched_last_tick:-n/a}")"

  printf '{"id":"grant-income-panel","title":"Grant / Income Panel","summary":"Funding task surfacing with optional autonomous queue injection.","metrics":[{"label":"Queue injection","value":"mode-gated"},{"label":"Authorization","value":"required"}],"stream":"%s"},' \
    "$(json_escape "Enable queue injection on selected modes for autonomous task insertion.")"

  printf '{"id":"reputation-monitoring-panel","title":"Reputation Monitoring Panel","summary":"Signal-cost and sentiment pressure tracking.","metrics":[{"label":"Reputation mode","value":"available"},{"label":"Compliance gate","value":"active"}],"stream":"%s"}' \
    "$(json_escape "Use Reputation Thermostat + Compliance modes for guarded outreach.")"
  printf ']'
}

mr_mode_pending_directive_count() {
  mode_id=$1
  inbox_file=$(mr_mode_directive_inbox_file "$mode_id")
  cursor_file=$(mr_mode_directive_cursor_file "$mode_id")
  total_lines=0
  cursor_line=0
  if [ -f "$inbox_file" ]; then
    total_lines=$(wc -l < "$inbox_file" 2>/dev/null | tr -d '[:space:]' || printf '0')
  fi
  if [ -f "$cursor_file" ]; then
    cursor_line=$(read_file_line "$cursor_file" "0")
  fi
  case "$total_lines" in ""|*[!0-9]*) total_lines=0 ;; esac
  case "$cursor_line" in ""|*[!0-9]*) cursor_line=0 ;; esac
  pending=$((total_lines - cursor_line))
  if [ "$pending" -lt 0 ]; then
    pending=0
  fi
  printf '%s' "$pending"
}

mr_cooperation_pending_stats() {
  pending_total=0
  modes_with_pending=0
  for mode_id in $(mr_list_mode_ids); do
    mode_pending=$(mr_mode_pending_directive_count "$mode_id")
    case "$mode_pending" in ""|*[!0-9]*) mode_pending=0 ;; esac
    pending_total=$((pending_total + mode_pending))
    if [ "$mode_pending" -gt 0 ]; then
      modes_with_pending=$((modes_with_pending + 1))
    fi
  done
  printf '%s|%s' "$pending_total" "$modes_with_pending"
}

mr_cooperation_recent_json() {
  max_rows=$1
  case "$max_rows" in ""|*[!0-9]*) max_rows=20 ;; esac
  if [ "$max_rows" -lt 1 ]; then
    max_rows=1
  fi
  coop_log=$(mr_cooperation_log_file)
  printf '['
  first=1
  if [ -f "$coop_log" ]; then
    recent_file=$(mktemp)
    tail -n "$max_rows" "$coop_log" > "$recent_file" 2>/dev/null || : > "$recent_file"
    now_epoch=$(mr_now_epoch)
    case "$now_epoch" in ""|*[!0-9]*) now_epoch=0 ;; esac
    while IFS="$(printf '\t')" read -r event_epoch event_iso from_mode to_mode event_kind event_priority event_payload expires_epoch || [ -n "$event_epoch$event_kind$event_payload" ]; do
      [ -n "$(trim "$event_kind")" ] || continue
      case "$expires_epoch" in ""|*[!0-9]*) expires_epoch=0 ;; esac
      expired=false
      if [ "$expires_epoch" -gt 0 ] && [ "$now_epoch" -gt 0 ] && [ "$expires_epoch" -lt "$now_epoch" ]; then
        expired=true
      fi
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"timestamp":"%s","from_mode":"%s","to_mode":"%s","kind":"%s","priority":"%s","payload":"%s","expires_epoch":"%s","expired":%s}' \
        "$(json_escape "$event_iso")" \
        "$(json_escape "$from_mode")" \
        "$(json_escape "$to_mode")" \
        "$(json_escape "$event_kind")" \
        "$(json_escape "$event_priority")" \
        "$(json_escape "$event_payload")" \
        "$(json_escape "$expires_epoch")" \
        "$expired"
    done < "$recent_file"
    rm -f "$recent_file"
  fi
  printf ']'
}

mode_runtime_state_json() {
  scheduler_state=$(mr_scheduler_state_file)
  last_tick=$(mr_env_get "$scheduler_state" "last_tick" "0")
  last_tick_iso=$(mr_env_get "$scheduler_state" "last_tick_iso" "")
  ticks=$(mr_env_get "$scheduler_state" "ticks" "0")
  due_modes=$(mr_env_get "$scheduler_state" "last_due_modes" "0")
  injections=$(mr_env_get "$scheduler_state" "last_injections" "0")
  directives_received=$(mr_env_get "$scheduler_state" "last_directives_received" "0")
  directives_emitted=$(mr_env_get "$scheduler_state" "last_directives_emitted" "0")
  summary=$(mr_env_get "$scheduler_state" "last_summary" "Scheduler idle")
  cooperation_stats=$(mr_cooperation_pending_stats)
  cooperation_pending_total=$(printf '%s' "$cooperation_stats" | cut -d'|' -f1)
  cooperation_modes_pending=$(printf '%s' "$cooperation_stats" | cut -d'|' -f2)
  cooperation_recent=$(mr_cooperation_recent_json "24")
  failure_taxonomy_state=$(mr_failure_taxonomy_state_json)
  improvement_proposals_state=$(mr_improvement_proposals_state_json)
  controller_variants_state=$(mr_controller_variants_state_json)
  quality_scorecard_state=$(mr_quality_scorecard_state_json)

  printf '{"scheduler":{"last_tick":"%s","last_tick_iso":"%s","ticks":"%s","last_due_modes":"%s","last_injections":"%s","last_directives_received":"%s","last_directives_emitted":"%s","summary":"%s"},"modes":%s,"skills":%s,"panels":%s,"cooperation":{"pending_total":"%s","modes_with_pending":"%s","recent":%s},"failure_taxonomy":%s,"improvement_proposals":%s,"controller_variants":%s,"quality_scorecard":%s}' \
    "$(json_escape "$last_tick")" \
    "$(json_escape "$last_tick_iso")" \
    "$(json_escape "$ticks")" \
    "$(json_escape "$due_modes")" \
    "$(json_escape "$injections")" \
    "$(json_escape "$directives_received")" \
    "$(json_escape "$directives_emitted")" \
    "$(json_escape "$summary")" \
    "$(mr_mode_json_array)" \
    "$(mr_skill_json_array)" \
    "$(mr_dashboard_panels_json)" \
    "$(json_escape "$cooperation_pending_total")" \
    "$(json_escape "$cooperation_modes_pending")" \
    "$cooperation_recent" \
    "$failure_taxonomy_state" \
    "$improvement_proposals_state" \
    "$controller_variants_state" \
    "$quality_scorecard_state"
}

mr_skill_capabilities() {
  skill_id=$1
  meta_file=$(mr_skill_meta_file "$skill_id")
  mr_env_get "$meta_file" "capabilities" ""
}

mr_skill_artifact_targets_json() {
  skill_id=$1
  artifacts="policy.md,trigger.yaml,tools.json,output.schema.json"
  case "$skill_id" in
    shadow-documentation)
      artifacts="$artifacts,README.md,.architecture.md,.tasks/index.md"
      ;;
    dashboard-builder|panel-integrator)
      artifacts="$artifacts,dashboard/composites.md,telemetry/*.log"
      ;;
    proceduralization)
      artifacts="$artifacts,scripts/*.sh,runbook.md"
      ;;
    compliance-lookup|contract-analyzer)
      artifacts="$artifacts,compliance-notes.md"
      ;;
    codegen-infra-spin-up)
      artifacts="$artifacts,infrastructure/*,deployment-checklist.md"
      ;;
  esac
  mr_csv_to_json_array "$artifacts"
}

mr_skill_risk_gate() {
  input_text=$1
  input_lower=$(printf '%s' "$input_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$input_lower" | grep -Eq 'phish|malware|credential stuffing|ddos|ransomware|exploit( chain)?|spam campaign|bypass paywall|steal credentials|fraud'; then
    printf '%s' "blocked"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'contact real|email customers|cold outreach|post publicly|publish live|charge card|payment|register company|legal filing|file taxes|sign contract'; then
    printf '%s' "needs_auth"
    return 0
  fi
  printf '%s' "ok"
}

mr_skill_dynamic_step() {
  input_text=$1
  input_lower=$(printf '%s' "$input_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$input_lower" | grep -Eq 'deterministic|replay|checksum|regression|test'; then
    printf '%s' "Attach deterministic checks, replay criteria, and pass/fail thresholds"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'dashboard|panel|telemetry|metric'; then
    printf '%s' "Publish telemetry mapping and panel acceptance criteria"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'contract|legal|compliance|policy'; then
    printf '%s' "Capture obligations and map each to an enforceable control"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'market|customer|demand|competition|pricing'; then
    printf '%s' "Document evidence quality, confidence, and open uncertainty"
    return 0
  fi
  printf '%s' "Capture measurable acceptance criteria and explicit stop conditions"
}

mr_skill_actuator_output_json() {
  skill_id=$1
  mode_id=$2
  input_text=$3

  clean_input=$(mr_sanitize_inline "$input_text")
  [ -n "$clean_input" ] || clean_input="No explicit input provided."
  mode_focus=$(mr_mode_focus_text "$mode_id")
  risk_gate=$(mr_skill_risk_gate "$clean_input")
  governance_gate="none"
  status_value="ok"
  required_followup=false

  case "$risk_gate" in
    blocked)
      status_value="blocked"
      governance_gate="blocked"
      required_followup=true
      ;;
    needs_auth)
      status_value="needs_auth"
      governance_gate="approval_required"
      required_followup=true
      ;;
  esac

  actions=""
  case "$skill_id" in
    proceduralization)
      actions='Capture successful manual workflow; Normalize into reusable pipeline stages; Generate script/runbook template; Define regression guardrails for reuse'
      ;;
    grant-hunter)
      actions='Scan funding channels; Score opportunities by fit and effort; Draft submission skeleton with milestones; Generate dependency checklist'
      ;;
    negotiation-doppelganger)
      actions='Model counterpart positions; Build BATNA/threshold tree; Generate negotiation script variants; Identify concession boundaries'
      ;;
    devils-liquidity-provider)
      actions='Detect current stall point; Propose substitute execution path; Re-sequence queue to recover momentum; Define rollback route'
      ;;
    shadow-documentation)
      actions='Diff changed artifacts; Update README/ops notes; Refresh architecture map and task index; Add concise changelog entry'
      ;;
    latent-opportunity-harvester)
      actions='Run cross-domain scan; Surface complementarities and slack; Rank leverage opportunities; Emit shortlist with rationale'
      ;;
    dashboard-builder)
      actions='Define panel modules and contracts; Attach telemetry streams; Emit composable dashboard config; Add freshness/latency indicators'
      ;;
    agent-spawner)
      actions='Validate spawn scope and boundaries; Select agent template; Emit child-agent bootstrap contract; Define supervision and stop criteria'
      ;;
    panel-integrator)
      actions='Bind multi-agent feeds; Normalize metric taxonomy; Publish unified panel view; Add source lineage metadata'
      ;;
    compliance-lookup)
      actions='Locate governing constraints; Extract actionable obligations; Flag uncertainty and jurisdictional gaps; Propose control mapping'
      ;;
    report-synthesizer)
      actions='Collect distributed outputs; Build sectioned narrative; Emit concise recommendations; Add residual-risk and confidence section'
      ;;
    market-research)
      actions='Define market slice and hypotheses; Gather demand signals; Summarize competitor posture; Estimate confidence and unknowns'
      ;;
    contract-analyzer)
      actions='Parse contract clauses; Extract obligations and risk surfaces; Summarize red flags; Recommend mitigation follow-ups'
      ;;
    pitch-drafter)
      actions='Identify target audience; Tailor value narrative; Draft pitch variants; Align with likely objections'
      ;;
    data-etl)
      actions='Ingest source payload; Normalize schema and typing; Route transformed output; Emit data quality diagnostics'
      ;;
    web-scraper)
      actions='Fetch policy-approved sources; Extract target fields; Emit structured dataset; Log provenance and extraction quality'
      ;;
    simulation-runner)
      actions='Define scenario bounds and assumptions; Execute bounded simulations; Report outcome distributions; Highlight failure envelopes'
      ;;
    codegen-infra-spin-up)
      actions='Generate infrastructure scaffolds; Validate baseline configuration; Produce deployment checklist; Add rollback and observability stubs'
      ;;
    *)
      actions='Parse request; Execute bounded task; Emit structured output; Capture next-action handoff'
      ;;
  esac

  if [ "$risk_gate" = "blocked" ]; then
    actions='Refuse unsafe objective; Explain blocked safety category; Offer compliant alternatives; Request safe objective rewrite'
  fi
  if [ "$risk_gate" = "needs_auth" ]; then
    actions="$actions; Request explicit authorization before irreversible external actions"
  fi
  dynamic_step=$(mr_skill_dynamic_step "$clean_input")
  actions="$actions; $dynamic_step"
  actions_json=$(mr_csv_to_json_array "$(printf '%s' "$actions" | sed 's/;\s*/,/g')")

  bundle_health="complete"
  missing_files=""
  skill_dir=$(mr_skill_dir_for "$skill_id")
  for required_file in policy.md trigger.yaml tools.json output.schema.json; do
    if [ ! -f "$skill_dir/$required_file" ]; then
      bundle_health="partial"
      if [ -n "$missing_files" ]; then
        missing_files="$missing_files,$required_file"
      else
        missing_files="$required_file"
      fi
    fi
  done
  missing_json=$(mr_csv_to_json_array "$missing_files")

  confidence="0.82"
  if [ "$bundle_health" = "partial" ]; then
    confidence="0.68"
  fi
  if [ "$status_value" = "needs_auth" ]; then
    confidence="0.55"
  elif [ "$status_value" = "blocked" ]; then
    confidence="0.20"
  fi

  artifacts_json=$(mr_skill_artifact_targets_json "$skill_id")
  summary_text="Executed $skill_id under mode ${mode_id:-assistant} with focus on $mode_focus. Objective: $clean_input"
  if [ "$status_value" = "needs_auth" ]; then
    summary_text="Prepared bounded plan for $skill_id, but explicit authorization is required for irreversible external actions."
  elif [ "$status_value" = "blocked" ]; then
    summary_text="Blocked unsafe request for $skill_id and generated compliant alternatives."
  fi

  notes_text="Stateless run completed; scratch memory disposed. Governance gate=$governance_gate. Bundle health=$bundle_health."

  printf '{"skill_id":"%s","status":"%s","summary":"%s","actions":%s,"artifacts":%s,"mode_focus":"%s","governance_gate":"%s","bundle_health":"%s","missing_bundle_files":%s,"required_followup":%s,"confidence":"%s","notes":"%s"}' \
    "$(json_escape "$skill_id")" \
    "$(json_escape "$status_value")" \
    "$(json_escape "$summary_text")" \
    "$actions_json" \
    "$artifacts_json" \
    "$(json_escape "$mode_focus")" \
    "$(json_escape "$governance_gate")" \
    "$(json_escape "$bundle_health")" \
    "$missing_json" \
    "$required_followup" \
    "$(json_escape "$confidence")" \
    "$(json_escape "$notes_text")"
}

mr_skill_invoke_json() {
  mode_id=$1
  skill_id=$2
  input_text=$3
  requested_caps=$4

  if [ -z "$(trim "$mode_id")" ]; then
    mode_id="assistant"
  fi

  if ! mr_skill_exists "$skill_id"; then
    printf '{"success":false,"error":"skill not found"}'
    return 0
  fi

  skill_caps=$(mr_skill_capabilities "$skill_id")
  caps_to_check=$skill_caps
  if [ -n "$(trim "$requested_caps")" ]; then
    caps_to_check=$(mr_csv_normalize "$requested_caps")
  fi

  sensitive_caps=""
  old_ifs=$IFS
  IFS=','
  for cap in $caps_to_check; do
    clean=$(trim "$cap")
    [ -n "$clean" ] || continue
    case "$clean" in
      filesystem|network|agent_spawn)
        if [ -z "$sensitive_caps" ]; then
          sensitive_caps="$clean"
        else
          sensitive_caps="$sensitive_caps,$clean"
        fi
        ;;
    esac
  done
  IFS=$old_ifs

  if [ -n "$(trim "$sensitive_caps")" ]; then
    if [ "$mode_id" = "assistant" ]; then
      printf '{"success":false,"error":"mode authorization required for requested capabilities","required_capabilities":%s}' "$(mr_csv_to_json_array "$sensitive_caps")"
      return 0
    fi
    if ! mr_mode_exists "$mode_id"; then
      printf '{"success":false,"error":"mode not found for authorization"}'
      return 0
    fi
    if ! mr_mode_authorizes_capabilities "$mode_id" "$sensitive_caps"; then
      printf '{"success":false,"error":"mode policy does not authorize requested capabilities","requested_capabilities":%s,"allowed_capabilities":%s}' \
        "$(mr_csv_to_json_array "$sensitive_caps")" "$(mr_csv_to_json_array "$(mr_mode_allowed_capabilities "$mode_id")")"
      return 0
    fi
  fi

  invocation_id=$(new_id)
  invocation_dir="$(mr_bus_dir)/$invocation_id"
  scratch_dir="$invocation_dir/scratch"
  mkdir -p "$scratch_dir"

  request_file="$invocation_dir/request.txt"
  result_file="$invocation_dir/result.json"
  metadata_file="$invocation_dir/metadata.env"
  started_iso=$(mr_now_iso)

  {
    printf 'mode_id=%s\n' "$mode_id"
    printf 'skill_id=%s\n' "$skill_id"
    printf 'requested_capabilities=%s\n' "$(mr_csv_normalize "$caps_to_check")"
    printf 'started=%s\n' "$started_iso"
  } > "$metadata_file"

  printf '%s\n' "$input_text" > "$request_file"

  result_json=$(mr_skill_actuator_output_json "$skill_id" "$mode_id" "$input_text")
  printf '%s\n' "$result_json" > "$result_file"
  result_status=$(json_extract_string_field "status" "$result_json" || true)
  [ -n "$(trim "$result_status")" ] || result_status="ok"
  result_gate=$(json_extract_string_field "governance_gate" "$result_json" || true)
  [ -n "$(trim "$result_gate")" ] || result_gate="none"

  rm -rf "$scratch_dir"

  finished_iso=$(mr_now_iso)
  mr_env_set "$metadata_file" "finished" "$finished_iso"
  mr_env_set "$metadata_file" "scratch_disposed" "1"

  if [ "$mode_id" != "assistant" ] && mr_mode_exists "$mode_id"; then
    mode_events_file=$(mr_mode_event_queue_file "$mode_id")
    printf '%s\tinvocation=%s\tskill=%s\tstatus=%s\tgate=%s\n' "$finished_iso" "$invocation_id" "$skill_id" "$result_status" "$result_gate" >> "$mode_events_file"
  fi

  printf '{"success":true,"invocation":{"id":"%s","mode_id":"%s","skill_id":"%s","requested_capabilities":%s,"scratch_persistent":false,"started":"%s","finished":"%s"},"result":%s}' \
    "$(json_escape "$invocation_id")" \
    "$(json_escape "$mode_id")" \
    "$(json_escape "$skill_id")" \
    "$(mr_csv_to_json_array "$caps_to_check")" \
    "$(json_escape "$started_iso")" \
    "$(json_escape "$finished_iso")" \
    "$result_json"
}

mr_mode_update_json() {
  mode_id=$(trim "$(param "mode_id")")
  if ! valid_id "$mode_id"; then
    printf '{"success":false,"error":"invalid mode_id"}'
    return 0
  fi
  if ! mr_mode_exists "$mode_id"; then
    printf '{"success":false,"error":"mode not found"}'
    return 0
  fi

  state_file=$(mr_mode_state_file "$mode_id")

  enabled_raw=$(trim "$(param "enabled")")
  cadence_raw=$(trim "$(param "cadence_sec")")
  priority_raw=$(trim "$(param "priority")")
  interrupt_raw=$(trim "$(param "interrupt_rights")")
  queue_injection_raw=$(trim "$(param "allow_queue_injection")")
  goal_raw=$(param "goal_state")
  subscriptions_raw=$(param "subscriptions")

  if [ -n "$enabled_raw" ]; then
    mr_env_set "$state_file" "enabled" "$(mr_bool_norm "$enabled_raw")"
  fi
  if [ -n "$cadence_raw" ]; then
    mr_env_set "$state_file" "cadence_sec" "$(mr_positive_int_or "$cadence_raw" "900")"
  fi
  if [ -n "$priority_raw" ]; then
    mr_env_set "$state_file" "priority" "$(mr_positive_int_or "$priority_raw" "5")"
  fi
  if [ -n "$interrupt_raw" ]; then
    mr_env_set "$state_file" "interrupt_rights" "$(mr_bool_norm "$interrupt_raw")"
  fi
  if [ -n "$queue_injection_raw" ]; then
    mr_env_set "$state_file" "allow_queue_injection" "$(mr_bool_norm "$queue_injection_raw")"
  fi
  if [ -n "$(trim "$goal_raw")" ]; then
    clean_goal=$(mr_sanitize_inline "$goal_raw")
    mr_env_set "$state_file" "goal_state" "$clean_goal"
    printf '# Goal State\n\n- %s\n' "$clean_goal" > "$(mr_mode_goal_file "$mode_id")"
  fi
  if [ -n "$(trim "$subscriptions_raw")" ]; then
    printf '%s\n' "$(mr_csv_normalize "$subscriptions_raw")" > "$(mr_mode_subscriptions_file "$mode_id")"
  fi

  printf '{"success":true,"mode_id":"%s","mode_runtime":%s}' "$(json_escape "$mode_id")" "$(mode_runtime_state_json)"
}

mr_mode_runtime_state_response() {
  printf '{"success":true,"mode_runtime":%s}\n' "$(mode_runtime_state_json)"
}

mr_mode_runtime_tick_response() {
  workspace_id=$(trim "$(param "workspace_id")")
  conversation_id=$(trim "$(param "conversation_id")")
  if [ -n "$workspace_id" ] && ! valid_id "$workspace_id"; then
    printf '{"success":false,"error":"invalid workspace_id"}\n'
    return 0
  fi
  if [ -n "$conversation_id" ] && ! valid_id "$conversation_id"; then
    printf '{"success":false,"error":"invalid conversation_id"}\n'
    return 0
  fi

  tick_json=$(mr_mode_scheduler_tick_json "$workspace_id" "$conversation_id")
  printf '{"success":true,"tick":%s,"mode_runtime":%s}\n' "$tick_json" "$(mode_runtime_state_json)"
}

mr_failure_taxonomy_state_response() {
  printf '{"success":true,"failure_taxonomy":%s}\n' "$(mr_failure_taxonomy_state_json)"
}

mr_failure_taxonomy_query_response() {
  category_filter=$(trim "$(param "category")")
  severity_filter=$(trim "$(param "severity")")
  surface_filter=$(trim "$(param "surface")")
  mode_filter=$(trim "$(param "mode")")
  since_epoch=$(trim "$(param "since_epoch")")
  limit_value=$(trim "$(param "limit")")
  printf '{"success":true,"failure_taxonomy_query":%s}\n' \
    "$(mr_failure_taxonomy_query_json "$category_filter" "$severity_filter" "$surface_filter" "$mode_filter" "$since_epoch" "$limit_value")"
}

mr_improvement_proposals_state_response() {
  printf '{"success":true,"improvement_proposals":%s}\n' "$(mr_improvement_proposals_state_json)"
}

mr_controller_variants_state_response() {
  printf '{"success":true,"controller_variants":%s,"mode_runtime":%s}\n' \
    "$(mr_controller_variants_state_json)" \
    "$(mode_runtime_state_json)"
}

mr_quality_scorecard_state_response() {
  printf '{"success":true,"quality_scorecard":%s,"mode_runtime":%s}\n' \
    "$(mr_quality_scorecard_state_json)" \
    "$(mode_runtime_state_json)"
}

mr_controller_variant_promote_response() {
  variant_id=$(trim "$(param "variant_id")")
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  if ! valid_id "$variant_id"; then
    printf '{"success":false,"error":"invalid variant_id"}\n'
    return 0
  fi
  if [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for promote"}\n'
    return 0
  fi
  if ! mr_controller_variant_promote "$variant_id"; then
    printf '{"success":false,"error":"variant not found"}\n'
    return 0
  fi
  printf '{"success":true,"variant_id":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$variant_id")" \
    "$(mode_runtime_state_json)"
}

mr_controller_variant_rollback_response() {
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  if [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for rollback"}\n'
    return 0
  fi
  if ! mr_controller_variant_rollback; then
    printf '{"success":false,"error":"rollback target unavailable"}\n'
    return 0
  fi
  printf '{"success":true,"mode_runtime":%s}\n' "$(mode_runtime_state_json)"
}

mr_improvement_proposal_create_response() {
  title_text=$(trim "$(param "title")")
  rationale_text=$(trim "$(param "rationale")")
  proposed_change_text=$(trim "$(param "proposed_change")")
  scope_text=$(trim "$(param "scope")")
  risk_level_text=$(trim "$(param "risk_level")")

  if [ -z "$title_text" ]; then
    printf '{"success":false,"error":"title is required"}\n'
    return 0
  fi
  proposal_id=$(mr_improvement_proposal_create "$title_text" "$rationale_text" "$proposed_change_text" "$scope_text" "$risk_level_text" "manual")
  printf '{"success":true,"proposal_id":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$proposal_id")" \
    "$(mode_runtime_state_json)"
}

mr_improvement_proposal_generate_response() {
  generated_json=$(mr_improvement_proposal_generate_from_taxonomy_json)
  printf '{"success":true,"result":%s,"mode_runtime":%s}\n' "$generated_json" "$(mode_runtime_state_json)"
}

mr_improvement_proposal_decide_response() {
  proposal_id=$(trim "$(param "proposal_id")")
  decision_raw=$(trim "$(param "decision")")
  decision_note=$(param "note")
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  decision_value="accepted"

  if ! valid_id "$proposal_id"; then
    printf '{"success":false,"error":"invalid proposal_id"}\n'
    return 0
  fi

  case "$decision_raw" in
    accept|accepted)
      decision_value="accepted"
      ;;
    apply|applied)
      decision_value="applied"
      ;;
    reject|rejected|dismiss|dismissed)
      decision_value="rejected"
      ;;
    *)
      printf '{"success":false,"error":"invalid decision"}\n'
      return 0
      ;;
  esac

  if [ "$decision_value" = "applied" ] && [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for apply"}\n'
    return 0
  fi

  if ! mr_improvement_proposal_set_status "$proposal_id" "$decision_value" "$decision_note"; then
    printf '{"success":false,"error":"proposal not found"}\n'
    return 0
  fi

  printf '{"success":true,"proposal_id":"%s","decision":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$proposal_id")" \
    "$(json_escape "$decision_value")" \
    "$(mode_runtime_state_json)"
}

mr_mode_runtime_skill_invoke_response() {
  mode_id=$(trim "$(param "mode_id")")
  skill_id=$(trim "$(param "skill_id")")
  input_text=$(param "input")
  requested_caps=$(param "capabilities")

  if [ -z "$skill_id" ]; then
    printf '{"success":false,"error":"skill_id is required"}\n'
    return 0
  fi

  mr_skill_invoke_json "$mode_id" "$skill_id" "$input_text" "$requested_caps"
  printf '\n'
}

mr_skill_name_from_trigger_file() {
  trigger_file=$1
  if [ ! -f "$trigger_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(sed -n 's/^name:[[:space:]]*"\{0,1\}\(.*\)"\{0,1\}[[:space:]]*$/\1/p' "$trigger_file" | sed -n '1p')
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_skill_trigger_from_trigger_file() {
  trigger_file=$1
  if [ ! -f "$trigger_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(sed -n 's/^[[:space:]]*-[[:space:]]*"\{0,1\}\(.*\)"\{0,1\}[[:space:]]*$/\1/p' "$trigger_file" | sed -n '1p')
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_skill_caps_from_tools_file() {
  tools_file=$1
  if [ ! -f "$tools_file" ]; then
    printf '%s' ""
    return 0
  fi
  raw=$(tr -d '\n\r' < "$tools_file" | sed -n 's/.*"tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | sed -n '1p')
  if [ -z "$(trim "$raw")" ]; then
    printf '%s' ""
    return 0
  fi
  normalized=$(printf '%s' "$raw" | tr '"' ' ' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | paste -sd, -)
  printf '%s' "$(mr_csv_normalize "$normalized")"
}

mr_skill_description_from_policy_file() {
  policy_file=$1
  if [ ! -f "$policy_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(awk 'NF { if ($0 ~ /^#/) next; print; exit }' "$policy_file")
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_mode_runtime_skill_create_response() {
  skill_id=$(trim "$(param "skill_id")")
  skill_name=$(trim "$(param "name")")
  trigger_text=$(trim "$(param "trigger")")
  capabilities=$(trim "$(param "capabilities")")
  description_text=$(trim "$(param "description")")

  skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
  if ! valid_id "$skill_id"; then
    printf '{"success":false,"error":"invalid skill_id"}\n'
    return 0
  fi
  if mr_skill_exists "$skill_id"; then
    printf '{"success":false,"error":"skill already exists"}\n'
    return 0
  fi
  if [ -z "$skill_name" ]; then
    skill_name=$skill_id
  fi
  if [ -z "$trigger_text" ]; then
    trigger_text="when manually invoked"
  fi
  if [ -z "$capabilities" ]; then
    capabilities="filesystem"
  fi
  if [ -z "$description_text" ]; then
    description_text="Custom skill bundle created from the Artificer skill manager."
  fi

  mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  printf '{"success":true,"skill_id":"%s","mode_runtime":%s}\n' "$(json_escape "$skill_id")" "$(mode_runtime_state_json)"
}

mr_mode_runtime_skill_install_response() {
  source_path=$(trim "$(param "source_path")")
  skill_id_raw=$(trim "$(param "skill_id")")
  replace_raw=$(trim "$(param "replace")")
  replace_existing=$(mr_bool_norm "$replace_raw")

  if [ -z "$source_path" ]; then
    printf '{"success":false,"error":"source_path is required"}\n'
    return 0
  fi
  if [ ! -d "$source_path" ]; then
    printf '{"success":false,"error":"source_path is not a directory"}\n'
    return 0
  fi

  skill_id=$skill_id_raw
  if [ -z "$skill_id" ]; then
    skill_id=$(basename "$source_path")
  fi
  skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
  if ! valid_id "$skill_id"; then
    printf '{"success":false,"error":"invalid skill_id"}\n'
    return 0
  fi

  target_dir=$(mr_skill_dir_for "$skill_id")
  if mr_skill_exists "$skill_id" && [ "$replace_existing" != "1" ]; then
    printf '{"success":false,"error":"skill already exists (set replace=1 to overwrite)"}\n'
    return 0
  fi

  missing=""
  for required_file in policy.md trigger.yaml tools.json output.schema.json; do
    if [ ! -f "$source_path/$required_file" ]; then
      if [ -n "$missing" ]; then
        missing="$missing,$required_file"
      else
        missing="$required_file"
      fi
    fi
  done
  if [ -n "$missing" ]; then
    printf '{"success":false,"error":"source bundle is missing required files","missing":%s}\n' "$(mr_csv_to_json_array "$missing")"
    return 0
  fi

  source_policy="$source_path/policy.md"
  source_trigger="$source_path/trigger.yaml"
  source_tools="$source_path/tools.json"
  source_schema="$source_path/output.schema.json"

  skill_name=$(mr_skill_name_from_trigger_file "$source_trigger")
  trigger_text=$(mr_skill_trigger_from_trigger_file "$source_trigger")
  capabilities=$(mr_skill_caps_from_tools_file "$source_tools")
  description_text=$(mr_skill_description_from_policy_file "$source_policy")

  if [ -z "$skill_name" ]; then
    skill_name=$skill_id
  fi
  if [ -z "$trigger_text" ]; then
    trigger_text="when manually invoked"
  fi
  if [ -z "$capabilities" ]; then
    capabilities="filesystem"
  fi
  if [ -z "$description_text" ]; then
    description_text="Installed external skill bundle."
  fi

  if [ "$replace_existing" = "1" ] && [ -d "$target_dir" ]; then
    rm -rf "$target_dir"
  fi

  mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  cp "$source_policy" "$target_dir/policy.md"
  cp "$source_trigger" "$target_dir/trigger.yaml"
  cp "$source_tools" "$target_dir/tools.json"
  cp "$source_schema" "$target_dir/output.schema.json"

  meta_file=$(mr_skill_meta_file "$skill_id")
  {
    printf 'id=%s\n' "$skill_id"
    printf 'name=%s\n' "$(mr_sanitize_inline "$skill_name")"
    printf 'trigger=%s\n' "$(mr_sanitize_inline "$trigger_text")"
    printf 'capabilities=%s\n' "$(mr_csv_normalize "$capabilities")"
    printf 'description=%s\n' "$(mr_sanitize_inline "$description_text")"
    printf 'stateless=1\n'
    printf 'interrupt_authority=0\n'
  } > "$meta_file"

  printf '{"success":true,"skill_id":"%s","replaced":%s,"mode_runtime":%s}\n' \
    "$(json_escape "$skill_id")" \
    "$( [ "$replace_existing" = "1" ] && printf 'true' || printf 'false' )" \
    "$(mode_runtime_state_json)"
}
