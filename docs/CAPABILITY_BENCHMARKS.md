# Capability Benchmarks

Artificer now has an explicit cross-domain benchmark battery for measuring real capability gains, not just local correctness or one-off demos.

The benchmark manifest lives at:

- `hosted-web/tests/fixtures/artificer-capability-benchmark-manifest-v1.tsv`

The driver script lives at:

- `hosted-web/scripts/capability-benchmark-cycle.sh`

## What It Measures

The current battery tracks six capability families:

- research and knowledge integration
- planning and architecture
- coding and bounded mutation
- review and document quality
- teaching and long-context reassessment
- admin setup and environment repair

Each family maps to an existing Artificer assay cycle. That keeps the benchmark battery grounded in real behavior rather than a second disconnected evaluation framework.

## What The Driver Does

The benchmark driver supports four workflows:

1. `manifest`
2. `plan`
3. `score`
4. `compare`

Use it like this:

```sh
sh hosted-web/scripts/capability-benchmark-cycle.sh manifest
sh hosted-web/scripts/capability-benchmark-cycle.sh plan --label candidate-a
sh hosted-web/scripts/capability-benchmark-cycle.sh score --label candidate-a
sh hosted-web/scripts/capability-benchmark-cycle.sh compare --baseline ~/.local/state/artificer/assay-reports/baseline-a-capability-benchmark-scorecard.json --candidate ~/.local/state/artificer/assay-reports/candidate-a-capability-benchmark-scorecard.json --label candidate-a-vs-baseline-a
```

## Intended Workflow

1. Generate a plan for a named benchmark label.
2. Run the listed regressions, holdout, and transfer commands for each family.
3. Build a scorecard from the resulting transfer reports.
4. Compare the new scorecard against a baseline before keeping any self-improvement change.

Do not promote a self-improvement idea because it sounds plausible.

Promote it only if the scorecard improves and the comparison result stays promotable.

## How This Connects To Self-Improvement

Artificer's self-improvement runtime evidence now reads the latest capability benchmark scorecards and comparisons from the assay reports directory.

That means self-improvement runs can see:

- the latest benchmark recommendation
- weak capability families
- the current highest-leverage gaps
- whether a candidate scorecard actually beat a baseline

This is the intended loop:

1. identify weak families
2. propose reversible improvements
3. measure them against the battery
4. keep only the changes that improve holdout performance

## Why This Matters

This is the difference between:

- "Artificer gave a good answer once"

and:

- "Artificer improved on repeatable cross-domain tasks and the improvement transferred to holdout work"

The second standard is the one that matters.
