#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
app_src_head="$repo_root/hosted-web/static/artificer-app-modules/08-event-bindings-and-boot.js"
app_src_tail="$repo_root/hosted-web/static/artificer-app-modules/08b-event-bindings-and-boot-tail.js"
combined_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-model-refresh-test.XXXXXX")
trap 'rm -f "$combined_tmp"' EXIT INT TERM

if [ ! -f "$app_src_head" ] || [ ! -f "$app_src_tail" ]; then
  printf '%s\n' "missing boot source fragments at $app_src_head and $app_src_tail" >&2
  exit 1
fi

cat "$app_src_head" "$app_src_tail" > "$combined_tmp"

if ! grep -q 'refreshAll()' "$combined_tmp"; then
  printf '%s\n' "missing refreshAll boot chain in event bindings fragments" >&2
  exit 1
fi

if ! grep -q 'Keep model data self-healing even when initial state bootstrap fails\.' "$combined_tmp"; then
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
' "$combined_tmp"; then
  printf '%s\n' "boot failure catch must start model auto-refresh and force a model refresh" >&2
  exit 1
fi

printf '%s\n' "ok model auto-refresh recovery is enabled in refreshAll failure path"
