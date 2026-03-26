#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
app_src="$repo_root/hosted-web/static/artificer-app-src/08-event-bindings-and-boot.js"

if [ ! -f "$app_src" ]; then
  printf '%s\n' "missing boot source at $app_src" >&2
  exit 1
fi

if ! grep -q 'refreshAll()' "$app_src"; then
  printf '%s\n' "missing refreshAll boot chain in 08-event-bindings-and-boot.js" >&2
  exit 1
fi

if ! grep -q 'Keep model data self-healing even when initial state bootstrap fails\.' "$app_src"; then
  printf '%s\n' "missing boot failure model self-healing note in catch path" >&2
  exit 1
fi

if ! awk '
  /Keep model data self-healing even when initial state bootstrap fails\./ { in_block = 1; next }
  in_block && /startModelAutoRefreshLoop\(\)/ { saw_loop = 1 }
  in_block && /refreshModelData\(\{ force: true, silent: false \}\)/ { saw_refresh = 1 }
  in_block && /showError\(error\)/ {
    ok = (saw_loop && saw_refresh)
    exit
  }
  END { exit ok ? 0 : 1 }
' "$app_src"; then
  printf '%s\n' "boot failure catch must start model auto-refresh and force a model refresh" >&2
  exit 1
fi

printf '%s\n' "ok model auto-refresh recovery is enabled in refreshAll failure path"
