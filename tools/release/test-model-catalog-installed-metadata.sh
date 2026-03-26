#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
runtime_file="$repo_root/hosted-web/cgi/lib/runtime/40g-state-ui.sh"
render_file="$repo_root/hosted-web/static/artificer-app-src/03-ui-and-rendering.js"
events_file="$repo_root/hosted-web/static/artificer-app-src/08-event-bindings-and-boot.js"
index_file="$repo_root/hosted-web/pages/index.md"

for file_path in "$runtime_file" "$render_file" "$events_file" "$index_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  fi
done

if ! grep -q 'installed_metadata=$(ollama_installed_metadata_entries || true)' "$runtime_file"; then
  printf '%s\n' "model catalog runtime does not load installed model metadata from Ollama tags" >&2
  exit 1
fi

if ! grep -q 'available=$(merge_available_model_entries "$installed_enriched" "$available")' "$runtime_file"; then
  printf '%s\n' "model catalog runtime does not merge installed model metadata into available catalog entries" >&2
  exit 1
fi

if ! grep -q 'installedSizeLabel = "Size unavailable";' "$render_file"; then
  printf '%s\n' "installed model fallback size label missing from UI rendering" >&2
  exit 1
fi

if ! grep -q 'sizeLabel = "Size unavailable";' "$render_file"; then
  printf '%s\n' "available model fallback size label missing from UI rendering" >&2
  exit 1
fi

if ! grep -q "<span class='catalog-size catalog-size-right'>" "$render_file"; then
  printf '%s\n' "installed model size badge markup missing from UI rendering" >&2
  exit 1
fi

if ! grep -q 'id="models-box-head"' "$index_file"; then
  printf '%s\n' "models panel header id missing from index markup" >&2
  exit 1
fi

if ! grep -q 'on(el.modelsBoxHead, "click"' "$events_file"; then
  printf '%s\n' "models panel header click close binding missing" >&2
  exit 1
fi

printf '%s\n' "ok model catalog keeps optional descriptions while always rendering a size label"
