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
DECISION_FIXTURE_FILE="$SITE_ROOT/tests/fixtures/artificer-decision-surfacing-fixtures.psv"
LEGACY_DECISION_FIXTURE_FILE="$PROJECT_ROOT/.tests/apps/fixtures/artificer-decision-surfacing-fixtures.psv"

SCORE_DEFAULT_MIN_CMD=2
SCORE_DEFAULT_MIN_STEPS=12
SCORE_DEFAULT_MIN_TS=2
SCORE_DEFAULT_MIN_FOLD_STEPS=9
SCORE_STRICT_MIN_CMD=2
SCORE_STRICT_MIN_STEPS=15
SCORE_STRICT_MIN_TS=3
SCORE_STRICT_MIN_FOLD_STEPS=11

usage() {
  cat <<'EOF'
Usage:
  assay-cycle.sh run [--label NAME] [--timeout-sec N] [--run-budget-sec N] [--timeout-buffer-sec N] [--attempts N] [--mentor-from FILE] [--max-tasks N] [--tasks-file FILE] [--strict-scoring]
  assay-cycle.sh mentor [--label NAME] [--cycles N] [--timeout-sec N] [--run-budget-sec N] [--timeout-buffer-sec N] [--attempts N] [--mentor-from FILE] [--max-tasks N] [--tasks-file FILE] [--strict-scoring]
  assay-cycle.sh compare --before FILE --after FILE
  assay-cycle.sh decisions [--label NAME] [--fixtures FILE]

Examples:
  hosted-web/scripts/assay-cycle.sh run --label baseline
  hosted-web/scripts/assay-cycle.sh run --label after
  hosted-web/scripts/assay-cycle.sh mentor --label mentor --cycles 2 --attempts 2
  hosted-web/scripts/assay-cycle.sh compare --before /path/to/baseline.tsv --after /path/to/after.tsv
EOF
}

urlenc() {
  jq -rn --arg v "$1" '$v|@uri'
}

trim_field() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

lower_field() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

task_row_is_header() {
  first=$(lower_field "$(trim_field "${1:-}")")
  second=$(lower_field "$(trim_field "${2:-}")")
  third=$(lower_field "$(trim_field "${3:-}")")
  case "$first:$second:$third" in
    task:mode:budget|task_id:mode:budget|task:run_mode:compute_budget|task_id:run_mode:compute_budget)
      return 0
      ;;
  esac
  return 1
}

json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

post_api() {
  body=$1
  if [ ! -x "$API" ]; then
    echo "API endpoint is not executable: $API" >&2
    return 1
  fi
  REQUEST_METHOD=POST sh "$API" <<EOF
$body
EOF
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

status_rank() {
  case "$1" in
    done) printf '%s' "6" ;;
    awaiting_approval|awaiting_decision) printf '%s' "5" ;;
    error) printf '%s' "4" ;;
    cancelled) printf '%s' "3" ;;
    timeout) printf '%s' "2" ;;
    running) printf '%s' "1" ;;
    *) printf '%s' "0" ;;
  esac
}

decision_fixture_file() {
  override_file=$1
  if [ -n "$override_file" ]; then
    printf '%s' "$override_file"
    return 0
  fi
  if [ -f "$DECISION_FIXTURE_FILE" ]; then
    printf '%s' "$DECISION_FIXTURE_FILE"
    return 0
  fi
  if [ -f "$LEGACY_DECISION_FIXTURE_FILE" ]; then
    printf '%s' "$LEGACY_DECISION_FIXTURE_FILE"
    return 0
  fi
  printf '%s' "$DECISION_FIXTURE_FILE"
}

mentor_suffix_for_task() {
  task_id=$1
  mentor_file=$2
  if [ -z "$mentor_file" ] || [ ! -f "$mentor_file" ]; then
    return 0
  fi
  line=$(awk -F '\t' -v t="$task_id" 'NR>1 && $1==t {print; exit}' "$mentor_file")
  [ -n "$line" ] || return 0
  prior_status=$(printf '%s' "$line" | awk -F '\t' '{print $4}')
  commands=$(printf '%s' "$line" | awk -F '\t' '{print $5+0}')
  steps=$(printf '%s' "$line" | awk -F '\t' '{print $6+0}')
  iq=$(printf '%s' "$line" | awk -F '\t' '{print $13+0}')
  flow=$(printf '%s' "$line" | awk -F '\t' '{print $14+0}')
  timestamp_steps=$(printf '%s' "$line" | awk -F '\t' '{print $15+0}')
  fold_ready=$(printf '%s' "$line" | awk -F '\t' '{print $16+0}')
  flow_strict=$(printf '%s' "$line" | awk -F '\t' '{print $17+0}')
  sections=$(printf '%s' "$line" | awk -F '\t' '{print $9+0}')
  control=$(printf '%s' "$line" | awk -F '\t' '{print $10+0}')
  verify=$(printf '%s' "$line" | awk -F '\t' '{print $11+0}')
  runtime_line=$(printf '%s' "$line" | awk -F '\t' '{print $12+0}')

  printf '\n\nAssay mentor guidance from prior cycle:\n'
  if [ "$prior_status" != "done" ]; then
    printf -- '- Prior cycle ended with status "%s"; tighten scope, assume missing inputs, and drive to a concrete best-effort completion.\n' "$prior_status"
  fi
  if [ "$iq" -lt 60 ]; then
    printf -- '- Raise intelligence score by increasing concrete execution depth and explicit verification.\n'
  fi
  if [ "$flow" -lt 60 ]; then
    printf -- '- Raise flow score with concise timestamp-style step updates and a cleaner final structure.\n'
  fi
  if [ "$commands" -lt 2 ] && [ "$prior_status" = "done" ]; then
    printf -- '- Increase concrete execution depth: include at least two meaningful commands when claiming completion.\n'
  fi
  if [ "$steps" -lt 8 ]; then
    printf -- '- Expand the step timeline so the run trace clearly shows progression, not just start/end markers.\n'
  fi
  if [ "$timestamp_steps" -lt 3 ]; then
    printf -- '- Emit more timestamped progress lines while thinking (target at least 3).\n'
  fi
  if [ "$fold_ready" -lt 1 ] && [ "$flow" -lt 75 ]; then
    printf -- '- For complex tasks, keep enough concise step updates to enable readable folded timelines at completion.\n'
  fi
  if [ "$sections" -lt 1 ]; then
    printf -- '- Mandatory final sections: Outcome, Verification Evidence, Risks, Next Improvement.\n'
  fi
  if [ "$control" -lt 1 ]; then
    printf -- '- Include explicit planning scaffold updates while running.\n'
  fi
  if [ "$verify" -lt 1 ]; then
    printf -- '- Include concrete verification evidence before DONE.\n'
  fi
  if [ "$runtime_line" -lt 1 ]; then
    printf -- '- Include explicit runtime line: Worked for Xm Ys.\n'
  fi
  if [ "$flow_strict" -lt 1 ]; then
    printf -- '- Target strict flow contract: timestamped thinking trace + planning scaffold + verification + runtime evidence + final sections.\n'
  fi
  printf -- '- Keep all edits and generated artifacts inside $ARTIFICER_ASSAY_RUNS_DIR/%s/.\n' "$task_id"
}

task_table() {
  table_file=${1:-}
  if [ -n "$table_file" ] && [ -f "$table_file" ]; then
    cat "$table_file"
    return 0
  fi
  cat <<'EOF'
deterministic-tests	report	standard	Design a deterministic test harness strategy for a flaky subsystem, including seed policy, repeatability checks, and a concise regression report template.
concurrency-race	assistant	standard	Diagnose a likely race-condition class failure path, propose a concrete mitigation design, and specify verification steps for concurrent stress conditions.
api-hardening	programming	standard	Introduce strict input validation for one high-risk API path, include backward-compatible error handling, and add focused contract tests.
migration-safe	assistant	standard	Design an idempotent migration plan for a realistic schema change, including rollback, observability, and release sequencing safeguards.
perf-regression	report	standard	Analyze a probable performance regression path and propose measurable optimization and benchmark guardrails without behavior drift.
security-audit	security-audit	standard	Audit this project for one concrete security weakness class, implement a fix, and add tests that fail before and pass after.
refactor-boundaries	assistant	standard	Refactor strategy: split one tangled area into clear module boundaries with minimal behavior change and parity validation checkpoints.
failure-recovery	programming	standard	Add robust failure recovery for one external dependency path with retries, fallback behavior, and observable failure diagnostics.
spec-to-code	assistant	standard	Write a short implementation contract first, then produce a high-confidence implementation and verification plan for end-to-end delivery.
report-trace	report	standard	Evaluate one recent run for conversation clarity and trace readability. Propose concrete improvements to step framing and summary quality.
teacher-explain	teacher	standard	Teach a difficult subsystem as a mini lesson with misconceptions, checkpoints, and spaced recall prompts.
pentest-simulation	pentest	standard	Run a safe internal pentest simulation against likely attack surfaces, propose concrete exploit paths, then implement and verify high-signal mitigations.
EOF
}

score_row_from_event_json() {
  min_cmd=$1
  min_steps=$2
  min_ts=$3
  min_fold_steps=$4
  jq -r --argjson min_cmd "$min_cmd" --argjson min_steps "$min_steps" --argjson min_ts "$min_ts" --argjson min_fold_steps "$min_fold_steps" '
    . as $e |
    ($e.status // "error") as $status |
    ($e.stream_text // "") as $stream |
    ($e.plan // "") as $plan |
    ($e.session_log // "") as $session |
    ($e.failures // "") as $failures |
    (if (($e.assistant // "") | length) > 0 then ($e.assistant // "") else ($e.error // "") end) as $assistant |
    ([($e.commands // [])[]] | length) as $cmd |
    ([((($stream + "\n" + $failures) | split("\n")))[] | select(length > 0)] | length) as $steps |
    ([($stream | split("\n"))[] | select(test("^\\[[0-9]{2}:[0-9]{2}:[0-9]{2}\\]"))] | length) as $ts_steps |
    (((($stream + "\n" + $plan + "\n" + $session + "\n" + $failures + "\n" + $assistant) | test("MODE_UPDATE:|PLAN_UPDATE:|Next Action:|Completion Criteria:|Transition:"; "i")))) as $control |
    (((($stream + "\n" + $session + "\n" + ($e.state // "") + "\n" + $failures + "\n" + $assistant) | test("verified|verification|tests?\\s+(pass|passed)|DONE_CLAIM:\\s*yes"; "i")))) as $verify |
    ((($assistant | test("Outcome:"; "i")) and ($assistant | test("Verification Evidence:"; "i")) and ($assistant | test("Risks:"; "i")) and ($assistant | test("Next Improvement:"; "i")))) as $sections |
    (($stream + "\n" + $assistant + "\n" + $failures) | test("Worked for\\s+[0-9]+m\\s+[0-9]+s|Worked for\\s+[0-9]+s"; "i")) as $runtime_line |
    ($steps >= $min_fold_steps) as $fold_ready |
    (($status == "done") and ($cmd >= $min_cmd) and ($steps >= $min_steps) and ($verify) and ($sections)) as $depth_ok |
    (($sections and $control and $verify and $runtime_line and ($ts_steps >= $min_ts))) as $flow_strict |
    (
      32
      + (if $status == "done" then 24 elif $status == "error" then -28 elif $status == "cancelled" then -20 elif $status == "timeout" then -16 elif ($status == "awaiting_approval" or $status == "awaiting_decision") then -10 else 0 end)
      + (if ($plan|length) > 0 then 6 else 0 end)
      + (if $control then 6 else 0 end)
      + (if $verify then 8 else 0 end)
      + (if $sections then 8 elif $status == "done" then -8 else 0 end)
      + (if $runtime_line then 4 else 0 end)
      + (if $steps >= 20 then 9 elif $steps >= 12 then 5 elif $steps < 8 then -8 else 0 end)
      + (if $cmd >= 3 then 10 elif $cmd == 2 then 7 elif $cmd == 1 then 2 else 0 end)
      + (if $depth_ok then 9 else 0 end)
      + (if $status == "done" and $cmd < $min_cmd then -12 else 0 end)
      + (if $status == "done" and $steps < $min_steps then -8 else 0 end)
    ) as $iq_raw |
    (
      34
      + (if $steps >= 24 then 20 elif $steps >= 14 then 14 elif $steps >= 8 then 8 elif $steps >= 3 then 3 else -10 end)
      + (if $ts_steps >= 10 then 14 elif $ts_steps >= 6 then 10 elif $ts_steps >= 3 then 7 elif $ts_steps >= 1 then 3 else 0 end)
      + (if $sections then 9 elif $status == "done" then -9 else 0 end)
      + (if $control then 8 else 0 end)
      + (if $verify then 7 else 0 end)
      + (if $runtime_line then 4 else 0 end)
      + (if $fold_ready then 4 else 0 end)
      + (if ($stream|length) < 180 then -8 else 0 end)
      + (if $status == "error" and $steps < 4 then -10 else 0 end)
    ) as $flow_raw |
    [
      $status,
      ($cmd|tostring),
      ($steps|tostring),
      (($stream|length)|tostring),
      (($assistant|length)|tostring),
      (if $sections then "1" else "0" end),
      (if $control then "1" else "0" end),
      (if $verify then "1" else "0" end),
      (if $runtime_line then "1" else "0" end),
      ((if $iq_raw < 0 then 0 elif $iq_raw > 100 then 100 else $iq_raw end)|floor|tostring),
      ((if $flow_raw < 0 then 0 elif $flow_raw > 100 then 100 else $flow_raw end)|floor|tostring),
      ($ts_steps|tostring),
      (if $fold_ready then "1" else "0" end),
      (if $flow_strict then "1" else "0" end),
      (if $depth_ok then "1" else "0" end)
    ] | @tsv
  '
}

run_cycle() {
  label=$1
  task_timeout_sec=$2
  run_budget_sec=$3
  attempts=$4
  mentor_from=$5
  max_tasks=$6
  timeout_buffer_sec=$7
  tasks_file=$8
  strict_scoring=${9:-0}
  effective_attempts=$attempts

  score_min_cmd=$SCORE_DEFAULT_MIN_CMD
  score_min_steps=$SCORE_DEFAULT_MIN_STEPS
  score_min_ts=$SCORE_DEFAULT_MIN_TS
  score_min_fold_steps=$SCORE_DEFAULT_MIN_FOLD_STEPS
  if [ "$strict_scoring" -eq 1 ]; then
    score_min_cmd=$SCORE_STRICT_MIN_CMD
    score_min_steps=$SCORE_STRICT_MIN_STEPS
    score_min_ts=$SCORE_STRICT_MIN_TS
    score_min_fold_steps=$SCORE_STRICT_MIN_FOLD_STEPS
    if [ "$effective_attempts" -lt 2 ]; then
      effective_attempts=2
    fi
  fi
  mkdir -p "$OUT_DIR"
  out_file="$OUT_DIR/$label.tsv"
  tmp_tasks=$(mktemp)
  task_table "$tasks_file" > "$tmp_tasks"

  ws_path=$PROJECT_ROOT
  ws_json=$(post_api_json "action=add_workspace&path=$(urlenc "$ws_path")&name=$(urlenc "Assay $label")")
  ws_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id')
  if [ -z "$ws_id" ] || [ "$ws_id" = "null" ]; then
    echo "Failed to create/get workspace for assay run." >&2
    exit 1
  fi

  printf 'task\tmode\tbudget\tstatus\tcommands\tsteps\tstream_len\tassistant_len\tsections\tcontrol\tverification\truntime_line\tintelligence\tflow\ttimestamp_steps\tfold_ready\tflow_strict\tdepth_ok\n' > "$out_file"

  processed_count=0
  while IFS= read -r task_line || [ -n "$task_line" ]; do
    task_line=$(printf '%s' "$task_line" | tr -d '\r')
    task_line_trim=$(trim_field "$task_line")
    [ -n "$task_line_trim" ] || continue
    case "$task_line_trim" in
      \#*) continue ;;
    esac

    field_count=$(printf '%s\n' "$task_line" | awk -F '\t' '{print NF+0}')
    if [ "$field_count" -lt 4 ]; then
      continue
    fi

    task=$(printf '%s\n' "$task_line" | awk -F '\t' '{print $1}')
    mode=$(printf '%s\n' "$task_line" | awk -F '\t' '{print $2}')
    budget=$(printf '%s\n' "$task_line" | awk -F '\t' '{print $3}')
    prompt=$(printf '%s\n' "$task_line" | awk -F '\t' '{print $NF}')

    task=$(trim_field "$task")
    mode=$(trim_field "$mode")
    budget=$(trim_field "$budget")
    prompt=$(trim_field "$prompt")

    [ -n "$task" ] || continue
    if task_row_is_header "$task" "$mode" "$budget"; then
      continue
    fi
    [ -n "$mode" ] || continue
    [ -n "$budget" ] || continue
    [ -n "$prompt" ] || continue

    if [ "$max_tasks" -gt 0 ] && [ "$processed_count" -ge "$max_tasks" ]; then
      break
    fi
    max_iterations=6
    case "$budget" in
      long) max_iterations=4 ;;
      until-complete) max_iterations=5 ;;
      quick) max_iterations=2 ;;
      *) max_iterations=3 ;;
    esac
    case "$mode" in
      programming|security-audit|pentest)
        if [ "$max_iterations" -lt 4 ]; then
          max_iterations=4
        fi
        ;;
      assistant|report|teacher)
        if [ "$max_iterations" -lt 3 ]; then
          max_iterations=3
        fi
        ;;
    esac

    best_row=""
    best_rank=-1
    attempt=1
    while [ "$attempt" -le "$effective_attempts" ]; do
      conv_json=$(post_api_json "action=new_conversation&workspace_id=$(urlenc "$ws_id")&title=$(urlenc "$task")")
      conv_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id')
      if [ -z "$conv_id" ] || [ "$conv_id" = "null" ]; then
        row="error\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0"
        current_rank=$(status_rank "error")
        if [ "$current_rank" -gt "$best_rank" ]; then
          best_rank=$current_rank
          best_row=$row
        fi
        break
      fi

      budget_this=$run_budget_sec
      case "$budget" in
        long)
          budget_this=$((budget_this + 10))
          ;;
        until-complete)
          budget_this=$((budget_this + 15))
          ;;
      esac

      # Tight runtime budgets need shallower controller loops to avoid assay timeouts.
      if [ "$budget_this" -le 45 ]; then
        case "$mode" in
          programming|security-audit|pentest)
            if [ "$max_iterations" -gt 3 ]; then
              max_iterations=3
            fi
            ;;
          *)
            if [ "$max_iterations" -gt 2 ]; then
              max_iterations=2
            fi
            ;;
        esac
      fi
      if [ "$budget_this" -le 30 ]; then
        case "$mode" in
          programming|security-audit|pentest)
            if [ "$max_iterations" -gt 2 ]; then
              max_iterations=2
            fi
            ;;
          *)
            if [ "$max_iterations" -gt 1 ]; then
              max_iterations=1
            fi
            ;;
        esac
      fi

      timeout_this=$((budget_this + timeout_buffer_sec))
      if [ "$timeout_this" -lt "$task_timeout_sec" ]; then
        timeout_this=$task_timeout_sec
      fi
      if [ "$timeout_this" -gt 540 ]; then
        timeout_this=540
      fi
      if [ "$attempt" -gt 1 ]; then
        timeout_this=$((timeout_this + (attempt - 1) * 15))
        budget_this=$((budget_this + (attempt - 1) * 10))
      fi

      mentor_suffix=$(mentor_suffix_for_task "$task" "$mentor_from" || true)
      prompt_for_run=$prompt
      assay_scope_suffix=$(cat <<EOF

Assay execution scope:
- Work only inside $ARTIFICER_ASSAY_RUNS_DIR/$task/
- If required context is missing, choose explicit assumptions and continue autonomously.
- Keep streaming concise timestamp-style progress updates.
- Runtime budget is ${budget_this}s with max_iterations=${max_iterations}; prioritize one concrete high-confidence slice that reaches a complete best-effort outcome.
- For a completed result, include at least 2 distinct command executions plus explicit verification evidence.
- If execution is short, force a quick verification pair before completion (for example: ls and git status --short).
EOF
)
      prompt_for_run=$(printf '%s\n%s' "$prompt_for_run" "$assay_scope_suffix")
      if [ -n "$mentor_suffix" ]; then
        prompt_for_run=$(printf '%s\n%s' "$prompt_for_run" "$mentor_suffix")
      fi
      body="action=run&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")&prompt=$(urlenc "$prompt_for_run")&run_mode=$(urlenc "$mode")&compute_budget=$(urlenc "$budget")&advanced_loop=1&max_iterations=$max_iterations&programmer_review=1&programmer_review_rounds=2&assay_task_id=$(urlenc "$task")"
      timed_out=0
      if ! run_with_timeout "$timeout_this" sh -c "ARTIFICER_RUN_TIME_BUDGET_SEC=$budget_this REQUEST_METHOD=POST sh \"$API\" <<'EOF' >/dev/null
$body
EOF
" 2>/dev/null; then
        timed_out=1
      fi

      if [ "$timed_out" -eq 1 ]; then
        post_api "action=queue_stop&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")" >/dev/null || true
      fi

      settle_try=0
      settle_limit=20
      if [ "$timed_out" -eq 1 ]; then
        settle_limit=45
      fi
      state_json=""
      while [ "$settle_try" -lt "$settle_limit" ]; do
        queue_json=$(post_api_json "action=queue_list&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")")
        queue_running=$(printf '%s' "$queue_json" | jq -r '.queue_running // 0')
        if [ "$queue_running" != "1" ]; then
          break
        fi
        sleep 0.4
        settle_try=$((settle_try + 1))
      done
      queue_json=$(post_api_json "action=queue_list&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")")
      queue_last_status=$(printf '%s' "$queue_json" | jq -r '.queue_last_status // "unknown"')
      state_json=$(post_api_json "action=get_conversation&workspace_id=$(urlenc "$ws_id")&conversation_id=$(urlenc "$conv_id")")
      event_json=$(printf '%s' "$state_json" | jq -c '.conversation.run_events[-1] // {}')
      assistant_from_messages=$(printf '%s' "$state_json" | jq -r '.conversation.messages | map(select(.role=="assistant")) | last | .content // ""')
      if [ -n "$assistant_from_messages" ]; then
        event_json=$(printf '%s' "$event_json" | jq -c --arg a "$assistant_from_messages" '.assistant = (if ((.assistant // "") | length) > 0 then .assistant else $a end)')
      fi
      row=$(printf '%s' "$event_json" | score_row_from_event_json "$score_min_cmd" "$score_min_steps" "$score_min_ts" "$score_min_fold_steps")
      event_status=$(printf '%s' "$event_json" | jq -r '.status // "unknown"')
      if [ "$event_status" = "running" ] && [ -n "$queue_last_status" ] && [ "$queue_last_status" != "running" ] && [ "$queue_last_status" != "unknown" ]; then
        row=$(printf '%s' "$row" | awk -F '\t' -v s="$queue_last_status" 'BEGIN{OFS=FS}{$1=s; print}')
      elif [ "$event_status" = "running" ] && [ "$timed_out" -eq 1 ]; then
        row=$(printf '%s' "$row" | awk -F '\t' 'BEGIN{OFS=FS}{$1="timeout"; print}')
      fi

      this_status=$(printf '%s' "$row" | awk -F '\t' '{print $1}')
      if [ "$timed_out" -eq 1 ] && [ "$this_status" != "done" ]; then
        row=$(printf '%s' "$row" | awk -F '\t' 'BEGIN{OFS=FS}{$1="timeout"; print}')
        this_status="timeout"
      fi
      this_rank=$(status_rank "$this_status")
      if [ "$this_rank" -gt "$best_rank" ]; then
        best_rank=$this_rank
        best_row=$row
      fi
      if [ "$this_status" = "done" ]; then
        break
      fi
      attempt=$((attempt + 1))
    done

    [ -n "$best_row" ] || best_row="error\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0"
    printf '%s\t%s\t%s\t%s\n' "$task" "$mode" "$budget" "$best_row" >> "$out_file"
    echo "cycle[$label] done: $task" >&2
    processed_count=$((processed_count + 1))
  done < "$tmp_tasks"

  rm -f "$tmp_tasks"
  echo "$out_file"
}

compare_cycles() {
  before=$1
  after=$2
  report="$OUT_DIR/compare-$(date +%Y%m%d-%H%M%S).md"
  awk -F '\t' 'NR==1{next} {print $1"\t"$13"\t"$14}' "$before" > "$OUT_DIR/.before.$$"
  awk -F '\t' 'NR==1{next} {print $1"\t"$13"\t"$14}' "$after" > "$OUT_DIR/.after.$$"
  join -t "$(printf '\t')" -a 1 -a 2 -e "0" -o 0,1.2,2.2,1.3,2.3 "$OUT_DIR/.before.$$" "$OUT_DIR/.after.$$" > "$OUT_DIR/.joined.$$"
  {
    echo "# Assay Before/After Report"
    echo
    echo "| Task | IQ Before | IQ After | Delta IQ | Flow Before | Flow After | Delta Flow |"
    echo "|---|---:|---:|---:|---:|---:|---:|"
    awk -F '\t' '{
      iqb=$2+0; iqa=$3+0; fb=$4+0; fa=$5+0;
      printf("| %s | %d | %d | %+d | %d | %d | %+d |\n", $1, iqb, iqa, iqa-iqb, fb, fa, fa-fb);
    }' "$OUT_DIR/.joined.$$"
  } > "$report"
  rm -f "$OUT_DIR/.before.$$" "$OUT_DIR/.after.$$" "$OUT_DIR/.joined.$$"
  echo "$report"
}

decision_matrix() {
  label=$1
  fixtures_override=${2:-}
  fixture_file=$(decision_fixture_file "$fixtures_override")
  mkdir -p "$OUT_DIR"
  out_file="$OUT_DIR/$label.tsv"
  printf 'case\tkind\texpected_category\tactual_category\texpected_allow\tactual_allow\texpected_explicit\tactual_explicit\texpected_missing\tactual_missing\texpected_risk\tactual_risk\texpected_external\tactual_external\texpected_destructive\tactual_destructive\tpass\n' > "$out_file"

  if [ ! -f "$fixture_file" ]; then
    echo "Decision fixture file not found: $fixture_file" >&2
    exit 1
  fi

  while IFS='|' read -r case_id expected_category expected_allow expected_explicit expected_missing expected_risk expected_external expected_destructive run_mode prompt question commands || [ -n "$case_id" ]; do
    case_id=$(printf '%s' "$case_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$case_id" ] || continue
    case "$case_id" in
      \#*) continue ;;
    esac
    if [ "$(lower_field "$case_id")" = "case" ] && [ "$(lower_field "$expected_category")" = "expected_category" ]; then
      continue
    fi

    kind="trigger"
    if [ "$expected_category" = "none" ]; then
      kind="near-miss"
    fi

    raw=$(post_api_json "action=decision_surface_preview&prompt=$(urlenc "$prompt")&question=$(urlenc "$question")&commands=$(urlenc "$commands")&run_mode=$(urlenc "$run_mode")")
    actual_category=$(printf '%s' "$raw" | jq -r '.category // "none"')
    actual_allow=$(printf '%s' "$raw" | jq -r '.allow_decision_request // false')
    actual_explicit=$(printf '%s' "$raw" | jq -r '.signals.explicit_choice // 0')
    actual_missing=$(printf '%s' "$raw" | jq -r '.signals.missing_required_inputs // 0')
    actual_risk=$(printf '%s' "$raw" | jq -r '.signals.risk_gate_question // 0')
    actual_external=$(printf '%s' "$raw" | jq -r '.signals.external_commands // 0')
    actual_destructive=$(printf '%s' "$raw" | jq -r '.signals.destructive_commands // 0')

    pass=1
    if [ "$actual_category" != "$expected_category" ]; then pass=0; fi
    if [ "$actual_allow" != "$expected_allow" ]; then pass=0; fi
    if [ "$actual_explicit" != "$expected_explicit" ]; then pass=0; fi
    if [ "$actual_missing" != "$expected_missing" ]; then pass=0; fi
    if [ "$actual_risk" != "$expected_risk" ]; then pass=0; fi
    if [ "$actual_external" != "$expected_external" ]; then pass=0; fi
    if [ "$actual_destructive" != "$expected_destructive" ]; then pass=0; fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$case_id" "$kind" "$expected_category" "$actual_category" \
      "$expected_allow" "$actual_allow" \
      "$expected_explicit" "$actual_explicit" \
      "$expected_missing" "$actual_missing" \
      "$expected_risk" "$actual_risk" \
      "$expected_external" "$actual_external" \
      "$expected_destructive" "$actual_destructive" \
      "$pass" >> "$out_file"
  done < "$fixture_file"

  echo "$out_file"
}

cycle_metrics_for_file() {
  result_file=$1
  awk -F '\t' '
    NR==1 { next }
    {
      total += 1
      status = $4
      if (status == "done") done += 1
      if (status == "error") errors += 1
      if (status == "timeout") timeout += 1
      if (status == "awaiting_decision" || status == "awaiting_approval") blocking += 1
      iq += ($13 + 0)
      flow += ($14 + 0)
      if (($15 + 0) >= 3) ts_ok += 1
      if ($16 == "1") fold_ready += 1
      if ($17 == "1") strict_flow += 1
      if ($18 == "1") depth_ok += 1
    }
    END {
      if (total < 1) {
        printf "0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n"
        exit
      }
      printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", total, done, errors, timeout, blocking, int((iq / total) + 0.5), int((flow / total) + 0.5), strict_flow, ts_ok, fold_ready, depth_ok
    }
  ' "$result_file"
}

decision_metrics_for_file() {
  result_file=$1
  awk -F '\t' '
    NR==1 { next }
    {
      total += 1
      if ($17 == "1") passed += 1
      if ($2 == "trigger") triggers += 1
      if ($2 == "near-miss") near += 1
    }
    END {
      if (total < 1) {
        printf "0\t0\t0\t0\n"
        exit
      }
      printf "%d\t%d\t%d\t%d\n", total, passed, triggers, near
    }
  ' "$result_file"
}

percent_label() {
  numerator=$1
  denominator=$2
  if [ "$denominator" -le 0 ]; then
    printf '%s' "0%"
    return 0
  fi
  awk -v n="$numerator" -v d="$denominator" 'BEGIN { printf "%.0f%%", (n * 100.0) / d }'
}

cycle_postmortem_for_files() {
  cycle_label=$1
  cycle_file=$2
  decision_file=$3
  out_file="$OUT_DIR/$cycle_label-postmortem.md"

  {
    printf '# Assay Postmortem: %s\n\n' "$cycle_label"
    printf '## Run Risks\n'
    if ! awk -F '\t' 'NR>1 && $4 != "done" { printf "- %s: status=%s, iq=%s, flow=%s\n", $1, $4, $13, $14; found=1 } END { exit(found ? 0 : 1) }' "$cycle_file"; then
      printf -- '- No non-done tasks in this cycle.\n'
    fi

    printf '\n## Lowest Intelligence Tasks\n'
    if ! awk -F '\t' 'NR>1 { printf "%s\t%s\t%s\t%s\n", $13+0, $14+0, $1, $4 }' "$cycle_file" | sort -t "$(printf '\t')" -k1,1n -k2,2n | head -n 4 | awk -F '\t' '{ printf "- %s: iq=%s, flow=%s, status=%s\n", $3, $1, $2, $4; found=1 } END { exit(found ? 0 : 1) }'; then
      printf -- '- No task data available.\n'
    fi

    printf '\n## Flow Gaps\n'
    if ! awk -F '\t' 'NR>1 && $17 != "1" { printf "- %s: strict_flow=0 (sections=%s control=%s verify=%s runtime=%s ts_steps=%s)\n", $1, $9, $10, $11, $12, $15; found=1 } END { exit(found ? 0 : 1) }' "$cycle_file"; then
      printf -- '- No strict flow gaps detected.\n'
    fi
    printf '\n## Depth Gaps\n'
    if ! awk -F '\t' 'NR>1 && $18 != "1" { printf "- %s: depth_ok=0 (commands=%s steps=%s status=%s)\n", $1, $5, $6, $4; found=1 } END { exit(found ? 0 : 1) }' "$cycle_file"; then
      printf -- '- No execution-depth gaps detected.\n'
    fi

    printf '\n## Decision Misses\n'
    if [ -f "$decision_file" ]; then
      if ! awk -F '\t' 'NR>1 && $17 != "1" { printf "- %s: expected category=%s allow=%s but got category=%s allow=%s\n", $1, $3, $5, $4, $6; found=1 } END { exit(found ? 0 : 1) }' "$decision_file"; then
        printf -- '- No decision-surfacing misses.\n'
      fi
    else
      printf -- '- Decision matrix file missing: %s\n' "$decision_file"
    fi

    printf '\n## Next-Cycle Priorities\n'
    strict_missing=$(awk -F '\t' 'NR>1 && $17 != "1" {count += 1} END {print count+0}' "$cycle_file")
    ts_missing=$(awk -F '\t' 'NR>1 && ($15 + 0) < 3 {count += 1} END {print count+0}' "$cycle_file")
    depth_missing=$(awk -F '\t' 'NR>1 && $18 != "1" {count += 1} END {print count+0}' "$cycle_file")
    non_done=$(awk -F '\t' 'NR>1 && $4 != "done" {count += 1} END {print count+0}' "$cycle_file")
    if [ "$non_done" -gt 0 ]; then
      printf -- '- Push to completion: unresolved tasks should prioritize concrete assumptions and narrower execution slices.\n'
    fi
    if [ "$strict_missing" -gt 0 ]; then
      printf -- '- Improve conversation contract adherence: enforce final sections plus explicit verification/runtime evidence every run.\n'
    fi
    if [ "$ts_missing" -gt 0 ]; then
      printf -- '- Increase timestamped thinking updates to make run traces easier to scan and fold.\n'
    fi
    if [ "$depth_missing" -gt 0 ]; then
      printf -- '- Increase execution depth for done runs: target >=2 commands plus explicit verification before claiming completion.\n'
    fi
    if [ "$non_done" -eq 0 ] && [ "$strict_missing" -eq 0 ] && [ "$ts_missing" -eq 0 ] && [ "$depth_missing" -eq 0 ]; then
      printf -- '- Maintain current strategy and raise task difficulty or stricter acceptance thresholds in the next cycle.\n'
    fi
  } > "$out_file"

  printf '%s' "$out_file"
}

mentor_series() {
  label=$1
  cycles=$2
  task_timeout_sec=$3
  run_budget_sec=$4
  attempts=$5
  mentor_from=$6
  max_tasks=$7
  decisions_fixture_override=$8
  timeout_buffer_sec=$9
  tasks_file=${10:-}
  strict_scoring=${11:-0}

  mkdir -p "$OUT_DIR"
  report_file="$OUT_DIR/$label-series.md"
  printf '# Assay Mentor Series: %s\n\n' "$label" > "$report_file"
  printf '| Iteration | Tasks Done | Avg IQ | Avg Flow | Strict Flow | TS Coverage | Fold Ready | Depth OK | Decision Pass | Decisions Trigger/Near | Result TSV | Decisions TSV | Postmortem | Compare |\n' >> "$report_file"
  printf '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---|\n' >> "$report_file"

  previous_cycle_file=""
  prior_for_guidance=$mentor_from
  cycle_index=1
  while [ "$cycle_index" -le "$cycles" ]; do
    cycle_label="$label-i$cycle_index"
    decision_label="$label-decisions-i$cycle_index"
    cycle_file=$(run_cycle "$cycle_label" "$task_timeout_sec" "$run_budget_sec" "$attempts" "$prior_for_guidance" "$max_tasks" "$timeout_buffer_sec" "$tasks_file" "$strict_scoring")
    decision_file=$(decision_matrix "$decision_label" "$decisions_fixture_override")
    cycle_metrics=$(cycle_metrics_for_file "$cycle_file")
    decision_metrics=$(decision_metrics_for_file "$decision_file")

    task_total=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $1+0}')
    task_done=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $2+0}')
    avg_iq=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $6+0}')
    avg_flow=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $7+0}')
    strict_flow_count=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $8+0}')
    ts_coverage_count=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $9+0}')
    fold_ready_count=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $10+0}')
    depth_ok_count=$(printf '%s' "$cycle_metrics" | awk -F '\t' '{print $11+0}')

    strict_flow_rate=$(percent_label "$strict_flow_count" "$task_total")
    ts_coverage_rate=$(percent_label "$ts_coverage_count" "$task_total")
    fold_ready_rate=$(percent_label "$fold_ready_count" "$task_total")
    depth_ok_rate=$(percent_label "$depth_ok_count" "$task_total")

    decision_total=$(printf '%s' "$decision_metrics" | awk -F '\t' '{print $1+0}')
    decision_passed=$(printf '%s' "$decision_metrics" | awk -F '\t' '{print $2+0}')
    decision_trigger_count=$(printf '%s' "$decision_metrics" | awk -F '\t' '{print $3+0}')
    decision_near_count=$(printf '%s' "$decision_metrics" | awk -F '\t' '{print $4+0}')
    decision_pass_rate=$(percent_label "$decision_passed" "$decision_total")

    postmortem_file=$(cycle_postmortem_for_files "$cycle_label" "$cycle_file" "$decision_file")

    compare_text="-"
    if [ -n "$previous_cycle_file" ] && [ -f "$previous_cycle_file" ]; then
      compare_file=$(compare_cycles "$previous_cycle_file" "$cycle_file")
      compare_text=$(basename "$compare_file")
    fi

    printf '| %s | %d/%d | %d | %d | %s (%d/%d) | %s (%d/%d) | %s (%d/%d) | %s (%d/%d) | %s (%d/%d) | %d/%d | %s | %s | %s | %s |\n' \
      "$cycle_label" "$task_done" "$task_total" "$avg_iq" "$avg_flow" \
      "$strict_flow_rate" "$strict_flow_count" "$task_total" \
      "$ts_coverage_rate" "$ts_coverage_count" "$task_total" \
      "$fold_ready_rate" "$fold_ready_count" "$task_total" \
      "$depth_ok_rate" "$depth_ok_count" "$task_total" \
      "$decision_pass_rate" "$decision_passed" "$decision_total" \
      "$decision_trigger_count" "$decision_near_count" \
      "$(basename "$cycle_file")" "$(basename "$decision_file")" "$(basename "$postmortem_file")" "$compare_text" >> "$report_file"

    previous_cycle_file=$cycle_file
    prior_for_guidance=$cycle_file
    cycle_index=$((cycle_index + 1))
  done

  echo "$report_file"
}

mode=${1:-}
if [ -z "$mode" ]; then
  usage
  exit 1
fi
shift

case "$mode" in
  run)
    label="cycle-$(date +%Y%m%d-%H%M%S)"
    task_timeout_sec=320
    run_budget_sec=120
    timeout_buffer_sec=240
    attempts=1
    mentor_from=""
    max_tasks=0
    tasks_file=""
    strict_scoring=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --timeout-sec)
          task_timeout_sec=$2
          shift 2
          ;;
        --run-budget-sec)
          run_budget_sec=$2
          shift 2
          ;;
        --timeout-buffer-sec)
          timeout_buffer_sec=$2
          shift 2
          ;;
        --attempts)
          attempts=$2
          shift 2
          ;;
        --mentor-from)
          mentor_from=$2
          shift 2
          ;;
        --max-tasks)
          max_tasks=$2
          shift 2
          ;;
        --tasks-file)
          tasks_file=$2
          shift 2
          ;;
        --strict-scoring)
          strict_scoring=1
          shift
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done
    case "$max_tasks" in
      ""|*[!0-9]*)
        max_tasks=0
        ;;
    esac
    case "$timeout_buffer_sec" in
      ""|*[!0-9]*)
        timeout_buffer_sec=240
        ;;
    esac
    run_cycle "$label" "$task_timeout_sec" "$run_budget_sec" "$attempts" "$mentor_from" "$max_tasks" "$timeout_buffer_sec" "$tasks_file" "$strict_scoring"
    ;;
  mentor)
    label="mentor-$(date +%Y%m%d-%H%M%S)"
    cycles=2
    task_timeout_sec=320
    run_budget_sec=120
    timeout_buffer_sec=240
    attempts=1
    mentor_from=""
    max_tasks=0
    decisions_fixtures=""
    tasks_file=""
    strict_scoring=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --cycles)
          cycles=$2
          shift 2
          ;;
        --timeout-sec)
          task_timeout_sec=$2
          shift 2
          ;;
        --run-budget-sec)
          run_budget_sec=$2
          shift 2
          ;;
        --timeout-buffer-sec)
          timeout_buffer_sec=$2
          shift 2
          ;;
        --attempts)
          attempts=$2
          shift 2
          ;;
        --mentor-from)
          mentor_from=$2
          shift 2
          ;;
        --max-tasks)
          max_tasks=$2
          shift 2
          ;;
        --tasks-file)
          tasks_file=$2
          shift 2
          ;;
        --fixtures)
          decisions_fixtures=$2
          shift 2
          ;;
        --strict-scoring)
          strict_scoring=1
          shift
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done
    case "$cycles" in
      ""|*[!0-9]*|0)
        echo "Invalid --cycles: $cycles" >&2
        exit 1
        ;;
    esac
    case "$max_tasks" in
      ""|*[!0-9]*)
        max_tasks=0
        ;;
    esac
    case "$timeout_buffer_sec" in
      ""|*[!0-9]*)
        timeout_buffer_sec=240
        ;;
    esac
    mentor_series "$label" "$cycles" "$task_timeout_sec" "$run_budget_sec" "$attempts" "$mentor_from" "$max_tasks" "$decisions_fixtures" "$timeout_buffer_sec" "$tasks_file" "$strict_scoring"
    ;;
  compare)
    before=""
    after=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --before)
          before=$2
          shift 2
          ;;
        --after)
          after=$2
          shift 2
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done
    if [ -z "$before" ] || [ -z "$after" ]; then
      usage
      exit 1
    fi
    compare_cycles "$before" "$after"
    ;;
  decisions)
    label="decisions-$(date +%Y%m%d-%H%M%S)"
    fixture_file=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --fixtures)
          fixture_file=$2
          shift 2
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage
          exit 1
          ;;
      esac
    done
    decision_matrix "$label" "$fixture_file"
    ;;
  *)
    usage
    exit 1
    ;;
esac
