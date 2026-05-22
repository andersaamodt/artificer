# action: self_actuation_orchestrate
    sa_url_encode() {
      input=$1
      if command -v python3 >/dev/null 2>&1; then
        python3 - "$input" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
        return 0
      fi
      printf '%s' "$input" | sed 's/%/%25/g;s/ /%20/g;s/\t/%09/g;s/\n/%0A/g;s/\r/%0D/g;s/&/%26/g;s/=/%3D/g;s/?/%3F/g;s/#/%23/g'
    }

    sa_call_action() {
      action_name=$1
      shift
      body="action=$(sa_url_encode "$action_name")"
      while [ "$#" -gt 0 ]; do
        key=$1
        value=$2
        shift 2
        body="${body}&$(sa_url_encode "$key")=$(sa_url_encode "$value")"
      done
      body_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
      response=$(printf '%s' "$body" | REQUEST_METHOD=POST CONTENT_TYPE='application/x-www-form-urlencoded' CONTENT_LENGTH="$body_length" "$ARTIFICER_API_SCRIPT" 2>&1 || true)
      json_payload=$(printf '%s\n' "$response" | awk '
        BEGIN { body = 0 }
        {
          line = $0
          sub(/\r$/, "", line)
          if (body == 1) {
            print line
            next
          }
          if (line == "") {
            body = 1
          }
        }
      ')
      if [ -n "$json_payload" ]; then
        response=$json_payload
      fi
      printf '%s\n' "$response"
    }

    sa_json_query() {
      payload=$1
      expression=$2
      if ! command -v python3 >/dev/null 2>&1; then
        printf '%s' ""
        return 0
      fi
      JSON_PAYLOAD=$payload JSON_EXPR=$expression python3 - <<'PY'
import json
import os

payload = os.environ.get("JSON_PAYLOAD", "")
expr = os.environ.get("JSON_EXPR", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)
try:
    value = eval(expr, {"__builtins__": {"len": len}}, {"data": data})
except Exception:
    print("")
    raise SystemExit(0)
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
else:
    print(str(value))
PY
    }

    sa_json_success() {
      payload=$1
      success_value=$(sa_json_query "$payload" 'data.get("success", False)')
      [ "$success_value" = "true" ]
    }

    sa_emit_error_with_audit() {
      error_message=$1
      status_value=${2:-error}
      self_actuation_audit_append "orchestrate" "$operation" "$workspace_id_resolved" "$conversation_id_resolved" "$automation_id_resolved" "$status_value" "$error_message" "$idempotency_key" "$expected_confirm_token"
      emit_error "$error_message"
      exit 0
    }

    sa_append_change() {
      change_json=$1
      if [ -n "$changes_json" ]; then
        changes_json="${changes_json},${change_json}"
      else
        changes_json=$change_json
      fi
    }

    sa_resolve_workspace_id() {
      workspace_candidate=""
      if [ -n "$workspace_id_raw" ] && valid_workspace_id "$workspace_id_raw"; then
        ws_dir=$(workspace_dir_for "$workspace_id_raw")
        if [ -d "$ws_dir" ]; then
          workspace_candidate=$workspace_id_raw
        fi
      fi
      if [ -z "$workspace_candidate" ] && [ -n "$path_raw" ]; then
        workspace_candidate=$(self_actuation_workspace_id_for_path "$path_raw")
      fi
      if [ -z "$workspace_candidate" ] && [ -n "$automation_id_raw" ]; then
        workspace_candidate=$(self_actuation_workspace_id_for_automation "$automation_id_raw")
      fi
      printf '%s' "$workspace_candidate"
    }

    sa_resolve_conversation_id() {
      conversation_candidate=""
      if [ -n "$conversation_id_raw" ] && valid_id "$conversation_id_raw"; then
        conversation_candidate=$conversation_id_raw
      fi
      if [ -z "$conversation_candidate" ] && [ -n "$workspace_id_resolved" ] && [ -n "$title_raw" ]; then
        conversation_candidate=$(self_actuation_thread_id_for_title "$workspace_id_resolved" "$title_raw")
      fi
      printf '%s' "$conversation_candidate"
    }

    sa_resolve_automation_id() {
      automation_candidate=""
      if [ -n "$automation_id_raw" ] && valid_id "$automation_id_raw"; then
        automation_candidate=$automation_id_raw
      fi
      if [ -z "$automation_candidate" ] && [ -n "$workspace_id_resolved" ] && [ -n "$name_raw" ]; then
        automation_candidate=$(self_actuation_automation_id_for_workspace_name "$workspace_id_resolved" "$name_raw")
      fi
      printf '%s' "$automation_candidate"
    }

    sa_validate_operation_inputs() {
      case "$operation" in
        ensure_workspace)
          if [ -z "$workspace_id_resolved" ] && [ -z "$path_raw" ]; then
            emit_error "ensure_workspace requires an existing --workspace-id or a --path"
            return 1
          fi
          ;;
        rename_workspace)
          if [ -z "$workspace_id_resolved" ]; then
            emit_error "rename_workspace requires an existing workspace"
            return 1
          fi
          if [ -z "$name_raw" ]; then
            emit_error "rename_workspace requires --name"
            return 1
          fi
          ;;
        delete_workspace)
          if [ -z "$workspace_id_resolved" ]; then
            emit_error "delete_workspace requires an existing workspace"
            return 1
          fi
          ;;
        ensure_thread)
          if [ -z "$workspace_id_resolved" ]; then
            emit_error "ensure_thread requires an existing workspace"
            return 1
          fi
          if [ -z "$title_raw" ] && [ -z "$conversation_id_resolved" ]; then
            emit_error "ensure_thread requires --title or --conversation-id"
            return 1
          fi
          ;;
        archive_thread)
          if [ -z "$workspace_id_resolved" ] || [ -z "$conversation_id_resolved" ]; then
            emit_error "archive_thread requires existing workspace and conversation ids"
            return 1
          fi
          ;;
        ensure_automation)
          if [ -z "$workspace_id_resolved" ]; then
            emit_error "ensure_automation requires an existing workspace"
            return 1
          fi
          if [ -z "$name_raw" ] && [ -z "$automation_id_resolved" ]; then
            emit_error "ensure_automation requires --name or --automation-id"
            return 1
          fi
          if [ -z "$(trim "$prompt_raw")" ] && [ -z "$automation_id_resolved" ]; then
            emit_error "ensure_automation requires --prompt when creating"
            return 1
          fi
          if [ -z "$schedule_kind_raw" ] && [ -z "$automation_id_resolved" ]; then
            emit_error "ensure_automation requires --schedule-kind when creating"
            return 1
          fi
          if [ -z "$schedule_value_raw" ] && [ -z "$automation_id_resolved" ]; then
            emit_error "ensure_automation requires --schedule-value when creating"
            return 1
          fi
          ;;
        toggle_automation|run_automation_now|delete_automation)
          if [ -z "$automation_id_resolved" ]; then
            emit_error "$operation requires an existing automation id"
            return 1
          fi
          ;;
        bootstrap_workspace_stack)
          if [ -z "$workspace_id_resolved" ] && [ -z "$path_raw" ]; then
            emit_error "bootstrap_workspace_stack requires an existing --workspace-id or a --path"
            return 1
          fi
          ;;
        *)
          emit_error "unsupported operation"
          return 1
          ;;
      esac
      return 0
    }

    sa_apply_ensure_workspace() {
      if [ -n "$workspace_id_resolved" ]; then
        sa_append_change "{\"step\":\"workspace\",\"status\":\"exists\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        return 0
      fi
      if [ -z "$path_raw" ]; then
        return 1
      fi
      create_workspace_response=$(sa_call_action "control_plane_projects" \
        "op" "add" \
        "path" "$path_raw" \
        "name" "$name_raw" \
        "command_exec_mode" "$command_exec_mode_raw")
      if ! sa_json_success "$create_workspace_response"; then
        return 1
      fi
      workspace_id_resolved=$(sa_json_query "$create_workspace_response" '((data.get("workspace") or {}).get("id") or "")')
      if [ -z "$workspace_id_resolved" ]; then
        return 1
      fi
      sa_append_change "{\"step\":\"workspace\",\"status\":\"created\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
      return 0
    }

    sa_apply_rename_workspace() {
      rename_response=$(sa_call_action "control_plane_projects" \
        "op" "rename" \
        "workspace_id" "$workspace_id_resolved" \
        "name" "$name_raw")
      if ! sa_json_success "$rename_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"workspace\",\"status\":\"renamed\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
      return 0
    }

    sa_apply_delete_workspace() {
      delete_response=$(sa_call_action "control_plane_projects" \
        "op" "delete" \
        "workspace_id" "$workspace_id_resolved")
      if ! sa_json_success "$delete_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"workspace\",\"status\":\"deleted\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
      return 0
    }

    sa_apply_ensure_thread() {
      if [ -n "$conversation_id_resolved" ]; then
        sa_append_change "{\"step\":\"thread\",\"status\":\"exists\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
        return 0
      fi
      thread_response=$(sa_call_action "control_plane_sessions" \
        "op" "create" \
        "workspace_id" "$workspace_id_resolved" \
        "title" "$title_raw" \
        "model" "$model_raw")
      if ! sa_json_success "$thread_response"; then
        return 1
      fi
      conversation_id_resolved=$(sa_json_query "$thread_response" '((data.get("session") or {}).get("id") or "")')
      if [ -z "$conversation_id_resolved" ]; then
        return 1
      fi
      sa_append_change "{\"step\":\"thread\",\"status\":\"created\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
      return 0
    }

    sa_apply_archive_thread() {
      archive_response=$(sa_call_action "control_plane_sessions" \
        "op" "archive" \
        "workspace_id" "$workspace_id_resolved" \
        "conversation_id" "$conversation_id_resolved")
      if ! sa_json_success "$archive_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"thread\",\"status\":\"archived\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
      return 0
    }

    sa_apply_ensure_automation() {
      if [ -n "$automation_id_resolved" ]; then
        upsert_response=$(sa_call_action "control_plane_automations" \
          "op" "upsert" \
          "automation_id" "$automation_id_resolved" \
          "name" "$name_raw" \
          "workspace_id" "$workspace_id_resolved" \
          "conversation_id" "$conversation_id_resolved" \
          "prompt" "$prompt_raw" \
          "schedule_kind" "$schedule_kind_raw" \
          "schedule_value" "$schedule_value_raw" \
          "enabled" "$enabled_raw" \
          "allow_self_reschedule" "$allow_self_reschedule_raw")
        if ! sa_json_success "$upsert_response"; then
          return 1
        fi
        sa_append_change "{\"step\":\"automation\",\"status\":\"updated\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
        return 0
      fi
      upsert_response=$(sa_call_action "control_plane_automations" \
        "op" "upsert" \
        "name" "$name_raw" \
        "workspace_id" "$workspace_id_resolved" \
        "conversation_id" "$conversation_id_resolved" \
        "prompt" "$prompt_raw" \
        "schedule_kind" "$schedule_kind_raw" \
        "schedule_value" "$schedule_value_raw" \
        "enabled" "$enabled_raw" \
        "allow_self_reschedule" "$allow_self_reschedule_raw")
      if ! sa_json_success "$upsert_response"; then
        return 1
      fi
      automation_id_resolved=$(sa_json_query "$upsert_response" '((data.get("automation") or {}).get("id") or "")')
      if [ -z "$automation_id_resolved" ]; then
        return 1
      fi
      sa_append_change "{\"step\":\"automation\",\"status\":\"created\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
      return 0
    }

    sa_apply_toggle_automation() {
      toggle_response=$(sa_call_action "control_plane_automations" \
        "op" "toggle" \
        "automation_id" "$automation_id_resolved" \
        "enabled" "$enabled_raw")
      if ! sa_json_success "$toggle_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"automation\",\"status\":\"toggled\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
      return 0
    }

    sa_apply_run_automation_now() {
      run_response=$(sa_call_action "control_plane_automations" \
        "op" "run-now" \
        "automation_id" "$automation_id_resolved")
      if ! sa_json_success "$run_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"automation\",\"status\":\"run-now\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
      return 0
    }

    sa_apply_delete_automation() {
      delete_response=$(sa_call_action "control_plane_automations" \
        "op" "delete" \
        "automation_id" "$automation_id_resolved")
      if ! sa_json_success "$delete_response"; then
        return 1
      fi
      sa_append_change "{\"step\":\"automation\",\"status\":\"deleted\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
      return 0
    }

    operation=$(trim "$(param "operation")")
    workspace_id_raw=$(trim "$(param "workspace_id")")
    conversation_id_raw=$(trim "$(param "conversation_id")")
    automation_id_raw=$(trim "$(param "automation_id")")
    path_raw=$(trim "$(param "path")")
    name_raw=$(trim "$(param "name")")
    title_raw=$(trim "$(param "title")")
    model_raw=$(trim "$(param "model")")
    prompt_raw=$(param "prompt")
    schedule_kind_raw=$(trim "$(param "schedule_kind")")
    schedule_value_raw=$(trim "$(param "schedule_value")")
    command_exec_mode_raw=$(trim "$(param "command_exec_mode")")
    enabled_raw=$(trim "$(param "enabled")")
    allow_self_reschedule_raw=$(trim "$(param "allow_self_reschedule")")
    dry_run_raw=$(trim "$(param "dry_run")")
    confirm_token=$(trim "$(param "confirm_token")")
    idempotency_key=$(trim "$(param "idempotency_key")")

    if ! self_actuation_action_valid "$operation"; then
      emit_error "invalid operation"
      exit 0
    fi
    if [ "$operation" = "read_state" ]; then
      emit_error "read_state is not supported by orchestrate"
      exit 0
    fi

    if [ -z "$enabled_raw" ]; then
      enabled_raw="1"
    fi
    enabled_norm=$(normalize_toggle_01_value "$enabled_raw")
    if [ -z "$enabled_norm" ]; then
      emit_error "invalid enabled value"
      exit 0
    fi
    enabled_raw=$enabled_norm

    if [ -z "$allow_self_reschedule_raw" ]; then
      allow_self_reschedule_raw="0"
    fi
    allow_self_reschedule_norm=$(normalize_toggle_01_value "$allow_self_reschedule_raw")
    if [ -z "$allow_self_reschedule_norm" ]; then
      emit_error "invalid allow_self_reschedule value"
      exit 0
    fi
    allow_self_reschedule_raw=$allow_self_reschedule_norm

    dry_run_value=$(normalize_toggle_01_value "$dry_run_raw")
    if [ -z "$dry_run_value" ]; then
      dry_run_value="0"
    fi

    if [ -n "$workspace_id_raw" ] && ! valid_workspace_id "$workspace_id_raw"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -n "$conversation_id_raw" ] && ! valid_id "$conversation_id_raw"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -n "$automation_id_raw" ] && ! valid_id "$automation_id_raw"; then
      emit_error "invalid automation_id"
      exit 0
    fi
    if [ -n "$schedule_kind_raw" ] && [ -z "$(automation_schedule_kind_value "$schedule_kind_raw")" ]; then
      emit_error "invalid schedule_kind"
      exit 0
    fi
    if [ -n "$command_exec_mode_raw" ] && [ -z "$(normalize_command_exec_mode_value "$command_exec_mode_raw")" ]; then
      emit_error "invalid command_exec_mode"
      exit 0
    fi

    workspace_id_resolved=$(sa_resolve_workspace_id)
    conversation_id_resolved=$(sa_resolve_conversation_id)
    automation_id_resolved=$(sa_resolve_automation_id)

    if ! sa_validate_operation_inputs; then
      exit 0
    fi

    confirm_payload=$(cat <<EOF
operation=$operation
workspace_id=$workspace_id_resolved
conversation_id=$conversation_id_resolved
automation_id=$automation_id_resolved
path=$path_raw
name=$name_raw
title=$title_raw
model=$model_raw
prompt=$(trim "$prompt_raw")
schedule_kind=$schedule_kind_raw
schedule_value=$schedule_value_raw
enabled=$enabled_raw
allow_self_reschedule=$allow_self_reschedule_raw
EOF
)
    expected_confirm_token=$(self_actuation_confirm_token_for_payload "$confirm_payload")

    changes_json=""
    case "$operation" in
      ensure_workspace)
        if [ -n "$workspace_id_resolved" ]; then
          sa_append_change "{\"step\":\"workspace\",\"status\":\"exists\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        else
          sa_append_change "{\"step\":\"workspace\",\"status\":\"create\",\"path\":\"$(json_escape "$path_raw")\"}"
        fi
        ;;
      rename_workspace)
        sa_append_change "{\"step\":\"workspace\",\"status\":\"rename\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        ;;
      delete_workspace)
        sa_append_change "{\"step\":\"workspace\",\"status\":\"delete\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        ;;
      ensure_thread)
        if [ -n "$conversation_id_resolved" ]; then
          sa_append_change "{\"step\":\"thread\",\"status\":\"exists\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
        else
          sa_append_change "{\"step\":\"thread\",\"status\":\"create\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        fi
        ;;
      archive_thread)
        sa_append_change "{\"step\":\"thread\",\"status\":\"archive\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
        ;;
      ensure_automation)
        if [ -n "$automation_id_resolved" ]; then
          sa_append_change "{\"step\":\"automation\",\"status\":\"update\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
        else
          sa_append_change "{\"step\":\"automation\",\"status\":\"create\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        fi
        ;;
      toggle_automation)
        sa_append_change "{\"step\":\"automation\",\"status\":\"toggle\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
        ;;
      run_automation_now)
        sa_append_change "{\"step\":\"automation\",\"status\":\"run-now\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
        ;;
      delete_automation)
        sa_append_change "{\"step\":\"automation\",\"status\":\"delete\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
        ;;
      bootstrap_workspace_stack)
        if [ -n "$workspace_id_resolved" ]; then
          sa_append_change "{\"step\":\"workspace\",\"status\":\"exists\",\"workspace_id\":\"$(json_escape "$workspace_id_resolved")\"}"
        else
          sa_append_change "{\"step\":\"workspace\",\"status\":\"create\",\"path\":\"$(json_escape "$path_raw")\"}"
        fi
        if [ -n "$title_raw" ] || [ -n "$conversation_id_resolved" ]; then
          if [ -n "$conversation_id_resolved" ]; then
            sa_append_change "{\"step\":\"thread\",\"status\":\"exists\",\"conversation_id\":\"$(json_escape "$conversation_id_resolved")\"}"
          else
            sa_append_change "{\"step\":\"thread\",\"status\":\"create\"}"
          fi
        fi
        if [ -n "$name_raw" ] || [ -n "$automation_id_resolved" ]; then
          if [ -n "$automation_id_resolved" ]; then
            sa_append_change "{\"step\":\"automation\",\"status\":\"update\",\"automation_id\":\"$(json_escape "$automation_id_resolved")\"}"
          else
            sa_append_change "{\"step\":\"automation\",\"status\":\"create\"}"
          fi
        fi
        ;;
    esac

    if [ "$dry_run_value" = "1" ]; then
      self_actuation_audit_append "orchestrate" "$operation" "$workspace_id_resolved" "$conversation_id_resolved" "$automation_id_resolved" "preview" "preview generated" "$idempotency_key" "$expected_confirm_token"
      printf '{"success":true,"mode":"preview","operation":"%s","confirm_token":"%s","confirmation_required":"1","workspace_id":"%s","conversation_id":"%s","automation_id":"%s","planned_changes":[%s]}\n' \
        "$(json_escape "$operation")" \
        "$(json_escape "$expected_confirm_token")" \
        "$(json_escape "$workspace_id_resolved")" \
        "$(json_escape "$conversation_id_resolved")" \
        "$(json_escape "$automation_id_resolved")" \
        "$changes_json"
      exit 0
    fi

    if [ -n "$idempotency_key" ]; then
      if ! self_actuation_idempotency_key_valid "$idempotency_key"; then
        emit_error "invalid idempotency_key"
        exit 0
      fi
      existing_idempotent_payload=$(self_actuation_idempotency_get "$idempotency_key" 2>/dev/null || true)
      if [ -n "$existing_idempotent_payload" ]; then
        if command -v python3 >/dev/null 2>&1; then
          JSON_PAYLOAD=$existing_idempotent_payload python3 - <<'PY'
import json
import os
payload = os.environ.get("JSON_PAYLOAD", "")
data = json.loads(payload)
if isinstance(data, dict):
    data["idempotent_hit"] = "1"
print(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
PY
          exit 0
        fi
        printf '%s\n' "$existing_idempotent_payload"
        exit 0
      fi
    fi

    if [ -z "$confirm_token" ] || [ "$confirm_token" != "$expected_confirm_token" ]; then
      sa_emit_error_with_audit "confirm_token mismatch; run with dry_run=1 and use returned confirm_token" "blocked-confirm-token"
    fi

    if ! self_actuation_policy_allows "$operation" "$workspace_id_resolved"; then
      sa_emit_error_with_audit "operation blocked by self-actuation policy" "blocked-policy"
    fi

    self_actuation_audit_append "orchestrate" "$operation" "$workspace_id_resolved" "$conversation_id_resolved" "$automation_id_resolved" "apply-start" "apply started" "$idempotency_key" "$expected_confirm_token"

    apply_ok=0
    case "$operation" in
      ensure_workspace)
        sa_apply_ensure_workspace && apply_ok=1
        ;;
      rename_workspace)
        sa_apply_rename_workspace && apply_ok=1
        ;;
      delete_workspace)
        sa_apply_delete_workspace && apply_ok=1
        ;;
      ensure_thread)
        sa_apply_ensure_thread && apply_ok=1
        ;;
      archive_thread)
        sa_apply_archive_thread && apply_ok=1
        ;;
      ensure_automation)
        sa_apply_ensure_automation && apply_ok=1
        ;;
      toggle_automation)
        sa_apply_toggle_automation && apply_ok=1
        ;;
      run_automation_now)
        sa_apply_run_automation_now && apply_ok=1
        ;;
      delete_automation)
        sa_apply_delete_automation && apply_ok=1
        ;;
      bootstrap_workspace_stack)
        apply_ok=1
        sa_apply_ensure_workspace || apply_ok=0
        if [ "$apply_ok" -eq 1 ] && [ -n "$title_raw" ]; then
          conversation_id_resolved=$(sa_resolve_conversation_id)
          sa_apply_ensure_thread || apply_ok=0
        fi
        if [ "$apply_ok" -eq 1 ] && [ -n "$name_raw" ] && [ -n "$(trim "$prompt_raw")" ] && [ -n "$schedule_kind_raw" ] && [ -n "$schedule_value_raw" ]; then
          automation_id_resolved=$(sa_resolve_automation_id)
          sa_apply_ensure_automation || apply_ok=0
        fi
        ;;
    esac

    if [ "$apply_ok" -ne 1 ]; then
      sa_emit_error_with_audit "operation failed during apply" "apply-failed"
    fi

    result_payload=$(printf '{"success":true,"mode":"apply","operation":"%s","confirm_token":"%s","workspace_id":"%s","conversation_id":"%s","automation_id":"%s","idempotency_key":"%s","idempotent_hit":"0","changes":[%s]}' \
      "$(json_escape "$operation")" \
      "$(json_escape "$expected_confirm_token")" \
      "$(json_escape "$workspace_id_resolved")" \
      "$(json_escape "$conversation_id_resolved")" \
      "$(json_escape "$automation_id_resolved")" \
      "$(json_escape "$idempotency_key")" \
      "$changes_json")

    if [ -n "$idempotency_key" ]; then
      self_actuation_idempotency_put "$idempotency_key" "$result_payload" || true
    fi
    self_actuation_audit_append "orchestrate" "$operation" "$workspace_id_resolved" "$conversation_id_resolved" "$automation_id_resolved" "apply-ok" "apply complete" "$idempotency_key" "$expected_confirm_token"
    printf '%s\n' "$result_payload"
    exit 0
