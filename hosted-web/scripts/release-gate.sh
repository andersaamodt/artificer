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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for release gate evaluation." >&2
  exit 1
fi

BROAD_SCRIPT="$SCRIPT_DIR/broad-reasoning-cycle.sh"
COMPACT_SCRIPT="$SCRIPT_DIR/compact-reasoning-cycle.sh"
RICH_SCRIPT="$SCRIPT_DIR/rich-reasoning-cycle.sh"
FREEFORM_SCRIPT="$SCRIPT_DIR/freeform-reasoning-cycle.sh"
PROGRAMMING_SMOKE_SCRIPT="$SCRIPT_DIR/programming-stalled-summary-smoke.sh"
PROGRAMMING_BRANCHY_SMOKE_SCRIPT="$SCRIPT_DIR/programming-branchy-slice-smoke.sh"
GUI_SCRIPT="$SCRIPT_DIR/gui-regression-system.sh"
. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"

DEFAULT_BATTERY_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-battery-v16.tsv"
DEFAULT_HOLDOUT_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-holdout-v16.tsv"
DEFAULT_MIXED_BATTERY_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v41-mixedtransferfit.tsv"
DEFAULT_MIXED_HOLDOUT_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-holdout-v41-mixedtransferfit.tsv"
DEFAULT_COMPACT_BATTERY_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v44-compactthreadfit.tsv"
DEFAULT_COMPACT_HOLDOUT_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-holdout-v44-compactthreadfit.tsv"
DEFAULT_RICH_BATTERY_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v55-richdeicticstatefit.tsv"
DEFAULT_RICH_HOLDOUT_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-holdout-v55-richdeicticstatefit.tsv"
DEFAULT_FREEFORM_BATTERY_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v75-freeformtersefinalfit.tsv"
DEFAULT_FREEFORM_HOLDOUT_FILE="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-holdout-v75-freeformtersefinalfit.tsv"
DEFAULT_PROGRAMMING_AUTO_BRANCHY_FILE="$SITE_ROOT/tests/fixtures/artificer-programming-auto-branchy-smoke.tsv"
DEFAULT_REPO_RUNTIME_WEB_TRIAGE_TRANSFER_JSON="$OUT_DIR/repo-runtime-web-triage-v1-transfer-r1-transfer.json"
DEFAULT_BROWSER_IMAGE_RUN_INVESTIGATION_TRANSFER_JSON="$OUT_DIR/browser-image-run-investigation-v1-transfer-r1-transfer.json"
DEFAULT_TOOL_FAILURE_HANDOFF_TRANSFER_JSON="$OUT_DIR/tool-failure-handoff-v1-transfer-r1-transfer.json"
DEFAULT_CURRENT_API_MIGRATION_TRANSFER_JSON="$OUT_DIR/current-api-migration-v1-transfer-r1-transfer.json"
DEFAULT_CURRENT_OPS_GUIDANCE_TRANSFER_JSON="$OUT_DIR/current-ops-guidance-v1-transfer-r1-transfer.json"
DEFAULT_STANDARDS_GROUNDED_ANSWER_TRANSFER_JSON="$OUT_DIR/standards-grounded-answer-v1-transfer-r1-transfer.json"
DEFAULT_OPERATOR_DECISION_TRANSFER_JSON="$OUT_DIR/operator-decision-v1-transfer-r1-transfer.json"
DEFAULT_MULTI_ARTIFACT_JUDGMENT_TRANSFER_JSON="$OUT_DIR/multi-artifact-judgment-v1-transfer-transfer.json"
DEFAULT_LONG_CONTEXT_REASSESSMENT_TRANSFER_JSON="$OUT_DIR/long-context-reassessment-v1-transfer-transfer.json"
DEFAULT_LONG_HORIZON_TIMEOUT_COVERAGE_TRANSFER_JSON="$OUT_DIR/long-horizon-timeout-coverage-v1-transfer-r1-transfer.json"
DEFAULT_DOCUMENT_TRANSFER_JSON="$OUT_DIR/document-v1-transfer-r2-transfer.json"
DEFAULT_REMOTE_OPS_TRANSFER_JSON="$OUT_DIR/remote-ops-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_DEPLOY_TRANSFER_JSON="$OUT_DIR/remote-deploy-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_MULTI_HOST_TRANSFER_JSON="$OUT_DIR/remote-multi-host-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_MULTI_HOST_ROLLOUT_TRANSFER_JSON="$OUT_DIR/remote-multi-host-rollout-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_BASTION_CUTOVER_TRANSFER_JSON="$OUT_DIR/remote-bastion-cutover-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_BOUNDARY_ROLLOUT_TRANSFER_JSON="$OUT_DIR/remote-boundary-rollout-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_BOUNDARY_ROLLBACK_TRANSFER_JSON="$OUT_DIR/remote-boundary-rollback-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_BOUNDARY_PACK_TRANSFER_JSON="$OUT_DIR/remote-boundary-pack-v1-transfer-r1-transfer.json"
DEFAULT_REMOTE_RELEASE_PACK_TRANSFER_JSON="$OUT_DIR/remote-release-pack-v1-transfer-r1-transfer.json"
DEFAULT_GUI_VISUAL_TRANSFER_JSON="$OUT_DIR/gui-visual-v1-transfer-r1-transfer.json"
DEFAULT_GUI_SCREENSHOT_LAYOUT_TRIAGE_TRANSFER_JSON="$OUT_DIR/gui-screenshot-layout-triage-v1-transfer-r1-transfer.json"
DEFAULT_GUI_LOGIN_UPLOAD_DOWNLOAD_TRANSFER_JSON="$OUT_DIR/gui-login-upload-download-v1-transfer-r1-transfer.json"
DEFAULT_GUI_STATE_RECOVERY_PACK_TRANSFER_JSON="$OUT_DIR/gui-state-recovery-pack-v1-transfer-r2-transfer.json"
DEFAULT_DASHBOARD_CHART_READ_TRANSFER_JSON="$OUT_DIR/dashboard-chart-read-v1-transfer-r1-transfer.json"
DEFAULT_TERMINAL_SCREENSHOT_DEBUG_TRANSFER_JSON="$OUT_DIR/terminal-screenshot-debug-v1-transfer-r2-transfer.json"
DEFAULT_BEFORE_AFTER_UI_DELTA_TRANSFER_JSON="$OUT_DIR/before-after-ui-delta-v1-transfer-r1-transfer.json"
DEFAULT_TERMINAL_STATE_RECOVERY_READ_TRANSFER_JSON="$OUT_DIR/terminal-state-recovery-read-v1-transfer-r2-transfer.json"
DEFAULT_DIAGRAM_ANNOTATION_READ_TRANSFER_JSON="$OUT_DIR/diagram-annotation-read-v1-transfer-r2-transfer.json"

usage() {
  cat <<'USAGE'
Usage:
  release-gate.sh [options]

Options:
  --label NAME                          Gate label (default: release-gate-YYYYmmdd-HHMMSS)
  --battery-file FILE                   Intelligence battery fixture (default: broad-reasoning-battery-v16)
  --holdout-file FILE                   Intelligence holdout fixture (default: broad-reasoning-holdout-v16)
  --battery-summary FILE                Reuse an existing battery summary JSON (skip battery run)
  --holdout-summary FILE                Reuse an existing holdout summary JSON (skip holdout run)
  --mixed-battery-file FILE             Mixed transfer regression fixture (default: regressions-v41-mixedtransferfit)
  --mixed-holdout-file FILE             Mixed transfer holdout fixture (default: holdout-v41-mixedtransferfit)
  --mixed-battery-summary FILE          Reuse an existing mixed regression summary JSON
  --mixed-holdout-summary FILE          Reuse an existing mixed holdout summary JSON
  --mixed-transfer-json FILE            Reuse an existing mixed transfer JSON (skip mixed transfer run)
  --compact-battery-file FILE           Compact reasoning regression fixture (default: regressions-v44-compactthreadfit)
  --compact-holdout-file FILE           Compact reasoning holdout fixture (default: holdout-v44-compactthreadfit)
  --compact-battery-summary FILE        Reuse an existing compact regression summary JSON
  --compact-holdout-summary FILE        Reuse an existing compact holdout summary JSON
  --compact-transfer-json FILE          Reuse an existing compact transfer JSON (skip compact transfer run)
  --rich-battery-file FILE              Rich live-thread regression fixture (default: regressions-v55-richdeicticstatefit)
  --rich-holdout-file FILE              Rich live-thread holdout fixture (default: holdout-v55-richdeicticstatefit)
  --rich-battery-summary FILE           Reuse an existing rich live-thread regression summary JSON
  --rich-holdout-summary FILE           Reuse an existing rich live-thread holdout summary JSON
  --rich-transfer-json FILE             Reuse an existing rich live-thread transfer JSON (skip rich transfer run)
  --freeform-battery-file FILE          Freeform memo regression fixture (default: regressions-v75-freeformtersefinalfit)
  --freeform-holdout-file FILE          Freeform memo holdout fixture (default: holdout-v75-freeformtersefinalfit)
  --freeform-battery-summary FILE       Reuse an existing freeform memo regression summary JSON
  --freeform-holdout-summary FILE       Reuse an existing freeform memo holdout summary JSON
  --freeform-transfer-json FILE         Reuse an existing freeform memo transfer JSON (skip freeform transfer run)
  --programming-summary-json FILE       Reuse an existing programming stalled-summary smoke JSON
  --programming-branchy-json FILE       Reuse an existing programming branchy-slice smoke JSON
  --programming-auto-branchy-json FILE  Reuse an existing programming auto-budget branchy smoke JSON
  --repo-runtime-web-triage-transfer-json FILE
                                        Reuse an existing repo/runtime/web triage transfer JSON
  --browser-image-run-investigation-transfer-json FILE
                                        Reuse an existing browser/image/run investigation transfer JSON
  --tool-failure-handoff-transfer-json FILE
                                        Reuse an existing tool-failure handoff transfer JSON
  --current-api-migration-transfer-json FILE
                                        Reuse an existing current API migration transfer JSON
  --current-ops-guidance-transfer-json FILE
                                        Reuse an existing current ops guidance transfer JSON
  --standards-grounded-answer-transfer-json FILE
                                        Reuse an existing standards-grounded answer transfer JSON
  --operator-decision-transfer-json FILE
                                        Reuse an existing operator-decision transfer JSON
  --multi-artifact-judgment-transfer-json FILE
                                        Reuse an existing multi-artifact judgment transfer JSON
  --long-context-reassessment-transfer-json FILE
                                        Reuse an existing long-context reassessment transfer JSON
  --long-horizon-timeout-coverage-transfer-json FILE
                                        Reuse an existing long-horizon timeout coverage transfer JSON
  --document-transfer-json FILE
                                        Reuse an existing document family transfer JSON
  --remote-ops-transfer-json FILE
                                        Reuse an existing remote single-host diagnose transfer JSON
  --remote-deploy-transfer-json FILE
                                        Reuse an existing remote deploy transfer JSON
  --remote-multi-host-transfer-json FILE
                                        Reuse an existing remote multi-host failover transfer JSON
  --remote-multi-host-rollout-transfer-json FILE
                                        Reuse an existing remote multi-host rollout transfer JSON
  --remote-bastion-cutover-transfer-json FILE
                                        Reuse an existing remote bastion cutover transfer JSON
  --remote-boundary-rollout-transfer-json FILE
                                        Reuse an existing remote boundary rollout transfer JSON
  --remote-boundary-rollback-transfer-json FILE
                                        Reuse an existing remote boundary rollback transfer JSON
  --remote-boundary-pack-transfer-json FILE
                                        Reuse an existing remote boundary pack transfer JSON
  --remote-release-pack-transfer-json FILE
                                        Reuse an existing remote release pack transfer JSON
  --gui-visual-transfer-json FILE
                                        Reuse an existing GUI visual transfer JSON
  --gui-screenshot-layout-triage-transfer-json FILE
                                        Reuse an existing GUI screenshot triage transfer JSON
  --gui-login-upload-download-transfer-json FILE
                                        Reuse an existing GUI login/upload/download transfer JSON
  --gui-state-recovery-pack-transfer-json FILE
                                        Reuse an existing GUI state recovery transfer JSON
  --dashboard-chart-read-transfer-json FILE
                                        Reuse an existing dashboard chart read transfer JSON
  --terminal-screenshot-debug-transfer-json FILE
                                        Reuse an existing terminal screenshot debug transfer JSON
  --before-after-ui-delta-transfer-json FILE
                                        Reuse an existing before/after UI delta transfer JSON
  --terminal-state-recovery-read-transfer-json FILE
                                        Reuse an existing terminal state recovery transfer JSON
  --diagram-annotation-read-transfer-json FILE
                                        Reuse an existing diagram annotation transfer JSON
  --skip-programming                    Skip the programming stalled-summary gate
  --gui-profile PROFILE                 GUI sample profile: core|deep|background|full (default: core)
  --gui-result FILE                     Reuse an existing GUI result JSON (skip GUI run)
  --interactive-gui-profile PROFILE     Interactive GUI intelligence profile (default: intelligence)
  --interactive-gui-result FILE         Reuse an existing interactive GUI result JSON (skip interactive GUI run)
  --require-interactive-intelligence    Explicitly enable the interactive GUI-driven intelligence gate (default: enabled)
  --skip-intelligence                   Skip intelligence gate execution/evaluation
  --skip-interactive-intelligence       Skip the default interactive GUI-driven intelligence gate
  --skip-gui                            Skip GUI gate execution/evaluation
  --run-budget-sec N                    Override per-task runtime budget for intelligence runs
  --timeout-buffer-sec N                Timeout buffer passed to broad-reasoning-cycle.sh
  --task-timeout-sec N                  Minimum task timeout passed to broad-reasoning-cycle.sh
  --min-battery-overall N               Minimum battery avg_overall (default: 90)
  --min-holdout-overall N               Minimum holdout avg_overall (default: 90)
  --min-holdout-adversarial N           Minimum holdout avg_adversarial (default: 88)
  --min-holdout-ambiguity N             Minimum holdout avg_ambiguity (default: 88)
  --min-holdout-cross-domain N          Minimum holdout avg_cross_domain (default: 86)
  --min-holdout-recovery N              Minimum holdout avg_recovery (default: 88)
  --max-fail-open-rate N                Maximum battery/holdout fail_open_rate (default: 0)
  --max-contradiction-rate N            Maximum battery/holdout contradiction_rate (default: 0)
  --max-holdout-overall-drop N          Maximum allowed (battery - holdout) avg_overall drop (default: 2)

Examples:
  hosted-web/scripts/release-gate.sh --gui-profile deep
  hosted-web/scripts/release-gate.sh \
    --battery-summary ~/.local/state/artificer/assay-reports/broad15-strict-post1-summary.json \
    --holdout-summary ~/.local/state/artificer/assay-reports/broad15-holdout-post1-summary.json \
    --gui-result ~/.local/state/artificer/assay-reports/gui-state-coherence-v98-core-gui-result.json
USAGE
}

num_ge() {
  lhs=$1
  rhs=$2
  awk -v a="$lhs" -v b="$rhs" 'BEGIN { exit !((a + 0) >= (b + 0)) }'
}

num_le() {
  lhs=$1
  rhs=$2
  awk -v a="$lhs" -v b="$rhs" 'BEGIN { exit !((a + 0) <= (b + 0)) }'
}

run_command_with_timeout() {
  timeout_seconds=$1
  shift
  timeout_stdin_payload=$(mktemp "${TMPDIR:-/tmp}/artificer-release-gate-stdin.XXXXXX")
  cat > "$timeout_stdin_payload"
  set +e
  python3 - "$timeout_seconds" "$timeout_stdin_payload" "$@" <<'PY'
import subprocess
import sys

if len(sys.argv) < 4:
    print("run_command_with_timeout requires timeout and command", file=sys.stderr)
    sys.exit(2)

try:
    timeout_seconds = float(sys.argv[1])
except Exception:
    timeout_seconds = 0.0
stdin_payload_path = sys.argv[2]
command = sys.argv[3:]
with open(stdin_payload_path, "rb") as payload_file:
    stdin_payload = payload_file.read()

try:
    proc = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
except Exception as exc:
    print(f"__COMMAND_START_FAILED__ {exc}", file=sys.stderr)
    sys.exit(127)

try:
    stdout_data, _ = proc.communicate(stdin_payload, timeout=timeout_seconds if timeout_seconds > 0 else None)
except subprocess.TimeoutExpired:
    try:
      proc.terminate()
      stdout_data, _ = proc.communicate(timeout=2)
    except Exception:
      proc.kill()
      stdout_data, _ = proc.communicate()
    if stdout_data:
      sys.stdout.buffer.write(stdout_data)
    print(
      "__TIMEOUT__ command timed out after "
      + str(int(timeout_seconds) if timeout_seconds > 0 else 0)
      + "s: "
      + " ".join(command),
      file=sys.stderr,
    )
    sys.exit(124)

if stdout_data:
    sys.stdout.buffer.write(stdout_data)
sys.exit(proc.returncode)
PY
  status=$?
  set -e
  rm -f "$timeout_stdin_payload"
  return "$status"
}

run_command_with_timeout_to_file() {
  timeout_seconds=$1
  output_path=$2
  shift 2
  : > "$output_path"
  set +e
  python3 - "$timeout_seconds" "$output_path" "$@" <<'PY'
import os
import signal
import subprocess
import sys

if len(sys.argv) < 4:
    print("run_command_with_timeout_to_file requires timeout, output path, and command", file=sys.stderr)
    sys.exit(2)

try:
    timeout_seconds = float(sys.argv[1])
except Exception:
    timeout_seconds = 0.0
output_path = sys.argv[2]
command = sys.argv[3:]

try:
    with open(output_path, "ab", buffering=0) as output_file:
        proc = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=output_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            proc.wait(timeout=timeout_seconds if timeout_seconds > 0 else None)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except Exception:
                pass
            try:
                proc.wait(timeout=2)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except Exception:
                    pass
                proc.wait()
            with open(output_path, "ab", buffering=0) as timeout_file:
                timeout_file.write(
                    (
                        "__TIMEOUT__ command timed out after "
                        + str(int(timeout_seconds) if timeout_seconds > 0 else 0)
                        + "s: "
                        + " ".join(command)
                        + "\n"
                    ).encode("utf-8", "ignore")
                )
            sys.exit(124)
        sys.exit(proc.returncode)
except Exception as exc:
    with open(output_path, "ab", buffering=0) as output_file:
        output_file.write(f"__COMMAND_START_FAILED__ {exc}\n".encode("utf-8", "ignore"))
    sys.exit(127)
PY
  status=$?
  set -e
  return "$status"
}

to_json_bool() {
  if [ "$1" = "true" ]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "File not found: $1" >&2
    exit 1
  fi
}

transfer_json_pass() {
  transfer_json_path=${1:-}
  if [ -n "$transfer_json_path" ] && [ -f "$transfer_json_path" ]; then
    jq -r 'if .all_gates_pass == true then "true" else "false" end' "$transfer_json_path"
  else
    printf '%s\n' "false"
  fi
}

transfer_json_risk() {
  transfer_json_path=${1:-}
  if [ -n "$transfer_json_path" ] && [ -f "$transfer_json_path" ]; then
    jq -r '.transfer_risk // ""' "$transfer_json_path"
  else
    printf '%s\n' ""
  fi
}

label="release-gate-$(date +%Y%m%d-%H%M%S)"
battery_file="$DEFAULT_BATTERY_FILE"
holdout_file="$DEFAULT_HOLDOUT_FILE"
battery_summary=""
holdout_summary=""
mixed_battery_file="$DEFAULT_MIXED_BATTERY_FILE"
mixed_holdout_file="$DEFAULT_MIXED_HOLDOUT_FILE"
mixed_battery_summary=""
mixed_holdout_summary=""
mixed_transfer_json=""
compact_battery_file="$DEFAULT_COMPACT_BATTERY_FILE"
compact_holdout_file="$DEFAULT_COMPACT_HOLDOUT_FILE"
compact_battery_summary=""
compact_holdout_summary=""
compact_transfer_json=""
rich_battery_file="$DEFAULT_RICH_BATTERY_FILE"
rich_holdout_file="$DEFAULT_RICH_HOLDOUT_FILE"
rich_battery_summary=""
rich_holdout_summary=""
rich_transfer_json=""
freeform_battery_file="$DEFAULT_FREEFORM_BATTERY_FILE"
freeform_holdout_file="$DEFAULT_FREEFORM_HOLDOUT_FILE"
freeform_battery_summary=""
freeform_holdout_summary=""
freeform_transfer_json=""
programming_summary_json=""
programming_branchy_json=""
programming_auto_branchy_json=""
repo_runtime_web_triage_transfer_json="$DEFAULT_REPO_RUNTIME_WEB_TRIAGE_TRANSFER_JSON"
browser_image_run_investigation_transfer_json="$DEFAULT_BROWSER_IMAGE_RUN_INVESTIGATION_TRANSFER_JSON"
tool_failure_handoff_transfer_json="$DEFAULT_TOOL_FAILURE_HANDOFF_TRANSFER_JSON"
current_api_migration_transfer_json="$DEFAULT_CURRENT_API_MIGRATION_TRANSFER_JSON"
current_ops_guidance_transfer_json="$DEFAULT_CURRENT_OPS_GUIDANCE_TRANSFER_JSON"
standards_grounded_answer_transfer_json="$DEFAULT_STANDARDS_GROUNDED_ANSWER_TRANSFER_JSON"
operator_decision_transfer_json="$DEFAULT_OPERATOR_DECISION_TRANSFER_JSON"
multi_artifact_judgment_transfer_json="$DEFAULT_MULTI_ARTIFACT_JUDGMENT_TRANSFER_JSON"
long_context_reassessment_transfer_json="$DEFAULT_LONG_CONTEXT_REASSESSMENT_TRANSFER_JSON"
long_horizon_timeout_coverage_transfer_json="$DEFAULT_LONG_HORIZON_TIMEOUT_COVERAGE_TRANSFER_JSON"
document_transfer_json="$DEFAULT_DOCUMENT_TRANSFER_JSON"
remote_ops_transfer_json="$DEFAULT_REMOTE_OPS_TRANSFER_JSON"
remote_deploy_transfer_json="$DEFAULT_REMOTE_DEPLOY_TRANSFER_JSON"
remote_multi_host_transfer_json="$DEFAULT_REMOTE_MULTI_HOST_TRANSFER_JSON"
remote_multi_host_rollout_transfer_json="$DEFAULT_REMOTE_MULTI_HOST_ROLLOUT_TRANSFER_JSON"
remote_bastion_cutover_transfer_json="$DEFAULT_REMOTE_BASTION_CUTOVER_TRANSFER_JSON"
remote_boundary_rollout_transfer_json="$DEFAULT_REMOTE_BOUNDARY_ROLLOUT_TRANSFER_JSON"
remote_boundary_rollback_transfer_json="$DEFAULT_REMOTE_BOUNDARY_ROLLBACK_TRANSFER_JSON"
remote_boundary_pack_transfer_json="$DEFAULT_REMOTE_BOUNDARY_PACK_TRANSFER_JSON"
remote_release_pack_transfer_json="$DEFAULT_REMOTE_RELEASE_PACK_TRANSFER_JSON"
gui_visual_transfer_json="$DEFAULT_GUI_VISUAL_TRANSFER_JSON"
gui_screenshot_layout_triage_transfer_json="$DEFAULT_GUI_SCREENSHOT_LAYOUT_TRIAGE_TRANSFER_JSON"
gui_login_upload_download_transfer_json="$DEFAULT_GUI_LOGIN_UPLOAD_DOWNLOAD_TRANSFER_JSON"
gui_state_recovery_pack_transfer_json="$DEFAULT_GUI_STATE_RECOVERY_PACK_TRANSFER_JSON"
dashboard_chart_read_transfer_json="$DEFAULT_DASHBOARD_CHART_READ_TRANSFER_JSON"
terminal_screenshot_debug_transfer_json="$DEFAULT_TERMINAL_SCREENSHOT_DEBUG_TRANSFER_JSON"
before_after_ui_delta_transfer_json="$DEFAULT_BEFORE_AFTER_UI_DELTA_TRANSFER_JSON"
terminal_state_recovery_read_transfer_json="$DEFAULT_TERMINAL_STATE_RECOVERY_READ_TRANSFER_JSON"
diagram_annotation_read_transfer_json="$DEFAULT_DIAGRAM_ANNOTATION_READ_TRANSFER_JSON"
gui_profile="core"
gui_result=""
interactive_gui_profile="intelligence"
interactive_gui_result=""
require_interactive_intelligence=0
skip_intelligence=0
skip_interactive_intelligence=0
skip_programming=0
skip_gui=0
run_budget_sec=0
timeout_buffer_sec=140
task_timeout_sec=180

min_battery_overall=90
min_holdout_overall=90
min_holdout_adversarial=88
min_holdout_ambiguity=88
min_holdout_cross_domain=86
min_holdout_recovery=88
max_fail_open_rate=0
max_contradiction_rate=0
max_holdout_overall_drop=2

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --battery-file)
      battery_file=$2
      shift 2
      ;;
    --holdout-file)
      holdout_file=$2
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
    --mixed-battery-file)
      mixed_battery_file=$2
      shift 2
      ;;
    --mixed-holdout-file)
      mixed_holdout_file=$2
      shift 2
      ;;
    --mixed-battery-summary)
      mixed_battery_summary=$2
      shift 2
      ;;
    --mixed-holdout-summary)
      mixed_holdout_summary=$2
      shift 2
      ;;
    --mixed-transfer-json)
      mixed_transfer_json=$2
      shift 2
      ;;
    --compact-battery-file)
      compact_battery_file=$2
      shift 2
      ;;
    --compact-holdout-file)
      compact_holdout_file=$2
      shift 2
      ;;
    --compact-battery-summary)
      compact_battery_summary=$2
      shift 2
      ;;
    --compact-holdout-summary)
      compact_holdout_summary=$2
      shift 2
      ;;
    --compact-transfer-json)
      compact_transfer_json=$2
      shift 2
      ;;
    --rich-battery-file)
      rich_battery_file=$2
      shift 2
      ;;
    --rich-holdout-file)
      rich_holdout_file=$2
      shift 2
      ;;
    --rich-battery-summary)
      rich_battery_summary=$2
      shift 2
      ;;
    --rich-holdout-summary)
      rich_holdout_summary=$2
      shift 2
      ;;
    --rich-transfer-json)
      rich_transfer_json=$2
      shift 2
      ;;
    --freeform-battery-file)
      freeform_battery_file=$2
      shift 2
      ;;
    --freeform-holdout-file)
      freeform_holdout_file=$2
      shift 2
      ;;
    --freeform-battery-summary)
      freeform_battery_summary=$2
      shift 2
      ;;
    --freeform-holdout-summary)
      freeform_holdout_summary=$2
      shift 2
      ;;
    --freeform-transfer-json)
      freeform_transfer_json=$2
      shift 2
      ;;
    --programming-summary-json)
      programming_summary_json=$2
      shift 2
      ;;
    --programming-branchy-json)
      programming_branchy_json=$2
      shift 2
      ;;
    --programming-auto-branchy-json)
      programming_auto_branchy_json=$2
      shift 2
      ;;
    --repo-runtime-web-triage-transfer-json)
      repo_runtime_web_triage_transfer_json=$2
      shift 2
      ;;
    --browser-image-run-investigation-transfer-json)
      browser_image_run_investigation_transfer_json=$2
      shift 2
      ;;
    --tool-failure-handoff-transfer-json)
      tool_failure_handoff_transfer_json=$2
      shift 2
      ;;
    --current-api-migration-transfer-json)
      current_api_migration_transfer_json=$2
      shift 2
      ;;
    --current-ops-guidance-transfer-json)
      current_ops_guidance_transfer_json=$2
      shift 2
      ;;
    --standards-grounded-answer-transfer-json)
      standards_grounded_answer_transfer_json=$2
      shift 2
      ;;
    --operator-decision-transfer-json)
      operator_decision_transfer_json=$2
      shift 2
      ;;
    --multi-artifact-judgment-transfer-json)
      multi_artifact_judgment_transfer_json=$2
      shift 2
      ;;
    --long-context-reassessment-transfer-json)
      long_context_reassessment_transfer_json=$2
      shift 2
      ;;
    --long-horizon-timeout-coverage-transfer-json)
      long_horizon_timeout_coverage_transfer_json=$2
      shift 2
      ;;
    --document-transfer-json)
      document_transfer_json=$2
      shift 2
      ;;
    --remote-ops-transfer-json)
      remote_ops_transfer_json=$2
      shift 2
      ;;
    --remote-deploy-transfer-json)
      remote_deploy_transfer_json=$2
      shift 2
      ;;
    --remote-multi-host-transfer-json)
      remote_multi_host_transfer_json=$2
      shift 2
      ;;
    --remote-multi-host-rollout-transfer-json)
      remote_multi_host_rollout_transfer_json=$2
      shift 2
      ;;
    --remote-bastion-cutover-transfer-json)
      remote_bastion_cutover_transfer_json=$2
      shift 2
      ;;
    --remote-boundary-rollout-transfer-json)
      remote_boundary_rollout_transfer_json=$2
      shift 2
      ;;
    --remote-boundary-rollback-transfer-json)
      remote_boundary_rollback_transfer_json=$2
      shift 2
      ;;
    --remote-boundary-pack-transfer-json)
      remote_boundary_pack_transfer_json=$2
      shift 2
      ;;
    --remote-release-pack-transfer-json)
      remote_release_pack_transfer_json=$2
      shift 2
      ;;
    --gui-visual-transfer-json)
      gui_visual_transfer_json=$2
      shift 2
      ;;
    --gui-screenshot-layout-triage-transfer-json)
      gui_screenshot_layout_triage_transfer_json=$2
      shift 2
      ;;
    --gui-login-upload-download-transfer-json)
      gui_login_upload_download_transfer_json=$2
      shift 2
      ;;
    --gui-state-recovery-pack-transfer-json)
      gui_state_recovery_pack_transfer_json=$2
      shift 2
      ;;
    --dashboard-chart-read-transfer-json)
      dashboard_chart_read_transfer_json=$2
      shift 2
      ;;
    --terminal-screenshot-debug-transfer-json)
      terminal_screenshot_debug_transfer_json=$2
      shift 2
      ;;
    --before-after-ui-delta-transfer-json)
      before_after_ui_delta_transfer_json=$2
      shift 2
      ;;
    --terminal-state-recovery-read-transfer-json)
      terminal_state_recovery_read_transfer_json=$2
      shift 2
      ;;
    --diagram-annotation-read-transfer-json)
      diagram_annotation_read_transfer_json=$2
      shift 2
      ;;
    --gui-profile)
      gui_profile=$2
      shift 2
      ;;
    --gui-result)
      gui_result=$2
      shift 2
      ;;
    --interactive-gui-profile)
      interactive_gui_profile=$2
      shift 2
      ;;
    --interactive-gui-result)
      interactive_gui_result=$2
      shift 2
      ;;
    --require-interactive-intelligence)
      require_interactive_intelligence=1
      shift
      ;;
    --skip-intelligence)
      skip_intelligence=1
      shift
      ;;
    --skip-interactive-intelligence)
      skip_interactive_intelligence=1
      shift
      ;;
    --skip-programming)
      skip_programming=1
      shift
      ;;
    --skip-gui)
      skip_gui=1
      shift
      ;;
    --run-budget-sec)
      run_budget_sec=$2
      shift 2
      ;;
    --timeout-buffer-sec)
      timeout_buffer_sec=$2
      shift 2
      ;;
    --task-timeout-sec)
      task_timeout_sec=$2
      shift 2
      ;;
    --min-battery-overall)
      min_battery_overall=$2
      shift 2
      ;;
    --min-holdout-overall)
      min_holdout_overall=$2
      shift 2
      ;;
    --min-holdout-adversarial)
      min_holdout_adversarial=$2
      shift 2
      ;;
    --min-holdout-ambiguity)
      min_holdout_ambiguity=$2
      shift 2
      ;;
    --min-holdout-cross-domain)
      min_holdout_cross_domain=$2
      shift 2
      ;;
    --min-holdout-recovery)
      min_holdout_recovery=$2
      shift 2
      ;;
    --max-fail-open-rate)
      max_fail_open_rate=$2
      shift 2
      ;;
    --max-contradiction-rate)
      max_contradiction_rate=$2
      shift 2
      ;;
    --max-holdout-overall-drop)
      max_holdout_overall_drop=$2
      shift 2
      ;;
    --help|-h|--usage)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$gui_profile" in
  core|deep|background|full)
    ;;
  *)
    echo "Unknown --gui-profile value: $gui_profile" >&2
    exit 1
    ;;
esac

case "$interactive_gui_profile" in
  intelligence)
    ;;
  *)
    echo "Unknown --interactive-gui-profile value: $interactive_gui_profile" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR"

intelligence_enabled=true
interactive_intelligence_enabled=true
programming_enabled=true
gui_enabled=true
if [ "$skip_intelligence" -eq 1 ]; then
  intelligence_enabled=false
  interactive_intelligence_enabled=false
  programming_enabled=false
fi
if [ "$require_interactive_intelligence" -eq 1 ]; then
  interactive_intelligence_enabled=true
fi
if [ "$skip_interactive_intelligence" -eq 1 ]; then
  interactive_intelligence_enabled=false
fi
if [ "$skip_gui" -eq 1 ]; then
  gui_enabled=false
fi
if [ "$skip_programming" -eq 1 ]; then
  programming_enabled=false
fi

run_panel_and_extract_summary() {
  run_label=$1
  tasks_path=$2
  require_file "$tasks_path"
  run_output=$("$BROAD_SCRIPT" run \
    --label "$run_label" \
    --tasks-file "$tasks_path" \
    --run-budget-sec "$run_budget_sec" \
    --timeout-buffer-sec "$timeout_buffer_sec" \
    --task-timeout-sec "$task_timeout_sec")
  summary_path=$(printf '%s\n' "$run_output" | sed -n '2p')
  require_file "$summary_path"
  printf '%s' "$summary_path"
}

run_transfer_and_extract_paths() {
  transfer_label=$1
  battery_summary_path=$2
  holdout_summary_path=$3
  require_file "$battery_summary_path"
  require_file "$holdout_summary_path"
  transfer_output=$("$BROAD_SCRIPT" transfer \
    --label "$transfer_label" \
    --battery-summary "$battery_summary_path" \
    --holdout-summary "$holdout_summary_path")
  transfer_json_path=$(printf '%s\n' "$transfer_output" | sed -n '1p')
  transfer_report_path=$(printf '%s\n' "$transfer_output" | sed -n '2p')
  require_file "$transfer_json_path"
  require_file "$transfer_report_path"
  printf '%s\n%s\n' "$transfer_json_path" "$transfer_report_path"
}

run_compact_panel_and_extract_summary() {
  run_label=$1
  tasks_path=$2
  require_file "$tasks_path"
  run_output=$("$COMPACT_SCRIPT" run \
    --label "$run_label" \
    --tasks-file "$tasks_path")
  summary_path=$(printf '%s\n' "$run_output" | sed -n '2p')
  require_file "$summary_path"
  printf '%s' "$summary_path"
}

run_compact_transfer_and_extract_paths() {
  transfer_label=$1
  battery_summary_path=$2
  holdout_summary_path=$3
  require_file "$battery_summary_path"
  require_file "$holdout_summary_path"
  transfer_output=$("$COMPACT_SCRIPT" transfer \
    --label "$transfer_label" \
    --battery-summary "$battery_summary_path" \
    --holdout-summary "$holdout_summary_path")
  transfer_json_path=$(printf '%s\n' "$transfer_output" | sed -n '1p')
  transfer_report_path=$(printf '%s\n' "$transfer_output" | sed -n '2p')
  require_file "$transfer_json_path"
  require_file "$transfer_report_path"
  printf '%s\n%s\n' "$transfer_json_path" "$transfer_report_path"
}

run_rich_panel_and_extract_summary() {
  run_label=$1
  tasks_path=$2
  require_file "$tasks_path"
  run_output=$("$RICH_SCRIPT" run \
    --label "$run_label" \
    --tasks-file "$tasks_path")
  summary_path=$(printf '%s\n' "$run_output" | sed -n '2p')
  require_file "$summary_path"
  printf '%s' "$summary_path"
}

run_rich_transfer_and_extract_paths() {
  transfer_label=$1
  battery_summary_path=$2
  holdout_summary_path=$3
  require_file "$battery_summary_path"
  require_file "$holdout_summary_path"
  transfer_output=$("$RICH_SCRIPT" transfer \
    --label "$transfer_label" \
    --battery-summary "$battery_summary_path" \
    --holdout-summary "$holdout_summary_path")
  transfer_json_path=$(printf '%s\n' "$transfer_output" | sed -n '1p')
  transfer_report_path=$(printf '%s\n' "$transfer_output" | sed -n '2p')
  require_file "$transfer_json_path"
  require_file "$transfer_report_path"
  printf '%s\n%s\n' "$transfer_json_path" "$transfer_report_path"
}

run_freeform_panel_and_extract_summary() {
  run_label=$1
  tasks_path=$2
  require_file "$tasks_path"
  run_output=$("$FREEFORM_SCRIPT" run \
    --label "$run_label" \
    --tasks-file "$tasks_path")
  summary_path=$(printf '%s\n' "$run_output" | sed -n '2p')
  require_file "$summary_path"
  printf '%s' "$summary_path"
}

run_freeform_transfer_and_extract_paths() {
  transfer_label=$1
  battery_summary_path=$2
  holdout_summary_path=$3
  require_file "$battery_summary_path"
  require_file "$holdout_summary_path"
  transfer_output=$("$FREEFORM_SCRIPT" transfer \
    --label "$transfer_label" \
    --battery-summary "$battery_summary_path" \
    --holdout-summary "$holdout_summary_path")
  transfer_json_path=$(printf '%s\n' "$transfer_output" | sed -n '1p')
  transfer_report_path=$(printf '%s\n' "$transfer_output" | sed -n '2p')
  require_file "$transfer_json_path"
  require_file "$transfer_report_path"
  printf '%s\n%s\n' "$transfer_json_path" "$transfer_report_path"
}

run_programming_smoke_and_extract_paths() {
  run_label=$1
  smoke_output=$("$PROGRAMMING_SMOKE_SCRIPT" --label "$run_label")
  report_path=$(printf '%s\n' "$smoke_output" | sed -n '1p')
  json_path=$(printf '%s\n' "$report_path" | sed 's/\.md$/.json/')
  require_file "$report_path"
  require_file "$json_path"
  printf '%s\n%s\n' "$json_path" "$report_path"
}

run_programming_branchy_smoke_and_extract_paths() {
  run_label=$1
  smoke_output=$("$PROGRAMMING_BRANCHY_SMOKE_SCRIPT" --label "$run_label")
  report_path=$(printf '%s\n' "$smoke_output" | sed -n '1p')
  json_path=$(printf '%s\n' "$report_path" | sed 's/\.md$/.json/')
  require_file "$report_path"
  require_file "$json_path"
  printf '%s\n%s\n' "$json_path" "$report_path"
}

run_programming_auto_branchy_smoke_and_extract_paths() {
  run_label=$1
  smoke_output=$("$PROGRAMMING_BRANCHY_SMOKE_SCRIPT" --label "$run_label" --fixtures "$DEFAULT_PROGRAMMING_AUTO_BRANCHY_FILE")
  report_path=$(printf '%s\n' "$smoke_output" | sed -n '1p')
  json_path=$(printf '%s\n' "$report_path" | sed 's/\.md$/.json/')
  require_file "$report_path"
  require_file "$json_path"
  printf '%s\n%s\n' "$json_path" "$report_path"
}

run_gui_and_extract_paths() {
  gui_label=$1
  gui_profile_value=$2
  attempt=1
  max_attempts=2
  gui_output=""
  gui_status=1
  gui_result_path=""
  gui_report_path=""
  gui_success="false"
  gui_timeout_seconds=420
  case "$gui_profile_value" in
    core)
      gui_timeout_seconds=360
      ;;
    intelligence)
      gui_timeout_seconds=540
      ;;
    deep)
      gui_timeout_seconds=480
      ;;
    background|full)
      gui_timeout_seconds=720
      ;;
  esac
  while [ "$attempt" -le "$max_attempts" ]; do
    gui_output_file=$(mktemp "${TMPDIR:-/tmp}/artificer-release-gui-output.XXXXXX")
    fallback_result_path="$OUT_DIR/$gui_label-gui-result.json"
    fallback_report_path="$OUT_DIR/$gui_label-gui-report.md"
    set +e
    run_command_with_timeout_to_file "$gui_timeout_seconds" "$gui_output_file" "$GUI_SCRIPT" --profile "$gui_profile_value" --label "$gui_label"
    gui_status=$?
    set -e
    gui_output=$(cat "$gui_output_file" 2>/dev/null || true)
    rm -f "$gui_output_file"
    gui_result_path=$(printf '%s\n' "$gui_output" | awk '/result\.json$/ {print; exit}')
    gui_report_path=$(printf '%s\n' "$gui_output" | awk '/report\.md$/ {print; exit}')
    if [ -z "$gui_result_path" ] && [ -f "$fallback_result_path" ]; then
      gui_result_path="$fallback_result_path"
    fi
    if [ -z "$gui_report_path" ] && [ -f "$fallback_report_path" ]; then
      gui_report_path="$fallback_report_path"
    fi
    gui_success="false"
    if [ -n "$gui_result_path" ] && [ -f "$gui_result_path" ]; then
      gui_success=$(jq -r 'if .success == true then "true" else "false" end' "$gui_result_path")
    fi
    if [ "$gui_success" = "true" ]; then
      gui_status=0
    fi
    if [ "$gui_status" -eq 0 ] && [ "$gui_success" = "true" ]; then
      break
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      break
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  printf '%s\n%s\n%s\n' "$gui_status" "$gui_result_path" "$gui_report_path"
}

if [ "$intelligence_enabled" = "true" ]; then
  if [ -z "$battery_summary" ]; then
    battery_summary=$(run_panel_and_extract_summary "${label}-battery" "$battery_file")
  fi
  if [ -z "$holdout_summary" ]; then
    holdout_summary=$(run_panel_and_extract_summary "${label}-holdout" "$holdout_file")
  fi
  if [ -z "$mixed_battery_summary" ]; then
    mixed_battery_summary=$(run_panel_and_extract_summary "${label}-mixed-battery" "$mixed_battery_file")
  fi
  if [ -z "$mixed_holdout_summary" ]; then
    mixed_holdout_summary=$(run_panel_and_extract_summary "${label}-mixed-holdout" "$mixed_holdout_file")
  fi
  if [ -z "$mixed_transfer_json" ]; then
    mixed_transfer_paths=$(run_transfer_and_extract_paths "${label}-mixed-transfer" "$mixed_battery_summary" "$mixed_holdout_summary")
    mixed_transfer_json=$(printf '%s\n' "$mixed_transfer_paths" | sed -n '1p')
    mixed_transfer_report=$(printf '%s\n' "$mixed_transfer_paths" | sed -n '2p')
  fi
  if [ -z "$compact_battery_summary" ]; then
    compact_battery_summary=$(run_compact_panel_and_extract_summary "${label}-compact-battery" "$compact_battery_file")
  fi
  if [ -z "$compact_holdout_summary" ]; then
    compact_holdout_summary=$(run_compact_panel_and_extract_summary "${label}-compact-holdout" "$compact_holdout_file")
  fi
  if [ -z "$compact_transfer_json" ]; then
    compact_transfer_paths=$(run_compact_transfer_and_extract_paths "${label}-compact-transfer" "$compact_battery_summary" "$compact_holdout_summary")
    compact_transfer_json=$(printf '%s\n' "$compact_transfer_paths" | sed -n '1p')
    compact_transfer_report=$(printf '%s\n' "$compact_transfer_paths" | sed -n '2p')
  fi
  if [ -z "$rich_battery_summary" ]; then
    rich_battery_summary=$(run_rich_panel_and_extract_summary "${label}-rich-battery" "$rich_battery_file")
  fi
  if [ -z "$rich_holdout_summary" ]; then
    rich_holdout_summary=$(run_rich_panel_and_extract_summary "${label}-rich-holdout" "$rich_holdout_file")
  fi
  if [ -z "$rich_transfer_json" ]; then
    rich_transfer_paths=$(run_rich_transfer_and_extract_paths "${label}-rich-transfer" "$rich_battery_summary" "$rich_holdout_summary")
    rich_transfer_json=$(printf '%s\n' "$rich_transfer_paths" | sed -n '1p')
    rich_transfer_report=$(printf '%s\n' "$rich_transfer_paths" | sed -n '2p')
  fi
  if [ -z "$freeform_battery_summary" ]; then
    freeform_battery_summary=$(run_freeform_panel_and_extract_summary "${label}-freeform-battery" "$freeform_battery_file")
  fi
  if [ -z "$freeform_holdout_summary" ]; then
    freeform_holdout_summary=$(run_freeform_panel_and_extract_summary "${label}-freeform-holdout" "$freeform_holdout_file")
  fi
  if [ -z "$freeform_transfer_json" ]; then
    freeform_transfer_paths=$(run_freeform_transfer_and_extract_paths "${label}-freeform-transfer" "$freeform_battery_summary" "$freeform_holdout_summary")
    freeform_transfer_json=$(printf '%s\n' "$freeform_transfer_paths" | sed -n '1p')
    freeform_transfer_report=$(printf '%s\n' "$freeform_transfer_paths" | sed -n '2p')
  fi
  if [ "$programming_enabled" = "true" ] && [ -z "$programming_summary_json" ]; then
    programming_smoke_paths=$(run_programming_smoke_and_extract_paths "${label}-programming-stalled")
    programming_summary_json=$(printf '%s\n' "$programming_smoke_paths" | sed -n '1p')
    programming_summary_report=$(printf '%s\n' "$programming_smoke_paths" | sed -n '2p')
  fi
  if [ "$programming_enabled" = "true" ] && [ -z "$programming_branchy_json" ]; then
    programming_branchy_paths=$(run_programming_branchy_smoke_and_extract_paths "${label}-programming-branchy")
    programming_branchy_json=$(printf '%s\n' "$programming_branchy_paths" | sed -n '1p')
    programming_branchy_report=$(printf '%s\n' "$programming_branchy_paths" | sed -n '2p')
  fi
  if [ "$programming_enabled" = "true" ] && [ -z "$programming_auto_branchy_json" ]; then
    programming_auto_branchy_paths=$(run_programming_auto_branchy_smoke_and_extract_paths "${label}-programming-auto-branchy")
    programming_auto_branchy_json=$(printf '%s\n' "$programming_auto_branchy_paths" | sed -n '1p')
    programming_auto_branchy_report=$(printf '%s\n' "$programming_auto_branchy_paths" | sed -n '2p')
  fi
  require_file "$battery_summary"
  require_file "$holdout_summary"
  require_file "$mixed_battery_summary"
  require_file "$mixed_holdout_summary"
  require_file "$mixed_transfer_json"
  require_file "$compact_battery_summary"
  require_file "$compact_holdout_summary"
  require_file "$compact_transfer_json"
  require_file "$rich_battery_summary"
  require_file "$rich_holdout_summary"
  require_file "$rich_transfer_json"
  require_file "$freeform_battery_summary"
  require_file "$freeform_holdout_summary"
  require_file "$freeform_transfer_json"
  if [ "$programming_enabled" = "true" ]; then
    require_file "$programming_summary_json"
    require_file "$programming_branchy_json"
    require_file "$programming_auto_branchy_json"
  fi
fi

battery_overall=""
battery_fail_open=""
battery_contradiction=""
battery_done=""

holdout_overall=""
holdout_fail_open=""
holdout_contradiction=""
holdout_adversarial=""
holdout_ambiguity=""
holdout_cross_domain=""
holdout_recovery=""
holdout_done=""
mixed_transfer_report=""
mixed_transfer_pass=true
mixed_transfer_risk=""
mixed_improved_axes=""
mixed_stable_axes=""
mixed_coverage_axes=""
mixed_gate_fail_open=true
mixed_gate_contradiction=true
mixed_gate_holdout=true
mixed_gate_improved_axes=true
mixed_gate_coverage_axes=true
mixed_gate_saturation=true
compact_transfer_report=""
compact_transfer_pass=true
compact_transfer_risk=""
compact_battery_exact_contract=""
compact_battery_required_ratio=""
compact_battery_owner_window=""
compact_holdout_exact_contract=""
compact_holdout_required_ratio=""
compact_holdout_owner_window=""
compact_gate_fail_open=true
compact_gate_contradiction=true
compact_gate_holdout=true
compact_gate_exact=true
compact_gate_required=true
compact_gate_owner_window=true
rich_transfer_report=""
rich_transfer_pass=true
rich_transfer_risk=""
rich_battery_exact_contract=""
rich_battery_required_ratio=""
rich_battery_core_labels=""
rich_holdout_exact_contract=""
rich_holdout_required_ratio=""
rich_holdout_core_labels=""
rich_gate_fail_open=true
rich_gate_contradiction=true
rich_gate_holdout=true
rich_gate_exact=true
rich_gate_required=true
rich_gate_core_labels=true
freeform_transfer_report=""
freeform_transfer_pass=true
freeform_transfer_risk=""
freeform_battery_freeform_rate=""
freeform_battery_uncertainty_rate=""
freeform_battery_reversal_rate=""
freeform_battery_required_ratio=""
freeform_holdout_freeform_rate=""
freeform_holdout_uncertainty_rate=""
freeform_holdout_reversal_rate=""
freeform_holdout_required_ratio=""
freeform_gate_fail_open=true
freeform_gate_contradiction=true
freeform_gate_holdout=true
freeform_gate_freeform=true
freeform_gate_uncertainty=true
freeform_gate_reversal=true
freeform_gate_required=true
programming_summary_report=""
programming_gate_pass=true
programming_total=""
programming_passes=""
programming_failures=""
programming_gate_nonempty=true
programming_gate_all_rows=true
programming_branchy_report=""
programming_branchy_gate_pass=true
programming_branchy_total=""
programming_branchy_passes=""
programming_branchy_failures=""
programming_branchy_gate_nonempty=true
programming_branchy_gate_all_rows=true
programming_auto_branchy_report=""
programming_auto_branchy_gate_pass=true
programming_auto_branchy_total=""
programming_auto_branchy_passes=""
programming_auto_branchy_failures=""
programming_auto_branchy_gate_nonempty=true
programming_auto_branchy_gate_all_rows=true
programming_long_horizon_required_rows="until-complete-calc-phase2-followup,until-complete-calc-stopgo-phase3,until-complete-calc-phase3-followup,until-complete-calc-phase3-cross-session,until-complete-calc-phase2-cross-workspace"
programming_long_horizon_present_rows=""
programming_long_horizon_passing_rows=""
programming_long_horizon_expected_count="5"
programming_long_horizon_present_count=""
programming_long_horizon_pass_count=""
programming_long_horizon_gate_pass=true
programming_long_horizon_required_rows_present=true
programming_long_horizon_required_rows_pass=true
long_horizon_timeout_required_families="long-horizon-timeout-coverage"
long_horizon_timeout_present_families=""
long_horizon_timeout_passing_families=""
long_horizon_timeout_expected_count="1"
long_horizon_timeout_present_count="0"
long_horizon_timeout_pass_count="0"
long_horizon_timeout_gate_pass=true
long_horizon_timeout_required_present=true
long_horizon_timeout_required_pass=true
document_required_families="document-v1"
document_present_families=""
document_passing_families=""
document_expected_count="1"
document_present_count="0"
document_pass_count="0"
document_gate_pass=true
document_required_present=true
document_required_pass=true
multi_tool_required_families="repo-runtime-web-triage,browser-image-run-investigation,tool-failure-handoff"
multi_tool_present_families=""
multi_tool_passing_families=""
multi_tool_expected_count="3"
multi_tool_present_count="0"
multi_tool_pass_count="0"
multi_tool_gate_pass=true
multi_tool_required_present=true
multi_tool_required_pass=true
freshness_required_families="current-api-migration,current-ops-guidance,standards-grounded-answer"
freshness_present_families=""
freshness_passing_families=""
freshness_expected_count="3"
freshness_present_count="0"
freshness_pass_count="0"
freshness_gate_pass=true
freshness_required_present=true
freshness_required_pass=true
operator_required_families="operator-decision,multi-artifact-judgment,long-context-reassessment"
operator_present_families=""
operator_passing_families=""
operator_expected_count="3"
operator_present_count="0"
operator_pass_count="0"
operator_gate_pass=true
operator_required_present=true
operator_required_pass=true
remote_required_families="remote-ops,remote-deploy,remote-multi-host,remote-multi-host-rollout,remote-bastion-cutover,remote-boundary-rollout,remote-boundary-rollback,remote-boundary-pack,remote-release-pack"
remote_present_families=""
remote_passing_families=""
remote_expected_count="9"
remote_present_count="0"
remote_pass_count="0"
remote_gate_pass=true
remote_required_present=true
remote_required_pass=true
gui_release_required_families="gui-visual,gui-screenshot-layout-triage,gui-login-upload-download,gui-state-recovery-pack"
gui_release_present_families=""
gui_release_passing_families=""
gui_release_expected_count="4"
gui_release_present_count="0"
gui_release_pass_count="0"
gui_release_gate_pass=true
gui_release_required_present=true
gui_release_required_pass=true
visual_required_families="dashboard-chart-read,terminal-screenshot-debug,before-after-ui-delta,terminal-state-recovery-read,diagram-annotation-read"
visual_present_families=""
visual_passing_families=""
visual_expected_count="5"
visual_present_count="0"
visual_pass_count="0"
visual_gate_pass=true
visual_required_present=true
visual_required_pass=true
repo_runtime_web_triage_transfer_report=""
repo_runtime_web_triage_transfer_pass=false
repo_runtime_web_triage_transfer_risk=""
browser_image_run_investigation_transfer_report=""
browser_image_run_investigation_transfer_pass=false
browser_image_run_investigation_transfer_risk=""
tool_failure_handoff_transfer_report=""
tool_failure_handoff_transfer_pass=false
tool_failure_handoff_transfer_risk=""
current_api_migration_transfer_report=""
current_api_migration_transfer_pass=false
current_api_migration_transfer_risk=""
current_ops_guidance_transfer_report=""
current_ops_guidance_transfer_pass=false
current_ops_guidance_transfer_risk=""
standards_grounded_answer_transfer_report=""
standards_grounded_answer_transfer_pass=false
standards_grounded_answer_transfer_risk=""
operator_decision_transfer_report=""
operator_decision_transfer_pass=false
operator_decision_transfer_risk=""
multi_artifact_judgment_transfer_report=""
multi_artifact_judgment_transfer_pass=false
multi_artifact_judgment_transfer_risk=""
long_context_reassessment_transfer_report=""
long_context_reassessment_transfer_pass=false
long_context_reassessment_transfer_risk=""
long_horizon_timeout_coverage_transfer_report=""
long_horizon_timeout_coverage_transfer_pass=false
long_horizon_timeout_coverage_transfer_risk=""
document_transfer_report=""
document_transfer_pass=false
document_transfer_risk=""
remote_ops_transfer_report=""
remote_ops_transfer_pass=false
remote_ops_transfer_risk=""
remote_deploy_transfer_report=""
remote_deploy_transfer_pass=false
remote_deploy_transfer_risk=""
remote_multi_host_transfer_report=""
remote_multi_host_transfer_pass=false
remote_multi_host_transfer_risk=""
remote_multi_host_rollout_transfer_report=""
remote_multi_host_rollout_transfer_pass=false
remote_multi_host_rollout_transfer_risk=""
remote_bastion_cutover_transfer_report=""
remote_bastion_cutover_transfer_pass=false
remote_bastion_cutover_transfer_risk=""
remote_boundary_rollout_transfer_report=""
remote_boundary_rollout_transfer_pass=false
remote_boundary_rollout_transfer_risk=""
remote_boundary_rollback_transfer_report=""
remote_boundary_rollback_transfer_pass=false
remote_boundary_rollback_transfer_risk=""
remote_boundary_pack_transfer_report=""
remote_boundary_pack_transfer_pass=false
remote_boundary_pack_transfer_risk=""
remote_release_pack_transfer_report=""
remote_release_pack_transfer_pass=false
remote_release_pack_transfer_risk=""
gui_visual_transfer_report=""
gui_visual_transfer_pass=false
gui_visual_transfer_risk=""
gui_screenshot_layout_triage_transfer_report=""
gui_screenshot_layout_triage_transfer_pass=false
gui_screenshot_layout_triage_transfer_risk=""
gui_login_upload_download_transfer_report=""
gui_login_upload_download_transfer_pass=false
gui_login_upload_download_transfer_risk=""
gui_state_recovery_pack_transfer_report=""
gui_state_recovery_pack_transfer_pass=false
gui_state_recovery_pack_transfer_risk=""
dashboard_chart_read_transfer_report=""
dashboard_chart_read_transfer_pass=false
dashboard_chart_read_transfer_risk=""
terminal_screenshot_debug_transfer_report=""
terminal_screenshot_debug_transfer_pass=false
terminal_screenshot_debug_transfer_risk=""
before_after_ui_delta_transfer_report=""
before_after_ui_delta_transfer_pass=false
before_after_ui_delta_transfer_risk=""
terminal_state_recovery_read_transfer_report=""
terminal_state_recovery_read_transfer_pass=false
terminal_state_recovery_read_transfer_risk=""
diagram_annotation_read_transfer_report=""
diagram_annotation_read_transfer_pass=false
diagram_annotation_read_transfer_risk=""

gate_battery_overall=true
gate_holdout_overall=true
gate_holdout_adversarial=true
gate_holdout_ambiguity=true
gate_holdout_cross_domain=true
gate_holdout_recovery=true
gate_fail_open=true
gate_contradiction=true
gate_holdout_drop=true
gate_done_counts=true
intelligence_pass=true

if [ -n "$mixed_transfer_json" ]; then
  mixed_transfer_report=$(printf '%s\n' "$mixed_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$compact_transfer_json" ]; then
  compact_transfer_report=$(printf '%s\n' "$compact_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$rich_transfer_json" ]; then
  rich_transfer_report=$(printf '%s\n' "$rich_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$freeform_transfer_json" ]; then
  freeform_transfer_report=$(printf '%s\n' "$freeform_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$programming_summary_json" ]; then
  programming_summary_report=$(printf '%s\n' "$programming_summary_json" | sed 's/\.json$/.md/')
fi
if [ -n "$programming_branchy_json" ]; then
  programming_branchy_report=$(printf '%s\n' "$programming_branchy_json" | sed 's/\.json$/.md/')
fi
if [ -n "$programming_auto_branchy_json" ]; then
  programming_auto_branchy_report=$(printf '%s\n' "$programming_auto_branchy_json" | sed 's/\.json$/.md/')
fi
if [ -n "$repo_runtime_web_triage_transfer_json" ]; then
  repo_runtime_web_triage_transfer_report=$(printf '%s\n' "$repo_runtime_web_triage_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$browser_image_run_investigation_transfer_json" ]; then
  browser_image_run_investigation_transfer_report=$(printf '%s\n' "$browser_image_run_investigation_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$tool_failure_handoff_transfer_json" ]; then
  tool_failure_handoff_transfer_report=$(printf '%s\n' "$tool_failure_handoff_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$current_api_migration_transfer_json" ]; then
  current_api_migration_transfer_report=$(printf '%s\n' "$current_api_migration_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$current_ops_guidance_transfer_json" ]; then
  current_ops_guidance_transfer_report=$(printf '%s\n' "$current_ops_guidance_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$standards_grounded_answer_transfer_json" ]; then
  standards_grounded_answer_transfer_report=$(printf '%s\n' "$standards_grounded_answer_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$operator_decision_transfer_json" ]; then
  operator_decision_transfer_report=$(printf '%s\n' "$operator_decision_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$multi_artifact_judgment_transfer_json" ]; then
  multi_artifact_judgment_transfer_report=$(printf '%s\n' "$multi_artifact_judgment_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$long_context_reassessment_transfer_json" ]; then
  long_context_reassessment_transfer_report=$(printf '%s\n' "$long_context_reassessment_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$long_horizon_timeout_coverage_transfer_json" ]; then
  long_horizon_timeout_coverage_transfer_report=$(printf '%s\n' "$long_horizon_timeout_coverage_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$document_transfer_json" ]; then
  document_transfer_report=$(printf '%s\n' "$document_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_ops_transfer_json" ]; then
  remote_ops_transfer_report=$(printf '%s\n' "$remote_ops_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_deploy_transfer_json" ]; then
  remote_deploy_transfer_report=$(printf '%s\n' "$remote_deploy_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_multi_host_transfer_json" ]; then
  remote_multi_host_transfer_report=$(printf '%s\n' "$remote_multi_host_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_multi_host_rollout_transfer_json" ]; then
  remote_multi_host_rollout_transfer_report=$(printf '%s\n' "$remote_multi_host_rollout_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_bastion_cutover_transfer_json" ]; then
  remote_bastion_cutover_transfer_report=$(printf '%s\n' "$remote_bastion_cutover_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_boundary_rollout_transfer_json" ]; then
  remote_boundary_rollout_transfer_report=$(printf '%s\n' "$remote_boundary_rollout_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_boundary_rollback_transfer_json" ]; then
  remote_boundary_rollback_transfer_report=$(printf '%s\n' "$remote_boundary_rollback_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_boundary_pack_transfer_json" ]; then
  remote_boundary_pack_transfer_report=$(printf '%s\n' "$remote_boundary_pack_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$remote_release_pack_transfer_json" ]; then
  remote_release_pack_transfer_report=$(printf '%s\n' "$remote_release_pack_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$gui_visual_transfer_json" ]; then
  gui_visual_transfer_report=$(printf '%s\n' "$gui_visual_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$gui_screenshot_layout_triage_transfer_json" ]; then
  gui_screenshot_layout_triage_transfer_report=$(printf '%s\n' "$gui_screenshot_layout_triage_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$gui_login_upload_download_transfer_json" ]; then
  gui_login_upload_download_transfer_report=$(printf '%s\n' "$gui_login_upload_download_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$gui_state_recovery_pack_transfer_json" ]; then
  gui_state_recovery_pack_transfer_report=$(printf '%s\n' "$gui_state_recovery_pack_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$dashboard_chart_read_transfer_json" ]; then
  dashboard_chart_read_transfer_report=$(printf '%s\n' "$dashboard_chart_read_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$terminal_screenshot_debug_transfer_json" ]; then
  terminal_screenshot_debug_transfer_report=$(printf '%s\n' "$terminal_screenshot_debug_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$before_after_ui_delta_transfer_json" ]; then
  before_after_ui_delta_transfer_report=$(printf '%s\n' "$before_after_ui_delta_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$terminal_state_recovery_read_transfer_json" ]; then
  terminal_state_recovery_read_transfer_report=$(printf '%s\n' "$terminal_state_recovery_read_transfer_json" | sed 's/\.json$/.md/')
fi
if [ -n "$diagram_annotation_read_transfer_json" ]; then
  diagram_annotation_read_transfer_report=$(printf '%s\n' "$diagram_annotation_read_transfer_json" | sed 's/\.json$/.md/')
fi

if [ "$intelligence_enabled" = "true" ]; then
  battery_overall=$(jq -r '.avg_overall // 0' "$battery_summary")
  battery_fail_open=$(jq -r '.fail_open_rate // 1' "$battery_summary")
  battery_contradiction=$(jq -r '.contradiction_rate // 1' "$battery_summary")
  battery_done=$(jq -r '.done // 0' "$battery_summary")

  holdout_overall=$(jq -r '.avg_overall // 0' "$holdout_summary")
  holdout_fail_open=$(jq -r '.fail_open_rate // 1' "$holdout_summary")
  holdout_contradiction=$(jq -r '.contradiction_rate // 1' "$holdout_summary")
  holdout_adversarial=$(jq -r '.avg_adversarial // 0' "$holdout_summary")
  holdout_ambiguity=$(jq -r '.avg_ambiguity // 0' "$holdout_summary")
  holdout_cross_domain=$(jq -r '.avg_cross_domain // 0' "$holdout_summary")
  holdout_recovery=$(jq -r '.avg_recovery // 0' "$holdout_summary")
  holdout_done=$(jq -r '.done // 0' "$holdout_summary")

  gate_battery_overall=false
  if num_ge "$battery_overall" "$min_battery_overall"; then
    gate_battery_overall=true
  fi

  gate_holdout_overall=false
  if num_ge "$holdout_overall" "$min_holdout_overall"; then
    gate_holdout_overall=true
  fi

  gate_holdout_adversarial=false
  if num_ge "$holdout_adversarial" "$min_holdout_adversarial"; then
    gate_holdout_adversarial=true
  fi

  gate_holdout_ambiguity=false
  if num_ge "$holdout_ambiguity" "$min_holdout_ambiguity"; then
    gate_holdout_ambiguity=true
  fi

  gate_holdout_cross_domain=false
  if num_ge "$holdout_cross_domain" "$min_holdout_cross_domain"; then
    gate_holdout_cross_domain=true
  fi

  gate_holdout_recovery=false
  if num_ge "$holdout_recovery" "$min_holdout_recovery"; then
    gate_holdout_recovery=true
  fi

  gate_fail_open=false
  if num_le "$battery_fail_open" "$max_fail_open_rate" && num_le "$holdout_fail_open" "$max_fail_open_rate"; then
    gate_fail_open=true
  fi

  gate_contradiction=false
  if num_le "$battery_contradiction" "$max_contradiction_rate" && num_le "$holdout_contradiction" "$max_contradiction_rate"; then
    gate_contradiction=true
  fi

  min_holdout_allowed=$(awk -v b="$battery_overall" -v d="$max_holdout_overall_drop" 'BEGIN { printf "%.6f", ((b + 0) - (d + 0)) }')
  gate_holdout_drop=false
  if num_ge "$holdout_overall" "$min_holdout_allowed"; then
    gate_holdout_drop=true
  fi

  gate_done_counts=false
  if num_ge "$battery_done" "1" && num_ge "$holdout_done" "1"; then
    gate_done_counts=true
  fi

  mixed_transfer_pass=$(jq -r 'if .all_gates_pass == true then "true" else "false" end' "$mixed_transfer_json")
  mixed_transfer_risk=$(jq -r '.transfer_risk // ""' "$mixed_transfer_json")
  mixed_improved_axes=$(jq -r '.improved_axes_count // 0' "$mixed_transfer_json")
  mixed_stable_axes=$(jq -r '.stable_excellence_axes_count // 0' "$mixed_transfer_json")
  mixed_coverage_axes=$(jq -r '.robustness_coverage_axes_count // 0' "$mixed_transfer_json")
  mixed_gate_fail_open=$(jq -r '.gates.fail_open_non_increase // false' "$mixed_transfer_json")
  mixed_gate_contradiction=$(jq -r '.gates.contradiction_non_increase // false' "$mixed_transfer_json")
  mixed_gate_holdout=$(jq -r '.gates.holdout_not_worse_overall // false' "$mixed_transfer_json")
  mixed_gate_improved_axes=$(jq -r '.gates.improved_axes_at_least_two // false' "$mixed_transfer_json")
  mixed_gate_coverage_axes=$(jq -r '.gates.robustness_coverage_at_least_two // false' "$mixed_transfer_json")
  mixed_gate_saturation=$(jq -r '.gates.no_saturation_risk // false' "$mixed_transfer_json")
  compact_transfer_pass=$(jq -r 'if .all_gates_pass == true then "true" else "false" end' "$compact_transfer_json")
  compact_transfer_risk=$(jq -r '.transfer_risk // ""' "$compact_transfer_json")
  compact_battery_exact_contract=$(jq -r '.exact_contract_rate // 0' "$compact_battery_summary")
  compact_battery_required_ratio=$(jq -r '.avg_required_ratio // 0' "$compact_battery_summary")
  compact_battery_owner_window=$(jq -r '.owner_window_rate // 0' "$compact_battery_summary")
  compact_holdout_exact_contract=$(jq -r '.exact_contract_rate // 0' "$compact_holdout_summary")
  compact_holdout_required_ratio=$(jq -r '.avg_required_ratio // 0' "$compact_holdout_summary")
  compact_holdout_owner_window=$(jq -r '.owner_window_rate // 0' "$compact_holdout_summary")
  compact_gate_fail_open=$(jq -r '.gates.fail_open_non_increase // false' "$compact_transfer_json")
  compact_gate_contradiction=$(jq -r '.gates.contradiction_non_increase // false' "$compact_transfer_json")
  compact_gate_holdout=$(jq -r '.gates.holdout_not_worse_overall // false' "$compact_transfer_json")
  compact_gate_exact=$(jq -r '.gates.exact_contract_full // false' "$compact_transfer_json")
  compact_gate_required=$(jq -r '.gates.required_ratio_full // false' "$compact_transfer_json")
  compact_gate_owner_window=$(jq -r '.gates.owner_window_full // false' "$compact_transfer_json")
  rich_transfer_pass=$(jq -r 'if .all_gates_pass == true then "true" else "false" end' "$rich_transfer_json")
  rich_transfer_risk=$(jq -r '.transfer_risk // ""' "$rich_transfer_json")
  rich_battery_exact_contract=$(jq -r '.exact_contract_rate // 0' "$rich_battery_summary")
  rich_battery_required_ratio=$(jq -r '.avg_required_ratio // 0' "$rich_battery_summary")
  rich_battery_core_labels=$(jq -r '.core_labels_exact_once_rate // 0' "$rich_battery_summary")
  rich_holdout_exact_contract=$(jq -r '.exact_contract_rate // 0' "$rich_holdout_summary")
  rich_holdout_required_ratio=$(jq -r '.avg_required_ratio // 0' "$rich_holdout_summary")
  rich_holdout_core_labels=$(jq -r '.core_labels_exact_once_rate // 0' "$rich_holdout_summary")
  rich_gate_fail_open=$(jq -r '.gates.fail_open_non_increase // false' "$rich_transfer_json")
  rich_gate_contradiction=$(jq -r '.gates.contradiction_non_increase // false' "$rich_transfer_json")
  rich_gate_holdout=$(jq -r '.gates.holdout_not_worse_overall // false' "$rich_transfer_json")
  rich_gate_exact=$(jq -r '.gates.exact_contract_full // false' "$rich_transfer_json")
  rich_gate_required=$(jq -r '.gates.required_ratio_full // false' "$rich_transfer_json")
  rich_gate_core_labels=$(jq -r '.gates.core_labels_full // false' "$rich_transfer_json")
  freeform_transfer_pass=$(jq -r 'if .all_gates_pass == true then "true" else "false" end' "$freeform_transfer_json")
  freeform_transfer_risk=$(jq -r '.transfer_risk // ""' "$freeform_transfer_json")
  freeform_battery_freeform_rate=$(jq -r '.freeform_rate // 0' "$freeform_battery_summary")
  freeform_battery_uncertainty_rate=$(jq -r '.uncertainty_rate // 0' "$freeform_battery_summary")
  freeform_battery_reversal_rate=$(jq -r '.reversal_rate // 0' "$freeform_battery_summary")
  freeform_battery_required_ratio=$(jq -r '.avg_required_ratio // 0' "$freeform_battery_summary")
  freeform_holdout_freeform_rate=$(jq -r '.freeform_rate // 0' "$freeform_holdout_summary")
  freeform_holdout_uncertainty_rate=$(jq -r '.uncertainty_rate // 0' "$freeform_holdout_summary")
  freeform_holdout_reversal_rate=$(jq -r '.reversal_rate // 0' "$freeform_holdout_summary")
  freeform_holdout_required_ratio=$(jq -r '.avg_required_ratio // 0' "$freeform_holdout_summary")
  freeform_gate_fail_open=$(jq -r '.gates.fail_open_non_increase // false' "$freeform_transfer_json")
  freeform_gate_contradiction=$(jq -r '.gates.contradiction_non_increase // false' "$freeform_transfer_json")
  freeform_gate_holdout=$(jq -r '.gates.holdout_not_worse_overall // false' "$freeform_transfer_json")
  freeform_gate_freeform=$(jq -r '.gates.freeform_full // false' "$freeform_transfer_json")
  freeform_gate_uncertainty=$(jq -r '.gates.uncertainty_full // false' "$freeform_transfer_json")
  freeform_gate_reversal=$(jq -r '.gates.reversal_full // false' "$freeform_transfer_json")
  freeform_gate_required=$(jq -r '.gates.required_ratio_full // false' "$freeform_transfer_json")
  if [ "$programming_enabled" = "true" ]; then
    programming_total=$(jq -r '.total // 0' "$programming_summary_json")
    programming_passes=$(jq -r '.passes // 0' "$programming_summary_json")
    programming_failures=$(jq -r '.failures // 1' "$programming_summary_json")
    programming_gate_nonempty=false
    if num_ge "$programming_total" "1"; then
      programming_gate_nonempty=true
    fi
    programming_gate_all_rows=$(jq -r 'if (.total // 0) >= 1 and (.passes // 0) == (.total // 0) and (.failures // 1) == 0 then "true" else "false" end' "$programming_summary_json")
    if [ "$programming_gate_nonempty" != "true" ] || [ "$programming_gate_all_rows" != "true" ]; then
      programming_gate_pass=false
    fi

    programming_branchy_total=$(jq -r '.total // 0' "$programming_branchy_json")
    programming_branchy_passes=$(jq -r '.passes // 0' "$programming_branchy_json")
    programming_branchy_failures=$(jq -r '.failures // 1' "$programming_branchy_json")
    programming_branchy_gate_nonempty=false
    if num_ge "$programming_branchy_total" "1"; then
      programming_branchy_gate_nonempty=true
    fi
    programming_branchy_gate_all_rows=$(jq -r 'if (.total // 0) >= 1 and (.passes // 0) == (.total // 0) and (.failures // 1) == 0 then "true" else "false" end' "$programming_branchy_json")
    if [ "$programming_branchy_gate_nonempty" != "true" ] || [ "$programming_branchy_gate_all_rows" != "true" ]; then
      programming_branchy_gate_pass=false
    fi

    programming_auto_branchy_total=$(jq -r '.total // 0' "$programming_auto_branchy_json")
    programming_auto_branchy_passes=$(jq -r '.passes // 0' "$programming_auto_branchy_json")
    programming_auto_branchy_failures=$(jq -r '.failures // 1' "$programming_auto_branchy_json")
    programming_auto_branchy_gate_nonempty=false
    if num_ge "$programming_auto_branchy_total" "1"; then
      programming_auto_branchy_gate_nonempty=true
    fi
    programming_auto_branchy_gate_all_rows=$(jq -r 'if (.total // 0) >= 1 and (.passes // 0) == (.total // 0) and (.failures // 1) == 0 then "true" else "false" end' "$programming_auto_branchy_json")
    if [ "$programming_auto_branchy_gate_nonempty" != "true" ] || [ "$programming_auto_branchy_gate_all_rows" != "true" ]; then
      programming_auto_branchy_gate_pass=false
    fi

    programming_long_horizon_present_rows=$(jq -r '
      [
        .results[]? | (.task_id // "") |
        select(
          . == "until-complete-calc-phase2-followup" or
          . == "until-complete-calc-stopgo-phase3" or
          . == "until-complete-calc-phase3-followup" or
          . == "until-complete-calc-phase3-cross-session" or
          . == "until-complete-calc-phase2-cross-workspace"
        )
      ] | unique | join(",")
    ' "$programming_auto_branchy_json")
    programming_long_horizon_passing_rows=$(jq -r '
      [
        .results[]? |
        select(
          (
            (.task_id // "") == "until-complete-calc-phase2-followup" or
            (.task_id // "") == "until-complete-calc-stopgo-phase3" or
            (.task_id // "") == "until-complete-calc-phase3-followup" or
            (.task_id // "") == "until-complete-calc-phase3-cross-session" or
            (.task_id // "") == "until-complete-calc-phase2-cross-workspace"
          ) and
          (.status // "") == "pass" and
          ((.timed_out // 1) == 0) and
          ((.clean_verify_finish // 0) == 1)
        ) |
        (.task_id // "")
      ] | unique | join(",")
    ' "$programming_auto_branchy_json")
    programming_long_horizon_present_count=$(jq -r '
      [
        .results[]? | (.task_id // "") |
        select(
          . == "until-complete-calc-phase2-followup" or
          . == "until-complete-calc-stopgo-phase3" or
          . == "until-complete-calc-phase3-followup" or
          . == "until-complete-calc-phase3-cross-session" or
          . == "until-complete-calc-phase2-cross-workspace"
        )
      ] | unique | length
    ' "$programming_auto_branchy_json")
    programming_long_horizon_pass_count=$(jq -r '
      [
        .results[]? |
        select(
          (
            (.task_id // "") == "until-complete-calc-phase2-followup" or
            (.task_id // "") == "until-complete-calc-stopgo-phase3" or
            (.task_id // "") == "until-complete-calc-phase3-followup" or
            (.task_id // "") == "until-complete-calc-phase3-cross-session" or
            (.task_id // "") == "until-complete-calc-phase2-cross-workspace"
          ) and
          (.status // "") == "pass" and
          ((.timed_out // 1) == 0) and
          ((.clean_verify_finish // 0) == 1)
        ) |
        (.task_id // "")
      ] | unique | length
    ' "$programming_auto_branchy_json")
    programming_long_horizon_required_rows_present=false
    programming_long_horizon_required_rows_pass=false
    if num_ge "$programming_long_horizon_present_count" "$programming_long_horizon_expected_count"; then
      programming_long_horizon_required_rows_present=true
    fi
    if num_ge "$programming_long_horizon_pass_count" "$programming_long_horizon_expected_count"; then
      programming_long_horizon_required_rows_pass=true
    fi
    if [ "$programming_long_horizon_required_rows_present" != "true" ] || \
       [ "$programming_long_horizon_required_rows_pass" != "true" ]; then
      programming_long_horizon_gate_pass=false
    fi

    long_horizon_timeout_coverage_transfer_pass=$(transfer_json_pass "$long_horizon_timeout_coverage_transfer_json")
    long_horizon_timeout_coverage_transfer_risk=$(transfer_json_risk "$long_horizon_timeout_coverage_transfer_json")
    long_horizon_timeout_present_families=""
    long_horizon_timeout_passing_families=""
    if [ -f "$long_horizon_timeout_coverage_transfer_json" ]; then
      long_horizon_timeout_present_families="long-horizon-timeout-coverage"
    fi
    if [ "$long_horizon_timeout_coverage_transfer_pass" = "true" ]; then
      long_horizon_timeout_passing_families="long-horizon-timeout-coverage"
    fi
    long_horizon_timeout_present_count=$(printf '%s\n' "$long_horizon_timeout_present_families" | awk 'NF { count += 1 } END { print count + 0 }')
    long_horizon_timeout_pass_count=$(printf '%s\n' "$long_horizon_timeout_passing_families" | awk 'NF { count += 1 } END { print count + 0 }')
    long_horizon_timeout_required_present=false
    long_horizon_timeout_required_pass=false
    if num_ge "$long_horizon_timeout_present_count" "$long_horizon_timeout_expected_count"; then
      long_horizon_timeout_required_present=true
    fi
    if num_ge "$long_horizon_timeout_pass_count" "$long_horizon_timeout_expected_count"; then
      long_horizon_timeout_required_pass=true
    fi
    if [ "$long_horizon_timeout_required_present" != "true" ] || \
       [ "$long_horizon_timeout_required_pass" != "true" ]; then
      long_horizon_timeout_gate_pass=false
    fi

    document_transfer_pass=$(transfer_json_pass "$document_transfer_json")
    document_transfer_risk=$(transfer_json_risk "$document_transfer_json")
    document_present_families=""
    document_passing_families=""
    if [ -f "$document_transfer_json" ]; then
      document_present_families="document-v1"
    fi
    if [ "$document_transfer_pass" = "true" ]; then
      document_passing_families="document-v1"
    fi
    document_present_count=$(printf '%s\n' "$document_present_families" | awk 'NF { count += 1 } END { print count + 0 }')
    document_pass_count=$(printf '%s\n' "$document_passing_families" | awk 'NF { count += 1 } END { print count + 0 }')
    document_required_present=false
    document_required_pass=false
    if num_ge "$document_present_count" "$document_expected_count"; then
      document_required_present=true
    fi
    if num_ge "$document_pass_count" "$document_expected_count"; then
      document_required_pass=true
    fi
    if [ "$document_required_present" != "true" ] || \
       [ "$document_required_pass" != "true" ]; then
      document_gate_pass=false
    fi

    repo_runtime_web_triage_transfer_pass=$(transfer_json_pass "$repo_runtime_web_triage_transfer_json")
    repo_runtime_web_triage_transfer_risk=$(transfer_json_risk "$repo_runtime_web_triage_transfer_json")
    browser_image_run_investigation_transfer_pass=$(transfer_json_pass "$browser_image_run_investigation_transfer_json")
    browser_image_run_investigation_transfer_risk=$(transfer_json_risk "$browser_image_run_investigation_transfer_json")
    tool_failure_handoff_transfer_pass=$(transfer_json_pass "$tool_failure_handoff_transfer_json")
    tool_failure_handoff_transfer_risk=$(transfer_json_risk "$tool_failure_handoff_transfer_json")
    current_api_migration_transfer_pass=$(transfer_json_pass "$current_api_migration_transfer_json")
    current_api_migration_transfer_risk=$(transfer_json_risk "$current_api_migration_transfer_json")
    current_ops_guidance_transfer_pass=$(transfer_json_pass "$current_ops_guidance_transfer_json")
    current_ops_guidance_transfer_risk=$(transfer_json_risk "$current_ops_guidance_transfer_json")
    standards_grounded_answer_transfer_pass=$(transfer_json_pass "$standards_grounded_answer_transfer_json")
    standards_grounded_answer_transfer_risk=$(transfer_json_risk "$standards_grounded_answer_transfer_json")
    operator_decision_transfer_pass=$(transfer_json_pass "$operator_decision_transfer_json")
    operator_decision_transfer_risk=$(transfer_json_risk "$operator_decision_transfer_json")
    multi_artifact_judgment_transfer_pass=$(transfer_json_pass "$multi_artifact_judgment_transfer_json")
    multi_artifact_judgment_transfer_risk=$(transfer_json_risk "$multi_artifact_judgment_transfer_json")
    long_context_reassessment_transfer_pass=$(transfer_json_pass "$long_context_reassessment_transfer_json")
    long_context_reassessment_transfer_risk=$(transfer_json_risk "$long_context_reassessment_transfer_json")

    repo_runtime_web_triage_present=""
    browser_image_run_investigation_present=""
    tool_failure_handoff_present=""
    current_api_migration_present=""
    current_ops_guidance_present=""
    standards_grounded_answer_present=""
    operator_decision_present=""
    multi_artifact_judgment_present=""
    long_context_reassessment_present=""
    repo_runtime_web_triage_passing=""
    browser_image_run_investigation_passing=""
    tool_failure_handoff_passing=""
    current_api_migration_passing=""
    current_ops_guidance_passing=""
    standards_grounded_answer_passing=""
    operator_decision_passing=""
    multi_artifact_judgment_passing=""
    long_context_reassessment_passing=""

    if [ -f "$repo_runtime_web_triage_transfer_json" ]; then
      repo_runtime_web_triage_present="repo-runtime-web-triage"
    fi
    if [ -f "$browser_image_run_investigation_transfer_json" ]; then
      browser_image_run_investigation_present="browser-image-run-investigation"
    fi
    if [ -f "$tool_failure_handoff_transfer_json" ]; then
      tool_failure_handoff_present="tool-failure-handoff"
    fi
    if [ -f "$current_api_migration_transfer_json" ]; then
      current_api_migration_present="current-api-migration"
    fi
    if [ -f "$current_ops_guidance_transfer_json" ]; then
      current_ops_guidance_present="current-ops-guidance"
    fi
    if [ -f "$standards_grounded_answer_transfer_json" ]; then
      standards_grounded_answer_present="standards-grounded-answer"
    fi
    if [ -f "$operator_decision_transfer_json" ]; then
      operator_decision_present="operator-decision"
    fi
    if [ -f "$multi_artifact_judgment_transfer_json" ]; then
      multi_artifact_judgment_present="multi-artifact-judgment"
    fi
    if [ -f "$long_context_reassessment_transfer_json" ]; then
      long_context_reassessment_present="long-context-reassessment"
    fi

    if [ "$repo_runtime_web_triage_transfer_pass" = "true" ]; then
      repo_runtime_web_triage_passing="repo-runtime-web-triage"
    fi
    if [ "$browser_image_run_investigation_transfer_pass" = "true" ]; then
      browser_image_run_investigation_passing="browser-image-run-investigation"
    fi
    if [ "$tool_failure_handoff_transfer_pass" = "true" ]; then
      tool_failure_handoff_passing="tool-failure-handoff"
    fi
    if [ "$current_api_migration_transfer_pass" = "true" ]; then
      current_api_migration_passing="current-api-migration"
    fi
    if [ "$current_ops_guidance_transfer_pass" = "true" ]; then
      current_ops_guidance_passing="current-ops-guidance"
    fi
    if [ "$standards_grounded_answer_transfer_pass" = "true" ]; then
      standards_grounded_answer_passing="standards-grounded-answer"
    fi
    if [ "$operator_decision_transfer_pass" = "true" ]; then
      operator_decision_passing="operator-decision"
    fi
    if [ "$multi_artifact_judgment_transfer_pass" = "true" ]; then
      multi_artifact_judgment_passing="multi-artifact-judgment"
    fi
    if [ "$long_context_reassessment_transfer_pass" = "true" ]; then
      long_context_reassessment_passing="long-context-reassessment"
    fi

    multi_tool_present_families=$(printf '%s\n%s\n%s\n' \
      "$repo_runtime_web_triage_present" \
      "$browser_image_run_investigation_present" \
      "$tool_failure_handoff_present" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    multi_tool_passing_families=$(printf '%s\n%s\n%s\n' \
      "$repo_runtime_web_triage_passing" \
      "$browser_image_run_investigation_passing" \
      "$tool_failure_handoff_passing" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    freshness_present_families=$(printf '%s\n%s\n%s\n' \
      "$current_api_migration_present" \
      "$current_ops_guidance_present" \
      "$standards_grounded_answer_present" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    freshness_passing_families=$(printf '%s\n%s\n%s\n' \
      "$current_api_migration_passing" \
      "$current_ops_guidance_passing" \
      "$standards_grounded_answer_passing" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    operator_present_families=$(printf '%s\n%s\n%s\n' \
      "$operator_decision_present" \
      "$multi_artifact_judgment_present" \
      "$long_context_reassessment_present" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    operator_passing_families=$(printf '%s\n%s\n%s\n' \
      "$operator_decision_passing" \
      "$multi_artifact_judgment_passing" \
      "$long_context_reassessment_passing" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')

    multi_tool_present_count=$(printf '%s\n%s\n%s\n' \
      "$repo_runtime_web_triage_present" \
      "$browser_image_run_investigation_present" \
      "$tool_failure_handoff_present" | awk 'NF { count += 1 } END { print count + 0 }')
    multi_tool_pass_count=$(printf '%s\n%s\n%s\n' \
      "$repo_runtime_web_triage_passing" \
      "$browser_image_run_investigation_passing" \
      "$tool_failure_handoff_passing" | awk 'NF { count += 1 } END { print count + 0 }')
    freshness_present_count=$(printf '%s\n%s\n%s\n' \
      "$current_api_migration_present" \
      "$current_ops_guidance_present" \
      "$standards_grounded_answer_present" | awk 'NF { count += 1 } END { print count + 0 }')
    freshness_pass_count=$(printf '%s\n%s\n%s\n' \
      "$current_api_migration_passing" \
      "$current_ops_guidance_passing" \
      "$standards_grounded_answer_passing" | awk 'NF { count += 1 } END { print count + 0 }')
    operator_present_count=$(printf '%s\n%s\n%s\n' \
      "$operator_decision_present" \
      "$multi_artifact_judgment_present" \
      "$long_context_reassessment_present" | awk 'NF { count += 1 } END { print count + 0 }')
    operator_pass_count=$(printf '%s\n%s\n%s\n' \
      "$operator_decision_passing" \
      "$multi_artifact_judgment_passing" \
      "$long_context_reassessment_passing" | awk 'NF { count += 1 } END { print count + 0 }')

    multi_tool_required_present=false
    multi_tool_required_pass=false
    freshness_required_present=false
    freshness_required_pass=false
    operator_required_present=false
    operator_required_pass=false
    if num_ge "$multi_tool_present_count" "$multi_tool_expected_count"; then
      multi_tool_required_present=true
    fi
    if num_ge "$multi_tool_pass_count" "$multi_tool_expected_count"; then
      multi_tool_required_pass=true
    fi
    if num_ge "$freshness_present_count" "$freshness_expected_count"; then
      freshness_required_present=true
    fi
    if num_ge "$freshness_pass_count" "$freshness_expected_count"; then
      freshness_required_pass=true
    fi
    if num_ge "$operator_present_count" "$operator_expected_count"; then
      operator_required_present=true
    fi
    if num_ge "$operator_pass_count" "$operator_expected_count"; then
      operator_required_pass=true
    fi
    if [ "$multi_tool_required_present" != "true" ] || [ "$multi_tool_required_pass" != "true" ]; then
      multi_tool_gate_pass=false
    fi
    if [ "$freshness_required_present" != "true" ] || [ "$freshness_required_pass" != "true" ]; then
      freshness_gate_pass=false
    fi
    if [ "$operator_required_present" != "true" ] || [ "$operator_required_pass" != "true" ]; then
      operator_gate_pass=false
    fi

    remote_ops_transfer_pass=$(transfer_json_pass "$remote_ops_transfer_json")
    remote_ops_transfer_risk=$(transfer_json_risk "$remote_ops_transfer_json")
    remote_deploy_transfer_pass=$(transfer_json_pass "$remote_deploy_transfer_json")
    remote_deploy_transfer_risk=$(transfer_json_risk "$remote_deploy_transfer_json")
    remote_multi_host_transfer_pass=$(transfer_json_pass "$remote_multi_host_transfer_json")
    remote_multi_host_transfer_risk=$(transfer_json_risk "$remote_multi_host_transfer_json")
    remote_multi_host_rollout_transfer_pass=$(transfer_json_pass "$remote_multi_host_rollout_transfer_json")
    remote_multi_host_rollout_transfer_risk=$(transfer_json_risk "$remote_multi_host_rollout_transfer_json")
    remote_bastion_cutover_transfer_pass=$(transfer_json_pass "$remote_bastion_cutover_transfer_json")
    remote_bastion_cutover_transfer_risk=$(transfer_json_risk "$remote_bastion_cutover_transfer_json")
    remote_boundary_rollout_transfer_pass=$(transfer_json_pass "$remote_boundary_rollout_transfer_json")
    remote_boundary_rollout_transfer_risk=$(transfer_json_risk "$remote_boundary_rollout_transfer_json")
    remote_boundary_rollback_transfer_pass=$(transfer_json_pass "$remote_boundary_rollback_transfer_json")
    remote_boundary_rollback_transfer_risk=$(transfer_json_risk "$remote_boundary_rollback_transfer_json")
    remote_boundary_pack_transfer_pass=$(transfer_json_pass "$remote_boundary_pack_transfer_json")
    remote_boundary_pack_transfer_risk=$(transfer_json_risk "$remote_boundary_pack_transfer_json")
    remote_release_pack_transfer_pass=$(transfer_json_pass "$remote_release_pack_transfer_json")
    remote_release_pack_transfer_risk=$(transfer_json_risk "$remote_release_pack_transfer_json")
    gui_visual_transfer_pass=$(transfer_json_pass "$gui_visual_transfer_json")
    gui_visual_transfer_risk=$(transfer_json_risk "$gui_visual_transfer_json")
    gui_screenshot_layout_triage_transfer_pass=$(transfer_json_pass "$gui_screenshot_layout_triage_transfer_json")
    gui_screenshot_layout_triage_transfer_risk=$(transfer_json_risk "$gui_screenshot_layout_triage_transfer_json")
    gui_login_upload_download_transfer_pass=$(transfer_json_pass "$gui_login_upload_download_transfer_json")
    gui_login_upload_download_transfer_risk=$(transfer_json_risk "$gui_login_upload_download_transfer_json")
    gui_state_recovery_pack_transfer_pass=$(transfer_json_pass "$gui_state_recovery_pack_transfer_json")
    gui_state_recovery_pack_transfer_risk=$(transfer_json_risk "$gui_state_recovery_pack_transfer_json")
    dashboard_chart_read_transfer_pass=$(transfer_json_pass "$dashboard_chart_read_transfer_json")
    dashboard_chart_read_transfer_risk=$(transfer_json_risk "$dashboard_chart_read_transfer_json")
    terminal_screenshot_debug_transfer_pass=$(transfer_json_pass "$terminal_screenshot_debug_transfer_json")
    terminal_screenshot_debug_transfer_risk=$(transfer_json_risk "$terminal_screenshot_debug_transfer_json")
    before_after_ui_delta_transfer_pass=$(transfer_json_pass "$before_after_ui_delta_transfer_json")
    before_after_ui_delta_transfer_risk=$(transfer_json_risk "$before_after_ui_delta_transfer_json")
    terminal_state_recovery_read_transfer_pass=$(transfer_json_pass "$terminal_state_recovery_read_transfer_json")
    terminal_state_recovery_read_transfer_risk=$(transfer_json_risk "$terminal_state_recovery_read_transfer_json")
    diagram_annotation_read_transfer_pass=$(transfer_json_pass "$diagram_annotation_read_transfer_json")
    diagram_annotation_read_transfer_risk=$(transfer_json_risk "$diagram_annotation_read_transfer_json")

    remote_present_families=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
      "$( [ -f "$remote_ops_transfer_json" ] && printf '%s' 'remote-ops' )" \
      "$( [ -f "$remote_deploy_transfer_json" ] && printf '%s' 'remote-deploy' )" \
      "$( [ -f "$remote_multi_host_transfer_json" ] && printf '%s' 'remote-multi-host' )" \
      "$( [ -f "$remote_multi_host_rollout_transfer_json" ] && printf '%s' 'remote-multi-host-rollout' )" \
      "$( [ -f "$remote_bastion_cutover_transfer_json" ] && printf '%s' 'remote-bastion-cutover' )" \
      "$( [ -f "$remote_boundary_rollout_transfer_json" ] && printf '%s' 'remote-boundary-rollout' )" \
      "$( [ -f "$remote_boundary_rollback_transfer_json" ] && printf '%s' 'remote-boundary-rollback' )" \
      "$( [ -f "$remote_boundary_pack_transfer_json" ] && printf '%s' 'remote-boundary-pack' )" \
      "$( [ -f "$remote_release_pack_transfer_json" ] && printf '%s' 'remote-release-pack' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    remote_passing_families=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
      "$( [ "$remote_ops_transfer_pass" = "true" ] && printf '%s' 'remote-ops' )" \
      "$( [ "$remote_deploy_transfer_pass" = "true" ] && printf '%s' 'remote-deploy' )" \
      "$( [ "$remote_multi_host_transfer_pass" = "true" ] && printf '%s' 'remote-multi-host' )" \
      "$( [ "$remote_multi_host_rollout_transfer_pass" = "true" ] && printf '%s' 'remote-multi-host-rollout' )" \
      "$( [ "$remote_bastion_cutover_transfer_pass" = "true" ] && printf '%s' 'remote-bastion-cutover' )" \
      "$( [ "$remote_boundary_rollout_transfer_pass" = "true" ] && printf '%s' 'remote-boundary-rollout' )" \
      "$( [ "$remote_boundary_rollback_transfer_pass" = "true" ] && printf '%s' 'remote-boundary-rollback' )" \
      "$( [ "$remote_boundary_pack_transfer_pass" = "true" ] && printf '%s' 'remote-boundary-pack' )" \
      "$( [ "$remote_release_pack_transfer_pass" = "true" ] && printf '%s' 'remote-release-pack' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    gui_release_present_families=$(printf '%s\n%s\n%s\n%s\n' \
      "$( [ -f "$gui_visual_transfer_json" ] && printf '%s' 'gui-visual' )" \
      "$( [ -f "$gui_screenshot_layout_triage_transfer_json" ] && printf '%s' 'gui-screenshot-layout-triage' )" \
      "$( [ -f "$gui_login_upload_download_transfer_json" ] && printf '%s' 'gui-login-upload-download' )" \
      "$( [ -f "$gui_state_recovery_pack_transfer_json" ] && printf '%s' 'gui-state-recovery-pack' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    gui_release_passing_families=$(printf '%s\n%s\n%s\n%s\n' \
      "$( [ "$gui_visual_transfer_pass" = "true" ] && printf '%s' 'gui-visual' )" \
      "$( [ "$gui_screenshot_layout_triage_transfer_pass" = "true" ] && printf '%s' 'gui-screenshot-layout-triage' )" \
      "$( [ "$gui_login_upload_download_transfer_pass" = "true" ] && printf '%s' 'gui-login-upload-download' )" \
      "$( [ "$gui_state_recovery_pack_transfer_pass" = "true" ] && printf '%s' 'gui-state-recovery-pack' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    visual_present_families=$(printf '%s\n%s\n%s\n%s\n%s\n' \
      "$( [ -f "$dashboard_chart_read_transfer_json" ] && printf '%s' 'dashboard-chart-read' )" \
      "$( [ -f "$terminal_screenshot_debug_transfer_json" ] && printf '%s' 'terminal-screenshot-debug' )" \
      "$( [ -f "$before_after_ui_delta_transfer_json" ] && printf '%s' 'before-after-ui-delta' )" \
      "$( [ -f "$terminal_state_recovery_read_transfer_json" ] && printf '%s' 'terminal-state-recovery-read' )" \
      "$( [ -f "$diagram_annotation_read_transfer_json" ] && printf '%s' 'diagram-annotation-read' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')
    visual_passing_families=$(printf '%s\n%s\n%s\n%s\n%s\n' \
      "$( [ "$dashboard_chart_read_transfer_pass" = "true" ] && printf '%s' 'dashboard-chart-read' )" \
      "$( [ "$terminal_screenshot_debug_transfer_pass" = "true" ] && printf '%s' 'terminal-screenshot-debug' )" \
      "$( [ "$before_after_ui_delta_transfer_pass" = "true" ] && printf '%s' 'before-after-ui-delta' )" \
      "$( [ "$terminal_state_recovery_read_transfer_pass" = "true" ] && printf '%s' 'terminal-state-recovery-read' )" \
      "$( [ "$diagram_annotation_read_transfer_pass" = "true" ] && printf '%s' 'diagram-annotation-read' )" | awk 'NF { if (out != "") out = out ","; out = out $0 } END { print out }')

    remote_present_count=$(printf '%s\n' "$remote_present_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')
    remote_pass_count=$(printf '%s\n' "$remote_passing_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')
    gui_release_present_count=$(printf '%s\n' "$gui_release_present_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')
    gui_release_pass_count=$(printf '%s\n' "$gui_release_passing_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')
    visual_present_count=$(printf '%s\n' "$visual_present_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')
    visual_pass_count=$(printf '%s\n' "$visual_passing_families" | awk -F',' 'NF && $1 != "" { print NF + 0; next } { print 0 }')

    remote_required_present=false
    remote_required_pass=false
    gui_release_required_present=false
    gui_release_required_pass=false
    visual_required_present=false
    visual_required_pass=false
    if num_ge "$remote_present_count" "$remote_expected_count"; then
      remote_required_present=true
    fi
    if num_ge "$remote_pass_count" "$remote_expected_count"; then
      remote_required_pass=true
    fi
    if num_ge "$gui_release_present_count" "$gui_release_expected_count"; then
      gui_release_required_present=true
    fi
    if num_ge "$gui_release_pass_count" "$gui_release_expected_count"; then
      gui_release_required_pass=true
    fi
    if num_ge "$visual_present_count" "$visual_expected_count"; then
      visual_required_present=true
    fi
    if num_ge "$visual_pass_count" "$visual_expected_count"; then
      visual_required_pass=true
    fi
    if [ "$remote_required_present" != "true" ] || [ "$remote_required_pass" != "true" ]; then
      remote_gate_pass=false
    fi
    if [ "$gui_release_required_present" != "true" ] || [ "$gui_release_required_pass" != "true" ]; then
      gui_release_gate_pass=false
    fi
    if [ "$visual_required_present" != "true" ] || [ "$visual_required_pass" != "true" ]; then
      visual_gate_pass=false
    fi
  fi

  if [ "$gate_battery_overall" != "true" ] || \
     [ "$gate_holdout_overall" != "true" ] || \
     [ "$gate_holdout_adversarial" != "true" ] || \
     [ "$gate_holdout_ambiguity" != "true" ] || \
     [ "$gate_holdout_cross_domain" != "true" ] || \
     [ "$gate_holdout_recovery" != "true" ] || \
     [ "$gate_fail_open" != "true" ] || \
     [ "$gate_contradiction" != "true" ] || \
     [ "$gate_holdout_drop" != "true" ] || \
     [ "$gate_done_counts" != "true" ] || \
     [ "$mixed_transfer_pass" != "true" ] || \
     [ "$compact_transfer_pass" != "true" ] || \
     [ "$rich_transfer_pass" != "true" ] || \
     [ "$freeform_transfer_pass" != "true" ] || \
     [ "$programming_gate_pass" != "true" ] || \
     [ "$programming_branchy_gate_pass" != "true" ] || \
     [ "$programming_auto_branchy_gate_pass" != "true" ] || \
     [ "$programming_long_horizon_gate_pass" != "true" ] || \
     [ "$long_horizon_timeout_gate_pass" != "true" ] || \
     [ "$document_gate_pass" != "true" ] || \
     [ "$multi_tool_gate_pass" != "true" ] || \
     [ "$freshness_gate_pass" != "true" ] || \
     [ "$operator_gate_pass" != "true" ] || \
     [ "$remote_gate_pass" != "true" ] || \
     [ "$gui_release_gate_pass" != "true" ] || \
     [ "$visual_gate_pass" != "true" ]; then
    intelligence_pass=false
  fi
fi

gui_result_path="$gui_result"
gui_report_path=""
gui_success=false
gui_pass=true
interactive_gui_result_path="$interactive_gui_result"
interactive_gui_report_path=""
interactive_gui_success=false
interactive_gui_pass=true

if [ "$gui_enabled" = "true" ]; then
  if [ -z "$gui_result_path" ]; then
    gui_label="${label}-gui-${gui_profile}"
    gui_paths=$(run_gui_and_extract_paths "$gui_label" "$gui_profile")
    gui_status=$(printf '%s\n' "$gui_paths" | sed -n '1p')
    gui_result_path=$(printf '%s\n' "$gui_paths" | sed -n '2p')
    gui_report_path=$(printf '%s\n' "$gui_paths" | sed -n '3p')
    if [ -z "$gui_result_path" ]; then
      for candidate in "$OUT_DIR/${gui_label}-gui-result.json" "$OUT_DIR/${gui_label}-gui-firefox-result.json"; do
        if [ -f "$candidate" ]; then
          gui_result_path=$candidate
          break
        fi
      done
    fi
    if [ -z "$gui_report_path" ]; then
      for candidate in "$OUT_DIR/${gui_label}-gui-report.md" "$OUT_DIR/${gui_label}-gui-firefox-report.md"; do
        if [ -f "$candidate" ]; then
          gui_report_path=$candidate
          break
        fi
      done
    fi
    if [ "$gui_status" -ne 0 ] && [ -z "$gui_result_path" ]; then
      gui_pass=false
    fi
  fi

  if [ -n "$gui_result_path" ] && [ -f "$gui_result_path" ]; then
    gui_success=$(jq -r 'if .success == true then "true" else "false" end' "$gui_result_path")
    if [ "$gui_success" != "true" ]; then
      gui_pass=false
    fi
  else
    gui_pass=false
  fi
fi

if [ "$interactive_intelligence_enabled" = "true" ]; then
  if [ -z "$interactive_gui_result_path" ]; then
    interactive_label="${label}-interactive-${interactive_gui_profile}"
    interactive_paths=$(run_gui_and_extract_paths "$interactive_label" "$interactive_gui_profile")
    interactive_status=$(printf '%s\n' "$interactive_paths" | sed -n '1p')
    interactive_gui_result_path=$(printf '%s\n' "$interactive_paths" | sed -n '2p')
    interactive_gui_report_path=$(printf '%s\n' "$interactive_paths" | sed -n '3p')
    if [ -z "$interactive_gui_result_path" ]; then
      for candidate in "$OUT_DIR/${interactive_label}-gui-result.json" "$OUT_DIR/${interactive_label}-gui-firefox-result.json"; do
        if [ -f "$candidate" ]; then
          interactive_gui_result_path=$candidate
          break
        fi
      done
    fi
    if [ -z "$interactive_gui_report_path" ]; then
      for candidate in "$OUT_DIR/${interactive_label}-gui-report.md" "$OUT_DIR/${interactive_label}-gui-firefox-report.md"; do
        if [ -f "$candidate" ]; then
          interactive_gui_report_path=$candidate
          break
        fi
      done
    fi
    if [ "$interactive_status" -ne 0 ] && [ -z "$interactive_gui_result_path" ]; then
      interactive_gui_pass=false
    fi
  fi

  if [ -n "$interactive_gui_result_path" ] && [ -f "$interactive_gui_result_path" ]; then
    interactive_gui_success=$(jq -r 'if .success == true then "true" else "false" end' "$interactive_gui_result_path")
    if [ "$interactive_gui_success" != "true" ]; then
      interactive_gui_pass=false
    fi
  else
    interactive_gui_pass=false
  fi
fi

overall_pass=true
if [ "$interactive_intelligence_enabled" = "true" ] && [ "$interactive_gui_pass" != "true" ]; then
  intelligence_pass=false
fi
if [ "$intelligence_pass" != "true" ] || [ "$gui_pass" != "true" ]; then
  overall_pass=false
fi

gate_json="$OUT_DIR/$label-release-gate.json"
gate_report="$OUT_DIR/$label-release-gate.md"
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg label "$label" \
  --arg generated_at "$generated_at" \
  --arg battery_summary "$battery_summary" \
  --arg holdout_summary "$holdout_summary" \
  --arg battery_file "$battery_file" \
  --arg holdout_file "$holdout_file" \
  --arg mixed_battery_file "$mixed_battery_file" \
  --arg mixed_holdout_file "$mixed_holdout_file" \
  --arg mixed_battery_summary "$mixed_battery_summary" \
  --arg mixed_holdout_summary "$mixed_holdout_summary" \
  --arg mixed_transfer_json "$mixed_transfer_json" \
  --arg mixed_transfer_report "$mixed_transfer_report" \
  --arg compact_battery_file "$compact_battery_file" \
  --arg compact_holdout_file "$compact_holdout_file" \
  --arg compact_battery_summary "$compact_battery_summary" \
  --arg compact_holdout_summary "$compact_holdout_summary" \
  --arg compact_transfer_json "$compact_transfer_json" \
  --arg compact_transfer_report "$compact_transfer_report" \
  --arg rich_battery_file "$rich_battery_file" \
  --arg rich_holdout_file "$rich_holdout_file" \
  --arg rich_battery_summary "$rich_battery_summary" \
  --arg rich_holdout_summary "$rich_holdout_summary" \
  --arg rich_transfer_json "$rich_transfer_json" \
  --arg rich_transfer_report "$rich_transfer_report" \
  --arg freeform_battery_file "$freeform_battery_file" \
  --arg freeform_holdout_file "$freeform_holdout_file" \
  --arg freeform_battery_summary "$freeform_battery_summary" \
  --arg freeform_holdout_summary "$freeform_holdout_summary" \
  --arg freeform_transfer_json "$freeform_transfer_json" \
  --arg freeform_transfer_report "$freeform_transfer_report" \
  --arg programming_summary_json "$programming_summary_json" \
  --arg programming_summary_report "$programming_summary_report" \
  --arg programming_branchy_json "$programming_branchy_json" \
  --arg programming_branchy_report "$programming_branchy_report" \
  --arg programming_auto_branchy_json "$programming_auto_branchy_json" \
  --arg programming_auto_branchy_report "$programming_auto_branchy_report" \
  --arg battery_overall "$battery_overall" \
  --arg battery_fail_open "$battery_fail_open" \
  --arg battery_contradiction "$battery_contradiction" \
  --arg battery_done "$battery_done" \
  --arg holdout_overall "$holdout_overall" \
  --arg holdout_fail_open "$holdout_fail_open" \
  --arg holdout_contradiction "$holdout_contradiction" \
  --arg holdout_adversarial "$holdout_adversarial" \
  --arg holdout_ambiguity "$holdout_ambiguity" \
  --arg holdout_cross_domain "$holdout_cross_domain" \
  --arg holdout_recovery "$holdout_recovery" \
  --arg holdout_done "$holdout_done" \
  --arg mixed_transfer_risk "$mixed_transfer_risk" \
  --arg mixed_improved_axes "$mixed_improved_axes" \
  --arg mixed_stable_axes "$mixed_stable_axes" \
  --arg mixed_coverage_axes "$mixed_coverage_axes" \
  --arg compact_transfer_risk "$compact_transfer_risk" \
  --arg compact_battery_exact_contract "$compact_battery_exact_contract" \
  --arg compact_battery_required_ratio "$compact_battery_required_ratio" \
  --arg compact_battery_owner_window "$compact_battery_owner_window" \
  --arg compact_holdout_exact_contract "$compact_holdout_exact_contract" \
  --arg compact_holdout_required_ratio "$compact_holdout_required_ratio" \
  --arg compact_holdout_owner_window "$compact_holdout_owner_window" \
  --arg rich_transfer_risk "$rich_transfer_risk" \
  --arg rich_battery_exact_contract "$rich_battery_exact_contract" \
  --arg rich_battery_required_ratio "$rich_battery_required_ratio" \
  --arg rich_battery_core_labels "$rich_battery_core_labels" \
  --arg rich_holdout_exact_contract "$rich_holdout_exact_contract" \
  --arg rich_holdout_required_ratio "$rich_holdout_required_ratio" \
  --arg rich_holdout_core_labels "$rich_holdout_core_labels" \
  --arg freeform_transfer_risk "$freeform_transfer_risk" \
  --arg freeform_battery_freeform_rate "$freeform_battery_freeform_rate" \
  --arg freeform_battery_uncertainty_rate "$freeform_battery_uncertainty_rate" \
  --arg freeform_battery_reversal_rate "$freeform_battery_reversal_rate" \
  --arg freeform_battery_required_ratio "$freeform_battery_required_ratio" \
  --arg freeform_holdout_freeform_rate "$freeform_holdout_freeform_rate" \
  --arg freeform_holdout_uncertainty_rate "$freeform_holdout_uncertainty_rate" \
  --arg freeform_holdout_reversal_rate "$freeform_holdout_reversal_rate" \
  --arg freeform_holdout_required_ratio "$freeform_holdout_required_ratio" \
  --arg programming_total "$programming_total" \
  --arg programming_passes "$programming_passes" \
  --arg programming_failures "$programming_failures" \
  --arg programming_branchy_total "$programming_branchy_total" \
  --arg programming_branchy_passes "$programming_branchy_passes" \
  --arg programming_branchy_failures "$programming_branchy_failures" \
  --arg programming_auto_branchy_total "$programming_auto_branchy_total" \
  --arg programming_auto_branchy_passes "$programming_auto_branchy_passes" \
  --arg programming_auto_branchy_failures "$programming_auto_branchy_failures" \
  --arg programming_long_horizon_required_rows "$programming_long_horizon_required_rows" \
  --arg programming_long_horizon_present_rows "$programming_long_horizon_present_rows" \
  --arg programming_long_horizon_passing_rows "$programming_long_horizon_passing_rows" \
  --arg programming_long_horizon_expected_count "$programming_long_horizon_expected_count" \
  --arg programming_long_horizon_present_count "$programming_long_horizon_present_count" \
  --arg programming_long_horizon_pass_count "$programming_long_horizon_pass_count" \
  --arg long_horizon_timeout_required_families "$long_horizon_timeout_required_families" \
  --arg long_horizon_timeout_present_families "$long_horizon_timeout_present_families" \
  --arg long_horizon_timeout_passing_families "$long_horizon_timeout_passing_families" \
  --arg long_horizon_timeout_expected_count "$long_horizon_timeout_expected_count" \
  --arg long_horizon_timeout_present_count "$long_horizon_timeout_present_count" \
  --arg long_horizon_timeout_pass_count "$long_horizon_timeout_pass_count" \
  --arg long_horizon_timeout_coverage_transfer_json "$long_horizon_timeout_coverage_transfer_json" \
  --arg long_horizon_timeout_coverage_transfer_report "$long_horizon_timeout_coverage_transfer_report" \
  --arg long_horizon_timeout_coverage_transfer_risk "$long_horizon_timeout_coverage_transfer_risk" \
  --arg document_required_families "$document_required_families" \
  --arg document_present_families "$document_present_families" \
  --arg document_passing_families "$document_passing_families" \
  --arg document_expected_count "$document_expected_count" \
  --arg document_present_count "$document_present_count" \
  --arg document_pass_count "$document_pass_count" \
  --arg document_transfer_json "$document_transfer_json" \
  --arg document_transfer_report "$document_transfer_report" \
  --arg document_transfer_risk "$document_transfer_risk" \
  --arg remote_required_families "$remote_required_families" \
  --arg remote_present_families "$remote_present_families" \
  --arg remote_passing_families "$remote_passing_families" \
  --arg remote_expected_count "$remote_expected_count" \
  --arg remote_present_count "$remote_present_count" \
  --arg remote_pass_count "$remote_pass_count" \
  --arg remote_ops_transfer_json "$remote_ops_transfer_json" \
  --arg remote_ops_transfer_report "$remote_ops_transfer_report" \
  --arg remote_ops_transfer_risk "$remote_ops_transfer_risk" \
  --arg remote_deploy_transfer_json "$remote_deploy_transfer_json" \
  --arg remote_deploy_transfer_report "$remote_deploy_transfer_report" \
  --arg remote_deploy_transfer_risk "$remote_deploy_transfer_risk" \
  --arg remote_multi_host_transfer_json "$remote_multi_host_transfer_json" \
  --arg remote_multi_host_transfer_report "$remote_multi_host_transfer_report" \
  --arg remote_multi_host_transfer_risk "$remote_multi_host_transfer_risk" \
  --arg remote_multi_host_rollout_transfer_json "$remote_multi_host_rollout_transfer_json" \
  --arg remote_multi_host_rollout_transfer_report "$remote_multi_host_rollout_transfer_report" \
  --arg remote_multi_host_rollout_transfer_risk "$remote_multi_host_rollout_transfer_risk" \
  --arg remote_bastion_cutover_transfer_json "$remote_bastion_cutover_transfer_json" \
  --arg remote_bastion_cutover_transfer_report "$remote_bastion_cutover_transfer_report" \
  --arg remote_bastion_cutover_transfer_risk "$remote_bastion_cutover_transfer_risk" \
  --arg remote_boundary_rollout_transfer_json "$remote_boundary_rollout_transfer_json" \
  --arg remote_boundary_rollout_transfer_report "$remote_boundary_rollout_transfer_report" \
  --arg remote_boundary_rollout_transfer_risk "$remote_boundary_rollout_transfer_risk" \
  --arg remote_boundary_rollback_transfer_json "$remote_boundary_rollback_transfer_json" \
  --arg remote_boundary_rollback_transfer_report "$remote_boundary_rollback_transfer_report" \
  --arg remote_boundary_rollback_transfer_risk "$remote_boundary_rollback_transfer_risk" \
  --arg remote_boundary_pack_transfer_json "$remote_boundary_pack_transfer_json" \
  --arg remote_boundary_pack_transfer_report "$remote_boundary_pack_transfer_report" \
  --arg remote_boundary_pack_transfer_risk "$remote_boundary_pack_transfer_risk" \
  --arg remote_release_pack_transfer_json "$remote_release_pack_transfer_json" \
  --arg remote_release_pack_transfer_report "$remote_release_pack_transfer_report" \
  --arg remote_release_pack_transfer_risk "$remote_release_pack_transfer_risk" \
  --arg gui_release_required_families "$gui_release_required_families" \
  --arg gui_release_present_families "$gui_release_present_families" \
  --arg gui_release_passing_families "$gui_release_passing_families" \
  --arg gui_release_expected_count "$gui_release_expected_count" \
  --arg gui_release_present_count "$gui_release_present_count" \
  --arg gui_release_pass_count "$gui_release_pass_count" \
  --arg gui_visual_transfer_json "$gui_visual_transfer_json" \
  --arg gui_visual_transfer_report "$gui_visual_transfer_report" \
  --arg gui_visual_transfer_risk "$gui_visual_transfer_risk" \
  --arg gui_screenshot_layout_triage_transfer_json "$gui_screenshot_layout_triage_transfer_json" \
  --arg gui_screenshot_layout_triage_transfer_report "$gui_screenshot_layout_triage_transfer_report" \
  --arg gui_screenshot_layout_triage_transfer_risk "$gui_screenshot_layout_triage_transfer_risk" \
  --arg gui_login_upload_download_transfer_json "$gui_login_upload_download_transfer_json" \
  --arg gui_login_upload_download_transfer_report "$gui_login_upload_download_transfer_report" \
  --arg gui_login_upload_download_transfer_risk "$gui_login_upload_download_transfer_risk" \
  --arg gui_state_recovery_pack_transfer_json "$gui_state_recovery_pack_transfer_json" \
  --arg gui_state_recovery_pack_transfer_report "$gui_state_recovery_pack_transfer_report" \
  --arg gui_state_recovery_pack_transfer_risk "$gui_state_recovery_pack_transfer_risk" \
  --arg visual_required_families "$visual_required_families" \
  --arg visual_present_families "$visual_present_families" \
  --arg visual_passing_families "$visual_passing_families" \
  --arg visual_expected_count "$visual_expected_count" \
  --arg visual_present_count "$visual_present_count" \
  --arg visual_pass_count "$visual_pass_count" \
  --arg dashboard_chart_read_transfer_json "$dashboard_chart_read_transfer_json" \
  --arg dashboard_chart_read_transfer_report "$dashboard_chart_read_transfer_report" \
  --arg dashboard_chart_read_transfer_risk "$dashboard_chart_read_transfer_risk" \
  --arg terminal_screenshot_debug_transfer_json "$terminal_screenshot_debug_transfer_json" \
  --arg terminal_screenshot_debug_transfer_report "$terminal_screenshot_debug_transfer_report" \
  --arg terminal_screenshot_debug_transfer_risk "$terminal_screenshot_debug_transfer_risk" \
  --arg before_after_ui_delta_transfer_json "$before_after_ui_delta_transfer_json" \
  --arg before_after_ui_delta_transfer_report "$before_after_ui_delta_transfer_report" \
  --arg before_after_ui_delta_transfer_risk "$before_after_ui_delta_transfer_risk" \
  --arg terminal_state_recovery_read_transfer_json "$terminal_state_recovery_read_transfer_json" \
  --arg terminal_state_recovery_read_transfer_report "$terminal_state_recovery_read_transfer_report" \
  --arg terminal_state_recovery_read_transfer_risk "$terminal_state_recovery_read_transfer_risk" \
  --arg diagram_annotation_read_transfer_json "$diagram_annotation_read_transfer_json" \
  --arg diagram_annotation_read_transfer_report "$diagram_annotation_read_transfer_report" \
  --arg diagram_annotation_read_transfer_risk "$diagram_annotation_read_transfer_risk" \
  --arg repo_runtime_web_triage_transfer_json "$repo_runtime_web_triage_transfer_json" \
  --arg repo_runtime_web_triage_transfer_report "$repo_runtime_web_triage_transfer_report" \
  --arg repo_runtime_web_triage_transfer_risk "$repo_runtime_web_triage_transfer_risk" \
  --arg browser_image_run_investigation_transfer_json "$browser_image_run_investigation_transfer_json" \
  --arg browser_image_run_investigation_transfer_report "$browser_image_run_investigation_transfer_report" \
  --arg browser_image_run_investigation_transfer_risk "$browser_image_run_investigation_transfer_risk" \
  --arg tool_failure_handoff_transfer_json "$tool_failure_handoff_transfer_json" \
  --arg tool_failure_handoff_transfer_report "$tool_failure_handoff_transfer_report" \
  --arg tool_failure_handoff_transfer_risk "$tool_failure_handoff_transfer_risk" \
  --arg current_api_migration_transfer_json "$current_api_migration_transfer_json" \
  --arg current_api_migration_transfer_report "$current_api_migration_transfer_report" \
  --arg current_api_migration_transfer_risk "$current_api_migration_transfer_risk" \
  --arg current_ops_guidance_transfer_json "$current_ops_guidance_transfer_json" \
  --arg current_ops_guidance_transfer_report "$current_ops_guidance_transfer_report" \
  --arg current_ops_guidance_transfer_risk "$current_ops_guidance_transfer_risk" \
  --arg standards_grounded_answer_transfer_json "$standards_grounded_answer_transfer_json" \
  --arg standards_grounded_answer_transfer_report "$standards_grounded_answer_transfer_report" \
  --arg standards_grounded_answer_transfer_risk "$standards_grounded_answer_transfer_risk" \
  --arg operator_decision_transfer_json "$operator_decision_transfer_json" \
  --arg operator_decision_transfer_report "$operator_decision_transfer_report" \
  --arg operator_decision_transfer_risk "$operator_decision_transfer_risk" \
  --arg multi_artifact_judgment_transfer_json "$multi_artifact_judgment_transfer_json" \
  --arg multi_artifact_judgment_transfer_report "$multi_artifact_judgment_transfer_report" \
  --arg multi_artifact_judgment_transfer_risk "$multi_artifact_judgment_transfer_risk" \
  --arg long_context_reassessment_transfer_json "$long_context_reassessment_transfer_json" \
  --arg long_context_reassessment_transfer_report "$long_context_reassessment_transfer_report" \
  --arg long_context_reassessment_transfer_risk "$long_context_reassessment_transfer_risk" \
  --arg multi_tool_required_families "$multi_tool_required_families" \
  --arg multi_tool_present_families "$multi_tool_present_families" \
  --arg multi_tool_passing_families "$multi_tool_passing_families" \
  --arg multi_tool_expected_count "$multi_tool_expected_count" \
  --arg multi_tool_present_count "$multi_tool_present_count" \
  --arg multi_tool_pass_count "$multi_tool_pass_count" \
  --arg freshness_required_families "$freshness_required_families" \
  --arg freshness_present_families "$freshness_present_families" \
  --arg freshness_passing_families "$freshness_passing_families" \
  --arg freshness_expected_count "$freshness_expected_count" \
  --arg freshness_present_count "$freshness_present_count" \
  --arg freshness_pass_count "$freshness_pass_count" \
  --arg operator_required_families "$operator_required_families" \
  --arg operator_present_families "$operator_present_families" \
  --arg operator_passing_families "$operator_passing_families" \
  --arg operator_expected_count "$operator_expected_count" \
  --arg operator_present_count "$operator_present_count" \
  --arg operator_pass_count "$operator_pass_count" \
  --arg gui_profile "$gui_profile" \
  --arg gui_result_path "$gui_result_path" \
  --arg gui_report_path "$gui_report_path" \
  --arg interactive_gui_profile "$interactive_gui_profile" \
  --arg interactive_gui_result_path "$interactive_gui_result_path" \
  --arg interactive_gui_report_path "$interactive_gui_report_path" \
  --argjson intelligence_enabled "$(to_json_bool "$intelligence_enabled")" \
  --argjson intelligence_pass "$(to_json_bool "$intelligence_pass")" \
  --argjson interactive_intelligence_enabled "$(to_json_bool "$interactive_intelligence_enabled")" \
  --argjson interactive_gui_pass "$(to_json_bool "$interactive_gui_pass")" \
  --argjson interactive_gui_success "$(to_json_bool "$interactive_gui_success")" \
  --argjson gate_battery_overall "$(to_json_bool "$gate_battery_overall")" \
  --argjson gate_holdout_overall "$(to_json_bool "$gate_holdout_overall")" \
  --argjson gate_holdout_adversarial "$(to_json_bool "$gate_holdout_adversarial")" \
  --argjson gate_holdout_ambiguity "$(to_json_bool "$gate_holdout_ambiguity")" \
  --argjson gate_holdout_cross_domain "$(to_json_bool "$gate_holdout_cross_domain")" \
  --argjson gate_holdout_recovery "$(to_json_bool "$gate_holdout_recovery")" \
  --argjson gate_fail_open "$(to_json_bool "$gate_fail_open")" \
  --argjson gate_contradiction "$(to_json_bool "$gate_contradiction")" \
  --argjson gate_holdout_drop "$(to_json_bool "$gate_holdout_drop")" \
  --argjson gate_done_counts "$(to_json_bool "$gate_done_counts")" \
  --argjson mixed_transfer_pass "$(to_json_bool "$mixed_transfer_pass")" \
  --argjson mixed_gate_fail_open "$(to_json_bool "$mixed_gate_fail_open")" \
  --argjson mixed_gate_contradiction "$(to_json_bool "$mixed_gate_contradiction")" \
  --argjson mixed_gate_holdout "$(to_json_bool "$mixed_gate_holdout")" \
  --argjson mixed_gate_improved_axes "$(to_json_bool "$mixed_gate_improved_axes")" \
  --argjson mixed_gate_coverage_axes "$(to_json_bool "$mixed_gate_coverage_axes")" \
  --argjson mixed_gate_saturation "$(to_json_bool "$mixed_gate_saturation")" \
  --argjson compact_transfer_pass "$(to_json_bool "$compact_transfer_pass")" \
  --argjson compact_gate_fail_open "$(to_json_bool "$compact_gate_fail_open")" \
  --argjson compact_gate_contradiction "$(to_json_bool "$compact_gate_contradiction")" \
  --argjson compact_gate_holdout "$(to_json_bool "$compact_gate_holdout")" \
  --argjson compact_gate_exact "$(to_json_bool "$compact_gate_exact")" \
  --argjson compact_gate_required "$(to_json_bool "$compact_gate_required")" \
  --argjson compact_gate_owner_window "$(to_json_bool "$compact_gate_owner_window")" \
  --argjson rich_transfer_pass "$(to_json_bool "$rich_transfer_pass")" \
  --argjson rich_gate_fail_open "$(to_json_bool "$rich_gate_fail_open")" \
  --argjson rich_gate_contradiction "$(to_json_bool "$rich_gate_contradiction")" \
  --argjson rich_gate_holdout "$(to_json_bool "$rich_gate_holdout")" \
  --argjson rich_gate_exact "$(to_json_bool "$rich_gate_exact")" \
  --argjson rich_gate_required "$(to_json_bool "$rich_gate_required")" \
  --argjson rich_gate_core_labels "$(to_json_bool "$rich_gate_core_labels")" \
  --argjson freeform_transfer_pass "$(to_json_bool "$freeform_transfer_pass")" \
  --argjson freeform_gate_fail_open "$(to_json_bool "$freeform_gate_fail_open")" \
  --argjson freeform_gate_contradiction "$(to_json_bool "$freeform_gate_contradiction")" \
  --argjson freeform_gate_holdout "$(to_json_bool "$freeform_gate_holdout")" \
  --argjson freeform_gate_freeform "$(to_json_bool "$freeform_gate_freeform")" \
  --argjson freeform_gate_uncertainty "$(to_json_bool "$freeform_gate_uncertainty")" \
  --argjson freeform_gate_reversal "$(to_json_bool "$freeform_gate_reversal")" \
  --argjson freeform_gate_required "$(to_json_bool "$freeform_gate_required")" \
  --argjson programming_enabled "$(to_json_bool "$programming_enabled")" \
  --argjson programming_gate_pass "$(to_json_bool "$programming_gate_pass")" \
  --argjson programming_gate_nonempty "$(to_json_bool "$programming_gate_nonempty")" \
  --argjson programming_gate_all_rows "$(to_json_bool "$programming_gate_all_rows")" \
  --argjson programming_branchy_gate_pass "$(to_json_bool "$programming_branchy_gate_pass")" \
  --argjson programming_branchy_gate_nonempty "$(to_json_bool "$programming_branchy_gate_nonempty")" \
  --argjson programming_branchy_gate_all_rows "$(to_json_bool "$programming_branchy_gate_all_rows")" \
  --argjson programming_auto_branchy_gate_pass "$(to_json_bool "$programming_auto_branchy_gate_pass")" \
  --argjson programming_auto_branchy_gate_nonempty "$(to_json_bool "$programming_auto_branchy_gate_nonempty")" \
  --argjson programming_auto_branchy_gate_all_rows "$(to_json_bool "$programming_auto_branchy_gate_all_rows")" \
  --argjson programming_long_horizon_gate_pass "$(to_json_bool "$programming_long_horizon_gate_pass")" \
  --argjson programming_long_horizon_required_rows_present "$(to_json_bool "$programming_long_horizon_required_rows_present")" \
  --argjson programming_long_horizon_required_rows_pass "$(to_json_bool "$programming_long_horizon_required_rows_pass")" \
  --argjson long_horizon_timeout_gate_pass "$(to_json_bool "$long_horizon_timeout_gate_pass")" \
  --argjson long_horizon_timeout_required_present "$(to_json_bool "$long_horizon_timeout_required_present")" \
  --argjson long_horizon_timeout_required_pass "$(to_json_bool "$long_horizon_timeout_required_pass")" \
  --argjson long_horizon_timeout_coverage_transfer_pass "$(to_json_bool "$long_horizon_timeout_coverage_transfer_pass")" \
  --argjson document_gate_pass "$(to_json_bool "$document_gate_pass")" \
  --argjson document_required_present "$(to_json_bool "$document_required_present")" \
  --argjson document_required_pass "$(to_json_bool "$document_required_pass")" \
  --argjson document_transfer_pass "$(to_json_bool "$document_transfer_pass")" \
  --argjson remote_gate_pass "$(to_json_bool "$remote_gate_pass")" \
  --argjson remote_required_present "$(to_json_bool "$remote_required_present")" \
  --argjson remote_required_pass "$(to_json_bool "$remote_required_pass")" \
  --argjson remote_ops_transfer_pass "$(to_json_bool "$remote_ops_transfer_pass")" \
  --argjson remote_deploy_transfer_pass "$(to_json_bool "$remote_deploy_transfer_pass")" \
  --argjson remote_multi_host_transfer_pass "$(to_json_bool "$remote_multi_host_transfer_pass")" \
  --argjson remote_multi_host_rollout_transfer_pass "$(to_json_bool "$remote_multi_host_rollout_transfer_pass")" \
  --argjson remote_bastion_cutover_transfer_pass "$(to_json_bool "$remote_bastion_cutover_transfer_pass")" \
  --argjson remote_boundary_rollout_transfer_pass "$(to_json_bool "$remote_boundary_rollout_transfer_pass")" \
  --argjson remote_boundary_rollback_transfer_pass "$(to_json_bool "$remote_boundary_rollback_transfer_pass")" \
  --argjson remote_boundary_pack_transfer_pass "$(to_json_bool "$remote_boundary_pack_transfer_pass")" \
  --argjson remote_release_pack_transfer_pass "$(to_json_bool "$remote_release_pack_transfer_pass")" \
  --argjson gui_release_gate_pass "$(to_json_bool "$gui_release_gate_pass")" \
  --argjson gui_release_required_present "$(to_json_bool "$gui_release_required_present")" \
  --argjson gui_release_required_pass "$(to_json_bool "$gui_release_required_pass")" \
  --argjson gui_visual_transfer_pass "$(to_json_bool "$gui_visual_transfer_pass")" \
  --argjson gui_screenshot_layout_triage_transfer_pass "$(to_json_bool "$gui_screenshot_layout_triage_transfer_pass")" \
  --argjson gui_login_upload_download_transfer_pass "$(to_json_bool "$gui_login_upload_download_transfer_pass")" \
  --argjson gui_state_recovery_pack_transfer_pass "$(to_json_bool "$gui_state_recovery_pack_transfer_pass")" \
  --argjson visual_gate_pass "$(to_json_bool "$visual_gate_pass")" \
  --argjson visual_required_present "$(to_json_bool "$visual_required_present")" \
  --argjson visual_required_pass "$(to_json_bool "$visual_required_pass")" \
  --argjson dashboard_chart_read_transfer_pass "$(to_json_bool "$dashboard_chart_read_transfer_pass")" \
  --argjson terminal_screenshot_debug_transfer_pass "$(to_json_bool "$terminal_screenshot_debug_transfer_pass")" \
  --argjson before_after_ui_delta_transfer_pass "$(to_json_bool "$before_after_ui_delta_transfer_pass")" \
  --argjson terminal_state_recovery_read_transfer_pass "$(to_json_bool "$terminal_state_recovery_read_transfer_pass")" \
  --argjson diagram_annotation_read_transfer_pass "$(to_json_bool "$diagram_annotation_read_transfer_pass")" \
  --argjson repo_runtime_web_triage_transfer_pass "$(to_json_bool "$repo_runtime_web_triage_transfer_pass")" \
  --argjson browser_image_run_investigation_transfer_pass "$(to_json_bool "$browser_image_run_investigation_transfer_pass")" \
  --argjson tool_failure_handoff_transfer_pass "$(to_json_bool "$tool_failure_handoff_transfer_pass")" \
  --argjson current_api_migration_transfer_pass "$(to_json_bool "$current_api_migration_transfer_pass")" \
  --argjson current_ops_guidance_transfer_pass "$(to_json_bool "$current_ops_guidance_transfer_pass")" \
  --argjson standards_grounded_answer_transfer_pass "$(to_json_bool "$standards_grounded_answer_transfer_pass")" \
  --argjson operator_decision_transfer_pass "$(to_json_bool "$operator_decision_transfer_pass")" \
  --argjson multi_artifact_judgment_transfer_pass "$(to_json_bool "$multi_artifact_judgment_transfer_pass")" \
  --argjson long_context_reassessment_transfer_pass "$(to_json_bool "$long_context_reassessment_transfer_pass")" \
  --argjson multi_tool_gate_pass "$(to_json_bool "$multi_tool_gate_pass")" \
  --argjson multi_tool_required_present "$(to_json_bool "$multi_tool_required_present")" \
  --argjson multi_tool_required_pass "$(to_json_bool "$multi_tool_required_pass")" \
  --argjson freshness_gate_pass "$(to_json_bool "$freshness_gate_pass")" \
  --argjson freshness_required_present "$(to_json_bool "$freshness_required_present")" \
  --argjson freshness_required_pass "$(to_json_bool "$freshness_required_pass")" \
  --argjson operator_gate_pass "$(to_json_bool "$operator_gate_pass")" \
  --argjson operator_required_present "$(to_json_bool "$operator_required_present")" \
  --argjson operator_required_pass "$(to_json_bool "$operator_required_pass")" \
  --argjson gui_enabled "$(to_json_bool "$gui_enabled")" \
  --argjson gui_pass "$(to_json_bool "$gui_pass")" \
  --argjson gui_success "$(to_json_bool "$gui_success")" \
  --argjson overall_pass "$(to_json_bool "$overall_pass")" \
  --arg min_battery_overall "$min_battery_overall" \
  --arg min_holdout_overall "$min_holdout_overall" \
  --arg min_holdout_adversarial "$min_holdout_adversarial" \
  --arg min_holdout_ambiguity "$min_holdout_ambiguity" \
  --arg min_holdout_cross_domain "$min_holdout_cross_domain" \
  --arg min_holdout_recovery "$min_holdout_recovery" \
  --arg max_fail_open_rate "$max_fail_open_rate" \
  --arg max_contradiction_rate "$max_contradiction_rate" \
  --arg max_holdout_overall_drop "$max_holdout_overall_drop" '
    def num(v): if (v | length) == 0 then null else (v | tonumber) end;
    def path_or_null(v): if (v | length) == 0 then null else v end;
    {
      label: $label,
      generated_at: $generated_at,
      intelligence: {
        enabled: $intelligence_enabled,
        pass: $intelligence_pass,
        battery_fixture: path_or_null($battery_file),
        holdout_fixture: path_or_null($holdout_file),
        battery_summary_path: path_or_null($battery_summary),
        holdout_summary_path: path_or_null($holdout_summary),
        thresholds: {
          min_battery_overall: ($min_battery_overall | tonumber),
          min_holdout_overall: ($min_holdout_overall | tonumber),
          min_holdout_adversarial: ($min_holdout_adversarial | tonumber),
          min_holdout_ambiguity: ($min_holdout_ambiguity | tonumber),
          min_holdout_cross_domain: ($min_holdout_cross_domain | tonumber),
          min_holdout_recovery: ($min_holdout_recovery | tonumber),
          max_fail_open_rate: ($max_fail_open_rate | tonumber),
          max_contradiction_rate: ($max_contradiction_rate | tonumber),
          max_holdout_overall_drop: ($max_holdout_overall_drop | tonumber)
        },
        metrics: {
          battery: {
            avg_overall: num($battery_overall),
            fail_open_rate: num($battery_fail_open),
            contradiction_rate: num($battery_contradiction),
            done: num($battery_done)
          },
          holdout: {
            avg_overall: num($holdout_overall),
            fail_open_rate: num($holdout_fail_open),
            contradiction_rate: num($holdout_contradiction),
            avg_adversarial: num($holdout_adversarial),
            avg_ambiguity: num($holdout_ambiguity),
            avg_cross_domain: num($holdout_cross_domain),
            avg_recovery: num($holdout_recovery),
            done: num($holdout_done)
          }
        },
        gates: {
          battery_overall_min: $gate_battery_overall,
          holdout_overall_min: $gate_holdout_overall,
          holdout_adversarial_min: $gate_holdout_adversarial,
          holdout_ambiguity_min: $gate_holdout_ambiguity,
          holdout_cross_domain_min: $gate_holdout_cross_domain,
          holdout_recovery_min: $gate_holdout_recovery,
          fail_open_rate_max: $gate_fail_open,
          contradiction_rate_max: $gate_contradiction,
          holdout_not_too_far_below_battery: $gate_holdout_drop,
          done_counts_present: $gate_done_counts
        },
        mixed_transfer: {
          battery_fixture: path_or_null($mixed_battery_file),
          holdout_fixture: path_or_null($mixed_holdout_file),
          battery_summary_path: path_or_null($mixed_battery_summary),
          holdout_summary_path: path_or_null($mixed_holdout_summary),
          transfer_json_path: path_or_null($mixed_transfer_json),
          transfer_report_path: path_or_null($mixed_transfer_report),
          pass: $mixed_transfer_pass,
          transfer_risk: path_or_null($mixed_transfer_risk),
          improved_axes_count: num($mixed_improved_axes),
          stable_excellence_axes_count: num($mixed_stable_axes),
          robustness_coverage_axes_count: num($mixed_coverage_axes),
          gates: {
            fail_open_non_increase: $mixed_gate_fail_open,
            contradiction_non_increase: $mixed_gate_contradiction,
            holdout_not_worse_overall: $mixed_gate_holdout,
            improved_axes_at_least_two: $mixed_gate_improved_axes,
            robustness_coverage_at_least_two: $mixed_gate_coverage_axes,
            no_saturation_risk: $mixed_gate_saturation
          }
        },
        compact_transfer: {
          battery_fixture: path_or_null($compact_battery_file),
          holdout_fixture: path_or_null($compact_holdout_file),
          battery_summary_path: path_or_null($compact_battery_summary),
          holdout_summary_path: path_or_null($compact_holdout_summary),
          transfer_json_path: path_or_null($compact_transfer_json),
          transfer_report_path: path_or_null($compact_transfer_report),
          pass: $compact_transfer_pass,
          transfer_risk: path_or_null($compact_transfer_risk),
          metrics: {
            battery: {
              exact_contract_rate: num($compact_battery_exact_contract),
              avg_required_ratio: num($compact_battery_required_ratio),
              owner_window_rate: num($compact_battery_owner_window)
            },
            holdout: {
              exact_contract_rate: num($compact_holdout_exact_contract),
              avg_required_ratio: num($compact_holdout_required_ratio),
              owner_window_rate: num($compact_holdout_owner_window)
            }
          },
          gates: {
            fail_open_non_increase: $compact_gate_fail_open,
            contradiction_non_increase: $compact_gate_contradiction,
            holdout_not_worse_overall: $compact_gate_holdout,
            exact_contract_full: $compact_gate_exact,
            required_ratio_full: $compact_gate_required,
            owner_window_full: $compact_gate_owner_window
          }
        },
        rich_thread_transfer: {
          battery_fixture: path_or_null($rich_battery_file),
          holdout_fixture: path_or_null($rich_holdout_file),
          battery_summary_path: path_or_null($rich_battery_summary),
          holdout_summary_path: path_or_null($rich_holdout_summary),
          transfer_json_path: path_or_null($rich_transfer_json),
          transfer_report_path: path_or_null($rich_transfer_report),
          pass: $rich_transfer_pass,
          transfer_risk: path_or_null($rich_transfer_risk),
          metrics: {
            battery: {
              exact_contract_rate: num($rich_battery_exact_contract),
              avg_required_ratio: num($rich_battery_required_ratio),
              core_labels_exact_once_rate: num($rich_battery_core_labels)
            },
            holdout: {
              exact_contract_rate: num($rich_holdout_exact_contract),
              avg_required_ratio: num($rich_holdout_required_ratio),
              core_labels_exact_once_rate: num($rich_holdout_core_labels)
            }
          },
          gates: {
            fail_open_non_increase: $rich_gate_fail_open,
            contradiction_non_increase: $rich_gate_contradiction,
            holdout_not_worse_overall: $rich_gate_holdout,
            exact_contract_full: $rich_gate_exact,
            required_ratio_full: $rich_gate_required,
            core_labels_full: $rich_gate_core_labels
          }
        },
        freeform_memo_transfer: {
          battery_fixture: path_or_null($freeform_battery_file),
          holdout_fixture: path_or_null($freeform_holdout_file),
          battery_summary_path: path_or_null($freeform_battery_summary),
          holdout_summary_path: path_or_null($freeform_holdout_summary),
          transfer_json_path: path_or_null($freeform_transfer_json),
          transfer_report_path: path_or_null($freeform_transfer_report),
          pass: $freeform_transfer_pass,
          transfer_risk: path_or_null($freeform_transfer_risk),
          metrics: {
            battery: {
              freeform_rate: num($freeform_battery_freeform_rate),
              uncertainty_rate: num($freeform_battery_uncertainty_rate),
              reversal_rate: num($freeform_battery_reversal_rate),
              avg_required_ratio: num($freeform_battery_required_ratio)
            },
            holdout: {
              freeform_rate: num($freeform_holdout_freeform_rate),
              uncertainty_rate: num($freeform_holdout_uncertainty_rate),
              reversal_rate: num($freeform_holdout_reversal_rate),
              avg_required_ratio: num($freeform_holdout_required_ratio)
            }
          },
          gates: {
            fail_open_non_increase: $freeform_gate_fail_open,
            contradiction_non_increase: $freeform_gate_contradiction,
            holdout_not_worse_overall: $freeform_gate_holdout,
            freeform_full: $freeform_gate_freeform,
            uncertainty_full: $freeform_gate_uncertainty,
            reversal_full: $freeform_gate_reversal,
            required_ratio_full: $freeform_gate_required
          }
        },
        programming_stalled_summary: {
          enabled: $programming_enabled,
          pass: $programming_gate_pass,
          summary_json_path: path_or_null($programming_summary_json),
          summary_report_path: path_or_null($programming_summary_report),
          metrics: {
            total: num($programming_total),
            passes: num($programming_passes),
            failures: num($programming_failures)
          },
          gates: {
            nonempty: $programming_gate_nonempty,
            all_rows_pass: $programming_gate_all_rows
          }
        },
        programming_branchy_slice: {
          enabled: $programming_enabled,
          pass: $programming_branchy_gate_pass,
          summary_json_path: path_or_null($programming_branchy_json),
          summary_report_path: path_or_null($programming_branchy_report),
          metrics: {
            total: num($programming_branchy_total),
            passes: num($programming_branchy_passes),
            failures: num($programming_branchy_failures)
          },
          gates: {
            nonempty: $programming_branchy_gate_nonempty,
            all_rows_pass: $programming_branchy_gate_all_rows
          }
        },
        programming_auto_branchy: {
          enabled: $programming_enabled,
          pass: $programming_auto_branchy_gate_pass,
          summary_json_path: path_or_null($programming_auto_branchy_json),
          summary_report_path: path_or_null($programming_auto_branchy_report),
          metrics: {
            total: num($programming_auto_branchy_total),
            passes: num($programming_auto_branchy_passes),
            failures: num($programming_auto_branchy_failures)
          },
          gates: {
            nonempty: $programming_auto_branchy_gate_nonempty,
            all_rows_pass: $programming_auto_branchy_gate_all_rows
          }
        },
        long_horizon_programming: {
          enabled: $programming_enabled,
          pass: $programming_long_horizon_gate_pass,
          source_summary_json_path: path_or_null($programming_auto_branchy_json),
          required_task_ids: ($programming_long_horizon_required_rows | split(",") | map(select(length > 0))),
          present_task_ids: ($programming_long_horizon_present_rows | split(",") | map(select(length > 0))),
          passing_task_ids: ($programming_long_horizon_passing_rows | split(",") | map(select(length > 0))),
          metrics: {
            expected_rows: num($programming_long_horizon_expected_count),
            present_rows: num($programming_long_horizon_present_count),
            passing_rows: num($programming_long_horizon_pass_count)
          },
          gates: {
            required_rows_present: $programming_long_horizon_required_rows_present,
            required_rows_pass: $programming_long_horizon_required_rows_pass
          }
        },
        long_horizon_timeout_coverage: {
          enabled: $programming_enabled,
          pass: $long_horizon_timeout_gate_pass,
          required_family_ids: ($long_horizon_timeout_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($long_horizon_timeout_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($long_horizon_timeout_passing_families | split(",") | map(select(length > 0))),
          transfer_json_path: path_or_null($long_horizon_timeout_coverage_transfer_json),
          transfer_report_path: path_or_null($long_horizon_timeout_coverage_transfer_report),
          transfer_risk: path_or_null($long_horizon_timeout_coverage_transfer_risk),
          metrics: {
            expected_families: num($long_horizon_timeout_expected_count),
            present_families: num($long_horizon_timeout_present_count),
            passing_families: num($long_horizon_timeout_pass_count)
          },
          gates: {
            required_transfer_present: $long_horizon_timeout_required_present,
            required_family_pass: $long_horizon_timeout_required_pass,
            transfer_gate_pass: $long_horizon_timeout_coverage_transfer_pass
          }
        },
        document_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $document_gate_pass,
          required_family_ids: ($document_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($document_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($document_passing_families | split(",") | map(select(length > 0))),
          transfer_json_path: path_or_null($document_transfer_json),
          transfer_report_path: path_or_null($document_transfer_report),
          transfer_risk: path_or_null($document_transfer_risk),
          metrics: {
            expected_families: num($document_expected_count),
            present_families: num($document_present_count),
            passing_families: num($document_pass_count)
          },
          gates: {
            required_transfer_present: $document_required_present,
            required_family_pass: $document_required_pass,
            transfer_gate_pass: $document_transfer_pass
          }
        },
        remote_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $remote_gate_pass,
          required_family_ids: ($remote_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($remote_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($remote_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            remote_ops: path_or_null($remote_ops_transfer_json),
            remote_deploy: path_or_null($remote_deploy_transfer_json),
            remote_multi_host: path_or_null($remote_multi_host_transfer_json),
            remote_multi_host_rollout: path_or_null($remote_multi_host_rollout_transfer_json),
            remote_bastion_cutover: path_or_null($remote_bastion_cutover_transfer_json),
            remote_boundary_rollout: path_or_null($remote_boundary_rollout_transfer_json),
            remote_boundary_rollback: path_or_null($remote_boundary_rollback_transfer_json),
            remote_boundary_pack: path_or_null($remote_boundary_pack_transfer_json),
            remote_release_pack: path_or_null($remote_release_pack_transfer_json)
          },
          transfer_report_paths: {
            remote_ops: path_or_null($remote_ops_transfer_report),
            remote_deploy: path_or_null($remote_deploy_transfer_report),
            remote_multi_host: path_or_null($remote_multi_host_transfer_report),
            remote_multi_host_rollout: path_or_null($remote_multi_host_rollout_transfer_report),
            remote_bastion_cutover: path_or_null($remote_bastion_cutover_transfer_report),
            remote_boundary_rollout: path_or_null($remote_boundary_rollout_transfer_report),
            remote_boundary_rollback: path_or_null($remote_boundary_rollback_transfer_report),
            remote_boundary_pack: path_or_null($remote_boundary_pack_transfer_report),
            remote_release_pack: path_or_null($remote_release_pack_transfer_report)
          },
          transfer_risks: {
            remote_ops: path_or_null($remote_ops_transfer_risk),
            remote_deploy: path_or_null($remote_deploy_transfer_risk),
            remote_multi_host: path_or_null($remote_multi_host_transfer_risk),
            remote_multi_host_rollout: path_or_null($remote_multi_host_rollout_transfer_risk),
            remote_bastion_cutover: path_or_null($remote_bastion_cutover_transfer_risk),
            remote_boundary_rollout: path_or_null($remote_boundary_rollout_transfer_risk),
            remote_boundary_rollback: path_or_null($remote_boundary_rollback_transfer_risk),
            remote_boundary_pack: path_or_null($remote_boundary_pack_transfer_risk),
            remote_release_pack: path_or_null($remote_release_pack_transfer_risk)
          },
          metrics: {
            expected_families: num($remote_expected_count),
            present_families: num($remote_present_count),
            passing_families: num($remote_pass_count)
          },
          gates: {
            required_transfers_present: $remote_required_present,
            required_families_pass: $remote_required_pass
          }
        },
        gui_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $gui_release_gate_pass,
          required_family_ids: ($gui_release_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($gui_release_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($gui_release_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            gui_visual: path_or_null($gui_visual_transfer_json),
            gui_screenshot_layout_triage: path_or_null($gui_screenshot_layout_triage_transfer_json),
            gui_login_upload_download: path_or_null($gui_login_upload_download_transfer_json),
            gui_state_recovery_pack: path_or_null($gui_state_recovery_pack_transfer_json)
          },
          transfer_report_paths: {
            gui_visual: path_or_null($gui_visual_transfer_report),
            gui_screenshot_layout_triage: path_or_null($gui_screenshot_layout_triage_transfer_report),
            gui_login_upload_download: path_or_null($gui_login_upload_download_transfer_report),
            gui_state_recovery_pack: path_or_null($gui_state_recovery_pack_transfer_report)
          },
          transfer_risks: {
            gui_visual: path_or_null($gui_visual_transfer_risk),
            gui_screenshot_layout_triage: path_or_null($gui_screenshot_layout_triage_transfer_risk),
            gui_login_upload_download: path_or_null($gui_login_upload_download_transfer_risk),
            gui_state_recovery_pack: path_or_null($gui_state_recovery_pack_transfer_risk)
          },
          metrics: {
            expected_families: num($gui_release_expected_count),
            present_families: num($gui_release_present_count),
            passing_families: num($gui_release_pass_count)
          },
          gates: {
            required_transfers_present: $gui_release_required_present,
            required_families_pass: $gui_release_required_pass
          }
        },
        visual_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $visual_gate_pass,
          required_family_ids: ($visual_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($visual_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($visual_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            dashboard_chart_read: path_or_null($dashboard_chart_read_transfer_json),
            terminal_screenshot_debug: path_or_null($terminal_screenshot_debug_transfer_json),
            before_after_ui_delta: path_or_null($before_after_ui_delta_transfer_json),
            terminal_state_recovery_read: path_or_null($terminal_state_recovery_read_transfer_json),
            diagram_annotation_read: path_or_null($diagram_annotation_read_transfer_json)
          },
          transfer_report_paths: {
            dashboard_chart_read: path_or_null($dashboard_chart_read_transfer_report),
            terminal_screenshot_debug: path_or_null($terminal_screenshot_debug_transfer_report),
            before_after_ui_delta: path_or_null($before_after_ui_delta_transfer_report),
            terminal_state_recovery_read: path_or_null($terminal_state_recovery_read_transfer_report),
            diagram_annotation_read: path_or_null($diagram_annotation_read_transfer_report)
          },
          transfer_risks: {
            dashboard_chart_read: path_or_null($dashboard_chart_read_transfer_risk),
            terminal_screenshot_debug: path_or_null($terminal_screenshot_debug_transfer_risk),
            before_after_ui_delta: path_or_null($before_after_ui_delta_transfer_risk),
            terminal_state_recovery_read: path_or_null($terminal_state_recovery_read_transfer_risk),
            diagram_annotation_read: path_or_null($diagram_annotation_read_transfer_risk)
          },
          metrics: {
            expected_families: num($visual_expected_count),
            present_families: num($visual_present_count),
            passing_families: num($visual_pass_count)
          },
          gates: {
            required_transfers_present: $visual_required_present,
            required_families_pass: $visual_required_pass
          }
        },
        multi_tool_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $multi_tool_gate_pass,
          required_family_ids: ($multi_tool_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($multi_tool_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($multi_tool_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            repo_runtime_web_triage: path_or_null($repo_runtime_web_triage_transfer_json),
            browser_image_run_investigation: path_or_null($browser_image_run_investigation_transfer_json),
            tool_failure_handoff: path_or_null($tool_failure_handoff_transfer_json)
          },
          transfer_report_paths: {
            repo_runtime_web_triage: path_or_null($repo_runtime_web_triage_transfer_report),
            browser_image_run_investigation: path_or_null($browser_image_run_investigation_transfer_report),
            tool_failure_handoff: path_or_null($tool_failure_handoff_transfer_report)
          },
          transfer_risks: {
            repo_runtime_web_triage: path_or_null($repo_runtime_web_triage_transfer_risk),
            browser_image_run_investigation: path_or_null($browser_image_run_investigation_transfer_risk),
            tool_failure_handoff: path_or_null($tool_failure_handoff_transfer_risk)
          },
          metrics: {
            expected_families: num($multi_tool_expected_count),
            present_families: num($multi_tool_present_count),
            passing_families: num($multi_tool_pass_count)
          },
          gates: {
            required_transfers_present: $multi_tool_required_present,
            required_families_pass: $multi_tool_required_pass
          }
        },
        freshness_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $freshness_gate_pass,
          required_family_ids: ($freshness_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($freshness_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($freshness_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            current_api_migration: path_or_null($current_api_migration_transfer_json),
            current_ops_guidance: path_or_null($current_ops_guidance_transfer_json),
            standards_grounded_answer: path_or_null($standards_grounded_answer_transfer_json)
          },
          transfer_report_paths: {
            current_api_migration: path_or_null($current_api_migration_transfer_report),
            current_ops_guidance: path_or_null($current_ops_guidance_transfer_report),
            standards_grounded_answer: path_or_null($standards_grounded_answer_transfer_report)
          },
          transfer_risks: {
            current_api_migration: path_or_null($current_api_migration_transfer_risk),
            current_ops_guidance: path_or_null($current_ops_guidance_transfer_risk),
            standards_grounded_answer: path_or_null($standards_grounded_answer_transfer_risk)
          },
          metrics: {
            expected_families: num($freshness_expected_count),
            present_families: num($freshness_present_count),
            passing_families: num($freshness_pass_count)
          },
          gates: {
            required_transfers_present: $freshness_required_present,
            required_families_pass: $freshness_required_pass
          }
        },
        operator_judgment_release_enforcement: {
          enabled: $intelligence_enabled,
          pass: $operator_gate_pass,
          required_family_ids: ($operator_required_families | split(",") | map(select(length > 0))),
          present_family_ids: ($operator_present_families | split(",") | map(select(length > 0))),
          passing_family_ids: ($operator_passing_families | split(",") | map(select(length > 0))),
          transfer_json_paths: {
            operator_decision: path_or_null($operator_decision_transfer_json),
            multi_artifact_judgment: path_or_null($multi_artifact_judgment_transfer_json),
            long_context_reassessment: path_or_null($long_context_reassessment_transfer_json)
          },
          transfer_report_paths: {
            operator_decision: path_or_null($operator_decision_transfer_report),
            multi_artifact_judgment: path_or_null($multi_artifact_judgment_transfer_report),
            long_context_reassessment: path_or_null($long_context_reassessment_transfer_report)
          },
          transfer_risks: {
            operator_decision: path_or_null($operator_decision_transfer_risk),
            multi_artifact_judgment: path_or_null($multi_artifact_judgment_transfer_risk),
            long_context_reassessment: path_or_null($long_context_reassessment_transfer_risk)
          },
          metrics: {
            expected_families: num($operator_expected_count),
            present_families: num($operator_present_count),
            passing_families: num($operator_pass_count)
          },
          gates: {
            required_transfers_present: $operator_required_present,
            required_families_pass: $operator_required_pass
          }
        },
        interactive_session: {
          enabled: $interactive_intelligence_enabled,
          pass: $interactive_gui_pass,
          profile: path_or_null($interactive_gui_profile),
          result_path: path_or_null($interactive_gui_result_path),
          report_path: path_or_null($interactive_gui_report_path),
          success: $interactive_gui_success
        }
      },
      gui: {
        enabled: $gui_enabled,
        pass: $gui_pass,
        profile: $gui_profile,
        result_path: path_or_null($gui_result_path),
        report_path: path_or_null($gui_report_path),
        success: $gui_success
      },
      all_pass: $overall_pass
    }
  ' > "$gate_json"

status_text="FAIL"
if [ "$overall_pass" = "true" ]; then
  status_text="PASS"
fi

{
  printf '# Artificer Release Gate: %s\n\n' "$label"
  printf '## Status\n'
  printf -- '- Result: %s\n' "$status_text"
  printf -- '- Generated at (UTC): %s\n' "$generated_at"

  printf '\n## Intelligence Gate\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  printf -- '- Pass: %s\n' "$intelligence_pass"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Battery summary: `%s`\n' "$battery_summary"
    printf -- '- Holdout summary: `%s`\n' "$holdout_summary"
    printf -- '- battery avg_overall >= %s: %s (actual=%s)\n' "$min_battery_overall" "$gate_battery_overall" "$battery_overall"
    printf -- '- holdout avg_overall >= %s: %s (actual=%s)\n' "$min_holdout_overall" "$gate_holdout_overall" "$holdout_overall"
    printf -- '- holdout avg_adversarial >= %s: %s (actual=%s)\n' "$min_holdout_adversarial" "$gate_holdout_adversarial" "$holdout_adversarial"
    printf -- '- holdout avg_ambiguity >= %s: %s (actual=%s)\n' "$min_holdout_ambiguity" "$gate_holdout_ambiguity" "$holdout_ambiguity"
    printf -- '- holdout avg_cross_domain >= %s: %s (actual=%s)\n' "$min_holdout_cross_domain" "$gate_holdout_cross_domain" "$holdout_cross_domain"
    printf -- '- holdout avg_recovery >= %s: %s (actual=%s)\n' "$min_holdout_recovery" "$gate_holdout_recovery" "$holdout_recovery"
    printf -- '- fail_open_rate <= %s (battery+holdout): %s (battery=%s holdout=%s)\n' "$max_fail_open_rate" "$gate_fail_open" "$battery_fail_open" "$holdout_fail_open"
    printf -- '- contradiction_rate <= %s (battery+holdout): %s (battery=%s holdout=%s)\n' "$max_contradiction_rate" "$gate_contradiction" "$battery_contradiction" "$holdout_contradiction"
    printf -- '- holdout overall not below battery by > %s: %s\n' "$max_holdout_overall_drop" "$gate_holdout_drop"
  fi

  printf '\n## Mixed Transfer Gate\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$mixed_transfer_pass"
    printf -- '- Mixed regression summary: `%s`\n' "$mixed_battery_summary"
    printf -- '- Mixed holdout summary: `%s`\n' "$mixed_holdout_summary"
    printf -- '- Mixed transfer JSON: `%s`\n' "$mixed_transfer_json"
    if [ -n "$mixed_transfer_report" ]; then
      printf -- '- Mixed transfer report: `%s`\n' "$mixed_transfer_report"
    fi
    printf -- '- no fail-open increase: %s\n' "$mixed_gate_fail_open"
    printf -- '- no contradiction-rate increase: %s\n' "$mixed_gate_contradiction"
    printf -- '- holdout not worse overall: %s\n' "$mixed_gate_holdout"
    printf -- '- improved axes >= 2: %s (count=%s)\n' "$mixed_gate_improved_axes" "$mixed_improved_axes"
    printf -- '- improved or stably excellent axes >= 2: %s (coverage=%s stable=%s)\n' "$mixed_gate_coverage_axes" "$mixed_coverage_axes" "$mixed_stable_axes"
    printf -- '- no saturation-risk flag in battery/holdout: %s\n' "$mixed_gate_saturation"
    printf -- '- transfer risk: %s\n' "$mixed_transfer_risk"
  fi

  printf '\n## Compact Reasoning Gate\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$compact_transfer_pass"
    printf -- '- Compact regression summary: `%s`\n' "$compact_battery_summary"
    printf -- '- Compact holdout summary: `%s`\n' "$compact_holdout_summary"
    printf -- '- Compact transfer JSON: `%s`\n' "$compact_transfer_json"
    if [ -n "$compact_transfer_report" ]; then
      printf -- '- Compact transfer report: `%s`\n' "$compact_transfer_report"
    fi
    printf -- '- battery exact-contract rate: %s\n' "$compact_battery_exact_contract"
    printf -- '- battery required-ratio: %s\n' "$compact_battery_required_ratio"
    printf -- '- battery owner-window rate: %s\n' "$compact_battery_owner_window"
    printf -- '- holdout exact-contract rate: %s\n' "$compact_holdout_exact_contract"
    printf -- '- holdout required-ratio: %s\n' "$compact_holdout_required_ratio"
    printf -- '- holdout owner-window rate: %s\n' "$compact_holdout_owner_window"
    printf -- '- no fail-open increase: %s\n' "$compact_gate_fail_open"
    printf -- '- no contradiction-rate increase: %s\n' "$compact_gate_contradiction"
    printf -- '- holdout not worse overall: %s\n' "$compact_gate_holdout"
    printf -- '- exact contract full on battery+holdout: %s\n' "$compact_gate_exact"
    printf -- '- required ratio full on battery+holdout: %s\n' "$compact_gate_required"
    printf -- '- owner/window full on battery+holdout: %s\n' "$compact_gate_owner_window"
    printf -- '- transfer risk: %s\n' "$compact_transfer_risk"
  fi

  printf '\n## Rich Thread Gate\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$rich_transfer_pass"
    printf -- '- Rich regression summary: `%s`\n' "$rich_battery_summary"
    printf -- '- Rich holdout summary: `%s`\n' "$rich_holdout_summary"
    printf -- '- Rich transfer JSON: `%s`\n' "$rich_transfer_json"
    if [ -n "$rich_transfer_report" ]; then
      printf -- '- Rich transfer report: `%s`\n' "$rich_transfer_report"
    fi
    printf -- '- battery exact-contract rate: %s\n' "$rich_battery_exact_contract"
    printf -- '- battery required-ratio: %s\n' "$rich_battery_required_ratio"
    printf -- '- battery core-label exact-once rate: %s\n' "$rich_battery_core_labels"
    printf -- '- holdout exact-contract rate: %s\n' "$rich_holdout_exact_contract"
    printf -- '- holdout required-ratio: %s\n' "$rich_holdout_required_ratio"
    printf -- '- holdout core-label exact-once rate: %s\n' "$rich_holdout_core_labels"
    printf -- '- no fail-open increase: %s\n' "$rich_gate_fail_open"
    printf -- '- no contradiction-rate increase: %s\n' "$rich_gate_contradiction"
    printf -- '- holdout not worse overall: %s\n' "$rich_gate_holdout"
    printf -- '- exact contract full on battery+holdout: %s\n' "$rich_gate_exact"
    printf -- '- required ratio full on battery+holdout: %s\n' "$rich_gate_required"
    printf -- '- core labels full on battery+holdout: %s\n' "$rich_gate_core_labels"
    printf -- '- transfer risk: %s\n' "$rich_transfer_risk"
  fi

  printf '\n## Freeform Memo Gate\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$freeform_transfer_pass"
    printf -- '- Freeform regression summary: `%s`\n' "$freeform_battery_summary"
    printf -- '- Freeform holdout summary: `%s`\n' "$freeform_holdout_summary"
    printf -- '- Freeform transfer JSON: `%s`\n' "$freeform_transfer_json"
    if [ -n "$freeform_transfer_report" ]; then
      printf -- '- Freeform transfer report: `%s`\n' "$freeform_transfer_report"
    fi
    printf -- '- battery freeform rate: %s\n' "$freeform_battery_freeform_rate"
    printf -- '- battery uncertainty rate: %s\n' "$freeform_battery_uncertainty_rate"
    printf -- '- battery reversal rate: %s\n' "$freeform_battery_reversal_rate"
    printf -- '- battery required-ratio: %s\n' "$freeform_battery_required_ratio"
    printf -- '- holdout freeform rate: %s\n' "$freeform_holdout_freeform_rate"
    printf -- '- holdout uncertainty rate: %s\n' "$freeform_holdout_uncertainty_rate"
    printf -- '- holdout reversal rate: %s\n' "$freeform_holdout_reversal_rate"
    printf -- '- holdout required-ratio: %s\n' "$freeform_holdout_required_ratio"
    printf -- '- no fail-open increase: %s\n' "$freeform_gate_fail_open"
    printf -- '- no contradiction-rate increase: %s\n' "$freeform_gate_contradiction"
    printf -- '- holdout not worse overall: %s\n' "$freeform_gate_holdout"
    printf -- '- freeform prose full on battery+holdout: %s\n' "$freeform_gate_freeform"
    printf -- '- uncertainty signal full on battery+holdout: %s\n' "$freeform_gate_uncertainty"
    printf -- '- reversal signal full on battery+holdout: %s\n' "$freeform_gate_reversal"
    printf -- '- required ratio full on battery+holdout: %s\n' "$freeform_gate_required"
    printf -- '- transfer risk: %s\n' "$freeform_transfer_risk"
  fi

  printf '\n## Programming Stalled-Summary Gate\n'
  printf -- '- Enabled: %s\n' "$programming_enabled"
  if [ "$programming_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$programming_gate_pass"
    printf -- '- Programming summary JSON: `%s`\n' "$programming_summary_json"
    if [ -n "$programming_summary_report" ]; then
      printf -- '- Programming summary report: `%s`\n' "$programming_summary_report"
    fi
    printf -- '- total rows: %s\n' "$programming_total"
    printf -- '- passing rows: %s\n' "$programming_passes"
    printf -- '- failing rows: %s\n' "$programming_failures"
    printf -- '- nonempty run set: %s\n' "$programming_gate_nonempty"
    printf -- '- all rows pass: %s\n' "$programming_gate_all_rows"
  fi

  printf '\n## Programming Branchy-Slice Gate\n'
  printf -- '- Enabled: %s\n' "$programming_enabled"
  if [ "$programming_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$programming_branchy_gate_pass"
    printf -- '- Programming branchy JSON: `%s`\n' "$programming_branchy_json"
    if [ -n "$programming_branchy_report" ]; then
      printf -- '- Programming branchy report: `%s`\n' "$programming_branchy_report"
    fi
    printf -- '- total rows: %s\n' "$programming_branchy_total"
    printf -- '- passing rows: %s\n' "$programming_branchy_passes"
    printf -- '- failing rows: %s\n' "$programming_branchy_failures"
    printf -- '- nonempty run set: %s\n' "$programming_branchy_gate_nonempty"
    printf -- '- all rows pass: %s\n' "$programming_branchy_gate_all_rows"
  fi

  printf '\n## Programming Auto-Branchy Gate\n'
  printf -- '- Enabled: %s\n' "$programming_enabled"
  if [ "$programming_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$programming_auto_branchy_gate_pass"
    printf -- '- Programming auto-branchy JSON: `%s`\n' "$programming_auto_branchy_json"
    if [ -n "$programming_auto_branchy_report" ]; then
      printf -- '- Programming auto-branchy report: `%s`\n' "$programming_auto_branchy_report"
    fi
    printf -- '- total rows: %s\n' "$programming_auto_branchy_total"
    printf -- '- passing rows: %s\n' "$programming_auto_branchy_passes"
    printf -- '- failing rows: %s\n' "$programming_auto_branchy_failures"
    printf -- '- nonempty run set: %s\n' "$programming_auto_branchy_gate_nonempty"
    printf -- '- all rows pass: %s\n' "$programming_auto_branchy_gate_all_rows"
  fi

  printf '\n## Long-Horizon Programming Enforcement\n'
  printf -- '- Enabled: %s\n' "$programming_enabled"
  if [ "$programming_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$programming_long_horizon_gate_pass"
    printf -- '- Source programming auto-branchy JSON: `%s`\n' "$programming_auto_branchy_json"
    printf -- '- expected required rows: %s\n' "$programming_long_horizon_expected_count"
    printf -- '- present required rows: %s\n' "$programming_long_horizon_present_count"
    printf -- '- passing required rows: %s\n' "$programming_long_horizon_pass_count"
    printf -- '- required rows present: %s\n' "$programming_long_horizon_required_rows_present"
    printf -- '- required rows pass cleanly: %s\n' "$programming_long_horizon_required_rows_pass"
    printf -- '- required task ids: `%s`\n' "$programming_long_horizon_required_rows"
    printf -- '- present task ids: `%s`\n' "$programming_long_horizon_present_rows"
    printf -- '- passing task ids: `%s`\n' "$programming_long_horizon_passing_rows"
  fi

  printf '\n## Long-Horizon Timeout Coverage\n'
  printf -- '- Enabled: %s\n' "$programming_enabled"
  if [ "$programming_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$long_horizon_timeout_gate_pass"
    printf -- '- expected families: %s\n' "$long_horizon_timeout_expected_count"
    printf -- '- present families: %s\n' "$long_horizon_timeout_present_count"
    printf -- '- passing families: %s\n' "$long_horizon_timeout_pass_count"
    printf -- '- required transfer present: %s\n' "$long_horizon_timeout_required_present"
    printf -- '- required family pass: %s\n' "$long_horizon_timeout_required_pass"
    printf -- '- required family ids: `%s`\n' "$long_horizon_timeout_required_families"
    printf -- '- present family ids: `%s`\n' "$long_horizon_timeout_present_families"
    printf -- '- passing family ids: `%s`\n' "$long_horizon_timeout_passing_families"
    printf -- '- timeout coverage transfer JSON: `%s`\n' "$long_horizon_timeout_coverage_transfer_json"
  fi

  printf '\n## Document Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$document_gate_pass"
    printf -- '- expected families: %s\n' "$document_expected_count"
    printf -- '- present families: %s\n' "$document_present_count"
    printf -- '- passing families: %s\n' "$document_pass_count"
    printf -- '- required transfer present: %s\n' "$document_required_present"
    printf -- '- required family pass: %s\n' "$document_required_pass"
    printf -- '- required family ids: `%s`\n' "$document_required_families"
    printf -- '- present family ids: `%s`\n' "$document_present_families"
    printf -- '- passing family ids: `%s`\n' "$document_passing_families"
    printf -- '- document transfer JSON: `%s`\n' "$document_transfer_json"
  fi

  printf '\n## Remote Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$remote_gate_pass"
    printf -- '- expected families: %s\n' "$remote_expected_count"
    printf -- '- present families: %s\n' "$remote_present_count"
    printf -- '- passing families: %s\n' "$remote_pass_count"
    printf -- '- required transfers present: %s\n' "$remote_required_present"
    printf -- '- required families pass: %s\n' "$remote_required_pass"
    printf -- '- required family ids: `%s`\n' "$remote_required_families"
    printf -- '- present family ids: `%s`\n' "$remote_present_families"
    printf -- '- passing family ids: `%s`\n' "$remote_passing_families"
    printf -- '- remote release-pack transfer JSON: `%s`\n' "$remote_release_pack_transfer_json"
  fi

  printf '\n## GUI Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$gui_release_gate_pass"
    printf -- '- expected families: %s\n' "$gui_release_expected_count"
    printf -- '- present families: %s\n' "$gui_release_present_count"
    printf -- '- passing families: %s\n' "$gui_release_pass_count"
    printf -- '- required transfers present: %s\n' "$gui_release_required_present"
    printf -- '- required families pass: %s\n' "$gui_release_required_pass"
    printf -- '- required family ids: `%s`\n' "$gui_release_required_families"
    printf -- '- present family ids: `%s`\n' "$gui_release_present_families"
    printf -- '- passing family ids: `%s`\n' "$gui_release_passing_families"
    printf -- '- gui state-recovery transfer JSON: `%s`\n' "$gui_state_recovery_pack_transfer_json"
  fi

  printf '\n## Visual Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$visual_gate_pass"
    printf -- '- expected families: %s\n' "$visual_expected_count"
    printf -- '- present families: %s\n' "$visual_present_count"
    printf -- '- passing families: %s\n' "$visual_pass_count"
    printf -- '- required transfers present: %s\n' "$visual_required_present"
    printf -- '- required families pass: %s\n' "$visual_required_pass"
    printf -- '- required family ids: `%s`\n' "$visual_required_families"
    printf -- '- present family ids: `%s`\n' "$visual_present_families"
    printf -- '- passing family ids: `%s`\n' "$visual_passing_families"
    printf -- '- diagram annotation transfer JSON: `%s`\n' "$diagram_annotation_read_transfer_json"
  fi

  printf '\n## Multi-Tool Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$multi_tool_gate_pass"
    printf -- '- expected families: %s\n' "$multi_tool_expected_count"
    printf -- '- present families: %s\n' "$multi_tool_present_count"
    printf -- '- passing families: %s\n' "$multi_tool_pass_count"
    printf -- '- required transfers present: %s\n' "$multi_tool_required_present"
    printf -- '- required families pass: %s\n' "$multi_tool_required_pass"
    printf -- '- required family ids: `%s`\n' "$multi_tool_required_families"
    printf -- '- present family ids: `%s`\n' "$multi_tool_present_families"
    printf -- '- passing family ids: `%s`\n' "$multi_tool_passing_families"
    printf -- '- repo/runtime/web transfer JSON: `%s`\n' "$repo_runtime_web_triage_transfer_json"
    printf -- '- browser/image/run transfer JSON: `%s`\n' "$browser_image_run_investigation_transfer_json"
    printf -- '- tool-failure-handoff transfer JSON: `%s`\n' "$tool_failure_handoff_transfer_json"
  fi

  printf '\n## Freshness Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$freshness_gate_pass"
    printf -- '- expected families: %s\n' "$freshness_expected_count"
    printf -- '- present families: %s\n' "$freshness_present_count"
    printf -- '- passing families: %s\n' "$freshness_pass_count"
    printf -- '- required transfers present: %s\n' "$freshness_required_present"
    printf -- '- required families pass: %s\n' "$freshness_required_pass"
    printf -- '- required family ids: `%s`\n' "$freshness_required_families"
    printf -- '- present family ids: `%s`\n' "$freshness_present_families"
    printf -- '- passing family ids: `%s`\n' "$freshness_passing_families"
    printf -- '- current-api-migration transfer JSON: `%s`\n' "$current_api_migration_transfer_json"
    printf -- '- current-ops-guidance transfer JSON: `%s`\n' "$current_ops_guidance_transfer_json"
    printf -- '- standards-grounded-answer transfer JSON: `%s`\n' "$standards_grounded_answer_transfer_json"
  fi

  printf '\n## Operator Judgment Release Enforcement\n'
  printf -- '- Enabled: %s\n' "$intelligence_enabled"
  if [ "$intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$operator_gate_pass"
    printf -- '- expected families: %s\n' "$operator_expected_count"
    printf -- '- present families: %s\n' "$operator_present_count"
    printf -- '- passing families: %s\n' "$operator_pass_count"
    printf -- '- required transfers present: %s\n' "$operator_required_present"
    printf -- '- required families pass: %s\n' "$operator_required_pass"
    printf -- '- required family ids: `%s`\n' "$operator_required_families"
    printf -- '- present family ids: `%s`\n' "$operator_present_families"
    printf -- '- passing family ids: `%s`\n' "$operator_passing_families"
    printf -- '- operator-decision transfer JSON: `%s`\n' "$operator_decision_transfer_json"
    printf -- '- multi-artifact-judgment transfer JSON: `%s`\n' "$multi_artifact_judgment_transfer_json"
    printf -- '- long-context-reassessment transfer JSON: `%s`\n' "$long_context_reassessment_transfer_json"
  fi

  printf '\n## Interactive Intelligence Gate\n'
  printf -- '- Enabled: %s\n' "$interactive_intelligence_enabled"
  if [ "$interactive_intelligence_enabled" = "true" ]; then
    printf -- '- Pass: %s\n' "$interactive_gui_pass"
    printf -- '- Profile: `%s`\n' "$interactive_gui_profile"
    printf -- '- Result JSON: `%s`\n' "$interactive_gui_result_path"
    if [ -n "$interactive_gui_report_path" ]; then
      printf -- '- Report: `%s`\n' "$interactive_gui_report_path"
    fi
    printf -- '- GUI result `.success`: %s\n' "$interactive_gui_success"
  fi

  printf '\n## GUI Gate\n'
  printf -- '- Enabled: %s\n' "$gui_enabled"
  printf -- '- Pass: %s\n' "$gui_pass"
  if [ "$gui_enabled" = "true" ]; then
    printf -- '- Profile: `%s`\n' "$gui_profile"
    printf -- '- Result JSON: `%s`\n' "$gui_result_path"
    if [ -n "$gui_report_path" ]; then
      printf -- '- Report: `%s`\n' "$gui_report_path"
    fi
    printf -- '- GUI result `.success`: %s\n' "$gui_success"
  fi

  printf '\n## Artifacts\n'
  printf -- '- Combined gate JSON: `%s`\n' "$gate_json"
  printf -- '- Combined gate report: `%s`\n' "$gate_report"
} > "$gate_report"

printf '%s\n' "$gate_json"
printf '%s\n' "$gate_report"

if [ "$overall_pass" != "true" ]; then
  exit 1
fi
