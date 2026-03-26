#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="gui-login-upload-download-probe"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for GUI login/upload/download probe." >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required for Safari automation." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for GUI login/upload/download probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: gui-login-upload-download-probe.sh [--label NAME] [--scenario NAME]

Runs a deterministic Safari workflow:
1. load a local login-gated upload page
2. authenticate
3. survive a reload with session state intact
4. upload a file through the browser file chooser
5. download a generated receipt and verify its contents
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
  receipt_name=$3
  valid_email=$4
  valid_password=$5
  case "$scenario" in
    vendor-batch)
      headline="Vendor batch intake"
      helper_copy="Authenticate, attach the partner batch, then download the intake receipt."
      ;;
    csv-import)
      headline="CSV reconciliation import"
      helper_copy="Authenticate, attach the reconciliation CSV, then download the import receipt."
      ;;
    audit-bundle)
      headline="Release audit bundle"
      helper_copy="Authenticate, attach the audit bundle, then download the release receipt."
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  receipt_name_quoted=$(printf '%s' "$receipt_name" | sed "s/'/'\\\\''/g")
  valid_email_quoted=$(printf '%s' "$valid_email" | sed "s/'/'\\\\''/g")
  valid_password_quoted=$(printf '%s' "$valid_password" | sed "s/'/'\\\\''/g")
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
      radial-gradient(circle at top left, #dbeafe 0%, rgba(219,234,254,0) 38%),
      linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  main {
    max-width: 760px;
    margin: 0 auto;
    padding: 44px 28px 72px;
  }
  .card {
    background: rgba(255, 255, 255, 0.9);
    border: 1px solid rgba(148, 163, 184, 0.25);
    border-radius: 26px;
    box-shadow: 0 28px 70px rgba(15, 23, 42, 0.12);
    padding: 28px;
  }
  h1 {
    margin: 0 0 10px;
    font-size: 38px;
    line-height: 1.05;
  }
  p.lede {
    margin: 0 0 26px;
    font-size: 18px;
    line-height: 1.5;
    color: #334155;
  }
  .stack {
    display: grid;
    gap: 18px;
  }
  label {
    display: grid;
    gap: 8px;
    font-weight: 600;
  }
  input[type="email"],
  input[type="password"] {
    width: fit-content;
    min-width: 320px;
    max-width: 100%;
    padding: 12px 14px;
    border-radius: 14px;
    border: 1px solid #cbd5e1;
    font: inherit;
    background: white;
  }
  input[type="file"] {
    font: inherit;
  }
  button {
    width: fit-content;
    border: 0;
    border-radius: 999px;
    padding: 12px 18px;
    font: inherit;
    font-weight: 700;
    cursor: pointer;
  }
  #login-button {
    background: #0f766e;
    color: white;
  }
  #download-button {
    background: #0f172a;
    color: white;
  }
  .pill {
    width: fit-content;
    border-radius: 999px;
    padding: 8px 12px;
    background: #dcfce7;
    color: #166534;
    font-weight: 700;
  }
  .muted {
    color: #475569;
    font-size: 15px;
  }
  .hidden {
    display: none !important;
  }
  .dialog-shell {
    border: 1px solid rgba(15, 23, 42, 0.1);
    background: #f8fafc;
    border-radius: 18px;
    padding: 18px;
  }
</style>
</head>
<body>
  <main>
    <section class="card">
      <h1>${headline}</h1>
      <p class="lede">${helper_copy}</p>
      <div id="login-panel" class="stack">
        <label>Email
          <input id="email" type="email" autocomplete="username">
        </label>
        <label>Password
          <input id="password" type="password" autocomplete="current-password">
        </label>
        <button id="login-button" type="button">Log In</button>
        <div id="login-status" class="muted">Waiting for credentials.</div>
      </div>
      <div id="app-panel" class="stack hidden">
        <div id="session-badge" class="pill">Authenticated</div>
        <div class="muted">Session persists across reload for this receipt workspace.</div>
        <label>Attach source file
          <input id="upload-input" type="file">
        </label>
        <div id="upload-status" class="muted">No file attached yet.</div>
        <button id="download-button" type="button" disabled>Download receipt</button>
        <div id="download-status" class="muted">No receipt downloaded yet.</div>
        <div id="download-modal" class="dialog-shell hidden">
          <label>Receipt filename
            <input id="download-name" type="text">
          </label>
          <div class="stack">
            <button id="confirm-download" type="button">Confirm download</button>
            <button id="cancel-download" type="button">Cancel</button>
          </div>
        </div>
      </div>
    </section>
  </main>
<script>
(() => {
  const stateKey = 'gui-login-demo:${scenario}:${receipt_name_quoted}';
  const validEmail = '${valid_email_quoted}';
  const validPassword = '${valid_password_quoted}';
  const receiptName = '${receipt_name_quoted}';
  const loginPanel = document.getElementById('login-panel');
  const appPanel = document.getElementById('app-panel');
  const emailInput = document.getElementById('email');
  const passwordInput = document.getElementById('password');
  const loginStatus = document.getElementById('login-status');
  const sessionBadge = document.getElementById('session-badge');
  const uploadInput = document.getElementById('upload-input');
  const uploadStatus = document.getElementById('upload-status');
  const downloadButton = document.getElementById('download-button');
  const downloadStatus = document.getElementById('download-status');
  const downloadModal = document.getElementById('download-modal');
  const downloadNameInput = document.getElementById('download-name');
  const confirmDownloadButton = document.getElementById('confirm-download');
  const cancelDownloadButton = document.getElementById('cancel-download');

  const state = {
    session: null,
    upload: null
  };

  function persistSession(session) {
    localStorage.setItem(stateKey, JSON.stringify(session));
  }

  function restoreSession() {
    try {
      const raw = localStorage.getItem(stateKey);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (!parsed || !parsed.email) return null;
      return parsed;
    } catch (_err) {
      return null;
    }
  }

  function applyView() {
    const authenticated = !!state.session;
    document.body.dataset.authenticated = authenticated ? 'yes' : 'no';
    loginPanel.classList.toggle('hidden', authenticated);
    appPanel.classList.toggle('hidden', !authenticated);
    if (authenticated) {
      sessionBadge.textContent = 'Authenticated as ' + state.session.email;
    }
    if (state.upload) {
      uploadStatus.textContent = 'Attached ' + state.upload.name + ' (' + state.upload.bytes + ' bytes).';
      downloadButton.disabled = false;
    } else {
      uploadStatus.textContent = 'No file attached yet.';
      downloadButton.disabled = true;
    }
  }

  function setDownloadModal(open) {
    downloadModal.classList.toggle('hidden', !open);
    document.body.dataset.downloadModal = open ? 'open' : 'closed';
  }

  document.getElementById('login-button').addEventListener('click', () => {
    const email = emailInput.value.trim();
    const password = passwordInput.value;
    if (email === validEmail && password === validPassword) {
      state.session = { email };
      persistSession(state.session);
      loginStatus.textContent = 'Authenticated.';
      applyView();
      return;
    }
    loginStatus.textContent = 'Login failed.';
  });

  uploadInput.addEventListener('change', async () => {
    const file = uploadInput.files && uploadInput.files[0];
    if (!file) {
      state.upload = null;
      applyView();
      return;
    }
    const text = await file.text();
    const lines = String(text || '').replace(/\\r/g, '').split('\\n').filter(Boolean);
    state.upload = {
      name: file.name,
      bytes: file.size,
      rows: lines.length,
      firstLine: lines.length ? lines[0] : ''
    };
    downloadStatus.textContent = 'Receipt pending.';
    applyView();
  });

  window.demoInjectUpload = (fileName, fileText) => {
    const text = String(fileText || '');
    const lines = text.replace(/\\r/g, '').split('\\n').filter(Boolean);
    state.upload = {
      name: String(fileName || 'attachment.txt'),
      bytes: text.length,
      rows: lines.length,
      firstLine: lines.length ? lines[0] : ''
    };
    downloadStatus.textContent = 'Receipt pending.';
    applyView();
    return 'ok';
  };

  downloadButton.addEventListener('click', () => {
    if (!state.session || !state.upload) return;
    downloadNameInput.value = receiptName;
    setDownloadModal(true);
  });

  cancelDownloadButton.addEventListener('click', () => {
    setDownloadModal(false);
    downloadStatus.textContent = 'Download cancelled.';
  });

  confirmDownloadButton.addEventListener('click', () => {
    if (!state.session || !state.upload) return;
    const requestedName = String(downloadNameInput.value || '').trim();
    if (!requestedName) {
      downloadStatus.textContent = 'Download cancelled.';
      setDownloadModal(false);
      return;
    }
    const receiptText = [
      'scenario=${scenario}',
      'user=' + state.session.email,
      'upload=' + state.upload.name,
      'bytes=' + state.upload.bytes,
      'rows=' + state.upload.rows,
      'first_line=' + state.upload.firstLine
    ].join('\\n') + '\\n';
    const blob = new Blob([receiptText], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = requestedName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1200);
    downloadStatus.textContent = 'Downloaded ' + requestedName + '.';
    setDownloadModal(false);
  });

  state.session = restoreSession();
  setDownloadModal(false);
  applyView();
})();
</script>
</body>
</html>
EOF_HTML
}

score_result() {
  login_complete=$1
  session_persisted=$2
  dialog_handled=$3
  upload_processed=$4
  download_triggered=$5
  download_exists=$6
  download_content_match=$7
  if [ "$login_complete" -eq 1 ] \
    && [ "$session_persisted" -eq 1 ] \
    && [ "$dialog_handled" -eq 1 ] \
    && [ "$upload_processed" -eq 1 ] \
    && [ "$download_triggered" -eq 1 ] \
    && [ "$download_exists" -eq 1 ] \
    && [ "$download_content_match" -eq 1 ]; then
    printf '%s' "pass"
  else
    printf '%s' "fail"
  fi
}

label=$DEFAULT_LABEL
scenario="vendor-batch"
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
  vendor-batch)
    valid_email="ops-vendor@example.com"
    valid_password="vendor-batch-pass"
    upload_filename="vendor-batch.txt"
    upload_contents="partner=orion\nentries=18\npriority=high\n"
    ;;
  csv-import)
    valid_email="ops-import@example.com"
    valid_password="csv-import-pass"
    upload_filename="reconciliation.csv"
    upload_contents="invoice,amount\nA-100,42\nA-101,51\n"
    ;;
  audit-bundle)
    valid_email="ops-audit@example.com"
    valid_password="audit-bundle-pass"
    upload_filename="release-audit.log"
    upload_contents="cutover=blocked\nreason=drain-held\nminutes=41\n"
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
download_name="${label}-${scenario}-receipt.txt"
download_dir="$HOME/Downloads"
download_path="$download_dir/$download_name"
download_copy="$raw_dir/$download_name"
page_html="$raw_dir/$scenario.html"
upload_source_path="$raw_dir/$upload_filename"
server_root="$raw_dir/site"
mkdir -p "$server_root"
page_html="$server_root/index.html"
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

printf '%b' "$upload_contents" > "$upload_source_path"
render_demo_page "$scenario" "$page_html" "$download_name" "$valid_email" "$valid_password"
rm -f "$download_path" "$download_copy"

(
  cd "$server_root"
  python3 -m http.server "$port"
) > "$server_log" 2>&1 &
server_pid=$!

page_url="http://127.0.0.1:$port/index.html"
wait_for_http "$page_url" 15
safari_open_url "$page_url"
wait_for_js_truthy "document.readyState === 'complete'" 10

safari_do_javascript "document.getElementById('email').value = $(json_escape "$valid_email"); document.getElementById('password').value = $(json_escape "$valid_password"); document.getElementById('login-button').click(); 'ok';" >/dev/null
login_complete=0
if wait_for_js_truthy "document.body.dataset.authenticated === 'yes'" 10; then
  login_complete=1
fi

session_persisted=0
if [ "$login_complete" -eq 1 ]; then
  safari_do_javascript "location.reload(); 'ok';" >/dev/null
  if wait_for_js_truthy "document.body.dataset.authenticated === 'yes' && document.getElementById('session-badge').textContent.indexOf($(json_escape "$valid_email")) >= 0" 10; then
    session_persisted=1
  fi
fi

dialog_handled=0
upload_processed=0
if [ "$session_persisted" -eq 1 ]; then
  upload_contents_js=$(json_escape "$(cat "$upload_source_path")")
  safari_do_javascript "window.demoInjectUpload($(json_escape "$upload_filename"), $upload_contents_js);" >/dev/null
  if wait_for_js_truthy "document.getElementById('upload-status').textContent.indexOf($(json_escape "$upload_filename")) >= 0" 8; then
    upload_processed=1
  fi
fi

download_triggered=0
download_exists=0
download_content_match=0
if [ "$upload_processed" -eq 1 ]; then
  safari_do_javascript "document.getElementById('download-button').click(); 'ok';" >/dev/null
  if wait_for_js_truthy "document.body.dataset.downloadModal === 'open'" 5; then
    safari_do_javascript "document.getElementById('download-name').value = $(json_escape "$download_name"); document.getElementById('confirm-download').click(); 'ok';" >/dev/null
    dialog_handled=1
  fi
  if wait_for_js_truthy "document.getElementById('download-status').textContent.indexOf($(json_escape "$download_name")) >= 0" 10; then
    download_triggered=1
  fi
  elapsed=0
  while [ "$elapsed" -lt 20 ]; do
    if [ -f "$download_path" ]; then
      download_exists=1
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ "$download_exists" -eq 1 ]; then
    cp "$download_path" "$download_copy"
    if grep -Fq "scenario=$scenario" "$download_path" \
      && grep -Fq "user=$valid_email" "$download_path" \
      && grep -Fq "upload=$upload_filename" "$download_path"; then
      download_content_match=1
    fi
  fi
fi

status=$(score_result "$login_complete" "$session_persisted" "$dialog_handled" "$upload_processed" "$download_triggered" "$download_exists" "$download_content_match")

printf '{"label":%s,"status":%s,"scenario":%s,"login_complete":%s,"session_persisted":%s,"dialog_handled":%s,"upload_processed":%s,"download_triggered":%s,"download_exists":%s,"download_content_match":%s,"download_path":%s,"download_copy":%s}\n' \
  "$(json_escape "$label")" \
  "$(json_escape "$status")" \
  "$(json_escape "$scenario")" \
  "$login_complete" \
  "$session_persisted" \
  "$dialog_handled" \
  "$upload_processed" \
  "$download_triggered" \
  "$download_exists" \
  "$download_content_match" \
  "$(json_escape "$download_path")" \
  "$(json_escape "$download_copy")" > "$json_file"

{
  printf '# GUI Login Upload Download Probe %s\n\n' "$label"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Login complete: %s\n' "$login_complete"
  printf -- '- Session persisted: %s\n' "$session_persisted"
  printf -- '- Dialog handled: %s\n' "$dialog_handled"
  printf -- '- Upload processed: %s\n' "$upload_processed"
  printf -- '- Download triggered: %s\n' "$download_triggered"
  printf -- '- Download exists: %s\n' "$download_exists"
  printf -- '- Download content match: %s\n' "$download_content_match"
  printf -- '- Download path: %s\n' "$download_path"
  printf -- '- Download copy: %s\n' "$download_copy"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
