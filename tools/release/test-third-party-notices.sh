#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
notices_file="$repo_root/docs/THIRD_PARTY_NOTICES.md"
htmx_file="$repo_root/hosted-web/static/js/htmx.min.js"
idiomorph_file="$repo_root/hosted-web/static/js/idiomorph-ext.min.js"

expected_htmx_sha="b3bdcf5c741897a53648b1207fff0469a0d61901429ba1f6e88f98ebd84e669e"
expected_idiomorph_sha="763ad5ebd0963ea9436cb480f303fc4b7e543c37c649925f032c568b4dbab7e6"

sha256_file() {
  target_file=${1-}
  [ -n "$target_file" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$target_file" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$target_file" | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$target_file" | awk '{print $NF}'
    return 0
  fi
  printf '%s\n' "no SHA-256 tool available (need sha256sum, shasum, or openssl)" >&2
  return 1
}

[ -f "$notices_file" ] || {
  printf '%s\n' "missing notices file: $notices_file" >&2
  exit 1
}
[ -f "$htmx_file" ] || {
  printf '%s\n' "missing bundled file: $htmx_file" >&2
  exit 1
}
[ -f "$idiomorph_file" ] || {
  printf '%s\n' "missing bundled file: $idiomorph_file" >&2
  exit 1
}

htmx_sha=$(sha256_file "$htmx_file")
idiomorph_sha=$(sha256_file "$idiomorph_file")

[ "$htmx_sha" = "$expected_htmx_sha" ] || {
  printf '%s\n' "htmx checksum mismatch: expected $expected_htmx_sha got $htmx_sha" >&2
  exit 1
}
[ "$idiomorph_sha" = "$expected_idiomorph_sha" ] || {
  printf '%s\n' "idiomorph-ext checksum mismatch: expected $expected_idiomorph_sha got $idiomorph_sha" >&2
  exit 1
}

grep -q 'htmx.org@1.9.10/dist/htmx.min.js' "$notices_file" || {
  printf '%s\n' "notices missing htmx source version URL" >&2
  exit 1
}
grep -q 'idiomorph@0.3.0/dist/idiomorph-ext.min.js' "$notices_file" || {
  printf '%s\n' "notices missing idiomorph source version URL" >&2
  exit 1
}
grep -q 'BSD-2-Clause' "$notices_file" || {
  printf '%s\n' "notices must include license identifier" >&2
  exit 1
}
grep -q "$expected_htmx_sha" "$notices_file" || {
  printf '%s\n' "notices missing htmx checksum" >&2
  exit 1
}
grep -q "$expected_idiomorph_sha" "$notices_file" || {
  printf '%s\n' "notices missing idiomorph checksum" >&2
  exit 1
}

printf '%s\n' "ok third-party notices and checksums verified"
