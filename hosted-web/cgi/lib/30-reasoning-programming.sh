#!/bin/sh
set -eu

. "$ARTIFICER_SCRIPT_DIR/lib/reasoning/30a-core-budget-normalization.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/reasoning/30b-programming-branching.sh"
reasoning_contracts_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-reasoning-contracts.XXXXXX")
cat "$ARTIFICER_SCRIPT_DIR/lib/reasoning/30c-reasoning-contracts-src/"*.part > "$reasoning_contracts_tmp"
. "$reasoning_contracts_tmp"
rm -f "$reasoning_contracts_tmp"
. "$ARTIFICER_SCRIPT_DIR/lib/reasoning/30d-task-specializations.sh"
. "$ARTIFICER_SCRIPT_DIR/lib/reasoning/30e-model-adapters-salvage.sh"
