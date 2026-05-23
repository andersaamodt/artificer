#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$repo_root/templates/macos/App.swift.template"
generated="$repo_root/generated/macos/Sources/App/App.swift"
backend="$repo_root/scripts/artificer-native-backend.sh"

require_text() {
  file=$1
  pattern=$2
  label=$3
  if ! grep -F "$pattern" "$file" >/dev/null 2>&1; then
    printf '%s\n' "missing $label: $pattern" >&2
    exit 1
  fi
}

require_text "$template" "OpenProjectToolbarMenu" "native open target toolbar menu"
require_text "$template" "GitBranchToolbarMenu" "native branch toolbar menu"
require_text "$template" "GitChangesToolbarButton" "native changes toolbar button"
require_text "$template" "CommitToolbarMenu" "native commit toolbar menu"
require_text "$template" "TerminalPanelSheet" "native terminal panel"
require_text "$template" "ThemeToolbarMenu" "native theme toolbar menu"
require_text "$template" "ModelQuickPanel" "native model shelf"
require_text "$template" "SessionAttentionStrip" "native approval and decision strip"
require_text "$template" "RunTraceSummaryView" "native run trace summary"
require_text "$template" "QueueTraySheet" "native queue tray"
require_text "$template" "PreferencesTabStrip" "macOS-style preferences tab strip"
require_text "$template" "SessionStatusPill" "native explicit sidebar status pills"
require_text "$template" "DiffTextView" "native colorized diff view"
require_text "$template" "promptDraftsBySessionKey" "native per-thread composer draft retention"
require_text "$template" "draft: detail.draft" "native draft retention across model changes"
require_text "$template" "moveQueueItem" "native queue reorder controls"
require_text "$template" "sendTerminalInput" "native terminal input controls"
require_text "$template" "handleDroppedAttachments" "native composer file drop handling"
require_text "$template" "copyToPasteboard(message.content)" "native message copy affordance"
require_text "$template" "Jump to latest message" "native transcript jump-to-latest affordance"
require_text "$template" "ScrollViewReader { proxy in" "native transcript scroll reader"
require_text "$template" ".id(\"transcript-bottom\")" "native transcript bottom anchor"
require_text "$template" "CommandApprovalCard" "native hosted-style command approval card"
require_text "$template" "Deny + remember" "native remembered command deny control"
require_text "$template" "Regex pattern" "native approval regex pattern control"
require_text "$template" "DecisionRequestCard" "native hosted-style decision card"
require_text "$template" "TextField(\"Other\", text: \$otherAnswer)" "native decision other input"
require_text "$template" "RunTaskStatusView" "native run task progress monitor"
require_text "$template" "taskStatus = try? container.decodeIfPresent(RunTaskStatus.self" "native run task status decoding"
require_text "$template" "Close queue" "native queue sheet close affordance"
require_text "$template" "Close terminal" "native terminal sheet close affordance"
require_text "$template" "Close diff" "native diff sheet close affordance"
require_text "$template" "Close models" "native models sheet close affordance"
require_text "$template" "ComposerToggleIconButton(title: \"Network access\"" "native network option"
require_text "$template" "ComposerToggleIconButton(title: \"Web access\"" "native web option"
require_text "$template" "title: \"Reasoning depth\", selection: \$model.reasoningEffort" "native reasoning depth option"
require_text "$template" "ComposerContextBadge" "native context window badge"

require_text "$generated" "OpenProjectToolbarMenu" "rendered open target toolbar menu"
require_text "$generated" "SessionAttentionStrip" "rendered approval and decision strip"
require_text "$generated" "RunTraceSummaryView" "rendered run trace summary"
require_text "$generated" "QueueTraySheet" "rendered queue tray"
require_text "$generated" "ModelQuickPanel" "rendered model shelf"
require_text "$generated" "PreferencesTabStrip" "rendered macOS-style preferences tab strip"
require_text "$generated" "SessionStatusPill" "rendered explicit sidebar status pills"
require_text "$generated" "DiffTextView" "rendered colorized diff view"
require_text "$generated" "Jump to latest message" "rendered transcript jump-to-latest affordance"
require_text "$generated" ".id(\"transcript-bottom\")" "rendered transcript bottom anchor"
require_text "$generated" "CommandApprovalCard" "rendered hosted-style command approval card"
require_text "$generated" "Deny + remember" "rendered remembered command deny control"
require_text "$generated" "DecisionRequestCard" "rendered hosted-style decision card"
require_text "$generated" "RunTaskStatusView" "rendered run task progress monitor"
require_text "$generated" "onDrop(of: [UTType.fileURL]" "rendered composer file drop handling"

require_text "$backend" "git-status WORKSPACE_ID" "native git status bridge usage"
require_text "$backend" "queue-list WORKSPACE_ID CONVERSATION_ID" "native queue bridge usage"
require_text "$backend" "queue-reorder WORKSPACE_ID CONVERSATION_ID ITEM_IDS" "native queue reorder bridge usage"
require_text "$backend" "approval-answer WORKSPACE_ID CONVERSATION_ID DECISION SCOPE MATCH_MODE" "native approval match-mode bridge usage"
require_text "$backend" "command-rules-list WORKSPACE_ID" "native command approval rules bridge usage"
require_text "$backend" "command-rule-delete WORKSPACE_ID SCOPE INDEX" "native command approval rule deletion bridge usage"
require_text "$backend" "decision-answer WORKSPACE_ID CONVERSATION_ID" "native decision bridge usage"
require_text "$backend" "terminal-session-start WORKSPACE_ID" "native terminal bridge usage"
require_text "$backend" "terminal-session-input WORKSPACE_ID SESSION_ID INPUT" "native terminal input bridge usage"
require_text "$backend" "terminal-session-stop WORKSPACE_ID SESSION_ID" "native terminal stop bridge usage"
require_text "$backend" "open-project-target WORKSPACE_ID TARGET" "native open target bridge usage"

printf '%s\n' "native UI parity contract ok"
