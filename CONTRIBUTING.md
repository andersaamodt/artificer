# Contributing

## Development Priorities

1. Keep the public runtime contract stable: `artificer`, `install`, release bundles, and GitHub Actions.
2. Treat `hosted-web/` quality and release gates as merge blockers for meaningful behavior changes.
3. Prefer small, reviewable commits.

## Local Checks

Run the checks relevant to your change.

Packaging and publish surface:

```sh
sh -n artificer install uninstall
sh -n tools/release/*.sh
sh tools/release/build-release-bundle.sh dist
```

Runtime helper:

```sh
sh -n scripts/artificer-backend.sh
```

## GUI Changes

Use Safari automation for GUI changes and verify layout and task flow manually enough to catch real regressions.

## Docs Rule

Public docs must not require App Forge and should not hardcode personal workstation paths.
