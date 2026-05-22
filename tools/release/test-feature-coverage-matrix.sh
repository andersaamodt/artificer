#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
matrix_file="$script_dir/feature-coverage-matrix.tsv"

[ -f "$matrix_file" ] || {
  printf '%s\n' "missing feature coverage matrix: $matrix_file" >&2
  exit 1
}

features_seen=$(mktemp "${TMPDIR:-/tmp}/artificer-features-seen.XXXXXX")
tests_seen=$(mktemp "${TMPDIR:-/tmp}/artificer-tests-seen.XXXXXX")
cleanup() {
  rm -f "$features_seen" "$tests_seen"
}
trap cleanup EXIT INT HUP TERM

tab=$(printf '\t')

while IFS="$tab" read -r feature_id behavior_contract tests_csv; do
  case "$feature_id" in
    ''|'#'*) continue ;;
  esac

  feature_id=$(printf '%s' "$feature_id" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  behavior_contract=$(printf '%s' "$behavior_contract" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  tests_csv=$(printf '%s' "$tests_csv" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  [ -n "$feature_id" ] || {
    printf '%s\n' "feature coverage row missing feature_id" >&2
    exit 1
  }
  [ -n "$behavior_contract" ] || {
    printf '%s\n' "feature coverage row missing behavior_contract: $feature_id" >&2
    exit 1
  }
  [ -n "$tests_csv" ] || {
    printf '%s\n' "feature coverage row missing tests list: $feature_id" >&2
    exit 1
  }

  if grep -qx "$feature_id" "$features_seen"; then
    printf '%s\n' "duplicate feature_id in coverage matrix: $feature_id" >&2
    exit 1
  fi
  printf '%s\n' "$feature_id" >> "$features_seen"

  printf '%s\n' "$tests_csv" | tr ',' '\n' | while IFS= read -r test_name; do
    test_name=$(printf '%s' "$test_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$test_name" ] || continue

    case "$test_name" in
      test-*.sh) ;;
      *)
        printf '%s\n' "invalid test name in coverage matrix ($feature_id): $test_name" >&2
        exit 1
        ;;
    esac

    test_path="$script_dir/$test_name"
    [ -f "$test_path" ] || {
      printf '%s\n' "coverage matrix references missing test script ($feature_id): $test_path" >&2
      exit 1
    }

    if ! grep -qx "$test_name" "$tests_seen" 2>/dev/null; then
      printf '%s\n' "$test_name" >> "$tests_seen"
    fi
  done
done < "$matrix_file"

[ -s "$features_seen" ] || {
  printf '%s\n' "feature coverage matrix has no feature rows" >&2
  exit 1
}

for test_path in "$script_dir"/test-*.sh; do
  [ -f "$test_path" ] || continue
  test_name=$(basename "$test_path")
  if ! grep -qx "$test_name" "$tests_seen"; then
    printf '%s\n' "release test not mapped in feature coverage matrix: $test_name" >&2
    exit 1
  fi
done

printf '%s\n' "ok feature coverage matrix maps every release behavioral test"
