# action: self_knowledge_state
    topic_raw=$(trim "$(param "topic")")
    format_raw=$(trim "$(param "format")")
    format_value=$(printf '%s' "$format_raw" | tr '[:upper:]' '[:lower:]')
    case "$format_value" in
      ""|state|json)
        self_knowledge_state_json "$topic_raw"
        ;;
      teach|text)
        self_knowledge_teach_json "$topic_raw"
        ;;
      *)
        emit_error "invalid format (expected: state|json|teach|text)"
        ;;
    esac
    exit 0
