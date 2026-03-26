# Project Layout

## Public Surface

These are the files that matter for install, launch, and release:

- [README.md](../README.md)
- [artificer](../artificer)
- [install](../install)
- [uninstall](../uninstall)
- [tools/release](../tools/release)
- [.github/workflows](../.github/workflows)

## Main Application

The served app itself lives here:

- [hosted-web/pages/index.md](../hosted-web/pages/index.md)
- [hosted-web/static/artificer-app.js](../hosted-web/static/artificer-app.js)
- [hosted-web/cgi/artificer-api](../hosted-web/cgi/artificer-api)
- [hosted-web/cgi/actions](../hosted-web/cgi/actions)
- [hosted-web/cgi/lib](../hosted-web/cgi/lib)

## Internal Runtime Helper

The launcher and installers delegate to:

- [scripts/artificer-backend.sh](../scripts/artificer-backend.sh)
- [scripts/artificer-automations.sh](../scripts/artificer-automations.sh)

That script is internal implementation detail. End users are expected to run `artificer`, not backend helper commands.

## Runtime State

Important runtime state lives outside the repo:

```text
~/.local/share/artificer/
~/.local/state/artificer/
~/sites/.sitedata/
```

## Developer Tooling

The quality gates, probes, assay fixtures, and release wrappers live under `hosted-web/`. They are part of development and release validation, not the normal user install path.
