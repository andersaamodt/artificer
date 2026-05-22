# Headless Runtime API

Artificer now exposes a stable local control plane so other tools can drive the same runtime the GUI uses instead of rebuilding their own agent stack.

This is a local CGI JSON API, not a public hosted service.

## Why It Exists

- external tools can create sessions, send messages, inspect runs, and answer approvals
- self-actuation can mutate projects, threads, and automations through the same bounded surface
- coding workflows can request structured code context without scraping the GUI
- runtime behavior stays auditable because GUI, self-actuation, and embedding all share one backend contract

## Main Surfaces

Each surface is exposed as one CGI action under `hosted-web/cgi/actions/`.

- `control_plane_describe`
  - capability discovery and API metadata
- `control_plane_projects`
  - `list`, `get`, `add`, `rename`, `delete`
- `control_plane_sessions`
  - `list`, `get`, `create`, `archive`, `message`, `run-next`, `events`, `stream`
- `control_plane_attention`
  - `list`, `approval-answer`, `decision-answer`
- `control_plane_automations`
  - `list`, `get`, `upsert`, `toggle`, `run-now`, `delete`
- `control_plane_self_actuation`
  - `preview`, `apply`, `policy-get`, `policy-set`, `audit`
- `control_plane_health`
  - runtime health and surface availability
- `control_plane_code_context`
  - LSP-backed file context for coding tasks

The headless API version is currently `v1`.

## Embedding Client

The shell-first client is:

- `hosted-web/scripts/artificer-runtime-client`

It is the intended entrypoint for local tools that want to drive Artificer without reimplementing the API transport.

Examples:

```sh
hosted-web/scripts/artificer-runtime-client describe
hosted-web/scripts/artificer-runtime-client health
hosted-web/scripts/artificer-runtime-client project add --path "$PWD" --name "Current Repo"
hosted-web/scripts/artificer-runtime-client session create --workspace-id "$workspace_id" --title "Refactor Plan"
hosted-web/scripts/artificer-runtime-client session message --workspace-id "$workspace_id" --conversation-id "$conversation_id" --prompt "Audit the repo" --run-mode assistant
hosted-web/scripts/artificer-runtime-client session run-next --workspace-id "$workspace_id" --conversation-id "$conversation_id" --stream-session "embed-$(date +%s)"
```

## Sessions, Events, And Streams

`control_plane_sessions` separates durable session state from stream polling:

- `get`
  - full session envelope, including queue state, attention state, messages, and trace
- `run-next`
  - dequeues the next queued session item and executes it through the same backend `run` action the GUI uses
  - returns the refreshed session envelope plus nested run result JSON
  - accepts optional `stream_session` so embedding clients can poll `stream` concurrently or after completion
  - returns an empty `stream_session` when no new run starts, and the actual running stream session when the session is already busy
- `events`
  - run/event trace only
- `stream`
  - pass-through polling of the active token stream

The trace surface includes:

- active stream session id
- running event id
- running start time
- task status
- run events
- tool hook records

That makes ordinary runs inspectable by other tools without screen scraping.

## Durable Attention Workflow

Approvals and decisions are first-class runtime objects.

- `control_plane_attention list`
  - lists pending approvals and decision requests across sessions
- `approval-answer`
  - submits allow or deny decisions back into the runtime
- `decision-answer`
  - submits user decisions back into the runtime

This is the same durable workflow used by Artificer itself when runs need user confirmation.

For a fully headless lifecycle:

1. `session message`
2. `session run-next`
3. `session stream` while active
4. `attention list` and `approval-answer` / `decision-answer` when blocked
5. `session run-next` again to resume after an answered gate

## Self-Actuation Through The Control Plane

Self-actuation no longer mutates workspace state through ad hoc direct calls.

It now routes create/archive/toggle/apply operations through the same project, session, and automation control-plane actions that external tools can use.

This matters because it gives self-actuation:

- previewable changes
- confirm-token gating
- idempotent apply
- auditable outcomes

## LSP Code Context

`control_plane_code_context` exposes compact code intelligence for a single workspace file.

When a suitable local language server is available, Artificer can surface:

- diagnostics
- document symbols
- compact summary text

The default probe script is:

- `hosted-web/scripts/artificer-lsp-probe.py`

This is optional. If no language server is present, the surface fails cleanly instead of breaking the runtime.

## Tool Hooks And Prompt Enrichment

Artificer now has an internal tool lifecycle hook surface.

- pre-hook
  - captures normalized command, policy decision, and relevant code context
- post-hook
  - captures final status and compact output preview

The same coding evidence pipeline also enriches normal runs with compact structured evidence such as:

- tracked git status
- LSP coding context for referenced files

This is intentionally internal. It improves reasoning quality and traceability without introducing a general plugin system yet.

## Design Constraints

- local-first
- stable JSON envelopes
- small focused actions
- same backend surface for GUI, self-actuation, and external embedding
- no repo-local assay or generated artifacts

This is an infrastructure feature. It exists to make Artificer a better runtime other tools can drive, not just a better standalone GUI app.
