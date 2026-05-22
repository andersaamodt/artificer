# action: dictation_prewarm_set
    enabled=$(trim "$(param "enabled")")
    case "$enabled" in
      1|true|TRUE|True|yes|YES|Yes|on|ON|On)
        set_dictation_prewarm_enabled 1
        ;;
      0|false|FALSE|False|no|NO|No|off|OFF|Off)
        set_dictation_prewarm_enabled 0
        ;;
      *)
        emit_error "invalid enabled value"
        exit 0
        ;;
    esac
    dictation_prewarm_get_json
    exit 0
