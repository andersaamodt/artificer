# How Artificer LLMs Work

If you read only one document in this folder, read this one.

## First: What An LLM Actually Is

An LLM is a system trained to predict the next piece of text.

That can sound underwhelming, but in practice it means the model can often:

- answer questions
- summarize text
- write code
- explain ideas
- imitate reasoning patterns
- follow instructions surprisingly well

It can do those things because it has learned a huge amount of statistical structure from training data.

## What An LLM Is Not

A raw LLM is not:

- a human mind
- a perfect truth machine
- automatically aware of your files
- automatically aware of your goals
- naturally reliable just because it sounds fluent

This matters because a lot of beginner confusion comes from mistaking eloquence for understanding.

## What Artificer Adds

Artificer wraps the model in a structured environment.

That environment supplies things a raw model does not have on its own:

- a workspace
- a conversation thread
- a mode
- settings
- optional plugins
- runtime rules
- tool access

So when you use Artificer, you are not really talking to “just the model.” You are talking to a model that has been placed inside a working system.

## Why The Same Model Can Feel Smarter Inside Artificer

The same installed model can behave very differently depending on how it is set up.

If you ask a bare model a question, it may:

- answer too quickly
- ignore hidden constraints
- sound confident without checking anything
- lose track of follow-up context

Artificer tries to reduce those failures by giving the model better conditions to work under.

## The Main Pipeline

A normal Artificer run is roughly:

1. You choose a workspace and a conversation.
2. You pick a model and a mode.
3. Artificer gathers context.
4. Artificer frames the prompt for the current situation.
5. The local model produces output.
6. Artificer may structure, validate, or normalize that output.
7. You see the result.

So the final quality comes from both the model and the system around it.

## Why Model Choice Matters

Different models have different strengths.

In broad terms:

- smaller models are usually faster
- larger models are usually better at harder reasoning
- code-focused models tend to do better on code-heavy work
- general-purpose models tend to do better on broader synthesis

There is no perfect single model for every task.

## Why Mode Choice Matters

A mode is Artificer’s way of telling the system what kind of behavior to prefer.

Examples:

- `chat` pushes toward direct conversation
- `programming` pushes toward engineering help
- `report` pushes toward structured explanation
- `GUI testing` pushes toward hands-on automation and UX defect finding

Mode matters because the same model can produce very different answers when asked to behave in different ways.

## What Plugins Are

Plugins are controlled behavior patches, not magical self-rewrites.

A plugin can add a new habit, such as:

- be more explicit about uncertainty
- compare alternatives before deciding
- verify evidence before concluding

The important point is that plugins are visible and reversible. If one makes the system worse, you can turn it off.

## Why Human Judgment Still Matters

Even a well-wrapped model can still:

- misunderstand the task
- miss evidence
- overgeneralize
- dress up a weak answer in smooth prose

Artificer is designed to reduce those failures, not pretend they disappear.

## Practical Summary

The base model provides raw generative ability.

Artificer provides:

- structure
- memory
- steering
- tool use
- runtime discipline

That combination is what gives the app its character.
