#!/bin/sh
set -eu

# Print the first key=value value for key from a newline-delimited text block.
kv_get() {
  key=$1
  text=${2-}
  printf '%s\n' "$text" | awk -F'=' -v k="$key" '$1==k {sub($1"=", "", $0); print; exit}'
}
