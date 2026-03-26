#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="browser-image-run-investigation-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for browser/image/run investigation probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for browser/image/run investigation probe." >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required for Safari browser capture." >&2
  exit 1
fi
if ! command -v screencapture >/dev/null 2>&1; then
  echo "screencapture is required for Safari browser capture." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: browser-image-run-investigation-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Builds a bounded assistant workspace with one runtime helper, renders a local page
in Safari, uploads the screenshot, injects a browser snapshot, and checks whether
Artificer combines browser evidence, image evidence, and runtime evidence into one
concrete root-cause/next-action answer.
EOF_USAGE
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

json_escape() {
  printf '%s' "$1" | jq -Rs '.'
}

post_api_json() {
  body=$1
  len=$(printf '%s' "$body" | wc -c | tr -d ' ')
  REQUEST_METHOD=POST CONTENT_LENGTH="$len" sh "$API_SCRIPT" <<EOF_BODY | tr -d '\r' | awk 'seen{print} /^$/{seen=1}'
$body
EOF_BODY
}

post_api_json_with_timeout() {
  body=$1
  timeout_sec=$2
  python3 - "$API_SCRIPT" "$timeout_sec" "$body" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
timeout_sec = float(sys.argv[2])
body = sys.argv[3]
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))

try:
    proc = subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout_sec,
        check=False,
    )
    raw = proc.stdout.decode().replace("\r", "")
    parts = raw.split("\n\n", 1)
    payload = parts[1] if len(parts) > 1 else raw
    payload = payload.strip()
    if payload:
        print(payload)
    else:
        print('{"__timed_out":false}')
except subprocess.TimeoutExpired:
    print('{"__timed_out":true}')
PY
}

delete_workspace_best_effort() {
  workspace_id=$1
  [ -n "$workspace_id" ] || return 0
  workspace_id_uri=$(uri "$workspace_id")
  python3 - "$API_SCRIPT" "$workspace_id_uri" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
workspace_id_uri = sys.argv[2]
body = f"action=delete_workspace&workspace_id={workspace_id_uri}"
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))
try:
    subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=12,
        check=False,
    )
except Exception:
    pass
PY
}

file_uri_from_path() {
  python3 - "$1" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

write_runtime_workspace() {
  scenario=$1
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/config" "$workspace_dir/webapp/src"
  case "$scenario" in
    preview-timeout)
      cat > "$workspace_dir/webapp/src/preview-client.js" <<'EOF_JS'
export async function loadPreview(fetchJson) {
  return fetchJson('/v2/preview', {
    timeoutMs: 5000,
  });
}
EOF_JS
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=client_timeout_too_low'
printf '%s\n' 'runtime_file=webapp/src/preview-client.js'
printf '%s\n' 'runtime_timeout_ms=5000'
printf '%s\n' 'runtime_backend_p95_ms=12000'
printf '%s\n' 'runtime_expected_timeout_ms=15000'
printf '%s\n' 'runtime_endpoint=/v2/preview'
exit 1
EOF_SH
      ;;
    upload-flag-disabled)
      cat > "$workspace_dir/config/runtime.env" <<'EOF_CFG'
uploads_rollout=off
UPLOAD_BUCKET=tenant-artifacts
EOF_CFG
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=uploads_rollout_disabled'
printf '%s\n' 'runtime_file=config/runtime.env'
printf '%s\n' 'runtime_flag=uploads_rollout=off'
printf '%s\n' 'runtime_route=/v2/uploads/complete'
printf '%s\n' 'runtime_worker=ready'
exit 1
EOF_SH
      ;;
    session-cache-fallback)
      cat > "$workspace_dir/config/runtime.env" <<'EOF_CFG'
SESSION_CACHE_URL=
LOGIN_BOUNDARY=active
EOF_CFG
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=session_cache_fallback'
printf '%s\n' 'runtime_file=config/runtime.env'
printf '%s\n' 'runtime_session_cache_url=missing'
printf '%s\n' 'runtime_miss_rate=68%'
printf '%s\n' 'runtime_backend=redis_fallback_to_db'
exit 1
EOF_SH
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  chmod +x "$workspace_dir/bin/runtime-check.sh"
  cat > "$workspace_dir/README.md" <<EOF_README
# Browser Image Run Investigation Demo

Scenario: $scenario
Use ./bin/runtime-check.sh for bounded runtime evidence. Do not edit files in this probe.
EOF_README
}

render_browser_page() {
  scenario=$1
  html_path=$2
  case "$scenario" in
    preview-timeout)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Preview Feed Stalled</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #fff7ed 0%, #ffedd5 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  .page {
    padding: 34px;
    display: grid;
    gap: 22px;
    max-width: 980px;
  }
  .hero h1 {
    margin: 0 0 10px;
    font-size: 42px;
    line-height: 1.04;
  }
  .hero p {
    margin: 0;
    font-size: 18px;
    color: #7c2d12;
    max-width: 720px;
  }
  .panel {
    width: fit-content;
    min-width: 520px;
    background: rgba(255,255,255,0.92);
    border: 2px solid #fb923c;
    border-radius: 26px;
    padding: 24px 24px 22px;
    box-shadow: 0 24px 70px rgba(124, 45, 18, 0.15);
  }
  .pill {
    display: inline-flex;
    width: fit-content;
    padding: 10px 14px;
    border-radius: 999px;
    background: #ea580c;
    color: white;
    font-weight: 800;
    letter-spacing: 0.01em;
  }
  .panel h2 {
    margin: 18px 0 10px;
    font-size: 32px;
  }
  .panel p {
    margin: 0;
    font-size: 18px;
    color: #7c2d12;
    max-width: 640px;
  }
  .actions {
    margin-top: 18px;
    display: flex;
    gap: 12px;
  }
  .btn {
    border: 0;
    border-radius: 999px;
    padding: 13px 18px;
    font-size: 16px;
    font-weight: 800;
    width: fit-content;
  }
  .primary { background: #0f172a; color: white; }
  .secondary { background: #fed7aa; color: #9a3412; }
  .stats {
    display: flex;
    gap: 14px;
    flex-wrap: wrap;
  }
  .stat {
    width: fit-content;
    min-width: 170px;
    background: rgba(255,255,255,0.7);
    border-radius: 18px;
    padding: 14px 16px;
  }
  .stat .value { font-size: 28px; font-weight: 800; color: #c2410c; }
</style>
</head>
<body>
  <main class="page">
    <section class="hero">
      <h1>Release preview control room</h1>
      <p>The operator is checking whether the canary summary can refresh before widening the partner rollout.</p>
    </section>
    <section class="panel" aria-label="Preview status panel">
      <div class="pill">Preview feed stalled</div>
      <h2>Preview refresh timed out after 5s</h2>
      <p>The current release summary did not load, so the rollout preview is still blocked on stale data.</p>
      <div class="actions">
        <button class="btn primary">Retry preview</button>
        <button class="btn secondary">Hold rollout</button>
      </div>
    </section>
    <section class="stats" aria-label="Preview metrics">
      <article class="stat"><div class="value">12.0s</div><div>Backend p95</div></article>
      <article class="stat"><div class="value">5.0s</div><div>Client timeout</div></article>
      <article class="stat"><div class="value">1</div><div>Blocked panel</div></article>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    upload-flag-disabled)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Uploads Paused</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  .page {
    padding: 34px;
    display: grid;
    gap: 22px;
    max-width: 980px;
  }
  .hero h1 { margin: 0 0 10px; font-size: 42px; line-height: 1.04; }
  .hero p { margin: 0; font-size: 18px; color: #334155; max-width: 720px; }
  .drawer {
    width: fit-content;
    min-width: 560px;
    background: white;
    border-radius: 26px;
    border: 2px solid #93c5fd;
    padding: 24px;
    box-shadow: 0 24px 70px rgba(37, 99, 235, 0.12);
  }
  .banner {
    display: inline-flex;
    width: fit-content;
    padding: 10px 14px;
    border-radius: 999px;
    background: #dbeafe;
    color: #1d4ed8;
    font-weight: 800;
  }
  .drawer h2 { margin: 18px 0 10px; font-size: 30px; }
  .drawer p { margin: 0; font-size: 18px; color: #334155; max-width: 640px; }
  .field {
    margin-top: 18px;
    width: fit-content;
    min-width: 420px;
    background: #f8fafc;
    border: 1px solid #cbd5e1;
    border-radius: 18px;
    padding: 14px 16px;
    font-size: 16px;
  }
  .actions {
    margin-top: 18px;
    display: flex;
    gap: 12px;
  }
  .btn {
    border: 0;
    border-radius: 999px;
    padding: 13px 18px;
    font-size: 16px;
    font-weight: 800;
    width: fit-content;
  }
  .ghost { background: #e2e8f0; color: #334155; }
  .disabled {
    background: #cbd5e1;
    color: #64748b;
  }
</style>
</head>
<body>
  <main class="page">
    <section class="hero">
      <h1>Vendor upload control</h1>
      <p>The operator has already selected the file, but the final publish step is still blocked.</p>
    </section>
    <section class="drawer" aria-label="Upload drawer">
      <div class="banner">Uploads paused for this workspace</div>
      <h2>Vendor CSV ready</h2>
      <p>The upload completed locally, but publication is still gated until the workspace rollout is enabled.</p>
      <div class="field">File: vendor-rates-q2.csv</div>
      <div class="actions">
        <button class="btn ghost">Review upload</button>
        <button class="btn disabled" aria-disabled="true">Publish upload</button>
      </div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    session-cache-fallback)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Session Cache Fallback</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  .page {
    padding: 34px;
    display: grid;
    gap: 22px;
    max-width: 980px;
  }
  .hero h1 { margin: 0 0 10px; font-size: 42px; line-height: 1.04; }
  .hero p { margin: 0; font-size: 18px; color: #334155; max-width: 720px; }
  .panel {
    width: fit-content;
    min-width: 620px;
    background: white;
    border-radius: 26px;
    border: 2px solid #94a3b8;
    padding: 24px;
    box-shadow: 0 24px 70px rgba(15, 23, 42, 0.10);
  }
  .banner {
    display: inline-flex;
    width: fit-content;
    padding: 10px 14px;
    border-radius: 999px;
    background: #0f172a;
    color: white;
    font-weight: 800;
  }
  .panel h2 { margin: 18px 0 10px; font-size: 30px; }
  .panel p { margin: 0; font-size: 18px; color: #334155; max-width: 640px; }
  .metrics {
    margin-top: 18px;
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
  }
  .chip {
    display: inline-flex;
    width: fit-content;
    padding: 12px 14px;
    border-radius: 999px;
    background: #e2e8f0;
    color: #0f172a;
    font-weight: 800;
  }
  .btn {
    margin-top: 18px;
    border: 0;
    border-radius: 999px;
    padding: 13px 18px;
    font-size: 16px;
    font-weight: 800;
    width: fit-content;
    background: #1d4ed8;
    color: white;
  }
</style>
</head>
<body>
  <main class="page">
    <section class="hero">
      <h1>Login boundary watch</h1>
      <p>The operator is checking whether login traffic can widen after the cache recovery sequence.</p>
    </section>
    <section class="panel" aria-label="Session cache panel">
      <div class="banner">Session cache fallback active</div>
      <h2>Login boundary degraded</h2>
      <p>Logins are still succeeding, but the boundary is leaning on the database fallback path instead of the session cache.</p>
      <div class="metrics">
        <div class="chip">Login p95 4.8s</div>
        <div class="chip">Miss rate 68%</div>
        <div class="chip">DB fallback path active</div>
      </div>
      <button class="btn">Hold wider login traffic</button>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    *)
      echo "Unknown --scenario value: $scenario" >&2
      exit 1
      ;;
  esac
}

capture_safari_screenshot() {
  page_path=$1
  screenshot_path=$2
  page_uri=$(file_uri_from_path "$page_path")
  bounds_csv=$(osascript <<EOF_APPLESCRIPT
set targetUrl to "$page_uri"
tell application "Safari"
  activate
  make new document with properties {URL:targetUrl}
  set bounds of front window to {80, 60, 1180, 980}
end tell
repeat 40 times
  delay 0.25
  tell application "Safari"
    try
      set readyState to do JavaScript "document.readyState" in current tab of front window
      set titleText to do JavaScript "document.title || ''" in current tab of front window
    on error
      set readyState to ""
      set titleText to ""
    end try
  end tell
  if readyState is "complete" and titleText is not "" then
    exit repeat
  end if
end repeat
tell application "Safari"
  try
    do JavaScript "window.scrollTo(0,0); document.body.style.zoom='100%';" in current tab of front window
  end try
  set b to bounds of front window
  return (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text)
end tell
EOF_APPLESCRIPT
)
  x1=$(printf '%s' "$bounds_csv" | awk -F',' '{print $1}')
  y1=$(printf '%s' "$bounds_csv" | awk -F',' '{print $2}')
  x2=$(printf '%s' "$bounds_csv" | awk -F',' '{print $3}')
  y2=$(printf '%s' "$bounds_csv" | awk -F',' '{print $4}')
  width=$((x2 - x1))
  height=$((y2 - y1))
  chrome_side=14
  chrome_top=92
  chrome_bottom=18
  shot_x=$((x1 + chrome_side))
  shot_y=$((y1 + chrome_top))
  shot_w=$((width - (chrome_side * 2)))
  shot_h=$((height - chrome_top - chrome_bottom))
  screencapture -x -R"$shot_x,$shot_y,$shot_w,$shot_h" "$screenshot_path"
  osascript <<'EOF_APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Safari"
  try
    close front window
  end try
end tell
EOF_APPLESCRIPT
}

capture_safari_layout_snapshot() {
  page_path=$1
  snapshot_path=$2
  page_uri=$(file_uri_from_path "$page_path")
  osascript <<EOF_APPLESCRIPT >/dev/null
set targetUrl to "$page_uri"
tell application "Safari"
  activate
  make new document with properties {URL:targetUrl}
  set bounds of front window to {80, 60, 1180, 980}
end tell
repeat 40 times
  delay 0.25
  tell application "Safari"
    try
      set readyState to do JavaScript "document.readyState" in current tab of front window
      set titleText to do JavaScript "document.title || ''" in current tab of front window
    on error
      set readyState to ""
      set titleText to ""
    end try
  end tell
  if readyState is "complete" and titleText is not "" then
    exit repeat
  end if
end repeat
EOF_APPLESCRIPT
  osascript <<'EOF_APPLESCRIPT' > "$snapshot_path"
tell application "Safari"
  set snapshotJson to do JavaScript "(function () {
    const clean = (value, limit) => {
      const text = String(value || '').replace(/\\s+/g, ' ').trim();
      return text.slice(0, limit);
    };
    const inView = (rect) => rect.width >= 80 && rect.height >= 24 &&
      rect.bottom >= 0 && rect.right >= 0 &&
      rect.top <= window.innerHeight && rect.left <= window.innerWidth;
    const items = [];
    for (const el of document.querySelectorAll('body *')) {
      const rect = el.getBoundingClientRect();
      if (!inView(rect)) continue;
      const text = clean(el.innerText || el.textContent || el.getAttribute('aria-label') || '', 120);
      if (!text) continue;
      const style = window.getComputedStyle(el);
      items.push({
        tag: (el.tagName || '').toLowerCase(),
        role: clean(el.getAttribute('role') || '', 40),
        text,
        left: Math.round(rect.left),
        top: Math.round(rect.top),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        position: clean(style.position || '', 20),
        display: clean(style.display || '', 20)
      });
      if (items.length >= 18) break;
    }
    return JSON.stringify({
      viewport: { width: window.innerWidth, height: window.innerHeight },
      title: document.title || '',
      elements: items
    });
  })();" in current tab of front window
  return snapshotJson
end tell
EOF_APPLESCRIPT
  osascript <<'EOF_APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Safari"
  try
    close front window
  end try
end tell
EOF_APPLESCRIPT
}

derive_layout_observations() {
  snapshot_path=$1
  python3 - "$snapshot_path" <<'PY'
import json
import re
import sys

path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    print("- geometry snapshot unavailable")
    raise SystemExit(0)

viewport = data.get("viewport") or {}
vw = int(viewport.get("width") or 0)
vh = int(viewport.get("height") or 0)
elements = data.get("elements") or []

def clean(text, limit=72):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text[:limit]

notes = []
if vw and vh:
    notes.append(f"- viewport: {vw}x{vh}")

for el in elements[:8]:
    text = clean(el.get("text"), 80)
    tag = clean(el.get("tag"), 20)
    left = int(el.get("left") or 0)
    top = int(el.get("top") or 0)
    width = int(el.get("width") or 0)
    height = int(el.get("height") or 0)
    notes.append(f'- element: {tag} "{text}" at ({left},{top}) size {width}x{height}')

print("\n".join(notes[:8]))
PY
}

text_has_any() {
  haystack=$1
  shift
  for needle in "$@"; do
    case "$haystack" in
      *"$needle"*)
        return 0
        ;;
    esac
  done
  return 1
}

score_browser_image_answer() {
  scenario=$1
  answer_lower=$2
  browser_ref=0
  image_ref=0
  runtime_ref=0
  root_cause_ref=0
  next_action_ref=0
  case "$scenario" in
    preview-timeout)
      text_has_any "$answer_lower" "preview feed stalled" "retry preview" "timed out after 5s" && browser_ref=1
      text_has_any "$answer_lower" "preview refresh timed out after 5s" "timed out after 5s" "preview feed stalled" && image_ref=1
      text_has_any "$answer_lower" "runtime-check.sh" "5000" "12000" "15000" "preview-client.js" && runtime_ref=1
      text_has_any "$answer_lower" "timeout" "5000" "12000" && root_cause_ref=1
      text_has_any "$answer_lower" "15000" "preview-client.js" "retrying the preview" "update" && next_action_ref=1
      ;;
    upload-flag-disabled)
      text_has_any "$answer_lower" "uploads paused" "publish upload" "disabled" && browser_ref=1
      text_has_any "$answer_lower" "uploads paused for this workspace" "publish upload" && image_ref=1
      text_has_any "$answer_lower" "runtime-check.sh" "uploads_rollout=off" "config/runtime.env" && runtime_ref=1
      text_has_any "$answer_lower" "flag" "disabled" "uploads_rollout" "off" && root_cause_ref=1
      text_has_any "$answer_lower" "uploads_rollout=on" "config/runtime.env" "bounded upload verification" && next_action_ref=1
      ;;
    session-cache-fallback)
      text_has_any "$answer_lower" "session cache fallback active" "login p95 4.8s" "miss rate 68%" && browser_ref=1
      text_has_any "$answer_lower" "session cache fallback active" "login p95 4.8s" "miss rate 68%" && image_ref=1
      text_has_any "$answer_lower" "runtime-check.sh" "session_cache_url" "68%" "config/runtime.env" && runtime_ref=1
      text_has_any "$answer_lower" "session cache" "redis" "database" "fallback" && root_cause_ref=1
      text_has_any "$answer_lower" "session_cache_url" "config/runtime.env" "login boundary health check" "restore" && next_action_ref=1
      ;;
  esac
  printf '%s %s %s %s %s\n' "$browser_ref" "$image_ref" "$runtime_ref" "$root_cause_ref" "$next_action_ref"
}

label=$DEFAULT_LABEL
scenario="preview-timeout"
prompt_override=""
prompt_file=""
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
    --prompt)
      prompt_override=$2
      shift 2
      ;;
    --prompt-file)
      prompt_file=$2
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
  preview-timeout|upload-flag-disabled|session-cache-fallback)
    ;;
  *)
    echo "Unknown --scenario value: $scenario" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"
page_html="$raw_dir/$scenario.html"
screenshot_png="$raw_dir/$scenario.png"
layout_snapshot_json="$raw_dir/$scenario-layout.json"
layout_observations_txt="$raw_dir/$scenario-layout-observations.txt"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("llava:7b")) then "llava:7b"
  else ""
  end
')
[ -n "$model" ] || { echo "llava:7b is required for browser/image/run investigation probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

write_runtime_workspace "$scenario" "$tmp_ws"
render_browser_page "$scenario" "$page_html"
capture_safari_screenshot "$page_html" "$screenshot_png"
capture_safari_layout_snapshot "$page_html" "$layout_snapshot_json"
derive_layout_observations "$layout_snapshot_json" > "$layout_observations_txt"

screenshot_exists=0
if [ -s "$screenshot_png" ]; then
  screenshot_exists=1
fi

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

attachment_uploaded=0
attachment_id=""
if [ "$screenshot_exists" -eq 1 ]; then
  screenshot_b64=$(base64 < "$screenshot_png" | tr -d '\n')
  upload_json=$(post_api_json "action=upload_attachment&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&name=$(uri "$scenario.png")&mime=$(uri "image/png")&data=$(uri "$screenshot_b64")")
  printf '%s\n' "$upload_json" > "$raw_dir/upload.json"
  attachment_id=$(printf '%s' "$upload_json" | jq -r '.attachment.id // ""')
  if [ -n "$attachment_id" ]; then
    attachment_uploaded=1
  fi
fi

default_prompt_text=$(cat <<'EOF_PROMPT'
Investigate this bounded browser/runtime issue. Use the attached Safari screenshot as Image Evidence, use the browser snapshot below as Browser Evidence, and run `./bin/runtime-check.sh` for Runtime Evidence. Do not edit files. Respond in exactly five lines starting with `Browser Evidence:`, `Image Evidence:`, `Runtime Evidence:`, `Root Cause:`, and `Next Action:`.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
if [ -s "$layout_snapshot_json" ]; then
  layout_snapshot_compact=$(jq -c . "$layout_snapshot_json" 2>/dev/null || cat "$layout_snapshot_json")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Browser snapshot from the same Safari view:
$layout_snapshot_compact
EOF_PROMPT
)
fi
if [ -s "$layout_observations_txt" ]; then
  layout_observations=$(cat "$layout_observations_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Browser geometry notes from the same Safari view:
$layout_observations
EOF_PROMPT
)
fi

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=assistant&compute_budget=quick&advanced_loop=0&max_iterations=4&attachment_ids=$(uri "$attachment_id")&stream_session=$(uri "$stream_session")"
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=120 post_api_json_with_timeout "$run_body" 90)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

assistant_lower=$(printf '%s' "$assistant_text" | tr '[:upper:]' '[:lower:]')
line_count=$(printf '%s\n' "$assistant_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
has_browser=$(printf '%s\n' "$assistant_lower" | grep -q '^browser evidence:' && printf '1' || printf '0')
has_image=$(printf '%s\n' "$assistant_lower" | grep -q '^image evidence:' && printf '1' || printf '0')
has_runtime=$(printf '%s\n' "$assistant_lower" | grep -q '^runtime evidence:' && printf '1' || printf '0')
has_root=$(printf '%s\n' "$assistant_lower" | grep -q '^root cause:' && printf '1' || printf '0')
has_next=$(printf '%s\n' "$assistant_lower" | grep -q '^next action:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_browser" -eq 1 ] && [ "$has_image" -eq 1 ] && [ "$has_runtime" -eq 1 ] && [ "$has_root" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_browser_image_answer "$scenario" "$assistant_lower")
browser_detected=$1
image_detected=$2
runtime_detected=$3
root_cause_detected=$4
next_action_detected=$5
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$screenshot_exists" -eq 1 ] && [ "$attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$browser_detected" -eq 1 ] && [ "$image_detected" -eq 1 ] \
  && [ "$runtime_detected" -eq 1 ] && [ "$root_cause_detected" -eq 1 ] \
  && [ "$next_action_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"screenshot_exists":%s,"attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"browser_detected":%s,"image_detected":%s,"runtime_detected":%s,"root_cause_detected":%s,"next_action_detected":%s,"line_count":%s,"screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$screenshot_exists" "$attachment_uploaded" "$sections_complete" "$no_disclaimer" "$browser_detected" "$image_detected" "$runtime_detected" "$root_cause_detected" "$next_action_detected" "$line_count" "$(json_escape "$screenshot_png")" > "$json_file"

{
  printf '# Browser Image Run Investigation Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Screenshot exists: %s\n' "$screenshot_exists"
  printf -- '- Attachment uploaded: %s\n' "$attachment_uploaded"
  printf -- '- Sections complete: %s\n' "$sections_complete"
  printf -- '- No disclaimer: %s\n' "$no_disclaimer"
  printf -- '- Browser detected: %s\n' "$browser_detected"
  printf -- '- Image detected: %s\n' "$image_detected"
  printf -- '- Runtime detected: %s\n' "$runtime_detected"
  printf -- '- Root cause detected: %s\n' "$root_cause_detected"
  printf -- '- Next action detected: %s\n' "$next_action_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Screenshot: %s\n' "$screenshot_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
