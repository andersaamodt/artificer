# action: automations_state
    printf '{"success":true,"automations":%s}\n' "$(automations_state_json)"
    exit 0
