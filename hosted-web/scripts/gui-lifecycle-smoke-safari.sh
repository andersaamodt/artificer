#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SITE_ROOT="$PROJECT_ROOT/hosted-web"
. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs
API="$SITE_ROOT/cgi/artificer-api"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"

if [ ! -x "$API" ]; then
  echo "API endpoint is not executable: $API" >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required for Safari automation." >&2
  exit 1
fi
if ! command -v safaridriver >/dev/null 2>&1; then
  echo "safaridriver is required for Safari automation." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for GUI smoke checks." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for local CGI server." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for smoke result parsing." >&2
  exit 1
fi

run_command_with_timeout() {
  timeout_seconds=$1
  shift
  timeout_stdin_payload=$(mktemp "${TMPDIR:-/tmp}/artificer-timeout-stdin.XXXXXX")
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

reset_safari_for_automation() {
  run_command_with_timeout 30 osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Safari"
  if it is running then
    quit
  end if
end tell
delay 0.6
tell application "Safari"
  activate
end tell
delay 0.6
APPLESCRIPT
  pkill -f '^safaridriver( |$)' >/dev/null 2>&1 || true
  killall Safari >/dev/null 2>&1 || true
  sleep 1
}

pick_free_port() {
  python3 - <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

safari_continue_webdriver_session_if_needed() {
  run_command_with_timeout 20 osascript -l JavaScript <<'JXA' >/dev/null 2>&1 || true
const se = Application('System Events');
const p = se.processes.byName('Safari');
let clicked = false;
try {
  const windows = p.windows();
  for (let i = 0; i < windows.length; i += 1) {
    const buttons = windows[i].buttons();
    for (let j = 0; j < buttons.length; j += 1) {
      if (buttons[j].name() === 'Continue Session') {
        buttons[j].click();
        clicked = true;
      }
    }
  }
} catch (_err) {
  // best effort
}
if (clicked) {
  delay(0.5);
}
JXA
}

label="gui-lifecycle-smoke-$(date +%Y%m%d-%H%M%S)"
port="${ARTIFICER_GUI_LIFECYCLE_SMOKE_PORT:-}"
workspace_name="gui-lifecycle-$label"
decision_conversation_title="Lifecycle decision smoke $label"
approval_conversation_title="Lifecycle approval smoke $label"
site_name="artificer-lifecycle-$label"

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      workspace_name="gui-lifecycle-$label"
      decision_conversation_title="Lifecycle decision smoke $label"
      approval_conversation_title="Lifecycle approval smoke $label"
      site_name="artificer-lifecycle-$label"
      shift 2
      ;;
    --port)
      port=$2
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$port" ]; then
  port=$(pick_free_port)
fi

mkdir -p "$OUT_DIR"
server_log="$OUT_DIR/$label-lifecycle-server.log"
driver_log="$OUT_DIR/$label-lifecycle-safaridriver.log"
result_json="$OUT_DIR/$label-lifecycle-result.json"
report_md="$OUT_DIR/$label-lifecycle-report.md"
setup_js=$(mktemp "${TMPDIR:-/tmp}/artificer-lifecycle-setup.XXXXXX")
verify_js=$(mktemp "${TMPDIR:-/tmp}/artificer-lifecycle-verify.XXXXXX")
workspace_path=$(mktemp -d "${TMPDIR:-/tmp}/artificer-lifecycle-workspace.XXXXXX")
site_state_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-lifecycle-site-state.XXXXXX")

cleanup() {
  if [ -n "${driver_pid:-}" ] && kill -0 "$driver_pid" 2>/dev/null; then
    kill "$driver_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$driver_pid" 2>/dev/null; then
      kill -9 "$driver_pid" 2>/dev/null || true
    fi
  fi
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$server_pid" 2>/dev/null; then
      kill -9 "$server_pid" 2>/dev/null || true
    fi
  fi
  rm -f "$setup_js" "$verify_js"
  if [ -n "${workspace_path:-}" ] && [ -d "$workspace_path" ]; then
    rm -rf "$workspace_path" 2>/dev/null || true
  fi
  if [ -n "${site_state_root:-}" ] && [ -d "$site_state_root" ]; then
    rm -rf "$site_state_root" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

urlenc() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote_plus(sys.argv[1]), end="")
PY
}

json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

post_http_json() {
  body=$1
  raw=$(curl -fsS -X POST --data "$body" "http://127.0.0.1:$port/cgi/artificer-api")
  json=$(printf '%s' "$raw" | json_only)
  if [ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ]; then
    return 1
  fi
  ok=$(printf '%s' "$json" | jq -r 'if (type=="object" and has("success")) then (.success|tostring) else "true" end' 2>/dev/null || printf '%s' "false")
  if [ "$ok" = "false" ]; then
    return 1
  fi
  printf '%s' "$json"
}

(
  cd "$SITE_ROOT"
  export WIZARDRY_SITES_DIR="$site_state_root"
  export WIZARDRY_SITE_NAME="$site_name"
  python3 - "$port" <<'PY'
from http.server import CGIHTTPRequestHandler, ThreadingHTTPServer
import sys

port = int(sys.argv[1])

class ArtificerCgiHandler(CGIHTTPRequestHandler):
    cgi_directories = ["/cgi", "/cgi-bin", "/htbin"]

server = ThreadingHTTPServer(("127.0.0.1", port), ArtificerCgiHandler)
try:
    server.serve_forever()
finally:
    server.server_close()
PY
) >"$server_log" 2>&1 &
server_pid=$!

health_url="http://127.0.0.1:$port/pages/index.html"
ready=0
for _ in $(seq 1 80); do
  if curl -fsS "$health_url" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.15
done
if [ "$ready" -ne 1 ]; then
  echo "Local CGI server did not become ready. See $server_log" >&2
  exit 1
fi

add_json=$(post_http_json "action=add_workspace&path=$(urlenc "$workspace_path")&name=$(urlenc "$workspace_name")" || true)
workspace_id=$(printf '%s' "$add_json" | jq -r '.workspace.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$workspace_id" ]; then
  echo "Failed to seed workspace for lifecycle smoke." >&2
  exit 1
fi

decision_conversation_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$decision_conversation_title")" || true)
decision_conversation_id=$(printf '%s' "$decision_conversation_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$decision_conversation_id" ]; then
  echo "Failed to seed decision conversation for lifecycle smoke." >&2
  exit 1
fi

approval_conversation_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$approval_conversation_title")" || true)
approval_conversation_id=$(printf '%s' "$approval_conversation_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$approval_conversation_id" ]; then
  echo "Failed to seed approval conversation for lifecycle smoke." >&2
  exit 1
fi

cat > "$setup_js" <<'JS'
return (function () {
  function out(payload) {
    try {
      return JSON.stringify(payload || {});
    } catch (_jsonErr) {
      return "{\"success\":false,\"error\":\"serialize_failed\"}";
    }
  }
  function clickNode(node) {
    if (!node) {
      return;
    }
    if (typeof node.click === "function") {
      node.click();
      return;
    }
    var ev = document.createEvent("MouseEvents");
    ev.initEvent("click", true, true);
    node.dispatchEvent(ev);
  }
  function postActionSync(bodyText) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      xhr.send(String(bodyText || ""));
      var raw = String(xhr.responseText || "");
      var idx = raw.indexOf("{");
      if (idx >= 0) {
        raw = raw.slice(idx);
      }
      return JSON.parse(raw);
    } catch (_xhrErr) {
      return null;
    }
  }
  function encodeValue(text) {
    return encodeURIComponent(String(text || ""));
  }

  var workspaceId = "__WORKSPACE_ID__";
  var decisionConversationId = "__DECISION_CONVERSATION_ID__";
  var approvalConversationId = "__APPROVAL_CONVERSATION_ID__";
  var decisionQuestion = "Choose rollout path for lifecycle smoke";
  var decisionOptions = "Ship now|Canary first|Pause for validation";

  try {
    localStorage.removeItem("artificer.lifecycle.stage");
    localStorage.removeItem("artificer.lifecycle.workspaceId");
    localStorage.removeItem("artificer.lifecycle.decisionConversationId");
    localStorage.removeItem("artificer.lifecycle.approvalConversationId");
    localStorage.removeItem("artificer.lifecycle.basePathname");
    localStorage.removeItem("artificer.lifecycle.check.decision_visible");
    localStorage.removeItem("artificer.lifecycle.check.decision_focus_persisted");
    localStorage.removeItem("artificer.lifecycle.check.decision_submit_cleared");
    localStorage.removeItem("artificer.lifecycle.check.approval_visible");
    localStorage.removeItem("artificer.lifecycle.check.approval_focus_persisted");
    localStorage.removeItem("artificer.lifecycle.check.approval_reload_persisted");
    localStorage.removeItem("artificer.lifecycle.check.approval_clear_cleared");
    localStorage.removeItem("artificer.lifecycle.check.queue_not_stuck");
    for (var i = localStorage.length - 1; i >= 0; i -= 1) {
      var key = String(localStorage.key(i) || "");
      if (key.indexOf("artificer.lifecycle.wait.") === 0) {
        localStorage.removeItem(key);
      }
    }
  } catch (_storageClearErr) {
    // best effort
  }

  var decisionConversationRow = document.querySelector(".conversation-row[data-workspace-id='" + workspaceId + "'][data-conversation-id='" + decisionConversationId + "']");
  if (!decisionConversationRow) {
    return out({ success: false, error: "decision_conversation_row_missing" });
  }
  clickNode(decisionConversationRow);

  var decisionResponse = postActionSync(
    "action=assay_inject_decision_request" +
    "&workspace_id=" + encodeValue(workspaceId) +
    "&conversation_id=" + encodeValue(decisionConversationId) +
    "&question=" + encodeValue(decisionQuestion) +
    "&options=" + encodeValue(decisionOptions)
  );
  if (!decisionResponse || !decisionResponse.success) {
    return out({
      success: false,
      error: "inject_decision_failed",
      detail: String((decisionResponse && decisionResponse.error) || "")
    });
  }

  try {
    localStorage.setItem("artificer.lifecycle.stage", "decision_injected");
    localStorage.setItem("artificer.lifecycle.workspaceId", workspaceId);
    localStorage.setItem("artificer.lifecycle.decisionConversationId", decisionConversationId);
    localStorage.setItem("artificer.lifecycle.approvalConversationId", approvalConversationId);
    localStorage.setItem("artificer.lifecycle.basePathname", String(window.location.pathname || ""));
  } catch (_storageWriteErr) {
    // best effort
  }

  try {
    window.dispatchEvent(new Event("focus"));
  } catch (_focusErr) {
    // best effort
  }

  return out({ success: true });
})();
JS

cat > "$verify_js" <<'JS'
return (function () {
  function out(payload) {
    try {
      return JSON.stringify(payload || {});
    } catch (_jsonErr) {
      return "{\"success\":false,\"error\":\"serialize_failed\"}";
    }
  }
  function readKey(name) {
    try {
      return String(localStorage.getItem(name) || "");
    } catch (_err) {
      return "";
    }
  }
  function writeKey(name, value) {
    try {
      localStorage.setItem(name, String(value || ""));
    } catch (_err) {
      // best effort
    }
  }
  function clearKey(name) {
    try {
      localStorage.removeItem(name);
    } catch (_err) {
      // best effort
    }
  }
  function clickNode(node) {
    if (!node) {
      return;
    }
    if (typeof node.click === "function") {
      node.click();
      return;
    }
    var ev = document.createEvent("MouseEvents");
    ev.initEvent("click", true, true);
    node.dispatchEvent(ev);
  }
  function postActionSync(bodyText) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      xhr.send(String(bodyText || ""));
      var raw = String(xhr.responseText || "");
      var idx = raw.indexOf("{");
      if (idx >= 0) {
        raw = raw.slice(idx);
      }
      return JSON.parse(raw);
    } catch (_xhrErr) {
      return null;
    }
  }
  function getStateSync() {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", "/cgi/artificer-api?action=state&level=light&cached=0&_ts=" + String(Date.now()), false);
      xhr.send(null);
      var raw = String(xhr.responseText || "");
      var idx = raw.indexOf("{");
      if (idx >= 0) {
        raw = raw.slice(idx);
      }
      return JSON.parse(raw);
    } catch (_xhrErr) {
      return null;
    }
  }
  function encodeValue(text) {
    return encodeURIComponent(String(text || ""));
  }
  function isVisible(node) {
    if (!node) {
      return false;
    }
    if (node.classList && node.classList.contains("hidden")) {
      return false;
    }
    return true;
  }
  function lifecycleConversationState(stateResponse, workspaceId, conversationId) {
    var workspaces = stateResponse && Array.isArray(stateResponse.workspaces) ? stateResponse.workspaces : [];
    for (var i = 0; i < workspaces.length; i += 1) {
      var workspace = workspaces[i] || {};
      if (String(workspace.id || "") !== String(workspaceId || "")) {
        continue;
      }
      var conversations = Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j] || {};
        if (String(conversation.id || "") === String(conversationId || "")) {
          return conversation;
        }
      }
    }
    return null;
  }
  function ensureConversationSelected(workspaceId, conversationId) {
    var selector = ".conversation-row[data-workspace-id='" + String(workspaceId || "") + "'][data-conversation-id='" + String(conversationId || "") + "']";
    var row = document.querySelector(selector);
    if (!row) {
      return false;
    }
    if (
      !row.classList.contains("is-active") &&
      !row.classList.contains("active") &&
      String(row.getAttribute("aria-current") || "") !== "true"
    ) {
      clickNode(row);
    }
    return true;
  }
  function isConversationSelected(workspaceId, conversationId) {
    var selector = ".conversation-row[data-workspace-id='" + String(workspaceId || "") + "'][data-conversation-id='" + String(conversationId || "") + "']";
    var row = document.querySelector(selector);
    var rowActive = !!(
      row &&
      (
        row.classList.contains("is-active") ||
        row.classList.contains("active") ||
        String(row.getAttribute("aria-current") || "") === "true"
      )
    );
    var routeHash = String(window.location.hash || "");
    var hashActive = !!(
      workspaceId &&
      conversationId &&
      routeHash.indexOf(String(workspaceId || "")) !== -1 &&
      routeHash.indexOf(String(conversationId || "")) !== -1
    );
    return rowActive || hashActive;
  }
  function chooseFirstDecisionOption() {
    var optionsWrap = document.getElementById("decision-request-options");
    if (!optionsWrap) {
      return false;
    }
    var first = optionsWrap.querySelector("input[name='decision-request-choice']");
    if (!first) {
      return false;
    }
    if (!first.checked) {
      first.checked = true;
      try {
        var ev = document.createEvent("Event");
        ev.initEvent("change", true, true);
        first.dispatchEvent(ev);
      } catch (_changeErr) {
        // best effort
      }
    }
    return true;
  }
  function submitDecisionViaForm() {
    var form = document.getElementById("decision-request-form");
    var submit = document.getElementById("decision-request-submit");
    if (!form || !submit) {
      return false;
    }
    if (submit.disabled) {
      return false;
    }
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit(submit);
      return true;
    }
    clickNode(submit);
    return true;
  }
  function stageWaitOrFail(stageName, errorCode, extra) {
    var key = "artificer.lifecycle.wait." + String(stageName || "");
    var rawCount = readKey(key);
    var count = Number(rawCount || "0");
    if (!isFinite(count) || count < 0) {
      count = 0;
    }
    count += 1;
    writeKey(key, String(count));
    if (count > 120) {
      var payload = {
        success: false,
        error: String(errorCode || "lifecycle_stage_timeout"),
        stage: String(stageName || ""),
        wait_iterations: count,
        queue_status: queueStatus
      };
      if (extra && typeof extra === "object") {
        for (var keyName in extra) {
          if (Object.prototype.hasOwnProperty.call(extra, keyName)) {
            payload[keyName] = extra[keyName];
          }
        }
      }
      return out(payload);
    }
    return "";
  }
  function clearStageWait(stageName) {
    clearKey("artificer.lifecycle.wait." + String(stageName || ""));
  }
  function dispatchBlurFocus() {
    try {
      window.dispatchEvent(new Event("blur"));
    } catch (_blurErr) {
      // best effort
    }
    try {
      window.dispatchEvent(new Event("focus"));
    } catch (_focusErr) {
      // best effort
    }
  }

  var workspaceId = readKey("artificer.lifecycle.workspaceId");
  var decisionConversationId = readKey("artificer.lifecycle.decisionConversationId");
  var approvalConversationId = readKey("artificer.lifecycle.approvalConversationId");
  var basePathname = readKey("artificer.lifecycle.basePathname");
  var stage = readKey("artificer.lifecycle.stage");
  if (!workspaceId || !decisionConversationId || !approvalConversationId) {
    return out({ success: false, error: "missing_lifecycle_ids" });
  }

  var decisionInline = document.getElementById("decision-request-inline");
  var decisionSubmit = document.getElementById("decision-request-submit");
  var approvalInline = document.getElementById("command-approval-inline");
  var approvalStage = (
    stage === "approval_injected" ||
    stage === "approval_reload_requested" ||
    stage === "approval_cleared"
  );
  var activeConversationId = approvalStage ? approvalConversationId : decisionConversationId;
  var queueStatus = "";
  var conversationSummary = lifecycleConversationState(getStateSync(), workspaceId, activeConversationId);
  if (conversationSummary) {
    queueStatus = String(conversationSummary.queue_last_status || "");
  }
  ensureConversationSelected(workspaceId, activeConversationId);

  if (stage === "decision_injected") {
    if (!isVisible(decisionInline)) {
      dispatchBlurFocus();
      return stageWaitOrFail("decision_injected", "decision_not_visible_after_injection");
    }
    clearStageWait("decision_injected");
    writeKey("artificer.lifecycle.check.decision_visible", "1");
    dispatchBlurFocus();
    writeKey("artificer.lifecycle.stage", "decision_focus_checked");
    return "";
  }

  if (stage === "decision_focus_checked") {
    if (!isVisible(decisionInline)) {
      return out({ success: false, error: "decision_hidden_after_focus_refresh" });
    }
    writeKey("artificer.lifecycle.check.decision_focus_persisted", "1");
    chooseFirstDecisionOption();
    if (!decisionSubmit || decisionSubmit.disabled) {
      return stageWaitOrFail("decision_focus_checked_submit", "decision_submit_never_enabled");
    }
    clearStageWait("decision_focus_checked_submit");
    if (!submitDecisionViaForm()) {
      return stageWaitOrFail("decision_focus_checked_submit", "decision_submit_not_triggered");
    }
    writeKey("artificer.lifecycle.stage", "decision_submitted");
    return "";
  }

  if (stage === "decision_submitted") {
    if (isVisible(decisionInline)) {
      return stageWaitOrFail("decision_submitted", "decision_inline_not_cleared_after_submit");
    }
    clearStageWait("decision_submitted");
    var decisionState = getStateSync();
    var decisionConversation = lifecycleConversationState(decisionState, workspaceId, decisionConversationId);
    var decisionStatus = decisionConversation ? String(decisionConversation.queue_last_status || "") : "";
    var decisionPresent = !!(decisionConversation && decisionConversation.decision_request);
    if (decisionPresent || decisionStatus === "awaiting_decision") {
      return stageWaitOrFail("decision_submitted_backend", "decision_not_cleared_backend", {
        latest_queue_status: decisionStatus,
        decision_request_present: decisionPresent
      });
    }
    clearStageWait("decision_submitted_backend");
    writeKey("artificer.lifecycle.check.decision_submit_cleared", "1");
    postActionSync(
      "action=assay_clear_lifecycle_requests" +
      "&workspace_id=" + encodeValue(workspaceId) +
      "&conversation_id=" + encodeValue(decisionConversationId)
    );
    var approvalResponse = postActionSync(
      "action=assay_inject_approval_request" +
      "&workspace_id=" + encodeValue(workspaceId) +
      "&conversation_id=" + encodeValue(approvalConversationId) +
      "&command=" + encodeValue("./deploy.sh --env production") +
      "&reason=" + encodeValue("lifecycle-smoke")
    );
    if (!approvalResponse || !approvalResponse.success) {
      return out({
        success: false,
        error: "inject_approval_failed",
        detail: String((approvalResponse && approvalResponse.error) || "")
      });
    }
    ensureConversationSelected(workspaceId, approvalConversationId);
    dispatchBlurFocus();
    if (!isConversationSelected(workspaceId, approvalConversationId)) {
      return stageWaitOrFail("approval_conversation_selected", "approval_conversation_not_selected_after_injection");
    }
    clearStageWait("approval_conversation_selected");
    writeKey("artificer.lifecycle.stage", "approval_injected");
    return "";
  }

  if (stage === "approval_injected") {
    ensureConversationSelected(workspaceId, approvalConversationId);
    if (!isConversationSelected(workspaceId, approvalConversationId)) {
      dispatchBlurFocus();
      return stageWaitOrFail("approval_injected_selected", "approval_conversation_not_selected");
    }
    clearStageWait("approval_injected_selected");
    if (!isVisible(approvalInline)) {
      dispatchBlurFocus();
      return stageWaitOrFail("approval_injected", "approval_not_visible_after_injection");
    }
    clearStageWait("approval_injected");
    writeKey("artificer.lifecycle.check.approval_visible", "1");
    dispatchBlurFocus();
    writeKey("artificer.lifecycle.check.approval_focus_persisted", "1");
    writeKey("artificer.lifecycle.stage", "approval_reload_requested");
    location.reload();
    return "";
  }

  if (stage === "approval_reload_requested") {
    var pathnameAfterReload = String(window.location.pathname || "");
    if (basePathname && pathnameAfterReload && pathnameAfterReload !== basePathname) {
      return out({
        success: false,
        error: "route_pathname_changed_after_reload",
        initial_pathname: basePathname,
        current_pathname: pathnameAfterReload,
        current_hash: String(window.location.hash || "")
      });
    }
    if (!isConversationSelected(workspaceId, approvalConversationId)) {
      ensureConversationSelected(workspaceId, approvalConversationId);
      dispatchBlurFocus();
      return stageWaitOrFail("approval_reload_requested_selected", "approval_conversation_not_selected_after_reload");
    }
    clearStageWait("approval_reload_requested_selected");
    if (!isVisible(approvalInline)) {
      var reloadedState = getStateSync();
      var reloadedConversation = lifecycleConversationState(reloadedState, workspaceId, approvalConversationId);
      var reloadedStatus = reloadedConversation ? String(reloadedConversation.queue_last_status || "") : "";
      var reloadedApprovalPresent = !!(reloadedConversation && reloadedConversation.approval_request);
      ensureConversationSelected(workspaceId, approvalConversationId);
      dispatchBlurFocus();
      return stageWaitOrFail("approval_reload_requested_visible", "approval_hidden_after_reload", {
        reloaded_queue_status: reloadedStatus,
        reloaded_approval_present: reloadedApprovalPresent
      });
    }
    clearStageWait("approval_reload_requested_visible");
    writeKey("artificer.lifecycle.check.approval_reload_persisted", "1");
    postActionSync(
      "action=assay_clear_lifecycle_requests" +
      "&workspace_id=" + encodeValue(workspaceId) +
      "&conversation_id=" + encodeValue(approvalConversationId)
    );
    writeKey("artificer.lifecycle.stage", "approval_cleared");
    return "";
  }

  if (stage === "approval_cleared") {
    if (isVisible(approvalInline)) {
      return stageWaitOrFail("approval_cleared_inline", "approval_inline_not_cleared_after_clear");
    }
    clearStageWait("approval_cleared_inline");
    var latestState = getStateSync();
    var latestConversation = lifecycleConversationState(latestState, workspaceId, approvalConversationId);
    var latestStatus = latestConversation ? String(latestConversation.queue_last_status || "") : "";
    var approvalPresent = latestConversation && latestConversation.approval_request;
    if (latestStatus === "awaiting_approval" || approvalPresent) {
      return stageWaitOrFail("approval_cleared_queue", "approval_queue_not_advancing", {
        latest_queue_status: latestStatus,
        latest_approval_present: !!approvalPresent
      });
    }
    clearStageWait("approval_cleared_queue");
    writeKey("artificer.lifecycle.check.approval_clear_cleared", "1");
    writeKey("artificer.lifecycle.check.queue_not_stuck", "1");
    writeKey("artificer.lifecycle.stage", "done");
    return "";
  }

  if (stage === "done") {
    var checks = [
      {
        name: "decision request visible after injection",
        pass: readKey("artificer.lifecycle.check.decision_visible") === "1",
        detail: "decision inline surfaced"
      },
      {
        name: "decision request persists after focus refresh",
        pass: readKey("artificer.lifecycle.check.decision_focus_persisted") === "1",
        detail: "decision inline survived blur/focus"
      },
      {
        name: "decision submit clears inline prompt",
        pass: readKey("artificer.lifecycle.check.decision_submit_cleared") === "1",
        detail: "decision inline hidden after submit"
      },
      {
        name: "approval request visible after injection",
        pass: readKey("artificer.lifecycle.check.approval_visible") === "1",
        detail: "approval inline surfaced"
      },
      {
        name: "approval request persists after focus refresh",
        pass: readKey("artificer.lifecycle.check.approval_focus_persisted") === "1",
        detail: "approval inline survived blur/focus"
      },
      {
        name: "approval request persists after full reload",
        pass: readKey("artificer.lifecycle.check.approval_reload_persisted") === "1",
        detail: "approval inline survived location.reload"
      },
      {
        name: "approval clear clears inline prompt",
        pass: readKey("artificer.lifecycle.check.approval_clear_cleared") === "1",
        detail: "approval inline hidden after deterministic clear"
      },
      {
        name: "queue status not stuck in awaiting_approval",
        pass: readKey("artificer.lifecycle.check.queue_not_stuck") === "1",
        detail: "conversation resumed beyond approval hold"
      },
      {
        name: "thread route keeps app pathname stable across reload",
        pass: !basePathname || String(window.location.pathname || "") === basePathname,
        detail: "initial=" + String(basePathname || "") + " current=" + String(window.location.pathname || "")
      },
      {
        name: "thread route uses hash-based selection after reload",
        pass: String(window.location.hash || "").indexOf("#/") === 0,
        detail: String(window.location.hash || "")
      }
    ];
    var success = true;
    for (var i = 0; i < checks.length; i += 1) {
      if (!checks[i].pass) {
        success = false;
        break;
      }
    }
    clearKey("artificer.lifecycle.stage");
    clearKey("artificer.lifecycle.workspaceId");
    clearKey("artificer.lifecycle.decisionConversationId");
    clearKey("artificer.lifecycle.approvalConversationId");
    clearKey("artificer.lifecycle.basePathname");
    return out({
      success: success,
      checks: checks,
      queue_status: queueStatus
    });
  }

  if (!stage) {
    return "";
  }

  return out({
    success: false,
    error: "unknown_stage",
    stage: stage,
    queue_status: queueStatus
  });
})();
JS

safe_workspace_id=$(printf '%s' "$workspace_id" | sed 's/["\\]/\\&/g')
safe_decision_conversation_id=$(printf '%s' "$decision_conversation_id" | sed 's/["\\]/\\&/g')
safe_approval_conversation_id=$(printf '%s' "$approval_conversation_id" | sed 's/["\\]/\\&/g')
sed -i '' "s/__WORKSPACE_ID__/$safe_workspace_id/g" "$setup_js"
sed -i '' "s/__DECISION_CONVERSATION_ID__/$safe_decision_conversation_id/g" "$setup_js"
sed -i '' "s/__APPROVAL_CONVERSATION_ID__/$safe_approval_conversation_id/g" "$setup_js"

app_url="http://127.0.0.1:$port/pages/index.html"

run_lifecycle_smoke_once() {
  driver_port=$(pick_free_port)
  : > "$driver_log"
  safaridriver -p "$driver_port" >"$driver_log" 2>&1 &
  driver_pid=$!
  set +e
  lifecycle_output=$(run_command_with_timeout 330 python3 - "$driver_port" "$app_url" "$setup_js" "$verify_js" 2>>"$driver_log" <<'PY'
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

driver_port = sys.argv[1]
app_url = sys.argv[2]
setup_path = sys.argv[3]
verify_path = sys.argv[4]
base_url = f"http://127.0.0.1:{driver_port}"


class WebDriverCommandError(RuntimeError):
    def __init__(self, error, message="", stacktrace="", response=None):
        self.error = str(error or "webdriver_error")
        self.response = response or {}
        details = str(message or self.error)
        super().__init__(details)
        self.stacktrace = str(stacktrace or "")


def safari_continue_session_if_needed():
    script = r'''
const se = Application('System Events');
const p = se.processes.byName('Safari');
let clicked = false;
try {
  const windows = p.windows();
  for (let i = 0; i < windows.length; i += 1) {
    const buttons = windows[i].buttons();
    for (let j = 0; j < buttons.length; j += 1) {
      if (buttons[j].name() === 'Continue Session') {
        buttons[j].click();
        clicked = true;
      }
    }
  }
} catch (_err) {
}
if (clicked) {
  delay(0.5);
}
console.log(clicked ? 'clicked' : 'not-found');
'''
    try:
        completed = subprocess.run(
            ["osascript", "-l", "JavaScript"],
            input=script,
            capture_output=True,
            text=True,
            timeout=20,
        )
        return "clicked" in (completed.stdout or "")
    except Exception:
        return False


def webdriver_request(method, path, payload=None, timeout=15, allow_continue_retry=False):
    headers = {}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(base_url + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            return {"value": {"error": "http_error", "message": raw}}
        parsed_value = parsed.get("value") if isinstance(parsed, dict) else None
        if isinstance(parsed_value, dict) and parsed_value.get("error"):
            if allow_continue_retry and safari_continue_session_if_needed():
                time.sleep(0.5)
                return webdriver_request(method, path, payload, timeout, False)
            raise WebDriverCommandError(
                parsed_value.get("error"),
                parsed_value.get("message"),
                parsed_value.get("stacktrace"),
                parsed,
            )
        return parsed
    except Exception:
        if allow_continue_retry and safari_continue_session_if_needed():
            time.sleep(0.5)
            return webdriver_request(method, path, payload, timeout, False)
        raise
    if not raw.strip():
        return {"value": None}
    parsed = json.loads(raw)
    parsed_value = parsed.get("value") if isinstance(parsed, dict) else None
    if isinstance(parsed_value, dict) and parsed_value.get("error"):
        if allow_continue_retry and safari_continue_session_if_needed():
            time.sleep(0.5)
            return webdriver_request(method, path, payload, timeout, False)
        raise WebDriverCommandError(
            parsed_value.get("error"),
            parsed_value.get("message"),
            parsed_value.get("stacktrace"),
            parsed,
        )
    return parsed


def wait_for_driver_ready():
    started = time.time()
    while (time.time() - started) < 15:
        try:
            webdriver_request("GET", "/status", timeout=5)
            return
        except Exception:
            time.sleep(0.25)
    raise RuntimeError("safaridriver did not become ready")


def execute_script(session_id, script_text, timeout=15):
    return webdriver_request(
        "POST",
        f"/session/{session_id}/execute/sync",
        {"script": script_text, "args": []},
        timeout=timeout,
        allow_continue_retry=True,
    )


def execute_script_until_success(session_id, script_text, timeout=15, total_timeout=20):
    started = time.time()
    last_error = None
    while (time.time() - started) < total_timeout:
        try:
            return execute_script(session_id, script_text, timeout)
        except WebDriverCommandError as exc:
            last_error = exc
            if exc.error not in ("no such window", "javascript error"):
                raise
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    if last_error is not None:
        raise last_error
    raise RuntimeError("Timed out waiting for execute_script success")


def text_value(response):
    value = response.get("value")
    if value is None:
        return ""
    return str(value)


diagnostic_script = r'''
var payload = {
  stage: String(localStorage.getItem("artificer.lifecycle.stage") || ""),
  pathname: String(window.location.pathname || ""),
  hash: String(window.location.hash || ""),
  decisionVisible: !!(document.getElementById("decision-request-inline") && !document.getElementById("decision-request-inline").classList.contains("hidden")),
  approvalVisible: !!(document.getElementById("command-approval-inline") && !document.getElementById("command-approval-inline").classList.contains("hidden")),
  waits: {}
};
for (var i = 0; i < localStorage.length; i += 1) {
  var key = String(localStorage.key(i) || "");
  if (key.indexOf("artificer.lifecycle.wait.") === 0) {
    payload.waits[key.slice("artificer.lifecycle.wait.".length)] = String(localStorage.getItem(key) || "");
  }
}
return JSON.stringify(payload);
'''


wait_for_driver_ready()
session_id = ""
try:
    safari_continue_session_if_needed()
    session_response = webdriver_request(
        "POST",
        "/session",
        {"capabilities": {"alwaysMatch": {"browserName": "safari"}}},
        timeout=60,
        allow_continue_retry=True,
    )
    session_value = session_response.get("value") or {}
    session_id = session_value.get("sessionId") or ""
    if not session_id:
        raise RuntimeError(session_value.get("message") or "Unable to create Safari WebDriver session")

    safari_continue_session_if_needed()
    webdriver_request(
        "POST",
        f"/session/{session_id}/url",
        {"url": app_url},
        timeout=30,
        allow_continue_retry=True,
    )

    boot_started = time.time()
    boot_state = ""
    while (time.time() - boot_started) < 40:
        try:
            boot_state = text_value(execute_script(session_id, 'return String(window.__artificerBooted || "");', 20))
        except Exception:
            time.sleep(0.2)
            continue
        if boot_state == "true":
            break
        time.sleep(0.2)
    if boot_state != "true":
        raise RuntimeError("Timed out waiting for Artificer boot")

    with open(setup_path, "r", encoding="utf-8") as setup_file:
        setup_script = setup_file.read()
    setup_text = text_value(execute_script_until_success(session_id, setup_script, 20, 25))
    if setup_text.strip() and '"success":false' in setup_text:
        print(setup_text)
        sys.exit(0)

    with open(verify_path, "r", encoding="utf-8") as verify_file:
        verify_script = verify_file.read()
    verify_started = time.time()
    verify_attempt = 0
    while (time.time() - verify_started) < 160:
        verify_attempt += 1
        try:
            verify_text = text_value(execute_script(session_id, verify_script, 60))
        except Exception:
            time.sleep(0.25)
            continue
        if verify_text.strip():
            print(verify_text)
            sys.exit(0)
        if verify_attempt % 20 == 0:
            try:
                diagnostic_snapshot = text_value(execute_script_until_success(session_id, diagnostic_script, 20, 10))
            except Exception as exc:
                diagnostic_snapshot = "diagnostic-error:" + str(exc)
            sys.stderr.write("verify-wait[%s]: %s\n" % (verify_attempt, diagnostic_snapshot))
            sys.stderr.flush()
        time.sleep(0.25)
    diagnostic_text = ""
    try:
        diagnostic_text = text_value(execute_script_until_success(session_id, diagnostic_script, 20, 10))
    except Exception:
        diagnostic_text = ""
    if diagnostic_text.strip():
        raise RuntimeError("Timed out waiting for lifecycle smoke verification: " + diagnostic_text)
    raise RuntimeError("Timed out waiting for lifecycle smoke verification")
finally:
    if session_id:
        try:
            webdriver_request("DELETE", f"/session/{session_id}", timeout=10)
        except Exception:
            pass
PY
)
  lifecycle_status=$?
  set -e
  if [ -n "${driver_pid:-}" ] && kill -0 "$driver_pid" 2>/dev/null; then
    kill "$driver_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$driver_pid" 2>/dev/null; then
      kill -9 "$driver_pid" 2>/dev/null || true
    fi
  fi
  driver_pid=
  printf '%s' "$lifecycle_output"
  return "$lifecycle_status"
}

lifecycle_retry_max=2
lifecycle_attempt=1
lifecycle_status=1
lifecycle_raw=""
reset_safari_for_automation
while [ "$lifecycle_attempt" -le "$lifecycle_retry_max" ]; do
  set +e
  lifecycle_raw=$(run_lifecycle_smoke_once)
  lifecycle_status=$?
  set -e
  if [ "$lifecycle_status" -eq 0 ]; then
    break
  fi
  if [ "$lifecycle_attempt" -lt "$lifecycle_retry_max" ]; then
    lifecycle_attempt=$((lifecycle_attempt + 1))
    reset_safari_for_automation
    sleep 1
    continue
  fi
  break
done

if [ "$lifecycle_status" -ne 0 ]; then
  escaped_error=$(printf '%s' "$lifecycle_raw" | jq -Rs '.' 2>/dev/null || printf '%s' "\"Safari lifecycle smoke failure\"")
  lifecycle_raw=$(printf '{"success":false,"error":"Safari lifecycle smoke automation failed","automation_error":%s}' "$escaped_error")
fi

if ! printf '%s' "$lifecycle_raw" | jq -e 'type=="object"' >/dev/null 2>&1; then
  escaped_raw=$(printf '%s' "$lifecycle_raw" | jq -Rs '.' 2>/dev/null || printf '%s' "\"Non-JSON lifecycle output\"")
  lifecycle_raw=$(printf '{"success":false,"error":"Lifecycle smoke returned non-JSON output","raw_output":%s}' "$escaped_raw")
fi

printf '%s\n' "$lifecycle_raw" > "$result_json"

status="PASS"
if ! printf '%s' "$lifecycle_raw" | jq -e '.success == true' >/dev/null 2>&1; then
  status="FAIL"
fi

{
  printf '# Safari GUI Lifecycle Smoke: %s\n\n' "$label"
  printf '## Status\n'
  printf -- '- Result: %s\n' "$status"
  printf -- '- Workspace seed: `%s`\n' "$workspace_name"
  printf -- '- Decision conversation seed: `%s`\n' "$decision_conversation_title"
  printf -- '- Approval conversation seed: `%s`\n' "$approval_conversation_title"
  printf -- '- Workspace path: `%s`\n' "$workspace_path"
  printf -- '- Site state root: `%s`\n' "$site_state_root"
  printf -- '- Site name: `%s`\n' "$site_name"
  printf -- '- Local app URL: `%s`\n' "$app_url"
  printf -- '- Server log: `%s`\n' "$server_log"
  printf -- '- WebDriver log: `%s`\n' "$driver_log"
  printf -- '- Raw JSON: `%s`\n' "$result_json"

  if [ "$status" = "PASS" ]; then
    printf '\n## Checks\n'
    printf '| Check | Pass | Detail |\n'
    printf '|---|---|---|\n'
    printf '%s' "$lifecycle_raw" | jq -r '.checks[] | "| " + (.name|tostring) + " | " + ((.pass|tostring)) + " | " + ((.detail // "")|tostring) + " |"'
  else
    printf '\n## Failure\n'
    printf -- '- Error: %s\n' "$(printf '%s' "$lifecycle_raw" | jq -r '.error // "Unknown lifecycle smoke failure"' 2>/dev/null || printf '%s' "Unknown lifecycle smoke failure")"
  fi
} > "$report_md"

printf '%s\n' "$result_json"
printf '%s\n' "$report_md"

if [ "$status" != "PASS" ]; then
  exit 1
fi
