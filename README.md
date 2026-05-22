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

Durable native UI Preferences live in
`${XDG_CONFIG_HOME:-$HOME/.config}/artificer/ui-prefs.env`. Native runtime
state, including voice automation status and logs, lives under
`${XDG_STATE_HOME:-$HOME/.local/state}/artificer-native`.

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
- Automations sidebar panel with add/list/run controls plus Preferences controls
  for launching, pausing, and checking due automations in the existing Artificer
  background runtime
- voice automation Preferences and a local launchd-backed listener for
  allowlisted phrases such as `main screen turn on`, with separate opt-ins for
  voice-to-Artificer prompts and voice-triggered Artificer actions
- Artificer Mobile as a native Android/iOS thin client, paired to this computer
  through the desktop Mobile bridge over localhost, explicit LAN exposure, or
  an optional Tor hidden service
- native Preferences for selecting the Artificer core root
- macOS and Linux generated source targets through the Forge native desktop IR
  pipeline

The mobile workspace lives in `artificer-mobile/`. Its source of truth is
`artificer-mobile/app-blueprint/mobile.ir.yaml`, rendered with
`sh artificer-mobile/scripts/render-native-mobile.sh` into reproducible Android
and iOS projects under `artificer-mobile/generated/mobile/`.

Deferred on purpose:

- rich attachment previews and download/open affordances remain hosted for now;
  native upload and queued-run attachment handling are implemented.
- the detailed self-improvement/assay dashboards stay in hosted Artificer; the
  native app exposes the underlying run/session controls without cloning every
  diagnostic visualization.

## License

This is a native port of Artificer and inherits Artificer's O.W.L. license.
