# action: llm_runtime_settings_set
    use_gpu=$(trim "$(param "use_gpu")")
    case "$use_gpu" in
      1|true|TRUE|True|yes|YES|Yes|on|ON|On)
        normalized_gpu=1
        ;;
      0|false|FALSE|False|no|NO|No|off|OFF|Off)
        normalized_gpu=0
        ;;
      *)
        emit_error "invalid use_gpu value"
        exit 0
        ;;
    esac
    set_llm_use_gpu_enabled "$normalized_gpu"
    if [ "$normalized_gpu" = "1" ]; then
      use_gpu_json=true
    else
      use_gpu_json=false
    fi
    printf '{"success":true,"provider":"ollama","use_gpu":%s}\n' "$use_gpu_json"
    exit 0
