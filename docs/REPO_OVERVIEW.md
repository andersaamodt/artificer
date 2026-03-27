# Repo Overview

This is the quick, accessible explanation of how the repository is organized.

The easiest way to picture it is as three layers.

## 1. The Front Door

At the top level, the repo contains a few shell files and documentation files. This is the lightweight outer shell.

Important examples:

- [`../README.md`](../README.md)
- [`../index.html`](../index.html)
- [`../style.css`](../style.css)

These are not where most of Artificer’s intelligence lives.

## 2. The Actual Application

Most of the real app lives under [`../hosted-web/`](../hosted-web/).

That folder contains:

- page definitions
- frontend JavaScript
- backend CGI code
- test and release scripts
- deeper implementation docs

If you want to understand how Artificer actually behaves, this is usually the directory that matters most.

## 3. Local Build And Serve Support

The top-level [`../scripts/`](../scripts/) directory contains local helper scripts that build, sync, and serve the app.

The most important one for day-to-day local use is [`../scripts/artificer-backend.sh`](../scripts/artificer-backend.sh).

## The Three Most Important Source Files

If someone only reads three files to understand the app, these are usually the right ones:

- [`../hosted-web/pages/index.md`](../hosted-web/pages/index.md)
- [`../hosted-web/static/artificer-app-modules/`](../hosted-web/static/artificer-app-modules/)
- [`../hosted-web/cgi/artificer-api`](../hosted-web/cgi/artificer-api)

In plain English:

- `index.md` describes what the app shows
- `artificer-app-modules/*.js` describes how the browser behaves
- `artificer-api` describes how the backend behaves

## Short Version

If you want the shortest possible map:

- root: entrypoint and docs
- `docs/`: human-facing explanations
- `hosted-web/`: the real app
- `scripts/`: local run/build helpers
