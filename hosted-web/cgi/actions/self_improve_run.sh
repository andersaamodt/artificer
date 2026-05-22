# action: self_improve_run
    model_name=$(trim "$(param "model")")
    if [ -z "$model_name" ]; then
      model_name=$(self_improve_selected_model)
    fi
    if [ -z "$model_name" ]; then
      model_name=$(list_models_raw | sed -n '1p')
    fi
    if [ -z "$model_name" ]; then
      emit_error "no installed models available for self-improve"
      exit 0
    fi
    set_self_improve_selected_model "$model_name"
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

    run_options_json=$(self_improve_run_options_merge_json \
      "$objective_value" \
      "$competition_value" \
      "$challenger_value" \
      "$codex_work_check_value" \
      "$source_papers_value" \
      "$source_web_value" \
      "$source_runtime_value" \
      "$source_repo_value" \
      "$source_platform_value")
    run_options_json=$(set_self_improve_run_options_json "$run_options_json")
    options_kv=$(SELF_IMPROVE_OPTIONS_JSON=$run_options_json python3 - <<'PY'
import json, os
try:
    payload = json.loads(os.environ.get("SELF_IMPROVE_OPTIONS_JSON", ""))
except Exception:
    payload = {}
if not isinstance(payload, dict):
    payload = {}
objective = " ".join(str(payload.get("objective", "")).split()).strip()
competition_enabled = payload.get("competition_enabled", True)
if isinstance(competition_enabled, bool):
    competition_enabled_value = competition_enabled
else:
    competition_enabled_value = str(competition_enabled).strip().lower() in {"1", "true", "yes", "on", "enabled"}
challenger_model = " ".join(str(payload.get("challenger_model", "")).split()).strip()
print(f"objective={objective}")
print(f"competition_enabled={'1' if competition_enabled_value else '0'}")
print(f"challenger_model={challenger_model}")
PY
    )
    objective_text=$(kv_get "objective" "$options_kv")
    competition_enabled=$(kv_get "competition_enabled" "$options_kv")
    challenger_model=$(kv_get "challenger_model" "$options_kv")
    if [ "$competition_enabled" = "1" ] && [ -z "$challenger_model" ]; then
      challenger_model=$(list_models_raw | awk -v active="$model_name" '
        $0 != "" && $0 != active { print $0; exit }
      ')
    fi
    if [ -z "$challenger_model" ]; then
      challenger_model="$model_name"
    fi

    evidence_json=$(self_improve_build_evidence_bundle_json "$run_options_json")
    primary_report_json=$(self_improve_generate_lane_report_json "$model_name" "artificer" "$objective_text" "$evidence_json")
    challenger_report_json='{"lane":"challenger","model":"","summary":"","strategy":"","plugins":[]}'
    if [ "$competition_enabled" = "1" ]; then
      challenger_report_json=$(self_improve_generate_lane_report_json "$challenger_model" "challenger" "$objective_text" "$evidence_json")
    fi
    final_report_json=$(self_improve_compare_reports_json \
      "$objective_text" \
      "$evidence_json" \
      "$primary_report_json" \
      "$challenger_report_json" \
      "$model_name" \
      "$challenger_model" \
      "$competition_enabled")
    merged_plugin_count=$(REPORT_JSON=$final_report_json python3 - <<'PY'
import json, os
try:
    payload = json.loads(os.environ.get("REPORT_JSON", ""))
except Exception:
    payload = {}
plugins = payload.get("plugins", []) if isinstance(payload, dict) else []
print(len(plugins) if isinstance(plugins, list) else 0)
PY
)
    case "$merged_plugin_count" in
      ""|*[!0-9]*) merged_plugin_count=0 ;;
    esac
    if [ "$merged_plugin_count" -lt 1 ]; then
      emit_error "self-improve did not generate any usable plugins"
      exit 0
    fi
    store_json=$(self_improve_store_report_and_plugins "$model_name" "$run_options_json" "$evidence_json" "$final_report_json")
    printf '{"success":true,"selected_model":"%s","run_options":%s,"last_run":%s,"plugins":%s,"archived_plugins":%s,"plugin_inventory":%s}\n' \
      "$(json_escape "$model_name")" \
      "$run_options_json" \
      "$store_json" \
      "$(self_improve_plugins_json)" \
      "$(self_improve_archived_plugins_json)" \
      "$(self_improve_plugin_inventory_json)"
    exit 0
