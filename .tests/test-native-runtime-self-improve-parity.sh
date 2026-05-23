#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'SelfImprovePluginRow(model: model, plugin: plugin)' "$file" || {
    printf '%s\n' "Native self-improve settings should render plugin cards: $file" >&2
    exit 1
  }
  grep -q 'func setSelfImprovePlugin(_ plugin: SelfImprovePlugin' "$file" || {
    printf '%s\n' "Native model should update self-improve plugin policy/enabled state: $file" >&2
    exit 1
  }
  grep -q 'RuntimeProposalList(model: model' "$file" || {
    printf '%s\n' "Native runtime settings should render improvement proposals: $file" >&2
    exit 1
  }
  grep -q 'RuntimeControllerVariantList(model: model' "$file" || {
    printf '%s\n' "Native runtime settings should render controller variants: $file" >&2
    exit 1
  }
  grep -q 'RuntimeFailureTaxonomyView(taxonomy:' "$file" || {
    printf '%s\n' "Native runtime settings should render failure taxonomy: $file" >&2
    exit 1
  }
  grep -q 'func generateModeRuntimeProposals() async' "$file" || {
    printf '%s\n' "Native model should generate runtime improvement proposals: $file" >&2
    exit 1
  }
done

grep -q 'api_post self_improve_plugin_set' "$backend" || {
  printf '%s\n' "Native backend should update self-improve plugins" >&2
  exit 1
}

grep -q 'api_get mode_runtime_state' "$backend" || {
  printf '%s\n' "Native backend should load mode runtime state" >&2
  exit 1
}

grep -q 'api_post improvement_proposal_generate' "$backend" || {
  printf '%s\n' "Native backend should generate improvement proposals" >&2
  exit 1
}

grep -q 'api_post improvement_proposal_decide' "$backend" || {
  printf '%s\n' "Native backend should decide improvement proposals" >&2
  exit 1
}

grep -q 'api_post controller_variant_promote' "$backend" || {
  printf '%s\n' "Native backend should promote controller variants" >&2
  exit 1
}

printf '%s\n' "ok native runtime/self-improve parity"
