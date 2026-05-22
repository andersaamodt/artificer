# Publishing Audit

Date: 2026-03-26

## Scope

This audit covers the GitHub-facing publish surface:

- root docs
- install and launcher scripts
- release tooling
- GitHub Actions release pipeline

## Current Publish Surface Status

- standalone install and launcher paths are in place
- release artifact scripts exist for Linux (`x86_64`, `arm64`) and macOS
- release workflow publishes from GitHub context (no hardcoded Artificer owner/repo target)
- third-party JS bundle attribution is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- public docs avoid workstation-specific startup instructions

## Verification Gates

- publish surface path/name scanner: [tools/release/audit-publish-surface.sh](../tools/release/audit-publish-surface.sh)
- neutral publish defaults regression test: [tools/release/test-publish-surface-neutral-defaults.sh](../tools/release/test-publish-surface-neutral-defaults.sh)
- release suite runner: [tools/release/run-release-tests.sh](../tools/release/run-release-tests.sh)

## Notes

- Wizardry runtime bootstrap defaults still point to the canonical Wizardry repository via `ARTIFICER_WIZARDRY_REPO_URL`; this is runtime dependency sourcing, not an Artificer publish target.
- Developer-only assay/probe content may still include internal implementation naming, but this is outside the user publish/install contract.

## Recommendation

Publish is ready once the release workflow and release test suite are green.
