#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
launcher="$repo_root/run-artificer"

[ -f "$launcher" ] || {
  printf '%s\n' "missing launcher script at $launcher" >&2
  exit 1
}

if grep -q 'port=\$("$APP_ROOT/scripts/artificer-backend.sh" start-serve "$APP_ROOT")' "$launcher"; then
  printf '%s\n' "startup regression: run-artificer captures start-serve via command substitution" >&2
  exit 1
fi

grep -q '\$APP_ROOT/scripts/artificer-backend.sh" start-serve "$APP_ROOT" >/dev/null' "$launcher" || {
  printf '%s\n' "startup regression: run-artificer must start backend directly before resolving port" >&2
  exit 1
}

grep -q 'artificer-backend.sh" detect-ready-port "$APP_ROOT"' "$launcher" || {
  printf '%s\n' "startup regression: run-artificer must resolve active port via detect-ready-port" >&2
  exit 1
}

grep -q 'artificer-backend.sh" get-port "$APP_ROOT"' "$launcher" || {
  printf '%s\n' "startup regression: run-artificer must fallback to configured port lookup" >&2
  exit 1
}

printf '%s\n' "ok run-artificer startup resolves port without start-serve command substitution"
