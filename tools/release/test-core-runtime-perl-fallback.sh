#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
bootstrap_file="$repo_root/hosted-web/cgi/lib/00-bootstrap.sh"

if [ ! -f "$bootstrap_file" ]; then
  printf '%s\n' "missing bootstrap runtime file: $bootstrap_file" >&2
  exit 1
fi

if ! grep -q 'strip_terminal_noise()' "$bootstrap_file"; then
  printf '%s\n' "strip_terminal_noise helper missing" >&2
  exit 1
fi
if ! grep -q 'canonicalize_controller_output()' "$bootstrap_file"; then
  printf '%s\n' "canonicalize_controller_output helper missing" >&2
  exit 1
fi

if ! awk '
  /strip_terminal_noise\(\)/ { in_fn=1 }
  in_fn && /command -v perl/ { found=1 }
  in_fn && /^}/ { in_fn=0 }
  END { exit(found ? 0 : 1) }
' "$bootstrap_file"; then
  printf '%s\n' "strip_terminal_noise must gate perl usage and include shell fallback" >&2
  exit 1
fi

if ! awk '
  /canonicalize_controller_output\(\)/ { in_fn=1 }
  in_fn && /command -v perl/ { found=1 }
  in_fn && /^}/ { in_fn=0 }
  END { exit(found ? 0 : 1) }
' "$bootstrap_file"; then
  printf '%s\n' "canonicalize_controller_output must gate perl usage and include shell fallback" >&2
  exit 1
fi

printf '%s\n' "ok core runtime perl fallback is present for bootstrap normalizers"
