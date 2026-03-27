#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
app_src="$repo_root/hosted-web/static/artificer-app-modules/05b-api-and-state-sync-tail.js"

[ -f "$app_src" ] || {
  printf '%s\n' "missing frontend source: $app_src" >&2
  exit 1
}

if ! grep -q 'var streamPollIntervalMs = 350;' "$app_src"; then
  printf '%s\n' "run stream polling interval should stay at 350ms for responsive incremental updates" >&2
  exit 1
fi

if ! grep -q 'function requestStreamPollStop()' "$app_src"; then
  printf '%s\n' "missing requestStreamPollStop helper" >&2
  exit 1
fi

if ! grep -q 'function drainStreamAndStop()' "$app_src"; then
  printf '%s\n' "missing drainStreamAndStop helper" >&2
  exit 1
fi

if ! grep -q 'return drainStreamAndStop()' "$app_src"; then
  printf '%s\n' "run lifecycle finalizer must drain stream before settling" >&2
  exit 1
fi

run_start_line=$(grep -n 'return apiPost("run", {' "$app_src" | cut -d: -f1 | sed -n '1p')
catch_line=$(awk -v start="$run_start_line" 'NR > start && /[.]catch\(function \(err\) \{/ { print NR; exit }' "$app_src")
finally_line=$(awk -v start="$run_start_line" 'NR > start && /[.]finally\(function \(\) \{/ { print NR; exit }' "$app_src")

if [ -z "$run_start_line" ] || [ -z "$catch_line" ] || [ -z "$finally_line" ]; then
  printf '%s\n' "unable to locate run stream lifecycle boundaries in $app_src" >&2
  exit 1
fi

if sed -n "${run_start_line},${finally_line}p" "$app_src" | \
  awk '
    /[.]then\(function \(response\) \{/ { in_then = 1; next }
    in_then && /[.]catch\(function \(err\) \{/ { in_then = 0; next }
    in_then && /stopStreamPoll\(/ { bad_then = 1 }
    END { exit bad_then ? 0 : 1 }
  '
then
  printf '%s\n' "stopStreamPoll should not run in run/err branches before final stream drain" >&2
  exit 1
fi

if sed -n "${catch_line},${finally_line}p" "$app_src" | grep -q 'stopStreamPoll('; then
  printf '%s\n' "stopStreamPoll should not run in run/err branches before final stream drain" >&2
  exit 1
fi

if ! awk '
  /function pollStreamOnce\(options\)/ { in_fn = 1 }
  in_fn && /return streamPollPromise;/ { saw_return = 1 }
  in_fn && /^    }$/ { in_fn = 0 }
  END { exit saw_return ? 0 : 1 }
' "$app_src"; then
  printf '%s\n' "pollStreamOnce must return a promise so drain sequencing can await in-flight polls" >&2
  exit 1
fi

printf '%s\n' "ok run stream poll lifecycle: responsive polling with final drain sequencing is enforced"
