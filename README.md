# Artificer

Artificer is a local-first AI assistant that runs against local models, keeps
workspaces on disk, and exposes native desktop, hosted desktop, headless, and
mobile thin-client surfaces from one repository.

The public runtime contract is simple:

- install Artificer for your platform
- run `artificer` or open `Artificer.app`
- add a workspace and start working

App Forge is not required for installed releases. The native desktop and mobile
sources are still generated through the Forge native pipeline so the UI can stay
reproducible across platforms.

## Supported Platforms

Artificer currently targets the same desktop platform set tracked in Wizardry,
plus Android and iOS mobile thin clients.

| Platform | Status | Artifact |
| --- | --- | --- |
| macOS | supported | `.app` bundle zip |
| Debian / Ubuntu | supported via portable Linux bundle | `.tar.gz` |
| NixOS | supported via portable Linux bundle | `.tar.gz` |
| Arch | supported via portable Linux bundle | `.tar.gz` |
| Android | supported as a mobile thin client | APK artifact |
| iOS | supported as a mobile thin client | simulator app zip artifact |
| Windows | no native support planned (WSL only if you know what you are doing) | none |

## Runtime Requirements

- [Ollama](https://ollama.com/) installed and running
- at least one local model installed in Ollama
- Wizardry runtime, auto-installed by `./install` if missing
- `python3` and `perl` available for advanced runtime pipelines; details:
  [docs/RUNTIME_DEPENDENCIES.md](docs/RUNTIME_DEPENDENCIES.md)

Artificer no longer depends on App Forge for install or launch, but it still
uses the Wizardry runtime internally.

## Install

### From a release artifact

1. Download the artifact for your platform from GitHub Releases.
2. Unpack it.
3. Run the bundled installer:

```sh
./install
```

This installs:

- the standalone runtime under `~/.local/share/artificer/app`
- a launcher at `~/.local/bin/artificer`
- desktop integration on macOS or Linux

### From a source checkout

```sh
./install
```

Then start Artificer with:

```sh
artificer
```

On macOS you can also open `Artificer.app` after install.

## Quick Start

```sh
artificer
```

The launcher will:

1. prepare the served Artificer site
2. start the local Artificer server if needed
3. print the local URL
4. open the app in your browser

## Native Desktop And Mobile

From the Forge app list, select `Artificer (native)` and run the native desktop
target.

From this checkout:

```sh
sh scripts/render-native-desktop.sh
swift build --package-path generated/macos
swift run --package-path generated/macos
```

The native desktop app locates Artificer core in this order:

- `ARTIFICER_CORE_ROOT`
- the saved native app setting
- `vendor/artificer`
- sibling `../artificer`
- `~/.local/share/artificer/app`
- `~/git/artificer`

Durable native UI Preferences live in
`${XDG_CONFIG_HOME:-$HOME/.config}/artificer/ui-prefs.env`. Native runtime
state, including voice automation status and logs, lives under
`${XDG_STATE_HOME:-$HOME/.local/state}/artificer-native`.

Implemented natively:

- runtime health and model status
- workspace list and add-workspace via native open panel
- session list, transcript view, new session, queued message, and run-next
- native attachment upload through the existing Artificer attachment pipeline,
  including image/document metadata and queued-run attachment IDs
- dictation controls backed by Artificer's local dictation backend, with native
  install/check/cancel controls and live waveform telemetry while recording
- Codex Desktop work-check setting for Artificer self-improvement runs, backed
  by the same `codex_work_check_enabled` option as hosted Artificer
- run policy controls for mode, compute budget, command execution, permission,
  programmer review, reflexive knowledge, and self-actuation
- Automations sidebar panel with add/list/run controls plus Preferences controls
  for launching, pausing, and checking due automations in the existing Artificer
  background runtime
- voice automation Preferences and a local app-hosted listener for
  user-configured local command phrases, built-in macOS-style commands,
  voice dictation into the frontmost app, current-notification reading aloud,
  and separate opt-ins for voice-to-Artificer prompts and voice-triggered
  Artificer actions
- Artificer Mobile as a native Android/iOS thin client, paired to this computer
  through the desktop Mobile bridge over localhost, explicit LAN exposure, or
  an optional Tor hidden service
- native Preferences for selecting the Artificer core root
- macOS and Linux generated source targets through the Forge native desktop IR
  pipeline

The mobile workspace lives in `artificer-mobile/`. Its source of truth is
`artificer-mobile/app-blueprint/mobile.ir.yaml`, rendered with:

```sh
sh artificer-mobile/scripts/render-native-mobile.sh
```

Rendered Android and iOS projects live under
`artificer-mobile/generated/mobile/`.

Mobile update behavior is platform-specific. Android direct APK builds check
GitHub Releases, download a newer `artificer-mobile` APK automatically, and
show an `Update` pill that hands off to Android's package installer. iOS builds
can check GitHub Releases and open the release page, but iOS app replacement
must still go through Apple-supported distribution such as App Store,
TestFlight, or an approved alternative marketplace.

Deferred on purpose:

- rich attachment previews and download/open affordances remain hosted for now;
  native upload and queued-run attachment handling are implemented
- the detailed self-improvement/assay dashboards stay in hosted Artificer; the
  native app exposes the underlying run/session controls without cloning every
  diagnostic visualization

Voice control expansion ideas for later:

- context-sensitive command lists that change with the active app
- more reliable named-control clicking for commands like `Click Done` across
  every native app
- VoiceOver command parity
- code-aware dictation modes for programming editors

## Source Layout

- [docs/README.md](docs/README.md): user and contributor docs
- [hosted-web/README.md](hosted-web/README.md): developer-facing app internals
- [docs/HEADLESS_RUNTIME_API.md](docs/HEADLESS_RUNTIME_API.md): headless
  embedding and operator-control runtime
- [tools/release](tools/release): installers, packagers, publish audit helpers
- [scripts/artificer-backend.sh](scripts/artificer-backend.sh): internal
  launcher/runtime helper
- [artificer-mobile](artificer-mobile): Android and iOS mobile thin-client
  source and generated projects

## Release Artifacts

The GitHub Actions builds create:

- `artificer-<version>-linux-x86_64.tar.gz`
- `artificer-<version>-linux-arm64.tar.gz`
- `artificer-<version>-macos.zip`
- `artificer-mobile-android`
- `artificer-mobile-ios`

The Linux bundles are portable artifacts for Debian, Ubuntu, NixOS, and Arch on
their corresponding CPU architecture. The mobile artifacts are CI-built
thin-client packages for testing against an Artificer desktop bridge. Tagged
release builds also attach the mobile artifacts to the GitHub Release so direct
Android builds can discover them for updates.

## Documentation

Human-facing docs, by intent:

- Start here: [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md),
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md),
  [docs/SETTINGS_AND_MODELS.md](docs/SETTINGS_AND_MODELS.md)
- Intelligence and reasoning: [docs/HOW_ARTIFICER_LLMS_WORK.md](docs/HOW_ARTIFICER_LLMS_WORK.md),
  [docs/OLLAMA_CONTRIBUTOR_PATH.md](docs/OLLAMA_CONTRIBUTOR_PATH.md),
  [docs/INTELLIGENCE_MENTORING_EXPLAINED.md](docs/INTELLIGENCE_MENTORING_EXPLAINED.md),
  [docs/CAPABILITY_ROADMAP.md](docs/CAPABILITY_ROADMAP.md)
- Capability measurement: [docs/CAPABILITY_BENCHMARKS.md](docs/CAPABILITY_BENCHMARKS.md)
- Reference: [docs/GLOSSARY.md](docs/GLOSSARY.md),
  [docs/REPO_OVERVIEW.md](docs/REPO_OVERVIEW.md),
  [docs/PROJECT_LAYOUT.md](docs/PROJECT_LAYOUT.md)
- Headless embedding/runtime API: [docs/HEADLESS_RUNTIME_API.md](docs/HEADLESS_RUNTIME_API.md)
- Release and contribution: [docs/release-notes/v0.1.0.md](docs/release-notes/v0.1.0.md),
  [docs/PUBLISHING_AUDIT.md](docs/PUBLISHING_AUDIT.md),
  [docs/CODEBASE_HARDENING_CHECKLIST.md](docs/CODEBASE_HARDENING_CHECKLIST.md),
  [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md)
- Runtime/tooling dependencies: [docs/RUNTIME_DEPENDENCIES.md](docs/RUNTIME_DEPENDENCIES.md)
- Third-party bundle attribution: [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)
- Full index: [docs/README.md](docs/README.md)
- Internals map: [hosted-web/README.md](hosted-web/README.md)

AI-facing documentation lives under [.github/](.github/) for workflows and
automation-facing repo configuration.

## License

Artificer is licensed under O.W.L. 3.0. See [LICENSE](LICENSE).
