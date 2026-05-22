#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SITE_ROOT="$PROJECT_ROOT/hosted-web"
. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
RELEASE_GATE_SCRIPT="$SCRIPT_DIR/release-gate.sh"

if [ ! -x "$RELEASE_GATE_SCRIPT" ]; then
  echo "release-gate.sh is not executable: $RELEASE_GATE_SCRIPT" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for GUI soak reporting." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for GUI soak reporting." >&2
  exit 1
fi

usage() {
  cat <<'USAGE'
Usage:
  release-gate-gui-soak.sh [options]

Options:
  --label NAME                       Soak label (default: release-gui-soak-YYYYmmdd-HHMMSS)
  --iterations N                     Number of live GUI gate iterations (default: 3)
  --iteration-timeout-sec N          Max time per release-gate iteration (default: 1200)
  --gui-profile PROFILE              GUI profile for release-gate.sh (default: core)
  --interactive-gui-profile PROFILE  Interactive GUI profile for release-gate.sh (default: intelligence)
  --battery-summary FILE             Reuse strict battery summary JSON
  --holdout-summary FILE             Reuse strict holdout summary JSON
  --mixed-battery-summary FILE       Reuse mixed regression summary JSON
  --mixed-holdout-summary FILE       Reuse mixed holdout summary JSON
  --mixed-transfer-json FILE         Reuse mixed transfer JSON
  --compact-battery-summary FILE     Reuse compact regression summary JSON
  --compact-holdout-summary FILE     Reuse compact holdout summary JSON
  --compact-transfer-json FILE       Reuse compact transfer JSON
  --rich-battery-summary FILE        Reuse rich live-thread regression summary JSON
  --rich-holdout-summary FILE        Reuse rich live-thread holdout summary JSON
  --rich-transfer-json FILE          Reuse rich live-thread transfer JSON
  --freeform-battery-summary FILE    Reuse freeform memo regression summary JSON
  --freeform-holdout-summary FILE    Reuse freeform memo holdout summary JSON
  --freeform-transfer-json FILE      Reuse freeform memo transfer JSON
  --programming-summary-json FILE    Reuse programming stalled-summary smoke JSON
  --programming-branchy-json FILE    Reuse programming branchy-slice smoke JSON
  --programming-auto-branchy-json FILE
                                     Reuse programming auto-budget branchy smoke JSON
  --repo-runtime-web-triage-transfer-json FILE
                                     Reuse repo/runtime/web triage transfer JSON
  --browser-image-run-investigation-transfer-json FILE
                                     Reuse browser/image/run investigation transfer JSON
  --tool-failure-handoff-transfer-json FILE
                                     Reuse tool-failure handoff transfer JSON
  --current-api-migration-transfer-json FILE
                                     Reuse current API migration transfer JSON
  --current-ops-guidance-transfer-json FILE
                                     Reuse current ops guidance transfer JSON
  --standards-grounded-answer-transfer-json FILE
                                     Reuse standards-grounded answer transfer JSON
  --operator-decision-transfer-json FILE
                                     Reuse operator-decision transfer JSON
  --multi-artifact-judgment-transfer-json FILE
                                     Reuse multi-artifact judgment transfer JSON
  --long-context-reassessment-transfer-json FILE
                                     Reuse long-context reassessment transfer JSON
  --long-horizon-timeout-coverage-transfer-json FILE
                                     Reuse long-horizon timeout coverage transfer JSON
  --document-transfer-json FILE
                                     Reuse document family transfer JSON
  --remote-ops-transfer-json FILE
                                     Reuse remote single-host diagnose transfer JSON
  --remote-deploy-transfer-json FILE
                                     Reuse remote deploy transfer JSON
  --remote-multi-host-transfer-json FILE
                                     Reuse remote multi-host failover transfer JSON
  --remote-multi-host-rollout-transfer-json FILE
                                     Reuse remote multi-host rollout transfer JSON
  --remote-bastion-cutover-transfer-json FILE
                                     Reuse remote bastion cutover transfer JSON
  --remote-boundary-rollout-transfer-json FILE
                                     Reuse remote boundary rollout transfer JSON
  --remote-boundary-rollback-transfer-json FILE
                                     Reuse remote boundary rollback transfer JSON
  --remote-boundary-pack-transfer-json FILE
                                     Reuse remote boundary pack transfer JSON
  --remote-release-pack-transfer-json FILE
                                     Reuse remote release pack transfer JSON
  --gui-visual-transfer-json FILE
                                     Reuse GUI visual transfer JSON
  --gui-screenshot-layout-triage-transfer-json FILE
                                     Reuse GUI screenshot triage transfer JSON
  --gui-login-upload-download-transfer-json FILE
                                     Reuse GUI login/upload/download transfer JSON
  --gui-state-recovery-pack-transfer-json FILE
                                     Reuse GUI state recovery transfer JSON
  --dashboard-chart-read-transfer-json FILE
                                     Reuse dashboard chart read transfer JSON
  --terminal-screenshot-debug-transfer-json FILE
                                     Reuse terminal screenshot debug transfer JSON
  --before-after-ui-delta-transfer-json FILE
                                     Reuse before/after UI delta transfer JSON
  --terminal-state-recovery-read-transfer-json FILE
                                     Reuse terminal state recovery transfer JSON
  --diagram-annotation-read-transfer-json FILE
                                     Reuse diagram annotation transfer JSON
  --gui-result FILE                  Reuse a GUI gate result JSON for every iteration
  --interactive-gui-result FILE      Reuse an interactive GUI gate result JSON for every iteration
  --stop-on-fail                     Stop the soak after the first failed iteration
  --help                             Show this help

Notes:
  - By default the soak tries to reuse the current known-good reasoning summaries if they exist.
  - GUI checks stay live; only reasoning summaries are reused.
USAGE
}

label="release-gui-soak-$(date +%Y%m%d-%H%M%S)"
iterations=3
iteration_timeout_sec=1200
gui_profile="core"
interactive_gui_profile="intelligence"
stop_on_fail=0
gui_result=""
interactive_gui_result=""

default_battery_summary="$OUT_DIR/broad-v16-regressions-r4-summary.json"
default_holdout_summary="$OUT_DIR/broad-v16-holdout-r4-summary.json"
default_mixed_battery_summary="$OUT_DIR/broad93-reg41-full-summary.json"
default_mixed_holdout_summary="$OUT_DIR/broad93-hold41-full-summary.json"
default_mixed_transfer_json="$OUT_DIR/broad94-mixedtransfer-gatecheck-transfer.json"
default_compact_battery_summary="$OUT_DIR/compact-v44-regressions-r1-summary.json"
default_compact_holdout_summary="$OUT_DIR/compact-v44-holdout-r1-summary.json"
default_compact_transfer_json="$OUT_DIR/compact-v44-transfer-r1-transfer.json"
default_rich_battery_summary="$OUT_DIR/rich-v55-regressions-r5-summary.json"
default_rich_holdout_summary="$OUT_DIR/rich-v55-holdout-r5-summary.json"
default_rich_transfer_json="$OUT_DIR/rich-v55-transfer-r1-transfer.json"
default_freeform_battery_summary="$OUT_DIR/freeform-v75-regressions-r2-summary.json"
default_freeform_holdout_summary="$OUT_DIR/freeform-v75-holdout-r2-summary.json"
default_freeform_transfer_json="$OUT_DIR/freeform-v75-transfer-r1-transfer.json"
default_programming_summary_json="$OUT_DIR/programming-stalled-summary-smoke-r7.json"
default_programming_branchy_json="$OUT_DIR/programming-branchy-slice-smoke-r106.json"
default_programming_auto_branchy_json="$OUT_DIR/programming-auto-branchy-smoke-r23.json"
default_repo_runtime_web_triage_transfer_json="$OUT_DIR/repo-runtime-web-triage-v1-transfer-r1-transfer.json"
default_browser_image_run_investigation_transfer_json="$OUT_DIR/browser-image-run-investigation-v1-transfer-r1-transfer.json"
default_tool_failure_handoff_transfer_json="$OUT_DIR/tool-failure-handoff-v1-transfer-r1-transfer.json"
default_current_api_migration_transfer_json="$OUT_DIR/current-api-migration-v1-transfer-r1-transfer.json"
default_current_ops_guidance_transfer_json="$OUT_DIR/current-ops-guidance-v1-transfer-r1-transfer.json"
default_standards_grounded_answer_transfer_json="$OUT_DIR/standards-grounded-answer-v1-transfer-r1-transfer.json"
default_operator_decision_transfer_json="$OUT_DIR/operator-decision-v1-transfer-r1-transfer.json"
default_multi_artifact_judgment_transfer_json="$OUT_DIR/multi-artifact-judgment-v1-transfer-transfer.json"
default_long_context_reassessment_transfer_json="$OUT_DIR/long-context-reassessment-v1-transfer-transfer.json"
default_long_horizon_timeout_coverage_transfer_json="$OUT_DIR/long-horizon-timeout-coverage-v1-transfer-r1-transfer.json"
default_document_transfer_json="$OUT_DIR/document-v1-transfer-r2-transfer.json"
default_remote_ops_transfer_json="$OUT_DIR/remote-ops-v1-transfer-r1-transfer.json"
default_remote_deploy_transfer_json="$OUT_DIR/remote-deploy-v1-transfer-r1-transfer.json"
default_remote_multi_host_transfer_json="$OUT_DIR/remote-multi-host-v1-transfer-r1-transfer.json"
default_remote_multi_host_rollout_transfer_json="$OUT_DIR/remote-multi-host-rollout-v1-transfer-r1-transfer.json"
default_remote_bastion_cutover_transfer_json="$OUT_DIR/remote-bastion-cutover-v1-transfer-r1-transfer.json"
default_remote_boundary_rollout_transfer_json="$OUT_DIR/remote-boundary-rollout-v1-transfer-r1-transfer.json"
default_remote_boundary_rollback_transfer_json="$OUT_DIR/remote-boundary-rollback-v1-transfer-r1-transfer.json"
default_remote_boundary_pack_transfer_json="$OUT_DIR/remote-boundary-pack-v1-transfer-r1-transfer.json"
default_remote_release_pack_transfer_json="$OUT_DIR/remote-release-pack-v1-transfer-r1-transfer.json"
default_gui_visual_transfer_json="$OUT_DIR/gui-visual-v1-transfer-r1-transfer.json"
default_gui_screenshot_layout_triage_transfer_json="$OUT_DIR/gui-screenshot-layout-triage-v1-transfer-r1-transfer.json"
default_gui_login_upload_download_transfer_json="$OUT_DIR/gui-login-upload-download-v1-transfer-r1-transfer.json"
default_gui_state_recovery_pack_transfer_json="$OUT_DIR/gui-state-recovery-pack-v1-transfer-r2-transfer.json"
default_dashboard_chart_read_transfer_json="$OUT_DIR/dashboard-chart-read-v1-transfer-r1-transfer.json"
default_terminal_screenshot_debug_transfer_json="$OUT_DIR/terminal-screenshot-debug-v1-transfer-r2-transfer.json"
default_before_after_ui_delta_transfer_json="$OUT_DIR/before-after-ui-delta-v1-transfer-r1-transfer.json"
default_terminal_state_recovery_read_transfer_json="$OUT_DIR/terminal-state-recovery-read-v1-transfer-r2-transfer.json"
default_diagram_annotation_read_transfer_json="$OUT_DIR/diagram-annotation-read-v1-transfer-r2-transfer.json"

battery_summary=""
holdout_summary=""
mixed_battery_summary=""
mixed_holdout_summary=""
mixed_transfer_json=""
compact_battery_summary=""
compact_holdout_summary=""
compact_transfer_json=""
rich_battery_summary=""
rich_holdout_summary=""
rich_transfer_json=""
freeform_battery_summary=""
freeform_holdout_summary=""
freeform_transfer_json=""
programming_summary_json=""
programming_branchy_json=""
programming_auto_branchy_json=""
repo_runtime_web_triage_transfer_json=""
browser_image_run_investigation_transfer_json=""
tool_failure_handoff_transfer_json=""
current_api_migration_transfer_json=""
current_ops_guidance_transfer_json=""
standards_grounded_answer_transfer_json=""
operator_decision_transfer_json=""
multi_artifact_judgment_transfer_json=""
long_context_reassessment_transfer_json=""
long_horizon_timeout_coverage_transfer_json=""
document_transfer_json=""
remote_ops_transfer_json=""
remote_deploy_transfer_json=""
remote_multi_host_transfer_json=""
remote_multi_host_rollout_transfer_json=""
remote_bastion_cutover_transfer_json=""
remote_boundary_rollout_transfer_json=""
remote_boundary_rollback_transfer_json=""
remote_boundary_pack_transfer_json=""
remote_release_pack_transfer_json=""
gui_visual_transfer_json=""
gui_screenshot_layout_triage_transfer_json=""
gui_login_upload_download_transfer_json=""
gui_state_recovery_pack_transfer_json=""
dashboard_chart_read_transfer_json=""
terminal_screenshot_debug_transfer_json=""
before_after_ui_delta_transfer_json=""
terminal_state_recovery_read_transfer_json=""
diagram_annotation_read_transfer_json=""

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --iterations)
      iterations=$2
      shift 2
      ;;
    --iteration-timeout-sec)
      iteration_timeout_sec=$2
      shift 2
      ;;
    --gui-profile)
      gui_profile=$2
      shift 2
      ;;
    --interactive-gui-profile)
      interactive_gui_profile=$2
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
    --gui-result)
      gui_result=$2
      shift 2
      ;;
    --interactive-gui-result)
      interactive_gui_result=$2
      shift 2
      ;;
    --stop-on-fail)
      stop_on_fail=1
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
case "$iterations" in
  ''|*[!0-9]*)
    echo "--iterations must be a positive integer" >&2
    exit 1
    ;;
esac
if [ "$iterations" -lt 1 ]; then
  echo "--iterations must be >= 1" >&2
  exit 1
fi
case "$iteration_timeout_sec" in
  ''|*[!0-9]*)
    echo "--iteration-timeout-sec must be a positive integer" >&2
    exit 1
    ;;
esac
if [ "$iteration_timeout_sec" -lt 60 ]; then
  echo "--iteration-timeout-sec must be >= 60" >&2
  exit 1
fi

pick_default_if_exists() {
  candidate=$1
  if [ -z "$2" ] && [ -f "$candidate" ]; then
    printf '%s' "$candidate"
  else
    printf '%s' "$2"
  fi
}

battery_summary=$(pick_default_if_exists "$default_battery_summary" "$battery_summary")
holdout_summary=$(pick_default_if_exists "$default_holdout_summary" "$holdout_summary")
mixed_battery_summary=$(pick_default_if_exists "$default_mixed_battery_summary" "$mixed_battery_summary")
mixed_holdout_summary=$(pick_default_if_exists "$default_mixed_holdout_summary" "$mixed_holdout_summary")
mixed_transfer_json=$(pick_default_if_exists "$default_mixed_transfer_json" "$mixed_transfer_json")
compact_battery_summary=$(pick_default_if_exists "$default_compact_battery_summary" "$compact_battery_summary")
compact_holdout_summary=$(pick_default_if_exists "$default_compact_holdout_summary" "$compact_holdout_summary")
compact_transfer_json=$(pick_default_if_exists "$default_compact_transfer_json" "$compact_transfer_json")
rich_battery_summary=$(pick_default_if_exists "$default_rich_battery_summary" "$rich_battery_summary")
rich_holdout_summary=$(pick_default_if_exists "$default_rich_holdout_summary" "$rich_holdout_summary")
rich_transfer_json=$(pick_default_if_exists "$default_rich_transfer_json" "$rich_transfer_json")
freeform_battery_summary=$(pick_default_if_exists "$default_freeform_battery_summary" "$freeform_battery_summary")
freeform_holdout_summary=$(pick_default_if_exists "$default_freeform_holdout_summary" "$freeform_holdout_summary")
freeform_transfer_json=$(pick_default_if_exists "$default_freeform_transfer_json" "$freeform_transfer_json")
programming_summary_json=$(pick_default_if_exists "$default_programming_summary_json" "$programming_summary_json")
programming_branchy_json=$(pick_default_if_exists "$default_programming_branchy_json" "$programming_branchy_json")
programming_auto_branchy_json=$(pick_default_if_exists "$default_programming_auto_branchy_json" "$programming_auto_branchy_json")
repo_runtime_web_triage_transfer_json=$(pick_default_if_exists "$default_repo_runtime_web_triage_transfer_json" "$repo_runtime_web_triage_transfer_json")
browser_image_run_investigation_transfer_json=$(pick_default_if_exists "$default_browser_image_run_investigation_transfer_json" "$browser_image_run_investigation_transfer_json")
tool_failure_handoff_transfer_json=$(pick_default_if_exists "$default_tool_failure_handoff_transfer_json" "$tool_failure_handoff_transfer_json")
current_api_migration_transfer_json=$(pick_default_if_exists "$default_current_api_migration_transfer_json" "$current_api_migration_transfer_json")
current_ops_guidance_transfer_json=$(pick_default_if_exists "$default_current_ops_guidance_transfer_json" "$current_ops_guidance_transfer_json")
standards_grounded_answer_transfer_json=$(pick_default_if_exists "$default_standards_grounded_answer_transfer_json" "$standards_grounded_answer_transfer_json")
operator_decision_transfer_json=$(pick_default_if_exists "$default_operator_decision_transfer_json" "$operator_decision_transfer_json")
multi_artifact_judgment_transfer_json=$(pick_default_if_exists "$default_multi_artifact_judgment_transfer_json" "$multi_artifact_judgment_transfer_json")
long_context_reassessment_transfer_json=$(pick_default_if_exists "$default_long_context_reassessment_transfer_json" "$long_context_reassessment_transfer_json")
long_horizon_timeout_coverage_transfer_json=$(pick_default_if_exists "$default_long_horizon_timeout_coverage_transfer_json" "$long_horizon_timeout_coverage_transfer_json")
document_transfer_json=$(pick_default_if_exists "$default_document_transfer_json" "$document_transfer_json")
remote_ops_transfer_json=$(pick_default_if_exists "$default_remote_ops_transfer_json" "$remote_ops_transfer_json")
remote_deploy_transfer_json=$(pick_default_if_exists "$default_remote_deploy_transfer_json" "$remote_deploy_transfer_json")
remote_multi_host_transfer_json=$(pick_default_if_exists "$default_remote_multi_host_transfer_json" "$remote_multi_host_transfer_json")
remote_multi_host_rollout_transfer_json=$(pick_default_if_exists "$default_remote_multi_host_rollout_transfer_json" "$remote_multi_host_rollout_transfer_json")
remote_bastion_cutover_transfer_json=$(pick_default_if_exists "$default_remote_bastion_cutover_transfer_json" "$remote_bastion_cutover_transfer_json")
remote_boundary_rollout_transfer_json=$(pick_default_if_exists "$default_remote_boundary_rollout_transfer_json" "$remote_boundary_rollout_transfer_json")
remote_boundary_rollback_transfer_json=$(pick_default_if_exists "$default_remote_boundary_rollback_transfer_json" "$remote_boundary_rollback_transfer_json")
remote_boundary_pack_transfer_json=$(pick_default_if_exists "$default_remote_boundary_pack_transfer_json" "$remote_boundary_pack_transfer_json")
remote_release_pack_transfer_json=$(pick_default_if_exists "$default_remote_release_pack_transfer_json" "$remote_release_pack_transfer_json")
gui_visual_transfer_json=$(pick_default_if_exists "$default_gui_visual_transfer_json" "$gui_visual_transfer_json")
gui_screenshot_layout_triage_transfer_json=$(pick_default_if_exists "$default_gui_screenshot_layout_triage_transfer_json" "$gui_screenshot_layout_triage_transfer_json")
gui_login_upload_download_transfer_json=$(pick_default_if_exists "$default_gui_login_upload_download_transfer_json" "$gui_login_upload_download_transfer_json")
gui_state_recovery_pack_transfer_json=$(pick_default_if_exists "$default_gui_state_recovery_pack_transfer_json" "$gui_state_recovery_pack_transfer_json")
dashboard_chart_read_transfer_json=$(pick_default_if_exists "$default_dashboard_chart_read_transfer_json" "$dashboard_chart_read_transfer_json")
terminal_screenshot_debug_transfer_json=$(pick_default_if_exists "$default_terminal_screenshot_debug_transfer_json" "$terminal_screenshot_debug_transfer_json")
before_after_ui_delta_transfer_json=$(pick_default_if_exists "$default_before_after_ui_delta_transfer_json" "$before_after_ui_delta_transfer_json")
terminal_state_recovery_read_transfer_json=$(pick_default_if_exists "$default_terminal_state_recovery_read_transfer_json" "$terminal_state_recovery_read_transfer_json")
diagram_annotation_read_transfer_json=$(pick_default_if_exists "$default_diagram_annotation_read_transfer_json" "$diagram_annotation_read_transfer_json")

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

mkdir -p "$OUT_DIR"
tsv_path="$OUT_DIR/$label-soak.tsv"
json_path="$OUT_DIR/$label-soak.json"
report_path="$OUT_DIR/$label-soak.md"
printf 'iteration\tlabel\trelease_gate_status\tall_pass\tgui_pass\tinteractive_pass\tintelligence_pass\tgate_json\tgate_report\tlog_file\n' > "$tsv_path"

iteration=1
passes=0
failures=0
last_gate_json=""
last_gate_report=""

while [ "$iteration" -le "$iterations" ]; do
  iteration_label="${label}-i${iteration}"
  iteration_log=$(mktemp "${TMPDIR:-/tmp}/artificer-release-gui-soak.XXXXXX")

  set -- "$RELEASE_GATE_SCRIPT" --label "$iteration_label" --gui-profile "$gui_profile" --interactive-gui-profile "$interactive_gui_profile"
  if [ -n "$battery_summary" ]; then
    set -- "$@" --battery-summary "$battery_summary"
  fi
  if [ -n "$holdout_summary" ]; then
    set -- "$@" --holdout-summary "$holdout_summary"
  fi
  if [ -n "$mixed_battery_summary" ]; then
    set -- "$@" --mixed-battery-summary "$mixed_battery_summary"
  fi
  if [ -n "$mixed_holdout_summary" ]; then
    set -- "$@" --mixed-holdout-summary "$mixed_holdout_summary"
  fi
  if [ -n "$mixed_transfer_json" ]; then
    set -- "$@" --mixed-transfer-json "$mixed_transfer_json"
  fi
  if [ -n "$compact_battery_summary" ]; then
    set -- "$@" --compact-battery-summary "$compact_battery_summary"
  fi
  if [ -n "$compact_holdout_summary" ]; then
    set -- "$@" --compact-holdout-summary "$compact_holdout_summary"
  fi
  if [ -n "$compact_transfer_json" ]; then
    set -- "$@" --compact-transfer-json "$compact_transfer_json"
  fi
  if [ -n "$rich_battery_summary" ]; then
    set -- "$@" --rich-battery-summary "$rich_battery_summary"
  fi
  if [ -n "$rich_holdout_summary" ]; then
    set -- "$@" --rich-holdout-summary "$rich_holdout_summary"
  fi
  if [ -n "$rich_transfer_json" ]; then
    set -- "$@" --rich-transfer-json "$rich_transfer_json"
  fi
  if [ -n "$freeform_battery_summary" ]; then
    set -- "$@" --freeform-battery-summary "$freeform_battery_summary"
  fi
  if [ -n "$freeform_holdout_summary" ]; then
    set -- "$@" --freeform-holdout-summary "$freeform_holdout_summary"
  fi
  if [ -n "$freeform_transfer_json" ]; then
    set -- "$@" --freeform-transfer-json "$freeform_transfer_json"
  fi
  if [ -n "$programming_summary_json" ]; then
    set -- "$@" --programming-summary-json "$programming_summary_json"
  fi
  if [ -n "$programming_branchy_json" ]; then
    set -- "$@" --programming-branchy-json "$programming_branchy_json"
  fi
  if [ -n "$programming_auto_branchy_json" ]; then
    set -- "$@" --programming-auto-branchy-json "$programming_auto_branchy_json"
  fi
  if [ -n "$repo_runtime_web_triage_transfer_json" ]; then
    set -- "$@" --repo-runtime-web-triage-transfer-json "$repo_runtime_web_triage_transfer_json"
  fi
  if [ -n "$browser_image_run_investigation_transfer_json" ]; then
    set -- "$@" --browser-image-run-investigation-transfer-json "$browser_image_run_investigation_transfer_json"
  fi
  if [ -n "$tool_failure_handoff_transfer_json" ]; then
    set -- "$@" --tool-failure-handoff-transfer-json "$tool_failure_handoff_transfer_json"
  fi
  if [ -n "$current_api_migration_transfer_json" ]; then
    set -- "$@" --current-api-migration-transfer-json "$current_api_migration_transfer_json"
  fi
  if [ -n "$current_ops_guidance_transfer_json" ]; then
    set -- "$@" --current-ops-guidance-transfer-json "$current_ops_guidance_transfer_json"
  fi
  if [ -n "$standards_grounded_answer_transfer_json" ]; then
    set -- "$@" --standards-grounded-answer-transfer-json "$standards_grounded_answer_transfer_json"
  fi
  if [ -n "$operator_decision_transfer_json" ]; then
    set -- "$@" --operator-decision-transfer-json "$operator_decision_transfer_json"
  fi
  if [ -n "$multi_artifact_judgment_transfer_json" ]; then
    set -- "$@" --multi-artifact-judgment-transfer-json "$multi_artifact_judgment_transfer_json"
  fi
  if [ -n "$long_context_reassessment_transfer_json" ]; then
    set -- "$@" --long-context-reassessment-transfer-json "$long_context_reassessment_transfer_json"
  fi
  if [ -n "$long_horizon_timeout_coverage_transfer_json" ]; then
    set -- "$@" --long-horizon-timeout-coverage-transfer-json "$long_horizon_timeout_coverage_transfer_json"
  fi
  if [ -n "$document_transfer_json" ]; then
    set -- "$@" --document-transfer-json "$document_transfer_json"
  fi
  if [ -n "$remote_ops_transfer_json" ]; then
    set -- "$@" --remote-ops-transfer-json "$remote_ops_transfer_json"
  fi
  if [ -n "$remote_deploy_transfer_json" ]; then
    set -- "$@" --remote-deploy-transfer-json "$remote_deploy_transfer_json"
  fi
  if [ -n "$remote_multi_host_transfer_json" ]; then
    set -- "$@" --remote-multi-host-transfer-json "$remote_multi_host_transfer_json"
  fi
  if [ -n "$remote_multi_host_rollout_transfer_json" ]; then
    set -- "$@" --remote-multi-host-rollout-transfer-json "$remote_multi_host_rollout_transfer_json"
  fi
  if [ -n "$remote_bastion_cutover_transfer_json" ]; then
    set -- "$@" --remote-bastion-cutover-transfer-json "$remote_bastion_cutover_transfer_json"
  fi
  if [ -n "$remote_boundary_rollout_transfer_json" ]; then
    set -- "$@" --remote-boundary-rollout-transfer-json "$remote_boundary_rollout_transfer_json"
  fi
  if [ -n "$remote_boundary_rollback_transfer_json" ]; then
    set -- "$@" --remote-boundary-rollback-transfer-json "$remote_boundary_rollback_transfer_json"
  fi
  if [ -n "$remote_boundary_pack_transfer_json" ]; then
    set -- "$@" --remote-boundary-pack-transfer-json "$remote_boundary_pack_transfer_json"
  fi
  if [ -n "$remote_release_pack_transfer_json" ]; then
    set -- "$@" --remote-release-pack-transfer-json "$remote_release_pack_transfer_json"
  fi
  if [ -n "$gui_visual_transfer_json" ]; then
    set -- "$@" --gui-visual-transfer-json "$gui_visual_transfer_json"
  fi
  if [ -n "$gui_screenshot_layout_triage_transfer_json" ]; then
    set -- "$@" --gui-screenshot-layout-triage-transfer-json "$gui_screenshot_layout_triage_transfer_json"
  fi
  if [ -n "$gui_login_upload_download_transfer_json" ]; then
    set -- "$@" --gui-login-upload-download-transfer-json "$gui_login_upload_download_transfer_json"
  fi
  if [ -n "$gui_state_recovery_pack_transfer_json" ]; then
    set -- "$@" --gui-state-recovery-pack-transfer-json "$gui_state_recovery_pack_transfer_json"
  fi
  if [ -n "$dashboard_chart_read_transfer_json" ]; then
    set -- "$@" --dashboard-chart-read-transfer-json "$dashboard_chart_read_transfer_json"
  fi
  if [ -n "$terminal_screenshot_debug_transfer_json" ]; then
    set -- "$@" --terminal-screenshot-debug-transfer-json "$terminal_screenshot_debug_transfer_json"
  fi
  if [ -n "$before_after_ui_delta_transfer_json" ]; then
    set -- "$@" --before-after-ui-delta-transfer-json "$before_after_ui_delta_transfer_json"
  fi
  if [ -n "$terminal_state_recovery_read_transfer_json" ]; then
    set -- "$@" --terminal-state-recovery-read-transfer-json "$terminal_state_recovery_read_transfer_json"
  fi
  if [ -n "$diagram_annotation_read_transfer_json" ]; then
    set -- "$@" --diagram-annotation-read-transfer-json "$diagram_annotation_read_transfer_json"
  fi
  if [ -n "$gui_result" ]; then
    set -- "$@" --gui-result "$gui_result"
  fi
  if [ -n "$interactive_gui_result" ]; then
    set -- "$@" --interactive-gui-result "$interactive_gui_result"
  fi

  run_command_with_timeout_to_file "$iteration_timeout_sec" "$iteration_log" "$@"
  iteration_status=$?
  iteration_output=$(cat "$iteration_log" 2>/dev/null || true)
  gate_json=$(printf '%s\n' "$iteration_output" | awk '/release-gate\.json$/ {print; exit}')
  gate_report=$(printf '%s\n' "$iteration_output" | awk '/release-gate\.md$/ {print; exit}')
  if [ -z "$gate_json" ] && [ -f "$OUT_DIR/${iteration_label}-release-gate.json" ]; then
    gate_json="$OUT_DIR/${iteration_label}-release-gate.json"
  fi
  if [ -z "$gate_report" ] && [ -f "$OUT_DIR/${iteration_label}-release-gate.md" ]; then
    gate_report="$OUT_DIR/${iteration_label}-release-gate.md"
  fi

  all_pass="false"
  gui_pass="false"
  interactive_pass="false"
  intelligence_pass="false"
  if [ -n "$gate_json" ] && [ -f "$gate_json" ]; then
    all_pass=$(jq -r 'if .all_pass == true then "true" else "false" end' "$gate_json")
    gui_pass=$(jq -r 'if .gui.pass == true then "true" else "false" end' "$gate_json")
    interactive_pass=$(jq -r 'if .intelligence.interactive_session.pass == true then "true" else "false" end' "$gate_json")
    intelligence_pass=$(jq -r 'if .intelligence.pass == true then "true" else "false" end' "$gate_json")
  fi

  if [ "$all_pass" = "true" ] && [ "$iteration_status" -eq 0 ]; then
    passes=$((passes + 1))
  else
    failures=$((failures + 1))
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" \
    "$iteration_label" \
    "$iteration_status" \
    "$all_pass" \
    "$gui_pass" \
    "$interactive_pass" \
    "$intelligence_pass" \
    "$gate_json" \
    "$gate_report" \
    "$iteration_log" >> "$tsv_path"

  last_gate_json="$gate_json"
  last_gate_report="$gate_report"

  if [ "$stop_on_fail" -eq 1 ] && { [ "$iteration_status" -ne 0 ] || [ "$all_pass" != "true" ]; }; then
    break
  fi

  iteration=$((iteration + 1))
done

ran_iterations=$((passes + failures))
pass_rate="0.00"
if [ "$ran_iterations" -gt 0 ]; then
  pass_rate=$(awk -v p="$passes" -v t="$ran_iterations" 'BEGIN { printf "%.2f", (p / t) * 100 }')
fi

jq -Rn \
  --arg label "$label" \
  --arg tsv_path "$tsv_path" \
  --arg last_gate_json "$last_gate_json" \
  --arg last_gate_report "$last_gate_report" \
  --arg gui_profile "$gui_profile" \
  --arg interactive_gui_profile "$interactive_gui_profile" \
  --arg gui_result "$gui_result" \
  --arg interactive_gui_result "$interactive_gui_result" \
  --arg battery_summary "$battery_summary" \
  --arg holdout_summary "$holdout_summary" \
  --arg mixed_battery_summary "$mixed_battery_summary" \
  --arg mixed_holdout_summary "$mixed_holdout_summary" \
  --arg mixed_transfer_json "$mixed_transfer_json" \
  --arg compact_battery_summary "$compact_battery_summary" \
  --arg compact_holdout_summary "$compact_holdout_summary" \
  --arg compact_transfer_json "$compact_transfer_json" \
  --arg rich_battery_summary "$rich_battery_summary" \
  --arg rich_holdout_summary "$rich_holdout_summary" \
  --arg rich_transfer_json "$rich_transfer_json" \
  --argjson iterations_requested "$iterations" \
  --argjson iterations_ran "$ran_iterations" \
  --argjson passes "$passes" \
  --argjson failures "$failures" \
  --arg pass_rate "$pass_rate" '
    {
      label: $label,
      generated_at: (now | todateiso8601),
      gui_profile: $gui_profile,
      interactive_gui_profile: $interactive_gui_profile,
      iterations_requested: $iterations_requested,
      iterations_ran: $iterations_ran,
      passes: $passes,
      failures: $failures,
      pass_rate_percent: ($pass_rate | tonumber),
      reused_summaries: {
        battery_summary: $battery_summary,
        holdout_summary: $holdout_summary,
        mixed_battery_summary: $mixed_battery_summary,
        mixed_holdout_summary: $mixed_holdout_summary,
        mixed_transfer_json: $mixed_transfer_json,
        compact_battery_summary: $compact_battery_summary,
        compact_holdout_summary: $compact_holdout_summary,
        compact_transfer_json: $compact_transfer_json,
        rich_battery_summary: $rich_battery_summary,
        rich_holdout_summary: $rich_holdout_summary,
        rich_transfer_json: $rich_transfer_json,
        gui_result: $gui_result,
        interactive_gui_result: $interactive_gui_result
      },
      tsv_path: $tsv_path,
      last_gate_json: $last_gate_json,
      last_gate_report: $last_gate_report,
      iterations: (
        [inputs | split("\t")] 
        | .[1:]
        | map({
            iteration: (.[0] | tonumber),
            label: .[1],
            release_gate_status: (.[2] | tonumber),
            all_pass: (.[3] == "true"),
            gui_pass: (.[4] == "true"),
            interactive_pass: (.[5] == "true"),
            intelligence_pass: (.[6] == "true"),
            gate_json: .[7],
            gate_report: .[8],
            log_file: .[9]
          })
      )
    }
' "$tsv_path" > "$json_path"

{
  printf '# Release Gate GUI Soak: %s\n\n' "$label"
  printf '## Status\n'
  printf -- '- Iterations requested: %s\n' "$iterations"
  printf -- '- Iterations ran: %s\n' "$ran_iterations"
  printf -- '- Passes: %s\n' "$passes"
  printf -- '- Failures: %s\n' "$failures"
  printf -- '- Pass rate: %s%%\n' "$pass_rate"
  printf -- '- GUI profile: `%s`\n' "$gui_profile"
  printf -- '- Interactive GUI profile: `%s`\n' "$interactive_gui_profile"
  if [ -n "$battery_summary" ] || [ -n "$holdout_summary" ] || [ -n "$mixed_battery_summary" ] || [ -n "$mixed_holdout_summary" ] || [ -n "$mixed_transfer_json" ] || [ -n "$compact_battery_summary" ] || [ -n "$compact_holdout_summary" ] || [ -n "$compact_transfer_json" ] || [ -n "$rich_battery_summary" ] || [ -n "$rich_holdout_summary" ] || [ -n "$rich_transfer_json" ]; then
    printf '\n## Reused Reasoning Artifacts\n'
    [ -n "$battery_summary" ] && printf -- '- Battery summary: `%s`\n' "$battery_summary"
    [ -n "$holdout_summary" ] && printf -- '- Holdout summary: `%s`\n' "$holdout_summary"
    [ -n "$mixed_battery_summary" ] && printf -- '- Mixed battery summary: `%s`\n' "$mixed_battery_summary"
    [ -n "$mixed_holdout_summary" ] && printf -- '- Mixed holdout summary: `%s`\n' "$mixed_holdout_summary"
    [ -n "$mixed_transfer_json" ] && printf -- '- Mixed transfer JSON: `%s`\n' "$mixed_transfer_json"
    [ -n "$compact_battery_summary" ] && printf -- '- Compact battery summary: `%s`\n' "$compact_battery_summary"
    [ -n "$compact_holdout_summary" ] && printf -- '- Compact holdout summary: `%s`\n' "$compact_holdout_summary"
    [ -n "$compact_transfer_json" ] && printf -- '- Compact transfer JSON: `%s`\n' "$compact_transfer_json"
    [ -n "$rich_battery_summary" ] && printf -- '- Rich battery summary: `%s`\n' "$rich_battery_summary"
    [ -n "$rich_holdout_summary" ] && printf -- '- Rich holdout summary: `%s`\n' "$rich_holdout_summary"
    [ -n "$rich_transfer_json" ] && printf -- '- Rich transfer JSON: `%s`\n' "$rich_transfer_json"
    [ -n "$gui_result" ] && printf -- '- GUI result: `%s`\n' "$gui_result"
    [ -n "$interactive_gui_result" ] && printf -- '- Interactive GUI result: `%s`\n' "$interactive_gui_result"
  fi
  printf '\n## Iterations\n'
  printf '| Iteration | Status | All Pass | GUI | Interactive | Intelligence | Gate JSON | Gate Report |\n'
  printf '|---|---:|---|---|---|---|---|---|\n'
  awk -F '\t' 'NR>1 {printf "| %s | %s | %s | %s | %s | %s | `%s` | `%s` |\n", $1, $3, $4, $5, $6, $7, $8, $9}' "$tsv_path"
  printf '\n## Artifacts\n'
  printf -- '- TSV: `%s`\n' "$tsv_path"
  printf -- '- JSON: `%s`\n' "$json_path"
  printf -- '- Last gate JSON: `%s`\n' "$last_gate_json"
  printf -- '- Last gate report: `%s`\n' "$last_gate_report"
} > "$report_path"

printf '%s\n' "$json_path"
printf '%s\n' "$report_path"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
