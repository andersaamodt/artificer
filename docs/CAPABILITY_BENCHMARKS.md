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

The benchmark driver supports these workflows:

1. `manifest`
2. `plan`
3. `score`
4. `compare`
5. `external-compare`
6. `external-adapters`
7. `external-plan`
8. `external-run`

Use it like this:

```sh
sh hosted-web/scripts/capability-benchmark-cycle.sh manifest
sh hosted-web/scripts/capability-benchmark-cycle.sh plan --label candidate-a
sh hosted-web/scripts/capability-benchmark-cycle.sh score --label candidate-a
sh hosted-web/scripts/capability-benchmark-cycle.sh compare --baseline ~/.local/state/artificer/assay-reports/baseline-a-capability-benchmark-scorecard.json --candidate ~/.local/state/artificer/assay-reports/candidate-a-capability-benchmark-scorecard.json --label candidate-a-vs-baseline-a
sh hosted-web/scripts/capability-benchmark-cycle.sh external-adapters
sh hosted-web/scripts/capability-benchmark-cycle.sh external-plan --adapter mock-frontier --label frontier-a
sh hosted-web/scripts/capability-benchmark-cycle.sh external-run --adapter mock-frontier --label frontier-a
sh hosted-web/scripts/capability-benchmark-cycle.sh external-compare --external-baseline ~/.local/state/artificer/assay-reports/frontier-a-capability-benchmark-scorecard.json --candidate ~/.local/state/artificer/assay-reports/candidate-a-capability-benchmark-scorecard.json --external-name "Frontier Reference" --external-kind model --external-model gpt-5.4 --label candidate-a-vs-frontier-a
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
- whether an external baseline is still ahead, and on which families

This is the intended loop:

1. identify weak families
2. propose reversible improvements
3. measure them against the battery
4. keep only the changes that improve holdout performance

## How This Connects To Ordinary Runs

Capability benchmarks no longer only steer self-improvement proposals.

Artificer's ordinary controller prompt now receives a bounded capability-guidance block derived from the latest benchmark evidence.

That means measured deficits can shape normal behavior in the moment:

- research tasks can be pushed toward stricter source-grounding when research integration is weak
- programming tasks can be pushed toward tighter bounded verification when coding mutation is weak
- teaching tasks can be pushed toward misconception checks and reassessment when teaching remains behind
- repair tasks can be pushed toward stricter probe-then-fix behavior when admin environment repair is weak

The important constraint is boundedness.

Artificer does not dump the whole benchmark battery into every run.

It selects only the families that are both measured as weak and relevant to the current task or run mode, so benchmark evidence changes ordinary behavior without turning the controller prompt into generic noise.

Artificer now also records that capability-guidance focus into the run record.

That means a completed run can show:

- which benchmark families influenced the run
- why those families were selected
- the concrete operating guidance derived from them

Artificer can now also use that same capability-guidance trace before the run starts to reroute onto a better-matched installed model.

That means benchmark evidence can improve execution quality directly, not only explain decisions after the fact.

Artificer can also derive a benchmark-aware execution profile from that trace and raise reasoning floor or iteration minima for substantive runs when the task touches measured weak families.

That means benchmark evidence can influence not only which model runs, but also how much effort the run spends when the task sits in a family Artificer still needs to strengthen.

Artificer now also computes an internal family-closure report from recent scorecards.

That report tracks whether each capability family is:

- improving
- flat
- regressing
- new

and whether that direction has held across multiple benchmark scorecards.

This matters because a family can be trending the wrong way before it fully collapses into an obvious weak-family failure. Artificer can now see that earlier and use it in ordinary-run guidance and self-improvement prioritization.

This matters because benchmark-aware reasoning should be inspectable, not invisible. If a run was influenced by a measured weak family or sustained external deficit, the operator should be able to see that instead of guessing.

## External Baseline Lane

Internal compare results answer:

- "Did this change beat Artificer's previous baseline?"

External compare results answer:

- "Where does another model or workflow still beat Artificer?"

That distinction matters. Internal improvement can be real while Artificer still trails a stronger external reference on important families.

The `external-compare` workflow writes a first-class artifact:

- `*-capability-benchmark-external-compare.json`
- `*-capability-benchmark-external-compare.md`

Those artifacts keep:

- external baseline metadata such as name, kind, and model
- overall deltas against the external reference
- family-level gaps where the external baseline is still ahead
- family-level leads where Artificer is already ahead

Artificer also aggregates recent external compare artifacts into a persistent-gap view.

That lets self-improvement distinguish:

- a one-off external loss
- from a recurring external deficit that has shown up across multiple compare cycles

Persistent external gaps are the higher-leverage target because they are less likely to be noise.

Artificer now also tracks whether each recurring external gap is:

- `worsening`: the gap is opening further
- `flat`: the gap is not materially improving
- `closing`: the gap is shrinking
- `new`: there is only one recorded compare so far

That trend signal matters because self-improvement should spend more attention on recurring deficits that are worsening or flat than on deficits that are already closing.

Artificer now also keeps a compare-cycle streak for that current direction.

That means it can distinguish:

- a family that worsened once
- from a family that has been worsening for multiple compare cycles in a row

The same applies to closing and flat trajectories. This is a better prioritization signal because it tells Artificer whether an external deficit is transient, already recovering, or persistently moving the wrong way.

Self-improvement now reads those artifacts and treats the reported family gaps as measured targets, not vague aspirations.

## External Adapter Registry

Artificer now has a registry-backed adapter surface for external references.

That surface lets it:

- list named external adapters
- plan the exact command and output artifacts for a chosen adapter
- run the adapter into a validated external scorecard without ad hoc shell construction

The registry currently lives at:

- `hosted-web/tests/fixtures/artificer-capability-external-adapters-v1.tsv`

The important property is control, not the mock fixture itself. The adapter id is chosen from a trusted registry, and the resulting command is constructed from trusted template tokens rather than arbitrary user shell text.

## Automatic Adoption Policy

Self-improvement plugins are no longer treated as active just because they were proposed.

Artificer now stores an explicit adoption state for each plugin and keeps one current record per plugin lineage:

- `adopted`: two consecutive promotable benchmark compares improved or recovered the plugin's targeted families
- `trial`: promising, but still waiting for either the first direct family-level win or the second consecutive win needed for adoption
- `review`: mapped to a benchmark family, but the latest compare did not prove it should stay active
- `rejected`: two consecutive failed compares still showed weakness or failed to prove the plugin's mapped families

This keeps the self-improvement loop aligned with the standard above: measured transfer beats plausibility, and repeated evidence beats one lucky run.

## Operator Override And Lock

Artificer now exposes a separate operator policy layer for self-improvement plugins:

- `Automatic`: follow the benchmark-derived state
- `Force adopted`
- `Force trial`
- `Force review`
- `Force rejected`

If the operator also enables `Lock override`, that manual policy survives future lineage replacement when new benchmark runs refresh the plugin.

The automatic benchmark judgment is still stored and shown alongside the effective forced state, so manual intervention does not erase the evidence that automation would have used on its own.

## Automatic Stale-Pruning

Review and rejected plugins no longer accumulate forever.

Artificer now archives stale auto-managed plugins by benchmark compare-cycle age:

- `review` plugins archive after 3 later compare cycles without being refreshed
- `rejected` plugins archive after 2 later compare cycles without being refreshed
- manually forced plugins are excluded from this pruning path
- adopted and trial plugins are excluded from this pruning path

Archived plugins move into the self-improvement archive under the plugin state directory instead of staying mixed into the active set.

The settings surface now reports active plugin count plus archived stale-plugin count so the pruning is inspectable instead of silent.

## Archived Plugin Recovery

Pruning is not destructive by default.

Artificer now exposes archived plugins back through the self-improvement settings surface:

- archived plugins are listed separately from the active set
- each archive entry keeps its prior rationale, benchmark families, archived state, and archive reason
- restore is conservative and refuses to revive a lineage that is already active
- restored plugins come back disabled in locked `review` so they can be reconsidered without immediately re-entering automation
- restored plugins reset stale compare-cycle age against the latest benchmark compare count
- archive entries can also be removed permanently when they are no longer useful

## Why This Matters

This is the difference between:

- "Artificer gave a good answer once"

and:

- "Artificer improved on repeatable cross-domain tasks and the improvement transferred to holdout work"

The second standard is the one that matters.
