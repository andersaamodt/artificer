#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="gui-state-recovery-pack-probe"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for GUI state recovery probe." >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required for Safari automation." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for GUI state recovery probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: gui-state-recovery-pack-probe.sh [--label NAME] [--scenario NAME]

Runs a deterministic Safari recovery flow:
1. open a local page with one or more blockers
2. recover from modal/popover/permission/stale-state blockers
3. verify the blocked action becomes available
4. complete the final action and confirm the recovered state
EOF_USAGE
}

json_escape() {
  printf '%s' "$1" | jq -Rs '.'
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

wait_for_http() {
  url=$1
  timeout_sec=$2
  python3 - "$url" "$timeout_sec" <<'PY'
import sys
import time
import urllib.request

url = sys.argv[1]
timeout = float(sys.argv[2])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            if 200 <= response.status < 500:
                sys.exit(0)
    except Exception:
        pass
    time.sleep(0.2)
sys.exit(1)
PY
}

quote_for_applescript() {
  python3 - "$1" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]), end="")
PY
}

safari_open_url() {
  target_url=$1
  target_url_quoted=$(quote_for_applescript "$target_url")
  osascript <<EOF_APPLESCRIPT >/dev/null
set targetUrl to $target_url_quoted
tell application "Safari"
  activate
  if (count of windows) = 0 then
    make new document with properties {URL:targetUrl}
  else
    set URL of front document to targetUrl
  end if
  set bounds of front window to {110, 80, 1220, 930}
end tell
delay 1.4
EOF_APPLESCRIPT
}

safari_do_javascript() {
  js_source=$1
  js_quoted=$(quote_for_applescript "$js_source")
  osascript <<EOF_APPLESCRIPT | tr -d '\r'
set jsSource to $js_quoted
tell application "Safari"
  activate
  return do JavaScript jsSource in current tab of front window
end tell
EOF_APPLESCRIPT
}

wait_for_js_truthy() {
  expr=$1
  timeout_sec=$2
  elapsed=0
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    result=$(safari_do_javascript "(function () { try { return ($expr) ? '1' : ''; } catch (_err) { return ''; } })();" 2>/dev/null || true)
    if [ "$result" = "1" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

render_demo_page() {
  scenario=$1
  html_path=$2
  state_key=$3
  case "$scenario" in
    modal-popover-stale)
      headline="Recovery pack: approvals queue"
      helper_copy="Dismiss the launch trap, close the coach popover, reload the stale queue state, then resume the approval flow."
      modal_default=true
      popover_default=true
      permission_default=false
      stale_default=true
      ;;
    permission-stale)
      headline="Recovery pack: import monitor"
      helper_copy="Resolve the permission gate, refresh the stale monitor state, then resume the import flow."
      modal_default=false
      popover_default=false
      permission_default=true
      stale_default=true
      ;;
    all-blockers)
      headline="Recovery pack: release workspace"
      helper_copy="Clear every blocker in order, reload the stale workspace, and recover the release action."
      modal_default=true
      popover_default=true
      permission_default=true
      stale_default=true
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  state_key_quoted=$(printf '%s' "$state_key" | sed "s/'/'\\\\''/g")
  headline_quoted=$(printf '%s' "$headline" | sed "s/'/'\\\\''/g")
  helper_copy_quoted=$(printf '%s' "$helper_copy" | sed "s/'/'\\\\''/g")
  cat > "$html_path" <<EOF_HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${headline}</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: "SF Pro Text", "Segoe UI", sans-serif;
    background:
      radial-gradient(circle at top right, #fef3c7 0%, rgba(254,243,199,0) 40%),
      linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  main {
    max-width: 860px;
    margin: 0 auto;
    padding: 44px 28px 72px;
  }
  .shell {
    background: rgba(255,255,255,0.92);
    border-radius: 28px;
    border: 1px solid rgba(148,163,184,0.22);
    box-shadow: 0 30px 70px rgba(15,23,42,0.12);
    padding: 28px;
  }
  h1 {
    margin: 0 0 10px;
    font-size: 38px;
    line-height: 1.05;
  }
  .lede {
    margin: 0 0 24px;
    color: #334155;
    font-size: 18px;
    line-height: 1.55;
  }
  .stack {
    display: grid;
    gap: 16px;
  }
  .row {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    align-items: center;
  }
  .panel {
    border-radius: 20px;
    border: 1px solid rgba(148,163,184,0.25);
    background: white;
    padding: 18px;
  }
  .banner {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    align-items: center;
    border-radius: 18px;
    padding: 16px 18px;
  }
  .warning {
    background: #fff7ed;
    border: 1px solid #fdba74;
    color: #9a3412;
  }
  .info {
    background: #eff6ff;
    border: 1px solid #93c5fd;
    color: #1d4ed8;
  }
  .success {
    background: #ecfdf5;
    border: 1px solid #86efac;
    color: #166534;
  }
  button {
    width: fit-content;
    border: 0;
    border-radius: 999px;
    padding: 11px 16px;
    font: inherit;
    font-weight: 700;
    cursor: pointer;
  }
  .ghost {
    background: #e2e8f0;
    color: #0f172a;
  }
  .primary {
    background: #0f766e;
    color: white;
  }
  .danger {
    background: #b91c1c;
    color: white;
  }
  .hidden {
    display: none !important;
  }
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(15,23,42,0.42);
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 28px;
  }
  .modal {
    width: min(560px, 100%);
    background: #fff8ed;
    border: 2px solid #fdba74;
    border-radius: 26px;
    padding: 24px;
    box-shadow: 0 28px 80px rgba(15,23,42,0.28);
  }
  .popover {
    position: absolute;
    top: 122px;
    right: 24px;
    width: 260px;
    background: #0f172a;
    color: white;
    border-radius: 18px;
    padding: 16px;
    box-shadow: 0 24px 60px rgba(15,23,42,0.32);
  }
  .status-pill {
    width: fit-content;
    border-radius: 999px;
    padding: 8px 12px;
    background: #e2e8f0;
    color: #334155;
    font-weight: 700;
  }
  .muted {
    color: #475569;
    font-size: 15px;
  }
  .workspace {
    position: relative;
    min-height: 240px;
  }
</style>
</head>
<body>
  <main>
    <section class="shell stack">
      <div>
        <h1>${headline}</h1>
        <p class="lede">${helper_copy}</p>
      </div>
      <div class="row">
        <div id="modal-pill" class="status-pill">Modal pending</div>
        <div id="popover-pill" class="status-pill">Popover pending</div>
        <div id="permission-pill" class="status-pill">Permission pending</div>
        <div id="stale-pill" class="status-pill">Stale state pending</div>
      </div>
      <div id="permission-banner" class="banner warning hidden">
        <div>
          <strong>Permission required</strong>
          <div class="muted">Allow the release workspace to continue the guided recovery checks.</div>
        </div>
        <button id="allow-permission" class="primary" type="button">Allow once</button>
      </div>
      <div class="workspace panel">
        <div id="popover-card" class="popover hidden">
          <strong>Coach tip</strong>
          <div class="muted" style="color:#cbd5e1">This help bubble obscures the top-right action cluster until dismissed.</div>
          <div style="margin-top:12px">
            <button id="dismiss-popover" class="ghost" type="button">Dismiss tip</button>
          </div>
        </div>
        <div id="stale-banner" class="banner info hidden">
          <div>
            <strong>Workspace tab is stale</strong>
            <div class="muted">Reload the workspace state before the resume action can be trusted.</div>
          </div>
          <button id="refresh-stale" class="ghost" type="button">Reload workspace</button>
        </div>
        <div class="panel success" style="margin-top:16px">
          <strong>Recovery destination</strong>
          <div class="muted">All blockers must clear before the release action resumes.</div>
          <div class="row" style="margin-top:14px">
            <button id="resume-action" class="primary" type="button" disabled>Resume release</button>
            <div id="recovery-status" class="muted">Blocked by pending recovery steps.</div>
          </div>
        </div>
      </div>
    </section>
  </main>
  <div id="modal-backdrop" class="modal-backdrop hidden">
    <section class="modal">
      <h2 style="margin:0 0 10px;font-size:30px;line-height:1.1">Recovery modal trap</h2>
      <p class="muted" style="margin:0 0 16px">A launch confirmation is blocking the rest of the workspace until it is dismissed.</p>
      <button id="dismiss-modal" class="danger" type="button">Dismiss blocking modal</button>
    </section>
  </div>
<script>
(() => {
  const stateKey = '${state_key_quoted}';
  const initialState = {
    modalOpen: ${modal_default},
    popoverOpen: ${popover_default},
    permissionPending: ${permission_default},
    stalePending: ${stale_default},
    reloaded: false,
    recovered: false
  };

  function cloneState(source) {
    return JSON.parse(JSON.stringify(source));
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(stateKey);
      if (!raw) return cloneState(initialState);
      const parsed = JSON.parse(raw);
      return Object.assign(cloneState(initialState), parsed || {});
    } catch (_err) {
      return cloneState(initialState);
    }
  }

  function saveState() {
    localStorage.setItem(stateKey, JSON.stringify(state));
  }

  function readyToResume() {
    return !state.modalOpen && !state.popoverOpen && !state.permissionPending && !state.stalePending;
  }

  const modalPill = document.getElementById('modal-pill');
  const popoverPill = document.getElementById('popover-pill');
  const permissionPill = document.getElementById('permission-pill');
  const stalePill = document.getElementById('stale-pill');
  const modalBackdrop = document.getElementById('modal-backdrop');
  const permissionBanner = document.getElementById('permission-banner');
  const popoverCard = document.getElementById('popover-card');
  const staleBanner = document.getElementById('stale-banner');
  const resumeButton = document.getElementById('resume-action');
  const recoveryStatus = document.getElementById('recovery-status');

  const state = loadState();
  if (state.refreshRequested) {
    state.stalePending = false;
    state.reloaded = true;
    state.refreshRequested = false;
    saveState();
  }

  function setPill(node, active, label) {
    node.textContent = active ? label + ' pending' : label + ' clear';
    node.style.background = active ? '#fee2e2' : '#dcfce7';
    node.style.color = active ? '#991b1b' : '#166534';
  }

  function applyView() {
    modalBackdrop.classList.toggle('hidden', !state.modalOpen);
    popoverCard.classList.toggle('hidden', !state.popoverOpen);
    permissionBanner.classList.toggle('hidden', !state.permissionPending);
    staleBanner.classList.toggle('hidden', !state.stalePending);
    setPill(modalPill, state.modalOpen, 'Modal');
    setPill(popoverPill, state.popoverOpen, 'Popover');
    setPill(permissionPill, state.permissionPending, 'Permission');
    setPill(stalePill, state.stalePending, 'Stale state');
    document.body.dataset.modalOpen = state.modalOpen ? 'yes' : 'no';
    document.body.dataset.popoverOpen = state.popoverOpen ? 'yes' : 'no';
    document.body.dataset.permissionPending = state.permissionPending ? 'yes' : 'no';
    document.body.dataset.stalePending = state.stalePending ? 'yes' : 'no';
    document.body.dataset.reloaded = state.reloaded ? 'yes' : 'no';
    document.body.dataset.recovered = state.recovered ? 'yes' : 'no';
    resumeButton.disabled = !readyToResume();
    if (state.recovered) {
      recoveryStatus.textContent = 'Recovery pack complete.';
    } else if (readyToResume()) {
      recoveryStatus.textContent = 'All blockers cleared. Resume release is ready.';
    } else {
      recoveryStatus.textContent = 'Blocked by pending recovery steps.';
    }
  }

  document.getElementById('dismiss-modal').addEventListener('click', () => {
    state.modalOpen = false;
    saveState();
    applyView();
  });

  document.getElementById('dismiss-popover').addEventListener('click', () => {
    state.popoverOpen = false;
    saveState();
    applyView();
  });

  document.getElementById('allow-permission').addEventListener('click', () => {
    state.permissionPending = false;
    saveState();
    applyView();
  });

  window.demoResolvePermission = () => {
    const button = document.getElementById('allow-permission');
    if (button) {
      button.click();
    }
    return document.body.dataset.permissionPending || '';
  };

  document.getElementById('refresh-stale').addEventListener('click', () => {
    state.refreshRequested = true;
    saveState();
    location.reload();
  });

  window.demoRecoverStale = () => {
    const button = document.getElementById('refresh-stale');
    if (button) {
      button.click();
    }
    return 'ok';
  };

  resumeButton.addEventListener('click', () => {
    if (!readyToResume()) return;
    state.recovered = true;
    saveState();
    applyView();
  });

  applyView();
})();
</script>
</body>
</html>
EOF_HTML
}

score_result() {
  modal_cleared=$1
  popover_cleared=$2
  permission_resolved=$3
  stale_recovered=$4
  resume_complete=$5
  if [ "$modal_cleared" -eq 1 ] \
    && [ "$popover_cleared" -eq 1 ] \
    && [ "$permission_resolved" -eq 1 ] \
    && [ "$stale_recovered" -eq 1 ] \
    && [ "$resume_complete" -eq 1 ]; then
    printf '%s' "pass"
  else
    printf '%s' "fail"
  fi
}

label=$DEFAULT_LABEL
scenario="modal-popover-stale"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --scenario)
      scenario=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$scenario" in
  modal-popover-stale)
    expect_modal=1
    expect_popover=1
    expect_permission=0
    expect_stale=1
    ;;
  permission-stale)
    expect_modal=0
    expect_popover=0
    expect_permission=1
    expect_stale=1
    ;;
  all-blockers)
    expect_modal=1
    expect_popover=1
    expect_permission=1
    expect_stale=1
    ;;
  *)
    echo "Unknown scenario: $scenario" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"
server_root="$raw_dir/site"
mkdir -p "$server_root"
page_html="$server_root/index.html"
state_key="gui-state-recovery:$label:$scenario"
port=$(pick_free_port)
server_log="$raw_dir/http-server.log"

cleanup() {
  if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$server_pid" 2>/dev/null; then
      kill -9 "$server_pid" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT INT TERM

render_demo_page "$scenario" "$page_html" "$state_key"

(
  cd "$server_root"
  python3 -m http.server "$port"
) > "$server_log" 2>&1 &
server_pid=$!

page_url="http://127.0.0.1:$port/index.html"
wait_for_http "$page_url" 15
safari_open_url "$page_url"
wait_for_js_truthy "document.readyState === 'complete'" 10

initial_modal_seen=0
initial_popover_seen=0
initial_permission_seen=0
initial_stale_seen=0

if wait_for_js_truthy "document.body.dataset.modalOpen === 'yes'" 2; then
  initial_modal_seen=1
fi
if wait_for_js_truthy "document.body.dataset.popoverOpen === 'yes'" 2; then
  initial_popover_seen=1
fi
if wait_for_js_truthy "document.body.dataset.permissionPending === 'yes'" 2; then
  initial_permission_seen=1
fi
if wait_for_js_truthy "document.body.dataset.stalePending === 'yes'" 2; then
  initial_stale_seen=1
fi

modal_cleared=0
popover_cleared=0
permission_resolved=0
stale_recovered=0
resume_complete=0

if [ "$expect_modal" -eq 0 ]; then
  modal_cleared=1
else
  safari_do_javascript "document.getElementById('dismiss-modal').click(); 'ok';" >/dev/null
  if wait_for_js_truthy "document.body.dataset.modalOpen === 'no'" 6; then
    modal_cleared=1
  fi
fi

if [ "$expect_popover" -eq 0 ]; then
  popover_cleared=1
else
  safari_do_javascript "document.getElementById('dismiss-popover').click(); 'ok';" >/dev/null
  if wait_for_js_truthy "document.body.dataset.popoverOpen === 'no'" 6; then
    popover_cleared=1
  fi
fi

if [ "$expect_permission" -eq 0 ]; then
  permission_resolved=1
else
  safari_do_javascript "window.demoResolvePermission();" >/dev/null
  if wait_for_js_truthy "document.body.dataset.permissionPending === 'no'" 6; then
    permission_resolved=1
  fi
fi

if [ "$expect_stale" -eq 0 ]; then
  stale_recovered=1
else
  safari_do_javascript "window.demoRecoverStale();" >/dev/null
  if wait_for_js_truthy "document.body.dataset.stalePending === 'no' && document.body.dataset.reloaded === 'yes'" 8; then
    stale_recovered=1
  fi
fi

if [ "$modal_cleared" -eq 1 ] && [ "$popover_cleared" -eq 1 ] && [ "$permission_resolved" -eq 1 ] && [ "$stale_recovered" -eq 1 ]; then
  safari_do_javascript "document.getElementById('resume-action').click(); 'ok';" >/dev/null
  if wait_for_js_truthy "document.body.dataset.recovered === 'yes'" 6; then
    resume_complete=1
  fi
fi

status=$(score_result "$modal_cleared" "$popover_cleared" "$permission_resolved" "$stale_recovered" "$resume_complete")

printf '{"label":%s,"status":%s,"scenario":%s,"initial_modal_seen":%s,"initial_popover_seen":%s,"initial_permission_seen":%s,"initial_stale_seen":%s,"modal_cleared":%s,"popover_cleared":%s,"permission_resolved":%s,"stale_recovered":%s,"resume_complete":%s}\n' \
  "$(json_escape "$label")" \
  "$(json_escape "$status")" \
  "$(json_escape "$scenario")" \
  "$initial_modal_seen" \
  "$initial_popover_seen" \
  "$initial_permission_seen" \
  "$initial_stale_seen" \
  "$modal_cleared" \
  "$popover_cleared" \
  "$permission_resolved" \
  "$stale_recovered" \
  "$resume_complete" > "$json_file"

{
  printf '# GUI State Recovery Probe %s\n\n' "$label"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Initial modal seen: %s\n' "$initial_modal_seen"
  printf -- '- Initial popover seen: %s\n' "$initial_popover_seen"
  printf -- '- Initial permission seen: %s\n' "$initial_permission_seen"
  printf -- '- Initial stale seen: %s\n' "$initial_stale_seen"
  printf -- '- Modal cleared: %s\n' "$modal_cleared"
  printf -- '- Popover cleared: %s\n' "$popover_cleared"
  printf -- '- Permission resolved: %s\n' "$permission_resolved"
  printf -- '- Stale recovered: %s\n' "$stale_recovered"
  printf -- '- Resume complete: %s\n' "$resume_complete"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
