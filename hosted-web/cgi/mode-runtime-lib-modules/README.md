# Mode Runtime Library Modules

`../mode-runtime-lib.sh` is the canonical load surface.

It sources these concern-oriented modules in lexical order:

- `00-paths-and-primitives.sh`
- `10-failure-taxonomy.sh`
- `20-improvement-proposals.sh`
- `30-controller-variants.sh`
- `40-quality-scorecard.sh`
- `50-bootstrap-seeding.sh`
- `60-mode-runtime-core.sh`
- `70-skill-runtime.sh`
- `80-response-builders.sh`

The loader file remains stable so existing runtime call sites do not need to change.
