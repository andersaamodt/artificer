#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'private struct QueueItemDropDelegate: DropDelegate' "$file" || {
    printf '%s\n' "Native queue sheet should support drag/drop reorder: $file" >&2
    exit 1
  }
  grep -q 'model.queueDragProvider(itemID: item.id)' "$file" || {
    printf '%s\n' "Native queue rows should expose drag providers: $file" >&2
    exit 1
  }
  grep -q 'func steerQueueItem(_ itemID: String) async' "$file" || {
    printf '%s\n' "Native model should steer queued items: $file" >&2
    exit 1
  }
  grep -q 'arrow.up.to.line' "$file" || {
    printf '%s\n' "Native queue row should include a steer-to-front control: $file" >&2
    exit 1
  }
done

grep -q 'queue-steer WORKSPACE_ID CONVERSATION_ID ITEM_ID' "$backend" || {
  printf '%s\n' "Native backend should expose queue-steer" >&2
  exit 1
}

grep -q 'api_post queue_steer' "$backend" || {
  printf '%s\n' "Native backend should call hosted queue_steer" >&2
  exit 1
}

printf '%s\n' "ok native queue parity"
