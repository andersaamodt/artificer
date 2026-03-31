#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

backend_mode_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
backend_queue_file="$repo_root/hosted-web/cgi/lib/runtime/40a-core-queue.sh"
frontend_modes_file="$repo_root/hosted-web/static/artificer-app-modules/05-api-and-state-sync.js"
frontend_runtime_file="$repo_root/hosted-web/static/artificer-app-modules/02-runtime-core.js"
frontend_boot_file="$repo_root/hosted-web/static/artificer-app-modules/01-boot-and-storage.js"
frontend_save_file="$repo_root/hosted-web/static/artificer-app-modules/04b-dictation-wave-tail.js"
index_md_file="$repo_root/hosted-web/pages/index.md"
index_html_file="$repo_root/hosted-web/pages/index.html"

for file_path in \
  "$backend_mode_file" \
  "$backend_queue_file" \
  "$frontend_modes_file" \
  "$frontend_runtime_file" \
  "$frontend_boot_file" \
  "$frontend_save_file" \
  "$index_md_file" \
  "$index_html_file"
do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing control-mode parity dependency: $file_path" >&2
    exit 1
  }
done

backend_compute_fn=$(awk '
  /^normalize_compute_budget\(\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' "$backend_mode_file")
[ -n "$backend_compute_fn" ] || {
  printf '%s\n' "failed to locate backend normalize_compute_budget function" >&2
  exit 1
}

frontend_compute_fn=$(awk '
  /^  function normalizeComputeBudget\(value\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^  }$/ { exit }
' "$frontend_modes_file")
[ -n "$frontend_compute_fn" ] || {
  printf '%s\n' "failed to locate frontend normalizeComputeBudget function" >&2
  exit 1
}

canonical_compute_budgets="
auto
quick
standard
long
until-complete
"

for budget_name in $canonical_compute_budgets; do
  if ! printf '%s\n' "$backend_compute_fn" | grep -Fq "$budget_name"; then
    printf '%s\n' "backend normalize_compute_budget missing budget branch: $budget_name" >&2
    exit 1
  fi
  if ! printf '%s\n' "$frontend_compute_fn" | grep -Fq "\"$budget_name\""; then
    printf '%s\n' "frontend normalizeComputeBudget missing budget branch: $budget_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-compute-budget=\"$budget_name\"" "$index_md_file"; then
    printf '%s\n' "index.md compute budget menu missing canonical option: $budget_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-compute-budget=\"$budget_name\"" "$index_html_file"; then
    printf '%s\n' "index.html compute budget menu missing canonical option: $budget_name" >&2
    exit 1
  fi
done

backend_command_exec_fn=$(awk '
  /^normalize_command_exec_mode_value\(\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' "$backend_queue_file")
[ -n "$backend_command_exec_fn" ] || {
  printf '%s\n' "failed to locate backend normalize_command_exec_mode_value function" >&2
  exit 1
}

frontend_command_exec_fn=$(awk '
  /^  function normalizeCommandExecModeValue\(mode\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^  }$/ { exit }
' "$frontend_runtime_file")
[ -n "$frontend_command_exec_fn" ] || {
  printf '%s\n' "failed to locate frontend normalizeCommandExecModeValue function" >&2
  exit 1
}

canonical_command_exec_modes="
none
ask-all
ask-some
all
"

for mode_name in $canonical_command_exec_modes; do
  if ! printf '%s\n' "$backend_command_exec_fn" | grep -Fq "$mode_name"; then
    printf '%s\n' "backend normalize_command_exec_mode_value missing mode branch: $mode_name" >&2
    exit 1
  fi
  if ! printf '%s\n' "$frontend_command_exec_fn" | grep -Fq "\"$mode_name\""; then
    printf '%s\n' "frontend normalizeCommandExecModeValue missing mode branch: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-command-exec=\"$mode_name\"" "$index_md_file"; then
    printf '%s\n' "index.md command-exec menu missing canonical option: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-command-exec=\"$mode_name\"" "$index_html_file"; then
    printf '%s\n' "index.html command-exec menu missing canonical option: $mode_name" >&2
    exit 1
  fi
done

if ! printf '%s\n' "$backend_command_exec_fn" | grep -Fq "ask)"; then
  printf '%s\n' "backend normalize_command_exec_mode_value missing ask alias branch" >&2
  exit 1
fi
if ! printf '%s\n' "$backend_command_exec_fn" | grep -Fq '"ask-some"'; then
  printf '%s\n' "backend normalize_command_exec_mode_value must map ask alias to ask-some" >&2
  exit 1
fi
if ! printf '%s\n' "$frontend_command_exec_fn" | grep -Fq 'value === "ask"'; then
  printf '%s\n' "frontend normalizeCommandExecModeValue missing ask alias branch" >&2
  exit 1
fi
if ! printf '%s\n' "$frontend_command_exec_fn" | grep -Fq '"ask-some"'; then
  printf '%s\n' "frontend normalizeCommandExecModeValue must map ask alias to ask-some" >&2
  exit 1
fi

backend_permission_fn=$(awk '
  /^normalize_permission_mode_value\(\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' "$backend_queue_file")
[ -n "$backend_permission_fn" ] || {
  printf '%s\n' "failed to locate backend normalize_permission_mode_value function" >&2
  exit 1
}

frontend_permission_fn=$(awk '
  /^  function normalizePermissionModeValue\(mode\)/ { in_fn=1 }
  in_fn { print }
  in_fn && /^  }$/ { exit }
' "$frontend_runtime_file")
[ -n "$frontend_permission_fn" ] || {
  printf '%s\n' "failed to locate frontend normalizePermissionModeValue function" >&2
  exit 1
}

canonical_permission_modes="
default
workspace-write
read-only
"

for mode_name in $canonical_permission_modes; do
  if ! printf '%s\n' "$backend_permission_fn" | grep -Fq "$mode_name"; then
    printf '%s\n' "backend normalize_permission_mode_value missing mode branch: $mode_name" >&2
    exit 1
  fi
  if ! printf '%s\n' "$frontend_permission_fn" | grep -Fq "\"$mode_name\""; then
    printf '%s\n' "frontend normalizePermissionModeValue missing mode branch: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-permission=\"$mode_name\"" "$index_md_file"; then
    printf '%s\n' "index.md permissions menu missing canonical option: $mode_name" >&2
    exit 1
  fi
  if ! grep -Fq "data-permission=\"$mode_name\"" "$index_html_file"; then
    printf '%s\n' "index.html permissions menu missing canonical option: $mode_name" >&2
    exit 1
  fi
done

if printf '%s\n' "$backend_permission_fn" | grep -Fq "full-access)" && \
  ! printf '%s\n' "$backend_permission_fn" | grep -Fq '"default"'; then
  printf '%s\n' "backend normalize_permission_mode_value full-access alias must collapse to default" >&2
  exit 1
fi
if ! printf '%s\n' "$frontend_permission_fn" | grep -Fq 'value === "full-access"'; then
  printf '%s\n' "frontend normalizePermissionModeValue missing full-access alias branch" >&2
  exit 1
fi
if ! printf '%s\n' "$frontend_permission_fn" | grep -Fq '"default"'; then
  printf '%s\n' "frontend normalizePermissionModeValue full-access alias must collapse to default" >&2
  exit 1
fi

if grep -Fq 'data-permission="full-access"' "$index_md_file"; then
  printf '%s\n' "index.md permissions menu must not expose full-access option" >&2
  exit 1
fi
if grep -Fq 'data-permission="full-access"' "$index_html_file"; then
  printf '%s\n' "index.html permissions menu must not expose full-access option" >&2
  exit 1
fi

if grep -Fq 'case "full-access":' "$frontend_runtime_file"; then
  printf '%s\n' "frontend permission label rendering must not expose full-access label" >&2
  exit 1
fi
if grep -Fq 'mode === "full-access"' "$frontend_runtime_file"; then
  printf '%s\n' "frontend permission icon rendering must not expose full-access icon path" >&2
  exit 1
fi

if ! grep -Fq 'if (state.permissionMode === "full-access") {' "$frontend_boot_file"; then
  printf '%s\n' "boot migration must collapse persisted full-access permission mode to default" >&2
  exit 1
fi
if ! grep -Fq 'state.permissionMode = "default";' "$frontend_boot_file"; then
  printf '%s\n' "boot migration must set canonical default permission mode" >&2
  exit 1
fi
if ! grep -Fq 'var next = normalizePermissionModeValue(mode) || "default";' "$frontend_save_file"; then
  printf '%s\n' "permission-mode persistence must save canonical normalized value" >&2
  exit 1
fi

for parse_target in "$backend_mode_file" "$backend_queue_file"; do
  if ! sh -n "$parse_target"; then
    printf '%s\n' "shell parse failed for control-mode parity file: $parse_target" >&2
    exit 1
  fi
done

printf '%s\n' "ok control-mode UI/normalization parity: compute budget, command execution mode, and permissions remain synchronized across backend normalization, frontend normalization, and menus"
