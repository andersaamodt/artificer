#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
out_dir=${1-"$ROOT_DIR/dist"}
os=$(uname -s 2>/dev/null || printf unknown)

mkdir -p "$out_dir"
case "$os" in
  Darwin)
    "$SCRIPT_DIR/build-release-bundle.sh" "$out_dir" >/dev/null
    "$SCRIPT_DIR/build-macos-app.sh" "$out_dir"
    ;;
  Linux)
    "$SCRIPT_DIR/build-release-bundle.sh" "$out_dir"
    ;;
  *)
    printf '%s\n' "build-release-artifacts: unsupported OS $os" >&2
    exit 1
    ;;
esac
