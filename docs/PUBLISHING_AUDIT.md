# Publishing Audit

Date: 2026-03-24

## Scope

This audit covers the GitHub-facing publish surface:

- root docs
- install and launcher scripts
- release tooling
- GitHub Actions

## Fixed In This Pass

- added a standalone Artificer launcher and installer independent of App Forge
- replaced public docs that hardcoded local workstation paths as startup instructions
- added release packaging scripts for Linux and macOS
- added Linux release matrix support for `x86_64` and `arm64` artifact names
- added a publish-surface audit script at [tools/release/audit-publish-surface.sh](../tools/release/audit-publish-surface.sh)
- added GitHub Actions release/build workflow support
- added version, changelog, license, and release notes
- added standalone background automations scheduler controls and daemon actions

## Remaining Internal References

The repo still contains workstation-specific absolute paths and legacy Forge-era naming in developer-only surfaces, mainly under `hosted-web/` assay and quality documents.

Current known categories:

- internal quality trackers with absolute clickable file paths
- internal CSS and DOM names that still use `forge-shell`
- internal runtime coupling to Wizardry web helpers such as `web-wizardry`

## Publish Assessment

### Ready

- standalone install path
- standalone launcher path
- release artifact generation
- public README/getting-started docs
- license and release metadata

### Not Yet Removed Everywhere

- all personal-path references from deep internal development docs
- all legacy internal naming from non-user-visible implementation details

## Recommendation

Publish is reasonable once the release workflow artifacts are green.

A later hygiene pass should scrub remaining personal absolute paths from the deep developer assay documents, but those are no longer on the primary user path.
