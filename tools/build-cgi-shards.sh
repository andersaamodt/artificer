#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)

build_concat() {
  src_dir=$1
  out_file=$2

  if [ ! -d "$src_dir" ]; then
    printf 'missing source dir: %s\n' "$src_dir" >&2
    exit 1
  fi

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-cgi-build.XXXXXX")
  trap 'rm -f "$tmp_file"' EXIT INT TERM

  for part in "$src_dir"/*.sh; do
    [ -f "$part" ] || continue
    cat "$part" >> "$tmp_file"
  done

  if [ ! -s "$tmp_file" ]; then
    printf 'no source shards found in %s\n' "$src_dir" >&2
    exit 1
  fi

  mv "$tmp_file" "$out_file"
  trap - EXIT INT TERM
  printf 'wrote %s\n' "$out_file"
}

build_concat \
  "$REPO_ROOT/hosted-web/cgi/actions/run_parts/run-part-004-src" \
  "$REPO_ROOT/hosted-web/cgi/actions/run_parts/run-part-004.sh"

build_concat \
  "$REPO_ROOT/hosted-web/cgi/lib/reasoning/30c-reasoning-contracts-src" \
  "$REPO_ROOT/hosted-web/cgi/lib/reasoning/30c-reasoning-contracts.sh"
