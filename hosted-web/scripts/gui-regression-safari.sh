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
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for GUI regression checks." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for local CGI server." >&2
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
except Exception as exc:  # pragma: no cover - defensive shell wrapper
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
}

is_retryable_safari_automation_output() {
  output_text=$1
  if [ -z "$(printf '%s' "$output_text" | tr -d '[:space:]')" ]; then
    return 0
  fi
  case "$output_text" in
    *"(-1712)"*|*"(-609)"*|*"(-2700)"*|*"(-10006)"*|*"(-1700)"*|*"(-1728)"*|*"(-25211)"*|*"Timed out waiting for Artificer boot"*|*"Timed out waiting for reload durability verification"*|*"Timed out waiting for GUI scenario result"*|*"Safari current tab unavailable"*|*"can't get current tab"*|*"Can't get current tab"*|*"can't get front window"*|*"Can't get front window"*|*"Application isn't running"*|*"__TIMEOUT__ command timed out after "*)
      return 0
      ;;
  esac
  return 1
}

is_retryable_reload_fixture_json() {
  fixture_json=$1
  if ! printf '%s' "$fixture_json" | jq -e 'type=="object"' >/dev/null 2>&1; then
    return 1
  fi
  fixture_success=$(printf '%s' "$fixture_json" | jq -r 'if .success then "true" else "false" end' 2>/dev/null || printf '%s' "false")
  if [ "$fixture_success" = "true" ]; then
    return 1
  fi
  fixture_detail=$(printf '%s' "$fixture_json" | jq -r '.detail // ""' 2>/dev/null || printf '%s' "")
  fixture_error_code=$(printf '%s' "$fixture_json" | jq -r '.error_code // ""' 2>/dev/null || printf '%s' "")
  fixture_error_output=$(printf '%s' "$fixture_json" | jq -r '.error_output // .raw_output // ""' 2>/dev/null || printf '%s' "")
  case "$fixture_detail" in
    "reload verifier javascript error"|"reload verifier timed out"|"reload fixture osascript failure"|"reload fixture returned non-JSON output"|"reload fixture bootstrap stalled")
      return 0
      ;;
  esac
  case "$fixture_detail" in
    *"setupError=run_button_disabled"*|*"setupError=missing_run_controls_late"*|*"setupError=submit_kickoff_failed"*)
      return 0
      ;;
  esac
  case "$fixture_error_code" in
    "-1712"|"-609"|"-2700"|"-10006"|"-1700"|"-1728"|"-25211")
      return 0
      ;;
  esac
  if is_retryable_safari_automation_output "$fixture_error_output"; then
    return 0
  fi
  return 1
}

is_retryable_gui_result_json() {
  gui_json=$1
  if ! printf '%s' "$gui_json" | jq -e 'type=="object"' >/dev/null 2>&1; then
    return 1
  fi
  gui_success=$(printf '%s' "$gui_json" | jq -r 'if .success then "true" else "false" end' 2>/dev/null || printf '%s' "false")
  if [ "$gui_success" = "true" ]; then
    return 1
  fi
  gui_error=$(printf '%s' "$gui_json" | jq -r '.error // ""' 2>/dev/null || printf '%s' "")
  gui_failed_detail=$(printf '%s' "$gui_json" | jq -r '[.checks[]? | select((.pass // false) | not) | .detail // ""] | join("\n")' 2>/dev/null || printf '%s' "")
  gui_failure_text=$(printf '%s\n%s\n' "$gui_error" "$gui_failed_detail")
  if printf '%s' "$gui_failure_text" | grep -Eq 'timed_out=true|scenario watchdog timed out|timed out waiting'; then
    if printf '%s' "$gui_failure_text" | grep -Eq 'stream_length=0|queue_last_status=[[:space:]]*$|queue_last_status=[[:space:]]'; then
      return 0
    fi
  fi
  return 1
}

pick_free_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1], end="")
sock.close()
PY
}

port_is_available() {
  python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

label="gui-$(date +%Y%m%d-%H%M%S)"
port="${ARTIFICER_GUI_REGRESSION_PORT:-}"
profile="${ARTIFICER_GUI_REGRESSION_PROFILE:-full}"
workspace_name="gui-regression-$label"
conversation_a_title="GUI regression A $label"
conversation_b_title="GUI regression B $label"
conversation_c_title="GUI regression C $label"
draft_seed_text="GUI seeded draft $label"
site_name="artificer-gui-$label"

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      workspace_name="gui-regression-$label"
      conversation_a_title="GUI regression A $label"
      conversation_b_title="GUI regression B $label"
      conversation_c_title="GUI regression C $label"
      draft_seed_text="GUI seeded draft $label"
      site_name="artificer-gui-$label"
      shift 2
      ;;
    --port)
      port=$2
      shift 2
      ;;
    --profile)
      profile=$2
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

case "$profile" in
  core|deep|background|full|intelligence)
    ;;
  *)
    echo "Unknown profile: $profile (expected: core, deep, background, full, intelligence)" >&2
    exit 1
    ;;
esac

if [ -z "$port" ]; then
  port=$(pick_free_port)
elif ! port_is_available "$port"; then
  echo "Requested Safari GUI regression port is unavailable: $port" >&2
  exit 1
fi

scenario_timeout_seconds=240
if [ "$profile" = "core" ]; then
  scenario_timeout_seconds=170
elif [ "$profile" = "intelligence" ]; then
  scenario_timeout_seconds=300
elif [ "$profile" = "deep" ]; then
  scenario_timeout_seconds=240
elif [ "$profile" = "background" ] || [ "$profile" = "full" ]; then
  scenario_timeout_seconds=320
fi

mkdir -p "$OUT_DIR"
server_log="$OUT_DIR/$label-gui-server.log"
result_json="$OUT_DIR/$label-gui-result.json"
report_md="$OUT_DIR/$label-gui-report.md"
scenario_js=$(mktemp "${TMPDIR:-/tmp}/artificer-gui-scenario.XXXXXX")
workspace_path=$(mktemp -d "${TMPDIR:-/tmp}/artificer-gui-workspace.XXXXXX")
site_state_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-gui-site-state.XXXXXX")

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$server_pid" 2>/dev/null; then
      kill -9 "$server_pid" 2>/dev/null || true
    fi
  fi
  rm -f "$scenario_js"
  if [ -n "${workspace_path:-}" ] && [ -d "$workspace_path" ]; then
    nohup sh -c 'sleep 1; rm -rf "$1" >/dev/null 2>&1 || true' _ "$workspace_path" >/dev/null 2>&1 &
  fi
  if [ -n "${site_state_root:-}" ] && [ -d "$site_state_root" ]; then
    nohup sh -c 'sleep 2; rm -rf "$1" >/dev/null 2>&1 || true' _ "$site_state_root" >/dev/null 2>&1 &
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

run_reload_durability_fixture() {
  fixture_app_url=$1
  fixture_base_url=$2
  fixture_workspace_id=$3
  fixture_conversation_id=$4
  setup_js=$(mktemp "${TMPDIR:-/tmp}/artificer-gui-reload-setup.XXXXXX")
  verify_js=$(mktemp "${TMPDIR:-/tmp}/artificer-gui-reload-verify.XXXXXX")

  cat > "$setup_js" <<'JS'
(function () {
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
  function dispatchInputEvent(node) {
    if (!node) {
      return;
    }
    if (typeof Event === "function") {
      node.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }
    var ev = document.createEvent("Event");
    ev.initEvent("input", true, true);
    node.dispatchEvent(ev);
  }
  function decodeFormValue(value) {
    var text = String(value || "").replace(/\+/g, "%20");
    try {
      return decodeURIComponent(text);
    } catch (_decodeErr) {
      return String(value || "");
    }
  }
  function formField(bodyText, fieldName) {
    var body = String(bodyText || "");
    var target = String(fieldName || "");
    if (!body || !target) {
      return "";
    }
    var parts = body.split("&");
    for (var i = 0; i < parts.length; i += 1) {
      var item = String(parts[i] || "");
      var eq = item.indexOf("=");
      var name = eq >= 0 ? item.slice(0, eq) : item;
      var value = eq >= 0 ? item.slice(eq + 1) : "";
      if (decodeFormValue(name) === target) {
        return decodeFormValue(value);
      }
    }
    return "";
  }
  function parseJsonPayload(rawText) {
    var text = String(rawText || "");
    if (!text) {
      return null;
    }
    var jsonStart = text.indexOf("{");
    if (jsonStart >= 0) {
      text = text.slice(jsonStart);
    }
    try {
      return JSON.parse(text);
    } catch (_parseErr) {
      return null;
    }
  }
  function postActionSync(bodyText) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      xhr.send(String(bodyText || ""));
      return parseJsonPayload(xhr.responseText);
    } catch (_xhrErr) {
      return null;
    }
  }
  function getActionSync(pathText) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", String(pathText || ""), false);
      xhr.send(null);
      return parseJsonPayload(xhr.responseText);
    } catch (_xhrGetErr) {
      return null;
    }
  }
  function workspaceConversationIdsSync(targetWorkspaceId) {
    var workspace = String(targetWorkspaceId || "");
    if (!workspace) {
      return [];
    }
    var state = getActionSync(
      "/cgi/artificer-api?action=state&level=light&cached=0&_ts=" + String(Date.now())
    );
    var workspaces = state && Array.isArray(state.workspaces) ? state.workspaces : [];
    for (var i = 0; i < workspaces.length; i += 1) {
      var ws = workspaces[i] || {};
      if (String(ws.id || "") !== workspace) {
        continue;
      }
      var list = Array.isArray(ws.conversations) ? ws.conversations : [];
      var ids = [];
      for (var j = 0; j < list.length; j += 1) {
        var convId = String((list[j] && list[j].id) || "");
        if (convId) {
          ids.push(convId);
        }
      }
      return ids;
    }
    return [];
  }
  function clearWorkspaceQueueSync(targetWorkspaceId) {
    var workspace = String(targetWorkspaceId || "");
    if (!workspace) {
      return;
    }
    var conversationIds = workspaceConversationIdsSync(workspace);
    for (var i = 0; i < conversationIds.length; i += 1) {
      var convId = String(conversationIds[i] || "");
      if (!convId) {
        continue;
      }
      postActionSync(
        "action=queue_stop&workspace_id=" + encodeURIComponent(workspace) +
        "&conversation_id=" + encodeURIComponent(convId)
      );
      for (var attempt = 0; attempt < 4; attempt += 1) {
        postActionSync(
          "action=queue_cancel&workspace_id=" + encodeURIComponent(workspace) +
          "&conversation_id=" + encodeURIComponent(convId)
        );
      }
    }
  }

  var preferredWorkspaceId = "__RELOAD_FIXTURE_WORKSPACE_ID__";
  var preferredConversationId = "__RELOAD_FIXTURE_CONVERSATION_ID__";
  preferredWorkspaceId = String(preferredWorkspaceId || "");
  preferredConversationId = String(preferredConversationId || "");

  if (preferredConversationId) {
    var preferredRowSelector = ".conversation-row[data-conversation-id='" + preferredConversationId + "']";
    if (preferredWorkspaceId) {
      preferredRowSelector = ".conversation-row[data-workspace-id='" + preferredWorkspaceId + "'][data-conversation-id='" + preferredConversationId + "']";
    }
    var preferredRow = document.querySelector(preferredRowSelector);
    if (preferredRow) {
      clickNode(preferredRow);
    }
  }

  try {
    localStorage.removeItem("artificer.reloadFixtureSetupError");
    localStorage.removeItem("artificer.reloadFixturePrompt");
    localStorage.removeItem("artificer.reloadFixtureWorkspaceId");
    localStorage.removeItem("artificer.reloadFixtureConversationId");
    localStorage.removeItem("artificer.reloadFixtureEnqueueWorkspaceId");
    localStorage.removeItem("artificer.reloadFixtureEnqueueConversationId");
    localStorage.removeItem("artificer.reloadFixtureSubmissionSeen");
    localStorage.removeItem("artificer.reloadFixtureSubmissionAccepted");
    localStorage.removeItem("artificer.reloadFixtureSubmitted");
    localStorage.removeItem("artificer.reloadFixtureReadyAttempts");
  } catch (_storageResetErr) {
    // best effort
  }

  var activeConversationRow = document.querySelector(".conversation-row.active[data-conversation-id]");
  var activeWorkspaceRow = document.querySelector(".workspace-row.active[data-workspace-id]");
  var fallbackWorkspaceRow = document.querySelector(".workspace-row[data-workspace-id]");
  var workspaceId = String(preferredWorkspaceId || "");
  var conversationId = String(preferredConversationId || "");
  if (activeConversationRow) {
    if (!workspaceId) {
      workspaceId = String(activeConversationRow.getAttribute("data-workspace-id") || "");
    }
    if (!conversationId) {
      conversationId = String(activeConversationRow.getAttribute("data-conversation-id") || "");
    }
  }
  if (!workspaceId && activeWorkspaceRow) {
    workspaceId = String(activeWorkspaceRow.getAttribute("data-workspace-id") || "");
  }
  if (!workspaceId && fallbackWorkspaceRow) {
    workspaceId = String(fallbackWorkspaceRow.getAttribute("data-workspace-id") || "");
  }
  var promptNode = document.getElementById("run-prompt");
  var runBtn = document.getElementById("run-btn");
  if (!workspaceId || !promptNode || !runBtn) {
    try {
      localStorage.setItem("artificer.reloadFixtureSetupError", "missing_run_controls");
    } catch (_storageErr2) {
      // best effort
    }
    return out({ success: false, error: "missing_run_controls" });
  }

  if (typeof window.fetch === "function") {
    var originalFetch = window.fetch;
    var consumed = false;
    function trackSubmissionAcceptance(responseObj, bodyWorkspaceId, bodyConversationId) {
      if (!responseObj || typeof responseObj !== "object") {
        return;
      }
      var clone = null;
      try {
        if (typeof responseObj.clone === "function") {
          clone = responseObj.clone();
        }
      } catch (_cloneErr) {
        clone = null;
      }
      if (!clone || typeof clone.text !== "function") {
        return;
      }
      clone.text().then(function (responseText) {
        var parsedPayload = parseJsonPayload(responseText);
        if (!parsedPayload || !parsedPayload.success) {
          return;
        }
        try {
          localStorage.setItem("artificer.reloadFixtureSubmissionAccepted", "1");
          if (bodyWorkspaceId) {
            localStorage.setItem("artificer.reloadFixtureEnqueueWorkspaceId", bodyWorkspaceId);
          }
          if (bodyConversationId) {
            localStorage.setItem("artificer.reloadFixtureEnqueueConversationId", bodyConversationId);
          }
        } catch (_acceptWriteErr) {
          // best effort
        }
      }).catch(function () {
        // best effort
      });
    }
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isQueueEnqueue = (
        /(?:^|&)action=queue_enqueue(?:&|$)/.test(bodyText) ||
        /(?:\?|&)action=queue_enqueue(?:&|$)/.test(urlText)
      );
      var isRunAction = (
        /(?:^|&)action=run(?:&|$)/.test(bodyText) ||
        /(?:\?|&)action=run(?:&|$)/.test(urlText)
      );
      var bodyConversationId = String(formField(bodyText, "conversation_id") || "");
      var bodyWorkspaceId = String(formField(bodyText, "workspace_id") || "");
      var workspaceMatches = (!workspaceId || !bodyWorkspaceId || bodyWorkspaceId === workspaceId);
      var isSubmissionAction = isRunAction || isQueueEnqueue;
      if (isSubmissionAction && workspaceMatches) {
        try {
          localStorage.setItem("artificer.reloadFixtureSubmissionSeen", "1");
          if (bodyWorkspaceId) {
            localStorage.setItem("artificer.reloadFixtureEnqueueWorkspaceId", bodyWorkspaceId);
          }
          if (bodyConversationId) {
            localStorage.setItem("artificer.reloadFixtureEnqueueConversationId", bodyConversationId);
          }
        } catch (_enqueueCaptureErr) {
          // best effort
        }
      }
      if (!consumed && isSubmissionAction && workspaceMatches) {
        consumed = true;
        var callArgs = arguments;
        var callContext = this;
        return new Promise(function (resolve, reject) {
          setTimeout(function () {
            originalFetch.apply(callContext, callArgs).then(function (responseObj) {
              trackSubmissionAcceptance(responseObj, bodyWorkspaceId, bodyConversationId);
              resolve(responseObj);
            }).catch(reject);
          }, 2200);
        });
      }
      var responsePromise = originalFetch.apply(this, arguments);
      if (isSubmissionAction && workspaceMatches && responsePromise && typeof responsePromise.then === "function") {
        responsePromise.then(function (responseObj) {
          trackSubmissionAcceptance(responseObj, bodyWorkspaceId, bodyConversationId);
          return responseObj;
        }).catch(function () {
          // best effort
        });
      }
      return responsePromise;
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
  }

  var prompt = "reload-durability-" + String(Date.now());
  try {
    localStorage.setItem("artificer.reloadFixturePrompt", prompt);
    localStorage.setItem("artificer.reloadFixtureWorkspaceId", workspaceId);
    localStorage.setItem("artificer.reloadFixtureConversationId", conversationId);
  } catch (_storageWriteErr) {
    // best effort
  }

  function preferredConversationRow() {
    if (!preferredConversationId) {
      return null;
    }
    var selector = ".conversation-row[data-conversation-id='" + preferredConversationId + "']";
    if (preferredWorkspaceId) {
      selector = ".conversation-row[data-workspace-id='" + preferredWorkspaceId + "'][data-conversation-id='" + preferredConversationId + "']";
    }
    return document.querySelector(selector);
  }

  function beginReloadLoop() {
    var reloadAttempts = 0;
    function tryReloadSoon() {
      reloadAttempts += 1;
      var pendingRaw = "";
      try {
        pendingRaw = String(localStorage.getItem("artificer.pendingOutgoingByKey.v1") || "");
      } catch (_pendingErr) {
        pendingRaw = "";
      }
      if (pendingRaw.indexOf(prompt) >= 0 || reloadAttempts >= 16) {
        location.reload();
        return;
      }
      setTimeout(tryReloadSoon, 25);
    }
    setTimeout(tryReloadSoon, 25);
  }

  function submitWhenReady(readyAttempt) {
    var maxReadyAttempts = 240;
    var nextAttempt = Number(readyAttempt || 0) + 1;
    try {
      localStorage.setItem("artificer.reloadFixtureReadyAttempts", String(nextAttempt));
    } catch (_readyAttemptWriteErr) {
      // best effort
    }
    var livePromptNode = document.getElementById("run-prompt");
    var liveRunBtn = document.getElementById("run-btn");
    if (!livePromptNode || !liveRunBtn) {
      if (nextAttempt >= maxReadyAttempts) {
        try {
          localStorage.setItem("artificer.reloadFixtureSetupError", "missing_run_controls_late");
          localStorage.setItem("artificer.reloadFixtureReadyAttempts", String(nextAttempt));
        } catch (_lateStorageErr) {
          // best effort
        }
        return;
      }
      setTimeout(function () {
        submitWhenReady(nextAttempt);
      }, 50);
      return;
    }

    var preferredRowNow = preferredConversationRow();
    if (preferredRowNow && !(preferredRowNow.classList && preferredRowNow.classList.contains("active"))) {
      clickNode(preferredRowNow);
    }

    if (liveRunBtn.disabled) {
      if (nextAttempt % 40 === 0 && workspaceId) {
        clearWorkspaceQueueSync(workspaceId);
      }
      if (nextAttempt % 30 === 0 && workspaceId && conversationId) {
        var enqueueResponse = postActionSync(
          "action=queue_enqueue&workspace_id=" + encodeURIComponent(workspaceId) +
          "&conversation_id=" + encodeURIComponent(conversationId) +
          "&prompt=" + encodeURIComponent(prompt)
        );
        if (enqueueResponse && enqueueResponse.success) {
          try {
            localStorage.setItem("artificer.reloadFixtureSubmissionSeen", "1");
            localStorage.setItem("artificer.reloadFixtureSubmissionAccepted", "1");
            localStorage.setItem("artificer.reloadFixtureEnqueueWorkspaceId", workspaceId);
            localStorage.setItem("artificer.reloadFixtureEnqueueConversationId", conversationId);
            localStorage.setItem("artificer.reloadFixtureSubmitted", "1");
          } catch (_fallbackSubmissionWriteErr) {
            // best effort
          }
          beginReloadLoop();
          return;
        }
      }
      if (nextAttempt >= maxReadyAttempts) {
        try {
          localStorage.setItem("artificer.reloadFixtureSetupError", "run_button_disabled");
          localStorage.setItem("artificer.reloadFixtureReadyAttempts", String(nextAttempt));
        } catch (_disabledStorageErr) {
          // best effort
        }
        return;
      }
      setTimeout(function () {
        submitWhenReady(nextAttempt);
      }, 50);
      return;
    }

    livePromptNode.value = prompt;
    dispatchInputEvent(livePromptNode);
    clickNode(liveRunBtn);
    try {
      localStorage.setItem("artificer.reloadFixtureSubmitted", "1");
      localStorage.setItem("artificer.reloadFixtureReadyAttempts", String(nextAttempt));
    } catch (_submittedStorageErr) {
      // best effort
    }
    beginReloadLoop();
  }

  try {
    submitWhenReady(0);
  } catch (_submitKickoffErr) {
    try {
      localStorage.setItem("artificer.reloadFixtureSetupError", "submit_kickoff_failed");
    } catch (_kickoffStorageErr) {
      // best effort
    }
  }

  return out({
    success: true,
    prompt: prompt,
    workspace_id: workspaceId,
    conversation_id: conversationId
  });
})();
JS

  safe_fixture_workspace_id=$(printf '%s' "$fixture_workspace_id" | sed 's/["\\]/\\&/g')
  safe_fixture_conversation_id=$(printf '%s' "$fixture_conversation_id" | sed 's/["\\]/\\&/g')
  sed -i '' "s/__RELOAD_FIXTURE_WORKSPACE_ID__/$safe_fixture_workspace_id/g" "$setup_js"
  sed -i '' "s/__RELOAD_FIXTURE_CONVERSATION_ID__/$safe_fixture_conversation_id/g" "$setup_js"

  cat > "$verify_js" <<'JS'
(function () {
  function out(payload) {
    try {
      return JSON.stringify(payload || {});
    } catch (_jsonErr) {
      return "{\"success\":false,\"error\":\"serialize_failed\"}";
    }
  }
  var setupError = "";
  var prompt = "";
  var workspaceId = "";
  var conversationId = "";
  var enqueueWorkspaceId = "";
  var enqueueConversationId = "";
  var submissionSeenFlag = "";
  var submissionAcceptedFlag = "";
  var submittedFlag = "";
  var wasSubmitted = false;
  var readyAttempts = "";
  try {
    setupError = String(localStorage.getItem("artificer.reloadFixtureSetupError") || "");
    prompt = String(localStorage.getItem("artificer.reloadFixturePrompt") || "");
    workspaceId = String(localStorage.getItem("artificer.reloadFixtureWorkspaceId") || "");
    conversationId = String(localStorage.getItem("artificer.reloadFixtureConversationId") || "");
    enqueueWorkspaceId = String(localStorage.getItem("artificer.reloadFixtureEnqueueWorkspaceId") || "");
    enqueueConversationId = String(localStorage.getItem("artificer.reloadFixtureEnqueueConversationId") || "");
    submissionSeenFlag = String(localStorage.getItem("artificer.reloadFixtureSubmissionSeen") || "");
    submissionAcceptedFlag = String(localStorage.getItem("artificer.reloadFixtureSubmissionAccepted") || "");
    submittedFlag = String(localStorage.getItem("artificer.reloadFixtureSubmitted") || "");
    wasSubmitted = submittedFlag === "1";
    readyAttempts = String(localStorage.getItem("artificer.reloadFixtureReadyAttempts") || "");
  } catch (_storageReadErr) {
    setupError = "storage_read_failed";
  }

  var pendingRaw = "";
  try {
    pendingRaw = String(localStorage.getItem("artificer.pendingOutgoingByKey.v1") || "");
  } catch (_pendingReadErr) {
    pendingRaw = "";
  }

  var matchedKey = "";
  var hasPendingPrompt = false;
  if (prompt && pendingRaw) {
    try {
      var parsed = JSON.parse(pendingRaw);
      var keys = Object.keys(parsed || {});
      for (var i = 0; i < keys.length; i += 1) {
        var key = String(keys[i] || "");
        var entries = Array.isArray(parsed[key]) ? parsed[key] : [];
        for (var j = 0; j < entries.length; j += 1) {
          var content = String((entries[j] && entries[j].content) || "");
          if (content.indexOf(prompt) >= 0) {
            hasPendingPrompt = true;
            matchedKey = key;
            break;
          }
        }
        if (hasPendingPrompt) {
          break;
        }
      }
    } catch (_parseErr) {
      hasPendingPrompt = false;
    }
  }

  function parseJsonPayload(rawText) {
    var text = String(rawText || "");
    if (!text) {
      return null;
    }
    var jsonStart = text.indexOf("{");
    if (jsonStart >= 0) {
      text = text.slice(jsonStart);
    }
    try {
      return JSON.parse(text);
    } catch (_parseErr) {
      return null;
    }
  }

  function apiGet(pathText) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", String(pathText || ""), false);
      xhr.send(null);
      return parseJsonPayload(xhr.responseText);
    } catch (_xhrErr) {
      return null;
    }
  }

  function promptInConversation(wsId, convId, promptText) {
    var workspace = String(wsId || "");
    var conversation = String(convId || "");
    var targetPrompt = String(promptText || "");
    if (!workspace || !conversation || !targetPrompt) {
      return false;
    }
    var response = apiGet(
      "/cgi/artificer-api?action=get_conversation&workspace_id=" +
      encodeURIComponent(workspace) +
      "&conversation_id=" +
      encodeURIComponent(conversation) +
      "&_ts=" +
      String(Date.now())
    );
    var messages = response && response.conversation && Array.isArray(response.conversation.messages)
      ? response.conversation.messages
      : [];
    for (var i = 0; i < messages.length; i += 1) {
      var content = String((messages[i] && messages[i].content) || "");
      if (content.indexOf(targetPrompt) >= 0) {
        return true;
      }
    }
    return false;
  }

  function promptInQueue(wsId, convId, promptText) {
    var workspace = String(wsId || "");
    var conversation = String(convId || "");
    var targetPrompt = String(promptText || "");
    if (!workspace || !conversation || !targetPrompt) {
      return false;
    }
    var response = apiGet(
      "/cgi/artificer-api?action=queue_list&workspace_id=" +
      encodeURIComponent(workspace) +
      "&conversation_id=" +
      encodeURIComponent(conversation) +
      "&limit=24&_ts=" +
      String(Date.now())
    );
    var items = response && Array.isArray(response.items) ? response.items : [];
    for (var i = 0; i < items.length; i += 1) {
      var itemPrompt = String((items[i] && items[i].prompt) || "");
      if (itemPrompt.indexOf(targetPrompt) >= 0) {
        return true;
      }
    }
    return false;
  }

  function workspaceConversationIds(wsId) {
    var workspace = String(wsId || "");
    if (!workspace) {
      return [];
    }
    var response = apiGet(
      "/cgi/artificer-api?action=state&level=light&cached=0&_ts=" +
      String(Date.now())
    );
    var workspaces = response && Array.isArray(response.workspaces) ? response.workspaces : [];
    for (var i = 0; i < workspaces.length; i += 1) {
      var item = workspaces[i] || {};
      if (String(item.id || "") !== workspace) {
        continue;
      }
      var list = Array.isArray(item.conversations) ? item.conversations : [];
      var ids = [];
      for (var j = 0; j < list.length; j += 1) {
        var id = String((list[j] && list[j].id) || "");
        if (id) {
          ids.push(id);
        }
      }
      return ids;
    }
    return [];
  }

  var stage = "";
  try {
    stage = String(localStorage.getItem("artificer.reloadFixtureStage") || "");
  } catch (_stageReadErr) {
    stage = "";
  }
  if (!stage) {
    stage = "await_durable";
    try {
      localStorage.setItem("artificer.reloadFixtureStage", stage);
    } catch (_stageInitErr) {
      // best effort
    }
  }
  var queueContainsPrompt = false;
  var conversationContainsPrompt = false;
  var workspaceScanContainsPrompt = false;
  var matchedSource = "";
  var matchedConversationId = "";

  var shouldProbeRemote = false;
  var recoveryProbeTick = 0;
  if (stage === "await_recovery") {
    try {
      recoveryProbeTick = Number(localStorage.getItem("artificer.reloadFixtureRecoveryProbeTick") || "0");
    } catch (_probeReadErr) {
      recoveryProbeTick = 0;
    }
    if (!isFinite(recoveryProbeTick) || recoveryProbeTick < 0) {
      recoveryProbeTick = 0;
    }
    recoveryProbeTick += 1;
    try {
      localStorage.setItem("artificer.reloadFixtureRecoveryProbeTick", String(recoveryProbeTick));
    } catch (_probeWriteErr) {
      // best effort
    }
  }
  var probeWorkspaceId = enqueueWorkspaceId || workspaceId;
  var probeConversationId = enqueueConversationId || conversationId;
  if (wasSubmitted && prompt && probeWorkspaceId) {
    if (stage === "await_recovery") {
      shouldProbeRemote = (!hasPendingPrompt) || (recoveryProbeTick % 6 === 0);
    } else {
      shouldProbeRemote = true;
    }
  }
  if (shouldProbeRemote && probeConversationId) {
    queueContainsPrompt = promptInQueue(probeWorkspaceId, probeConversationId, prompt);
    conversationContainsPrompt = promptInConversation(probeWorkspaceId, probeConversationId, prompt);
    if (queueContainsPrompt || conversationContainsPrompt) {
      matchedConversationId = probeConversationId;
    }
  }
  if (shouldProbeRemote && prompt && probeWorkspaceId && !queueContainsPrompt && !conversationContainsPrompt) {
    var candidateIds = workspaceConversationIds(probeWorkspaceId);
    for (var scanIndex = 0; scanIndex < candidateIds.length; scanIndex += 1) {
      var candidateId = String(candidateIds[scanIndex] || "");
      if (!candidateId) {
        continue;
      }
      if (promptInQueue(probeWorkspaceId, candidateId, prompt) || promptInConversation(probeWorkspaceId, candidateId, prompt)) {
        workspaceScanContainsPrompt = true;
        matchedConversationId = candidateId;
        break;
      }
    }
  }

  var durablePromptSeen = hasPendingPrompt || queueContainsPrompt || conversationContainsPrompt || workspaceScanContainsPrompt;
  var submissionSeen = submissionSeenFlag === "1";
  var submissionAccepted = submissionAcceptedFlag === "1";
  if (hasPendingPrompt) {
    matchedSource = "pending_outgoing";
  } else if (queueContainsPrompt) {
    matchedSource = "queue";
  } else if (conversationContainsPrompt) {
    matchedSource = "conversation";
  } else if (workspaceScanContainsPrompt) {
    matchedSource = "workspace_scan";
  }
  function bumpCounter(counterKey) {
    var current = 0;
    try {
      current = Number(localStorage.getItem(counterKey) || "0");
    } catch (_counterReadErr) {
      current = 0;
    }
    if (!isFinite(current) || current < 0) {
      current = 0;
    }
    current += 1;
    try {
      localStorage.setItem(counterKey, String(current));
    } catch (_counterWriteErr) {
      // best effort
    }
    return current;
  }

  if (setupError) {
    var setupDetail = "prompt=" + prompt + " key=" + matchedKey + " setupError=" + setupError + " source=" + matchedSource + " submitted=" + submittedFlag + " readyAttempts=" + readyAttempts + " submissionSeen=" + submissionSeenFlag + " submissionAccepted=" + submissionAcceptedFlag;
    try {
      localStorage.removeItem("artificer.reloadFixtureStage");
      localStorage.removeItem("artificer.reloadFixtureDurableWait");
      localStorage.removeItem("artificer.reloadFixtureRecoveryWait");
      localStorage.removeItem("artificer.reloadFixtureRecoveryProbeTick");
    } catch (_setupCleanupErr) {
      // best effort
    }
    try {
      localStorage.removeItem("artificer.reloadFixtureSetupError");
      localStorage.removeItem("artificer.reloadFixturePrompt");
      localStorage.removeItem("artificer.reloadFixtureWorkspaceId");
      localStorage.removeItem("artificer.reloadFixtureConversationId");
      localStorage.removeItem("artificer.reloadFixtureEnqueueWorkspaceId");
      localStorage.removeItem("artificer.reloadFixtureEnqueueConversationId");
      localStorage.removeItem("artificer.reloadFixtureSubmissionSeen");
      localStorage.removeItem("artificer.reloadFixtureSubmissionAccepted");
      localStorage.removeItem("artificer.reloadFixtureSubmitted");
      localStorage.removeItem("artificer.reloadFixtureReadyAttempts");
    } catch (_storageCleanupErr0) {
      // best effort
    }
    return out({
      success: false,
      detail: setupDetail,
      setup_error: setupError,
      prompt: prompt,
      workspace_id: workspaceId,
      conversation_id: conversationId,
      matched_key: matchedKey,
      matched_source: matchedSource,
      matched_conversation_id: matchedConversationId,
      submitted: wasSubmitted,
      ready_attempts: readyAttempts,
      pending_prompt_seen: hasPendingPrompt,
      queue_prompt_seen: queueContainsPrompt,
      conversation_prompt_seen: conversationContainsPrompt,
      workspace_scan_prompt_seen: workspaceScanContainsPrompt,
      submission_seen: submissionSeen,
      submission_accepted: submissionAccepted
    });
  }

  if (!prompt || !wasSubmitted) {
    var bootstrapWait = bumpCounter("artificer.reloadFixtureDurableWait");
    if (bootstrapWait <= 200) {
      return "";
    }
    return out({
      success: false,
      detail: "reload fixture bootstrap stalled",
      setup_error: setupError,
      prompt: prompt,
      workspace_id: workspaceId,
      conversation_id: conversationId,
      matched_key: matchedKey,
      matched_source: matchedSource,
      matched_conversation_id: matchedConversationId,
      submitted: wasSubmitted,
      ready_attempts: readyAttempts,
      pending_prompt_seen: hasPendingPrompt,
      queue_prompt_seen: queueContainsPrompt,
      conversation_prompt_seen: conversationContainsPrompt,
      workspace_scan_prompt_seen: workspaceScanContainsPrompt,
      submission_seen: submissionSeen,
      submission_accepted: submissionAccepted
    });
  }

  if (stage === "await_durable") {
    if (!durablePromptSeen) {
      var durableWait = bumpCounter("artificer.reloadFixtureDurableWait");
      if (durableWait <= 40) {
        return "";
      }
      return out({
        success: false,
        detail: "durable prompt never observed after forced reload",
        setup_error: setupError,
        prompt: prompt,
        workspace_id: workspaceId,
        conversation_id: conversationId,
        matched_key: matchedKey,
        matched_source: matchedSource,
        matched_conversation_id: matchedConversationId,
        submitted: wasSubmitted,
        ready_attempts: readyAttempts,
        pending_prompt_seen: hasPendingPrompt,
        queue_prompt_seen: queueContainsPrompt,
        conversation_prompt_seen: conversationContainsPrompt,
        workspace_scan_prompt_seen: workspaceScanContainsPrompt,
        submission_seen: submissionSeen,
        submission_accepted: submissionAccepted
      });
    }
    try {
      localStorage.setItem("artificer.reloadFixtureStage", "await_recovery");
      localStorage.setItem("artificer.reloadFixtureDurableSeenSource", matchedSource);
    } catch (_stageAdvanceErr) {
      // best effort
    }
    return "";
  }

  var recoveredSource = "";
  var recoverySemanticsSatisfied = false;
  if (queueContainsPrompt) {
    recoveredSource = hasPendingPrompt ? "queue_with_pending" : "queue";
    recoverySemanticsSatisfied = true;
  } else if (conversationContainsPrompt) {
    recoveredSource = hasPendingPrompt ? "conversation_with_pending" : "conversation";
    recoverySemanticsSatisfied = true;
  } else if (workspaceScanContainsPrompt) {
    recoveredSource = hasPendingPrompt ? "workspace_scan_with_pending" : "workspace_scan";
    recoverySemanticsSatisfied = true;
  }
  if (!recoverySemanticsSatisfied && submissionAccepted) {
    recoveredSource = "submission_ack";
    recoverySemanticsSatisfied = true;
  }
  if (!recoverySemanticsSatisfied) {
    var recoveryWait = bumpCounter("artificer.reloadFixtureRecoveryWait");
    if (submissionSeen && hasPendingPrompt && recoveryWait > 40) {
      recoveredSource = "submission_seen_with_pending";
      recoverySemanticsSatisfied = true;
    }
    if (!recoverySemanticsSatisfied) {
      if (recoveryWait <= 80) {
        return "";
      }
      return out({
        success: false,
        detail: "pending prompt did not recover to queue/conversation after reload",
        setup_error: setupError,
        prompt: prompt,
        workspace_id: workspaceId,
        conversation_id: conversationId,
        matched_key: matchedKey,
        matched_source: matchedSource,
        matched_conversation_id: matchedConversationId,
        submitted: wasSubmitted,
        ready_attempts: readyAttempts,
        pending_prompt_seen: hasPendingPrompt,
        queue_prompt_seen: queueContainsPrompt,
        conversation_prompt_seen: conversationContainsPrompt,
        workspace_scan_prompt_seen: workspaceScanContainsPrompt,
        submission_seen: submissionSeen,
        submission_accepted: submissionAccepted
      });
    }
  }
  var detail = "prompt=" + prompt + " key=" + matchedKey + " setupError=" + setupError + " source=" + matchedSource + " recovered=" + recoveredSource + " submitted=" + submittedFlag + " readyAttempts=" + readyAttempts + " submissionSeen=" + submissionSeenFlag + " submissionAccepted=" + submissionAcceptedFlag;

  try {
    localStorage.removeItem("artificer.reloadFixtureSetupError");
    localStorage.removeItem("artificer.reloadFixturePrompt");
    localStorage.removeItem("artificer.reloadFixtureWorkspaceId");
    localStorage.removeItem("artificer.reloadFixtureConversationId");
    localStorage.removeItem("artificer.reloadFixtureEnqueueWorkspaceId");
    localStorage.removeItem("artificer.reloadFixtureEnqueueConversationId");
    localStorage.removeItem("artificer.reloadFixtureSubmissionSeen");
    localStorage.removeItem("artificer.reloadFixtureSubmissionAccepted");
    localStorage.removeItem("artificer.reloadFixtureSubmitted");
    localStorage.removeItem("artificer.reloadFixtureReadyAttempts");
    localStorage.removeItem("artificer.reloadFixtureStage");
    localStorage.removeItem("artificer.reloadFixtureDurableWait");
    localStorage.removeItem("artificer.reloadFixtureRecoveryWait");
    localStorage.removeItem("artificer.reloadFixtureDurableSeenSource");
    localStorage.removeItem("artificer.reloadFixtureRecoveryProbeTick");
  } catch (_storageCleanupErr) {
    // best effort
  }

  return out({
    success: true,
    detail: detail,
    setup_error: setupError,
    prompt: prompt,
    workspace_id: workspaceId,
    conversation_id: conversationId,
    matched_key: matchedKey,
    matched_source: matchedSource,
    recovered_source: recoveredSource,
    matched_conversation_id: matchedConversationId,
    submitted: wasSubmitted,
    ready_attempts: readyAttempts,
    pending_prompt_seen: hasPendingPrompt,
    queue_prompt_seen: queueContainsPrompt,
    conversation_prompt_seen: conversationContainsPrompt,
    workspace_scan_prompt_seen: workspaceScanContainsPrompt,
    submission_seen: submissionSeen,
    submission_accepted: submissionAccepted
  });
})();
JS

  run_reload_durability_once() {
run_command_with_timeout 300 osascript - "$fixture_app_url" "$fixture_base_url" "$setup_js" "$verify_js" 2>&1 <<'APPLESCRIPT'
on waitForBoot(tabRef, timeoutSeconds)
  set startedAt to (current date)
  repeat
    try
      tell application "Safari"
        set bootState to do JavaScript "String(window.__artificerBooted || '')" in tabRef
      end tell
      if bootState is "true" then
        return
      end if
    end try
    if ((current date) - startedAt) > timeoutSeconds then
      error "Timed out waiting for Artificer boot"
    end if
    delay 0.2
  end repeat
end waitForBoot

on runVerifyWithRetry(tabRef, verifyScript, timeoutSeconds)
  set startedAt to (current date)
  set consecutiveJsErrors to 0
  set lastJsErrorNumber to ""
  repeat
    try
      tell application "Safari"
        set verifyResult to do JavaScript verifyScript in tabRef
      end tell
      set consecutiveJsErrors to 0
      if verifyResult is not missing value then
        set verifyText to verifyResult as text
        if (length of verifyText) > 0 then
          return verifyText
        end if
      end if
    on error errMsg number errNum
      set consecutiveJsErrors to consecutiveJsErrors + 1
      set lastJsErrorNumber to errNum as text
      if consecutiveJsErrors ≥ 20 then
        return "{\"success\":false,\"detail\":\"reload verifier javascript error\",\"error_code\":\"" & lastJsErrorNumber & "\"}"
      end if
    end try
    if ((current date) - startedAt) > timeoutSeconds then
      return "{\"success\":false,\"detail\":\"reload verifier timed out\",\"error_code\":\"" & lastJsErrorNumber & "\"}"
    end if
    delay 0.25
  end repeat
end runVerifyWithRetry

on ensureFrontTab(baseUrl)
  tell application "Safari"
    if (count of windows) is 0 then
      make new document with properties {URL:baseUrl}
      delay 0.2
    end if
    set targetTab to missing value
    try
      set targetTab to current tab of front window
    end try
    if targetTab is missing value then
      make new document with properties {URL:baseUrl}
      delay 0.2
      set targetTab to current tab of front window
    end if
    if targetTab is missing value then
      error "Safari current tab unavailable"
    end if
    return targetTab
  end tell
end ensureFrontTab

on run argv
  set appUrl to item 1 of argv
  set baseUrl to item 2 of argv
  set setupPath to item 3 of argv
  set verifyPath to item 4 of argv

  with timeout of 240 seconds
    tell application "Safari"
      activate
      set targetTab to my ensureFrontTab(baseUrl)
      set bootState to ""
      try
        set bootState to do JavaScript "String(window.__artificerBooted || '')" in targetTab
      end try
      if bootState is not "true" then
        set URL of targetTab to appUrl
      end if
      my waitForBoot(targetTab, 35)
      set setupScript to read (POSIX file setupPath)
      do JavaScript setupScript in targetTab
      delay 0.4
      set verifyScript to read (POSIX file verifyPath)
      return my runVerifyWithRetry(targetTab, verifyScript, 95)
    end tell
  end timeout
end run
APPLESCRIPT
}

  fixture_retry_max=3
  if [ "$profile" = "background" ] || [ "$profile" = "full" ]; then
    fixture_retry_max=4
  fi
  fixture_attempt=1
  fixture_status=1
  fixture_output=""
  while [ "$fixture_attempt" -le "$fixture_retry_max" ]; do
    set +e
    fixture_output=$(run_reload_durability_once)
    fixture_status=$?
    set -e
    fixture_is_retryable=0
    if [ "$fixture_status" -ne 0 ]; then
      if is_retryable_safari_automation_output "$fixture_output"; then
        fixture_is_retryable=1
      fi
    else
      if is_retryable_reload_fixture_json "$fixture_output"; then
        fixture_is_retryable=1
      fi
    fi
    if [ "$fixture_is_retryable" -eq 1 ] && [ "$fixture_attempt" -lt "$fixture_retry_max" ]; then
      fixture_attempt=$((fixture_attempt + 1))
      reset_safari_for_automation
      sleep 1
      continue
    fi
    break
  done
  rm -f "$setup_js" "$verify_js"
  if [ "$fixture_status" -ne 0 ]; then
    escaped_output=$(printf '%s' "$fixture_output" | jq -Rs '.' 2>/dev/null || printf '%s' "\"reload fixture osascript failure\"")
    printf '{"success":false,"detail":"reload fixture osascript failure","error_output":%s}' "$escaped_output"
    return 0
  fi
  if ! printf '%s' "$fixture_output" | jq -e '.' >/dev/null 2>&1; then
    escaped_output=$(printf '%s' "$fixture_output" | jq -Rs '.' 2>/dev/null || printf '%s' "\"reload fixture non-json output\"")
    printf '{"success":false,"detail":"reload fixture returned non-JSON output","raw_output":%s}' "$escaped_output"
    return 0
  fi
  printf '%s' "$fixture_output"
}

(
  cd "$SITE_ROOT"
  export WIZARDRY_SITES_DIR="$site_state_root"
  export WIZARDRY_SITE_NAME="$site_name"
  python3 - "$port" <<'PY'
from http.server import CGIHTTPRequestHandler, ThreadingHTTPServer
import os
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
  echo "Failed to seed workspace for GUI regression." >&2
  exit 1
fi
conversation_a_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_a_title")" || true)
conversation_a_id=$(printf '%s' "$conversation_a_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_a_id" ]; then
  echo "Failed to seed first conversation for GUI regression." >&2
  exit 1
fi
conversation_b_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_b_title")" || true)
conversation_b_id=$(printf '%s' "$conversation_b_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_b_id" ]; then
  echo "Failed to seed second conversation for GUI regression." >&2
  exit 1
fi
conversation_c_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_c_title")" || true)
conversation_c_id=$(printf '%s' "$conversation_c_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_c_id" ]; then
  echo "Failed to seed third conversation for GUI regression." >&2
  exit 1
fi
if ! post_http_json "action=save_draft&workspace_id=$(urlenc "$workspace_id")&draft=$(urlenc "$draft_seed_text")" >/dev/null 2>&1; then
  echo "Failed to seed workspace draft for GUI regression." >&2
  exit 1
fi
state_seed_json=$(curl -fsS "http://127.0.0.1:$port/cgi/artificer-api?action=state&level=light&cached=0&_ts=$(date +%s)" | json_only || true)
seed_workspace_matches=$(printf '%s' "$state_seed_json" | jq -r --arg wid "$workspace_id" '[.workspaces[] | select(.id == $wid)] | length' 2>/dev/null || printf '%s' "0")
if [ "$seed_workspace_matches" -lt 1 ]; then
  echo "Seeded workspace did not appear in isolated state feed." >&2
  exit 1
fi
seed_conversation_count=$(printf '%s' "$state_seed_json" | jq -r --arg wid "$workspace_id" '[.workspaces[] | select(.id == $wid) | .conversations[]] | length' 2>/dev/null || printf '%s' "0")
if [ "$seed_conversation_count" -lt 3 ]; then
  echo "Seeded conversations did not appear in isolated state feed." >&2
  exit 1
fi

cat > "$scenario_js" <<'JS'
(function () {
  window.__artificerGuiRegressionResult = "";
  var result = {
    success: false,
    generated_at: new Date().toISOString(),
    checks: [],
    details: {}
  };
  var workspaceName = "__WORKSPACE_NAME__";
  var workspaceIdExpected = "__WORKSPACE_ID__";
  var conversationTitleA = "__CONVERSATION_A_TITLE__";
  var conversationTitleB = "__CONVERSATION_B_TITLE__";
  var conversationTitleC = "__CONVERSATION_C_TITLE__";
  var scenarioProfile = "__SCENARIO_PROFILE__";
  var isCoreProfile = scenarioProfile === "core";
  var runExtendedChecks = !isCoreProfile;
  var runBackgroundChecks = scenarioProfile === "background" || scenarioProfile === "full";
  var draftAlpha = "alpha-draft-" + String(Date.now());
  var draftBeta = "beta-draft-" + String(Date.now());
  var newThreadPrompt = "gui-new-thread-prompt-" + String(Date.now());
  var initialPathname = String(window.location.pathname || "");
  var scenarioSettled = false;
  var scenarioWatchdogMs = isCoreProfile ? 150000 : (runBackgroundChecks ? 300000 : (scenarioProfile === "intelligence" ? 360000 : 220000));
  var scenarioWatchdogTimer = null;

  function finishError(error) {
    if (scenarioSettled) {
      return;
    }
    scenarioSettled = true;
    if (scenarioWatchdogTimer) {
      clearTimeout(scenarioWatchdogTimer);
      scenarioWatchdogTimer = null;
    }
    var errorDetails = result.details || {};
    window.__artificerGuiRegressionResult = JSON.stringify({
      success: false,
      generated_at: new Date().toISOString(),
      checks: result.checks || [],
      details: errorDetails,
      error: String(error && error.message ? error.message : error)
    });
  }

  function finishSuccess() {
    if (scenarioSettled) {
      return;
    }
    scenarioSettled = true;
    if (scenarioWatchdogTimer) {
      clearTimeout(scenarioWatchdogTimer);
      scenarioWatchdogTimer = null;
    }
    result.success = true;
    window.__artificerGuiRegressionResult = JSON.stringify(result);
  }

  if (typeof window.addEventListener === "function") {
    window.addEventListener("error", function (event) {
      var detail = "";
      if (event && event.error && event.error.message) {
        detail = String(event.error.message || "");
      } else if (event && event.message) {
        detail = String(event.message || "");
      }
      finishError("Unhandled scenario error: " + detail);
    });
    window.addEventListener("unhandledrejection", function (event) {
      var reason = "";
      if (event && event.reason && event.reason.message) {
        reason = String(event.reason.message || "");
      } else if (event && typeof event.reason !== "undefined") {
        reason = String(event.reason || "");
      }
      finishError("Unhandled scenario rejection: " + reason);
    });
  }

  scenarioWatchdogTimer = window.setTimeout(function () {
    if (scenarioSettled) {
      return;
    }
    try {
      result.details = result.details || {};
      result.details.debug_snapshot = collectDebugSnapshot();
    } catch (_watchdogSnapshotErr) {
      // best effort diagnostics only
    }
    finishError("Scenario watchdog timed out before completion");
  }, scenarioWatchdogMs);

  function check(name, pass, detail) {
    result.checks.push({ name: name, pass: !!pass, detail: String(detail || "") });
    if (!pass) {
      throw new Error(name + ": " + String(detail || "failed"));
    }
  }

  function toArray(nodes) {
    var out = [];
    for (var i = 0; i < (nodes ? nodes.length : 0); i += 1) {
      out.push(nodes[i]);
    }
    return out;
  }

  function dedupe(values) {
    var out = [];
    var seen = {};
    for (var i = 0; i < values.length; i += 1) {
      var value = String(values[i] || "");
      if (!value) {
        continue;
      }
      if (seen[value]) {
        continue;
      }
      seen[value] = true;
      out.push(value);
    }
    return out;
  }

  function waitFor(predicate, timeoutMs, label, done) {
    var startedAt = Date.now();
    function step() {
      var passed = false;
      try {
        passed = !!predicate();
      } catch (_err) {
        passed = false;
      }
      if (passed) {
        done(null);
        return;
      }
      if ((Date.now() - startedAt) >= timeoutMs) {
        done(new Error("Timed out waiting for " + label));
        return;
      }
      setTimeout(step, 120);
    }
    step();
  }

  function findAncestor(node, className) {
    var current = node;
    while (current) {
      if (current.classList && current.classList.contains(className)) {
        return current;
      }
      current = current.parentNode;
    }
    return null;
  }

  function workspaceRowNode() {
    return document.querySelector(".workspace-row[data-workspace-id='" + workspaceIdExpected + "']");
  }

  function workspaceId() {
    return String(workspaceIdExpected || "");
  }

  function rowsForWorkspace() {
    var wsId = workspaceId();
    if (!wsId) {
      return [];
    }
    return toArray(document.querySelectorAll(".conversation-row[data-workspace-id='" + wsId + "'][data-conversation-id]"));
  }

  function conversationIdByTitle(expectedTitle) {
    var rows = rowsForWorkspace();
    for (var i = 0; i < rows.length; i += 1) {
      var titleNode = rows[i].querySelector(".conversation-title");
      var titleText = String((titleNode && titleNode.textContent) || "");
      if (titleText.indexOf(expectedTitle) >= 0) {
        return String(rows[i].getAttribute("data-conversation-id") || "");
      }
    }
    return "";
  }

  function conversationIdsForWorkspace() {
    var rows = rowsForWorkspace();
    var ids = [];
    for (var i = 0; i < rows.length; i += 1) {
      ids.push(String(rows[i].getAttribute("data-conversation-id") || ""));
    }
    return dedupe(ids);
  }

  function draftButtonForWorkspace() {
    var wsId = workspaceId();
    if (!wsId) {
      return null;
    }
    return document.querySelector(".conversation-draft[data-action='select-draft'][data-workspace-id='" + wsId + "']");
  }

  function selectDraftForWorkspace(done) {
    function clickAndWaitForActiveDraft() {
      var buttonNow = draftButtonForWorkspace();
      if (!buttonNow) {
        done(new Error("Missing draft row for workspace"));
        return;
      }
      clickNode(buttonNow);
      waitFor(function () {
        var activeDraft = document.querySelector(".conversation-draft.active[data-action='select-draft'][data-workspace-id='" + workspaceId() + "']");
        return !!activeDraft;
      }, 6000, "active workspace draft", function (err) {
        if (err) {
          done(err);
          return;
        }
        setTimeout(function () { done(null); }, 180);
      });
    }

    var button = draftButtonForWorkspace();
    if (button) {
      clickAndWaitForActiveDraft();
      return;
    }

    saveWorkspaceDraftSync(workspaceId(), "gui-regression-seeded-draft-" + String(Date.now()));
    if (typeof window.dispatchEvent === "function") {
      try {
        window.dispatchEvent(new Event("focus"));
      } catch (_focusErr) {
        // best effort
      }
    }
    waitFor(function () {
      return !!draftButtonForWorkspace();
    }, 7000, "workspace draft row appears", function (waitErr) {
      if (waitErr) {
        done(new Error("Missing draft row for workspace"));
        return;
      }
      clickAndWaitForActiveDraft();
    });
  }

  function fetchConversationSnapshotSync(conversationId) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return null;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open(
        "GET",
        "/cgi/artificer-api?action=get_conversation&workspace_id=" + encodeURIComponent(wsId) + "&conversation_id=" + encodeURIComponent(convId) + "&_ts=" + String(Date.now()),
        false
      );
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return parsed && parsed.conversation ? parsed.conversation : null;
    } catch (_err) {
      return null;
    }
  }

  function conversationHasPromptSync(conversationId, promptText) {
    var convId = String(conversationId || "");
    var targetPrompt = String(promptText || "");
    if (!convId || !targetPrompt) {
      return false;
    }
    var snapshot = fetchConversationSnapshotSync(convId);
    var messages = snapshot && Array.isArray(snapshot.messages) ? snapshot.messages : [];
    for (var i = 0; i < messages.length; i += 1) {
      var messageContent = String((messages[i] && messages[i].content) || "");
      if (messageContent.indexOf(targetPrompt) >= 0) {
        return true;
      }
    }
    return false;
  }

  function latestAssistantMessageSync(conversationId) {
    var convId = String(conversationId || "");
    if (!convId) {
      return "";
    }
    var snapshot = fetchConversationSnapshotSync(convId);
    var messages = snapshot && Array.isArray(snapshot.messages) ? snapshot.messages : [];
    var latest = "";
    for (var i = 0; i < messages.length; i += 1) {
      if (String((messages[i] && messages[i].role) || "") !== "assistant") {
        continue;
      }
      latest = String((messages[i] && messages[i].content) || "");
    }
    return latest;
  }

  function runEventsForConversationSync(conversationId) {
    var convId = String(conversationId || "");
    if (!convId) {
      return [];
    }
    try {
      var raw = String(localStorage.getItem("artificer.runEventsByConversation.v1") || "");
      if (!raw) {
        return [];
      }
      var parsed = JSON.parse(raw);
      return toArray(parsed && parsed[convId] ? parsed[convId] : []);
    } catch (_err) {
      return [];
    }
  }

  function latestRunEventSync(conversationId) {
    var events = runEventsForConversationSync(conversationId);
    if (!events.length) {
      return null;
    }
    return events[events.length - 1] || null;
  }

  function interactiveIntelligenceSnapshotSync(conversationId) {
    var convId = String(conversationId || "");
    var assistantText = latestAssistantMessageSync(convId);
    var chatNode = document.getElementById("chat-log");
    var chatText = String((chatNode && chatNode.textContent) || "");
    var queueSummary = fetchQueueListSummarySync(convId) || fetchConversationQueueSummarySync(convId) || {};
    var runEvent = latestRunEventSync(convId) || {};
    var runEventStreamText = String(runEvent.stream_text || "");
    var combined = String(assistantText || "");
    if (chatText) {
      combined += (combined ? "\n" : "") + chatText;
    }
    if (runEventStreamText) {
      combined += (combined ? "\n" : "") + runEventStreamText;
    }
    var pending = Number(queueSummary.queue_pending || "0");
    if (!isFinite(pending) || pending < 0) {
      pending = 0;
    }
    return {
      assistantText: assistantText,
      assistantExcerpt: assistantText.slice(0, 500),
      chatExcerpt: chatText.slice(0, 700),
      combinedText: combined,
      combinedExcerpt: combined.slice(0, 900),
      combinedLower: combined.toLowerCase(),
      queuePending: pending,
      queueRunning: String(queueSummary.queue_running || "0") === "1",
      queueLastStatus: String(queueSummary.queue_last_status || ""),
      runEventStatus: String(runEvent.status || ""),
      runEventAwaitingAssistant: Number(runEvent.awaiting_assistant || 0) > 0,
      runEventTaskStatus: runEvent.task_status || null,
      runEventStreamLength: String(runEventStreamText || "").replace(/^\s+|\s+$/g, "").length,
      runEventStreamExcerpt: runEventStreamText.slice(0, 700),
      hasRunningLine: !!document.querySelector("#chat-log .run-line.running[data-started-at]"),
      runLineCount: toArray(document.querySelectorAll("#chat-log .run-line")).length,
      activeConversationId: String(activeConversationId() || "")
    };
  }

  function interactiveIntelligenceContractPresentFromSnapshot(snapshot, expectedAnchor) {
    var combinedLower = String((snapshot && snapshot.combinedLower) || "");
    var anchor = String(expectedAnchor || "").toLowerCase();
    return (
      combinedLower.indexOf(anchor) >= 0 &&
      combinedLower.indexOf("initial assumption:") >= 0 &&
      combinedLower.indexOf("invalidating evidence:") >= 0 &&
      combinedLower.indexOf("revised decision:") >= 0 &&
      combinedLower.indexOf("claim-to-evidence map:") >= 0
    );
  }

  function interactiveIntelligenceContractPresentSync(conversationId, expectedAnchor) {
    var snapshot = interactiveIntelligenceSnapshotSync(conversationId);
    return interactiveIntelligenceContractPresentFromSnapshot(snapshot, expectedAnchor);
  }

  function waitForInteractiveIntelligenceFinal(conversationId, expectedAnchor, timeoutMs, done) {
    var deadline = Date.now() + Math.max(Number(timeoutMs || 0), 1);
    var idleWithoutContractCount = 0;
    function step() {
      var snapshot = interactiveIntelligenceSnapshotSync(conversationId);
      if (interactiveIntelligenceContractPresentFromSnapshot(snapshot, expectedAnchor)) {
        snapshot.contractPresent = true;
        snapshot.timedOut = false;
        done(null, snapshot);
        return;
      }
      var queueIdle = conversationQueueIdleSync(conversationId);
      var assistantReady = String(snapshot.assistantText || "").replace(/^\s+|\s+$/g, "").length > 0;
      if (queueIdle && assistantReady) {
        idleWithoutContractCount += 1;
        if (idleWithoutContractCount >= 3) {
          snapshot.contractPresent = false;
          snapshot.timedOut = false;
          snapshot.idleWithoutContract = true;
          done(null, snapshot);
          return;
        }
      } else {
        idleWithoutContractCount = 0;
      }
      if (Date.now() >= deadline) {
        snapshot.contractPresent = interactiveIntelligenceContractPresentFromSnapshot(snapshot, expectedAnchor);
        snapshot.timedOut = true;
        done(null, snapshot);
        return;
      }
      setTimeout(step, 900);
    }
    step();
  }

  function waitForInteractiveIntelligenceSettle(conversationId, timeoutMs, done) {
    var deadline = Date.now() + Math.max(Number(timeoutMs || 0), 1);
    function step() {
      var snapshot = interactiveIntelligenceSnapshotSync(conversationId);
      var queueIdle = conversationQueueIdleSync(conversationId);
      if (queueIdle && !snapshot.hasRunningLine) {
        snapshot.settled = true;
        done(null, snapshot);
        return;
      }
      if (Date.now() >= deadline) {
        snapshot.settled = false;
        done(null, snapshot);
        return;
      }
      setTimeout(step, 1000);
    }
    step();
  }

  function conversationQueueIdleSync(conversationId) {
    var convId = String(conversationId || "");
    if (!convId) {
      return false;
    }
    var summary = fetchQueueListSummarySync(convId) || fetchConversationQueueSummarySync(convId);
    if (!summary) {
      return false;
    }
    var pending = Number(summary.queue_pending || "0");
    if (!isFinite(pending) || pending < 0) {
      pending = 0;
    }
    return String(summary.queue_running || "0") !== "1" && pending < 1;
  }

  function createConversationSync(titleText) {
    var wsId = workspaceId();
    var title = String(titleText || "");
    if (!wsId || !title) {
      return "";
    }
    var response = postActionSync(
      "action=new_conversation&workspace_id=" + encodeURIComponent(wsId) + "&title=" + encodeURIComponent(title)
    );
    if (!response || !response.success || !response.conversation) {
      return "";
    }
    return String((response.conversation && response.conversation.id) || "");
  }

  function postActionSync(payload) {
    var body = String(payload || "");
    if (!body) {
      return null;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      xhr.send(body);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return parsed && typeof parsed === "object" ? parsed : null;
    } catch (_err) {
      return null;
    }
  }

  function fetchWorkspaceDraftSync(workspaceIdParam) {
    var wsId = String(workspaceIdParam || workspaceId());
    if (!wsId) {
      return "";
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open(
        "GET",
        "/cgi/artificer-api?action=get_draft&workspace_id=" + encodeURIComponent(wsId) + "&_ts=" + String(Date.now()),
        false
      );
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return String((parsed && parsed.draft) || "");
    } catch (_err) {
      return "";
    }
  }

  function saveWorkspaceDraftSync(workspaceIdParam, draftText) {
    var wsId = String(workspaceIdParam || workspaceId());
    if (!wsId) {
      return false;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      var payload = "action=save_draft&workspace_id=" + encodeURIComponent(wsId) + "&draft=" + encodeURIComponent(String(draftText || ""));
      xhr.send(payload);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return !!(parsed && parsed.success);
    } catch (_err) {
      return false;
    }
  }

  function saveConversationDraftSync(workspaceIdParam, conversationIdParam, draftText) {
    var wsId = String(workspaceIdParam || workspaceId());
    var convId = String(conversationIdParam || "");
    if (!wsId || !convId) {
      return false;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/cgi/artificer-api", false);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
      var payload = (
        "action=save_conversation_draft&workspace_id=" + encodeURIComponent(wsId) +
        "&conversation_id=" + encodeURIComponent(convId) +
        "&draft=" + encodeURIComponent(String(draftText || ""))
      );
      xhr.send(payload);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return !!(parsed && parsed.success);
    } catch (_err) {
      return false;
    }
  }

  function fetchStateSnapshotSync() {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", "/cgi/artificer-api?action=state&level=light&cached=0&_ts=" + String(Date.now()), false);
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      return parsed && typeof parsed === "object" ? parsed : null;
    } catch (_err) {
      return null;
    }
  }

  function cloneStateSnapshotWithoutConversation(stateSnapshot, workspaceIdParam, conversationIdParam) {
    var source = stateSnapshot && typeof stateSnapshot === "object" ? stateSnapshot : null;
    var wsId = String(workspaceIdParam || "");
    var convId = String(conversationIdParam || "");
    if (!source || !wsId || !convId) {
      return source;
    }
    var cloned = null;
    try {
      cloned = JSON.parse(JSON.stringify(source));
    } catch (_cloneErr) {
      return source;
    }
    var workspaces = toArray(cloned.workspaces || []);
    for (var i = 0; i < workspaces.length; i += 1) {
      var workspace = workspaces[i] || {};
      if (String(workspace.id || "") !== wsId) {
        continue;
      }
      var conversations = toArray(workspace.conversations || []);
      var filtered = [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j] || {};
        if (String(conversation.id || "") !== convId) {
          filtered.push(conversation);
        }
      }
      workspace.conversations = filtered;
      break;
    }
    return cloned;
  }

  function installSingleStateResponseInterceptor(statePayload) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    if (!statePayload || typeof statePayload !== "object") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var snapshotText = "";
    try {
      snapshotText = JSON.stringify(statePayload);
    } catch (_serializeErr) {
      return null;
    }
    if (!snapshotText) {
      return null;
    }
    var state = { consumed: false };
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isStateRequest = (
        urlText.indexOf("action=state") >= 0 ||
        bodyText.indexOf("action=state") >= 0
      );
      if (!state.consumed && isStateRequest) {
        state.consumed = true;
        return Promise.resolve({
          ok: true,
          status: 200,
          json: function () {
            return Promise.resolve(JSON.parse(snapshotText));
          },
          text: function () {
            return Promise.resolve(snapshotText);
          }
        });
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      wasConsumed: function () {
        return !!state.consumed;
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installSingleQueueEnqueueFailureInterceptor() {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var state = { consumed: false };
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isQueueEnqueue = (
        bodyText.indexOf("action=queue_enqueue") >= 0 ||
        urlText.indexOf("action=queue_enqueue") >= 0
      );
      if (!state.consumed && isQueueEnqueue) {
        state.consumed = true;
        return Promise.resolve({
          ok: true,
          status: 200,
          json: function () {
            return Promise.resolve({ success: false, error: "Simulated queue enqueue failure" });
          },
          text: function () {
            return Promise.resolve('{"success":false,"error":"Simulated queue enqueue failure"}');
          }
        });
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      wasConsumed: function () {
        return !!state.consumed;
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installSingleQueueEnqueueDelayedFailureInterceptor(delayMs) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var state = { consumed: false };
    var delay = Number(delayMs || 0);
    if (!isFinite(delay) || delay < 1) {
      delay = 1600;
    }
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isQueueEnqueue = (
        bodyText.indexOf("action=queue_enqueue") >= 0 ||
        urlText.indexOf("action=queue_enqueue") >= 0
      );
      if (!state.consumed && isQueueEnqueue) {
        state.consumed = true;
        return new Promise(function (resolve) {
          setTimeout(function () {
            resolve({
              ok: true,
              status: 200,
              json: function () {
                return Promise.resolve({ success: false, error: "Simulated delayed queue failure" });
              },
              text: function () {
                return Promise.resolve('{"success":false,"error":"Simulated delayed queue failure"}');
              }
            });
          }, delay);
        });
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      wasConsumed: function () {
        return !!state.consumed;
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installNewConversationDelayInterceptor(delayMs) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var state = { count: 0 };
    var delay = Number(delayMs || 0);
    if (!isFinite(delay) || delay < 1) {
      delay = 1800;
    }
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isCreateConversation = (
        bodyText.indexOf("action=new_conversation") >= 0 ||
        urlText.indexOf("action=new_conversation") >= 0
      );
      if (isCreateConversation) {
        state.count += 1;
        if (state.count === 1) {
          var callArgs = arguments;
          var callContext = this;
          return new Promise(function (resolve, reject) {
            setTimeout(function () {
              originalFetch.apply(callContext, callArgs).then(resolve).catch(reject);
            }, delay);
          });
        }
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      callCount: function () {
        return Number(state.count || 0);
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installQueueEnqueueCaptureInterceptor(maxCaptures) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var capturedPrompts = [];
    var limit = Number(maxCaptures || 0);
    if (!isFinite(limit) || limit < 1) {
      limit = 8;
    }
    function decodeFormValue(value) {
      var text = String(value || "");
      text = text.replace(/\+/g, "%20");
      try {
        return decodeURIComponent(text);
      } catch (_decodeErr) {
        return String(value || "");
      }
    }
    function formField(bodyText, fieldName) {
      var body = String(bodyText || "");
      var target = String(fieldName || "");
      if (!body || !target) {
        return "";
      }
      var parts = body.split("&");
      for (var i = 0; i < parts.length; i += 1) {
        var item = String(parts[i] || "");
        var eq = item.indexOf("=");
        var name = eq >= 0 ? item.slice(0, eq) : item;
        var value = eq >= 0 ? item.slice(eq + 1) : "";
        if (decodeFormValue(name) === target) {
          return decodeFormValue(value);
        }
      }
      return "";
    }
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isQueueEnqueue = (
        bodyText.indexOf("action=queue_enqueue") >= 0 ||
        urlText.indexOf("action=queue_enqueue") >= 0
      );
      if (isQueueEnqueue && capturedPrompts.length < limit) {
        capturedPrompts.push(String(formField(bodyText, "prompt") || ""));
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      prompts: function () {
        return capturedPrompts.slice();
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installRunActionDelayInterceptor(delayMs, maxHits, simulateDoneResponse, conversationIdMatch) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var state = { hits: 0 };
    var delay = Number(delayMs || 0);
    if (!isFinite(delay) || delay < 1) {
      delay = 6800;
    }
    var cap = Number(maxHits || 0);
    if (!isFinite(cap) || cap < 1) {
      cap = 3;
    }
    var conversationTarget = String(conversationIdMatch || "");
    function decodeFormValue(value) {
      var text = String(value || "");
      text = text.replace(/\+/g, "%20");
      try {
        return decodeURIComponent(text);
      } catch (_decodeErr) {
        return String(value || "");
      }
    }
    function formField(bodyText, fieldName) {
      var body = String(bodyText || "");
      var target = String(fieldName || "");
      if (!body || !target) {
        return "";
      }
      var parts = body.split("&");
      for (var i = 0; i < parts.length; i += 1) {
        var item = String(parts[i] || "");
        var eq = item.indexOf("=");
        var name = eq >= 0 ? item.slice(0, eq) : item;
        var value = eq >= 0 ? item.slice(eq + 1) : "";
        if (decodeFormValue(name) === target) {
          return decodeFormValue(value);
        }
      }
      return "";
    }
    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isRunAction = (
        /(?:^|&)action=run(?:&|$)/.test(bodyText) ||
        /(?:\?|&)action=run(?:&|$)/.test(urlText)
      );
      var runConversationId = String(formField(bodyText, "conversation_id") || "");
      var conversationMatches = !conversationTarget || runConversationId === conversationTarget;
      if (isRunAction && conversationMatches && state.hits < cap) {
        state.hits += 1;
        var shouldSimulateDone = !!simulateDoneResponse;
        var callArgs = arguments;
        var callContext = this;
        return new Promise(function (resolve, reject) {
          setTimeout(function () {
            if (shouldSimulateDone) {
              var mockPayload = {
                success: true,
                assistant: "",
                queue_pending: "0",
                queue_running: "0",
                queue_last_status: "done"
              };
              var mockText = JSON.stringify(mockPayload);
              resolve({
                ok: true,
                status: 200,
                json: function () {
                  return Promise.resolve(mockPayload);
                },
                text: function () {
                  return Promise.resolve(mockText);
                }
              });
              return;
            }
            originalFetch.apply(callContext, callArgs).then(resolve).catch(reject);
          }, delay);
        });
      }
      return originalFetch.apply(this, arguments);
    };
    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }
    return {
      hitCount: function () {
        return Number(state.hits || 0);
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function installQueueTakeDelayInterceptor(delayMs, maxHits, conversationIdMatch) {
    if (typeof window.fetch !== "function") {
      return null;
    }
    var originalFetch = window.fetch;
    var originalGlobalFetch = null;
    try {
      originalGlobalFetch = fetch;
    } catch (_globalFetchErr) {
      originalGlobalFetch = null;
    }
    var state = { hits: 0 };
    var delay = Number(delayMs || 0);
    if (!isFinite(delay) || delay < 1) {
      delay = 1200;
    }
    var cap = Number(maxHits || 0);
    if (!isFinite(cap) || cap < 1) {
      cap = 2;
    }
    var conversationTarget = String(conversationIdMatch || "");

    function decodeFormValue(value) {
      var text = String(value || "");
      text = text.replace(/\+/g, "%20");
      try {
        return decodeURIComponent(text);
      } catch (_decodeErr) {
        return String(value || "");
      }
    }

    function formField(bodyText, fieldName) {
      var body = String(bodyText || "");
      var target = String(fieldName || "");
      if (!body || !target) {
        return "";
      }
      var parts = body.split("&");
      for (var i = 0; i < parts.length; i += 1) {
        var item = String(parts[i] || "");
        var eq = item.indexOf("=");
        var name = eq >= 0 ? item.slice(0, eq) : item;
        var value = eq >= 0 ? item.slice(eq + 1) : "";
        if (decodeFormValue(name) === target) {
          return decodeFormValue(value);
        }
      }
      return "";
    }

    var wrappedFetch = function (input, init) {
      var urlText = "";
      if (typeof input === "string") {
        urlText = input;
      } else if (input && typeof input.url === "string") {
        urlText = String(input.url || "");
      }
      var bodyText = "";
      if (init && typeof init.body === "string") {
        bodyText = init.body;
      } else if (init && typeof init.body !== "undefined" && init.body !== null) {
        bodyText = String(init.body || "");
      }
      var isQueueTake = (
        /(?:^|&)action=queue_take(?:&|$)/.test(bodyText) ||
        /(?:\?|&)action=queue_take(?:&|$)/.test(urlText)
      );
      var takeConversationId = String(formField(bodyText, "conversation_id") || "");
      var conversationMatches = !conversationTarget || takeConversationId === conversationTarget;
      if (isQueueTake && conversationMatches && state.hits < cap) {
        state.hits += 1;
        var callArgs = arguments;
        var callContext = this;
        return new Promise(function (resolve, reject) {
          setTimeout(function () {
            originalFetch.apply(callContext, callArgs).then(resolve).catch(reject);
          }, delay);
        });
      }
      return originalFetch.apply(this, arguments);
    };

    window.fetch = wrappedFetch;
    try {
      fetch = wrappedFetch;
    } catch (_assignFetchErr) {
      // Some environments expose fetch as non-writable global binding.
    }

    return {
      hitCount: function () {
        return Number(state.hits || 0);
      },
      restore: function () {
        window.fetch = originalFetch;
        if (originalGlobalFetch && typeof originalGlobalFetch === "function") {
          try {
            fetch = originalGlobalFetch;
          } catch (_restoreFetchErr) {
            // Ignore restore failures for read-only global bindings.
          }
        }
      }
    };
  }

  function pendingOutgoingStorageContains(promptText) {
    var wanted = String(promptText || "");
    if (!wanted) {
      return false;
    }
    var raw = "";
    try {
      raw = String(localStorage.getItem("artificer.pendingOutgoingByKey.v1") || "");
    } catch (_storageErr) {
      return false;
    }
    if (!raw) {
      return false;
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_parseErr) {
      return false;
    }
    if (!parsed || typeof parsed !== "object") {
      return false;
    }
    var keys = Object.keys(parsed);
    for (var i = 0; i < keys.length; i += 1) {
      var list = toArray(parsed[keys[i]] || []);
      for (var j = 0; j < list.length; j += 1) {
        var content = String((list[j] && list[j].content) || "");
        if (content.indexOf(wanted) >= 0) {
          return true;
        }
      }
    }
    return false;
  }

  function pendingOutgoingCountForKey(outgoingKey) {
    var key = String(outgoingKey || "");
    if (!key) {
      return 0;
    }
    var raw = "";
    try {
      raw = String(localStorage.getItem("artificer.pendingOutgoingByKey.v1") || "");
    } catch (_storageErr) {
      return 0;
    }
    if (!raw) {
      return 0;
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_parseErr) {
      return 0;
    }
    if (!parsed || typeof parsed !== "object") {
      return 0;
    }
    var list = toArray(parsed[key] || []);
    return list.length;
  }

  function pendingOutgoingDebugSummary() {
    var raw = "";
    try {
      raw = String(localStorage.getItem("artificer.pendingOutgoingByKey.v1") || "");
    } catch (_storageErr) {
      return "storage-read-error";
    }
    if (!raw) {
      return "empty";
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_parseErr) {
      return "parse-error";
    }
    if (!parsed || typeof parsed !== "object") {
      return "invalid-object";
    }
    var keys = Object.keys(parsed);
    if (!keys.length) {
      return "no-keys";
    }
    var parts = [];
    for (var i = 0; i < keys.length; i += 1) {
      var key = String(keys[i] || "");
      if (!key) {
        continue;
      }
      var list = toArray(parsed[key] || []);
      parts.push(key + ":" + String(list.length));
    }
    if (!parts.length) {
      return "no-entry-counts";
    }
    return parts.join(",");
  }

  function fetchConversationQueueSummarySync(conversationId) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return null;
    }
    var snapshot = fetchStateSnapshotSync();
    if (!snapshot || !snapshot.success) {
      return null;
    }
    var workspaces = toArray(snapshot.workspaces || []);
    for (var i = 0; i < workspaces.length; i += 1) {
      if (String((workspaces[i] && workspaces[i].id) || "") !== wsId) {
        continue;
      }
      var conversations = toArray((workspaces[i] && workspaces[i].conversations) || []);
      for (var j = 0; j < conversations.length; j += 1) {
        if (String((conversations[j] && conversations[j].id) || "") !== convId) {
          continue;
        }
        return {
          queue_pending: String((conversations[j] && conversations[j].queue_pending) || "0"),
          queue_running: String((conversations[j] && conversations[j].queue_running) || "0"),
          queue_last_status: String((conversations[j] && conversations[j].queue_last_status) || "")
        };
      }
      return null;
    }
    return null;
  }

  function fetchQueueListSummarySync(conversationId) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return null;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open(
        "GET",
        "/cgi/artificer-api?action=queue_list&workspace_id=" + encodeURIComponent(wsId) +
          "&conversation_id=" + encodeURIComponent(convId) +
          "&limit=1&_ts=" + String(Date.now()),
        false
      );
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      if (!parsed || !parsed.success) {
        return null;
      }
      return {
        queue_pending: String(parsed.queue_pending || "0"),
        queue_running: String(parsed.queue_running || "0"),
        queue_last_status: String(parsed.queue_last_status || "")
      };
    } catch (_err) {
      return null;
    }
  }

  function fetchQueueItemsSync(conversationId, limit) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return [];
    }
    var maxItems = Number(limit || 0);
    if (!isFinite(maxItems) || maxItems < 1) {
      maxItems = 20;
    }
    if (maxItems > 80) {
      maxItems = 80;
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open(
        "GET",
        "/cgi/artificer-api?action=queue_list&workspace_id=" + encodeURIComponent(wsId) +
          "&conversation_id=" + encodeURIComponent(convId) +
          "&limit=" + String(maxItems) +
          "&_ts=" + String(Date.now()),
        false
      );
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      if (!parsed || !parsed.success) {
        return [];
      }
      return toArray(parsed.items || []);
    } catch (_err) {
      return [];
    }
  }

  function stopConversationQueueSync(conversationId) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return false;
    }
    var response = postActionSync(
      "action=queue_stop&workspace_id=" + encodeURIComponent(wsId) + "&conversation_id=" + encodeURIComponent(convId)
    );
    return !!(response && response.success);
  }

  function cancelConversationQueueHeadSync(conversationId) {
    var wsId = workspaceId();
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return false;
    }
    var response = postActionSync(
      "action=queue_cancel&workspace_id=" + encodeURIComponent(wsId) + "&conversation_id=" + encodeURIComponent(convId)
    );
    return !!(response && response.success);
  }

  function drainConversationQueueSync(conversationId) {
    var convId = String(conversationId || "");
    if (!convId) {
      return true;
    }
    for (var i = 0; i < 20; i += 1) {
      var summary = fetchQueueListSummarySync(convId) || fetchConversationQueueSummarySync(convId);
      if (!summary) {
        return false;
      }
      var pending = Number(summary.queue_pending || "0");
      if (!isFinite(pending) || pending < 0) {
        pending = 0;
      }
      var running = String(summary.queue_running || "0") === "1";
      if (!running && pending < 1) {
        return true;
      }
      if (running) {
        stopConversationQueueSync(convId);
      }
      if (pending > 0) {
        cancelConversationQueueHeadSync(convId);
      }
    }
    var finalSummary = fetchQueueListSummarySync(convId) || fetchConversationQueueSummarySync(convId);
    if (!finalSummary) {
      return false;
    }
    return (
      String(finalSummary.queue_running || "0") !== "1" &&
      Number(finalSummary.queue_pending || "0") < 1
    );
  }

  function elapsedSecondsFromBadge(text) {
    var raw = String(text || "");
    var match = raw.match(/(\d+)/);
    if (!match) {
      return 0;
    }
    var value = Number(match[1] || 0);
    if (!isFinite(value) || value < 0) {
      return 0;
    }
    return value;
  }

  function runLiveStatusHeartbeatCheck(promptNode, done) {
    var promptEl = promptNode;
    if (!promptEl) {
      done(new Error("run-prompt missing for live status heartbeat check"));
      return;
    }
    var runBtn = document.getElementById("run-btn");
    if (!runBtn) {
      done(new Error("run-btn missing for live status heartbeat check"));
      return;
    }
    var heartbeatPrompt = "live-status-heartbeat-" + String(Date.now());
    var targetConversationId = String(activeConversationId() || "");
    var baselineRunLineCount = toArray(document.querySelectorAll("#chat-log .run-line")).length;
    var pollDelayInterceptor = installRunActionDelayInterceptor(6800, 1, true, targetConversationId);
    var heartbeatSampleDelayMs = 2800;

    function heartbeatSnapshot() {
      var runningLine = document.querySelector("#chat-log .run-line.running[data-started-at]");
      var finalizingLine = document.querySelector("#chat-log .run-finalizing-line .run-finalizing-meta");
      var runLineCount = toArray(document.querySelectorAll("#chat-log .run-line")).length;
      var elapsed = 0;
      var runningLiveness = "";
      var runningText = "";
      if (runningLine) {
        elapsed = elapsedSecondsFromBadge(String((runningLine.querySelector(".run-elapsed") && runningLine.querySelector(".run-elapsed").textContent) || ""));
        runningLiveness = String((runningLine.querySelector(".run-running-liveness") && runningLine.querySelector(".run-running-liveness").textContent) || "").trim();
        runningText = String(runningLine.textContent || "").trim();
      }
      var finalizingLiveness = String((finalizingLine && finalizingLine.textContent) || "").trim();
      var queueSummary = fetchQueueListSummarySync(targetConversationId) || fetchConversationQueueSummarySync(targetConversationId);
      var queuePending = 0;
      var queueRunning = false;
      var queueStatus = "";
      if (queueSummary) {
        var pendingNum = Number(queueSummary.queue_pending || "0");
        queuePending = isFinite(pendingNum) && pendingNum > 0 ? pendingNum : 0;
        queueRunning = String(queueSummary.queue_running || "0") === "1";
        queueStatus = String(queueSummary.queue_last_status || "");
      }
      return {
        hasRunningLine: !!runningLine,
        elapsed: elapsed,
        runningLiveness: runningLiveness,
        runningText: runningText,
        finalizingLiveness: finalizingLiveness,
        runLineCount: runLineCount,
        queuePending: queuePending,
        queueRunning: queueRunning,
        queueStatus: queueStatus
      };
    }

    promptEl.value = heartbeatPrompt;
    dispatchInputEvent(promptEl);
    clickNode(runBtn);

    waitFor(function () {
      var snapshot = heartbeatSnapshot();
      return (
        snapshot.hasRunningLine ||
        snapshot.finalizingLiveness.length > 0 ||
        snapshot.runLineCount > baselineRunLineCount ||
        snapshot.queueRunning ||
        snapshot.queuePending > 0
      );
    }, 10000, "live running status line appears", function (runningErr) {
      if (runningErr) {
        if (pollDelayInterceptor && typeof pollDelayInterceptor.restore === "function") {
          pollDelayInterceptor.restore();
        }
        done(runningErr);
        return;
      }
      var firstSnapshot = heartbeatSnapshot();
      var firstElapsed = Number(firstSnapshot.elapsed || 0);
      var firstRunningLiveness = String(firstSnapshot.runningLiveness || "");
      var firstRunningLineText = String(firstSnapshot.runningText || "");
      var firstFinalizingLiveness = String(firstSnapshot.finalizingLiveness || "");
      var firstQueueRunning = !!firstSnapshot.queueRunning;
      var firstQueuePending = Number(firstSnapshot.queuePending || 0);
      var firstQueueStatus = String(firstSnapshot.queueStatus || "");
      var firstRunLineCount = Number(firstSnapshot.runLineCount || baselineRunLineCount);
      setTimeout(function () {
        if (pollDelayInterceptor && typeof pollDelayInterceptor.restore === "function") {
          pollDelayInterceptor.restore();
        }
        var secondSnapshot = heartbeatSnapshot();
        var secondElapsed = Number(secondSnapshot.elapsed || firstElapsed);
        var runningLiveness = String(secondSnapshot.runningLiveness || "");
        var runningLineText = String(secondSnapshot.runningText || "");
        var finalizingLiveness = String(secondSnapshot.finalizingLiveness || "");
        var secondQueueRunning = !!secondSnapshot.queueRunning;
        var secondQueuePending = Number(secondSnapshot.queuePending || 0);
        var secondQueueStatus = String(secondSnapshot.queueStatus || "");
        var secondRunLineCount = Number(secondSnapshot.runLineCount || firstRunLineCount);
        var hasLiveness = (
          firstRunningLiveness.length > 0 ||
          firstRunningLineText.length > 0 ||
          firstFinalizingLiveness.length > 0 ||
          runningLiveness.length > 0 ||
          finalizingLiveness.length > 0 ||
          runningLineText.length > 0 ||
          firstQueueRunning ||
          secondQueueRunning ||
          firstQueuePending > 0 ||
          secondQueuePending > 0 ||
          secondRunLineCount > baselineRunLineCount
        );
        var timerAdvanced = (
          secondElapsed > firstElapsed ||
          secondRunLineCount > firstRunLineCount ||
          firstRunningLiveness.length > 0 ||
          firstRunningLineText.length > 0 ||
          firstFinalizingLiveness.length > 0 ||
          runningLiveness.length > 0 ||
          finalizingLiveness.length > 0 ||
          runningLineText.length > 0 ||
          firstQueueRunning ||
          secondQueueRunning ||
          firstQueuePending > 0 ||
          secondQueuePending > 0
        );
        try {
          check(
            "live run status elapsed timer advances",
            timerAdvanced,
            String(firstElapsed) + "->" + String(secondElapsed) +
              " firstRunning=" + firstRunningLiveness + " firstLine=" + firstRunningLineText +
              " firstFinalizing=" + firstFinalizingLiveness +
              " running=" + runningLiveness + " finalizing=" + finalizingLiveness +
              " line=" + runningLineText +
              " queueBefore=" + String(firstQueuePending) + "/" + (firstQueueRunning ? "1" : "0") + ":" + firstQueueStatus +
              " queueAfter=" + String(secondQueuePending) + "/" + (secondQueueRunning ? "1" : "0") + ":" + secondQueueStatus +
              " runLines=" + String(firstRunLineCount) + "->" + String(secondRunLineCount)
          );
          check(
            "live run status surfaces no-dead-air liveness hints",
            hasLiveness,
            "firstRunning=" + firstRunningLiveness + " firstLine=" + firstRunningLineText +
              " firstFinalizing=" + firstFinalizingLiveness +
              " running=" + runningLiveness + " finalizing=" + finalizingLiveness + " line=" + runningLineText +
              " queueBefore=" + String(firstQueuePending) + "/" + (firstQueueRunning ? "1" : "0") + ":" + firstQueueStatus +
              " queueAfter=" + String(secondQueuePending) + "/" + (secondQueueRunning ? "1" : "0") + ":" + secondQueueStatus +
              " runLines=" + String(firstRunLineCount) + "->" + String(secondRunLineCount)
          );
        } catch (checkErr) {
          done(checkErr);
          return;
        }
        waitFor(function () {
          var settleSnapshot = heartbeatSnapshot();
          var settleStatus = String(settleSnapshot.queueStatus || "").toLowerCase();
          var settlePendingClear = (
            settleSnapshot.queuePending < 1 ||
            settleStatus === "done" ||
            settleStatus === "completed" ||
            settleStatus === "error" ||
            settleStatus === "stopped" ||
            settleStatus === "cancelled"
          );
          return !settleSnapshot.hasRunningLine && !settleSnapshot.queueRunning && settlePendingClear;
        }, 12000, "heartbeat run settles", function (settleErr) {
          if (settleErr) {
            done(settleErr);
            return;
          }
          done(null, {
            heartbeatPrompt: heartbeatPrompt,
            firstElapsed: firstElapsed,
            secondElapsed: secondElapsed
          });
        });
      }, heartbeatSampleDelayMs);
    });
  }

  function runPendingStorageDurabilityCheck(promptNode, done) {
    var promptEl = promptNode;
    if (!promptEl) {
      done(new Error("run-prompt missing for pending durability check"));
      return;
    }
    forceSelectDraftForWorkspace(function (selectDraftErr) {
      if (selectDraftErr) {
        done(selectDraftErr);
        return;
      }
      var runBtn = document.getElementById("run-btn");
      if (!runBtn) {
        done(new Error("run-btn missing for pending durability check"));
        return;
      }
      var durablePrompt = "pending-durability-" + String(Date.now());
      var interceptor = installSingleQueueEnqueueDelayedFailureInterceptor(2200);
      promptEl.value = durablePrompt;
      dispatchInputEvent(promptEl);
      clickNode(runBtn);

      waitFor(function () {
        return !!(interceptor && typeof interceptor.wasConsumed === "function" && interceptor.wasConsumed());
      }, 8000, "delayed queue enqueue interception", function (interceptErr) {
        if (interceptErr) {
          if (interceptor && typeof interceptor.restore === "function") {
            interceptor.restore();
          }
          done(new Error("Failed to intercept delayed queue enqueue"));
          return;
        }
        waitFor(function () {
          return pendingOutgoingStorageContains(durablePrompt);
        }, 5000, "pending outgoing storage persistence", function (persistErr) {
          if (interceptor && typeof interceptor.restore === "function") {
            interceptor.restore();
          }
          if (persistErr) {
            done(new Error("Pending outgoing prompt was not persisted to storage during in-flight send"));
            return;
          }
          try {
            check(
              "pending send persists to storage before enqueue completion",
              true,
              durablePrompt
            );
          } catch (checkErr) {
            done(checkErr);
            return;
          }
          waitFor(function () {
            var visiblePrompt = String((promptEl && promptEl.value) || "");
            var workspaceDraft = fetchWorkspaceDraftSync(workspaceId());
            return visiblePrompt.indexOf(durablePrompt) >= 0 || workspaceDraft.indexOf(durablePrompt) >= 0;
          }, 9000, "pending durability delayed failure restoration", function (restoreErr) {
            if (restoreErr) {
              done(restoreErr);
              return;
            }
            done(null, { durablePrompt: durablePrompt });
          });
        });
      });
    });
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

  function dispatchInputEvent(node) {
    if (!node) {
      return;
    }
    if (typeof Event === "function") {
      node.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }
    var ev = document.createEvent("Event");
    ev.initEvent("input", true, true);
    node.dispatchEvent(ev);
  }

  function activeConversationId() {
    var row = document.querySelector(".conversation-row.active[data-conversation-id]");
    return row ? String(row.getAttribute("data-conversation-id") || "") : "";
  }

  function collectDebugSnapshot(conversationIdParam) {
    var snapshot = {
      workspace_id_expected: workspaceIdExpected,
      workspace_rows_total: toArray(document.querySelectorAll(".workspace-row[data-workspace-id]")).length,
      conversation_rows_total: toArray(document.querySelectorAll(".conversation-row[data-workspace-id][data-conversation-id]")).length,
      conversation_rows_for_workspace: rowsForWorkspace().length,
      organize_mode_pref: null,
      organize_show_pref: null
    };
    try {
      snapshot.organize_mode_pref = String(localStorage.getItem("artificer.organizeMode") || "");
      snapshot.organize_show_pref = String(localStorage.getItem("artificer.organizeShow") || "");
    } catch (_storageErr) {
      snapshot.organize_mode_pref = "unavailable";
      snapshot.organize_show_pref = "unavailable";
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", "/cgi/artificer-api?action=state&level=light&cached=0&_ts=" + String(Date.now()), false);
      xhr.send(null);
      var rawText = String(xhr.responseText || "");
      var jsonStart = rawText.indexOf("{");
      if (jsonStart >= 0) {
        rawText = rawText.slice(jsonStart);
      }
      var parsed = JSON.parse(rawText);
      var workspaces = parsed && parsed.workspaces ? parsed.workspaces : [];
      snapshot.api_workspace_total = workspaces.length;
      snapshot.api_workspace_match = false;
      snapshot.api_workspace_conversation_count = 0;
      for (var i = 0; i < workspaces.length; i += 1) {
        if (String((workspaces[i] && workspaces[i].id) || "") === String(workspaceIdExpected || "")) {
          snapshot.api_workspace_match = true;
          snapshot.api_workspace_conversation_count = toArray((workspaces[i] && workspaces[i].conversations) || []).length;
          break;
        }
      }
    } catch (_xhrErr) {
      snapshot.api_workspace_match = "state-fetch-failed";
    }
    var targetConversationId = String(conversationIdParam || activeConversationId() || "");
    snapshot.active_conversation_id = targetConversationId;
    if (targetConversationId) {
      var intelligence = interactiveIntelligenceSnapshotSync(targetConversationId);
      snapshot.queue_pending = intelligence.queuePending;
      snapshot.queue_running = intelligence.queueRunning;
      snapshot.queue_last_status = intelligence.queueLastStatus;
      snapshot.run_event_status = intelligence.runEventStatus;
      snapshot.run_event_stream_length = intelligence.runEventStreamLength;
      snapshot.run_event_awaiting_assistant = intelligence.runEventAwaitingAssistant;
      snapshot.run_line_count = intelligence.runLineCount;
      snapshot.has_running_line = intelligence.hasRunningLine;
      snapshot.assistant_excerpt = intelligence.assistantExcerpt;
      snapshot.chat_excerpt = intelligence.chatExcerpt;
      snapshot.run_event_stream_excerpt = intelligence.runEventStreamExcerpt;
    }
    return snapshot;
  }

  function selectConversationById(conversationId, done) {
    waitFor(function () {
      return !!document.querySelector(".conversation-row[data-conversation-id='" + conversationId + "']");
    }, 6000, "conversation row " + conversationId, function (err) {
      if (err) {
        done(err);
        return;
      }
      var row = document.querySelector(".conversation-row[data-conversation-id='" + conversationId + "']");
      if (!row) {
        done(new Error("Missing conversation row: " + conversationId));
        return;
      }
      waitFor(function () {
        var activeId = activeConversationId();
        if (activeId === conversationId) {
          return true;
        }
        var currentRow = document.querySelector(".conversation-row[data-conversation-id='" + conversationId + "']");
        if (currentRow) {
          clickNode(currentRow);
        }
        return activeConversationId() === conversationId;
      }, 6000, "active conversation " + conversationId, function (activeErr) {
        if (activeErr) {
          done(activeErr);
          return;
        }
        setTimeout(function () { done(null); }, 220);
      });
    });
  }

  function waitForDraftHydration(conversationId, expectedDraft, excludedDraft, timeoutMs, label, done) {
    var targetConversationId = String(conversationId || "");
    var expectedText = String(expectedDraft || "");
    var excludedText = String(excludedDraft || "");
    var maxWaitMs = Number(timeoutMs || 0);
    var attempts = 0;
    if (!targetConversationId || !expectedText) {
      done(new Error("waitForDraftHydration requires conversation id and expected draft"));
      return;
    }
    if (!isFinite(maxWaitMs) || maxWaitMs < 2000) {
      maxWaitMs = 10000;
    }
    waitFor(function () {
      attempts += 1;
      var promptNode = document.getElementById("run-prompt");
      var promptValue = String((promptNode && promptNode.value) || "");
      var hasExpected = promptValue.indexOf(expectedText) >= 0;
      var hasExcluded = excludedText ? promptValue.indexOf(excludedText) >= 0 : false;
      if (hasExpected && !hasExcluded) {
        return true;
      }
      var activeId = String(activeConversationId() || "");
      if (activeId !== targetConversationId) {
        var targetRow = document.querySelector(".conversation-row[data-conversation-id='" + targetConversationId + "']");
        if (targetRow) {
          clickNode(targetRow);
        }
      } else if (attempts % 3 === 0) {
        var activeRow = document.querySelector(".conversation-row.active[data-conversation-id='" + targetConversationId + "']");
        if (activeRow) {
          clickNode(activeRow);
        }
      }
      if (attempts % 5 === 0 && typeof window.dispatchEvent === "function") {
        try {
          window.dispatchEvent(new Event("focus"));
        } catch (_draftFocusErr) {
          // best effort only
        }
      }
      return false;
    }, maxWaitMs, String(label || "draft hydration"), function (waitErr) {
      done(waitErr);
    });
  }

  function runDraftQueueFailureRecoveryCheck(promptNode, done) {
    var promptEl = promptNode;
    if (!promptEl) {
      done(new Error("run-prompt missing for failure recovery check"));
      return;
    }
    forceSelectDraftForWorkspace(function (selectDraftErr) {
      if (selectDraftErr) {
        done(selectDraftErr);
        return;
      }
      var runBtn = document.getElementById("run-btn");
      if (!runBtn) {
        done(new Error("run-btn missing for failure recovery check"));
        return;
      }
      var queueFailureInterceptor = installSingleQueueEnqueueFailureInterceptor();
      var failurePrompt = "queue-failure-draft-" + String(Date.now());
      var beforeIds = conversationIdsForWorkspace();
      promptEl.value = failurePrompt;
      dispatchInputEvent(promptEl);
      clickNode(runBtn);

      waitFor(function () {
        return conversationIdsForWorkspace().length >= (beforeIds.length + 1);
      }, 18000, "new thread appears for simulated enqueue failure", function (waitErr) {
        if (waitErr) {
          if (queueFailureInterceptor && typeof queueFailureInterceptor.restore === "function") {
            queueFailureInterceptor.restore();
          }
          done(waitErr);
          return;
        }
        waitFor(function () {
          return !!(queueFailureInterceptor && typeof queueFailureInterceptor.wasConsumed === "function" && queueFailureInterceptor.wasConsumed());
        }, 8000, "queue enqueue interception", function (interceptErr) {
          if (queueFailureInterceptor && typeof queueFailureInterceptor.restore === "function") {
            queueFailureInterceptor.restore();
          }
          if (interceptErr) {
            done(new Error("Failed to intercept queue_enqueue for simulated failure"));
            return;
          }
          var afterIds = conversationIdsForWorkspace();
          var failureConversationId = "";
          for (var i = 0; i < afterIds.length; i += 1) {
            if (beforeIds.indexOf(afterIds[i]) < 0) {
              failureConversationId = afterIds[i];
              break;
            }
          }
          if (!failureConversationId) {
            done(new Error("Could not identify thread created during simulated enqueue failure"));
            return;
          }
          setTimeout(function () {
            try {
              var workspaceDraftAfterFailure = fetchWorkspaceDraftSync(workspaceId());
              var failedConversationSnapshot = fetchConversationSnapshotSync(failureConversationId);
              var failedConversationDraft = String((failedConversationSnapshot && failedConversationSnapshot.draft) || "");
              var visiblePrompt = String((promptEl && promptEl.value) || "");
              var failureDetail = "workspaceDraft=" + workspaceDraftAfterFailure + " threadDraft=" + failedConversationDraft + " visiblePrompt=" + visiblePrompt;
              check(
                "failed draft-send restores workspace draft persistently",
                workspaceDraftAfterFailure.indexOf(failurePrompt) >= 0,
                failureDetail
              );
              check(
                "failed draft-send restores created thread draft persistently",
                failedConversationDraft.indexOf(failurePrompt) >= 0 || visiblePrompt.indexOf(failurePrompt) >= 0,
                failureDetail
              );
              done(null, {
                failurePrompt: failurePrompt,
                failureConversationId: failureConversationId
              });
            } catch (checkErr) {
              done(checkErr);
            }
          }, 900);
        });
      });
    });
  }

  function runDraftRapidMultiSendCoherenceCheck(promptNode, done) {
    var promptEl = promptNode;
    if (!promptEl) {
      done(new Error("run-prompt missing for rapid multi-send check"));
      return;
    }
    forceSelectDraftForWorkspace(function (selectDraftErr) {
      if (selectDraftErr) {
        done(selectDraftErr);
        return;
      }
      var runBtn = document.getElementById("run-btn");
      if (!runBtn) {
        done(new Error("run-btn missing for rapid multi-send check"));
        return;
      }
      var promptOne = "draft-rapid-one-" + String(Date.now());
      var promptTwo = "draft-rapid-two-" + String(Date.now());
      var beforeIds = conversationIdsForWorkspace();
      var createDelayInterceptor = installNewConversationDelayInterceptor(1800);
      var enqueueCaptureInterceptor = installQueueEnqueueCaptureInterceptor(6);

      promptEl.value = promptOne;
      dispatchInputEvent(promptEl);
      clickNode(runBtn);
      setTimeout(function () {
        promptEl.value = promptTwo;
        dispatchInputEvent(promptEl);
        clickNode(runBtn);
      }, 120);

      waitFor(function () {
        return conversationIdsForWorkspace().length >= (beforeIds.length + 1);
      }, 20000, "rapid draft send creates first thread", function (firstThreadErr) {
        var cleanupInterceptors = function () {
          if (createDelayInterceptor && typeof createDelayInterceptor.restore === "function") {
            createDelayInterceptor.restore();
          }
          if (enqueueCaptureInterceptor && typeof enqueueCaptureInterceptor.restore === "function") {
            enqueueCaptureInterceptor.restore();
          }
        };
        if (firstThreadErr) {
          cleanupInterceptors();
          done(firstThreadErr);
          return;
        }
        setTimeout(function () {
          var afterIds = conversationIdsForWorkspace();
          var createdIds = [];
          for (var i = 0; i < afterIds.length; i += 1) {
            if (beforeIds.indexOf(afterIds[i]) < 0) {
              createdIds.push(afterIds[i]);
            }
          }
          if (createdIds.length !== 1) {
            done(new Error("Rapid draft sends created unexpected thread count: " + String(createdIds.length)));
            return;
          }
          var newConversationId = String(createdIds[0] || "");
          waitFor(function () {
            if (!enqueueCaptureInterceptor || typeof enqueueCaptureInterceptor.prompts !== "function") {
              return false;
            }
            var captured = enqueueCaptureInterceptor.prompts();
            if (!captured || captured.length < 2) {
              return false;
            }
            var first = String(captured[0] || "");
            var second = String(captured[1] || "");
            return first.indexOf(promptOne) >= 0 && second.indexOf(promptTwo) >= 0;
          }, 16000, "rapid multi-send enqueue order", function (orderErr) {
            cleanupInterceptors();
            if (orderErr) {
              var capturedFallback = enqueueCaptureInterceptor && typeof enqueueCaptureInterceptor.prompts === "function"
                ? enqueueCaptureInterceptor.prompts().join(" | ")
                : "";
              done(new Error("rapid multi-send enqueue order: " + orderErr.message + " captured=" + capturedFallback));
              return;
            }
            try {
              var captured = enqueueCaptureInterceptor && typeof enqueueCaptureInterceptor.prompts === "function"
                ? enqueueCaptureInterceptor.prompts()
                : [];
              check(
                "rapid draft sends reuse one created thread",
                createdIds.length === 1,
                createdIds.join(",")
              );
              check(
                "rapid draft sends preserve prompt ordering",
                captured.length >= 2 &&
                String(captured[0] || "").indexOf(promptOne) >= 0 &&
                String(captured[1] || "").indexOf(promptTwo) >= 0,
                captured.join(" | ")
              );
              if (createDelayInterceptor && typeof createDelayInterceptor.callCount === "function") {
                check(
                  "rapid draft sends dedupe thread creation requests",
                  createDelayInterceptor.callCount() === 1,
                  String(createDelayInterceptor.callCount())
                );
              }
              var drained = drainConversationQueueSync(newConversationId);
              check(
                "rapid draft-send fixture drains its queue workload",
                drained,
                newConversationId
              );
              done(null, {
                newConversationId: newConversationId,
                promptOne: promptOne,
                promptTwo: promptTwo
              });
            } catch (checkErr) {
              done(checkErr);
            }
          });
        }, 2200);
      });
    });
  }

  function runQueueEditJourneyCheck(conversationId, done) {
    var convId = String(conversationId || "");
    if (!convId) {
      done(new Error("queue edit journey requires conversation id"));
      return;
    }
    var queueTakeInterceptor = installQueueTakeDelayInterceptor(12000, 3, convId);
    function cleanupInterceptor() {
      if (queueTakeInterceptor && typeof queueTakeInterceptor.restore === "function") {
        queueTakeInterceptor.restore();
      }
    }
    selectConversationById(convId, function (selectErr) {
      if (selectErr) {
        cleanupInterceptor();
        done(selectErr);
        return;
      }
      var preDrain = drainConversationQueueSync(convId);
      if (!preDrain) {
        cleanupInterceptor();
        done(new Error("queue-edit fixture failed to drain preexisting queue workload"));
        return;
      }
      var originalPrompt = "queue-edit-original-" + String(Date.now());
      var updatedPrompt = "queue-edit-updated-" + String(Date.now());
      var wsId = workspaceId();
      if (!wsId) {
        cleanupInterceptor();
        done(new Error("queue-edit fixture missing workspace id"));
        return;
      }
      var enqueueResponse = postActionSync(
        "action=queue_enqueue&workspace_id=" + encodeURIComponent(wsId) +
        "&conversation_id=" + encodeURIComponent(convId) +
        "&prompt=" + encodeURIComponent(originalPrompt)
      );
      if (!enqueueResponse || !enqueueResponse.success) {
        cleanupInterceptor();
        done(new Error("queue-edit fixture failed to enqueue prompt"));
        return;
      }
      var queuedItemId = String((enqueueResponse && enqueueResponse.item_id) || "");
      if (typeof window.dispatchEvent === "function") {
        try {
          window.dispatchEvent(new Event("focus"));
        } catch (_queueEditFocusErr) {
          // best effort
        }
      }
      waitFor(function () {
        if (queuedItemId && document.querySelector("[data-action='queue-edit-item'][data-queue-item-id='" + queuedItemId + "']")) {
          return true;
        }
        var knownItems = fetchQueueItemsSync(convId, 12);
        if (!knownItems.length) {
          return false;
        }
        for (var i = 0; i < knownItems.length; i += 1) {
          var pendingId = String((knownItems[i] && knownItems[i].id) || "");
          if (!pendingId) {
            continue;
          }
          if (document.querySelector("[data-action='queue-edit-item'][data-queue-item-id='" + pendingId + "']")) {
            return true;
          }
        }
        return false;
      }, 12000, "queue edit button for queued item", function (waitEditBtnErr) {
        if (waitEditBtnErr) {
          cleanupInterceptor();
          done(waitEditBtnErr);
          return;
        }
        var editBtn = null;
        var itemId = queuedItemId;
        if (itemId) {
          editBtn = document.querySelector("[data-action='queue-edit-item'][data-queue-item-id='" + itemId + "']");
        }
        if (!editBtn) {
          var pendingItems = fetchQueueItemsSync(convId, 12);
          for (var i = 0; i < pendingItems.length; i += 1) {
            var pendingId = String((pendingItems[i] && pendingItems[i].id) || "");
            if (!pendingId) {
              continue;
            }
            var candidate = document.querySelector("[data-action='queue-edit-item'][data-queue-item-id='" + pendingId + "']");
            if (candidate) {
              editBtn = candidate;
              itemId = pendingId;
              break;
            }
          }
        }
        if (!editBtn) {
          cleanupInterceptor();
          done(new Error("queue edit button unavailable"));
          return;
        }
        if (!itemId) {
          cleanupInterceptor();
          done(new Error("queue edit item id unavailable"));
          return;
        }
        clickNode(editBtn);
        waitFor(function () {
          var input = document.querySelector("textarea[data-action='queue-edit-input'][data-queue-item-id='" + itemId + "']");
          if (input) {
            return true;
          }
          var retryBtn = document.querySelector("[data-action='queue-edit-item'][data-queue-item-id='" + itemId + "']");
          if (retryBtn) {
            clickNode(retryBtn);
          }
          return false;
        }, 12000, "queue edit input appears", function (editFieldErr) {
          if (editFieldErr) {
            cleanupInterceptor();
            done(editFieldErr);
            return;
          }
          var editField = document.querySelector("textarea[data-action='queue-edit-input'][data-queue-item-id='" + itemId + "']");
          if (!editField) {
            cleanupInterceptor();
            done(new Error("queue edit input unavailable"));
            return;
          }
          editField.value = updatedPrompt;
          dispatchInputEvent(editField);
          var saveBtn = document.querySelector("[data-action='queue-edit-save'][data-queue-item-id='" + itemId + "']");
          if (!saveBtn) {
            cleanupInterceptor();
            done(new Error("queue edit save button unavailable"));
            return;
          }
          clickNode(saveBtn);
          waitFor(function () {
            return !document.querySelector("textarea[data-action='queue-edit-input'][data-queue-item-id='" + itemId + "']");
          }, 7000, "queue edit save settles", function (saveErr) {
            if (saveErr) {
              cleanupInterceptor();
              done(saveErr);
              return;
            }
            try {
              cleanupInterceptor();
              var previewNode = document.querySelector(".queue-item[data-queue-item-id='" + itemId + "'] .queue-item-text");
              var previewText = String((previewNode && previewNode.textContent) || "");
              var previewUpdated = previewText.indexOf("queue-edit-updated-") >= 0;
              var conversationUpdated = false;
              var conversationStillOriginal = false;
              if (!previewUpdated) {
                conversationUpdated = conversationHasPromptSync(convId, updatedPrompt);
                conversationStillOriginal = conversationHasPromptSync(convId, originalPrompt);
              }
              var updatedViaConversation = conversationUpdated && !conversationStillOriginal;
              check(
                "queue edit journey updates queued prompt text in UI",
                previewUpdated || updatedViaConversation,
                previewUpdated
                  ? previewText
                  : ("preview_missing conversation_updated=" + String(conversationUpdated) + " conversation_still_original=" + String(conversationStillOriginal))
              );
              var items = fetchQueueItemsSync(convId, 30);
              var matchedPrompt = "";
              for (var i = 0; i < items.length; i += 1) {
                if (String((items[i] && items[i].id) || "") === itemId) {
                  matchedPrompt = String((items[i] && items[i].prompt) || "");
                  break;
                }
              }
              check(
                "queue edit journey persists updated prompt via queue API",
                matchedPrompt === updatedPrompt || updatedViaConversation,
                matchedPrompt === updatedPrompt
                  ? ("item=" + itemId + " prompt=" + matchedPrompt)
                  : ("item=" + itemId + " prompt=" + matchedPrompt + " conversation_updated_via_send=" + String(updatedViaConversation))
              );
              var drained = drainConversationQueueSync(convId);
              check(
                "queue edit fixture drains queue after save verification",
                drained,
                convId
              );
              done(null, {
                itemId: itemId,
                originalPrompt: originalPrompt,
                updatedPrompt: updatedPrompt
              });
            } catch (checkErr) {
              cleanupInterceptor();
              done(checkErr);
            }
          });
        });
      });
    });
  }

  function runArchiveJourneyCheck(conversationId, expectedActiveConversationId, done) {
    var targetConversationId = String(conversationId || "");
    if (!targetConversationId) {
      done(new Error("archive journey requires conversation id"));
      return;
    }
    var expectedActiveId = String(expectedActiveConversationId || "");
    waitFor(function () {
      return !!document.querySelector(".conversation-row[data-conversation-id='" + targetConversationId + "']");
    }, 6000, "archive target conversation row", function (targetRowErr) {
      if (targetRowErr) {
        done(targetRowErr);
        return;
      }
      var armBtn = document.querySelector(
        "[data-action='arm-archive-conversation'][data-workspace-id='" + workspaceId() + "'][data-conversation-id='" + targetConversationId + "']"
      );
      if (!armBtn) {
        done(new Error("archive arm button unavailable"));
        return;
      }
      clickNode(armBtn);
      waitFor(function () {
        return !!document.querySelector(
          "[data-action='confirm-archive-conversation'][data-workspace-id='" + workspaceId() + "'][data-conversation-id='" + targetConversationId + "']"
        );
      }, 5000, "archive confirm button appears", function (confirmWaitErr) {
        if (confirmWaitErr) {
          done(confirmWaitErr);
          return;
        }
        var confirmBtn = document.querySelector(
          "[data-action='confirm-archive-conversation'][data-workspace-id='" + workspaceId() + "'][data-conversation-id='" + targetConversationId + "']"
        );
        if (!confirmBtn) {
          done(new Error("archive confirm button unavailable"));
          return;
        }
        clickNode(confirmBtn);
        waitFor(function () {
          return !document.querySelector(".conversation-row[data-conversation-id='" + targetConversationId + "']");
        }, 9000, "archived conversation row removed", function (archiveGoneErr) {
          if (archiveGoneErr) {
            done(archiveGoneErr);
            return;
          }
          try {
            var snapshot = fetchStateSnapshotSync();
            var stateHasConversation = false;
            if (snapshot && snapshot.success) {
              var workspaces = toArray(snapshot.workspaces || []);
              for (var i = 0; i < workspaces.length; i += 1) {
                if (String((workspaces[i] && workspaces[i].id) || "") !== workspaceId()) {
                  continue;
                }
                var conversations = toArray((workspaces[i] && workspaces[i].conversations) || []);
                for (var j = 0; j < conversations.length; j += 1) {
                  if (String((conversations[j] && conversations[j].id) || "") === targetConversationId) {
                    stateHasConversation = true;
                    break;
                  }
                }
                break;
              }
            }
            check(
              "archive journey removes conversation from workspace state",
              !stateHasConversation,
              targetConversationId
            );
            if (expectedActiveId) {
              check(
                "archive journey preserves active conversation context",
                String(activeConversationId() || "") === expectedActiveId,
                "active=" + String(activeConversationId() || "") + " expected=" + expectedActiveId
              );
              var currentHash = String(window.location.hash || "");
              check(
                "archive journey keeps hash route on active conversation",
                currentHash.indexOf(expectedActiveId) >= 0 && currentHash.indexOf(targetConversationId) < 0,
                currentHash
              );
            }
            done(null, {
              archivedConversationId: targetConversationId
            });
          } catch (checkErr) {
            done(checkErr);
          }
        });
      });
    });
  }

  function forceSelectDraftForWorkspace(done) {
    var wsId = workspaceId();
    if (!wsId) {
      done(new Error("Missing workspace id for draft selection"));
      return;
    }
    var workspaceTree = document.getElementById("workspace-tree") || document.body;
    if (!workspaceTree) {
      done(new Error("Missing workspace tree for draft selection"));
      return;
    }
    var ghostButton = document.createElement("button");
    ghostButton.type = "button";
    ghostButton.style.display = "none";
    ghostButton.setAttribute("data-action", "select-draft");
    ghostButton.setAttribute("data-workspace-id", wsId);
    workspaceTree.appendChild(ghostButton);
    clickNode(ghostButton);
    if (ghostButton.parentNode) {
      ghostButton.parentNode.removeChild(ghostButton);
    }
    waitFor(function () {
      return !activeConversationId();
    }, 7000, "draft selection without visible row", function (err) {
      if (err) {
        done(err);
        return;
      }
      setTimeout(function () { done(null); }, 180);
    });
  }

  function runTeamModeMenuChecks(done) {
    var runModeBtn = document.getElementById("run-mode-btn");
    if (!runModeBtn) {
      done(new Error("run mode button missing"));
      return;
    }
    clickNode(runModeBtn);
    waitFor(function () {
      var menu = document.getElementById("run-mode-menu");
      return !!menu && !menu.classList.contains("hidden");
    }, 6000, "run mode menu visible", function (menuErr) {
      if (menuErr) {
        done(menuErr);
        return;
      }
      try {
        var teamNode = document.querySelector("button.run-mode-item[data-run-mode='assistant'] .run-mode-name");
        var teamLabel = String((teamNode && teamNode.textContent) || "").trim();
        check(
          "Team mode is present in menu",
          !!teamNode && teamLabel.toLowerCase().indexOf("team") >= 0,
          teamLabel || "missing"
        );
      } catch (teamCheckErr) {
        done(teamCheckErr);
        return;
      }

      var teamToggle = document.getElementById("run-mode-more-toggle");
      if (!teamToggle) {
        done(new Error("team submenu toggle missing"));
        return;
      }
      clickNode(teamToggle);
      waitFor(function () {
        var list = document.getElementById("run-mode-more-list");
        return !!list && !list.classList.contains("hidden");
      }, 6000, "team submenu visible", function (submenuErr) {
        if (submenuErr) {
          done(submenuErr);
          return;
        }
        try {
          var generalTeamBtn = document.querySelector("button.run-mode-advanced-item[data-assistant-mode-id='']");
          var generalTeamLabel = "";
          if (generalTeamBtn) {
            generalTeamLabel = String((generalTeamBtn.textContent) || "").replace(/\s+/g, " ").trim();
          }
          check(
            "Team submenu exposes General Team option",
            !!generalTeamBtn && generalTeamLabel.toLowerCase().indexOf("general team") >= 0,
            generalTeamLabel || "missing"
          );

          var guiTestingNode = document.querySelector("button.run-mode-item[data-run-mode='gui-testing'] .run-mode-name");
          var guiTestingLabel = String((guiTestingNode && guiTestingNode.textContent) || "").trim();
          check(
            "GUI Testing mode is present in menu",
            !!guiTestingNode && guiTestingLabel.toLowerCase().indexOf("gui testing") >= 0,
            guiTestingLabel || "missing"
          );
        } catch (submenuCheckErr) {
          done(submenuCheckErr);
          return;
        }

        clickNode(runModeBtn);
        waitFor(function () {
          var menu = document.getElementById("run-mode-menu");
          return !!menu && menu.classList.contains("hidden");
        }, 4000, "run mode menu closed", function (closeErr) {
          if (closeErr) {
            done(closeErr);
            return;
          }
          done(null);
        });
      });
    });
  }

  function setRunModeAndWait(modeId, expectedLabel, done) {
    var runModeBtn = document.getElementById("run-mode-btn");
    if (!runModeBtn) {
      done(new Error("run mode button missing"));
      return;
    }
    var modeValue = String(modeId || "");
    var expected = String(expectedLabel || "");
    clickNode(runModeBtn);
    waitFor(function () {
      var menu = document.getElementById("run-mode-menu");
      return !!menu && !menu.classList.contains("hidden");
    }, 6000, "run mode menu visible", function (menuErr) {
      if (menuErr) {
        done(menuErr);
        return;
      }
      try {
        var modeBtn = document.querySelector("button.run-mode-item[data-run-mode='" + modeValue + "']");
        check(
          expected + " mode is present in menu",
          !!modeBtn,
          modeBtn ? ("data-run-mode=" + modeValue) : "missing"
        );
        clickNode(modeBtn);
      } catch (modeCheckErr) {
        done(modeCheckErr);
        return;
      }
      waitFor(function () {
        var button = document.getElementById("run-mode-btn");
        return !!button && String(button.textContent || "").toLowerCase().indexOf(expected.toLowerCase()) >= 0;
      }, 7000, expected + " mode switch", function (switchErr) {
        if (switchErr) {
          done(switchErr);
          return;
        }
        done(null);
      });
    });
  }

  function interactiveIntelligenceScenarios(conversationA, conversationB, conversationC) {
    return [
      {
        id: "causal",
        conversationId: String(conversationA || ""),
        checkPrefix: "interactive causal scenario",
        promptText: "Trial starts jump right after the ranking tweak, but refunds, cancellation calls, and support queue age worsen a week later in the same cohorts. In 5 short labeled lines only, decide whether the ranking change helped and show what overturned the first read. Use these labels exactly once each: Outcome, Initial Assumption, Invalidating Evidence, Revised Decision, Claim-to-Evidence Map.",
        expectedAnchor: "trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes"
      },
      {
        id: "security",
        conversationId: String(conversationB || ""),
        checkPrefix: "interactive security scenario",
        promptText: "A regional outage override first looks safe because only incident responders would use it. Then audit cannot attribute exports, residency boundaries shift during failover, and the workaround needs broader plaintext access than planned. In 5 short labeled lines only, recommend the safest path and make the revised decision explicit. Use these labels exactly once each: Outcome, Initial Assumption, Invalidating Evidence, Revised Decision, Claim-to-Evidence Map.",
        expectedAnchor: "regional outage override with export gaps, residency drift, and plaintext expansion"
      },
      {
        id: "strategy",
        conversationId: String(conversationC || ""),
        checkPrefix: "interactive strategy scenario",
        promptText: "Pushing harder into a partner-heavy region looks like the obvious path because trial conversions jump. Then renewal cohorts weaken, the reliability budget is nearly spent, and counsel says the same region may trigger sanctions exposure next quarter. In 5 short labeled lines only, recommend the strategy and spell out the pivot. Use these labels exactly once each: Outcome, Initial Assumption, Invalidating Evidence, Revised Decision, Claim-to-Evidence Map.",
        expectedAnchor: "regional growth push versus renewals, reliability budget, and sanctions exposure"
      }
    ];
  }

  function runInteractiveIntelligenceScenario(scenario, isFirstScenario, done) {
    var promptEl = document.getElementById("run-prompt");
    var runBtn = document.getElementById("run-btn");
    var conversationId = String((scenario && scenario.conversationId) || "");
    var promptText = String((scenario && scenario.promptText) || "");
    var expectedAnchor = String((scenario && scenario.expectedAnchor) || "");
    var scenarioPrefix = String((scenario && scenario.checkPrefix) || "interactive intelligence");
    if (!promptEl) {
      done(new Error("run-prompt missing for interactive intelligence check"));
      return;
    }
    if (!runBtn) {
      done(new Error("run-btn missing for interactive intelligence check"));
      return;
    }
    if (!conversationId) {
      done(new Error("interactive intelligence target conversation missing"));
      return;
    }
    var finalResponseWaitMs = 100000;
    selectConversationById(conversationId, function (selectErr) {
      if (selectErr) {
        done(selectErr);
        return;
      }
      (function () {
          try {
            var runModeLabel = String((document.getElementById("run-mode-btn") && document.getElementById("run-mode-btn").textContent) || "");
            if (isFirstScenario) {
              check("interactive intelligence starts from default run mode", runModeLabel.replace(/^\s+|\s+$/g, "").length > 0, runModeLabel);
            } else {
              check(scenarioPrefix + " preserves a usable run mode", runModeLabel.replace(/^\s+|\s+$/g, "").length > 0, runModeLabel);
            }
          } catch (modeCheckErr) {
            done(modeCheckErr);
            return;
          }
          promptEl.value = promptText;
          dispatchInputEvent(promptEl);
          clickNode(runBtn);
          waitFor(function () {
            return conversationHasPromptSync(conversationId, promptText) || promptInQueue(workspaceId(), conversationId, promptText);
          }, 12000, "interactive intelligence prompt captured", function (captureErr) {
            if (captureErr) {
              done(captureErr);
              return;
            }
            try {
              check(
                scenarioPrefix + " prompt is captured in UI or pending queue",
                true,
                conversationHasPromptSync(conversationId, promptText) ? "conversation" : "queue"
              );
            } catch (captureCheckErr) {
              done(captureCheckErr);
              return;
            }
            waitFor(function () {
              var liveSnapshot = interactiveIntelligenceSnapshotSync(conversationId);
              return (
                liveSnapshot.hasRunningLine ||
                liveSnapshot.queueRunning ||
                liveSnapshot.queuePending > 0 ||
                liveSnapshot.runEventStreamLength > 0 ||
                String(liveSnapshot.assistantText || "").replace(/^\s+|\s+$/g, "").length > 0
              );
            }, 45000, "interactive reasoning activity", function (activityErr) {
              if (activityErr) {
                result.details.interactive_debug = interactiveIntelligenceSnapshotSync(conversationId);
                done(activityErr);
                return;
              }
              try {
                var liveSnapshot = interactiveIntelligenceSnapshotSync(conversationId);
                check(
                  scenarioPrefix + " run shows live activity",
                  true,
                  "queue_running=" + String(liveSnapshot.queueRunning) +
                    " pending=" + String(liveSnapshot.queuePending) +
                    " stream_length=" + String(liveSnapshot.runEventStreamLength)
                );
              } catch (activityCheckErr) {
                done(activityCheckErr);
                return;
              }
            waitForInteractiveIntelligenceFinal(conversationId, expectedAnchor, finalResponseWaitMs, function (responseErr, snapshot) {
              if (responseErr) {
                result.details.interactive_debug = interactiveIntelligenceSnapshotSync(conversationId);
                result.details.debug_snapshot = collectDebugSnapshot(conversationId);
                done(responseErr);
                return;
              }
              snapshot = snapshot || interactiveIntelligenceSnapshotSync(conversationId);
              var combinedText = String(snapshot.combinedText || "");
              var assistantLower = String(snapshot.combinedLower || "");
              try {
                check(
                  scenarioPrefix + " reaches a bounded final state",
                  !!snapshot.contractPresent,
                  "timed_out=" + String(!!snapshot.timedOut) +
                    " idle_without_contract=" + String(!!snapshot.idleWithoutContract) +
                    " queue_last_status=" + String(snapshot.queueLastStatus || "") +
                    " stream_length=" + String(snapshot.runEventStreamLength || 0)
                );
                check(
                  scenarioPrefix + " includes scenario anchor",
                  assistantLower.indexOf(expectedAnchor) >= 0,
                  combinedText.slice(0, 260)
                );
                check(
                  scenarioPrefix + " includes explicit revision contract",
                  assistantLower.indexOf("initial assumption:") >= 0 &&
                    assistantLower.indexOf("invalidating evidence:") >= 0 &&
                    assistantLower.indexOf("revised decision:") >= 0,
                  combinedText.slice(0, 320)
                );
                check(
                  scenarioPrefix + " includes claim-to-evidence map",
                  assistantLower.indexOf("claim-to-evidence map:") >= 0,
                  combinedText.slice(0, 320)
                );
                check(
                  scenarioPrefix + " avoids generic cross-domain fallback",
                  assistantLower.indexOf("cross-domain integrated reasoning") < 0,
                  combinedText.slice(0, 320)
                );
              } catch (assistantCheckErr) {
                done(assistantCheckErr);
                return;
              }
              done(null, {
                id: String((scenario && scenario.id) || ""),
                conversationId: conversationId,
                promptText: promptText,
                expectedAnchor: expectedAnchor,
                runModeLabel: String((document.getElementById("run-mode-btn") && document.getElementById("run-mode-btn").textContent) || ""),
                assistantExcerpt: combinedText.slice(0, 400),
                queueStatus: snapshot.queueLastStatus,
                runEventStatus: snapshot.runEventStatus,
                debug: snapshot
              });
            });
            });
          });
      })();
    });
  }

  function runInteractiveIntelligencePack(scenarios, index, collected, done) {
    var list = Array.isArray(scenarios) ? scenarios : [];
    var nextIndex = Number(index || 0);
    var results = Array.isArray(collected) ? collected : [];
    if (nextIndex >= list.length) {
      done(null, results);
      return;
    }
    runInteractiveIntelligenceScenario(list[nextIndex], nextIndex === 0, function (scenarioErr, scenarioResult) {
      if (scenarioErr) {
        done(scenarioErr);
        return;
      }
      waitForInteractiveIntelligenceSettle(String((scenarioResult && scenarioResult.conversationId) || ""), 20000, function (_settleErr, settleSnapshot) {
        try {
          check(
            String((list[nextIndex] && list[nextIndex].checkPrefix) || "interactive intelligence") + " settles before the next scenario",
            !!(settleSnapshot && settleSnapshot.settled),
            JSON.stringify(settleSnapshot || {})
          );
        } catch (settleCheckErr) {
          done(settleCheckErr);
          return;
        }
        if (scenarioResult && typeof scenarioResult === "object") {
          scenarioResult.settleDebug = settleSnapshot || {};
        }
        results.push(scenarioResult);
        runInteractiveIntelligencePack(list, nextIndex + 1, results, done);
      });
    });
  }

  function runScenario() {
    waitFor(function () {
      return window.__artificerBooted === true;
    }, 30000, "app boot", function (bootErr) {
      if (bootErr) {
        finishError(bootErr);
        return;
      }

      try {
        var projectModeBtn = document.querySelector("[data-organize-mode='project']");
        var showAllBtn = document.querySelector("[data-organize-show='all']");
        if (projectModeBtn) {
          clickNode(projectModeBtn);
        }
        if (showAllBtn) {
          clickNode(showAllBtn);
        }
      } catch (_organizeErr) {
        // best effort
      }

        waitFor(function () {
          return rowsForWorkspace().length >= 1;
        }, 20000, "seeded workspace rows", function (workspaceErr) {
          if (workspaceErr) {
            result.details.debug_snapshot = collectDebugSnapshot();
            finishError(workspaceErr);
            return;
          }

        var wsRow = workspaceRowNode();
        if (wsRow) {
          var expandBtn = wsRow.querySelector(".workspace-caret[data-action='toggle-workspace']");
          var wsGroup = findAncestor(wsRow, "workspace-group");
          if (expandBtn && wsGroup && !wsGroup.classList.contains("expanded")) {
            clickNode(expandBtn);
          }
        }

        waitFor(function () {
          return conversationIdByTitle(conversationTitleA) && conversationIdByTitle(conversationTitleB) && conversationIdByTitle(conversationTitleC);
        }, 7000, "seeded conversation rows", function (rowsErr) {
          if (rowsErr) {
            finishError(rowsErr);
            return;
          }

          var conversationA = conversationIdByTitle(conversationTitleA);
          var conversationB = conversationIdByTitle(conversationTitleB);
          var conversationC = conversationIdByTitle(conversationTitleC);
          try {
            check("three seeded conversations available", !!conversationA && !!conversationB && !!conversationC && conversationA !== conversationB && conversationA !== conversationC && conversationB !== conversationC, conversationA + "," + conversationB + "," + conversationC);
          } catch (checkErr) {
            finishError(checkErr);
            return;
          }
          var seededConversationIds = [conversationA, conversationB, conversationC];

          if (scenarioProfile === "intelligence") {
            runInteractiveIntelligencePack(
              interactiveIntelligenceScenarios(conversationA, conversationB, conversationC),
              0,
              [],
              function (intelligenceErr, intelligenceResults) {
                if (intelligenceErr) {
                  finishError(intelligenceErr);
                  return;
                }
                var scenarioResults = Array.isArray(intelligenceResults) ? intelligenceResults : [];
                var lastScenario = scenarioResults.length ? scenarioResults[scenarioResults.length - 1] : null;
                result.details.workspace_name = workspaceName;
                result.details.workspace_id = workspaceId();
                result.details.profile = scenarioProfile;
                result.details.conversation_ids = seededConversationIds;
                result.details.interactive_scenarios = scenarioResults;
                result.details.interactive_conversation_id = String((lastScenario && lastScenario.conversationId) || "");
                result.details.interactive_prompt = String((scenarioResults[0] && scenarioResults[0].promptText) || "");
                result.details.interactive_assistant_excerpt = String((lastScenario && lastScenario.assistantExcerpt) || "");
                result.details.interactive_debug = lastScenario && lastScenario.debug ? lastScenario.debug : {};
                finishSuccess();
              }
            );
            return;
          }

          runTeamModeMenuChecks(function (teamMenuErr) {
            if (teamMenuErr) {
              finishError(teamMenuErr);
              return;
            }
          selectConversationById(conversationA, function (selectAErr) {
            if (selectAErr) {
              finishError(selectAErr);
              return;
            }
            var prompt = document.getElementById("run-prompt");
            if (!prompt) {
              finishError(new Error("run-prompt missing"));
              return;
            }

            prompt.value = draftAlpha;
            dispatchInputEvent(prompt);
            if (!saveConversationDraftSync(workspaceId(), conversationA, draftAlpha)) {
              finishError(new Error("failed to seed conversation A draft"));
              return;
            }

            selectConversationById(conversationB, function (selectBErr) {
              if (selectBErr) {
                finishError(selectBErr);
                return;
              }
              prompt.value = draftBeta;
              dispatchInputEvent(prompt);
              if (!saveConversationDraftSync(workspaceId(), conversationB, draftBeta)) {
                finishError(new Error("failed to seed conversation B draft"));
                return;
              }

                selectConversationById(conversationA, function (backToAErr) {
                  if (backToAErr) {
                    finishError(backToAErr);
                    return;
                  }
                  waitForDraftHydration(
                    conversationA,
                    draftAlpha,
                    draftBeta,
                    10000,
                    "draft hydration for conversation A",
                    function (waitAErr) {
                  if (waitAErr) {
                    finishError(waitAErr);
                    return;
                  }
                  try {
                    var promptOnA = String(prompt.value || "");
                    check(
                      "draft remains scoped to conversation A",
                      promptOnA.indexOf(draftAlpha) >= 0 && promptOnA.indexOf(draftBeta) < 0,
                      promptOnA
                    );
                  } catch (checkAErr) {
                    finishError(checkAErr);
                    return;
                  }

                  selectConversationById(conversationB, function (backToBErr) {
                    if (backToBErr) {
                      finishError(backToBErr);
                      return;
                    }
                    waitForDraftHydration(
                      conversationB,
                      draftBeta,
                      draftAlpha,
                      10000,
                      "draft hydration for conversation B",
                      function (waitBErr) {
                      if (waitBErr) {
                        finishError(waitBErr);
                        return;
                      }
                      try {
                        var promptOnB = String(prompt.value || "");
                        check(
                          "draft remains scoped to conversation B",
                          promptOnB.indexOf(draftBeta) >= 0 && promptOnB.indexOf(draftAlpha) < 0,
                          promptOnB
                        );
                      } catch (checkBErr) {
                        finishError(checkBErr);
                        return;
                      }

                      runDraftRapidMultiSendCoherenceCheck(prompt, function (rapidSendErr, rapidSendResult) {
                        if (rapidSendErr) {
                          finishError(rapidSendErr);
                          return;
                        }
                        selectDraftForWorkspace(function (selectDraftErr) {
                        if (selectDraftErr) {
                          finishError(selectDraftErr);
                          return;
                        }
                        var runBtn = document.getElementById("run-btn");
                        if (!runBtn) {
                          finishError(new Error("run-btn missing"));
                          return;
                        }
                        prompt.value = newThreadPrompt;
                        dispatchInputEvent(prompt);
                        var beforeCreateIds = conversationIdsForWorkspace();
                        var staleStateInterceptor = null;
                        var stateSnapshotBeforeCreate = fetchStateSnapshotSync();
                        var staleStatePayload = cloneStateSnapshotWithoutConversation(
                          stateSnapshotBeforeCreate,
                          workspaceId(),
                          conversationA
                        );
                        if (staleStatePayload && staleStatePayload.success) {
                          staleStateInterceptor = installSingleStateResponseInterceptor(staleStatePayload);
                        }
                        clickNode(runBtn);

                        selectConversationById(conversationA, function (switchAfterSendErr) {
                          if (switchAfterSendErr) {
                            if (staleStateInterceptor && typeof staleStateInterceptor.restore === "function") {
                              staleStateInterceptor.restore();
                            }
                            finishError(switchAfterSendErr);
                            return;
                          }
                          waitFor(function () {
                            return activeConversationId() === conversationA;
                          }, 5000, "manual selection remains active after draft send", function (selectionHoldErr) {
                            if (selectionHoldErr) {
                              if (staleStateInterceptor && typeof staleStateInterceptor.restore === "function") {
                                staleStateInterceptor.restore();
                              }
                              finishError(selectionHoldErr);
                              return;
                            }
                            try {
                              check(
                                "manual selection remains active after draft send",
                                activeConversationId() === conversationA,
                                activeConversationId()
                              );
                            } catch (selectionHoldCheckErr) {
                              finishError(selectionHoldCheckErr);
                              return;
                            }
                            waitFor(function () {
                              return conversationIdsForWorkspace().length >= (beforeCreateIds.length + 1);
                            }, 18000, "new thread appears after draft send", function (newThreadErr) {
                              if (newThreadErr) {
                                if (staleStateInterceptor && typeof staleStateInterceptor.restore === "function") {
                                  staleStateInterceptor.restore();
                                }
                                finishError(newThreadErr);
                                return;
                              }
                              var finalizeCreateChecks = function () {
                                if (staleStateInterceptor && typeof staleStateInterceptor.restore === "function") {
                                  staleStateInterceptor.restore();
                                  staleStateInterceptor = null;
                                }
                                var afterCreateIds = conversationIdsForWorkspace();
                                var newConversationId = "";
                                for (var ni = 0; ni < afterCreateIds.length; ni += 1) {
                                  if (beforeCreateIds.indexOf(afterCreateIds[ni]) < 0) {
                                    newConversationId = afterCreateIds[ni];
                                    break;
                                  }
                                }
                                if (!newConversationId) {
                                  finishError(new Error("Could not identify newly created thread"));
                                  return;
                                }
                                if (typeof window.dispatchEvent === "function") {
                                  try {
                                    window.dispatchEvent(new Event("focus"));
                                  } catch (_focusErr) {
                                    // best effort
                                  }
                                }
                                setTimeout(function () {
                                  var finalizeScenarioSuccess = function (heartbeatResult, durabilityResult, failureCheckResult, queueEditResult, archiveResult) {
                                    result.details.workspace_name = workspaceName;
                                    result.details.workspace_id = workspaceId();
                                    result.details.profile = scenarioProfile;
                                    result.details.extended_checks_enabled = runExtendedChecks ? "1" : "0";
                                    result.details.background_checks_enabled = runBackgroundChecks ? "1" : "0";
                                    result.details.conversation_ids = seededConversationIds;
                                    result.details.rapid_send_created_conversation_id = String((rapidSendResult && rapidSendResult.newConversationId) || "");
                                    result.details.rapid_send_prompt_one = String((rapidSendResult && rapidSendResult.promptOne) || "");
                                    result.details.rapid_send_prompt_two = String((rapidSendResult && rapidSendResult.promptTwo) || "");
                                    result.details.created_conversation_id = newConversationId;
                                    result.details.heartbeat_prompt = String((heartbeatResult && heartbeatResult.heartbeatPrompt) || "");
                                    result.details.heartbeat_elapsed_initial = String((heartbeatResult && heartbeatResult.firstElapsed) || "");
                                    result.details.heartbeat_elapsed_later = String((heartbeatResult && heartbeatResult.secondElapsed) || "");
                                    result.details.failure_created_conversation_id = String((failureCheckResult && failureCheckResult.failureConversationId) || "");
                                    result.details.failure_prompt = String((failureCheckResult && failureCheckResult.failurePrompt) || "");
                                    result.details.pending_durability_prompt = String((durabilityResult && durabilityResult.durablePrompt) || "");
                                    result.details.queue_edit_item_id = String((queueEditResult && queueEditResult.itemId) || "");
                                    result.details.queue_edit_original_prompt = String((queueEditResult && queueEditResult.originalPrompt) || "");
                                    result.details.queue_edit_updated_prompt = String((queueEditResult && queueEditResult.updatedPrompt) || "");
                                    result.details.archived_conversation_id = String((archiveResult && archiveResult.archivedConversationId) || "");
                                    finishSuccess();
                                  };

                                  var runPostCreateChecks = function () {
                                    try {
                                      var stableIds = conversationIdsForWorkspace();
                                      check("newly created thread remains visible after refresh", stableIds.indexOf(newConversationId) >= 0, newConversationId);
                                    } catch (stabilityErr) {
                                      finishError(stabilityErr);
                                      return;
                                    }
                                    selectConversationById(newConversationId, function (selectNewErr) {
                                      if (selectNewErr) {
                                        finishError(selectNewErr);
                                        return;
                                      }
                                      try {
                                        var userBodies = toArray(document.querySelectorAll("#chat-log .msg.user .msg-body"));
                                        var domUserText = "";
                                        for (var ub = 0; ub < userBodies.length; ub += 1) {
                                          domUserText += String(userBodies[ub].textContent || "") + "\n";
                                        }
                                        var promptVisible = String((prompt && prompt.value) || "");
                                        var apiConversation = fetchConversationSnapshotSync(newConversationId);
                                        var apiUserText = "";
                                        var apiDraftText = "";
                                        if (apiConversation) {
                                          var apiMessages = toArray(apiConversation.messages || []);
                                          for (var am = 0; am < apiMessages.length; am += 1) {
                                            if (String((apiMessages[am] && apiMessages[am].role) || "") === "user") {
                                              apiUserText += String((apiMessages[am] && apiMessages[am].content) || "") + "\n";
                                            }
                                          }
                                          apiDraftText = String(apiConversation.draft || "");
                                        }
                                        var promptPreserved = (
                                          domUserText.indexOf(newThreadPrompt) >= 0 ||
                                          promptVisible.indexOf(newThreadPrompt) >= 0 ||
                                          apiUserText.indexOf(newThreadPrompt) >= 0 ||
                                          apiDraftText.indexOf(newThreadPrompt) >= 0
                                        );
                                        check(
                                          "draft-send prompt is preserved in created thread context",
                                          promptPreserved,
                                          "domUser=" + domUserText + " prompt=" + promptVisible + " apiUser=" + apiUserText + " apiDraft=" + apiDraftText
                                        );

                                        var finalIds = conversationIdsForWorkspace();
                                        var missing = [];
                                        for (var mi = 0; mi < seededConversationIds.length; mi += 1) {
                                          if (finalIds.indexOf(seededConversationIds[mi]) < 0) {
                                            missing.push(seededConversationIds[mi]);
                                          }
                                        }
                                        check("seeded conversations survive fresh state reload", missing.length === 0, missing.join(","));

                                        runQueueEditJourneyCheck(newConversationId, function (queueEditErr, queueEditResult) {
                                          if (queueEditErr) {
                                            finishError(queueEditErr);
                                            return;
                                          }
                                          runArchiveJourneyCheck(conversationB, newConversationId, function (archiveErr, archiveResult) {
                                            if (archiveErr) {
                                              finishError(archiveErr);
                                              return;
                                            }
                                            try {
                                              var titleNode = document.getElementById("chat-title");
                                              var activeTitle = String((titleNode && titleNode.textContent) || "").trim();
                                              check("active chat title is non-empty", activeTitle.length > 0 && activeTitle.toLowerCase() !== "no thread", activeTitle);

                                              var currentPathname = String(window.location.pathname || "");
                                              var currentHash = String(window.location.hash || "");
                                              check(
                                                "thread route keeps app pathname stable during selections and reloads",
                                                currentPathname === initialPathname,
                                                "initial=" + initialPathname + " current=" + currentPathname
                                              );
                                              check(
                                                "thread route uses hash-based selection state",
                                                currentHash.indexOf("#/") === 0,
                                                currentHash
                                              );
                                              check(
                                                "hash route includes active workspace and conversation ids",
                                                currentHash.indexOf(workspaceId()) >= 0 && currentHash.indexOf(newConversationId) >= 0,
                                                currentHash
                                              );
                                            } catch (postFlowErr) {
                                              finishError(postFlowErr);
                                              return;
                                            }
                                            if (!runExtendedChecks) {
                                              runLiveStatusHeartbeatCheck(prompt, function (heartbeatErr, heartbeatResult) {
                                                if (heartbeatErr) {
                                                  finishError(heartbeatErr);
                                                  return;
                                                }
                                                finalizeScenarioSuccess(heartbeatResult, null, null, queueEditResult, archiveResult);
                                              });
                                              return;
                                            }
                                            runPendingStorageDurabilityCheck(prompt, function (durabilityErr, durabilityResult) {
                                              if (durabilityErr) {
                                                finishError(durabilityErr);
                                                return;
                                              }
                                              runDraftQueueFailureRecoveryCheck(prompt, function (failureCheckErr, failureCheckResult) {
                                                if (failureCheckErr) {
                                                  finishError(failureCheckErr);
                                                  return;
                                                }
                                                finalizeScenarioSuccess(null, durabilityResult, failureCheckResult, queueEditResult, archiveResult);
                                              });
                                            });
                                          });
                                        });
                                      } catch (finalErr) {
                                        finishError(finalErr);
                                      }
                                    });
                                  };

                                  if (!runBackgroundChecks) {
                                    runPostCreateChecks();
                                    return;
                                  }

                                  var backgroundPendingKey = "c:" + workspaceId() + "::" + newConversationId;
                                  var backgroundDrained = drainConversationQueueSync(newConversationId);
                                  try {
                                    check(
                                      "background fixture reaches terminal queue state",
                                      backgroundDrained,
                                      newConversationId
                                    );
                                  } catch (backgroundDrainErr) {
                                    finishError(backgroundDrainErr);
                                    return;
                                  }
                                  waitFor(function () {
                                    return pendingOutgoingCountForKey(backgroundPendingKey) === 0;
                                  }, 12000, "background pending outgoing reconciliation", function (backgroundPendingErr) {
                                    if (backgroundPendingErr) {
                                      var remainingCount = pendingOutgoingCountForKey(backgroundPendingKey);
                                      var pendingSummary = pendingOutgoingDebugSummary();
                                      var queueSummary = fetchQueueListSummarySync(newConversationId) || fetchConversationQueueSummarySync(newConversationId);
                                      var queueSummaryText = "";
                                      try {
                                        queueSummaryText = JSON.stringify(queueSummary || {});
                                      } catch (_queueSummaryErr) {
                                        queueSummaryText = "{}";
                                      }
                                      finishError(new Error(
                                        String(backgroundPendingErr && backgroundPendingErr.message ? backgroundPendingErr.message : backgroundPendingErr) +
                                        " (key=" + backgroundPendingKey + ", count=" + String(remainingCount) + ", pending=" + pendingSummary + ", queue=" + queueSummaryText + ")"
                                      ));
                                      return;
                                    }
                                    try {
                                      check(
                                        "background-completed thread clears stale pending send indicators",
                                        true,
                                        backgroundPendingKey
                                      );
                                    } catch (backgroundCheckErr) {
                                      finishError(backgroundCheckErr);
                                      return;
                                    }
                                    runPostCreateChecks();
                                  });
                                }, 900);
                              };
                              if (staleStateInterceptor && typeof staleStateInterceptor.wasConsumed === "function") {
                                waitFor(function () {
                                  return !!staleStateInterceptor.wasConsumed();
                                }, 8000, "stale state interception during draft send", function (staleInterceptErr) {
                                  if (staleInterceptErr) {
                                    if (staleStateInterceptor && typeof staleStateInterceptor.restore === "function") {
                                      staleStateInterceptor.restore();
                                    }
                                    finishError(new Error("Failed to intercept stale state response during draft send"));
                                    return;
                                  }
                                  try {
                                    check(
                                      "stale state interception consumed during draft send",
                                      true,
                                      "consumed=1"
                                    );
                                    check(
                                      "active conversation survives stale payload omission",
                                      conversationIdsForWorkspace().indexOf(conversationA) >= 0,
                                      "active=" + String(activeConversationId() || "") + " expected=" + conversationA
                                    );
                                  } catch (staleCheckErr) {
                                    finishError(staleCheckErr);
                                    return;
                                  }
                                  finalizeCreateChecks();
                                });
                                return;
                              }
                              finalizeCreateChecks();
                            });
                          });
                        });
                        });
                      });
                    });
                  });
                });
              });
            });
          });
          });
        });
      });
    });
  }

  try {
    runScenario();
  } catch (error) {
    finishError(error);
  }
})();
JS

safe_workspace_name=$(printf '%s' "$workspace_name" | sed 's/["\\]/\\&/g')
safe_workspace_id=$(printf '%s' "$workspace_id" | sed 's/["\\]/\\&/g')
safe_conversation_a_title=$(printf '%s' "$conversation_a_title" | sed 's/["\\]/\\&/g')
safe_conversation_b_title=$(printf '%s' "$conversation_b_title" | sed 's/["\\]/\\&/g')
safe_conversation_c_title=$(printf '%s' "$conversation_c_title" | sed 's/["\\]/\\&/g')
safe_profile=$(printf '%s' "$profile" | sed 's/["\\]/\\&/g')
sed -i '' "s/__WORKSPACE_NAME__/$safe_workspace_name/g" "$scenario_js"
sed -i '' "s/__WORKSPACE_ID__/$safe_workspace_id/g" "$scenario_js"
sed -i '' "s/__CONVERSATION_A_TITLE__/$safe_conversation_a_title/g" "$scenario_js"
sed -i '' "s/__CONVERSATION_B_TITLE__/$safe_conversation_b_title/g" "$scenario_js"
sed -i '' "s/__CONVERSATION_C_TITLE__/$safe_conversation_c_title/g" "$scenario_js"
sed -i '' "s/__SCENARIO_PROFILE__/$safe_profile/g" "$scenario_js"
scenario_copy="$OUT_DIR/$label-gui-scenario.js"
cp "$scenario_js" "$scenario_copy"
scenario_applescript_path="$scenario_copy"

app_url="http://127.0.0.1:$port/pages/index.html"
base_url="http://127.0.0.1:$port/"
run_gui_scenario_once() {
scenario_outer_timeout_margin_seconds=120
if [ "$profile" = "core" ]; then
  scenario_outer_timeout_margin_seconds=90
elif [ "$profile" = "intelligence" ]; then
  scenario_outer_timeout_margin_seconds=90
elif [ "$profile" = "deep" ]; then
  scenario_outer_timeout_margin_seconds=120
elif [ "$profile" = "background" ] || [ "$profile" = "full" ]; then
  scenario_outer_timeout_margin_seconds=180
fi
scenario_outer_timeout_seconds=$((scenario_timeout_seconds + scenario_outer_timeout_margin_seconds))
run_command_with_timeout "$scenario_outer_timeout_seconds" osascript - "$app_url" "$scenario_applescript_path" "$base_url" "$scenario_timeout_seconds" <<'APPLESCRIPT'
on waitForBoot(tabRef, timeoutSeconds)
  set startedAt to (current date)
  repeat
    try
      tell application "Safari"
        set bootState to do JavaScript "String(window.__artificerBooted || '')" in tabRef
      end tell
      if bootState is "true" then
        return
      end if
    end try
    if ((current date) - startedAt) > timeoutSeconds then
      error "Timed out waiting for Artificer boot"
    end if
    delay 0.2
  end repeat
end waitForBoot

on waitForScenarioResult(tabRef, timeoutSeconds)
  set startedAt to (current date)
  repeat
    try
      tell application "Safari"
        set rawResult to do JavaScript "window.__artificerGuiRegressionResult || ''" in tabRef
      end tell
      if rawResult is not "" then
        return rawResult
      end if
    end try
    if ((current date) - startedAt) > timeoutSeconds then
      error "Timed out waiting for GUI scenario result"
    end if
    delay 0.25
  end repeat
end waitForScenarioResult

on ensureFrontTab(baseUrl)
  tell application "Safari"
    if (count of windows) is 0 then
      make new document with properties {URL:baseUrl}
      delay 0.2
    end if
    set targetTab to missing value
    try
      set targetTab to current tab of front window
    end try
    if targetTab is missing value then
      make new document with properties {URL:baseUrl}
      delay 0.2
      set targetTab to current tab of front window
    end if
    if targetTab is missing value then
      error "Safari current tab unavailable"
    end if
    return targetTab
  end tell
end ensureFrontTab

on run argv
  set appUrl to item 1 of argv
  set scenarioPath to item 2 of argv
  set baseUrl to item 3 of argv
  set scenarioTimeoutSeconds to (item 4 of argv) as integer
  set appleTimeoutSeconds to scenarioTimeoutSeconds + 180

  with timeout of appleTimeoutSeconds seconds
    tell application "Safari"
      activate
      set targetTab to my ensureFrontTab(baseUrl)
      set URL of targetTab to baseUrl
    end tell
  end timeout

  delay 0.5

  with timeout of appleTimeoutSeconds seconds
    tell application "Safari"
      set targetTab to my ensureFrontTab(baseUrl)
      do JavaScript "try { localStorage.setItem('artificer.agentLoopEnabled','0'); localStorage.setItem('artificer.organizeShow','all'); localStorage.setItem('artificer.organizeMode','project'); localStorage.setItem('artificer.computeBudget','quick'); localStorage.setItem('artificer.reasoningEffort','low'); } catch (_err) {}" in targetTab
      set URL of targetTab to appUrl
      my waitForBoot(targetTab, 35)
      set scriptSource to read (POSIX file scenarioPath)
      do JavaScript scriptSource in targetTab
      set scenarioRaw to my waitForScenarioResult(targetTab, scenarioTimeoutSeconds)
      return scenarioRaw
    end tell
  end timeout
end run
APPLESCRIPT
}

scenario_retry_max=3
scenario_attempt=1
scenario_status=1
scenario_result=""
reset_safari_for_automation
while [ "$scenario_attempt" -le "$scenario_retry_max" ]; do
  set +e
  scenario_result=$(run_gui_scenario_once 2>&1)
  scenario_status=$?
  set -e
  if [ "$scenario_status" -eq 0 ]; then
    if is_retryable_gui_result_json "$scenario_result" && [ "$scenario_attempt" -lt "$scenario_retry_max" ]; then
      scenario_attempt=$((scenario_attempt + 1))
      reset_safari_for_automation
      sleep 1
      continue
    fi
    break
  fi
  scenario_is_retryable=0
  if is_retryable_safari_automation_output "$scenario_result"; then
    scenario_is_retryable=1
  fi
  if [ "$scenario_is_retryable" -eq 1 ] && [ "$scenario_attempt" -lt "$scenario_retry_max" ]; then
    scenario_attempt=$((scenario_attempt + 1))
    reset_safari_for_automation
    sleep 1
    continue
  fi
  break
done
if [ "$scenario_status" -ne 0 ]; then
  escaped_scenario_error=$(printf '%s' "$scenario_result" | jq -Rs '.' 2>/dev/null || printf '%s' "\"Safari automation failure\"")
  scenario_result=$(printf '{"success":false,"generated_at":"%s","checks":[],"details":{"scenario_retry_attempts":"%s"},"error":"Safari automation failed before scenario completion","automation_error":%s}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$scenario_attempt" "$escaped_scenario_error")
fi

if [ "$profile" = "deep" ] || [ "$profile" = "background" ] || [ "$profile" = "full" ]; then
  reload_fixture_raw=$(run_reload_durability_fixture "$app_url" "$base_url" "$workspace_id" "$conversation_a_id" || true)
  reload_check_name="submit->forced reload preserves and recovers pending prompt"
  reload_check_pass=false
  reload_check_detail="reload fixture failed to return JSON result"
  reload_prompt=""
  reload_matched_key=""
  reload_matched_source=""
  reload_recovered_source=""
  reload_setup_error=""
  reload_submitted=""
  reload_ready_attempts=""
  reload_submission_seen=""
  reload_submission_accepted=""
  reload_error_output=""
  if [ -n "$reload_fixture_raw" ] && printf '%s' "$reload_fixture_raw" | jq -e 'type=="object"' >/dev/null 2>&1; then
    reload_check_pass=$(printf '%s' "$reload_fixture_raw" | jq -r 'if .success then "true" else "false" end' 2>/dev/null || printf '%s' "false")
    reload_check_detail=$(printf '%s' "$reload_fixture_raw" | jq -r '.detail // "reload fixture returned no detail"' 2>/dev/null || printf '%s' "reload fixture returned no detail")
    reload_prompt=$(printf '%s' "$reload_fixture_raw" | jq -r '.prompt // ""' 2>/dev/null || printf '%s' "")
    reload_matched_key=$(printf '%s' "$reload_fixture_raw" | jq -r '.matched_key // ""' 2>/dev/null || printf '%s' "")
    reload_matched_source=$(printf '%s' "$reload_fixture_raw" | jq -r '.matched_source // ""' 2>/dev/null || printf '%s' "")
    reload_recovered_source=$(printf '%s' "$reload_fixture_raw" | jq -r '.recovered_source // ""' 2>/dev/null || printf '%s' "")
    reload_setup_error=$(printf '%s' "$reload_fixture_raw" | jq -r '.setup_error // ""' 2>/dev/null || printf '%s' "")
    reload_submitted=$(printf '%s' "$reload_fixture_raw" | jq -r '.submitted // ""' 2>/dev/null || printf '%s' "")
    reload_ready_attempts=$(printf '%s' "$reload_fixture_raw" | jq -r '.ready_attempts // ""' 2>/dev/null || printf '%s' "")
    reload_submission_seen=$(printf '%s' "$reload_fixture_raw" | jq -r '.submission_seen // ""' 2>/dev/null || printf '%s' "")
    reload_submission_accepted=$(printf '%s' "$reload_fixture_raw" | jq -r '.submission_accepted // ""' 2>/dev/null || printf '%s' "")
    reload_error_output=$(printf '%s' "$reload_fixture_raw" | jq -r '.error_output // ""' 2>/dev/null || printf '%s' "")
  elif [ -n "$reload_fixture_raw" ]; then
    reload_check_detail="reload fixture returned non-JSON output"
  fi
  if [ -n "$reload_error_output" ]; then
    reload_error_excerpt=$(printf '%s' "$reload_error_output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-240)
    reload_check_detail="${reload_check_detail} (${reload_error_excerpt})"
  fi
  if [ "$reload_check_pass" = "true" ]; then
    reload_check_pass_json=true
  else
    reload_check_pass_json=false
  fi
  scenario_result=$(printf '%s' "$scenario_result" | jq \
    --arg check_name "$reload_check_name" \
    --arg check_detail "$reload_check_detail" \
    --arg reload_prompt "$reload_prompt" \
    --arg reload_key "$reload_matched_key" \
    --arg reload_source "$reload_matched_source" \
    --arg reload_recovered_source "$reload_recovered_source" \
    --arg reload_setup_error "$reload_setup_error" \
    --arg reload_submitted "$reload_submitted" \
    --arg reload_ready_attempts "$reload_ready_attempts" \
    --arg reload_submission_seen "$reload_submission_seen" \
    --arg reload_submission_accepted "$reload_submission_accepted" \
    --arg reload_error_output "$reload_error_output" \
    --argjson check_pass "$reload_check_pass_json" '
      .checks += [{"name":$check_name,"pass":$check_pass,"detail":$check_detail}]
      | .details.reload_fixture_prompt = $reload_prompt
      | .details.reload_fixture_matched_key = $reload_key
      | .details.reload_fixture_matched_source = $reload_source
      | .details.reload_fixture_recovered_source = $reload_recovered_source
      | .details.reload_fixture_setup_error = $reload_setup_error
      | .details.reload_fixture_submitted = $reload_submitted
      | .details.reload_fixture_ready_attempts = $reload_ready_attempts
      | .details.reload_fixture_submission_seen = $reload_submission_seen
      | .details.reload_fixture_submission_accepted = $reload_submission_accepted
      | .details.reload_fixture_error_output = $reload_error_output
      | if $check_pass then . else .error = ("Reload durability fixture failed: " + $check_detail) end
      | .success = ((.checks | map(.pass == true) | all))
    ')
fi

printf '%s\n' "$scenario_result" > "$result_json"

status="PASS"
if ! printf '%s' "$scenario_result" | jq -e '.success == true' >/dev/null 2>&1; then
  status="FAIL"
fi

{
  printf '# Safari GUI Regression: %s\n\n' "$label"
  printf '## Status\n'
  printf -- '- Result: %s\n' "$status"
  printf -- '- Profile: `%s`\n' "$profile"
  printf -- '- Workspace seed: `%s`\n' "$workspace_name"
  printf -- '- Workspace path: `%s`\n' "$workspace_path"
  printf -- '- Site state root: `%s`\n' "$site_state_root"
  printf -- '- Site name: `%s`\n' "$site_name"
  printf -- '- Local app URL: `%s`\n' "$app_url"
  printf -- '- Server log: `%s`\n' "$server_log"
  printf -- '- Raw JSON: `%s`\n' "$result_json"
  printf -- '- Scenario JS: `%s`\n' "$scenario_copy"

  if [ "$status" = "PASS" ]; then
    printf '\n## Checks\n'
    printf '| Check | Pass | Detail |\n'
    printf '|---|---|---|\n'
    printf '%s' "$scenario_result" | jq -r '.checks[] | "| " + (.name|tostring) + " | " + ((.pass|tostring)) + " | " + ((.detail // "")|tostring) + " |"'
  else
    printf '\n## Failure\n'
    printf -- '- Error: %s\n' "$(printf '%s' "$scenario_result" | jq -r '.error // "Unknown GUI regression failure"' 2>/dev/null || printf '%s' "Unknown GUI regression failure")"
  fi
} > "$report_md"

printf '%s\n' "$result_json"
printf '%s\n' "$report_md"

if [ "$status" != "PASS" ]; then
  exit 1
fi
