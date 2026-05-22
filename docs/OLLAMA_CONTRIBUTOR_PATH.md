# LLM + Ollama Contributor Path

This guide is for users who want to go beyond prompt usage and understand the stack deeply enough to contribute code upstream.

## Goal

Reach the point where you can:

1. explain how local LLM inference works end-to-end
2. debug model/runtime behavior with evidence
3. make small, tested contributions to Ollama (or similar local-model runtimes)

## Layer 1: LLM Fundamentals

You should be able to explain each item in plain language:

- tokenization and context windows
- transformer forward pass at a high level (attention + feed-forward)
- autoregressive decoding (next-token generation)
- sampling controls (for example temperature, top-p) and quality tradeoffs
- why hallucinations happen and how verification mitigates them

Minimum hands-on competency:

1. compare outputs from two different local models on the same prompt
2. identify when failures are model limitations vs prompt framing vs missing context
3. design a verification step that can falsify an incorrect answer

## Layer 2: Ollama Runtime Understanding

You should know the operational surfaces:

- local service behavior and model lifecycle
- model tags and local model inventory
- how model configuration/templates are controlled (for example with Modelfiles)
- how to inspect active runs and metadata

Minimum hands-on competency:

1. diagnose why a model is unavailable vs misconfigured vs too large for local resources
2. run a reproducible local smoke script for model pull/list/run/show checks
3. trace one request from client call to model output

## Layer 3: Contributor Readiness

Before opening a PR against a runtime codebase, you should be able to:

- reproduce a bug with a deterministic script
- add or update tests that fail before and pass after your change
- explain compatibility and rollback impact
- keep behavior changes separate from pure refactors

Recommended contribution sequence:

1. documentation clarification with tests/examples
2. small bug fix with targeted test coverage
3. performance or runtime behavior change with benchmark evidence

## Artificer Reflexive Teaching Surface

When `Reflexive knowledge` permission is enabled, Artificer can teach these layers directly:

- GUI and architecture self-explanation
- LLM fundamentals
- Ollama runtime behavior
- contributor-level progression guidance

CLI hooks for introspection:

- `artificer-appctl knowledge show`
- `artificer-appctl knowledge teach --topic llm-foundations`
- `artificer-appctl knowledge teach --topic ollama-runtime`
- `artificer-appctl knowledge teach --topic ollama-contributing`

## Self-Assessment Checklist

You are contributor-ready when you can answer these without handwaving:

1. Where does request context get limited, and why?
2. What evidence proves a quality issue is decoding/sampling vs model capability?
3. What test would catch your runtime bug if it regresses later?
4. What is your rollback plan if the patch harms reliability?
