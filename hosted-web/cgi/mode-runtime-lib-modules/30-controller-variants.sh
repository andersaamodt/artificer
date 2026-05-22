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

