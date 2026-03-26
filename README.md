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
- Wizardry installed at `~/.wizardry` or exposed through `WIZARDRY_DIR`

Artificer no longer depends on App Forge for install or launch, but it still uses the Wizardry web runtime internally.

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

## Project Documents

- [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)
- [docs/PROJECT_LAYOUT.md](docs/PROJECT_LAYOUT.md)
- [docs/PUBLISHING_AUDIT.md](docs/PUBLISHING_AUDIT.md)
- [CHANGELOG.md](CHANGELOG.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Artificer is licensed under O.W.L. 2.0. See [LICENSE](LICENSE).
