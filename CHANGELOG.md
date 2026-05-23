# Changelog

## Unreleased

### Added

- background automations scheduler script with platform daemon controls (`launchd`, `systemd --user`, `cron` fallback)
- API actions for scheduler status, enable/disable, and manual scheduler tick
- Settings UI controls for scheduler enablement, status refresh, and manual tick
- Linux release artifact matrix support for `x86_64` and `arm64`
- competitive self-improvement pipeline (`artificer` lane vs challenger lane) with scored merge output
- self-improvement evidence bundle support beyond papers: web signals, runtime telemetry, repo signals, and platform checks
- self-improvement run options API and settings controls for objective, challenger model, and source toggles

### Changed

- release workflow now builds macOS app artifacts directly and publishes both Linux architecture bundles
- self-improvement plugin metadata now stores lane/model provenance, domain tags, evidence refs, admin actions, and risk level
- project license updated from O.W.L. 2.0 to O.W.L. 3.0

### Fixed

- LSP code-context probing now reads back-to-back server messages reliably during the full release test suite

## 0.1.0 - 2026-03-23

First GitHub-publishable Artificer release surface.

### Added

- standalone `artificer` launcher
- standalone `install` and `uninstall` scripts
- Linux portable release bundle builder
- macOS `.app` bundle builder
- GitHub Actions build and release workflow
- publish-surface audit document and audit script
- explicit version file and O.W.L. 2.0 license

### Changed

- public docs now describe the executable-first install path
- App Forge is no longer part of the public Artificer install story
- release gates now enforce remote, GUI, visual, multi-tool, freshness, operator, document, and long-horizon families already closed in the repo
