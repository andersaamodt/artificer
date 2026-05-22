# action: self_improve_run_options_set
    keep_value="__ARTIFICER_KEEP__"
    objective_value=$keep_value
    competition_value=$keep_value
    challenger_value=$keep_value
    codex_work_check_value=$keep_value
    source_papers_value=$keep_value
    source_web_value=$keep_value
    source_runtime_value=$keep_value
    source_repo_value=$keep_value
    source_platform_value=$keep_value

    if self_improve_param_present "objective"; then
      objective_value=$(param "objective")
    fi
    if self_improve_param_present "competition_enabled"; then
      competition_value=$(param "competition_enabled")
    fi
    if self_improve_param_present "challenger_model"; then
      challenger_value=$(param "challenger_model")
    fi
    if self_improve_param_present "codex_work_check_enabled"; then
      codex_work_check_value=$(param "codex_work_check_enabled")
    fi
    if self_improve_param_present "source_papers"; then
      source_papers_value=$(param "source_papers")
    fi
    if self_improve_param_present "source_web"; then
      source_web_value=$(param "source_web")
    fi
    if self_improve_param_present "source_runtime"; then
      source_runtime_value=$(param "source_runtime")
    fi
    if self_improve_param_present "source_repo"; then
      source_repo_value=$(param "source_repo")
    fi
    if self_improve_param_present "source_platform"; then
      source_platform_value=$(param "source_platform")
    fi

    merged_options_json=$(self_improve_run_options_merge_json \
      "$objective_value" \
      "$competition_value" \
      "$challenger_value" \
      "$codex_work_check_value" \
      "$source_papers_value" \
      "$source_web_value" \
      "$source_runtime_value" \
      "$source_repo_value" \
      "$source_platform_value")
    persisted_options_json=$(set_self_improve_run_options_json "$merged_options_json")
    printf '{"success":true,"run_options":%s}\n' "$persisted_options_json"
    exit 0
