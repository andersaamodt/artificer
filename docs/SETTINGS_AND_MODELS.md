# Settings And Models

This document explains the parts of Artificer that most strongly change how the app feels in practice.

## Models: Which Brain Is Being Used

The model picker answers a simple question:

```text
Which brain is Artificer using right now?
```

This matters because models are not interchangeable.

Broadly:

- larger models are often better at difficult reasoning
- smaller models are often faster and lighter
- coding-tuned models often perform better on engineering tasks
- some models are simply more stable than others

## Why Model Loading Matters So Much

If the model list is not ready, the app is not really ready.

That is why Artificer now tries to have models and conversations loaded before the interface is considered booted. A UI that appears early but is still missing core state feels broken, even if it eventually catches up.

## Runtime Settings

Runtime settings are the behavior knobs around the model.

They influence things like:

- GPU use
- review strictness
- command safety
- background automations scheduling
- other system-level behavior rules

This matters because Artificer is not just a text box over an LLM. It is a small operating system around one.

## Automations Scheduler

Automations can run while the app is open via in-app ticks, and optionally in the background via a platform scheduler.

In Settings, the scheduler controls let you:

- enable or disable background scheduling
- refresh current daemon/timer status
- run one scheduler tick now

This makes recurring automation runs more reliable when no browser tab is open.

## Self-Improvement

The self-improvement feature is one of the clearest examples of what makes Artificer unusual.

It lets Artificer:

1. search online for research papers about improving LLM behavior
2. pull non-paper web signals plus local runtime/repo/platform evidence
3. run a competitive lane (`artificer` vs challenger) and score the outputs
4. store the best merged ideas as plugins you can control

Each plugin is meant to be a visible behavioral patch, not a hidden rewrite.

## Why This Is Better Than Silent Mutation

If an AI system changes itself invisibly, the operator loses control.

Artificer takes the opposite approach. Plugins are:

- visible
- reversible
- individually controllable
- easy to delete if they are bad

That is much more defensible than “the app silently rewrote itself.”

## Choosing A Model For Self-Improve

For the self-improvement workflow, you usually want a model that can:

- follow structure well
- summarize research decently
- produce stable output

That is not always the same model you would choose for casual chat. You can also set a challenger model so Artificer compares two independently generated plugin sets before saving.

## Evidence Sources

Self-improvement can include or exclude each source family:

- papers (arXiv + Crossref)
- web signals (engineering community and issue trackers)
- runtime telemetry (failure taxonomy, scorecards, proposal traces)
- repository signals (worktree, code-shape, release-surface hints)
- platform checks (scheduler/tooling availability)

The objective field lets you steer the run toward a specific type of improvement while keeping the plugin output reversible.

## Troubleshooting

### No Models Appear

Run:

```sh
ollama list
```

If that fails, fix Ollama first.

### The Generated Plugins Feel Weak

Common reasons:

- the chosen model is too weak
- the papers found were not very strong
- the generated guidance is too generic

The practical fix is simple: keep the useful plugins and disable or delete the weak ones.
