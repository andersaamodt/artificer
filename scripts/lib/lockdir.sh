#!/bin/sh
set -eu

# Acquire a process lock via lock directory.
# Returns 0 if acquired, 1 if held by a live process.
lockdir_acquire() {
  lock_dir=$1
  lock_pid_file=$lock_dir/pid
  lock_pid=${2-$$}

  mkdir -p "$(dirname "$lock_dir")"
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$lock_pid" > "$lock_pid_file"
    return 0
  fi

  prior_pid=$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)
  case "$prior_pid" in
    ''|*[!0-9]*)
      prior_pid=""
      ;;
  esac

  if [ -n "$prior_pid" ] && kill -0 "$prior_pid" 2>/dev/null; then
    return 1
  fi

  rm -rf "$lock_dir" 2>/dev/null || true
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$lock_pid" > "$lock_pid_file"
    return 0
  fi
  return 1
}

lockdir_release() {
  lock_dir=$1
  rm -rf "$lock_dir" 2>/dev/null || true
}
