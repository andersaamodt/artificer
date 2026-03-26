#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
SRC_DIR="$REPO_ROOT/hosted-web/static/artificer-app-src"
OUT_FILE="$REPO_ROOT/hosted-web/static/artificer-app.js"

if [ ! -d "$SRC_DIR" ]; then
  printf 'missing source dir: %s\n' "$SRC_DIR" >&2
  exit 1
fi

tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-app-build.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT INT TERM

for part in "$SRC_DIR"/*.js; do
  [ -f "$part" ] || continue
  cat "$part" >> "$tmp_file"
done

if [ ! -s "$tmp_file" ]; then
  printf 'no app source parts found in %s\n' "$SRC_DIR" >&2
  exit 1
fi

mv "$tmp_file" "$OUT_FILE"
trap - EXIT INT TERM
printf 'wrote %s\n' "$OUT_FILE"
