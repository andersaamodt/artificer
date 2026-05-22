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

