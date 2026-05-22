#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
runtime_lib="$repo_root/scripts/lib/wizardry_runtime.sh"

[ -f "$runtime_lib" ] || {
  printf '%s\n' "missing runtime lib at $runtime_lib" >&2
  exit 1
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/artificer-runtime-fallback.XXXXXX")
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT INT TERM

app_root="$scratch/app"
home_dir="$scratch/home"
marker="$scratch/ensure-called"
mkdir -p "$app_root/tools/release" "$home_dir/.wizardry/spells/.imps/sys"

cat > "$app_root/tools/release/common.sh" <<EOF
#!/bin/sh
ensure_wizardry_installed() {
  printf '%s\n' "called" >> "$marker"
  return 1
}
EOF

cat > "$home_dir/.wizardry/spells/.imps/sys/invoke-wizardry" <<'EOF'
#!/bin/sh
PATH="$PATH"
export PATH
EOF

chosen_wizardry_dir=$(
  APP_ROOT="$app_root" HOME_DIR="$home_dir" RUNTIME_LIB="$runtime_lib" WIZARDRY_DIR="$scratch/invalid-wizardry-dir" sh <<'SH'
set -eu
. "$RUNTIME_LIB"
wizardry_bootstrap_or_install "$APP_ROOT" "$HOME_DIR"
printf '%s\n' "$WIZARDRY_DIR"
SH
)

expected="$home_dir/.wizardry"
if [ "$chosen_wizardry_dir" != "$expected" ]; then
  printf '%s\n' "runtime fallback mismatch: expected $expected, got $chosen_wizardry_dir" >&2
  exit 1
fi

if [ -f "$marker" ]; then
  printf '%s\n' "runtime fallback regression: ensure_wizardry_installed should not run when home wizardry runtime is present" >&2
  exit 1
fi

printf '%s\n' "ok runtime fallback: stale WIZARDRY_DIR falls back to $expected without installer call"
