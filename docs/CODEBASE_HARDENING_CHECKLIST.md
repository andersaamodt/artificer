# Artificer Codebase Hardening Checklist

This checklist tracks the remaining work to make Artificer production-grade, Wizardry-aligned, and didactic in code quality.

## 1) Backend Modularity

- [x] Split `hosted-web/cgi/actions/run_parts/run-part-004.sh` into named submodules with a stable loader.
- [x] Split `hosted-web/cgi/mode-runtime-lib.sh` into named submodules grouped by concern.
- [x] Split `hosted-web/cgi/lib/reasoning/30c-reasoning-contracts.sh` into named submodules grouped by concern.
- [x] Keep canonical entrypoint files stable so action wiring does not break.
- [x] Keep generated-artifact policy tests passing.

Done criteria:

- Canonical files remain load points, but core logic is moved into smaller concern-oriented files.
- Release suite passes.

## 2) Frontend Modularity

- [x] Break large frontend module files into smaller concern-oriented files.
- [x] Keep deterministic build order and preserve runtime behavior.
- [x] Ensure each new file has a clear boundary (boot, storage, render, API sync, automations, settings, events).

Done criteria:

- No giant single-file concentration for major UI concerns.
- Build output is deterministic and tests pass.

## 3) Unit Coverage Expansion

- [ ] Add unit-style tests for key runtime behaviors (boot flow, storage rules, automations rendering, action contract assumptions).
- [ ] Add tests for newly introduced module boundaries and loaders.
- [ ] Keep release contract tests as integration safety net.

Done criteria:

- New tests fail when the covered behavior is intentionally broken.
- Release suite passes in full.

## 4) Desktop Durability Policy

- [ ] Move durable desktop UI state away from browser-owned storage.
- [ ] Add backend preference actions and file-backed storage.
- [ ] Keep localStorage as non-durable fallback/cache only where needed.

Done criteria:

- Desktop-preferred state paths are backend file APIs.
- Browser storage is no longer the primary durable source for desktop.

## 5) CI Lint Rigor

- [ ] Add dedicated shell lint workflow(s) for `checkbashisms` and shell safety checks.
- [ ] Keep build workflow focused on build + release tests.
- [ ] Ensure lint failures block regressions.

Done criteria:

- PRs get explicit shell lint signal in CI.

## 6) Runtime Dependency Tightening

- [ ] Reduce non-shell dependencies in core runtime paths where practical.
- [ ] Keep probe/dev scripts allowed to use Python/Perl when justified.
- [ ] Document any remaining hard requirements.

Done criteria:

- Core runtime path has fewer non-POSIX helper invocations.

## 7) Third-Party Attribution

- [ ] Add third-party notices for bundled minified JS assets.
- [ ] Reference versions/license info used at bundle time.

Done criteria:

- Repository includes clear attribution and licensing metadata for bundled third-party assets.

## 8) Publish Surface Cleanup

- [ ] Remove personal-default publish settings from release scripts.
- [ ] Require explicit config or neutral defaults.

Done criteria:

- No personal identifiers are used as default release/publish values.

## 9) Final Verification

- [ ] Run full release suite.
- [ ] Verify working tree cleanliness and repo size profile.
- [ ] Re-audit for sensitive path/name leakage.

Done criteria:

- Tests pass, tree is clean, and publish surface is ready.
