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

