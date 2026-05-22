# User Guide

When people first use Artificer, they often look at the interface and wonder which controls actually matter.

The short answer is: four of them matter most.

## The Four Main Levers

1. workspace
2. conversation
3. model
4. mode

If output quality feels wrong, one of those four is usually the reason.

## Workspace

A workspace is the local folder Artificer is helping you with.

Why it matters:

- it tells Artificer which project you mean
- it sets the file and git context
- it keeps unrelated work separate

## Conversation

A conversation is the running thread for one task or topic.

Why it matters:

- it carries context forward
- it helps follow-up prompts make sense
- it reduces the chance that a short question gets treated like a brand new task

## Model

A model is the underlying LLM.

Why it matters:

- some models are better at code
- some are better at explanation
- some are faster but weaker
- some are slower but more capable

## Mode

A mode changes what Artificer asks the system to optimize for.

Why it matters:

- it affects prompt framing
- it affects output structure
- it affects what habits Artificer emphasizes

## A Good Basic Workflow

1. Pick the right workspace.
2. Start a fresh conversation for a fresh task.
3. Choose a model that fits the task.
4. Choose a mode that fits the task.
5. Ask clearly for what you want.
6. Read the answer critically.

## What Good Output Looks Like

Look for:

- correct understanding of the request
- relevant evidence
- explicit assumptions when needed
- tradeoffs handled honestly
- specificity instead of filler

Be skeptical when you see:

- smooth but vague confidence
- ignored constraints
- generic advice that could fit any project
- conclusions that appear before evidence

## Best Beginner Exercise

Take one task and vary only one thing at a time:

1. change only the model
2. change only the mode
3. change only the wording of the prompt

That teaches you what part of the system is actually changing the result.

## Read Next

- [`SETTINGS_AND_MODELS.md`](SETTINGS_AND_MODELS.md)
- [`GLOSSARY.md`](GLOSSARY.md)
