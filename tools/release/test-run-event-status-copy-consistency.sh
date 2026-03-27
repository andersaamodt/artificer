#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
app_src="$repo_root/hosted-web/static/artificer-app-modules/03-ui-and-rendering.js"

[ -f "$app_src" ] || {
  printf '%s\n' "missing ui source: $app_src" >&2
  exit 1
}

if ! grep -q 'var shouldShowQueueProgressLine = isLatestRunEvent && (queueRunning || queuePending > 0);' "$app_src"; then
  printf '%s\n' "queue progress copy must be gated to the latest run event only" >&2
  exit 1
fi

if ! grep -q 'var hasLatestQueueStatusLine = shouldShowQueueProgressLine || shouldShowQueueApprovalPause || shouldShowQueueDecisionPause;' "$app_src"; then
  printf '%s\n' "run narrative should centralize latest-queue status-line gating" >&2
  exit 1
fi

if ! grep -q 'if (shouldShowQueueProgressLine) {' "$app_src"; then
  printf '%s\n' "missing latest-run queue progress guard for continuing status copy" >&2
  exit 1
fi

if ! grep -q "Run step complete. Continuing..." "$app_src"; then
  printf '%s\n' "missing continuing status copy in run narrative rendering" >&2
  exit 1
fi

if ! grep -q 'if (!hasLatestQueueStatusLine) {' "$app_src"; then
  printf '%s\n' "run narrative copy/changes card guards are inconsistent with latest-run-only status policy" >&2
  exit 1
fi

if grep -q 'if (queueRunning || queuePending > 0)' "$app_src"; then
  printf '%s\n' "legacy queue-wide continuing copy gate detected; use latest-run-only gate instead" >&2
  exit 1
fi

printf '%s\n' "ok run event status copy: continuing/paused lines are latest-run-only and non-contradictory"
