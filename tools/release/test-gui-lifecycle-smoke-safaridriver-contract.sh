#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
smoke_script="$repo_root/hosted-web/scripts/gui-lifecycle-smoke-safari.sh"

if [ ! -f "$smoke_script" ]; then
  printf '%s\n' "missing Safari lifecycle smoke script: $smoke_script" >&2
  exit 1
fi

if ! grep -q 'command -v safaridriver' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke no longer requires safaridriver" >&2
  exit 1
fi

if ! grep -q 'Continue Session' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke missing Continue Session interlock handling" >&2
  exit 1
fi

if ! grep -q '/session/{session_id}/execute/sync' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke missing WebDriver execute/sync automation path" >&2
  exit 1
fi

if ! grep -q 'safaridriver -p' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke missing safaridriver launch" >&2
  exit 1
fi

if grep -q 'do JavaScript' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke still depends on Safari do JavaScript Apple-event automation" >&2
  exit 1
fi

if ! grep -q 'return (function () {' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke no longer returns its injected WebDriver script results" >&2
  exit 1
fi

if ! grep -q 'ensureConversationSelected(workspaceId, approvalConversationId)' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke no longer switches into the approval conversation before approval verification" >&2
  exit 1
fi

if ! grep -q 'approval_conversation_not_selected_after_reload' "$smoke_script"; then
  printf '%s\n' "Safari lifecycle smoke no longer guards approval conversation selection across reload" >&2
  exit 1
fi

printf '%s\n' "ok Safari lifecycle smoke harness uses safaridriver with session-continue interlock handling"
