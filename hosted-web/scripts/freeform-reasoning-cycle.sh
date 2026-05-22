#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PARENT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)

SITE_ROOT=""
if [ -x "$PROJECT_ROOT/hosted-web/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT/hosted-web"
elif [ -x "$PROJECT_ROOT/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT"
elif [ -x "$PARENT_ROOT/web/artificer/cgi/artificer-api" ]; then
  SITE_ROOT="$PARENT_ROOT/web/artificer"
fi

if [ -z "$SITE_ROOT" ]; then
  echo "Could not locate artificer site root from $SCRIPT_DIR" >&2
  exit 1
fi

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

API="$SITE_ROOT/cgi/artificer-api"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_TASKS="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v75-freeformtersefinalfit.tsv"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for freeform reasoning assays." >&2
  exit 1
fi

cleanup_workspace_id=""
cleanup_workspace_path=""

usage() {
  cat <<'USAGE'
Usage:
  freeform-reasoning-cycle.sh run [--label NAME] [--tasks-file FILE] [--request-timeout-sec N] [--settle-timeout-sec N]
  freeform-reasoning-cycle.sh transfer [--label NAME] --battery-summary FILE --holdout-summary FILE [--enforce-gates]

Notes:
  - The freeform runner exercises the live non-assay auto/quick path for short normal-prose reasoning memos.
  - Tasks may optionally include a followup_prompt column; when present, the runner sends
    the first prompt, waits for completion, then sends follow-up turns in the same thread and
    scores the final assistant reply.
  - Multiple follow-up turns may be encoded in followup_prompt with `|||` separators.
  - Prompts are sent as-is with run_mode=auto, compute_budget=quick, and advanced_loop=0.
USAGE
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

cleanup_workspace() {
  if [ -n "$cleanup_workspace_id" ]; then
    post_api "action=delete_workspace&workspace_id=$(urlenc "$cleanup_workspace_id")" >/dev/null 2>&1 || true
    cleanup_workspace_id=""
  fi
  if [ -n "$cleanup_workspace_path" ]; then
    rm -rf "$cleanup_workspace_path" >/dev/null 2>&1 || true
    cleanup_workspace_path=""
  fi
}

trap 'cleanup_workspace' EXIT HUP INT TERM

urlenc() {
  jq -rn --arg v "$1" '$v|@uri'
}

json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

post_api() {
  body=$1
  REQUEST_METHOD=POST sh "$API" <<EOF_BODY
$body
EOF_BODY
}

post_api_json() {
  body=$1
  raw=$(post_api "$body")
  json=$(printf '%s' "$raw" | json_only)
  if [ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ]; then
    echo "API response did not include JSON payload." >&2
    return 1
  fi
  ok=$(printf '%s' "$json" | jq -r 'if (type=="object" and has("success")) then (.success|tostring) else "true" end' 2>/dev/null || printf '%s' "false")
  if [ "$ok" = "false" ]; then
    err=$(printf '%s' "$json" | jq -r '.error // "unknown error"' 2>/dev/null || printf '%s' "unknown error")
    echo "API returned failure: $err" >&2
    return 1
  fi
  printf '%s' "$json"
}

run_with_timeout() {
  timeout_sec=$1
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_sec" "$@"
}

post_api_with_timeout() {
  timeout_sec=$1
  body=$2
  body_file=$(mktemp "${TMPDIR:-/tmp}/artificer-freeform-body.XXXXXX")
  printf '%s' "$body" > "$body_file"
  set +e
  run_with_timeout "$timeout_sec" sh -c 'REQUEST_METHOD=POST sh "$1" < "$2"' sh "$API" "$body_file"
  status=$?
  set -e
  rm -f "$body_file"
  return "$status"
}

run_turn() {
  workspace_id=$1
  conversation_id=$2
  prompt_text=$3
  request_timeout_sec=$4
  settle_timeout_sec=$5

  body="action=run&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&prompt=$(urlenc "$prompt_text")&run_mode=auto&compute_budget=quick&advanced_loop=0&max_iterations=7"
  submit_timed_out=0
  if ! post_api_with_timeout "$request_timeout_sec" "$body" >/dev/null 2>&1; then
    submit_timed_out=1
    post_api "action=queue_stop&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")" >/dev/null 2>&1 || true
  fi

  poll_count=0
  poll_limit=$((settle_timeout_sec * 4))
  turn_state_json='{}'
  turn_queue_json='{}'
  turn_assistant_text=""
  turn_run_event_id=""
  turn_run_status=""
  turn_stream_text=""
  while [ "$poll_count" -lt "$poll_limit" ]; do
    turn_queue_json=$(post_api_json "action=queue_list&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&limit=1")
    turn_state_json=$(post_api_json "action=get_conversation&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")")
    turn_assistant_text=$(printf '%s' "$turn_state_json" | jq -r '.conversation.messages | map(select(.role=="assistant")) | last | .content // ""')
    turn_run_event_id=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].id // ""')
    turn_run_status=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].status // ""')
    turn_stream_text=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].stream_text // ""')
    queue_running=$(printf '%s' "$turn_queue_json" | jq -r '.queue_running // 0')

    if [ "$queue_running" != "1" ] && [ -n "$(trim "$turn_assistant_text")" ]; then
      break
    fi
    if [ "$queue_running" != "1" ] && { [ "$turn_run_status" = "error" ] || [ "$turn_run_status" = "timeout" ]; }; then
      break
    fi
    sleep 0.25
    poll_count=$((poll_count + 1))
  done

  if [ -z "$turn_run_status" ]; then
    turn_run_status="pending"
  fi
  if [ "$submit_timed_out" -eq 1 ]; then
    turn_run_status="timeout"
  elif [ -z "$(trim "$turn_assistant_text")" ] && [ "$turn_run_status" = "pending" ]; then
    turn_run_status="timeout"
  fi
}

run_followup_sequence() {
  workspace_id=$1
  conversation_id=$2
  followup_text=$3
  request_timeout_sec=$4
  settle_timeout_sec=$5

  followup_text=$(trim "$followup_text")
  [ -n "$followup_text" ] || return 0

  followup_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-freeform-followups.XXXXXX")
  printf '%s\n' "$followup_text" | awk '
    {
      line = $0
      gsub(/[[:space:]]*\|\|\|[[:space:]]*/, "\n", line)
      print line
    }
  ' | sed '/^[[:space:]]*$/d' > "$followup_tmp"

  while IFS= read -r next_followup || [ -n "$next_followup" ]; do
    next_followup=$(trim "$next_followup")
    [ -n "$next_followup" ] || continue
    run_turn "$workspace_id" "$conversation_id" "$next_followup" "$request_timeout_sec" "$settle_timeout_sec"
    if [ "$turn_run_status" != "done" ] || [ -z "$(trim "$turn_assistant_text")" ]; then
      break
    fi
  done < "$followup_tmp"

  rm -f "$followup_tmp"
}

score_freeform_row() {
  assistant_text=$1
  run_status=$2
  task_id=$3
  mode=$4
  budget=$5
  domain=$6
  pair_id=$7
  variant=$8
  tactics=$9
  required_patterns=${10}
  forbidden_patterns=${11}
  conversation_id=${12}
  run_event_id=${13}

  jq -rn \
    --arg assistant_text "$assistant_text" \
    --arg run_status "$run_status" \
    --arg task_id "$task_id" \
    --arg mode "$mode" \
    --arg budget "$budget" \
    --arg domain "$domain" \
    --arg pair_id "$pair_id" \
    --arg variant "$variant" \
    --arg tactics "$tactics" \
    --arg required_patterns "$required_patterns" \
    --arg forbidden_patterns "$forbidden_patterns" \
    --arg conversation_id "$conversation_id" \
    --arg run_event_id "$run_event_id" '
      def trim_text: gsub("^[[:space:]]+|[[:space:]]+$";"");
      def split_patterns(s): (s | split(";") | map(trim_text) | map(select(length > 0)));
      ($assistant_text | gsub("\r";"")) as $assistant |
      ($assistant | ascii_downcase) as $assistant_lower |
      ($mode | ascii_downcase) as $mode_lower |
      ($assistant | split("\n") | map(select(length > 0))) as $lines |
      ($lines | length) as $line_count |
      (split_patterns($required_patterns)) as $required |
      (split_patterns($forbidden_patterns)) as $forbidden |
      ([ $required[] as $pattern | select($assistant | test($pattern; "im")) ] | length) as $required_hits |
      ([ $forbidden[] as $pattern | select($assistant | test($pattern; "im")) ] | length) as $forbidden_hits |
      (($assistant_lower | test("(^|\\n)(outcome|decision|fallback path|disconfirming evidence|risks|next improvement|initial assumption|invalidating evidence|revised decision|evidence delta):"; "m"))
        or ($assistant | test("(^|\\n)\\s*[-*][[:space:]]"; "m"))
        or ($assistant | test("(^|\\n)#+[[:space:]]"; "m"))) as $label_signal |
      ($mode_lower | test("clarify")) as $clarify_expected |
      ($mode_lower | test("reflect")) as $reflect_expected |
      ($mode_lower | test("frame")) as $frame_expected |
      ($assistant_lower | test("main uncertainty|largest uncertainty|key uncertainty|uncertainty is|uncertainty remains|the main uncertainty")) as $uncertainty_signal |
      ($assistant_lower | test("i would reverse|would reverse|i would revisit|would revisit|i would change|would change")) as $reversal_signal |
      ($assistant_lower | test("do you want|are you just|capturing .*notes|recording .*notes|if you want the call|if you want analysis")) as $clarify_phrase_signal |
      ($assistant_lower | test("the tension is")) as $tension_signal |
      ($assistant_lower | test("the unresolved question is")) as $unresolved_signal |
      ($assistant_lower | test("not a settled decision request yet")) as $frame_status_signal |
      ($assistant_lower | test("the key moving parts are")) as $moving_parts_signal |
      ($assistant | test("\\?")) as $question_signal |
      (($line_count <= 4) and ($label_signal | not)) as $freeform_hit |
      (($line_count <= 2) and ($label_signal | not) and $question_signal and $clarify_phrase_signal) as $clarify_hit |
      (($line_count <= 3) and ($label_signal | not) and ($question_signal | not) and $tension_signal and $unresolved_signal) as $reflect_hit |
      (($line_count <= 3) and ($label_signal | not) and ($question_signal | not) and $frame_status_signal and $moving_parts_signal) as $frame_hit |
      (if $clarify_expected then $clarify_hit elif $reflect_expected then $reflect_hit elif $frame_expected then $frame_hit else $freeform_hit end) as $style_hit |
      ($required | length) as $required_total |
      (if $required_total == 0 then 1 else ($required_hits / $required_total) end) as $required_ratio |
      ((if $style_hit then 30 else 0 end)
       + (50 * $required_ratio)
       + (if $forbidden_hits == 0 then 10 else 0 end)
       + (if $clarify_expected then
            (if $question_signal then 5 else 0 end)
            + (if $clarify_phrase_signal then 5 else 0 end)
          elif $reflect_expected then
            (if $tension_signal then 5 else 0 end)
            + (if $unresolved_signal then 5 else 0 end)
          elif $frame_expected then
            (if $frame_status_signal then 5 else 0 end)
            + (if $moving_parts_signal then 5 else 0 end)
          else
            (if $uncertainty_signal then 5 else 0 end)
            + (if $reversal_signal then 5 else 0 end)
          end)) as $overall_raw |
      ($overall_raw | floor) as $overall |
      (if (($run_status != "done") or ($style_hit | not) or ($forbidden_hits > 0) or ($required_ratio < 1)
           or ($clarify_expected and (($question_signal | not) or ($clarify_phrase_signal | not)))
           or ($reflect_expected and (($tension_signal | not) or ($unresolved_signal | not)))
           or ($frame_expected and (($frame_status_signal | not) or ($moving_parts_signal | not)))
           or (( $clarify_expected | not) and ($reflect_expected | not) and ($frame_expected | not) and (($uncertainty_signal | not) or ($reversal_signal | not))))
        then 1 else 0 end) as $fail_open |
      (if (($forbidden_hits > 0) or $label_signal) then 1 else 0 end) as $contradiction |
      (if (($style_hit | not)
           or ($clarify_expected and (($question_signal | not) or ($clarify_phrase_signal | not)))
           or ($reflect_expected and (($tension_signal | not) or ($unresolved_signal | not)))
           or ($frame_expected and (($frame_status_signal | not) or ($moving_parts_signal | not)))
           or (( $clarify_expected | not) and ($reflect_expected | not) and ($frame_expected | not) and (($uncertainty_signal | not) or ($reversal_signal | not))))
        then 1 else 0 end) as $shallow_completion |
      [
        $task_id,
        $mode,
        $budget,
        $domain,
        $pair_id,
        $variant,
        $tactics,
        $run_status,
        ($line_count|tostring),
        (if $freeform_hit then "1" else "0" end),
        (if $clarify_hit then "1" else "0" end),
        (if $reflect_hit then "1" else "0" end),
        (if $frame_hit then "1" else "0" end),
        (if $style_hit then "1" else "0" end),
        (if $uncertainty_signal then "1" else "0" end),
        (if $reversal_signal then "1" else "0" end),
        (if $tension_signal then "1" else "0" end),
        (if $unresolved_signal then "1" else "0" end),
        (if $frame_status_signal then "1" else "0" end),
        (if $moving_parts_signal then "1" else "0" end),
        ($required_ratio|tostring),
        ($forbidden_hits|tostring),
        ($overall|tostring),
        ($fail_open|tostring),
        ($contradiction|tostring),
        ($shallow_completion|tostring),
        $conversation_id,
        $run_event_id
      ] | @tsv
    '
}

write_summary_json() {
  score_file=$1
  summary_file=$2
  awk -F '\t' '
    NR == 1 { next }
    {
      tasks += 1
      if ($8 == "done") done += 1
      line_sum += $9
      style_sum += $14
      if (tolower($2) ~ /clarify/) {
        clarify_tasks += 1
        clarify_sum += $11
      } else if (tolower($2) ~ /reflect/) {
        reflect_tasks += 1
        reflect_sum += $12
        tension_sum += $17
        unresolved_sum += $18
      } else if (tolower($2) ~ /frame/) {
        frame_tasks += 1
        frame_sum += $13
        frame_status_sum += $19
        moving_parts_sum += $20
      } else {
        report_tasks += 1
        freeform_sum += $10
        uncertainty_sum += $15
        reversal_sum += $16
      }
      required_sum += $21
      forbidden_sum += $22
      overall_sum += $23
      fail_open_sum += $24
      contradiction_sum += $25
      shallow_sum += $26
    }
    END {
      if (tasks == 0) {
        tasks = 1
      }
      if (report_tasks == 0) {
        report_tasks = 1
        freeform_sum = report_tasks
        uncertainty_sum = report_tasks
        reversal_sum = report_tasks
      }
      if (clarify_tasks == 0) {
        clarify_tasks = 1
        clarify_sum = clarify_tasks
      }
      if (reflect_tasks == 0) {
        reflect_tasks = 1
        reflect_sum = reflect_tasks
        tension_sum = reflect_tasks
        unresolved_sum = reflect_tasks
      }
      if (frame_tasks == 0) {
        frame_tasks = 1
        frame_sum = frame_tasks
        frame_status_sum = frame_tasks
        moving_parts_sum = frame_tasks
      }
      printf "{\"tasks\":%d,\"done\":%d,\"report_tasks\":%d,\"clarify_tasks\":%d,\"reflect_tasks\":%d,\"frame_tasks\":%d,\"avg_line_count\":%.2f,\"style_rate\":%.4f,\"freeform_rate\":%.4f,\"clarify_rate\":%.4f,\"reflect_rate\":%.4f,\"frame_rate\":%.4f,\"uncertainty_rate\":%.4f,\"reversal_rate\":%.4f,\"tension_rate\":%.4f,\"unresolved_rate\":%.4f,\"frame_status_rate\":%.4f,\"moving_parts_rate\":%.4f,\"avg_required_ratio\":%.4f,\"forbidden_hit_rate\":%.4f,\"avg_overall\":%.2f,\"fail_open_rate\":%.4f,\"contradiction_rate\":%.4f,\"shallow_completion_rate\":%.4f}\n", \
        tasks, done, report_tasks, clarify_tasks, reflect_tasks, frame_tasks, line_sum / tasks, style_sum / tasks, freeform_sum / report_tasks, clarify_sum / clarify_tasks, reflect_sum / reflect_tasks, frame_sum / frame_tasks, uncertainty_sum / report_tasks, reversal_sum / report_tasks, tension_sum / reflect_tasks, unresolved_sum / reflect_tasks, frame_status_sum / frame_tasks, moving_parts_sum / frame_tasks, required_sum / tasks, forbidden_sum / tasks, overall_sum / tasks, fail_open_sum / tasks, contradiction_sum / tasks, shallow_sum / tasks
    }
  ' "$score_file" > "$summary_file"
}

write_report_md() {
  label=$1
  summary_file=$2
  report_file=$3
  {
    printf '# Freeform Reasoning Cycle: %s\n\n' "$label"
    printf -- '- Tasks: %s\n' "$(jq -r '.tasks' "$summary_file")"
    printf -- '- Done: %s\n' "$(jq -r '.done' "$summary_file")"
    printf -- '- Report tasks: %s\n' "$(jq -r '.report_tasks' "$summary_file")"
    printf -- '- Clarify tasks: %s\n' "$(jq -r '.clarify_tasks' "$summary_file")"
    printf -- '- Reflect tasks: %s\n' "$(jq -r '.reflect_tasks' "$summary_file")"
    printf -- '- Frame tasks: %s\n' "$(jq -r '.frame_tasks' "$summary_file")"
    printf -- '- Avg line count: %s\n' "$(jq -r '.avg_line_count' "$summary_file")"
    printf -- '- Style match rate: %s\n' "$(jq -r '.style_rate' "$summary_file")"
    printf -- '- Freeform rate: %s\n' "$(jq -r '.freeform_rate' "$summary_file")"
    printf -- '- Clarify rate: %s\n' "$(jq -r '.clarify_rate' "$summary_file")"
    printf -- '- Reflect rate: %s\n' "$(jq -r '.reflect_rate' "$summary_file")"
    printf -- '- Frame rate: %s\n' "$(jq -r '.frame_rate' "$summary_file")"
    printf -- '- Uncertainty rate: %s\n' "$(jq -r '.uncertainty_rate' "$summary_file")"
    printf -- '- Reversal rate: %s\n' "$(jq -r '.reversal_rate' "$summary_file")"
    printf -- '- Tension rate: %s\n' "$(jq -r '.tension_rate' "$summary_file")"
    printf -- '- Unresolved rate: %s\n' "$(jq -r '.unresolved_rate' "$summary_file")"
    printf -- '- Frame status rate: %s\n' "$(jq -r '.frame_status_rate' "$summary_file")"
    printf -- '- Moving parts rate: %s\n' "$(jq -r '.moving_parts_rate' "$summary_file")"
    printf -- '- Avg required ratio: %s\n' "$(jq -r '.avg_required_ratio' "$summary_file")"
    printf -- '- Avg overall: %s\n' "$(jq -r '.avg_overall' "$summary_file")"
    printf -- '- Fail-open rate: %s\n' "$(jq -r '.fail_open_rate' "$summary_file")"
    printf -- '- Contradiction rate: %s\n' "$(jq -r '.contradiction_rate' "$summary_file")"
    printf -- '- Shallow completion rate: %s\n' "$(jq -r '.shallow_completion_rate' "$summary_file")"
  } > "$report_file"
}

run_panel() {
  label=$1
  tasks_file=$2
  request_timeout_sec=$3
  settle_timeout_sec=$4

  mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"

  score_file="$OUT_DIR/$label-scores.tsv"
  summary_file="$OUT_DIR/$label-summary.json"
  report_file="$OUT_DIR/$label-report.md"

  printf 'task_id\tmode\tbudget\tdomain\tpair_id\tvariant\ttactics\tstatus\tline_count\tfreeform_hit\tclarify_hit\treflect_hit\tframe_hit\tstyle_hit\tuncertainty_hit\treversal_hit\ttension_hit\tunresolved_hit\tframe_status_hit\tmoving_parts_hit\trequired_ratio\tforbidden_hits\toverall\tfail_open\tcontradiction\tshallow_completion\tconversation_id\trun_event_id\n' > "$score_file"

  cleanup_workspace_path=$(mktemp -d "${TMPDIR:-/tmp}/artificer-freeform-workspace.XXXXXX")
  ws_json=$(post_api_json "action=add_workspace&path=$(urlenc "$cleanup_workspace_path")&name=$(urlenc "Freeform Reasoning $label")")
  cleanup_workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id')
  if [ -z "$cleanup_workspace_id" ] || [ "$cleanup_workspace_id" = "null" ]; then
    echo "Failed to create workspace for freeform reasoning run." >&2
    exit 1
  fi

  tab_char=$(printf '\t')
  while IFS="$tab_char" read -r task_id mode budget domain pair_id variant tactics required_patterns forbidden_patterns prompt followup_prompt || [ -n "$task_id" ]; do
    task_id=$(trim "$task_id")
    [ -n "$task_id" ] || continue
    case "$task_id" in
      task_id) continue ;;
      \#*) continue ;;
    esac

    mkdir -p "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id"

    conv_title="${label}-${task_id}"
    conv_json=$(post_api_json "action=new_conversation&workspace_id=$(urlenc "$cleanup_workspace_id")&title=$(urlenc "$conv_title")")
    conv_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id')

    run_turn "$cleanup_workspace_id" "$conv_id" "$prompt" "$request_timeout_sec" "$settle_timeout_sec"
    followup_prompt=$(trim "${followup_prompt:-}")
    if [ -n "$followup_prompt" ] && [ "$turn_run_status" = "done" ] && [ -n "$(trim "$turn_assistant_text")" ]; then
      run_followup_sequence "$cleanup_workspace_id" "$conv_id" "$followup_prompt" "$request_timeout_sec" "$settle_timeout_sec"
    fi

    printf '%s\n' "$turn_state_json" > "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id/state.json"
    printf '%s\n' "$turn_queue_json" > "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id/queue.json"
    printf '%s\n' "$turn_stream_text" > "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id/stream.txt"
    printf '%s\n' "$turn_assistant_text" > "$ARTIFICER_ASSAY_RUNS_DIR/$label/$task_id/assistant.txt"

    score_line=$(score_freeform_row "$turn_assistant_text" "$turn_run_status" "$task_id" "$mode" "$budget" "$domain" "$pair_id" "$variant" "$tactics" "$required_patterns" "$forbidden_patterns" "$conv_id" "$turn_run_event_id")
    printf '%s\n' "$score_line" >> "$score_file"
    printf 'freeform[%s] done: %s\n' "$label" "$task_id"
  done < "$tasks_file"

  write_summary_json "$score_file" "$summary_file"
  write_report_md "$label" "$summary_file" "$report_file"

  printf '%s\n%s\n%s\n' "$score_file" "$summary_file" "$report_file"
}

run_transfer() {
  label=$1
  battery_summary=$2
  holdout_summary=$3
  enforce_gates=$4

  mkdir -p "$OUT_DIR"
  transfer_json="$OUT_DIR/$label-transfer.json"
  transfer_md="$OUT_DIR/$label-transfer.md"

  jq -n \
    --arg label "$label" \
    --slurpfile battery "$battery_summary" \
    --slurpfile holdout "$holdout_summary" '
      ($battery[0]) as $battery |
      ($holdout[0]) as $holdout |
      {
        label: $label,
        battery: $battery,
        holdout: $holdout,
        deltas: {
          overall: (($holdout.avg_overall // 0) - ($battery.avg_overall // 0)),
          style_rate: (($holdout.style_rate // 0) - ($battery.style_rate // 0)),
          required_ratio: (($holdout.avg_required_ratio // 0) - ($battery.avg_required_ratio // 0)),
          freeform_rate: (($holdout.freeform_rate // 0) - ($battery.freeform_rate // 0)),
          clarify_rate: (($holdout.clarify_rate // 0) - ($battery.clarify_rate // 0)),
          reflect_rate: (($holdout.reflect_rate // 0) - ($battery.reflect_rate // 0)),
          frame_rate: (($holdout.frame_rate // 0) - ($battery.frame_rate // 0)),
          uncertainty_rate: (($holdout.uncertainty_rate // 0) - ($battery.uncertainty_rate // 0)),
          reversal_rate: (($holdout.reversal_rate // 0) - ($battery.reversal_rate // 0)),
          tension_rate: (($holdout.tension_rate // 0) - ($battery.tension_rate // 0)),
          unresolved_rate: (($holdout.unresolved_rate // 0) - ($battery.unresolved_rate // 0)),
          frame_status_rate: (($holdout.frame_status_rate // 0) - ($battery.frame_status_rate // 0)),
          moving_parts_rate: (($holdout.moving_parts_rate // 0) - ($battery.moving_parts_rate // 0)),
          fail_open_rate: (($holdout.fail_open_rate // 0) - ($battery.fail_open_rate // 0)),
          contradiction_rate: (($holdout.contradiction_rate // 0) - ($battery.contradiction_rate // 0))
        },
        gates: {
          fail_open_non_increase: (($holdout.fail_open_rate // 0) <= ($battery.fail_open_rate // 0)),
          contradiction_non_increase: (($holdout.contradiction_rate // 0) <= ($battery.contradiction_rate // 0)),
          holdout_not_worse_overall: (($holdout.avg_overall // 0) >= ($battery.avg_overall // 0)),
          style_full: (($battery.style_rate // 0) >= 1 and ($holdout.style_rate // 0) >= 1),
          freeform_full: (($battery.freeform_rate // 0) >= 1 and ($holdout.freeform_rate // 0) >= 1),
          clarify_full: (($battery.clarify_rate // 0) >= 1 and ($holdout.clarify_rate // 0) >= 1),
          reflect_full: (($battery.reflect_rate // 0) >= 1 and ($holdout.reflect_rate // 0) >= 1),
          frame_full: (($battery.frame_rate // 0) >= 1 and ($holdout.frame_rate // 0) >= 1),
          uncertainty_full: (($battery.uncertainty_rate // 0) >= 1 and ($holdout.uncertainty_rate // 0) >= 1),
          reversal_full: (($battery.reversal_rate // 0) >= 1 and ($holdout.reversal_rate // 0) >= 1),
          tension_full: (($battery.tension_rate // 0) >= 1 and ($holdout.tension_rate // 0) >= 1),
          unresolved_full: (($battery.unresolved_rate // 0) >= 1 and ($holdout.unresolved_rate // 0) >= 1),
          frame_status_full: (($battery.frame_status_rate // 0) >= 1 and ($holdout.frame_status_rate // 0) >= 1),
          moving_parts_full: (($battery.moving_parts_rate // 0) >= 1 and ($holdout.moving_parts_rate // 0) >= 1),
          required_ratio_full: (($battery.avg_required_ratio // 0) >= 1 and ($holdout.avg_required_ratio // 0) >= 1)
        }
      }
      | .all_gates_pass = (
          .gates.fail_open_non_increase and
          .gates.contradiction_non_increase and
          .gates.holdout_not_worse_overall and
          .gates.style_full and
          .gates.freeform_full and
          .gates.clarify_full and
          .gates.reflect_full and
          .gates.frame_full and
          .gates.uncertainty_full and
          .gates.reversal_full and
          .gates.tension_full and
          .gates.unresolved_full and
          .gates.frame_status_full and
          .gates.moving_parts_full and
          .gates.required_ratio_full
        )
      | .transfer_risk = (if .all_gates_pass then "low" else "medium" end)
    ' > "$transfer_json"

  {
    printf '# Freeform Transfer: %s\n\n' "$label"
    printf -- '- Transfer JSON: `%s`\n' "$transfer_json"
    printf -- '- All gates pass: %s\n' "$(jq -r '.all_gates_pass' "$transfer_json")"
    printf -- '- Transfer risk: %s\n' "$(jq -r '.transfer_risk' "$transfer_json")"
  } > "$transfer_md"

  printf '%s\n%s\n' "$transfer_json" "$transfer_md"

  if [ "$enforce_gates" = "1" ] && [ "$(jq -r '.all_gates_pass' "$transfer_json")" != "true" ]; then
    echo "Freeform transfer gates failed for label '$label'." >&2
    exit 2
  fi
}

command=${1:-}
if [ -z "$command" ]; then
  usage >&2
  exit 1
fi
shift

label=""
tasks_file="$DEFAULT_TASKS"
request_timeout_sec=45
settle_timeout_sec=45
battery_summary=""
holdout_summary=""
enforce_gates=0

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --tasks-file)
      tasks_file=$2
      shift 2
      ;;
    --request-timeout-sec)
      request_timeout_sec=$2
      shift 2
      ;;
    --settle-timeout-sec)
      settle_timeout_sec=$2
      shift 2
      ;;
    --battery-summary)
      battery_summary=$2
      shift 2
      ;;
    --holdout-summary)
      holdout_summary=$2
      shift 2
      ;;
    --enforce-gates)
      enforce_gates=1
      shift
      ;;
    --help|-h|--usage)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$label" ]; then
  label="freeform-reasoning-$(date +%Y%m%d-%H%M%S)"
fi

case "$command" in
  run)
    run_panel "$label" "$tasks_file" "$request_timeout_sec" "$settle_timeout_sec"
    ;;
  transfer)
    if [ -z "$battery_summary" ] || [ -z "$holdout_summary" ]; then
      echo "transfer requires --battery-summary and --holdout-summary" >&2
      exit 1
    fi
    run_transfer "$label" "$battery_summary" "$holdout_summary" "$enforce_gates"
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
