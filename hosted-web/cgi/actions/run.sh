# action: run
. "$ARTIFICER_SCRIPT_DIR/actions/run_parts/run-part-001.sh"
. "$ARTIFICER_SCRIPT_DIR/actions/run_parts/run-part-002.sh"
. "$ARTIFICER_SCRIPT_DIR/actions/run_parts/run-part-003.sh"
run_part_004_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-run-part-004.XXXXXX")
cat "$ARTIFICER_SCRIPT_DIR/actions/run_parts/run-part-004-src/"*.part > "$run_part_004_tmp"
. "$run_part_004_tmp"
rm -f "$run_part_004_tmp"
