#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
SRC_DIR="$REPO_ROOT/hosted-web/static/artificer-app-modules"
OUT_FILE="$REPO_ROOT/hosted-web/static/artificer-app.js"

if [ ! -d "$SRC_DIR" ]; then
  printf 'missing source dir: %s\n' "$SRC_DIR" >&2
  exit 1
fi

tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-app-build.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT INT TERM

for module_file in "$SRC_DIR"/*.js; do
  [ -f "$module_file" ] || continue
  cat "$module_file" >> "$tmp_file"
done

if [ ! -s "$tmp_file" ]; then
  printf 'no app source modules found in %s\n' "$SRC_DIR" >&2
  exit 1
fi

mv "$tmp_file" "$OUT_FILE"
trap - EXIT INT TERM
printf 'wrote %s\n' "$OUT_FILE"
