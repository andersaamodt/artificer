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
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for Firefox GUI automation." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for Firefox GUI automation." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for Firefox GUI automation." >&2
  exit 1
fi

firefox_bin=""
for candidate in firefox firefox-esr; do
  if command -v "$candidate" >/dev/null 2>&1; then
    firefox_bin=$candidate
    break
  fi
done

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
site_name="artificer-gui-firefox-$label"

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      workspace_name="gui-regression-$label"
      conversation_a_title="GUI regression A $label"
      conversation_b_title="GUI regression B $label"
      conversation_c_title="GUI regression C $label"
      draft_seed_text="GUI seeded draft $label"
      site_name="artificer-gui-firefox-$label"
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
  echo "Requested Firefox GUI regression port is unavailable: $port" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
server_log="$OUT_DIR/$label-gui-firefox-server.log"
result_json="$OUT_DIR/$label-gui-firefox-result.json"
report_md="$OUT_DIR/$label-gui-firefox-report.md"
workspace_path=$(mktemp -d "${TMPDIR:-/tmp}/artificer-gui-firefox-workspace.XXXXXX")
site_state_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-gui-firefox-site-state.XXXXXX")

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$server_pid" 2>/dev/null; then
      kill -9 "$server_pid" 2>/dev/null || true
    fi
  fi
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

run_with_timeout() {
  timeout_seconds=$1
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

if len(sys.argv) < 3:
    print("run_with_timeout requires timeout and command", file=sys.stderr)
    sys.exit(2)

try:
    timeout_seconds = float(sys.argv[1])
except Exception:
    timeout_seconds = 0.0
command = sys.argv[2:]

try:
    completed = subprocess.run(command, timeout=timeout_seconds if timeout_seconds > 0 else None)
except subprocess.TimeoutExpired:
    print(
        "__TIMEOUT__ command timed out after "
        + str(int(timeout_seconds) if timeout_seconds > 0 else 0)
        + "s: "
        + " ".join(command),
        file=sys.stderr,
    )
    sys.exit(124)

sys.exit(int(completed.returncode))
PY
}

ensure_playwright_python() {
  py_cmd="${ARTIFICER_GUI_PYTHON:-python3}"
  if "$py_cmd" - <<'PY' >/dev/null 2>&1
from playwright.sync_api import sync_playwright
PY
  then
    printf '%s' "$py_cmd"
    return 0
  fi

  venv_dir="$ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR"
  if [ ! -x "$venv_dir/bin/python3" ]; then
    python3 -m venv "$venv_dir"
  fi
  if "$venv_dir/bin/python3" - <<'PY' >/dev/null 2>&1
from playwright.sync_api import sync_playwright
PY
  then
    printf '%s' "$venv_dir/bin/python3"
    return 0
  fi
  run_with_timeout "${ARTIFICER_GUI_FIREFOX_PIP_TIMEOUT_SEC:-420}" \
    "$venv_dir/bin/python3" -m pip install --upgrade pip >/dev/null 2>&1 || true
  if ! run_with_timeout "${ARTIFICER_GUI_FIREFOX_PIP_TIMEOUT_SEC:-420}" \
    "$venv_dir/bin/python3" -m pip install playwright >/dev/null 2>&1; then
    echo "Timed out or failed while installing Playwright Python package." >&2
    return 1
  fi
  printf '%s' "$venv_dir/bin/python3"
}

PYTHON_BIN=$(ensure_playwright_python)
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR}"
export PLAYWRIGHT_BROWSERS_PATH
if ! run_with_timeout "${ARTIFICER_GUI_FIREFOX_BROWSER_TIMEOUT_SEC:-600}" \
  "$PYTHON_BIN" -m playwright install firefox >/dev/null 2>&1; then
  echo "Timed out or failed while installing Playwright Firefox runtime." >&2
  exit 1
fi

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
for _ in $(seq 1 90); do
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
  echo "Failed to seed workspace for Firefox GUI regression." >&2
  exit 1
fi
conversation_a_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_a_title")" || true)
conversation_a_id=$(printf '%s' "$conversation_a_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_a_id" ]; then
  echo "Failed to seed first conversation for Firefox GUI regression." >&2
  exit 1
fi
conversation_b_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_b_title")" || true)
conversation_b_id=$(printf '%s' "$conversation_b_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_b_id" ]; then
  echo "Failed to seed second conversation for Firefox GUI regression." >&2
  exit 1
fi
conversation_c_json=$(post_http_json "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=$(urlenc "$conversation_c_title")" || true)
conversation_c_id=$(printf '%s' "$conversation_c_json" | jq -r '.conversation.id // ""' 2>/dev/null || printf '%s' "")
if [ -z "$conversation_c_id" ]; then
  echo "Failed to seed third conversation for Firefox GUI regression." >&2
  exit 1
fi
if ! post_http_json "action=save_draft&workspace_id=$(urlenc "$workspace_id")&draft=$(urlenc "$draft_seed_text")" >/dev/null 2>&1; then
  echo "Failed to seed workspace draft for Firefox GUI regression." >&2
  exit 1
fi

app_url="http://127.0.0.1:$port/pages/index.html?workspace=$workspace_id&conversation=$conversation_a_id"

scenario_result=$("$PYTHON_BIN" - "$app_url" "$workspace_id" "$workspace_name" "$conversation_a_title" "$conversation_b_title" "$conversation_c_title" "$profile" "$firefox_bin" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright

app_url = sys.argv[1]
workspace_id = sys.argv[2]
workspace_name = sys.argv[3]
conversation_a_title = sys.argv[4]
conversation_b_title = sys.argv[5]
conversation_c_title = sys.argv[6]
profile = sys.argv[7]
firefox_bin = sys.argv[8]
api_url = urllib.parse.urljoin(app_url, "/cgi/artificer-api")

result = {
    "success": False,
    "engine": "firefox-playwright",
    "profile": profile,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "checks": [],
    "details": {},
}


def add_check(name, passed, detail):
    result["checks"].append({"name": name, "pass": bool(passed), "detail": str(detail or "")})
    if not passed:
        raise AssertionError(f"{name}: {detail}")


def parse_json_payload(raw_text):
    text = str(raw_text or "")
    start = text.find("{")
    if start >= 0:
        text = text[start:]
    return json.loads(text)


def api_get(params):
    url = api_url + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=60) as response:
        return parse_json_payload(response.read().decode())


def api_post(params):
    payload = urllib.parse.urlencode(params).encode()
    request = urllib.request.Request(api_url, data=payload, method="POST")
    with urllib.request.urlopen(request, timeout=90) as response:
        return parse_json_payload(response.read().decode())


def set_runtime_prefs(page):
    page.evaluate(
        """() => {
          try {
            localStorage.setItem("artificer.agentLoopEnabled", "0");
            localStorage.setItem("artificer.organizeShow", "all");
            localStorage.setItem("artificer.organizeMode", "project");
            localStorage.setItem("artificer.computeBudget", "quick");
            localStorage.setItem("artificer.reasoningEffort", "low");
          } catch (_err) {
            // best effort only
          }
        }"""
    )


def dom_click(locator):
    locator.first.evaluate(
        """(node) => {
          if (!node) {
            return false;
          }
          try {
            node.scrollIntoView({ block: 'center', inline: 'center' });
          } catch (_scrollErr) {
            // best effort only
          }
          if (typeof node.click === 'function') {
            node.click();
            return true;
          }
          const ev = new MouseEvent('click', { bubbles: true, cancelable: true, view: window });
          node.dispatchEvent(ev);
          return true;
        }"""
    )


def wait_for_run_controls(page):
    page.wait_for_function(
        """() => {
          function visible(node) {
            if (!node) {
              return false;
            }
            const style = window.getComputedStyle(node);
            return !!style && style.display !== 'none' && style.visibility !== 'hidden' && node.getClientRects().length > 0;
          }
          return (
            visible(document.getElementById('run-mode-btn')) &&
            visible(document.getElementById('run-prompt')) &&
            visible(document.getElementById('run-btn'))
          );
        }""",
        timeout=30000,
    )


def ensure_run_mode(page, mode_id, expected_label):
    menu_open = page.evaluate(
        "() => { const node = document.getElementById('run-mode-menu'); return !!node && !node.classList.contains('hidden'); }"
    )
    if not menu_open:
      page.click("#run-mode-btn")
      page.wait_for_selector("#run-mode-menu:not(.hidden)", timeout=6000)
    item = page.locator(f"button.run-mode-item[data-run-mode='{mode_id}']")
    add_check(
        f"{expected_label} mode is present in menu",
        item.count() > 0,
        f"data-run-mode={mode_id}",
    )
    dom_click(item)
    page.wait_for_function(
        """(needle) => {
          const node = document.getElementById('run-mode-btn');
          return !!node && String(node.textContent || '').toLowerCase().indexOf(String(needle || '').toLowerCase()) >= 0;
        }""",
        arg=expected_label,
        timeout=8000,
    )


def interactive_output_snapshot(page, conversation_id):
    return page.evaluate(
        """(conversationId) => {
          const convId = String(conversationId || "");
          let runEvent = null;
          try {
            const raw = String(localStorage.getItem('artificer.runEventsByConversation.v1') || '');
            if (raw) {
              const parsed = JSON.parse(raw);
              const list = Array.isArray(parsed && parsed[convId]) ? parsed[convId] : [];
              if (list.length) {
                runEvent = list[list.length - 1] || null;
              }
            }
          } catch (_err) {
            runEvent = null;
          }
          const assistantBodies = Array.from(document.querySelectorAll('#chat-log .msg.assistant .msg-body'));
          let assistantText = '';
          if (assistantBodies.length) {
            assistantText = String((assistantBodies[assistantBodies.length - 1] && assistantBodies[assistantBodies.length - 1].textContent) || '');
          }
          const chatNode = document.getElementById('chat-log');
          const chatText = String((chatNode && chatNode.textContent) || '');
          const streamText = String((runEvent && runEvent.stream_text) || '');
          const combined = [assistantText, chatText, streamText].filter(Boolean).join('\\n');
          return {
            assistant_excerpt: assistantText.slice(0, 500),
            chat_excerpt: chatText.slice(0, 700),
            combined_text: combined,
            combined_excerpt: combined.slice(0, 900),
            combined_lower: combined.toLowerCase(),
            run_event_status: String((runEvent && runEvent.status) || ''),
            run_event_stream_length: String(streamText || '').trim().length,
            run_event_stream_excerpt: streamText.slice(0, 700),
            run_event_awaiting_assistant: Number((runEvent && runEvent.awaiting_assistant) || 0) > 0,
            has_running_line: !!document.querySelector('#chat-log .run-line.running[data-started-at]'),
            run_line_count: Array.from(document.querySelectorAll('#chat-log .run-line')).length,
          };
        }""",
        conversation_id,
    )


def conversation_snapshot(conversation_id):
    payload = api_get(
        {
            "action": "get_conversation",
            "workspace_id": workspace_id,
            "conversation_id": conversation_id,
        }
    )
    return payload.get("conversation") or {}


def queue_summary(conversation_id):
    payload = api_get(
        {
            "action": "queue_list",
            "workspace_id": workspace_id,
            "conversation_id": conversation_id,
            "limit": 1,
        }
    )
    return {
        "queue_pending": int(payload.get("queue_pending") or 0),
        "queue_running": int(payload.get("queue_running") or 0),
        "queue_last_status": str(payload.get("queue_last_status") or ""),
    }


def latest_assistant_message_from_conversation(conversation):
    messages = conversation.get("messages") or []
    latest = ""
    for message in messages:
        if str((message or {}).get("role") or "") != "assistant":
            continue
        latest = str((message or {}).get("content") or "")
    return latest


def contract_present(text, expected_anchor):
    lower = str(text or "").lower()
    return (
        expected_anchor in lower
        and "initial assumption:" in lower
        and "invalidating evidence:" in lower
        and "revised decision:" in lower
        and "claim-to-evidence map:" in lower
    )


def wait_for_interactive_contract(page, conversation_id, expected_anchor, timeout_seconds):
    deadline = time.time() + max(float(timeout_seconds or 0), 1.0)
    idle_without_contract_count = 0
    last_snapshot = {}
    while time.time() < deadline:
        ui_snapshot = interactive_output_snapshot(page, conversation_id)
        conversation = conversation_snapshot(conversation_id)
        queue = queue_summary(conversation_id)
        assistant_text = latest_assistant_message_from_conversation(conversation)
        combined_text = "\n".join(
            [part for part in [assistant_text, str(ui_snapshot.get("combined_text") or "")] if str(part or "").strip()]
        )
        combined_lower = combined_text.lower()
        snapshot = {
            "assistant_text": assistant_text,
            "assistant_excerpt": assistant_text[:500],
            "combined_text": combined_text,
            "combined_excerpt": combined_text[:900],
            "combined_lower": combined_lower,
            "queue_pending": queue.get("queue_pending"),
            "queue_running": queue.get("queue_running"),
            "queue_last_status": queue.get("queue_last_status"),
            "ui": ui_snapshot,
        }
        last_snapshot = snapshot
        if contract_present(combined_lower, expected_anchor):
            snapshot["contract_present"] = True
            snapshot["timed_out"] = False
            return snapshot
        queue_idle = int(queue.get("queue_running") or 0) < 1 and int(queue.get("queue_pending") or 0) < 1
        if queue_idle and assistant_text.strip():
            idle_without_contract_count += 1
            if idle_without_contract_count >= 3:
                snapshot["contract_present"] = False
                snapshot["timed_out"] = False
                snapshot["idle_without_contract"] = True
                return snapshot
        else:
            idle_without_contract_count = 0
        page.wait_for_timeout(1000)
    last_snapshot["contract_present"] = contract_present(last_snapshot.get("combined_lower") or "", expected_anchor)
    last_snapshot["timed_out"] = True
    return last_snapshot


def wait_for_interactive_settle(page, conversation_id, timeout_seconds):
    deadline = time.time() + max(float(timeout_seconds or 0), 1.0)
    last_snapshot = {}
    while time.time() < deadline:
        ui_snapshot = interactive_output_snapshot(page, conversation_id)
        queue = queue_summary(conversation_id)
        snapshot = {
            "queue_pending": queue.get("queue_pending"),
            "queue_running": queue.get("queue_running"),
            "queue_last_status": queue.get("queue_last_status"),
            "has_running_line": bool(ui_snapshot.get("has_running_line")),
            "run_event_stream_length": ui_snapshot.get("run_event_stream_length"),
        }
        last_snapshot = snapshot
        queue_idle = int(queue.get("queue_running") or 0) < 1 and int(queue.get("queue_pending") or 0) < 1
        if queue_idle and not snapshot["has_running_line"]:
            snapshot["settled"] = True
            return snapshot
        page.wait_for_timeout(1000)
    last_snapshot["settled"] = False
    return last_snapshot


def interactive_intelligence_scenarios():
    return [
        {
            "id": "causal",
            "title": conversation_a_title,
            "check_prefix": "interactive causal scenario",
            "prompt_text": (
                "Trial starts jump right after the ranking tweak, but refunds, cancellation calls, and support queue age worsen "
                "a week later in the same cohorts. In 5 short labeled lines only, decide whether the ranking change helped and "
                "show what overturned the first read. Use these labels exactly once each: Outcome, Initial Assumption, "
                "Invalidating Evidence, Revised Decision, Claim-to-Evidence Map."
            ),
            "expected_anchor": "trial-start gains versus refunds, queue age, and cancellation pressure after ranking changes",
        },
        {
            "id": "security",
            "title": conversation_b_title,
            "check_prefix": "interactive security scenario",
            "prompt_text": (
                "A regional outage override first looks safe because only incident responders would use it. Then audit cannot "
                "attribute exports, residency boundaries shift during failover, and the workaround needs broader plaintext access "
                "than planned. In 5 short labeled lines only, recommend the safest path and make the revised decision explicit. "
                "Use these labels exactly once each: Outcome, Initial Assumption, Invalidating Evidence, Revised Decision, "
                "Claim-to-Evidence Map."
            ),
            "expected_anchor": "regional outage override with export gaps, residency drift, and plaintext expansion",
        },
        {
            "id": "strategy",
            "title": conversation_c_title,
            "check_prefix": "interactive strategy scenario",
            "prompt_text": (
                "Pushing harder into a partner-heavy region looks like the obvious path because trial conversions jump. Then "
                "renewal cohorts weaken, the reliability budget is nearly spent, and counsel says the same region may trigger "
                "sanctions exposure next quarter. In 5 short labeled lines only, recommend the strategy and spell out the pivot. "
                "Use these labels exactly once each: Outcome, Initial Assumption, Invalidating Evidence, Revised Decision, "
                "Claim-to-Evidence Map."
            ),
            "expected_anchor": "regional growth push versus renewals, reliability budget, and sanctions exposure",
        },
    ]


def run_interactive_intelligence_scenario(page, scenario, first_scenario=False):
    rows = page.locator(f".conversation-row[data-workspace-id='{workspace_id}']")
    row = rows.filter(has_text=scenario["title"])
    add_check(
        f"{scenario['check_prefix']} target conversation row is present",
        row.count() > 0,
        scenario["title"],
    )
    conversation_id = str(row.first.get_attribute("data-conversation-id") or "")
    add_check(
        f"{scenario['check_prefix']} target conversation is available",
        bool(conversation_id),
        conversation_id or "missing",
    )

    dom_click(row)
    page.wait_for_timeout(240)

    wait_for_run_controls(page)
    add_check(
        f"{scenario['check_prefix']} run controls are visible",
        True,
        "run mode, prompt, and run button are visible",
    )

    run_mode_label = page.locator("#run-mode-btn").inner_text(timeout=5000)
    if first_scenario:
        add_check(
            "interactive intelligence starts from default run mode",
            bool(str(run_mode_label or "").strip()),
            run_mode_label,
        )
    else:
        add_check(
            f"{scenario['check_prefix']} preserves a usable run mode",
            bool(str(run_mode_label or "").strip()),
            run_mode_label,
        )

    prompt = page.locator("#run-prompt")
    prompt.fill(scenario["prompt_text"])
    page.wait_for_timeout(240)
    page.click("#run-btn")
    page.wait_for_timeout(1500)

    captured = page.evaluate(
        """(targetPrompt) => {
          const messageBodies = Array.from(document.querySelectorAll('.msg.user .msg-body'));
          const rendered = messageBodies.some((node) => String(node && node.textContent || '').indexOf(targetPrompt) >= 0);
          let pendingFound = false;
          try {
            const raw = String(localStorage.getItem('artificer.pendingOutgoingByKey.v1') || '');
            if (raw) {
              const parsed = JSON.parse(raw);
              const keys = Object.keys(parsed || {});
              for (let i = 0; i < keys.length; i += 1) {
                const list = Array.isArray(parsed[keys[i]]) ? parsed[keys[i]] : [];
                for (let j = 0; j < list.length; j += 1) {
                  const content = String((list[j] && list[j].content) || '');
                  if (content.indexOf(targetPrompt) >= 0) {
                    pendingFound = true;
                    break;
                  }
                }
                if (pendingFound) {
                  break;
                }
              }
            }
          } catch (_err) {
            pendingFound = false;
          }
          return { rendered, pendingFound };
        }""",
        scenario["prompt_text"],
    )
    add_check(
        f"{scenario['check_prefix']} prompt is captured in UI or pending queue",
        bool(captured.get("rendered")) or bool(captured.get("pendingFound")),
        f"rendered={captured.get('rendered')} pendingFound={captured.get('pendingFound')}",
    )

    page.wait_for_function(
        """(conversationId) => {
          const convId = String(conversationId || '');
          let runEvent = null;
          try {
            const raw = String(localStorage.getItem('artificer.runEventsByConversation.v1') || '');
            if (raw) {
              const parsed = JSON.parse(raw);
              const list = Array.isArray(parsed && parsed[convId]) ? parsed[convId] : [];
              if (list.length) {
                runEvent = list[list.length - 1] || null;
              }
            }
          } catch (_err) {
            runEvent = null;
          }
          const streamLength = String((runEvent && runEvent.stream_text) || '').trim().length;
          return (
            !!document.querySelector('#chat-log .run-line.running[data-started-at]') ||
            streamLength > 0 ||
            !!document.querySelector('#chat-log .msg.assistant .msg-body')
          );
        }""",
        arg=conversation_id,
        timeout=45000,
    )
    live_snapshot = interactive_output_snapshot(page, conversation_id)
    add_check(
        f"{scenario['check_prefix']} run shows live activity",
        bool(live_snapshot.get("has_running_line")) or int(live_snapshot.get("run_event_stream_length") or 0) > 0,
        f"running_line={live_snapshot.get('has_running_line')} stream_length={live_snapshot.get('run_event_stream_length')}",
    )

    final_snapshot = wait_for_interactive_contract(
        page,
        conversation_id,
        scenario["expected_anchor"],
        100,
    )
    assistant_text = str(final_snapshot.get("combined_text") or "")
    assistant_lower = assistant_text.lower()
    add_check(
        f"{scenario['check_prefix']} reaches a bounded final state",
        bool(final_snapshot.get("contract_present")),
        json.dumps(
            {
                "timed_out": bool(final_snapshot.get("timed_out")),
                "idle_without_contract": bool(final_snapshot.get("idle_without_contract")),
                "queue_pending": final_snapshot.get("queue_pending"),
                "queue_running": final_snapshot.get("queue_running"),
                "queue_last_status": final_snapshot.get("queue_last_status"),
                "assistant_excerpt": str(final_snapshot.get("assistant_excerpt") or "")[:220],
                "ui_excerpt": str(((final_snapshot.get("ui") or {}).get("combined_excerpt") or ""))[:220],
            }
        ),
    )
    add_check(
        f"{scenario['check_prefix']} includes scenario anchor",
        scenario["expected_anchor"] in assistant_lower,
        assistant_text[:260],
    )
    add_check(
        f"{scenario['check_prefix']} includes explicit revision contract",
        "initial assumption:" in assistant_lower and "invalidating evidence:" in assistant_lower and "revised decision:" in assistant_lower,
        assistant_text[:320],
    )
    add_check(
        f"{scenario['check_prefix']} includes claim-to-evidence map",
        "claim-to-evidence map:" in assistant_lower,
        assistant_text[:320],
    )
    add_check(
        f"{scenario['check_prefix']} avoids generic cross-domain fallback",
        "cross-domain integrated reasoning" not in assistant_lower,
        assistant_text[:320],
    )
    settle_snapshot = wait_for_interactive_settle(page, conversation_id, 20)
    add_check(
        f"{scenario['check_prefix']} settles before the next scenario",
        bool(settle_snapshot.get("settled")),
        json.dumps(settle_snapshot),
    )
    return {
        "id": scenario["id"],
        "conversation_id": conversation_id,
        "prompt_text": scenario["prompt_text"],
        "expected_anchor": scenario["expected_anchor"],
        "assistant_excerpt": assistant_text[:400],
        "run_mode_label": str(run_mode_label or ""),
        "debug": final_snapshot,
        "settle_debug": settle_snapshot,
    }


def prepare_intelligence_page(page, include_checks=False):
    page.goto(app_url, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_function("window.__artificerBooted === true", timeout=45000)
    if include_checks:
        add_check("app boot completes", True, "window.__artificerBooted became true")

    workspace_row = page.locator(f".workspace-row[data-workspace-id='{workspace_id}']")
    if include_checks:
        add_check(
            "seeded workspace row appears",
            workspace_row.count() > 0,
            f"workspace id {workspace_id} visible",
        )
    dom_click(workspace_row)
    page.wait_for_timeout(300)
    rows = page.locator(f".conversation-row[data-workspace-id='{workspace_id}']")
    if include_checks:
        add_check("seeded conversation rows appear", rows.count() >= 3, f"row count={rows.count()}")
        row_a = rows.filter(has_text=conversation_a_title)
        row_b = rows.filter(has_text=conversation_b_title)
        row_c = rows.filter(has_text=conversation_c_title)
        add_check(
            "three seeded conversations available",
            row_a.count() > 0 and row_b.count() > 0 and row_c.count() > 0,
            ",".join([conversation_a_title, conversation_b_title, conversation_c_title]),
        )


def run_intelligence_case(page):
    set_runtime_prefs(page)
    prepare_intelligence_page(page, include_checks=True)

    scenario_results = []
    for index, scenario in enumerate(interactive_intelligence_scenarios()):
        if index > 0:
            prepare_intelligence_page(page, include_checks=False)
        scenario_results.append(run_interactive_intelligence_scenario(page, scenario, first_scenario=(index == 0)))

    result["details"]["workspace_id"] = workspace_id
    result["details"]["workspace_name"] = workspace_name
    result["details"]["profile"] = profile
    result["details"]["firefox_binary"] = firefox_bin if firefox_bin else "playwright-managed"
    result["details"]["interactive_scenarios"] = scenario_results
    result["details"]["interactive_conversation_ids"] = [item["conversation_id"] for item in scenario_results]
    result["details"]["interactive_prompt"] = scenario_results[0]["prompt_text"]
    result["details"]["interactive_assistant_excerpt"] = scenario_results[-1]["assistant_excerpt"]
    result["details"]["interactive_run_mode_label"] = scenario_results[0]["run_mode_label"]
    result["details"]["interactive_debug"] = scenario_results[-1]["debug"]
    result["success"] = all(item.get("pass") for item in result["checks"])


def run_case():
    run_background_checks = profile in ("background", "full")
    with sync_playwright() as playwright:
        launch_kwargs = {"headless": True}
        if firefox_bin:
            launch_kwargs["executable_path"] = firefox_bin
        browser = playwright.firefox.launch(**launch_kwargs)
        context = browser.new_context(viewport={"width": 1365, "height": 920})
        page = context.new_page()

        try:
            if profile == "intelligence":
                run_intelligence_case(page)
                return

            page.goto(app_url, wait_until="domcontentloaded", timeout=60000)
            page.wait_for_function("window.__artificerBooted === true", timeout=45000)
            add_check("app boot completes", True, "window.__artificerBooted became true")

            page.click("#run-mode-btn")
            page.wait_for_selector("#run-mode-menu:not(.hidden)", timeout=6000)
            team_mode_name = page.locator("button.run-mode-item[data-run-mode='assistant'] .run-mode-name")
            add_check(
                "Team mode is present in menu",
                team_mode_name.count() > 0 and "team" in (team_mode_name.first.inner_text(timeout=3000) or "").lower(),
                team_mode_name.first.inner_text(timeout=3000) if team_mode_name.count() > 0 else "missing",
            )
            page.click("button.run-mode-item[data-run-mode='assistant']")
            page.wait_for_selector("#run-mode-more-list:not(.hidden)", timeout=6000)
            team_general = page.locator("button.run-mode-advanced-item[data-assistant-mode-id='']")
            add_check(
                "Team submenu exposes General Team option",
                team_general.count() > 0,
                "assistant_mode_id=''",
            )

            run_mode_item = page.locator("button.run-mode-item[data-run-mode='gui-testing']")
            add_check(
                "GUI Testing mode is present in menu",
                run_mode_item.count() > 0,
                "run mode selector includes data-run-mode=gui-testing",
            )

            workspace_row = page.locator(f".workspace-row[data-workspace-id='{workspace_id}']")
            add_check(
                "seeded workspace row appears",
                workspace_row.count() > 0,
                f"workspace id {workspace_id} visible",
            )
            dom_click(workspace_row)
            page.wait_for_timeout(240)

            rows = page.locator(f".conversation-row[data-workspace-id='{workspace_id}']")
            add_check("seeded conversation rows appear", rows.count() >= 2, f"row count={rows.count()}")

            row_a = rows.filter(has_text=conversation_a_title)
            row_b = rows.filter(has_text=conversation_b_title)
            add_check("conversation A row present", row_a.count() > 0, conversation_a_title)
            add_check("conversation B row present", row_b.count() > 0, conversation_b_title)

            prompt = page.locator("#run-prompt")
            dom_click(row_a)
            page.wait_for_timeout(240)
            alpha = f"alpha-draft-{int(time.time() * 1000)}"
            beta = f"beta-draft-{int(time.time() * 1000)}"
            prompt.fill(alpha)
            page.wait_for_timeout(900)

            dom_click(row_b)
            page.wait_for_timeout(240)
            prompt.fill(beta)
            page.wait_for_timeout(900)

            dom_click(row_a)
            page.wait_for_function(
                "(value) => { const node = document.getElementById('run-prompt'); return !!node && node.value === value; }",
                arg=alpha,
                timeout=8000,
            )
            dom_click(row_b)
            page.wait_for_function(
                "(value) => { const node = document.getElementById('run-prompt'); return !!node && node.value === value; }",
                arg=beta,
                timeout=8000,
            )
            add_check("conversation draft isolation holds", True, "each conversation retained its own draft text")

            is_run_mode_menu_open = page.evaluate(
                "() => { const n = document.getElementById('run-mode-menu'); return !!n && !n.classList.contains('hidden'); }"
            )
            if not is_run_mode_menu_open:
                page.click("#run-mode-btn")
                page.wait_for_selector("#run-mode-menu:not(.hidden)", timeout=6000)
            page.click("button.run-mode-item[data-run-mode='gui-testing']")
            page.wait_for_function(
                "() => { const node = document.getElementById('run-mode-btn'); return !!node && String(node.textContent || '').toLowerCase().indexOf('gui testing') >= 0; }",
                timeout=6000,
            )
            add_check("run mode switch to GUI Testing", True, "composer run mode button label updated")

            layout = page.evaluate(
                """() => {
                  const runForm = document.getElementById('run-form');
                  const chatLog = document.getElementById('chat-log');
                  const composer = document.getElementById('composer-row');
                  const runModeBtn = document.getElementById('run-mode-btn');
                  const modelBtn = document.getElementById('model-picker-btn');
                  const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
                  const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
                  if (!runForm || !chatLog || !composer || !runModeBtn || !modelBtn) {
                    return { ok: false, reason: 'missing-layout-nodes' };
                  }
                  const runRect = runForm.getBoundingClientRect();
                  const chatRect = chatLog.getBoundingClientRect();
                  const composerRect = composer.getBoundingClientRect();
                  const modeRect = runModeBtn.getBoundingClientRect();
                  const modelRect = modelBtn.getBoundingClientRect();
                  return {
                    ok: true,
                    viewportHeight,
                    viewportWidth,
                    runBottomGap: Math.max(0, viewportHeight - runRect.bottom),
                    composerBottomGap: Math.max(0, viewportHeight - composerRect.bottom),
                    chatHeight: chatRect.height,
                    runModeWidth: modeRect.width,
                    modelWidth: modelRect.width,
                  };
                }"""
            )
            if not layout.get("ok"):
                add_check("layout nodes present", False, layout.get("reason", "missing"))
            add_check(
                "composer anchored near bottom",
                float(layout.get("runBottomGap", 9999)) <= 120,
                f"runBottomGap={layout.get('runBottomGap')}",
            )
            add_check(
                "chat log has usable height",
                float(layout.get("chatHeight", 0)) >= 170,
                f"chatHeight={layout.get('chatHeight')}",
            )
            add_check(
                "composer controls stay fit-to-content",
                float(layout.get("runModeWidth", 0)) < float(layout.get("viewportWidth", 0)) * 0.65 and float(layout.get("modelWidth", 0)) < float(layout.get("viewportWidth", 0)) * 0.65,
                f"runModeWidth={layout.get('runModeWidth')} modelWidth={layout.get('modelWidth')} viewportWidth={layout.get('viewportWidth')}",
            )

            send_prompt = f"firefox-gui-regression-send-{int(time.time())}"
            prompt.fill(send_prompt)
            page.wait_for_timeout(180)
            page.click("#run-btn")
            page.wait_for_timeout(1800)
            captured = page.evaluate(
                """(targetPrompt) => {
                  const messageBodies = Array.from(document.querySelectorAll('.msg.user .msg-body'));
                  const rendered = messageBodies.some((node) => String(node && node.textContent || '').indexOf(targetPrompt) >= 0);
                  let pendingFound = false;
                  try {
                    const raw = String(localStorage.getItem('artificer.pendingOutgoingByKey.v1') || '');
                    if (raw) {
                      const parsed = JSON.parse(raw);
                      const keys = Object.keys(parsed || {});
                      for (let i = 0; i < keys.length; i += 1) {
                        const list = Array.isArray(parsed[keys[i]]) ? parsed[keys[i]] : [];
                        for (let j = 0; j < list.length; j += 1) {
                          const content = String((list[j] && list[j].content) || '');
                          if (content.indexOf(targetPrompt) >= 0) {
                            pendingFound = true;
                            break;
                          }
                        }
                        if (pendingFound) {
                          break;
                        }
                      }
                    }
                  } catch (_err) {
                    pendingFound = false;
                  }
                  return { rendered, pendingFound };
                }""",
                send_prompt,
            )
            add_check(
                "send captures user prompt in UI or pending queue",
                bool(captured.get("rendered")) or bool(captured.get("pendingFound")),
                f"rendered={captured.get('rendered')} pendingFound={captured.get('pendingFound')}",
            )

            if run_background_checks:
                before_reload = page.evaluate(
                    """() => ({
                      pathname: String(location.pathname || ''),
                      runModeLabel: String((document.getElementById('run-mode-btn') && document.getElementById('run-mode-btn').textContent) || ''),
                    })"""
                )
                page.reload(wait_until="domcontentloaded", timeout=60000)
                page.wait_for_function("window.__artificerBooted === true", timeout=45000)
                page.wait_for_selector(f".workspace-row[data-workspace-id='{workspace_id}']", timeout=12000)
                page.wait_for_function(
                    "() => { const node = document.getElementById('run-mode-btn'); return !!node && String(node.textContent || '').toLowerCase().indexOf('gui testing') >= 0; }",
                    timeout=10000,
                )
                after_reload = page.evaluate(
                    """() => ({
                      pathname: String(location.pathname || ''),
                      runModeLabel: String((document.getElementById('run-mode-btn') && document.getElementById('run-mode-btn').textContent) || ''),
                    })"""
                )
                add_check(
                    "reload preserves route path",
                    before_reload.get("pathname") == after_reload.get("pathname"),
                    f"before={before_reload.get('pathname')} after={after_reload.get('pathname')}",
                )

            result["details"]["workspace_id"] = workspace_id
            result["details"]["workspace_name"] = workspace_name
            result["details"]["conversation_a_title"] = conversation_a_title
            result["details"]["conversation_b_title"] = conversation_b_title
            result["details"]["profile"] = profile
            result["details"]["firefox_binary"] = firefox_bin if firefox_bin else "playwright-managed"
            result["success"] = all(item.get("pass") for item in result["checks"])
        finally:
            context.close()
            browser.close()


try:
    run_case()
except PlaywrightTimeoutError as err:
    result["error"] = f"Playwright timeout: {err}"
except Exception as err:
    result["error"] = str(err)

print(json.dumps(result))
PY
)

if ! printf '%s' "$scenario_result" | jq -e '.' >/dev/null 2>&1; then
  escaped=$(printf '%s' "$scenario_result" | jq -Rs '.' 2>/dev/null || printf '%s' '"Firefox scenario returned invalid JSON"')
  scenario_result=$(printf '{"success":false,"engine":"firefox-playwright","profile":"%s","generated_at":"%s","checks":[],"details":{},"error":"Firefox scenario returned invalid JSON","raw":%s}' "$profile" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$escaped")
fi

printf '%s\n' "$scenario_result" > "$result_json"

status="PASS"
if ! printf '%s' "$scenario_result" | jq -e '.success == true' >/dev/null 2>&1; then
  status="FAIL"
fi
firefox_label="$firefox_bin"
if [ -z "$firefox_label" ]; then
  firefox_label="playwright-managed"
fi

{
  printf '# Firefox GUI Regression: %s\n\n' "$label"
  printf '## Status\n'
  printf -- '- Result: %s\n' "$status"
  printf -- '- Engine: `firefox-playwright`\n'
  printf -- '- Profile: `%s`\n' "$profile"
  printf -- '- Workspace seed: `%s`\n' "$workspace_name"
  printf -- '- Workspace path: `%s`\n' "$workspace_path"
  printf -- '- Site state root: `%s`\n' "$site_state_root"
  printf -- '- Site name: `%s`\n' "$site_name"
  printf -- '- Firefox binary: `%s`\n' "$firefox_label"
  printf -- '- Local app URL: `%s`\n' "$app_url"
  printf -- '- Server log: `%s`\n' "$server_log"
  printf -- '- Raw JSON: `%s`\n' "$result_json"

  if [ "$status" = "PASS" ]; then
    printf '\n## Checks\n'
    printf '| Check | Pass | Detail |\n'
    printf '|---|---|---|\n'
    printf '%s' "$scenario_result" | jq -r '.checks[] | "| " + (.name|tostring) + " | " + ((.pass|tostring)) + " | " + ((.detail // "")|tostring) + " |"'
  else
    printf '\n## Failure\n'
    printf -- '- Error: %s\n' "$(printf '%s' "$scenario_result" | jq -r '.error // "Unknown Firefox GUI regression failure"' 2>/dev/null || printf '%s' "Unknown Firefox GUI regression failure")"
  fi
} > "$report_md"

printf '%s\n' "$result_json"
printf '%s\n' "$report_md"

if [ "$status" != "PASS" ]; then
  exit 1
fi
