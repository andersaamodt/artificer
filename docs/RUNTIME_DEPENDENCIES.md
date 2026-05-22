# Runtime Dependencies

Artificer prefers POSIX shell for runtime paths, but some features rely on extra system tools.

## Required For Core Runtime

- POSIX shell (`/bin/sh`)
- standard POSIX userland (`awk`, `sed`, `grep`, `find`, `mktemp`, `tr`, `wc`)
- `python3` (used by automations schedule normalization and self-improvement pipelines)
- `perl` (used by advanced run parsing/normalization and patch/runtime transforms)

## Optional / Feature-Gated

- `node`: used for JS syntax checks when available
- `jq`: used by selected diagnostic/probe tooling
- Ollama CLI/runtime: required for local model inference

## Dependency Tightening Notes

- Core bootstrap text-normalization paths now include shell fallback behavior when `perl` is unavailable for basic sanitization.
- Probe and assay scripts may continue to use Python/Perl where they provide major clarity or robustness benefits.
