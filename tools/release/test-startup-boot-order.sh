#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
index_file="$repo_root/index.html"

[ -f "$index_file" ] || {
  printf '%s\n' "missing index.html at $index_file" >&2
  exit 1
}

line_hot=$(
  grep -n "var hotPort = await detectReadyPort();" "$index_file" | head -n 1 | cut -d: -f1
)
line_start=$(
  grep -n "await startWithFallbackPort();" "$index_file" | head -n 1 | cut -d: -f1
)
line_ensure=$(
  grep -n "await ensureSiteIfNeeded();" "$index_file" | head -n 1 | cut -d: -f1
)

for pair in "$line_hot:detect-ready-port" "$line_start:start-with-fallback" "$line_ensure:ensure-site"; do
  line_no=${pair%%:*}
  label=${pair#*:}
  case "$line_no" in
    ''|*[!0-9]*)
      printf '%s\n' "unable to parse $label boot marker line from index.html" >&2
      exit 1
      ;;
  esac
done

if [ "$line_hot" -ge "$line_ensure" ]; then
  printf '%s\n' "boot order regression: detect-ready-port should run before ensure-site fallback" >&2
  exit 1
fi

if [ "$line_start" -ge "$line_ensure" ]; then
  printf '%s\n' "boot order regression: start-with-fallback should run before ensure-site fallback" >&2
  exit 1
fi

printf '%s\n' "ok startup boot order: detect-ready-port/start-with-fallback precede ensure-site fallback"
