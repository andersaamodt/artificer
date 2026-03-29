#!/bin/sh
set -eu

self_knowledge_registry_version() {
  printf '%s' "2026-03-29"
}

self_knowledge_topics_json() {
  printf '%s' '["overview","gui","architecture","llm-foundations","ollama-runtime","ollama-contributing"]'
}

self_knowledge_valid_topics_csv() {
  printf '%s' "overview,gui,architecture,llm-foundations,ollama-runtime,ollama-contributing"
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
    *)
      return 1
      ;;
  esac
}

self_knowledge_summary_text() {
  cat <<'EOF'
Artificer can teach and explain itself through six grounded topics: overview, gui, architecture, llm-foundations, ollama-runtime, and ollama-contributing.
Use the exact GUI labels, file paths, and runtime boundaries in explanations, and mark unknown details as inferred when evidence is missing.
EOF
}
