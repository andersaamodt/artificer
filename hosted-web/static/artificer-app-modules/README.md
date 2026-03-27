# Artificer Frontend Modules

This directory is the canonical frontend source.

- Each `*.js` file is a load-ordered runtime module.
- Larger runtime fragments are split into ordered continuation files (`01...`, `01b...`, etc.) to keep review units smaller.
- `/pages/index.md` and `/pages/index.html` load these modules directly for local runtime.
- `tools/build-artificer-app.sh` concatenates these modules into `static/artificer-app.js` for fallback/packaging.

Module order is numeric by filename prefix and must remain deterministic.
