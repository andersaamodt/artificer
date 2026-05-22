# action: self_actuation_audit_state
    limit_raw=$(trim "$(param "limit")")
    case "$limit_raw" in
      ""|*[!0-9]*)
        limit_raw=50
        ;;
    esac
    if [ "$limit_raw" -lt 1 ]; then
      limit_raw=1
    fi
    if [ "$limit_raw" -gt 500 ]; then
      limit_raw=500
    fi

    printf '{"success":true,"limit":"%s","entries":%s}\n' \
      "$(json_escape "$limit_raw")" \
      "$(self_actuation_audit_entries_json "$limit_raw")"
    exit 0
