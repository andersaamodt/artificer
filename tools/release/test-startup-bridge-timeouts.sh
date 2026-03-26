#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
index_file="$repo_root/index.html"

if [ ! -f "$index_file" ]; then
  printf '%s\n' "missing index.html at $index_file" >&2
  exit 1
fi

if ! grep -q "function bridgeExecTimeoutMs" "$index_file"; then
  printf '%s\n' "missing bridgeExecTimeoutMs function in index.html" >&2
  exit 1
fi

ensure_timeout=$(
  awk '
    /case '\''ensure-site'\'':/ { in_case = 1; next }
    in_case == 1 && /return[[:space:]]*[0-9]+;/ {
      line = $0
      sub(/^.*return[[:space:]]*/, "", line)
      sub(/;.*$/, "", line)
      print line
      exit
    }
  ' "$index_file"
)
default_timeout=$(
  awk '
    /default:/ { in_default = 1; next }
    in_default == 1 && /return[[:space:]]*[0-9]+;/ {
      line = $0
      sub(/^.*return[[:space:]]*/, "", line)
      sub(/;.*$/, "", line)
      print line
      exit
    }
  ' "$index_file"
)

case "$ensure_timeout" in
  ''|*[!0-9]*)
    printf '%s\n' "unable to parse ensure-site timeout from index.html" >&2
    exit 1
    ;;
esac
case "$default_timeout" in
  ''|*[!0-9]*)
    printf '%s\n' "unable to parse default timeout from index.html" >&2
    exit 1
    ;;
esac

if [ "$ensure_timeout" -lt 60000 ]; then
  printf '%s\n' "ensure-site timeout too low: $ensure_timeout (expected >= 60000)" >&2
  exit 1
fi

if [ "$default_timeout" -lt 15000 ]; then
  printf '%s\n' "default timeout too low: $default_timeout (expected >= 15000)" >&2
  exit 1
fi

printf '%s\n' "ok startup bridge timeout policy: ensure-site=$ensure_timeout default=$default_timeout"
