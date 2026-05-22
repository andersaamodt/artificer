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

