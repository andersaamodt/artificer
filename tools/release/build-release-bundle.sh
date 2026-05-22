#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
. "$SCRIPT_DIR/common.sh"

out_dir=${1-"$ROOT_DIR/dist"}
version=$(artificer_version "$ROOT_DIR")
arch_raw=${ARTIFICER_TARGET_ARCH:-$(uname -m 2>/dev/null || printf unknown)}
case "$arch_raw" in
  x86_64|amd64)
    arch_slug="x86_64"
    ;;
  aarch64|arm64)
    arch_slug="arm64"
    ;;
  *)
    arch_slug=$(printf '%s' "$arch_raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')
    [ -n "$arch_slug" ] || arch_slug="unknown"
    ;;
esac
slug="artificer-$version-linux-$arch_slug"

mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd -P)
stage_dir="$out_dir/$slug"
archive="$out_dir/$slug.tar.gz"
artificer_stage_runtime "$ROOT_DIR" "$stage_dir"
rm -f "$archive"
(
  cd "$out_dir"
  tar -czf "$archive" "$slug"
)
printf 'artifact=%s\n' "$archive"
printf 'stage_dir=%s\n' "$stage_dir"
