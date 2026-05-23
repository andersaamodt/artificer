#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'TriageSidebarRow(model: model)' "$file" || {
    printf '%s\n' "Native sidebar should expose triage with a count badge: $file" >&2
    exit 1
  }
  grep -q 'TriageDetailView(model: model)' "$file" || {
    printf '%s\n' "Native detail panel should render triage cards: $file" >&2
    exit 1
  }
  grep -q 'func selectTriagePanel() async' "$file" || {
    printf '%s\n' "Native model should select the triage panel: $file" >&2
    exit 1
  }
  grep -q 'func decideTriage(_ card: TriageCard, decision: String) async' "$file" || {
    printf '%s\n' "Native model should apply triage decisions: $file" >&2
    exit 1
  }
  grep -q 'func suppressTriage(_ card: TriageCard, scope: String) async' "$file" || {
    printf '%s\n' "Native model should support triage suppress policies: $file" >&2
    exit 1
  }
  grep -q 'private struct TriageCard: Identifiable, Decodable, Hashable' "$file" || {
    printf '%s\n' "Native model should decode hosted triage proposal cards: $file" >&2
    exit 1
  }
done

grep -q 'triage-list' "$backend" || {
  printf '%s\n' "Native backend should expose triage-list" >&2
  exit 1
}

grep -q 'api_get triage_list' "$backend" || {
  printf '%s\n' "Native backend should call hosted triage_list" >&2
  exit 1
}

grep -q 'api_post triage_decide' "$backend" || {
  printf '%s\n' "Native backend should call hosted triage_decide" >&2
  exit 1
}

grep -q 'api_post triage_suppress' "$backend" || {
  printf '%s\n' "Native backend should call hosted triage_suppress" >&2
  exit 1
}

grep -q 'api_post triage_cleanup' "$backend" || {
  printf '%s\n' "Native backend should call hosted triage_cleanup" >&2
  exit 1
}

printf '%s\n' "ok native triage parity"
