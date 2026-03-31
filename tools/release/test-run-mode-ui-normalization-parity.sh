#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

backend_modes_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
frontend_modes_file="$repo_root/hosted-web/static/artificer-app-modules/05-api-and-state-sync.js"
index_md_file="$repo_root/hosted-web/pages/index.md"
index_html_file="$repo_root/hosted-web/pages/index.html"

for file_path in "$backend_modes_file" "$frontend_modes_file" "$index_md_file" "$index_html_file"; do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing run-mode UI/normalization parity dependency: $file_path" >&2
    exit 1
  }
done

canonical_modes="
instant
auto
programming
pentest
security-audit
chat
teacher
report
text-perfecter
gui-testing
assistant
"

backend_mode_fn=$(awk '
  /^normalize_run_mode_name\(\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' "$backend_modes_file")
[ -n "$backend_mode_fn" ] || {
  printf '%s\n' "failed to locate normalize_run_mode_name function" >&2
  exit 1
}

frontend_mode_fn=$(awk '
  /^  function normalizeRunMode\(mode\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^  }$/ { exit }
' "$frontend_modes_file")
[ -n "$frontend_mode_fn" ] || {
  printf '%s\n' "failed to locate normalizeRunMode function" >&2
  exit 1
}

for mode_name in $canonical_modes; do
  if ! printf '%s\n' "$backend_mode_fn" | grep -Fq "$mode_name"; then
    printf '%s\n' "backend normalize_run_mode_name missing canonical mode: $mode_name" >&2
    exit 1
  fi
  if ! printf '%s\n' "$frontend_mode_fn" | grep -Fq "\"$mode_name\""; then
    printf '%s\n' "frontend normalizeRunMode missing canonical mode: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-run-mode=\"$mode_name\"" "$index_md_file"; then
    printf '%s\n' "index.md run-mode menu missing canonical mode button: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-run-mode=\"$mode_name\"" "$index_html_file"; then
    printf '%s\n' "index.html run-mode menu missing canonical mode button: $mode_name" >&2
    exit 1
  fi
done

if ! awk '
  /^[[:space:]]*if[[:space:]]*\(value[[:space:]]*===[[:space:]]*"security-audit"\)/ { in_branch=1; next }
  in_branch && /^[[:space:]]*if[[:space:]]*\(value[[:space:]]*===/ { in_branch=0 }
  in_branch && /reasoning:[[:space:]]*"extra-high"/ { branch_ok=1 }
  END { exit branch_ok ? 0 : 1 }
' "$frontend_modes_file"; then
  printf '%s\n' "frontend security-audit default profile must enforce extra-high reasoning" >&2
  exit 1
fi

for parse_target in "$backend_modes_file"; do
  if ! sh -n "$parse_target"; then
    printf '%s\n' "shell parse failed for run-mode UI/normalization parity file: $parse_target" >&2
    exit 1
  fi
done

printf '%s\n' "ok run-mode UI/normalization parity: canonical modes and security-audit default depth remain synchronized across backend normalization, frontend normalization, and menus"
