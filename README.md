# Artificer

Artificer is a local-first AI assistant that runs against local models, keeps workspaces on disk, and exposes one executable entrypoint per supported platform.

The public runtime contract is simple:

- install Artificer for your platform
- run `artificer` or open `Artificer.app`
- add a workspace and start working

App Forge is not required.

## Supported Platforms

Artificer currently targets the same desktop platform set tracked in Wizardry:

| Platform | Status | Artifact |
| --- | --- | --- |
| macOS | supported | `.app` bundle zip |
| Debian / Ubuntu | supported via portable Linux bundle | `.tar.gz` |
| NixOS | supported via portable Linux bundle | `.tar.gz` |
| Arch | supported via portable Linux bundle | `.tar.gz` |
| Android | unsupported | none |
| Windows | no native support planned (WSL only if you know what you are doing) | none |

## Runtime Requirements

- [Ollama](https://ollama.com/) installed and running
- at least one local model installed in Ollama
- Wizardry runtime (auto-installed by `./install` if missing)

Artificer no longer depends on App Forge for install or launch, but it still uses the Wizardry runtime internally.

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

## Source Layout

- [docs/README.md](docs/README.md): user and contributor docs
- [hosted-web/README.md](hosted-web/README.md): developer-facing app internals
- [tools/release](tools/release): installers, packagers, publish audit helpers
- [scripts/artificer-backend.sh](scripts/artificer-backend.sh): internal launcher/runtime helper

## Release Artifacts

The GitHub Actions build creates:

- `artificer-<version>-linux-x86_64.tar.gz`
- `artificer-<version>-linux-arm64.tar.gz`
- `artificer-<version>-macos.zip`

The Linux bundles are portable artifacts for Debian, Ubuntu, NixOS, and Arch on their corresponding CPU architecture.

## Documentation

Human-facing documentation:

- [docs/README.md](docs/README.md): documentation index and reading order
- [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md): install and first-run setup
- [docs/USER_GUIDE.md](docs/USER_GUIDE.md): day-to-day usage workflow
- [docs/SETTINGS_AND_MODELS.md](docs/SETTINGS_AND_MODELS.md): runtime knobs, model behavior, and automations
- [docs/HOW_ARTIFICER_LLMS_WORK.md](docs/HOW_ARTIFICER_LLMS_WORK.md): system-level model behavior explanation
- [docs/INTELLIGENCE_MENTORING_EXPLAINED.md](docs/INTELLIGENCE_MENTORING_EXPLAINED.md): intelligence iteration approach
- [docs/GLOSSARY.md](docs/GLOSSARY.md): terminology reference
- [docs/REPO_OVERVIEW.md](docs/REPO_OVERVIEW.md): high-level repository map
- [docs/PROJECT_LAYOUT.md](docs/PROJECT_LAYOUT.md): public and internal layout details
- [docs/PUBLISHING_AUDIT.md](docs/PUBLISHING_AUDIT.md): publish-surface audit notes
- [docs/release-notes/v0.1.0.md](docs/release-notes/v0.1.0.md): current release notes
- [CHANGELOG.md](CHANGELOG.md): release history
- [CONTRIBUTING.md](CONTRIBUTING.md): contributor workflow and checks
- [hosted-web/README.md](hosted-web/README.md): internals map for developers

AI-facing documentation lives under [.github/](.github/) (workflows and automation-facing repo configuration).

## License

Artificer is licensed under O.W.L. 2.0. See [LICENSE](LICENSE).
