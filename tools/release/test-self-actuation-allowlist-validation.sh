#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
allow_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"

[ -f "$allow_file" ] || {
  printf '%s\n' "missing allowlist file: $allow_file" >&2
  exit 1
}

ALLOW_NETWORK=0
ALLOW_WEB=0
REFLEXIVE_KNOWLEDGE=1
ARTIFICER_REFLEXIVE_KNOWLEDGE=0
SELF_ACTUATION=1
ARTIFICER_SELF_ACTUATION=0

# shellcheck source=/dev/null
. "$allow_file"

expect_allowed() {
  cmd=$1
  if ! allowed_command "$cmd"; then
    printf '%s\n' "expected allowed command was blocked: $cmd" >&2
    exit 1
  fi
}

expect_blocked() {
  cmd=$1
  if allowed_command "$cmd"; then
    printf '%s\n' "expected blocked command was allowed: $cmd" >&2
    exit 1
  fi
}

# Allowed self-actuation command forms.
expect_allowed "artificer-appctl project add --path /tmp/project-a --name project-a --command-exec-mode ask-some"
expect_allowed "artificer-appctl project list --json"
expect_allowed "artificer-appctl project rename --workspace-id ws_1 --name workspace-renamed"
expect_allowed "artificer-appctl project delete --workspace-id ws_1"
expect_allowed "artificer-appctl thread new --workspace-id ws_1 --title kickoff --model mistral:latest"
expect_allowed "artificer-appctl thread list --workspace-id ws_1 --json"
expect_allowed "artificer-appctl thread archive --workspace-id ws_1 --conversation-id conv_1"
expect_allowed "artificer-appctl automation list --json"
expect_allowed "artificer-appctl automation toggle --automation-id auto_1 --enabled 0"
expect_allowed "artificer-appctl automation run-now --automation-id auto_1"
expect_allowed "artificer-appctl automation delete --automation-id auto_1"
expect_allowed "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-kind interval --schedule-value 900 --enabled 1 --allow-self-reschedule 1 --run-mode auto --compute-budget quick --command-exec-mode ask-some --permission-mode workspace-write --programmer-review 1 --programmer-review-rounds 2 --next-run 1999999999"
expect_allowed "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-kind interval --schedule-value 900 --run-mode team --command-exec-mode ask"
expect_allowed "artificer-appctl self-actuation preview --operation ensure_workspace --path /tmp/project-a --name project-a --json"
expect_allowed "artificer-appctl self-actuation apply --operation rename_workspace --workspace-id ws_1 --name project-renamed --confirm-token token_123 --idempotency-key idem-1 --json"
expect_allowed "artificer-appctl self-actuation policy-get --workspace-id ws_1 --action ensure_workspace --json"
expect_allowed "artificer-appctl self-actuation policy-set --workspace-id ws_1 --action ensure_workspace --enabled 0 --json"
expect_allowed "artificer-appctl self-actuation audit --limit 50 --json"

# Allowed reflexive command forms.
expect_allowed "artificer-appctl knowledge show --topic gui --json"
expect_allowed "artificer-appctl knowledge teach --topic self-actuation --json"

# Reject malformed, unsafe, or underspecified variants.
expect_blocked "artificer-appctl project rename --workspace-id ws_1"
expect_blocked "artificer-appctl project delete --workspace-id ../bad"
expect_blocked "artificer-appctl thread list --json"
expect_blocked "artificer-appctl thread archive --workspace-id ws_1"
expect_blocked "artificer-appctl automation toggle --automation-id auto_1 --enabled 2"
expect_blocked "artificer-appctl automation run-now --automation-id ../bad"
expect_blocked "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-value 900"
expect_blocked "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-kind monthly --schedule-value 900"
expect_blocked "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-kind interval --schedule-value 900 --run-mode root-shell"
expect_blocked "artificer-appctl knowledge teach --json"
expect_blocked "artificer-appctl knowledge show --topic gui --unknown value"
expect_blocked "artificer-appctl self-actuation preview --path /tmp/project-a"
expect_blocked "artificer-appctl self-actuation apply --operation rename_workspace --workspace-id ws_1 --name project-renamed"
expect_blocked "artificer-appctl self-actuation policy-set --workspace-id ws_1 --action not_real --enabled 1"
expect_blocked "artificer-appctl self-actuation policy-set --workspace-id ws_1 --action ensure_workspace"
expect_blocked "artificer-appctl self-actuation audit --limit abc"
expect_blocked "artificer-appctl self-actuation preview --operation ensure_workspace --path /tmp/project-a --unknown value"
expect_blocked "artificer-appctl project list; ls"

# Gate behavior: self-actuation commands blocked when self-actuation gate disabled.
SELF_ACTUATION=0
ARTIFICER_SELF_ACTUATION=0
expect_blocked "artificer-appctl project list --json"
expect_blocked "artificer-appctl thread new --workspace-id ws_1 --title kickoff"
expect_blocked "artificer-appctl automation upsert --workspace-id ws_1 --name nightly --prompt summarize --schedule-kind interval --schedule-value 900"
expect_blocked "artificer-appctl self-actuation preview --operation ensure_workspace --path /tmp/project-a --json"

# Gate behavior: reflexive commands blocked when reflexive gate disabled.
REFLEXIVE_KNOWLEDGE=0
ARTIFICER_REFLEXIVE_KNOWLEDGE=0
expect_blocked "artificer-appctl knowledge show --topic gui"
expect_blocked "artificer-appctl knowledge teach --topic overview"

printf '%s\n' "ok strict self-actuation/reflexive command argument validation and permission gating"
