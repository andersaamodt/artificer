# action: triage_cleanup
    cleanup_directive=$(trim "$(param "directive")")
    cleanup_json=$(INST_CLEANUP_DIRECTIVE="$cleanup_directive" ma_cleanup_preview_json "$cleanup_directive")
    printf '{"success":true,"result":%s}\n' "$cleanup_json"
    exit 0
