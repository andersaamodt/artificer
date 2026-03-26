# Getting Started

## What You Need

- macOS, Debian/Ubuntu, NixOS, or Arch
- [Ollama](https://ollama.com/) installed and running
- at least one local model installed in Ollama
- Wizardry installed at `~/.wizardry` or exposed through `WIZARDRY_DIR`

App Forge is not required.

## Install Artificer

If you downloaded a release bundle, unpack it first and then run:

```sh
./install
```

If you are running from a source checkout, run the same command from the repo root:

```sh
./install
```

The installer creates:

- `~/.local/bin/artificer`
- `~/.local/share/artificer/app`
- desktop integration on macOS or Linux

## Start Artificer

```sh
artificer
```

Artificer prints the local URL it started and opens it in your browser.

## First Run

1. Add a workspace.
2. Confirm the model list is populated.
3. Start a conversation.
4. Ask a grounded question about the workspace.

Example:

```text
Explain which files matter most for startup in this project.
```

## If No Models Appear

Run:

```sh
ollama list
```

If that fails, fix Ollama first.

## If Artificer Does Not Open

Run:

```sh
artificer url
```

Then open the printed URL manually.

## If You Change Source Files In A Checkout

Re-run:

```sh
./install
```

That refreshes the installed runtime from the current checkout.

## Optional: Background Automations Scheduler

Artificer can run due automations in the background (outside a browser tab).

```sh
artificer automations status
artificer automations enable
artificer automations disable
```

Manual scheduler tick:

```sh
artificer automations tick
```
