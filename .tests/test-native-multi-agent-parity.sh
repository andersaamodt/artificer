#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'ProjectMultiAgentBadge(project: project)' "$file" || {
    printf '%s\n' "Native project rows should show multi-agent badges: $file" >&2
    exit 1
  }
  grep -q 'Label("Manage agents...", systemImage: "person.2.wave.2")' "$file" || {
    printf '%s\n' "Native project menu should expose Manage agents: $file" >&2
    exit 1
  }
  grep -q 'MultiAgentSheet(model: model)' "$file" || {
    printf '%s\n' "Native UI should include a multi-agent management sheet: $file" >&2
    exit 1
  }
  grep -q 'private struct MultiAgentResidentRow: View' "$file" || {
    printf '%s\n' "Native UI should expose resident controls: $file" >&2
    exit 1
  }
  grep -q 'func setMultiAgentResident(_ catalogResident: MultiAgentCatalogResident' "$file" || {
    printf '%s\n' "Native model should update resident settings: $file" >&2
    exit 1
  }
  grep -q 'multiAgentBackgroundResidents' "$file" || {
    printf '%s\n' "Native project model should decode background resident counts: $file" >&2
    exit 1
  }
done

grep -q 'projects-state' "$backend" || {
  printf '%s\n' "Native backend should expose rich project state" >&2
  exit 1
}

grep -q 'api_get state' "$backend" || {
  printf '%s\n' "Native backend should read hosted UI state for multi-agent metadata" >&2
  exit 1
}

grep -q 'api_get multi_agent_workspace_get' "$backend" || {
  printf '%s\n' "Native backend should load workspace multi-agent state" >&2
  exit 1
}

grep -q 'api_post multi_agent_resident_spawn' "$backend" || {
  printf '%s\n' "Native backend should spawn residents" >&2
  exit 1
}

grep -q 'api_post multi_agent_resident_update' "$backend" || {
  printf '%s\n' "Native backend should update residents" >&2
  exit 1
}

printf '%s\n' "ok native multi-agent parity"
