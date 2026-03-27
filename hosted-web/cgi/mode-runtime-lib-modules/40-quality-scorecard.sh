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

