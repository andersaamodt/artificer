#!/bin/sh
set -eu

ARTIFICER_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

. "$ARTIFICER_SCRIPT_DIR/lib/00-bootstrap.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/10-self-improve.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/20-dictation.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/30-reasoning-programming.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/40-workspace-runtime.sh"
