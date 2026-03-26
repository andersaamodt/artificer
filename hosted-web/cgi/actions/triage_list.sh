# action: triage_list
    if ! command -v ma_triage_cards_json >/dev/null 2>&1; then
      emit_error "Multi-agent runtime is unavailable"
      exit 0
    fi
    cards_json=$(ma_triage_cards_json)
    cards_count=$(printf '%s\n' "$cards_json" | perl -MJSON::PP -e 'use strict; use warnings; local $/; my $raw=<STDIN>; my $d=eval { decode_json($raw) }; if ($@ || ref($d) ne "ARRAY") { print 0; exit 0; } print scalar(@$d);' 2>/dev/null || printf '0')
    printf '{"success":true,"count":"%s","cards":%s}\n' "$(json_escape "$cards_count")" "$cards_json"
    exit 0
