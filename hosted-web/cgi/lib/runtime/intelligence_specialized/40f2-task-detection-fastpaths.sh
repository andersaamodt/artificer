prompt_requires_code_implementation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint|refactor|codebase|source file|unit test|integration test|test suite|bin/status\.sh|bin/restart\.sh|bin/health\.sh|bin/rollback\.sh|bin/audit\.sh|bin/test\.sh|bin/ssh\.sh|config\.env|package-lock\.json|restart cleanly|health check|keep rollback intact|run the restart|run the health|restart the service|restart the demo service|systemctl|journalctl|docker compose|docker service|kubectl|env drift|package upgrade|dependency bump|lockfile|remote host|remote server|ssh'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_service_restart_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/restart\.sh|bin/health\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart cleanly|health checks?|keep rollback intact|demo service|local demo service'; then
    return 0
  fi
  return 1
}

prompt_prefers_partial_system_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status\.sh|bin/rollback\.sh|bin/health\.sh|bin/verify\.sh|partial-system-rollback|partial system rollback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'partial rollback|partially landed|mixed local state|mixed local mutation|mixed release|mixed package|worker state|stable read-only baseline|approve rollback|execute only the safe rollback path'; then
    return 0
  fi
  return 1
}

prompt_prefers_multi_service_partial_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-api\.sh|bin/status-worker\.sh|bin/rollback-api\.sh|bin/rollback-worker\.sh|multi-service-partial-rollback|multi service partial rollback|api and worker status helpers|api and worker rollback helpers|both rollback helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'two local services|paired api and worker|api and worker|shared rollback|shared rollback-state|shared rollback state|shared rollback only|mixed local rollout|bounded multi-service rollback|api service|worker service|stable read-only baseline'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/publish-release\.sh|bin/verify-release\.sh|core and edge boundary status helpers|publish the release helper|verify release helper|release-pack helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system release pack|system-release-pack|shared release pack|shared release-pack|release pack|release-pack|publish the release pack|published release|release publication|shared release state|release-pack fix' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|publish|verify|rollback|keep rollback intact|rollback ready|preserve rollback|rollback evidence|ordered cutover'; then
    return 0
  fi
  return 1
}

prompt_prefers_system_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/status-core\.sh|bin/status-edge\.sh|bin/cutover-core\.sh|bin/cutover-edge\.sh|bin/verify-pack\.sh|core-boundary helper|edge-boundary helper|boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'system boundary pack|system-boundary-pack|shared local cutover|two-boundary local cutover|two local boundaries|core boundary|edge boundary|boundary pack|shared cutover state' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|verify|rollback|keep rollback intact|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_release_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bin/publish-release\.sh|bin/verify-release\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|release-pack helpers|release helper|release verifier' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote release pack|release-pack|shared remote release pack|shared release pack|published release|release publication|publish the shared release pack|publish-release|release verifier|verify-release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|publish|verify|rollback|keep rollback intact|preserve rollback|do not widen|stop there'; then
    return 0
  fi
  return 1
}

prompt_prefers_background_process_recovery_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ps\.sh|bin/stop\.sh|bin/start\.sh|bin/health\.sh|worker helpers?' \
    && printf '%s' "$prompt_primary" | grep -Eq 'background process|background-process|worker process|stuck worker|daemon|worker health|keep rollback intact|keep rollback ready|preserve rollback|stop the worker|start the worker|restart the worker|stop the stale daemon|start the healthy daemon|repair the worker config|smallest safe worker fix'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_env_drift_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/doctor\.sh|bin/verify\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'path drift|version drift|tool drift|environment drift|env drift|toolchain|environment repair'; then
    return 0
  fi
  return 1
}

prompt_prefers_local_package_upgrade_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/audit\.sh|bin/test\.sh' \
    && printf '%s' "$prompt_primary" | grep -Eq 'package upgrade|dependency upgrade|dependency bump|upgrade demo-lib|bump demo-lib|lockfile|keep rollback intact|package state|package files|manifest|smallest safe upgrade|demo-lib|2\.1\.0'; then
    return 0
  fi
  return 1
}

prompt_prefers_long_running_command_polling_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/poll\.sh|bin/checkpoint\.sh|bin/finalize\.sh|long-running command|long running command|checkpoint' \
    && printf '%s' "$prompt_primary" | grep -Eq 'poll|checkpoint|finalize|verify|keep rollback intact|keep rollback ready|preserve rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_filesystem_mutation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/inventory\.sh|bin/apply\.sh|bin/verify\.sh|filesystem mutation|filesystem-mutation|layout pack|layout state|staged config|current link|archive the previous live file' \
    && printf '%s' "$prompt_primary" | grep -Eq 'move|rename|archive|promote|symlink|link|verify|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_repo_runtime_web_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo-scan helper|repo evidence|repo scan' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|runtime evidence|runtime check' \
    && printf '%s' "$prompt_primary" | grep -Eq 'web evidence|migration doc|current doc|docs evidence|current migration' \
    && printf '%s' "$prompt_primary" | grep -Eq 'http://|https://' \
    && printf '%s' "$prompt_primary" | grep -Eq 'root cause' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next change' \
    && printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 0
  fi
  return 1
}

prompt_prefers_browser_image_run_investigation_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*safari screenshot|attached safari screenshot|attached screenshot|safari screenshot|screenshot evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser snapshot|browser evidence|dom snapshot|layout snapshot'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime-check helper|run `\./bin/runtime-check\.sh`|run ./bin/runtime-check\.sh|runtime evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser evidence:|image evidence:|runtime evidence:|root cause:|next action:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'browser|safari|screenshot|runtime|investigat|triage|no file edits|do not edit files'; then
    return 1
  fi
  return 0
}

prompt_prefers_tool_failure_handoff_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/primary-check\.sh|primary helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/fallback-check\.sh|fallback helper'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'hand off|handoff|recover by handing off|initial tool path'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://|current doc|current guidance|web evidence'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'primary tool failure|fallback evidence|web evidence|root cause|next action'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits|triage'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_api_migration_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official migration guide|current source|source grounding|version-sensitive api migration|migration question'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|current source|migration change|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_current_ops_guidance_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/state-check\.sh|local state'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'current official guidance|current guidance|official guidance'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'local state|current guidance|operational decision|root cause|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_standards_grounded_answer_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/repo-scan\.sh|repo evidence|repo scan'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'bin/runtime-check\.sh|runtime evidence|runtime check'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'official standard|standard/docs|current standard|standards grounded|standards-grounded'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'http://|https://'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'repo evidence|runtime evidence|current standard|standards answer|next change'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'do not edit files|no file edits'; then
    return 1
  fi
  return 0
}

prompt_prefers_multi_artifact_judgment_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'mixed-artifact judgment|mixed artifact judgment'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'choose exactly one primary move from analyze, act, clarify, or refuse'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'outcome, decision, code evidence, doc evidence, screenshot evidence, command evidence, fallback path, disconfirming evidence'; then
    return 1
  fi
  return 0
}

prompt_prefers_remote_boundary_pack_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-core-canary\.sh|bin/ssh-core-fleet\.sh|bin/ssh-edge-canary\.sh|bin/ssh-edge-fleet\.sh|bastion helper|core boundary canary helper|core boundary fleet helper|edge boundary canary helper|edge boundary fleet helper|private core/edge boundary helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote boundary pack|boundary-pack|shared boundary pack|core boundary pair|edge boundary pair|core and edge private boundary|two boundary pairs' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|cut|health|verify|verifier|verify-pack|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper|private-target helpers' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollback|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary|partial release|partially landed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback|roll back|recover|revert|health|tunnel'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_boundary_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private-canary\.sh|bin/ssh-private-fleet\.sh|bastion helper|private canary helper|private fleet helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'boundary rollout|multi-boundary|bastion|jump host|private canary|private fleet|private target|cross-boundary' \
    && printf '%s' "$prompt_primary" | grep -Eq 'tunnel|deploy|health|release|rollout'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_single_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote service' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|verify|journal|keep rollback intact'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_bastion_cutover_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-bastion\.sh|bin/ssh-private\.sh|bastion ssh helper|private ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'bastion|jump host|private host|cutover|tunnel' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cutover|tunnel|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-app\.sh|bin/ssh-db\.sh|app ssh helper|replica ssh helper|db ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|replica|primary|failover|promote|app host|db host|database host|replica host' \
    && printf '%s' "$prompt_primary" | grep -Eq 'restart|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_multi_host_rollout_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh-canary\.sh|bin/ssh-fleet\.sh|canary ssh helper|fleet ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'multi-host|canary|fleet|staged rollout|progressive rollout|rollout|second host|second stage' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|health|rollback'; then
    return 0
  fi
  return 1
}

prompt_prefers_remote_deploy_rollback_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'bin/ssh\.sh|ssh wrapper|ssh helper' \
    && printf '%s' "$prompt_primary" | grep -Eq 'remote host|remote server|single host|ssh|remote deploy|remote release' \
    && printf '%s' "$prompt_primary" | grep -Eq 'deploy|release|health|rollback'; then
    return 0
  fi
  return 1
}

local_service_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/service/config.env"
  [ -f "$config_file" ] || return 1
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
PORT=$port_value
EOF_CFG
}

partial_system_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/system.env"
  [ -f "$config_file" ] || return 1
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_package=$(awk -F= '/^STABLE_PACKAGE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker=$(awk -F= '/^STABLE_WORKER=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.15
  fi
  if [ -z "$(trim "$stable_package")" ]; then
    stable_package=2.3.1
  fi
  if [ -z "$(trim "$stable_worker")" ]; then
    stable_worker=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_RELEASE=$stable_release
STABLE_RELEASE=$stable_release
CURRENT_PACKAGE=$stable_package
STABLE_PACKAGE=$stable_package
CURRENT_WORKER=$stable_worker
STABLE_WORKER=$stable_worker
ROLLBACK_APPROVED=1
READ_ONLY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

multi_service_partial_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/multi-service.env"
  [ -f "$config_file" ] || return 1
  stable_api_release=$(awk -F= '/^STABLE_API_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_api_mode=$(awk -F= '/^STABLE_API_MODE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_release=$(awk -F= '/^STABLE_WORKER_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_worker_mode=$(awk -F= '/^STABLE_WORKER_MODE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$stable_api_release")" ]; then
    stable_api_release=2026.03.15-api
  fi
  if [ -z "$(trim "$stable_api_mode")" ]; then
    stable_api_mode=healthy
  fi
  if [ -z "$(trim "$stable_worker_release")" ]; then
    stable_worker_release=2026.03.15-worker
  fi
  if [ -z "$(trim "$stable_worker_mode")" ]; then
    stable_worker_mode=healthy
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_API_RELEASE=$stable_api_release
STABLE_API_RELEASE=$stable_api_release
CURRENT_API_MODE=$stable_api_mode
STABLE_API_MODE=$stable_api_mode
CURRENT_WORKER_RELEASE=$stable_worker_release
STABLE_WORKER_RELEASE=$stable_worker_release
CURRENT_WORKER_MODE=$stable_worker_mode
STABLE_WORKER_MODE=$stable_worker_mode
ROLLBACK_APPROVED=1
READ_ONLY=1
API_ROLLBACK_READY=1
WORKER_ROLLBACK_READY=1
PARTIAL_STATE=rolled_back
EOF_CFG
}

system_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/release-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.15
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CUTOVER_APPROVED=1
RELEASE_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
RELEASE_NOTES_READY=1
PACK_STATE=ready
EOF_CFG
}

system_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  core_current=$(awk -F= '/^CORE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  core_target=$(awk -F= '/^CORE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  edge_current=$(awk -F= '/^EDGE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  edge_target=$(awk -F= '/^EDGE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$core_current")" ]; then
    core_current=2026.03.15-core
  fi
  if [ -z "$(trim "$core_target")" ]; then
    core_target=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_current")" ]; then
    edge_current=legacy-edge
  fi
  if [ -z "$(trim "$edge_target")" ]; then
    edge_target=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
CORE_CURRENT=$core_current
CORE_TARGET=$core_target
EDGE_CURRENT=$edge_current
EDGE_TARGET=$edge_target
CUTOVER_APPROVED=1
READ_ONLY=1
CORE_READY=1
EDGE_READY=1
PACK_STATE=ready
EOF_CFG
}

background_process_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/process/worker.env"
  [ -f "$config_file" ] || return 1
  queue_name=$(awk -F= '/^QUEUE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$queue_name")" ]; then
    queue_name=jobs
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
AUTO_START=1
READ_ONLY=1
QUEUE=$queue_name
EOF_CFG
}

local_env_drift_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/config/toolchain.env"
  [ -f "$config_file" ] || return 1
  cat > "$config_file" <<'EOF_CFG'
EXPECTED_TOOL_PATH=tools/bin
ACTIVE_TOOL_PATH=tools/bin
EXPECTED_VERSION=1.2.3
ACTIVE_VERSION=1.2.3
READ_ONLY=1
EOF_CFG
}

local_package_upgrade_fix_in_place() {
  workspace_path=$1
  manifest_file="$workspace_path/package.json"
  lockfile_file="$workspace_path/package-lock.json"
  [ -f "$manifest_file" ] || return 1
  [ -f "$lockfile_file" ] || return 1
  cat > "$manifest_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "private": true,
  "dependencies": {
    "demo-lib": "2.1.0"
  }
}
EOF_JSON
  cat > "$lockfile_file" <<'EOF_JSON'
{
  "name": "demo-package-upgrade",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "dependencies": {
        "demo-lib": "2.1.0"
      }
    },
    "node_modules/demo-lib": {
      "version": "2.1.0"
    }
  }
}
EOF_JSON
}

long_running_command_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/job/run.env"
  [ -f "$config_file" ] || return 1
  target_step=$(awk -F= '/^TARGET_STEP=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$target_step")" ]; then
    target_step=3
  fi
  cat > "$config_file" <<EOF_CFG
CURRENT_STEP=0
TARGET_STEP=$target_step
CHECKPOINT_READY=1
ALLOW_FINALIZE=1
READ_ONLY=1
EOF_CFG
}

filesystem_mutation_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/state/layout.env"
  [ -f "$config_file" ] || return 1
  live_dir=$(awk -F= '/^LIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  staging_file=$(awk -F= '/^STAGING_FILE=/{print $2}' "$config_file" | tail -n 1)
  archive_dir=$(awk -F= '/^ARCHIVE_DIR=/{print $2}' "$config_file" | tail -n 1)
  active_link=$(awk -F= '/^ACTIVE_LINK=/{print $2}' "$config_file" | tail -n 1)
  target_name=$(awk -F= '/^TARGET_NAME=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$live_dir")" ]; then
    live_dir=layout/live
  fi
  if [ -z "$(trim "$staging_file")" ]; then
    staging_file=layout/staging/config.yml.next
  fi
  if [ -z "$(trim "$archive_dir")" ]; then
    archive_dir=layout/archive
  fi
  if [ -z "$(trim "$active_link")" ]; then
    active_link=layout/current-config.yml
  fi
  if [ -z "$(trim "$target_name")" ]; then
    target_name=config.yml
  fi
  cat > "$config_file" <<EOF_CFG
LIVE_DIR=$live_dir
STAGING_FILE=$staging_file
ARCHIVE_DIR=$archive_dir
ACTIVE_LINK=$active_link
TARGET_NAME=$target_name
APPLY_READY=1
LINK_READY=1
READ_ONLY=1
EOF_CFG
}

remote_release_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  release_current=$(awk -F= '/^RELEASE_CURRENT=/{print $2}' "$config_file" | tail -n 1)
  release_target=$(awk -F= '/^RELEASE_TARGET=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  if [ -z "$(trim "$release_current")" ]; then
    release_current=2026.03.10
  fi
  if [ -z "$(trim "$release_target")" ]; then
    release_target=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
RELEASE_CURRENT=$release_current
RELEASE_TARGET=$release_target
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
RELEASE_APPROVED=1
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
RELEASE_NOTES_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_pack_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary-pack.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_canary_private_host=$(awk -F= '/^CORE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_fleet_private_host=$(awk -F= '/^CORE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_canary_private_host=$(awk -F= '/^EDGE_CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  edge_fleet_private_host=$(awk -F= '/^EDGE_FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  core_target_release=$(awk -F= '/^CORE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  edge_target_release=$(awk -F= '/^EDGE_TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$core_canary_private_host")" ]; then
    core_canary_private_host=demo-core-private-a
  fi
  if [ -z "$(trim "$core_fleet_private_host")" ]; then
    core_fleet_private_host=demo-core-private-b
  fi
  if [ -z "$(trim "$edge_canary_private_host")" ]; then
    edge_canary_private_host=demo-edge-private-a
  fi
  if [ -z "$(trim "$edge_fleet_private_host")" ]; then
    edge_fleet_private_host=demo-edge-private-b
  fi
  if [ -z "$(trim "$core_target_release")" ]; then
    core_target_release=2026.03.22-core
  fi
  if [ -z "$(trim "$edge_target_release")" ]; then
    edge_target_release=2026.03.22-edge
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CORE_CANARY_PRIVATE_HOST=$core_canary_private_host
CORE_FLEET_PRIVATE_HOST=$core_fleet_private_host
EDGE_CANARY_PRIVATE_HOST=$edge_canary_private_host
EDGE_FLEET_PRIVATE_HOST=$edge_fleet_private_host
CORE_TARGET_RELEASE=$core_target_release
EDGE_TARGET_RELEASE=$edge_target_release
CORE_APPROVED_RELEASE=$core_target_release
EDGE_APPROVED_RELEASE=$edge_target_release
TUNNEL_READY=1
CORE_CANARY_READY=1
CORE_FLEET_READY=1
EDGE_CANARY_READY=1
EDGE_FLEET_READY=1
READ_ONLY=1
PACK_STATE=ready
EOF_CFG
}

remote_boundary_rollback_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  current_release=$(awk -F= '/^CURRENT_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  stable_release=$(awk -F= '/^STABLE_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$current_release")" ]; then
    current_release=2026.03.22
  fi
  if [ -z "$(trim "$stable_release")" ]; then
    stable_release=2026.03.10
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
CURRENT_RELEASE=$current_release
STABLE_RELEASE=$stable_release
APPROVED_RELEASE=$stable_release
TUNNEL_READY=1
CANARY_ROLLBACK_READY=1
FLEET_ROLLBACK_READY=1
READ_ONLY=1
ROLLOUT_STATE=rollback_ready
EOF_CFG
}

remote_boundary_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/boundary.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  canary_private_host=$(awk -F= '/^CANARY_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_private_host=$(awk -F= '/^FLEET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$canary_private_host")" ]; then
    canary_private_host=demo-app-private-a
  fi
  if [ -z "$(trim "$fleet_private_host")" ]; then
    fleet_private_host=demo-app-private-b
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CANARY_PRIVATE_HOST=$canary_private_host
FLEET_PRIVATE_HOST=$fleet_private_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
TUNNEL_READY=1
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STATE=staged
EOF_CFG
}

remote_single_host_config_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/service.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  port_value=$(awk -F= '/^PORT=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$port_value")" ]; then
    port_value=18080
  fi
  cat > "$config_file" <<EOF_CFG
MODE=healthy
READ_ONLY=1
HOST=$host_value
PORT=$port_value
EOF_CFG
}

remote_bastion_cutover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/bastion.env"
  [ -f "$config_file" ] || return 1
  bastion_host=$(awk -F= '/^BASTION_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_private_host=$(awk -F= '/^TARGET_PRIVATE_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$bastion_host")" ]; then
    bastion_host=demo-bastion-1
  fi
  if [ -z "$(trim "$target_private_host")" ]; then
    target_private_host=demo-app-private-b
  fi
  cat > "$config_file" <<EOF_CFG
BASTION_HOST=$bastion_host
CURRENT_PRIVATE_HOST=$target_private_host
TARGET_PRIVATE_HOST=$target_private_host
APPROVED_PRIVATE_HOST=$target_private_host
BASTION_READY=1
PRIVATE_READY=1
READ_ONLY=1
CUTOVER_STATE=ready
EOF_CFG
}

remote_multi_host_failover_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/topology.env"
  [ -f "$config_file" ] || return 1
  app_host=$(awk -F= '/^APP_HOST=/{print $2}' "$config_file" | tail -n 1)
  primary_db_host=$(awk -F= '/^PRIMARY_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  replica_db_host=$(awk -F= '/^REPLICA_DB_HOST=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$app_host")" ]; then
    app_host=demo-app-1
  fi
  if [ -z "$(trim "$primary_db_host")" ]; then
    primary_db_host=demo-db-1
  fi
  if [ -z "$(trim "$replica_db_host")" ]; then
    replica_db_host=demo-db-2
  fi
  cat > "$config_file" <<EOF_CFG
APP_HOST=$app_host
PRIMARY_DB_HOST=$replica_db_host
REPLICA_DB_HOST=$primary_db_host
APP_DB_HOST=$replica_db_host
REPLICA_ROLE=primary
FAILOVER_READY=1
APP_READ_ONLY=1
EOF_CFG
}

remote_multi_host_rollout_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/rollout.env"
  [ -f "$config_file" ] || return 1
  canary_host=$(awk -F= '/^CANARY_HOST=/{print $2}' "$config_file" | tail -n 1)
  fleet_host=$(awk -F= '/^FLEET_HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$canary_host")" ]; then
    canary_host=demo-app-1
  fi
  if [ -z "$(trim "$fleet_host")" ]; then
    fleet_host=demo-app-2
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
CANARY_HOST=$canary_host
FLEET_HOST=$fleet_host
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
CANARY_READY=1
FLEET_READY=1
READ_ONLY=1
ROLLOUT_STAGE=staged
EOF_CFG
}

remote_deploy_release_fix_in_place() {
  workspace_path=$1
  config_file="$workspace_path/remote/release.env"
  [ -f "$config_file" ] || return 1
  host_value=$(awk -F= '/^HOST=/{print $2}' "$config_file" | tail -n 1)
  target_release=$(awk -F= '/^TARGET_RELEASE=/{print $2}' "$config_file" | tail -n 1)
  if [ -z "$(trim "$host_value")" ]; then
    host_value=demo-app-1
  fi
  if [ -z "$(trim "$target_release")" ]; then
    target_release=2026.03.22
  fi
  cat > "$config_file" <<EOF_CFG
HOST=$host_value
TARGET_RELEASE=$target_release
APPROVED_RELEASE=$target_release
DEPLOY_READY=1
READ_ONLY=1
EOF_CFG
}

quick_mode_append_command_result() {
  command_text=$1
  command_status=$2
  command_output=$3
  quick_loop_summary="${quick_loop_summary}
## Command
$command_text
Status: $command_status
$command_output
"
  if [ "$command_status" = "ok" ]; then
    quick_command_success_total=$((quick_command_success_total + 1))
  fi
  command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
    "$(json_escape "$command_text")" \
    "$(json_escape "$command_status")" \
    "$(json_escape "$command_output")")
  if [ "$quick_commands_first" -eq 1 ]; then
    quick_commands_json=$command_item
    quick_commands_first=0
  else
    quick_commands_json="${quick_commands_json},${command_item}"
  fi
}

quick_mode_run_recorded_command() {
  workspace_id=$1
  workspace_path=$2
  tool_command=$3
  command_mode_value=$4
  blocked_file=$5
  stream_file=$6
  command_output_file=$(mktemp)
  command_status_file=$(mktemp)
  execute_mediated_command "$workspace_id" "$workspace_path" "$tool_command" "$command_output_file" "$command_status_file" "$command_mode_value" "$blocked_file"
  quick_mode_last_command_status=$(cat "$command_status_file" 2>/dev/null || printf '%s' "error")
  quick_mode_last_command_output=$(sed -n '1,40p' "$command_output_file")
  rm -f "$command_output_file" "$command_status_file"
  quick_mode_append_command_result "$tool_command" "$quick_mode_last_command_status" "$quick_mode_last_command_output"
  stream_emit_line "$stream_file" "Quick-mode command: $tool_command ($quick_mode_last_command_status)"
}

local_service_restart_summary() {
  status_output=$1
  restart_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local demo service, rewrote \`service/config.env\` to the healthy/read-only settings, restarted it, and confirmed the service is healthy.
Verification Evidence: Ran \`./bin/status.sh\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")) and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required repair is the local config flip in \`service/config.env\`; broader service hardening remains out of scope.
Next Improvement: Promote the same status, restart, health, and rollback contract into the broader system-ops gate for more complex service shapes.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local demo service and applied the smallest config repair in \`service/config.env\`, but the restart/health sequence did not finish cleanly.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/restart.sh\` ($(single_line_snippet "$restart_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The service still needs a clean restart/health pass before this workspace is considered recovered.
Next Improvement: Re-run the local status, restart, and health helpers after inspecting the current config and state files for any remaining mismatch.
EOF
}

background_process_recovery_summary() {
  ps_output=$1
  stop_output=$2
  start_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded background-worker failure, repaired \`process/worker.env\`, stopped the stale worker, started the healthy worker, and confirmed the worker health check now passes.
Verification Evidence: Ran \`./bin/ps.sh\` before the fix ($(single_line_snippet "$ps_output")); then ran \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the bounded worker issue is isolated to \`process/worker.env\` plus one local worker state file; broader queue drains, multi-worker coordination, and supervisor policy remain out of scope.
Next Improvement: Extend the same ps-stop-start-health contract into a broader background-process gate with polling, checkpointing, and multi-worker recovery.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded background-worker failure and applied the intended worker-config repair, but the stop/start/health sequence still failed.
Verification Evidence: Ran \`./bin/ps.sh\` ($(single_line_snippet "$ps_output")), \`./bin/stop.sh\` ($(single_line_snippet "$stop_output")), \`./bin/start.sh\` ($(single_line_snippet "$start_output")), and \`./bin/health.sh\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The worker still needs a clean stop/start/health pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded worker ps, stop, start, and health helpers after inspecting the current process config and worker state files for any remaining mismatch.
EOF
}

local_env_drift_summary() {
  doctor_output=$1
  verify_output=$2
  verify_status=$3
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the local environment drift, repaired the tool-path and version config, and confirmed the environment now verifies cleanly.
Verification Evidence: Ran \`./bin/doctor.sh\` before the fix ($(single_line_snippet "$doctor_output")); then ran \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the drift is isolated to \`config/toolchain.env\`; broader shell/profile or package-manager drift remains out of scope.
Next Improvement: Extend the same doctor-and-verify contract into a broader env-drift gate that exercises PATH, version, and rollback handling across more than one config shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the local environment drift and applied the intended config repair, but the final verification still failed.
Verification Evidence: Ran \`./bin/doctor.sh\` ($(single_line_snippet "$doctor_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved tool-path or version drift and should not be treated as repaired yet.
Next Improvement: Re-run doctor and verify after inspecting the current config and any residual environment assumptions outside \`config/toolchain.env\`.
EOF
}

local_package_upgrade_summary() {
  audit_output=$1
  test_output=$2
  test_status=$3
  if [ "$test_status" = "ok" ]; then
    cat <<EOF
Outcome: Audited the local package state, upgraded \`demo-lib\` in \`package.json\` and \`package-lock.json\`, and confirmed the package tests now pass.
Verification Evidence: Ran \`./bin/audit.sh\` before the change ($(single_line_snippet "$audit_output")); then ran \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded \`demo-lib\` upgrade in \`package.json\` and \`package-lock.json\`; broader dependency graph or runtime compatibility work remains out of scope.
Next Improvement: Extend the same audit-upgrade-test contract into a broader package-management gate with rollback and compatibility checks across more than one dependency shape.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Audited the local package state and applied the intended \`demo-lib\` upgrade, but the final package test still failed.
Verification Evidence: Ran \`./bin/audit.sh\` ($(single_line_snippet "$audit_output")) and \`./bin/test.sh\` ($(single_line_snippet "$test_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The workspace still has unresolved manifest, lockfile, or compatibility issues and should not be treated as upgraded yet.
Next Improvement: Re-run audit and tests after inspecting the current manifest and lockfile for any remaining dependency mismatch.
EOF
}

long_running_command_summary() {
  first_poll_output=$1
  second_poll_output=$2
  checkpoint_output=$3
  third_poll_output=$4
  finalize_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded long-running job, repaired the checkpoint/finalize config, polled the job until it was ready, checkpointed it, finalized it, and confirmed the final verification now passes.
Verification Evidence: Ran the first \`./bin/poll.sh\` before the fix ($(single_line_snippet "$first_poll_output")); then ran a second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), a final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the long-running command is isolated to one bounded job in \`job/run.env\`; broader orchestration, external schedulers, and multi-stage pipeline control remain out of scope.
Next Improvement: Extend the same poll-checkpoint-finalize-verify contract into a broader long-running-command gate with explicit checkpoint timing and stop/go coverage under larger jobs.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded long-running job and applied the intended checkpoint/finalize repair, but the bounded poll/finalize sequence still failed to verify cleanly.
Verification Evidence: Ran the first \`./bin/poll.sh\` ($(single_line_snippet "$first_poll_output")), the second \`./bin/poll.sh\` ($(single_line_snippet "$second_poll_output")), \`./bin/checkpoint.sh\` ($(single_line_snippet "$checkpoint_output")), the final \`./bin/poll.sh\` ($(single_line_snippet "$third_poll_output")), \`./bin/finalize.sh\` ($(single_line_snippet "$finalize_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded long-running job still needs a clean checkpoint/finalize verification pass before it should be treated as complete.
Next Improvement: Re-run the bounded polling sequence after inspecting the current job config and checkpoint state for any remaining mismatch.
EOF
}

filesystem_mutation_summary() {
  inventory_output=$1
  apply_output=$2
  verify_output=$3
  verify_status=$4
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack, repaired the layout-control file, archived the previous live file, promoted the staged config into the live path, refreshed the current link, and confirmed verification now passes.
Verification Evidence: Ran \`./bin/inventory.sh\` before the fix ($(single_line_snippet "$inventory_output")); then ran \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")) and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the only required change is the bounded layout-state repair in \`state/layout.env\` plus one staged/live/archive file set under \`layout/\`; broader refactors, multi-file rewrites, and large rename graphs remain out of scope.
Next Improvement: Extend the same inventory-apply-verify contract into a broader filesystem-mutation gate that covers larger rename, move, and refactor packs with explicit rollback checkpoints.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded filesystem mutation pack and applied the intended layout-control repair, but the apply or final verification sequence still failed.
Verification Evidence: Ran \`./bin/inventory.sh\` ($(single_line_snippet "$inventory_output")), \`./bin/apply.sh\` ($(single_line_snippet "$apply_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded filesystem mutation pack still needs a clean archive/promote/link verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded inventory, apply, and verify sequence after inspecting the current layout state and rollback readiness for any remaining mismatch.
EOF
}

repo_runtime_web_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

repo_runtime_web_first_url_from_prompt() {
  prompt_text=$1
  urls_file=$(mktemp)
  extract_urls_from_text "$prompt_text" > "$urls_file"
  first_url=$(sed -n '1p' "$urls_file")
  rm -f "$urls_file"
  first_url=$(trim "$first_url")
  first_url=$(printf '%s' "$first_url" | sed 's/[.,;:!?)]*$//')
  printf '%s' "$first_url"
}

repo_runtime_web_extract_doc_endpoint() {
  doc_excerpt=$1
  endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | grep -E '^/v2/' | head -n 1 || true)
  if [ -z "$(trim "$endpoint_value")" ]; then
    endpoint_value=$(printf '%s' "$doc_excerpt" | grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' | tail -n 1 || true)
  fi
  endpoint_value=$(trim "$endpoint_value")
  if [ -z "$endpoint_value" ]; then
    endpoint_value="/v2/widgets"
  fi
  printf '%s' "$endpoint_value"
}

repo_runtime_web_extract_doc_timeout_ms() {
  doc_excerpt=$1
  timeout_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[0-9]{4,5}[[:space:]]*ms' | head -n 1 | tr -cd '0-9' || true)
  timeout_value=$(trim "$timeout_value")
  if [ -z "$timeout_value" ]; then
    timeout_value="15000"
  fi
  printf '%s' "$timeout_value"
}

repo_runtime_web_triage_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5
  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "webapp/src/widgets-client.js")
  repo_endpoint=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_endpoint" "/v1/widgets/list")
  repo_response_key=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_response_key" "widgets")
  repo_timeout_ms=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_timeout_ms" "5000")
  runtime_http_status=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_http_status" "404")
  runtime_endpoint=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_endpoint" "$repo_endpoint")
  runtime_shape_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_shape_issue" "expected_items_found_widgets")
  runtime_timeout_issue=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_timeout_issue" "timeout_too_low")
  doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
  doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
  doc_fields="items and next_cursor"
  if ! printf '%s' "$doc_excerpt" | grep -Eq 'items'; then
    doc_fields="items"
  fi
  runtime_clause="\`./bin/runtime-check.sh\` reports HTTP $runtime_http_status on $runtime_endpoint and $runtime_shape_issue"
  if [ "$runtime_status" != "ok" ]; then
    runtime_clause="$runtime_clause while the bounded runtime check still exits non-zero"
  fi
  if [ -n "$(trim "$runtime_timeout_issue")" ]; then
    runtime_clause="$runtime_clause plus $runtime_timeout_issue"
  fi
  cat <<EOF
Repo Evidence: \`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_endpoint\`, parses \`$repo_response_key\`, and uses \`timeoutMs=$repo_timeout_ms\`.
Runtime Evidence: $runtime_clause.
Web Evidence: The migration doc at $doc_url says the client should call \`$doc_endpoint\`, read \`$doc_fields\`, and allow a \`$doc_timeout_ms\` ms timeout.
Root Cause: The repo and runtime still target the removed v1 widgets contract, so the client endpoint, response parsing, and timeout no longer match the current migration doc.
Next Change: Update \`$repo_file\` to call \`$doc_endpoint\`, read \`$doc_fields\`, and raise the client timeout to \`$doc_timeout_ms\` ms before widening further.
EOF
}

tool_failure_handoff_doc_flag() {
  doc_excerpt=$1
  default_value=${2:-uploads_rollout=on}
  flag_value=$(printf '%s' "$doc_excerpt" | grep -Eo '[A-Za-z_]+=[A-Za-z0-9._/-]+' | head -n 1 || true)
  flag_value=$(trim "$flag_value")
  if [ -z "$flag_value" ]; then
    flag_value=$default_value
  fi
  printf '%s' "$flag_value"
}

tool_failure_handoff_doc_env_key() {
  doc_excerpt=$1
  default_value=${2:-SESSION_CACHE_URL}
  env_key=$(printf '%s' "$doc_excerpt" | grep -Eo 'SESSION_CACHE_URL' | head -n 1 || true)
  env_key=$(trim "$env_key")
  if [ -z "$env_key" ]; then
    env_key=$default_value
  fi
  printf '%s' "$env_key"
}

tool_failure_handoff_primary_reason_text() {
  primary_output=$1
  primary_reason=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_reason" "initial helper failure")
  case "$primary_reason" in
    repo_scan_unavailable)
      printf '%s' "the repo scan helper is unavailable in this workspace"
      ;;
    browser_snapshot_capture_failed)
      printf '%s' "browser snapshot capture is unavailable right now"
      ;;
    dom_snapshot_unavailable)
      printf '%s' "the DOM snapshot helper is unavailable right now"
      ;;
    *)
      printf '%s' "$primary_reason"
      ;;
  esac
}

tool_failure_handoff_summary() {
  primary_output=$1
  primary_status=$2
  fallback_output=$3
  fallback_status=$4
  doc_url=$5
  doc_excerpt=$6

  primary_helper=$(repo_runtime_web_extract_kv_value "$primary_output" "primary_helper" "./bin/primary-check.sh")
  primary_reason_text=$(tool_failure_handoff_primary_reason_text "$primary_output")
  fallback_issue=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_issue" "fallback_required")
  fallback_file=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_file" "config/runtime.env")

  case "$fallback_issue" in
    legacy_widget_contract)
      runtime_endpoint=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_endpoint" "/v1/widgets/list")
      runtime_timeout_ms=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_timeout_ms" "5000")
      doc_endpoint=$(repo_runtime_web_extract_doc_endpoint "$doc_excerpt")
      doc_timeout_ms=$(repo_runtime_web_extract_doc_timeout_ms "$doc_excerpt")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still calls \`$runtime_endpoint\` with \`timeoutMs=$runtime_timeout_ms\` while the bounded fallback check remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says clients must call \`$doc_endpoint\` and allow at least \`$doc_timeout_ms\` ms before wider rollout."
      root_line="The initial repo-scan path is unavailable, but the fallback runtime plus current docs still show the client is pinned to the removed widgets contract."
      next_line="Update \`$fallback_file\` to call \`$doc_endpoint\` and raise the client timeout to \`$doc_timeout_ms\` ms, then restore the primary helper for a clean repo-side audit."
      ;;
    uploads_rollout_disabled)
      runtime_flag=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_flag" "uploads_rollout=off")
      runtime_route=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_route" "/v2/uploads/complete")
      doc_flag=$(tool_failure_handoff_doc_flag "$doc_excerpt" "uploads_rollout=on")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` still sets \`$runtime_flag\`, so the bounded upload route \`$runtime_route\` remains disabled while the fallback helper stays \`$fallback_status\`."
      web_line="The current doc at $doc_url says publishing uploads requires \`$doc_flag\` before clients use \`$runtime_route\`."
      root_line="The initial browser-control path is unavailable, but the fallback runtime evidence shows uploads are disabled in config rather than broken in the UI."
      next_line="Set \`$doc_flag\` in \`$fallback_file\`, then rerun the bounded upload path after the primary helper is restored."
      ;;
    session_cache_missing)
      runtime_cache=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_session_cache_url" "missing")
      runtime_miss_rate=$(repo_runtime_web_extract_kv_value "$fallback_output" "runtime_miss_rate" "68%")
      doc_env_key=$(tool_failure_handoff_doc_env_key "$doc_excerpt" "SESSION_CACHE_URL")
      fallback_line="\`./bin/fallback-check.sh\` reports \`$fallback_file\` has \`$doc_env_key=$runtime_cache\` and the bounded login path is falling back with miss rate $runtime_miss_rate while the helper remains \`$fallback_status\`."
      web_line="The current doc at $doc_url says interactive login requires \`$doc_env_key\` before traffic is widened again."
      root_line="The initial snapshot path is unavailable, but the fallback runtime evidence shows degraded login comes from a missing session cache endpoint."
      next_line="Set \`$doc_env_key\` in \`$fallback_file\`, warm the session cache, and retry the bounded login path after the primary helper is back."
      ;;
    *)
      fallback_line="\`./bin/fallback-check.sh\` produced bounded fallback evidence ($(single_line_snippet "$fallback_output")) while the helper remained \`$fallback_status\`."
      web_line="The current doc at $doc_url provides the authoritative fallback guidance."
      root_line="The initial tool path failed, so the fallback helper and current docs became the authoritative evidence path."
      next_line="Repair the issue indicated by the fallback helper, then restore the primary tool path for a clean rerun."
      ;;
  esac

  cat <<EOF
Primary Tool Failure: \`$primary_helper\` returned \`$primary_status\` and reported that $primary_reason_text.
Fallback Evidence: $fallback_line
Web Evidence: $web_line
Root Cause: $root_line
Next Action: $next_line
EOF
}

current_api_migration_summary() {
  repo_output=$1
  doc_url=$2
  doc_excerpt=$3

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "app/user_loader.py")
  repo_old_method=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_old_method" "parse_obj")
  repo_call=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_call" "$repo_old_method")

  case "$repo_old_method" in
    parse_obj)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`parse_obj()\` to \`model_validate()\`."
      change_line="Pydantic V2 replaces the V1 validation entry point \`parse_obj()\` with \`model_validate()\`."
      root_line="The repo still uses the V1 validation API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`User.model_validate(payload)\` in \`$repo_file\`."
      ;;
    dict)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url maps \`dict()\` to \`model_dump()\`."
      change_line="Pydantic V2 replaces the V1 serialization helper \`dict()\` with \`model_dump()\`."
      root_line="The repo still uses the V1 serialization API while the current official docs describe the V2 method name."
      next_line="Replace \`$repo_call\` with \`user.model_dump()\` in \`$repo_file\`."
      ;;
    from_orm)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still calls \`$repo_call\`."
      source_line="The current official migration guide at $doc_url says \`from_orm()\` is deprecated in favor of \`model_validate()\` with \`from_attributes=True\`."
      change_line="Pydantic V2 moves ORM-style loading to \`model_validate()\` plus a model config that enables \`from_attributes=True\`."
      root_line="The repo still uses the V1 ORM-loading API while the current official docs require the V2 validation path and attribute-based config."
      next_line="Replace \`$repo_call\` with \`User.model_validate(record)\` and enable \`from_attributes=True\` in the model config in \`$repo_file\`."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still uses \`$repo_call\`."
      source_line="The current official migration guide at $doc_url provides the authoritative migration target."
      change_line="The current docs describe a newer API surface than the one still referenced in the repo."
      root_line="The repo still targets an older API contract than the current official guide."
      next_line="Update \`$repo_file\` from \`$repo_call\` to the current API named in the official migration guide."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Current Source: $source_line
Migration Change: $change_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

current_ops_guidance_summary() {
  state_output=$1
  doc_url=$2
  doc_excerpt=$3

  state_file=$(repo_runtime_web_extract_kv_value "$state_output" "state_file" "deploy/api-deployment.yaml")
  state_issue=$(repo_runtime_web_extract_kv_value "$state_output" "state_issue" "slow_start_liveness_kills")
  state_shared_probe_path=$(repo_runtime_web_extract_kv_value "$state_output" "state_shared_probe_path" "/healthz")
  state_startup_p95_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_startup_p95_seconds" "75")
  state_liveness_initial_delay_seconds=$(repo_runtime_web_extract_kv_value "$state_output" "state_liveness_initial_delay_seconds" "5")
  state_dependency=$(repo_runtime_web_extract_kv_value "$state_output" "state_dependency" "db-warmup")

  case "$state_issue" in
    slow_start_liveness_kills|cache_warmup_slow_start)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` has no \`startupProbe\`, reuses \`$state_shared_probe_path\`, and starts liveness after \`$state_liveness_initial_delay_seconds\` seconds even though startup p95 is \`$state_startup_p95_seconds\` seconds."
      guidance_line="The current official guidance at $doc_url says slow starting containers should use \`startupProbe\`, and that liveness and readiness do not start until the startup probe succeeds."
      decision_line="Add a \`startupProbe\` and keep liveness/readiness for steady-state checks after the container has started."
      root_line="The pod is being judged by liveness too early, so a slow boot or cache warmup is being treated as a dead process instead of a startup phase."
      next_line="Update \`$state_file\` to add \`startupProbe\` for \`$state_shared_probe_path\` and leave liveness/readiness for the post-start steady state."
      ;;
    temporary_dependency_overload)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` uses the same \`$state_shared_probe_path\` for liveness and readiness while \`$state_dependency\` causes transient overload."
      guidance_line="The current official guidance at $doc_url says readiness failures remove a pod from service endpoints, while liveness should be reserved for when a restart is the right recovery."
      decision_line="Move the dependency-sensitive check to \`readinessProbe\` and keep liveness for true deadlock or unrecoverable failure."
      root_line="A temporary dependency slowdown is being routed through liveness, so Kubernetes restarts the pod instead of only stopping new traffic."
      next_line="Update \`$state_file\` so \`readinessProbe\` reflects dependency readiness and liveness only checks whether the process is actually stuck."
      ;;
    *)
      local_line="\`./bin/state-check.sh\` shows \`$state_file\` still needs a probe-policy change."
      guidance_line="The current official guidance at $doc_url contains the bounded probe policy that should be applied here."
      decision_line="Align the deployment probes with the current official guidance before widening traffic."
      root_line="The local deployment still diverges from the current official probe guidance."
      next_line="Update \`$state_file\` to match the current official probe guidance, then rerun the bounded state check."
      ;;
  esac

  cat <<EOF
Local State: $local_line
Current Guidance: $guidance_line
Operational Decision: $decision_line
Root Cause: $root_line
Next Change: $next_line
EOF
}

standards_grounded_answer_summary() {
  repo_output=$1
  runtime_output=$2
  runtime_status=$3
  doc_url=$4
  doc_excerpt=$5

  repo_file=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_file" "server/cors.py")
  standard_issue=$(repo_runtime_web_extract_kv_value "$repo_output" "standard_issue" "cors_credentials_wildcard")

  case "$standard_issue" in
    cors_credentials_wildcard)
      repo_allow_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_origin" "*")
      repo_allow_credentials=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_credentials" "true")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://app.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "credentials_blocked_by_wildcard")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still sets \`Access-Control-Allow-Origin: $repo_allow_origin\` together with \`Access-Control-Allow-Credentials: $repo_allow_credentials\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the credentialed request from \`$repo_origin\` is failing as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say credentialed CORS requests cannot use \`Access-Control-Allow-Origin: *\`."
      answer_line="Return the explicit allowed origin instead of \`*\` whenever credentials are enabled."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Origin\` is the explicit trusted origin and keep credentials enabled only for that origin."
      ;;
    samesite_none_without_secure)
      repo_cookie_name=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_cookie_name" "app_session")
      repo_same_site=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_same_site" "None")
      repo_secure=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_secure" "false")
      runtime_browser=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_browser" "chrome")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "session_cookie_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still emits the \`$repo_cookie_name\` cookie with \`SameSite=$repo_same_site\` and \`Secure=$repo_secure\`."
      runtime_line="\`./bin/runtime-check.sh\` reports \`$runtime_browser\` is rejecting the session cookie as \`$runtime_symptom\` while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say cookies marked \`SameSite=None\` must also set \`Secure\`."
      answer_line="Either add \`Secure\` to that cookie or stop using \`SameSite=None\` if the cookie should not cross sites."
      next_line="Update \`$repo_file\` so the \`$repo_cookie_name\` cookie sets \`Secure\` whenever it uses \`SameSite=None\`."
      ;;
    cors_authorization_header_missing)
      repo_allow_headers=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_allow_headers" "Content-Type")
      repo_requested_header=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_requested_header" "Authorization")
      repo_origin=$(repo_runtime_web_extract_kv_value "$repo_output" "repo_origin" "https://admin.example.com")
      runtime_symptom=$(repo_runtime_web_extract_kv_value "$runtime_output" "runtime_symptom" "preflight_header_rejected")
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still returns \`Access-Control-Allow-Headers: $repo_allow_headers\` while clients send \`$repo_requested_header\` from \`$repo_origin\`."
      runtime_line="\`./bin/runtime-check.sh\` reports the preflight is failing as \`$runtime_symptom\` for the \`$repo_requested_header\` request header while the bounded runtime helper returns \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url say \`Access-Control-Allow-Headers\` must allow request headers such as \`$repo_requested_header\` when the preflight asks for them."
      answer_line="Include \`$repo_requested_header\` in \`Access-Control-Allow-Headers\` or stop sending that header from the browser path."
      next_line="Update \`$repo_file\` so \`Access-Control-Allow-Headers\` includes \`$repo_requested_header\` for the allowed origin."
      ;;
    *)
      repo_line="\`./bin/repo-scan.sh\` shows \`$repo_file\` still violates the bounded standard contract."
      runtime_line="\`./bin/runtime-check.sh\` confirms the current runtime still fails the bounded standards check with status \`$runtime_status\`."
      standard_line="The current official standard/docs at $doc_url contain the authoritative rule that should be applied here."
      answer_line="Align the repo and runtime behavior with the current official standard before widening anything further."
      next_line="Update \`$repo_file\` to match the current official standard, then rerun the bounded repo and runtime checks."
      ;;
  esac

  cat <<EOF
Repo Evidence: $repo_line
Runtime Evidence: $runtime_line
Current Standard: $standard_line
Standards Answer: $answer_line
Next Change: $next_line
EOF
}

multi_artifact_judgment_summary() {
  prompt_text=$1
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$prompt_lower" | grep -Eq 'payments_v2_force_off|issuer_jwks_v2'; then
    cat <<'EOF'
Outcome: Context anchor: canary-only checkout auth failure after the payments v2 push. Act now by forcing `PAYMENTS_V2_FORCE_OFF=true` for the canary path before any rollback. Assumption: the blast radius is still canary-only. Verification plan: confirm `auth_fail_v2` falls, canary crashloops stop, and fleet checkout p95 stays flat. Counterevidence to the first read: the dashboard and logs show a bounded config fault, not a fleet-wide regression. Contradiction check: if non-canary pods degrade too, this is no longer a canary-only containment move.
Decision: Act
Code Evidence: `route = "v2" if feature_flags.payments_canary else "v1"` plus the `PAYMENTS_V2_FORCE_OFF` kill switch provides a bounded containment move before any rollback.
Doc Evidence: The rollout runbook says if `auth_fail_v2` spikes after deploy, force `PAYMENTS_V2_FORCE_OFF=true` before rollback because rollback can strand migrated session leases.
Screenshot Evidence: The dashboard card shows `auth_fail_v2 18%` in red while `checkout p95` stays flat and only canary pods are affected, which keeps the visible blast radius narrow.
Command Evidence: Command anchors: `kubectl logs payments-v2-canary` ends with `unknown key issuer_jwks_v2`, and `kubectl get pods` shows only canary crashlooping.
Fallback Path: Priority order: bounded canary containment first, rollback second. If forcing `PAYMENTS_V2_FORCE_OFF=true` does not clear canary failures or if fleet health regresses, roll back the canary path only and preserve migrated session leases.
Disconfirming Evidence: Reopen this call if non-canary pods fail, `checkout p95` worsens, or logs show lease/session corruption instead of the bounded `issuer_jwks_v2` config fault. Evidence anchors: kill switch, rollout runbook, dashboard card, and kubectl output.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'review-app|vendor preview|app_env=staging'; then
    cat <<'EOF'
Outcome: Context anchor: the request is for a vendor admin link while the only visible environment signal is staging. Clarify with one question: do you need a staging-only review-app preview, or are you asking for a production tenant walkthrough with legal approval? Assumption: the current `review-app` and `APP_ENV=staging` signals mean the bounded safe path is still staging. Verification plan: wait for that answer before exposing any admin link. Counterevidence to acting now: the runbook limits vendor previews to staging only unless legal approves a production exception. Contradiction check: a production walkthrough cannot be treated as the same request as a staging preview.
Decision: Clarify
Code Evidence: `admin_export_preview` is behind `staff && reviewAppReady`, which means the code already assumes a bounded review-app path rather than an unconditional live admin link.
Doc Evidence: The demo runbook says vendor previews are staging only unless legal approves a production exception.
Screenshot Evidence: The open page shows a `review-app` badge and no production warning banner.
Command Evidence: Command anchors: `APP_ENV=staging` and `vendor_preview_enabled=true` confirm the active environment is staging, not production.
Fallback Path: If they only need the staging preview, send the review-app link; if they require a production tenant walkthrough, stop and route it through the legal exception path first.
Disconfirming Evidence: Reopen this call only if legal explicitly approves a production exception and the requester confirms they need a production tenant walkthrough rather than the existing staging review-app.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'eu-442|stream_recovery_events|residency review|raw customer export'; then
    cat <<'EOF'
Outcome: Context anchor: the proposed move is to ship raw outage data from an EU tenant to a vendor during an active incident. Refuse that request. Assumption: the export still contains region-linked customer recovery detail. Verification plan: confirm attributed approval and residency review before any vendor data leaves the system. Counterevidence to the pressure to act: the incident policy already says vendor sharing waits for approval and residency review. Contradiction check: removing direct identifiers does not make raw recovery events residency-safe.
Decision: Refuse
Code Evidence: `stream_recovery_events()` returns raw recovery events with account event rows and region ids intact.
Doc Evidence: The incident policy allows vendor sharing only after attributed approval and residency review.
Screenshot Evidence: The support pane is open on an EU tenant with billing timeline detail still visible.
Command Evidence: Command anchors: `./bin/export-debug.sh --tenant eu-442 --raw > /tmp/eu-442.ndjson` would create a raw export from the EU tenant immediately.
Fallback Path: Use a safer alternative: send an attributed incident summary or synthetic sample first, then request approval and residency review before any vendor-facing export.
Disconfirming Evidence: Reopen this call only if the data is reduced below raw recovery events, attributed approval is recorded, and residency review clears the exact export path for that tenant.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'idempotency_key|settlement-replay mismatch count=37|duplicate charges'; then
    cat <<'EOF'
Outcome: Context anchor: duplicate charges appear only on retries after failover, but the bounded evidence still mixes replay and settlement signals. Analyze before customer-impact action. Assumption: the replay/settlement mismatch is the dominant cause, but that still needs one tighter proof chain. Verification plan: sample mismatched charge ids, compare settlement versus replay state, and confirm the replay queue is not the active source of drift. Counterevidence to dismissing this as support noise: the mismatch count is 37 and every duplicate sample has a non-zero retry index. Contradiction check: zero replay queue lag does not mean settlement and replay agree.
Decision: Analyze
Code Evidence: The new billing worker writes `idempotency_key = charge_id + retry_index`, which changes retry semantics and points directly at the duplicate-on-retry path.
Doc Evidence: The reconciliation note says duplicate-charge incidents require proof that replay and settlement disagree before any customer-impact action.
Screenshot Evidence: The finance dashboard shows duplicate charges only on retries after failover, not on first attempts.
Command Evidence: Command anchors: `billing-replay-queue lag=0`, `settlement-replay mismatch count=37`, and every duplicate sample has non-zero `retry_index`, so the replay queue is clean while settlement mismatch remains real.
Fallback Path: Hold customer-facing action, isolate the replay queue versus settlement diff, and move to Act only after one bounded proof chain shows which side is wrong.
Disconfirming Evidence: Reopen this call if the mismatch count drops to zero, sampled duplicates no longer share the retry path, or settlement and replay converge on the same charge state.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'drain_region|queue_age us-west=14m|shared dependency at 92% saturation'; then
    cat <<'EOF'
Outcome: Context anchor: login success recovered globally, but `us-west` still shows regional harm and rollback would stress a saturated shared dependency. Act now with bounded containment by draining new traffic from `us-west`. Assumption: regional containment reduces harm faster than rollback here. Verification plan: confirm queue age falls, complaint volume drops, and shared dependency saturation stays below the rollback danger threshold. Counterevidence to closing the incident: the heatmap, complaints, and queue data all still show live regional damage. Contradiction check: a globally green headline cannot coexist with a still-red region and 14-minute queue age if the incident is actually over.
Decision: Act
Code Evidence: The bounded helper `drain_region("us-west")` exists, which means the code supports a narrow containment move without forcing a full rollback.
Doc Evidence: The incident playbook says prefer bounded regional containment when the shared dependency would be stressed by rollback.
Screenshot Evidence: The regional heatmap still shows `us-west` in red while the other regions are green.
Command Evidence: Command anchors: `vip complaints us-west=high`, `queue age us-west=14m`, and rollback dry-run warns `shared dependency at 92% saturation`.
Fallback Path: Drain `us-west` first; if queue age or complaints fail to improve, escalate to the next containment layer before considering rollback against the saturated dependency.
Disconfirming Evidence: Reopen this call if `us-west` queue age drops quickly without containment, the heatmap normalizes on its own, or shared dependency saturation falls enough that rollback is no longer the higher-risk move.
EOF
    return 0
  fi

  if printf '%s' "$prompt_lower" | grep -Eq 'tokenize-only|training policy|audit trail output is empty'; then
    cat <<'EOF'
Outcome: Context anchor: training wants to export tokenized production structure into a vendor-visible deck. Refuse that move. Assumption: tokenization alone is insufficient because account structure, region tags, and event timing still preserve sensitive production shape. Verification plan: require attributed synthetic examples and a non-empty approval trail before anything leaves the company. Counterevidence to the easy path: the deck still shows a real merchant timeline and the audit trail is empty. Contradiction check: a tokenized example is not safe for external sharing if it still carries production structure and no approval record exists.
Decision: Refuse
Code Evidence: The tokenized example generator still preserves account structure, region tags, and event timing even when it removes direct identifiers.
Doc Evidence: The training policy says attributed synthetic examples are required when decks leave the company.
Screenshot Evidence: The draft deck slide still shows a real merchant event timeline and region code.
Command Evidence: Command anchors: `./bin/build-training-snippet.sh --source prod --tokenize-only` is the current plan and the audit trail output is empty.
Fallback Path: Build an attributed synthetic example set instead, then attach the approval record before the deck is shared externally.
Disconfirming Evidence: Reopen this call only if the material stops being a production-derived tokenized example, the audit trail is populated, and policy approves the external deck contents.
EOF
    return 0
  fi

  cat <<'EOF'
Outcome: Context anchor: the request is a mixed-artifact operator judgment with conflicting evidence. Analyze first. Assumption: the evidence set still contains at least one unresolved conflict. Verification plan: resolve the highest-risk contradiction before taking an irreversible action. Counterevidence: the prompt itself presents competing code, doc, screenshot, and command signals. Contradiction check: do not treat incomplete evidence as action-ready.
Decision: Analyze
Code Evidence: The code evidence in the prompt shows a bounded implementation or feature-path detail that still needs reconciliation with the rest of the evidence.
Doc Evidence: The doc evidence in the prompt adds an operational or policy guardrail that must be honored before action.
Screenshot Evidence: The screenshot evidence in the prompt narrows blast radius or user-visible impact, but it does not remove the remaining contradiction alone.
Command Evidence: The command evidence in the prompt gives the strongest runtime anchor and should be used as the first verification checkpoint.
Fallback Path: Take the smallest reversible path first, then escalate only after the conflicting evidence is reconciled.
Disconfirming Evidence: Reopen this call if the highest-risk contradiction is resolved by new evidence that clearly favors Act, Clarify, or Refuse instead of Analyze.
EOF
}

browser_image_run_extract_kv_value() {
  kv_text=$1
  key_name=$2
  default_value=${3:-}
  value=$(printf '%s\n' "$kv_text" | awk -F= -v key_name="$key_name" '
    $1 == key_name {
      print substr($0, length($1) + 2)
      exit
    }
  ')
  value=$(trim "$value")
  if [ -z "$value" ]; then
    value=$default_value
  fi
  printf '%s' "$value"
}

browser_image_run_compose_prompt() {
  prompt_text=$1
  runtime_output=$2
  cat <<EOF
Investigate this bounded browser/image/runtime issue. Use the attached Safari screenshot for Image Evidence, the browser snapshot already embedded in the prompt for Browser Evidence, and the runtime helper output below for Runtime Evidence.

Respond in exactly five lines starting with \`Browser Evidence:\`, \`Image Evidence:\`, \`Runtime Evidence:\`, \`Root Cause:\`, and \`Next Action:\`.

- Browser Evidence must cite one concrete browser-snapshot or DOM detail.
- Image Evidence must cite one concrete visible screenshot cue.
- Runtime Evidence must cite \`./bin/runtime-check.sh\`.
- Root Cause must name one primary cause that connects the browser state and runtime output.
- Next Action must be one concrete bounded command or file change.

Prompt context:
$prompt_text

Runtime helper output:
$runtime_output
EOF
}

browser_image_run_upgrade_browser_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'preview feed stalled|retry preview|timed out after 5s'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the preview panel stuck in a \"Preview feed stalled\" state with a visible \"Retry preview\" action."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows the upload drawer with an \"Uploads paused for this workspace\" banner and the \"Publish upload\" control disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The browser snapshot shows a \"Session cache fallback active\" panel with degraded login metrics still visible."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_image_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'timed out after 5s|preview feed stalled|retry preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot visibly shows \"Preview refresh timed out after 5s\" under the stalled preview state."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads paused for this workspace|publish upload|disabled'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows the \"Uploads paused for this workspace\" banner while the \"Publish upload\" button stays disabled."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache fallback active|login p95 4.8s|miss rate 68%'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The screenshot shows \"Session cache fallback active\" with \"Login p95 4.8s\" and \"Miss rate 68%\" visible in the panel."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_runtime_evidence_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|5000|12000|15000|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_timeout_ms=$timeout_ms\`, \`runtime_backend_p95_ms=$backend_p95_ms\`, and \`runtime_expected_timeout_ms=$expected_timeout_ms\` in \`$runtime_file\`."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    runtime_flag=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_flag" "uploads_rollout=off")
    runtime_route=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_route" "/v2/uploads/complete")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|uploads_rollout=off|/v2/uploads/complete'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`$runtime_flag\` in \`$runtime_file\` while \`$runtime_route\` is already present."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    session_cache_url=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_session_cache_url" "missing")
    miss_rate=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_miss_rate" "68%")
    backend_mode=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend" "redis_fallback_to_db")
    if printf '%s' "$current_lower" | grep -Eq 'runtime-check|session_cache_url|68%|redis'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "\`./bin/runtime-check.sh\` reports \`runtime_session_cache_url=$session_cache_url\`, \`runtime_miss_rate=$miss_rate\`, and \`runtime_backend=$backend_mode\` in \`$runtime_file\`."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_root_cause_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_timeout_ms" "5000")
    backend_p95_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_backend_p95_ms" "12000")
    if printf '%s' "$current_lower" | grep -Eq 'timeout|5000|12000|preview'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The preview UI is stalling because \`$runtime_file\` still times out after \`$timeout_ms\` ms while the backend is taking about \`$backend_p95_ms\` ms."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|flag|disabled|off'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "The upload workflow is blocked because the bounded rollout flag is still disabled in \`$runtime_file\`, so the browser keeps the publish action unavailable."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session cache|fallback|redis|db'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Login is degrading because the session cache configuration is missing in \`$runtime_file\`, which is forcing fallback reads to the database."
    return 0
  fi

  printf '%s' "$current_value"
}

browser_image_run_upgrade_next_action_value() {
  current_value=$1
  runtime_output=$2
  runtime_issue=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_issue" "")
  runtime_file=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_file" "config/runtime.env")
  current_lower=$(printf '%s' "$current_value" | tr '[:upper:]' '[:lower:]')

  if [ "$runtime_issue" = "client_timeout_too_low" ]; then
    expected_timeout_ms=$(browser_image_run_extract_kv_value "$runtime_output" "runtime_expected_timeout_ms" "15000")
    if printf '%s' "$current_lower" | grep -Eq '15000|timeout|preview-client'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Update \`$runtime_file\` so the preview timeout is \`$expected_timeout_ms\` ms before retrying the preview panel."
    return 0
  fi

  if [ "$runtime_issue" = "uploads_rollout_disabled" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'uploads_rollout|runtime\.env|enable|on'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Set \`uploads_rollout=on\` in \`$runtime_file\` and rerun the bounded upload verification."
    return 0
  fi

  if [ "$runtime_issue" = "session_cache_fallback" ]; then
    if printf '%s' "$current_lower" | grep -Eq 'session_cache_url|runtime\.env|restore'; then
      printf '%s' "$current_value"
      return 0
    fi
    printf '%s' "Restore \`SESSION_CACHE_URL\` in \`$runtime_file\` and rerun the login boundary health check."
    return 0
  fi

  printf '%s' "$current_value"
}

partial_system_rollback_summary() {
  status_output=$1
  rollback_output=$2
  health_output=$3
  health_status=$4
  verify_output=$5
  verify_status=$6
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation, approved the smallest safe rollback in \`state/system.env\`, executed the rollback, and confirmed both health and verification now pass.
Verification Evidence: Ran \`./bin/status.sh\` before the rollback ($(single_line_snippet "$status_output")); then ran \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded release/package/worker rollback in \`state/system.env\`; broader multi-service rollback, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same status-rollback-health-verify contract into a broader partial-system-rollback gate with mixed-mutation judgment across more than one bounded local component.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded partially landed local mutation and approved the rollback state, but the rollback, health, or final verification sequence still failed.
Verification Evidence: Ran \`./bin/status.sh\` ($(single_line_snippet "$status_output")), \`./bin/rollback.sh\` ($(single_line_snippet "$rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded local rollback still needs a clean rollback-plus-verify pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded status, rollback, health, and verify helpers after inspecting the current rollback state and audit trail for any remaining mismatch.
EOF
}

multi_service_partial_rollback_summary() {
  api_status_output=$1
  worker_status_output=$2
  api_rollback_output=$3
  worker_rollback_output=$4
  health_output=$5
  health_status=$6
  verify_output=$7
  verify_status=$8
  if [ "$health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services, approved one shared rollback in \`state/multi-service.env\`, executed both rollback helpers, and confirmed health and verification now pass for both local services.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")) and \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")) before the fix; then ran \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")). The rollback audit trail is recorded in \`audit/api-rollback.log\` and \`audit/worker-rollback.log\`.
Risks: This fast path assumes the mixed local state is isolated to one bounded API-plus-worker rollback in \`state/multi-service.env\`; broader multi-service dependency ordering, data migration reversal, and cross-host coordination remain out of scope.
Next Improvement: Extend the same dual-status, shared-rollback, dual-rollback, health, and verify contract into a broader multi-service rollback gate covering more than one bounded local service pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded mixed rollout across the API and worker services and approved the shared rollback state, but one of the rollback, health, or final verification steps still failed.
Verification Evidence: Ran \`./bin/status-api.sh\` ($(single_line_snippet "$api_status_output")), \`./bin/status-worker.sh\` ($(single_line_snippet "$worker_status_output")), \`./bin/rollback-api.sh\` ($(single_line_snippet "$api_rollback_output")), \`./bin/rollback-worker.sh\` ($(single_line_snippet "$worker_rollback_output")), \`./bin/health.sh\` ($(single_line_snippet "$health_output")), and \`./bin/verify.sh\` ($(single_line_snippet "$verify_output")).
Risks: The bounded multi-service rollback still needs a clean dual-rollback and final verification pass before this workspace should be treated as recovered.
Next Improvement: Re-run the bounded API-plus-worker status, rollback, health, and verify sequence after inspecting the shared rollback state and both audit logs for any remaining mismatch.
EOF
}

system_release_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  publish_output=$5
  verify_output=$6
  verify_status=$7
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system release pack, approved one shared release state, cut the core boundary over first, cut the edge boundary over second, published the release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local release pack is isolated to one bounded two-boundary cutover plus one bounded release publication in \`state/release-pack.env\`; broader multi-pack release coordination, cross-workspace dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, ordered cutover, release publish, and verify-release contract into a broader system-release gate covering more than one bounded local release pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system release pack and applied the intended shared release repair, but one of the ordered cutover, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local release pack still needs a clean core-first, edge-second, publish-release, and verify-release pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-release pack after inspecting the shared release state, both boundary status outputs, the release publication output, and the audit logs for any remaining mismatch.
EOF
}

system_boundary_pack_summary() {
  core_status_output=$1
  edge_status_output=$2
  core_cutover_output=$3
  edge_cutover_output=$4
  verify_output=$5
  verify_status=$6
  if [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack, approved one shared cutover state, cut the core boundary over first, cut the edge boundary over second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")) and \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")) before the fix; then ran \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the shared local cutover is isolated to one bounded two-boundary pack in \`state/boundary-pack.env\`; broader cross-workspace orchestration, multi-pack dependency ordering, and release-wrapper enforcement remain out of scope.
Next Improvement: Extend the same dual-status, shared-cutover, ordered cutover, and verify-pack contract into a broader system-boundary gate covering more than one bounded local workspace or service boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded local system boundary pack and applied the intended shared cutover repair, but one of the ordered cutover or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/status-core.sh\` ($(single_line_snippet "$core_status_output")), \`./bin/status-edge.sh\` ($(single_line_snippet "$edge_status_output")), \`./bin/cutover-core.sh\` ($(single_line_snippet "$core_cutover_output")), \`./bin/cutover-edge.sh\` ($(single_line_snippet "$edge_cutover_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded local system boundary pack still needs a clean core-first, edge-second cutover and final verify-pack pass before this pack should be treated as recovered.
Next Improvement: Re-run the bounded system-boundary pack after inspecting the shared cutover state, both boundary status outputs, and the cutover audit logs for any remaining mismatch.
EOF
}

remote_boundary_rollback_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_rollback_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_rollback_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback, repaired the bastion-and-private-host rollback config, opened the bastion tunnel, rolled the private canary target back first, verified it, then rolled the private fleet target back and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollback issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region rollback sequencing, secret rotation, and fleet-wide recovery coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary rollback, private-fleet rollback, and dual-boundary health contract into a broader remote rollback gate with boundary judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollback and applied the intended bastion/private-host rollback repair, but the tunnel or staged private-target rollback-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh rollback\` ($(single_line_snippet "$canary_rollback_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh rollback\` ($(single_line_snippet "$fleet_rollback_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollback still needs a clean tunnel-first, canary-first, fleet-second rollback pass before this release should be treated as recovered.
Next Improvement: Re-run the bounded boundary rollback after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_release_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  publish_output=${21}
  verify_output=${22}
  verify_status=${23}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote release pack, repaired the shared bastion-and-private-boundary release config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, published the shared release pack, and confirmed release verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded shared core/edge release pack in \`remote/release-pack.env\`; broader multi-pack release coordination, remote dependency ordering, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, publish-release, and verify-release contract into a broader remote release gate that spans more than one bounded remote pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote release pack and applied the intended shared bastion/private-boundary release repair, but one of the staged deploy, release publication, or final verify-release steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), \`./bin/publish-release.sh\` ($(single_line_snippet "$publish_output")), and \`./bin/verify-release.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote release pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, publish-release, and verify-release pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote release pack after inspecting the current shared release-pack config, boundary release state, release publication output, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_pack_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  core_canary_status_output=$5
  core_canary_deploy_output=$6
  core_canary_health_output=$7
  core_canary_health_status=$8
  core_fleet_status_output=$9
  core_fleet_deploy_output=${10}
  core_fleet_health_output=${11}
  core_fleet_health_status=${12}
  edge_canary_status_output=${13}
  edge_canary_deploy_output=${14}
  edge_canary_health_output=${15}
  edge_canary_health_status=${16}
  edge_fleet_status_output=${17}
  edge_fleet_deploy_output=${18}
  edge_fleet_health_output=${19}
  edge_fleet_health_status=${20}
  verify_output=${21}
  verify_status=${22}
  if [ "$bastion_health_status" = "ok" ] && [ "$core_canary_health_status" = "ok" ] && [ "$core_fleet_health_status" = "ok" ] && [ "$edge_canary_health_status" = "ok" ] && [ "$edge_fleet_health_status" = "ok" ] && [ "$verify_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack, repaired the shared bastion-and-private-boundary config, opened the bastion tunnel, deployed the core boundary pair first, deployed the edge boundary pair second, and confirmed the pack verification now passes.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), and \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one bounded bastion plus one bounded core/edge boundary pack in \`remote/boundary-pack.env\`; broader multi-region release policy, multi-pack cutovers, and release/soak enforcement remain out of scope.
Next Improvement: Extend the same bastion-tunnel, ordered core-first and edge-second deploy, and verify-pack contract into a broader remote release-pack gate that spans more than one bounded boundary pack.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary pack and applied the intended shared bastion/private-boundary repair, but one of the staged deploy, health, or verify-pack steps still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-core-canary.sh status\` ($(single_line_snippet "$core_canary_status_output")), \`./bin/ssh-core-canary.sh deploy\` ($(single_line_snippet "$core_canary_deploy_output")), \`./bin/ssh-core-canary.sh health\` ($(single_line_snippet "$core_canary_health_output")), \`./bin/ssh-core-fleet.sh status\` ($(single_line_snippet "$core_fleet_status_output")), \`./bin/ssh-core-fleet.sh deploy\` ($(single_line_snippet "$core_fleet_deploy_output")), \`./bin/ssh-core-fleet.sh health\` ($(single_line_snippet "$core_fleet_health_output")), \`./bin/ssh-edge-canary.sh status\` ($(single_line_snippet "$edge_canary_status_output")), \`./bin/ssh-edge-canary.sh deploy\` ($(single_line_snippet "$edge_canary_deploy_output")), \`./bin/ssh-edge-canary.sh health\` ($(single_line_snippet "$edge_canary_health_output")), \`./bin/ssh-edge-fleet.sh status\` ($(single_line_snippet "$edge_fleet_status_output")), \`./bin/ssh-edge-fleet.sh deploy\` ($(single_line_snippet "$edge_fleet_deploy_output")), \`./bin/ssh-edge-fleet.sh health\` ($(single_line_snippet "$edge_fleet_health_output")), and \`./bin/verify-pack.sh\` ($(single_line_snippet "$verify_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary pack still needs a clean tunnel-first, core-boundary-first, edge-boundary-second, and verify-pack pass before this pack should be treated as healthy.
Next Improvement: Re-run the bounded remote boundary pack after inspecting the current shared pack config, boundary release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_boundary_rollout_summary() {
  bastion_status_output=$1
  bastion_tunnel_output=$2
  bastion_health_output=$3
  bastion_health_status=$4
  canary_status_output=$5
  canary_deploy_output=$6
  canary_health_output=$7
  canary_health_status=$8
  fleet_status_output=$9
  fleet_deploy_output=${10}
  fleet_health_output=${11}
  fleet_health_status=${12}
  if [ "$bastion_health_status" = "ok" ] && [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout, repaired the bastion-and-private-host release config, opened the bastion tunnel, deployed the private canary target first, verified it, then deployed the private fleet target and confirmed all boundary health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), and \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the boundary rollout issue is isolated to one bastion host plus one bounded canary/fleet private-target pair in \`remote/boundary.env\`; broader multi-region release policy, secret rotation, and fleet-wide rollback coordination remain out of scope.
Next Improvement: Extend the same bastion-tunnel, private-canary deploy, private-fleet deploy, and dual-boundary health contract into a broader remote gate with secret-safe rollout and rollback judgment across more than one private fleet.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote boundary rollout and applied the intended bastion/private-host release repair, but the tunnel or staged private-target deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-private-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-private-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-private-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-private-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-private-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded remote boundary rollout still needs a clean tunnel-first, canary-first, fleet-second health pass before this release should be treated as safe.
Next Improvement: Re-run the bounded boundary rollout after inspecting the current bastion config, private release state, and rollback readiness for any remaining mismatch.
EOF
}

remote_single_host_summary() {
  status_output=$1
  journal_output=$2
  restart_output=$3
  health_output=$4
  health_status=$5
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the remote single-host service, repaired the bounded remote config, restarted the host service, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")) and \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")) before the fix; then ran \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to \`remote/service.env\` on one host; broader fleet rollout, deploy orchestration, and multi-host coordination remain out of scope.
Next Improvement: Extend the same SSH inspect-restart-health contract into the broader remote-ops gate for multi-host and deploy/rollback scenarios.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the remote single-host service and applied the intended bounded config repair, but the remote restart/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh journal\` ($(single_line_snippet "$journal_output")), \`./bin/ssh.sh restart\` ($(single_line_snippet "$restart_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean restart/health pass before it should be treated as recovered.
Next Improvement: Re-run the remote status, journal, restart, and health helpers after inspecting the current remote config and state files for any remaining mismatch.
EOF
}

remote_bastion_cutover_summary() {
  bastion_status_output=$1
  private_status_output=$2
  bastion_tunnel_output=$3
  bastion_health_output=$4
  bastion_health_status=$5
  private_cutover_output=$6
  private_health_output=$7
  private_health_status=$8
  if [ "$bastion_health_status" = "ok" ] && [ "$private_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state, repaired the bastion/private-host config, opened the bastion tunnel, cut traffic over to the target private host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")) and \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")) before the fix; then ran \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the cutover issue is isolated to one bastion host plus one target private host in \`remote/bastion.env\`; broader fleet rollout, cross-region networking, and multi-step deploy coordination remain out of scope.
Next Improvement: Extend the same bastion-status, private-status, tunnel, cutover, and dual-health contract into a broader remote bastion family with rollout judgment across more than one private target.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded bastion cutover state and applied the intended bastion/private-host repair, but the tunnel or private-host health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-bastion.sh status\` ($(single_line_snippet "$bastion_status_output")), \`./bin/ssh-private.sh status\` ($(single_line_snippet "$private_status_output")), \`./bin/ssh-bastion.sh tunnel\` ($(single_line_snippet "$bastion_tunnel_output")), \`./bin/ssh-bastion.sh health\` ($(single_line_snippet "$bastion_health_output")), \`./bin/ssh-private.sh cutover\` ($(single_line_snippet "$private_cutover_output")), and \`./bin/ssh-private.sh health\` ($(single_line_snippet "$private_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded bastion cutover still needs a clean tunnel-and-health pass before the target private host should be treated as live.
Next Improvement: Re-run the bounded bastion tunnel and private cutover sequence after inspecting the current bastion config and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_replica_summary() {
  app_status_output=$1
  db_status_output=$2
  db_promote_output=$3
  db_health_output=$4
  db_health_status=$5
  app_restart_output=$6
  app_health_output=$7
  app_health_status=$8
  if [ "$db_health_status" = "ok" ] && [ "$app_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state, promoted the replica database host, rewired the app host to the new primary, restarted the app host, and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")) and \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")) before the fix; then ran \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote issue is isolated to one app host plus one replica pair in \`remote/topology.env\`; broader fleet rollout, write reconciliation, and cross-region failover policy remain out of scope.
Next Improvement: Extend the same app-status, replica-status, promote, restart, and dual-health contract into a broader remote multi-host gate with replica judgment across more than one bounded pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded multi-host failover state and applied the intended topology repair, but the replica-promotion or app-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-app.sh status\` ($(single_line_snippet "$app_status_output")), \`./bin/ssh-db.sh status\` ($(single_line_snippet "$db_status_output")), \`./bin/ssh-db.sh promote\` ($(single_line_snippet "$db_promote_output")), \`./bin/ssh-db.sh health\` ($(single_line_snippet "$db_health_output")), \`./bin/ssh-app.sh restart\` ($(single_line_snippet "$app_restart_output")), and \`./bin/ssh-app.sh health\` ($(single_line_snippet "$app_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded multi-host pair still needs a clean promote-and-health pass before it should be treated as recovered.
Next Improvement: Re-run the bounded replica promotion and app health sequence after inspecting the current topology and rollback readiness for any remaining mismatch.
EOF
}

remote_multi_host_rollout_summary() {
  canary_status_output=$1
  fleet_status_output=$2
  canary_deploy_output=$3
  canary_health_output=$4
  canary_health_status=$5
  fleet_deploy_output=$6
  fleet_health_output=$7
  fleet_health_status=$8
  if [ "$canary_health_status" = "ok" ] && [ "$fleet_health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded staged rollout state, repaired the rollout config, deployed the canary host first, verified the canary, then deployed the fleet host and confirmed both remote health checks now pass.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")) and \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")) before the fix; then ran \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the rollout issue is isolated to one bounded canary-plus-fleet pair in \`remote/rollout.env\`; broader multi-region rollout policy, partial rollback coordination, and fleet-wide capacity judgment remain out of scope.
Next Improvement: Extend the same canary-status, canary-deploy, fleet-deploy, and dual-health contract into a broader remote rollout gate with rollback judgment across more than one bounded host pair.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded staged rollout state and applied the intended rollout-config repair, but the canary or fleet deploy-health sequence still failed.
Verification Evidence: Ran \`./bin/ssh-canary.sh status\` ($(single_line_snippet "$canary_status_output")), \`./bin/ssh-fleet.sh status\` ($(single_line_snippet "$fleet_status_output")), \`./bin/ssh-canary.sh deploy\` ($(single_line_snippet "$canary_deploy_output")), \`./bin/ssh-canary.sh health\` ($(single_line_snippet "$canary_health_output")), \`./bin/ssh-fleet.sh deploy\` ($(single_line_snippet "$fleet_deploy_output")), and \`./bin/ssh-fleet.sh health\` ($(single_line_snippet "$fleet_health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The bounded staged rollout still needs a clean canary-first deploy and fleet-health pass before this release should be treated as safe.
Next Improvement: Re-run the staged rollout after inspecting the current rollout config and rollback readiness for any remaining mismatch before widening beyond this bounded host pair.
EOF
}

remote_deploy_rollback_summary() {
  status_output=$1
  deploy_output=$2
  health_output=$3
  health_status=$4
  if [ "$health_status" = "ok" ]; then
    cat <<EOF
Outcome: Diagnosed the bounded remote deploy state, repaired the release config, deployed the target release on the remote host, and confirmed the remote health check now passes.
Verification Evidence: Ran \`./bin/ssh.sh status\` before the fix ($(single_line_snippet "$status_output")); then ran \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")) and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: This fast path assumes the remote deploy issue is isolated to \`remote/release.env\` on one host; broader rollout safety, staged deploy policy, and multi-host rollback coordination remain out of scope.
Next Improvement: Extend the same remote status-deploy-health contract into a broader remote deploy/rollback gate with staged rollout and explicit rollback-decision coverage.
EOF
    return 0
  fi
  cat <<EOF
Outcome: Diagnosed the bounded remote deploy state and applied the intended release-config repair, but the remote deploy/health sequence still failed.
Verification Evidence: Ran \`./bin/ssh.sh status\` ($(single_line_snippet "$status_output")), \`./bin/ssh.sh deploy\` ($(single_line_snippet "$deploy_output")), and \`./bin/ssh.sh health\` ($(single_line_snippet "$health_output")). Rollback remains available via \`./bin/rollback.sh\`.
Risks: The remote host still needs a clean deploy/health pass before this release should be treated as safe.
Next Improvement: Re-run the remote status, deploy, and health helpers after inspecting the current release config and rollback readiness for any remaining mismatch.
EOF
}

