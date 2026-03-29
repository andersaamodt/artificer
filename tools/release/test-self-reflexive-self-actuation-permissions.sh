#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

index_file="$repo_root/hosted-web/pages/index.md"
boot_file="$repo_root/hosted-web/static/artificer-app-modules/01-boot-and-storage.js"
api_sync_file="$repo_root/hosted-web/static/artificer-app-modules/05b-api-and-state-sync-tail.js"
queue_file="$repo_root/hosted-web/cgi/actions/queue_enqueue.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-001.sh"
allow_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
appctl_file="$repo_root/hosted-web/scripts/artificer-appctl"

for file_path in "$index_file" "$boot_file" "$api_sync_file" "$queue_file" "$run_part_file" "$allow_file" "$appctl_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  fi
done

if ! grep -q 'id="reflexive-knowledge-toggle-btn"' "$index_file"; then
  printf '%s\n' "permissions menu is missing reflexive knowledge toggle markup" >&2
  exit 1
fi

if ! grep -q 'id="self-actuation-toggle-btn"' "$index_file"; then
  printf '%s\n' "permissions menu is missing self-actuation toggle markup" >&2
  exit 1
fi

if ! grep -q 'artificer.reflexiveKnowledge' "$boot_file"; then
  printf '%s\n' "frontend state does not persist reflexive knowledge preference" >&2
  exit 1
fi

if ! grep -q 'artificer.selfActuation' "$boot_file"; then
  printf '%s\n' "frontend state does not persist self-actuation preference" >&2
  exit 1
fi

if ! grep -q 'reflexive_knowledge:' "$api_sync_file"; then
  printf '%s\n' "run payload does not include reflexive_knowledge" >&2
  exit 1
fi

if ! grep -q 'self_actuation:' "$api_sync_file"; then
  printf '%s\n' "run payload does not include self_actuation" >&2
  exit 1
fi

if ! grep -q 'reflexive_knowledge_raw=$(trim "$(param "reflexive_knowledge")")' "$queue_file"; then
  printf '%s\n' "queue enqueue action missing reflexive_knowledge parameter parsing" >&2
  exit 1
fi

if ! grep -q 'self_actuation_raw=$(trim "$(param "self_actuation")")' "$queue_file"; then
  printf '%s\n' "queue enqueue action missing self_actuation parameter parsing" >&2
  exit 1
fi

if ! grep -q 'reflexive_knowledge_raw=$(trim "$(param "reflexive_knowledge")")' "$run_part_file"; then
  printf '%s\n' "run action parser missing reflexive_knowledge support" >&2
  exit 1
fi

if ! grep -q 'self_actuation_raw=$(trim "$(param "self_actuation")")' "$run_part_file"; then
  printf '%s\n' "run action parser missing self_actuation support" >&2
  exit 1
fi

if ! grep -q 'artificer-appctl)' "$allow_file"; then
  printf '%s\n' "command allowlist is missing artificer-appctl support" >&2
  exit 1
fi

if ! grep -q 'SELF_ACTUATION' "$allow_file"; then
  printf '%s\n' "artificer-appctl allowlist is not gated by SELF_ACTUATION" >&2
  exit 1
fi

if ! grep -q 'automation upsert' "$appctl_file"; then
  printf '%s\n' "artificer-appctl script is missing automation upsert surface" >&2
  exit 1
fi

if ! grep -q 'knowledge show' "$appctl_file"; then
  printf '%s\n' "artificer-appctl script is missing reflexive knowledge show surface" >&2
  exit 1
fi

printf '%s\n' "ok reflexive knowledge + self-actuation permissions are wired through UI, queue/run payloads, and command gating"
