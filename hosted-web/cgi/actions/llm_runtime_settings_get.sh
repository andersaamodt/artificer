# action: llm_runtime_settings_get
    use_gpu=$(llm_use_gpu_enabled)
    if [ "$use_gpu" = "1" ]; then
      use_gpu_json=true
    else
      use_gpu_json=false
    fi
    printf '{"success":true,"provider":"ollama","use_gpu":%s}\n' "$use_gpu_json"
    exit 0
