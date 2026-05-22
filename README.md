# Artificer

Artificer is a platform-native desktop front end for the existing Artificer
runtime. It is built with the Forge native desktop pipeline and keeps the
existing Artificer core as the source of truth for workspaces, sessions,
automations, model routing, and queue execution.

## Run

From the Forge app list, select `Artificer (native)` and run the native desktop
target.

From this checkout:

```sh
sh scripts/render-native-desktop.sh
swift build --package-path generated/macos
swift run --package-path generated/macos
```

The app locates Artificer core in this order:

- `ARTIFICER_CORE_ROOT`
- the saved native app setting
- `vendor/artificer`
- sibling `../artificer`
- `~/.local/share/artificer/app`
- `~/git/artificer`

Durable native UI preferences live in
`${XDG_CONFIG_HOME:-$HOME/.config}/wizardry-apps/artificer-native`.

## Feature Scope

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
- automation list plus Preferences controls for launching, pausing, and ticking
  the existing Artificer background runtime
- native Preferences for selecting the Artificer core root
- macOS and Linux generated source targets through the Forge native desktop IR
  pipeline

Deferred on purpose:

- rich attachment previews and download/open affordances remain hosted for now;
  native upload and queued-run attachment handling are implemented.
- the detailed self-improvement/assay dashboards stay in hosted Artificer; the
  native app exposes the underlying run/session controls without cloning every
  diagnostic visualization.

## License

This is a native port of Artificer and inherits Artificer's O.W.L. license.
