# Artificer Capability Roadmap

This document answers a practical question:

What can Artificer already do well, what is still limited by the local models, and what engineering work would improve it the most?

## Current Strengths

Artificer is already strong when the task is grounded in a real working system.

That includes:

- repo-aware coding and debugging
- workspace and thread management
- tool-mediated execution with visible permissions
- file-backed state and repeatable automation flows
- self-knowledge about its own GUI, runtime, and operator surfaces
- self-actuation when the user explicitly permits it

In other words, Artificer is strongest where the model is working inside a disciplined environment rather than free-floating.

## Where The Current Local Models Still Hit A Ceiling

The current Ollama-based stack can still struggle on tasks that demand unusually broad or deep raw reasoning.

Examples:

- open-ended research synthesis across many unfamiliar domains
- ambiguous architecture decisions with weak evidence
- expert-level judgment in fields far outside the current workspace
- long-horizon self-improvement that requires generating and critiquing novel system designs
- teaching highly technical subjects at a consistently contributor-level depth

Better orchestration helps a great deal, but it does not remove the ceiling of the underlying models.

## Where The Current Gaps Are Mostly Engineering Gaps

Some limitations are not mainly about the model itself. They are about what the surrounding system still needs.

The largest current engineering gaps are:

- not enough comparative answer-quality evaluations
- not enough holdout-task promotion rules for self-improvement ideas
- specialist routing can still go further
- retrieval and evidence packaging can still improve
- critique and verification passes can be expanded on harder tasks

These are worth pursuing because they can raise reliability without pretending the base model changed.

## Highest-Leverage Next Improvements

The best next steps are:

1. Build benchmark batteries for research, planning, coding, review, and teaching.
2. Score outputs for quality, not just runtime correctness.
3. Route harder tasks through specialist controllers and explicit verification passes.
4. Improve retrieval so local models spend context on the most relevant evidence.
5. Keep self-improvement ideas only when they improve measured results on holdout tasks.

## How To Prove Improvement

Do not trust intuition or one impressive demo.

Require:

- before and after comparisons
- repeatable task families
- holdout tasks
- regression guards
- clear separation between model-limited failure and system-limited failure

That is how Artificer gets better in a way that transfers, instead of just sounding better for one moment.
