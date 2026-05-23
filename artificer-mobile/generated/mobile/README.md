# Artificer Mobile Native Mobile Build

Generated from `app-blueprint/mobile.ir.yaml`.

- Android output is a plain Gradle Android project with no app-store SDK dependency.
- iOS output is a SwiftUI project generated through XcodeGen.
- The app is a thin client for the Artificer Mobile bridge exposed by desktop Preferences.
- Android direct builds check GitHub Releases, auto-download newer APK assets, and expose an Update pill that launches Android's package installer.
- iOS builds can detect GitHub mobile releases and open the release page; installing a replacement app still uses Apple-supported update channels.
