#!/bin/sh
set -eu

self_knowledge_registry_version() {
  printf '%s' "2026-03-29"
}

self_knowledge_topics_json() {
  printf '%s' '["overview","gui","architecture","llm-foundations","ollama-runtime","ollama-contributing","self-actuation"]'
}

self_knowledge_valid_topics_csv() {
  printf '%s' "overview,gui,architecture,llm-foundations,ollama-runtime,ollama-contributing,self-actuation"
}

self_knowledge_normalize_topic() {
  raw_topic=$1
  normalized=$(printf '%s' "$raw_topic" | tr '[:upper:]' '[:lower:]' | tr ' _' '--')
  case "$normalized" in
    ""|overview|all|summary)
      printf '%s' "overview"
      return 0
      ;;
    gui|ui|interface|navigation|surface)
      printf '%s' "gui"
      return 0
      ;;
    architecture|runtime|internals|codebase)
      printf '%s' "architecture"
      return 0
      ;;
    llm|llms|foundations|llm-foundations|transformers|tokens|tokenization)
      printf '%s' "llm-foundations"
      return 0
      ;;
    ollama|ollama-runtime|runtime-ollama|ollama-models|models)
      printf '%s' "ollama-runtime"
      return 0
      ;;
    ollama-contributing|contributing|contrib|contributor|contributors)
      printf '%s' "ollama-contributing"
      return 0
      ;;
    self-actuation|self-actuate|actuation|automation-ops|workflow-ops|workflows|operations)
      printf '%s' "self-actuation"
      return 0
      ;;
  esac
  return 1
}

self_knowledge_overview_text() {
  cat <<'EOF'
Artificer self-knowledge overview:
- Artificer is a local-first GUI plus CGI runtime for workspace-grounded agent execution.
- The frontend lives in hosted-web/pages/index.md and hosted-web/static/artificer-app-modules/*.
- The backend API entrypoint is hosted-web/cgi/artificer-api, which dispatches action handlers in hosted-web/cgi/actions/*.
- Long-run orchestration is implemented by hosted-web/cgi/actions/run_parts/* with runtime helpers under hosted-web/cgi/lib/runtime/*.
- Queue, conversation, workspace, and automation state are file-first under the Artificer site data directory.
- Reflexive knowledge and self-actuation are explicit permission gates; they are disabled unless enabled for a run.

Use this mental model:
1. UI surface state chooses workspace/thread/model/mode and permissions.
2. Queue/run actions serialize those choices into file-backed run metadata.
3. Runtime pipeline performs planning, tool calls, implementation, verification, and final response.
4. State and logs remain inspectable through files and explicit API actions.
EOF
}

self_knowledge_gui_text() {
  cat <<'EOF'
GUI map (exact labels and major controls):
- Left sidebar:
  - Sidebar views listbox includes "Automations".
  - Main heading is "Threads".
  - Project actions include "New project" and "Organize threads".
  - Footer has "Settings", theme picker, and "Ollama Models" status button.
- Main toolbar:
  - Thread title and project path widget.
  - Run Action, Open, Commit, Terminal, and Changes controls.
- Composer row:
  - Attach button, model picker, run-mode picker, reasoning depth menu, compute/time budget menu, and send button.
  - Permissions menu includes command execution mode plus toggles for Network access, Web access, Reflexive knowledge, and Self-actuation.
- Settings modal sections:
  - Automations, Programming mode, Self-improvement, Command approvals, and Teams + Runtime + Skills.
- Automation modal fields:
  - Name, Project, Thread, Task prompt, schedule kind/value, enabled, self-reschedule toggle, next-run override.

When explaining the UI, use these labels verbatim so users can find controls reliably.
EOF
}

self_knowledge_architecture_text() {
  cat <<'EOF'
Architecture map:
- Entry routing:
  - hosted-web/cgi/artificer-api reads action and sources hosted-web/cgi/actions/<action>.sh.
- Runtime libraries:
  - hosted-web/cgi/lib/00-bootstrap.sh sets environment, paths, state roots, and JSON helpers.
  - hosted-web/cgi/lib/runtime/40a-core-queue.sh handles queue metadata, ids, and queue serialization.
  - hosted-web/cgi/lib/runtime/40b-automations.sh handles schedule parsing, run enqueueing, and automation state.
  - hosted-web/cgi/lib/runtime/40e-intelligence-core.sh and submodules handle model routing and command policies.
  - hosted-web/cgi/actions/run_parts/* drives iterative execution flow.
- Frontend composition:
  - hosted-web/pages/index.md defines semantic layout and element ids.
  - hosted-web/static/artificer-app-modules/* contains boot, rendering, sync, queue, settings, and event layers.
- Data locations:
  - get-site-data-dir("artificer"): durable app/workspace/conversation/queue data.
  - ARTIFICER_STATE_ROOT (default ~/.local/state/artificer): assay reports/runs and runtime diagnostics.
- CLI surface:
  - hosted-web/scripts/artificer-appctl exposes mediated project/thread/automation and knowledge operations.
EOF
}

self_knowledge_llm_foundations_text() {
  cat <<'EOF'
LLM foundations teaching path:
Step 1: Tokenization and context windows.
- Text is converted into tokens; context window is a finite token budget.
- Prompt framing quality and retrieved evidence determine what fits in context.

Step 2: Transformer inference basics.
- Models compute token probabilities autoregressively.
- Attention and feed-forward blocks transform token states each layer.
- KV cache reuses prior computation and governs streaming latency tradeoffs.

Step 3: Training pipeline concepts.
- Pretraining learns broad language/code statistics from large corpora.
- Instruction tuning aligns model behavior to task-like prompts.
- Post-training safety/alignment layers constrain harmful or low-quality behavior.

Step 4: Reliability engineering.
- Fluent text is not proof; require evidence and verification loops.
- Use explicit assumptions, contradiction checks, and tool-grounded validation.
- Prefer measurable pass/fail tests over narrative confidence.

Step 5: Contributor-level understanding targets.
- Read code for tokenizer boundaries, sampling policy, and context packing.
- Trace one request end-to-end from prompt assembly through streaming output.
- Explain latency bottlenecks: prompt eval, decode throughput, and I/O.
EOF
}

self_knowledge_ollama_runtime_text() {
  cat <<'EOF'
Ollama runtime essentials:
- Ollama runs a local model service (default localhost endpoint on port 11434).
- Typical interfaces include CLI commands (list/pull/run/show/ps) and HTTP API routes.
- Model images are referenced by model tags; quantization and context settings affect memory/latency.
- Modelfile definitions are used to compose/adapt model behavior and templates.

How Artificer uses Ollama:
- Installed-model discovery drives model selector and metadata panels.
- Active model is selected per thread/run and used for chat/programming/report flows.
- Runtime settings can steer compute behaviors (for example, GPU usage preference where available).

Operational debugging checklist:
1. Verify service reachability and installed model list.
2. Confirm selected model exists locally and matches run-mode needs.
3. Inspect prompt size/context pressure if quality or truncation regresses.
4. Check streaming behavior and run status timeline for stalls/timeouts.
EOF
}

self_knowledge_ollama_contributing_text() {
  cat <<'EOF'
Ollama contributor-learning path:
Phase 1: Local build and traceability.
- Build Ollama from source in a clean checkout.
- Run its tests and a local inference smoke script before editing anything.
- Trace a single API request from HTTP handler to model runner to response stream.

Phase 2: System internals.
- Identify request validation, scheduling, model loading, and stream emission boundaries.
- Map where model metadata, runtime options, and template/modelfile behavior are resolved.
- Document invariants before coding: what must stay true for compatibility and safety.

Phase 3: High-signal contribution types.
- Bug fixes with deterministic repro and regression tests.
- Performance patches with before/after benchmarks and memory impact notes.
- API/behavior changes with migration notes and compatibility tests.

Phase 4: Engineering discipline for upstream quality.
- Keep patches small, auditable, and backed by targeted tests.
- Separate refactor-only commits from behavior-changing commits.
- Include failure-mode analysis and rollback strategy in PR description.

Phase 5: Teaching mastery check.
- Be able to explain, with concrete files/functions, how token requests flow through Ollama.
- Be able to design and implement one new runtime option with tests and docs.
- Be able to review another contributor patch for correctness, performance, and compatibility risk.
EOF
}

self_knowledge_self_actuation_text() {
  cat <<'EOF'
Artificer self-actuation operator playbook:
Permission gate:
- Self-actuation commands are allowed only when the Self-actuation permission is enabled for the run.

Safe execution sequence (always in this order):
1. Inspect current state:
   - artificer-appctl project list --json
   - artificer-appctl automation list --json
   - artificer-appctl thread list --workspace-id <id> --json
2. Generate a dry-run plan:
   - artificer-appctl self-actuation preview --operation <operation> ... --json
3. Apply only with returned confirmation token:
   - artificer-appctl self-actuation apply --operation <operation> --confirm-token <token> ... --json
4. Re-list state and verify result before next mutation.
5. Use idempotency keys for retry-safe applies:
   - --idempotency-key <stable-key>

Policy and audit operations:
- policy inspect: artificer-appctl self-actuation policy-get [--workspace-id <id>] [--action <operation>] --json
- policy update:  artificer-appctl self-actuation policy-set --action <operation> --enabled <0|1> [--workspace-id <id>] --json
- audit tail:     artificer-appctl self-actuation audit --limit <n> --json

Orchestrated operation map:
- ensure_workspace: create-by-path if missing, otherwise resolve existing workspace id.
- rename_workspace: requires existing workspace id and new name.
- delete_workspace: destructive; requires existing workspace id.
- ensure_thread: create-by-title when missing, otherwise reuse resolved conversation id.
- archive_thread: destructive; requires workspace id + conversation id.
- ensure_automation: create-or-update automation using workspace/conversation context.
- toggle_automation: requires automation id + enabled flag.
- run_automation_now: queues immediate execution for existing automation id.
- delete_automation: destructive; requires existing automation id.
- bootstrap_workspace_stack: id-safe multi-step ensure flow for workspace + optional thread + optional automation.

Failure diagnosis runbook:
- "confirm_token mismatch": regenerate preview and apply with the returned token.
- "operation blocked by self-actuation policy": inspect policy-get scope (workspace/global), then set explicit allow when intended.
- "workspace/conversation/automation not found": re-list state and resolve real ids before retrying.
- "invalid <field>": normalize flags to allowed values (enabled 0/1, schedule-kind cron|interval|once, command-exec mode).

Project operations:
- create:  artificer-appctl project add --path <path> [--name <label>]
- rename:  artificer-appctl project rename --workspace-id <id> --name <label>
- delete:  artificer-appctl project delete --workspace-id <id>

Thread operations:
- list:    artificer-appctl thread list --workspace-id <id>
- create:  artificer-appctl thread new --workspace-id <id> [--title <title>] [--model <model>]
- archive: artificer-appctl thread archive --workspace-id <id> --conversation-id <id>

Automation operations:
- list:    artificer-appctl automation list
- upsert:  artificer-appctl automation upsert ...
- enable/disable: artificer-appctl automation toggle --automation-id <id> --enabled <0|1>
- run now: artificer-appctl automation run-now --automation-id <id>
- delete:  artificer-appctl automation delete --automation-id <id>

Reliability rules:
- Never mutate resources using unknown ids.
- Never chain multiple destructive operations without re-reading state.
- When id lookups fail, report mismatch and request a fresh list operation.
- Prefer orchestration preview/apply for destructive changes.
- Treat policy-set changes as explicit intent changes and confirm with policy-get.
- Use audit entries to explain exactly what ran, when, and why it failed or succeeded.
EOF
}

self_knowledge_topic_learning_goals_text() {
  topic_name=$1
  case "$topic_name" in
    overview)
      printf '%s' "- Explain Artificer as UI + API + runtime + file-backed state."
      ;;
    gui)
      printf '%s' "- Navigate users by exact labels and locate each core control."
      ;;
    architecture)
      printf '%s' "- Trace one run from UI input to runtime output with concrete file paths."
      ;;
    llm-foundations)
      printf '%s' "- Teach tokenization, transformer inference, decoding, and reliability tradeoffs."
      ;;
    ollama-runtime)
      printf '%s' "- Explain local model runtime behavior and diagnose common operational failures."
      ;;
    ollama-contributing)
      printf '%s' "- Prepare contributors for reproducible, tested upstream runtime patches."
      ;;
    self-actuation)
      printf '%s' "- Execute safe preview/apply self-actuation workflows with policy awareness, idempotent retries, and auditable outcomes."
      ;;
    *)
      printf '%s' "- Deliver accurate, grounded explanations with explicit uncertainty boundaries."
      ;;
  esac
}

self_knowledge_topic_misconceptions_text() {
  topic_name=$1
  case "$topic_name" in
    llm-foundations)
      printf '%s' "- Fluency implies factuality.\n- Bigger model always means correct answer."
      ;;
    ollama-runtime)
      printf '%s' "- Model not listed means model is broken (could be service/process/state mismatch).\n- Slow output always means weak hardware (can be prompt/context pressure)."
      ;;
    ollama-contributing)
      printf '%s' "- Refactor and behavior change should be mixed in one patch.\n- Manual repro is enough without regression tests."
      ;;
    self-actuation)
      printf '%s' "- A valid-looking id string is enough without checking live state.\n- Confirmation tokens can be reused after changing operation payload.\n- Policy gates only matter for destructive operations."
      ;;
    *)
      printf '%s' "- Confident wording is equivalent to grounded evidence."
      ;;
  esac
}

self_knowledge_topic_assessment_checks_text() {
  topic_name=$1
  case "$topic_name" in
    llm-foundations)
      printf '%s' "1. Explain KV cache impact on streaming latency.\n2. Distinguish sampling errors from context truncation failures."
      ;;
    ollama-runtime)
      printf '%s' "1. Diagnose a missing model using service/list/show checks.\n2. Provide a stepwise fix plan for failed model pull or run."
      ;;
    ollama-contributing)
      printf '%s' "1. Propose a bug-fix patch with deterministic repro and regression test.\n2. Provide rollback criteria for the patch."
      ;;
    self-actuation)
      printf '%s' "1. Given a requested mutation, produce preview command, explain confirm token purpose, and provide a safe apply command.\n2. Diagnose blocked-policy vs confirm-token mismatch from API error text and prescribe exact recovery steps."
      ;;
    *)
      printf '%s' "1. Explain the subsystem with concrete artifacts.\n2. Separate known facts from inferred details."
      ;;
  esac
}

self_knowledge_topic_practice_tasks_text() {
  topic_name=$1
  case "$topic_name" in
    llm-foundations)
      printf '%s' "- Compare two local models on one prompt and explain quality deltas using context/sampling hypotheses."
      ;;
    ollama-runtime)
      printf '%s' "- Perform a local runtime triage runbook: service check, model inventory, run smoke, and output verification."
      ;;
    ollama-contributing)
      printf '%s' "- Draft a contributor-ready issue-to-PR plan with tests, benchmarks, and compatibility notes."
      ;;
    self-actuation)
      printf '%s' "- Execute a complete orchestrated lifecycle: ensure_workspace -> ensure_thread -> ensure_automation -> run_automation_now, then verify via list/audit and perform one policy-set rollback."
      ;;
    *)
      printf '%s' "- Teach this topic to a beginner, then validate with two concrete comprehension checks."
      ;;
  esac
}

self_knowledge_topic_reference_paths_json() {
  topic_name=$1
  case "$topic_name" in
    overview)
      printf '%s' '["README.md","docs/REPO_OVERVIEW.md"]'
      ;;
    gui)
      printf '%s' '["hosted-web/pages/index.md","hosted-web/static/artificer-app-modules"]'
      ;;
    architecture)
      printf '%s' '["hosted-web/cgi/artificer-api","hosted-web/cgi/actions","hosted-web/cgi/lib/runtime"]'
      ;;
    llm-foundations)
      printf '%s' '["docs/HOW_ARTIFICER_LLMS_WORK.md"]'
      ;;
    ollama-runtime)
      printf '%s' '["docs/SETTINGS_AND_MODELS.md","docs/HOW_ARTIFICER_LLMS_WORK.md"]'
      ;;
    ollama-contributing)
      printf '%s' '["docs/OLLAMA_CONTRIBUTOR_PATH.md"]'
      ;;
    self-actuation)
      printf '%s' '["hosted-web/scripts/artificer-appctl","hosted-web/cgi/actions/self_actuation_orchestrate.sh","hosted-web/cgi/actions/self_actuation_policy_get.sh","hosted-web/cgi/actions/self_actuation_policy_set.sh","hosted-web/cgi/actions/self_actuation_audit_state.sh","hosted-web/cgi/lib/runtime/40i-self-actuation.sh","hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"]'
      ;;
    *)
      printf '%s' '[]'
      ;;
  esac
}

self_knowledge_topic_text() {
  topic_name=$1
  case "$topic_name" in
    overview)
      self_knowledge_overview_text
      ;;
    gui)
      self_knowledge_gui_text
      ;;
    architecture)
      self_knowledge_architecture_text
      ;;
    llm-foundations)
      self_knowledge_llm_foundations_text
      ;;
    ollama-runtime)
      self_knowledge_ollama_runtime_text
      ;;
    ollama-contributing)
      self_knowledge_ollama_contributing_text
      ;;
    self-actuation)
      self_knowledge_self_actuation_text
      ;;
    *)
      return 1
      ;;
  esac
}

self_knowledge_summary_text() {
  cat <<'EOF'
Artificer can teach and explain itself through seven grounded topics: overview, gui, architecture, llm-foundations, ollama-runtime, ollama-contributing, and self-actuation.
Use the exact GUI labels, file paths, and runtime boundaries in explanations, and mark unknown details as inferred when evidence is missing.
EOF
}
