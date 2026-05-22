#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="remote-release-pack-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for remote release pack probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: remote-release-pack-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded remote release-pack probe against a demo workspace and checks
whether Artificer can open the bastion tunnel, deploy the core boundary pair first,
then deploy the edge boundary pair second, publish the shared release pack, rerun
release verification, and keep rollback intact.
EOF_USAGE
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

post_api_json() {
  body=$1
  len=$(printf '%s' "$body" | wc -c | tr -d ' ')
  REQUEST_METHOD=POST CONTENT_LENGTH="$len" sh "$API_SCRIPT" <<EOF_BODY | tr -d '\r' | awk 'seen{print} /^$/{seen=1}'
$body
EOF_BODY
}

post_api_json_with_timeout() {
  body=$1
  timeout_sec=$2
  python3 - "$API_SCRIPT" "$timeout_sec" "$body" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
timeout_sec = float(sys.argv[2])
body = sys.argv[3]
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))

try:
    proc = subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout_sec,
        check=False,
    )
    raw = proc.stdout.decode().replace("\r", "")
    parts = raw.split("\n\n", 1)
    payload = parts[1] if len(parts) > 1 else raw
    payload = payload.strip()
    if payload:
        print(payload)
    else:
        print('{"__timed_out":false}')
except subprocess.TimeoutExpired:
    print('{"__timed_out":true}')
PY
}

delete_workspace_best_effort() {
  workspace_id=$1
  [ -n "$workspace_id" ] || return 0
  workspace_id_uri=$(uri "$workspace_id")
  python3 - "$API_SCRIPT" "$workspace_id_uri" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
workspace_id_uri = sys.argv[2]
body = f"action=delete_workspace&workspace_id={workspace_id_uri}"
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))
try:
    subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=12,
        check=False,
    )
except Exception:
    pass
PY
}

create_remote_release_pack_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/remote" "$workspace_dir/state" "$workspace_dir/audit" "$workspace_dir/release/live" "$workspace_dir/release/staging"
  cat > "$workspace_dir/remote/release-pack.env" <<'EOF_CFG'
BASTION_HOST=demo-bastion-1
CORE_CANARY_PRIVATE_HOST=demo-core-private-a
CORE_FLEET_PRIVATE_HOST=demo-core-private-b
EDGE_CANARY_PRIVATE_HOST=demo-edge-private-a
EDGE_FLEET_PRIVATE_HOST=demo-edge-private-b
CORE_TARGET_RELEASE=2026.03.22-core
EDGE_TARGET_RELEASE=2026.03.22-edge
RELEASE_CURRENT=2026.03.10
RELEASE_TARGET=2026.03.22
CORE_APPROVED_RELEASE=2026.03.10-core
EDGE_APPROVED_RELEASE=2026.03.10-edge
RELEASE_APPROVED=0
TUNNEL_READY=0
CORE_CANARY_READY=0
CORE_FLEET_READY=0
EDGE_CANARY_READY=0
EDGE_FLEET_READY=0
RELEASE_NOTES_READY=0
READ_ONLY=0
PACK_STATE=stale
EOF_CFG
  cp "$workspace_dir/remote/release-pack.env" "$workspace_dir/remote/release-pack.env.bak"
  printf '%s\n' '2026.03.10-core' > "$workspace_dir/state/core.canary.release"
  printf '%s\n' '2026.03.10-core' > "$workspace_dir/state/core.fleet.release"
  printf '%s\n' '2026.03.10-edge' > "$workspace_dir/state/edge.canary.release"
  printf '%s\n' '2026.03.10-edge' > "$workspace_dir/state/edge.fleet.release"
  cp "$workspace_dir/state/core.canary.release" "$workspace_dir/state/core.canary.release.bak"
  cp "$workspace_dir/state/core.fleet.release" "$workspace_dir/state/core.fleet.release.bak"
  cp "$workspace_dir/state/edge.canary.release" "$workspace_dir/state/edge.canary.release.bak"
  cp "$workspace_dir/state/edge.fleet.release" "$workspace_dir/state/edge.fleet.release.bak"
  cat > "$workspace_dir/release/live/current.json" <<'EOF_JSON'
{"release":"2026.03.10","core":"2026.03.10-core","edge":"2026.03.10-edge"}
EOF_JSON
  cat > "$workspace_dir/release/staging/current.json.next" <<'EOF_JSON'
{"release":"2026.03.22","core":"2026.03.22-core","edge":"2026.03.22-edge"}
EOF_JSON
  cp "$workspace_dir/release/live/current.json" "$workspace_dir/release/live/current.json.bak"
  cp "$workspace_dir/release/staging/current.json.next" "$workspace_dir/release/staging/current.json.next.bak"
  printf '%s\n' 'pending' > "$workspace_dir/state/release.publish.status"

  cat > "$workspace_dir/bin/ssh-bastion.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/release-pack.env"
state_file="$ROOT_DIR/state/boundary.tunnel"
case "$subcommand" in
  status)
    if [ "$TUNNEL_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' "release_pack_bastion=ready host=$BASTION_HOST"
    else
      printf '%s\n' "release_pack_bastion=stale host=$BASTION_HOST"
      printf '%s\n' "expected_fix=TUNNEL_READY=1 READ_ONLY=1 PACK_STATE=ready"
    fi
    ;;
  tunnel)
    if [ "$TUNNEL_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' 'ready' > "$state_file"
      printf '%s\n' "release_pack_tunnel=ok host=$BASTION_HOST"
    else
      printf '%s\n' 'blocked' > "$state_file"
      printf '%s\n' "release_pack_tunnel=failed host=$BASTION_HOST"
      exit 1
    fi
    ;;
  health)
    tunnel_state=$(cat "$state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$tunnel_state" = 'ready' ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "release_pack_bastion_health=ok host=$BASTION_HOST"
      exit 0
    fi
    printf '%s\n' "release_pack_bastion_health=failed host=$BASTION_HOST"
    exit 1
    ;;
  *)
    echo "usage: ssh-bastion.sh status|tunnel|health" >&2
    exit 2
    ;;
esac
EOF_BIN

  cat > "$workspace_dir/bin/ssh-core-canary.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/release-pack.env"
tunnel_state_file="$ROOT_DIR/state/boundary.tunnel"
release_file="$ROOT_DIR/state/core.canary.release"
case "$subcommand" in
  status)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$CORE_APPROVED_RELEASE" = "$CORE_TARGET_RELEASE" ] && [ "$CORE_CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' "core_canary_boundary=ready host=$CORE_CANARY_PRIVATE_HOST current=$current target=$CORE_TARGET_RELEASE"
    else
      printf '%s\n' "core_canary_boundary=stale host=$CORE_CANARY_PRIVATE_HOST current=$current target=$CORE_TARGET_RELEASE"
      printf '%s\n' "expected_fix=CORE_APPROVED_RELEASE=$CORE_TARGET_RELEASE CORE_CANARY_READY=1 READ_ONLY=1 PACK_STATE=ready"
    fi
    ;;
  deploy)
    tunnel_state=$(cat "$tunnel_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$CORE_APPROVED_RELEASE" = "$CORE_TARGET_RELEASE" ] && [ "$CORE_CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$tunnel_state" = 'ready' ]; then
      printf '%s\n' "$CORE_TARGET_RELEASE" > "$release_file"
      printf '%s\n' "core_canary_deploy=ok host=$CORE_CANARY_PRIVATE_HOST release=$CORE_TARGET_RELEASE" > "$ROOT_DIR/audit/core-canary.log"
      printf '%s\n' "core_canary_deploy=ok host=$CORE_CANARY_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
    else
      printf '%s\n' 'blocked' > "$release_file"
      printf '%s\n' "core_canary_deploy=failed host=$CORE_CANARY_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$current" = "$CORE_TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "core_canary_health=ok host=$CORE_CANARY_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "core_canary_health=failed host=$CORE_CANARY_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-core-canary.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN

  cat > "$workspace_dir/bin/ssh-core-fleet.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/release-pack.env"
canary_release_file="$ROOT_DIR/state/core.canary.release"
release_file="$ROOT_DIR/state/core.fleet.release"
case "$subcommand" in
  status)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$CORE_APPROVED_RELEASE" = "$CORE_TARGET_RELEASE" ] && [ "$CORE_FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' "core_fleet_boundary=ready host=$CORE_FLEET_PRIVATE_HOST current=$current target=$CORE_TARGET_RELEASE"
    else
      printf '%s\n' "core_fleet_boundary=stale host=$CORE_FLEET_PRIVATE_HOST current=$current target=$CORE_TARGET_RELEASE"
      printf '%s\n' "expected_fix=CORE_APPROVED_RELEASE=$CORE_TARGET_RELEASE CORE_FLEET_READY=1 READ_ONLY=1 PACK_STATE=ready"
    fi
    ;;
  deploy)
    canary_release=$(cat "$canary_release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$CORE_APPROVED_RELEASE" = "$CORE_TARGET_RELEASE" ] && [ "$CORE_FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$canary_release" = "$CORE_TARGET_RELEASE" ]; then
      printf '%s\n' "$CORE_TARGET_RELEASE" > "$release_file"
      printf '%s\n' "core_fleet_deploy=ok host=$CORE_FLEET_PRIVATE_HOST release=$CORE_TARGET_RELEASE" > "$ROOT_DIR/audit/core-fleet.log"
      printf '%s\n' "core_fleet_deploy=ok host=$CORE_FLEET_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
    else
      printf '%s\n' 'blocked' > "$release_file"
      printf '%s\n' "core_fleet_deploy=failed host=$CORE_FLEET_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$current" = "$CORE_TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "core_fleet_health=ok host=$CORE_FLEET_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "core_fleet_health=failed host=$CORE_FLEET_PRIVATE_HOST release=$CORE_TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-core-fleet.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN

  cat > "$workspace_dir/bin/ssh-edge-canary.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/release-pack.env"
core_fleet_release_file="$ROOT_DIR/state/core.fleet.release"
release_file="$ROOT_DIR/state/edge.canary.release"
case "$subcommand" in
  status)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$EDGE_APPROVED_RELEASE" = "$EDGE_TARGET_RELEASE" ] && [ "$EDGE_CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' "edge_canary_boundary=ready host=$EDGE_CANARY_PRIVATE_HOST current=$current target=$EDGE_TARGET_RELEASE"
    else
      printf '%s\n' "edge_canary_boundary=stale host=$EDGE_CANARY_PRIVATE_HOST current=$current target=$EDGE_TARGET_RELEASE"
      printf '%s\n' "expected_fix=EDGE_APPROVED_RELEASE=$EDGE_TARGET_RELEASE EDGE_CANARY_READY=1 READ_ONLY=1 PACK_STATE=ready"
    fi
    ;;
  deploy)
    core_fleet_release=$(cat "$core_fleet_release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$EDGE_APPROVED_RELEASE" = "$EDGE_TARGET_RELEASE" ] && [ "$EDGE_CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$core_fleet_release" = "$CORE_TARGET_RELEASE" ]; then
      printf '%s\n' "$EDGE_TARGET_RELEASE" > "$release_file"
      printf '%s\n' "edge_canary_deploy=ok host=$EDGE_CANARY_PRIVATE_HOST release=$EDGE_TARGET_RELEASE" > "$ROOT_DIR/audit/edge-canary.log"
      printf '%s\n' "edge_canary_deploy=ok host=$EDGE_CANARY_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
    else
      printf '%s\n' 'blocked' > "$release_file"
      printf '%s\n' "edge_canary_deploy=failed host=$EDGE_CANARY_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$current" = "$EDGE_TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "edge_canary_health=ok host=$EDGE_CANARY_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "edge_canary_health=failed host=$EDGE_CANARY_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-edge-canary.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN

  cat > "$workspace_dir/bin/ssh-edge-fleet.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/release-pack.env"
edge_canary_release_file="$ROOT_DIR/state/edge.canary.release"
release_file="$ROOT_DIR/state/edge.fleet.release"
case "$subcommand" in
  status)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$EDGE_APPROVED_RELEASE" = "$EDGE_TARGET_RELEASE" ] && [ "$EDGE_FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ]; then
      printf '%s\n' "edge_fleet_boundary=ready host=$EDGE_FLEET_PRIVATE_HOST current=$current target=$EDGE_TARGET_RELEASE"
    else
      printf '%s\n' "edge_fleet_boundary=stale host=$EDGE_FLEET_PRIVATE_HOST current=$current target=$EDGE_TARGET_RELEASE"
      printf '%s\n' "expected_fix=EDGE_APPROVED_RELEASE=$EDGE_TARGET_RELEASE EDGE_FLEET_READY=1 READ_ONLY=1 PACK_STATE=ready"
    fi
    ;;
  deploy)
    edge_canary_release=$(cat "$edge_canary_release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$EDGE_APPROVED_RELEASE" = "$EDGE_TARGET_RELEASE" ] && [ "$EDGE_FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$edge_canary_release" = "$EDGE_TARGET_RELEASE" ]; then
      printf '%s\n' "$EDGE_TARGET_RELEASE" > "$release_file"
      printf '%s\n' "edge_fleet_deploy=ok host=$EDGE_FLEET_PRIVATE_HOST release=$EDGE_TARGET_RELEASE" > "$ROOT_DIR/audit/edge-fleet.log"
      printf '%s\n' "edge_fleet_deploy=ok host=$EDGE_FLEET_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
    else
      printf '%s\n' 'blocked' > "$release_file"
      printf '%s\n' "edge_fleet_deploy=failed host=$EDGE_FLEET_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    current=$(cat "$release_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$current" = "$EDGE_TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "edge_fleet_health=ok host=$EDGE_FLEET_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "edge_fleet_health=failed host=$EDGE_FLEET_PRIVATE_HOST release=$EDGE_TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-edge-fleet.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN

  cat > "$workspace_dir/bin/publish-release.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/remote/release-pack.env"
core_canary_release=$(cat "$ROOT_DIR/state/core.canary.release" 2>/dev/null || printf '%s' 'missing')
core_fleet_release=$(cat "$ROOT_DIR/state/core.fleet.release" 2>/dev/null || printf '%s' 'missing')
edge_canary_release=$(cat "$ROOT_DIR/state/edge.canary.release" 2>/dev/null || printf '%s' 'missing')
edge_fleet_release=$(cat "$ROOT_DIR/state/edge.fleet.release" 2>/dev/null || printf '%s' 'missing')
if [ "$RELEASE_APPROVED" != "1" ] || [ "$RELEASE_NOTES_READY" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$PACK_STATE" != "ready" ] \
  || [ "$core_canary_release" != "$CORE_TARGET_RELEASE" ] || [ "$core_fleet_release" != "$CORE_TARGET_RELEASE" ] \
  || [ "$edge_canary_release" != "$EDGE_TARGET_RELEASE" ] || [ "$edge_fleet_release" != "$EDGE_TARGET_RELEASE" ]; then
  printf '%s\n' 'publish_release=blocked'
  exit 1
fi
cp "$ROOT_DIR/release/staging/current.json.next" "$ROOT_DIR/release/live/current.json"
printf '%s\n' 'applied' > "$ROOT_DIR/state/release.publish.status"
printf '%s\n' "publish_release=ok release=$RELEASE_TARGET" > "$ROOT_DIR/audit/release-publish.log"
printf '%s\n' 'publish_release=ok'
EOF_BIN

  cat > "$workspace_dir/bin/verify-release.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/remote/release-pack.env"
tunnel_state=$(cat "$ROOT_DIR/state/boundary.tunnel" 2>/dev/null || printf '%s' 'missing')
core_canary_release=$(cat "$ROOT_DIR/state/core.canary.release" 2>/dev/null || printf '%s' 'missing')
core_fleet_release=$(cat "$ROOT_DIR/state/core.fleet.release" 2>/dev/null || printf '%s' 'missing')
edge_canary_release=$(cat "$ROOT_DIR/state/edge.canary.release" 2>/dev/null || printf '%s' 'missing')
edge_fleet_release=$(cat "$ROOT_DIR/state/edge.fleet.release" 2>/dev/null || printf '%s' 'missing')
publish_state=$(cat "$ROOT_DIR/state/release.publish.status" 2>/dev/null || printf '%s' 'missing')
release_live=$(jq -r .release "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_core=$(jq -r .core "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_edge=$(jq -r .edge "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_log=$(cat "$ROOT_DIR/audit/release-publish.log" 2>/dev/null || printf '%s' 'missing')
core_canary_log=$(cat "$ROOT_DIR/audit/core-canary.log" 2>/dev/null || printf '%s' 'missing')
core_fleet_log=$(cat "$ROOT_DIR/audit/core-fleet.log" 2>/dev/null || printf '%s' 'missing')
edge_canary_log=$(cat "$ROOT_DIR/audit/edge-canary.log" 2>/dev/null || printf '%s' 'missing')
edge_fleet_log=$(cat "$ROOT_DIR/audit/edge-fleet.log" 2>/dev/null || printf '%s' 'missing')
if [ "$READ_ONLY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$tunnel_state" = 'ready' ] \
  && [ "$RELEASE_APPROVED" = "1" ] && [ "$RELEASE_NOTES_READY" = "1" ] \
  && [ "$core_canary_release" = "$CORE_TARGET_RELEASE" ] && [ "$core_fleet_release" = "$CORE_TARGET_RELEASE" ] \
  && [ "$edge_canary_release" = "$EDGE_TARGET_RELEASE" ] && [ "$edge_fleet_release" = "$EDGE_TARGET_RELEASE" ] \
  && [ "$publish_state" = "applied" ] && [ "$release_live" = "$RELEASE_TARGET" ] \
  && [ "$release_core" = "$CORE_TARGET_RELEASE" ] && [ "$release_edge" = "$EDGE_TARGET_RELEASE" ] \
  && printf '%s' "$release_log" | grep -q 'publish_release=ok' \
  && printf '%s' "$core_canary_log" | grep -q 'core_canary_deploy=ok' \
  && printf '%s' "$core_fleet_log" | grep -q 'core_fleet_deploy=ok' \
  && printf '%s' "$edge_canary_log" | grep -q 'edge_canary_deploy=ok' \
  && printf '%s' "$edge_fleet_log" | grep -q 'edge_fleet_deploy=ok'; then
  printf '%s\n' 'release_pack_verify=ok'
  exit 0
fi
printf '%s\n' 'release_pack_verify=failed'
exit 1
EOF_BIN

  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/remote/release-pack.env.bak" "$ROOT_DIR/remote/release-pack.env"
cp "$ROOT_DIR/state/core.canary.release.bak" "$ROOT_DIR/state/core.canary.release"
cp "$ROOT_DIR/state/core.fleet.release.bak" "$ROOT_DIR/state/core.fleet.release"
cp "$ROOT_DIR/state/edge.canary.release.bak" "$ROOT_DIR/state/edge.canary.release"
cp "$ROOT_DIR/state/edge.fleet.release.bak" "$ROOT_DIR/state/edge.fleet.release"
cp "$ROOT_DIR/release/live/current.json.bak" "$ROOT_DIR/release/live/current.json"
cp "$ROOT_DIR/release/staging/current.json.next.bak" "$ROOT_DIR/release/staging/current.json.next"
printf '%s\n' 'pending' > "$ROOT_DIR/state/release.publish.status"
rm -f "$ROOT_DIR/state/boundary.tunnel" "$ROOT_DIR/audit/core-canary.log" "$ROOT_DIR/audit/core-fleet.log" "$ROOT_DIR/audit/edge-canary.log" "$ROOT_DIR/audit/edge-fleet.log" "$ROOT_DIR/audit/release-publish.log"
printf '%s\n' 'rollback_status=ready'
EOF_BIN

  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Remote Release Pack Demo

Use the bastion helper plus the core and edge private-boundary helpers in `bin/` to recover the bounded remote release pack.
The pack is healthy only when the bastion tunnel opens first, the core boundary pair deploys second and third,
the edge boundary pair deploys fourth and fifth, `./bin/publish-release.sh` publishes the shared release pack,
`./bin/verify-release.sh` passes, and rollback stays intact.
EOF_README
}

label=$DEFAULT_LABEL
prompt_override=""
prompt_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --prompt)
      prompt_override=$2
      shift 2
      ;;
    --prompt-file)
      prompt_file=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("qwen2.5-coder:7b")) then "qwen2.5-coder:7b"
  elif ($m | index("mistral:7b")) then "mistral:7b"
  else ($m[0] // empty)
  end
')
[ -n "$model" ] || { echo "No installed models available; remote release pack probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_remote_release_pack_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded remote release pack in this workspace. Use `./bin/ssh-bastion.sh`, `./bin/ssh-core-canary.sh`, `./bin/ssh-core-fleet.sh`, `./bin/ssh-edge-canary.sh`, `./bin/ssh-edge-fleet.sh`, `./bin/publish-release.sh`, `./bin/verify-release.sh`, and `./bin/rollback.sh`. Make the smallest safe shared release-pack fix so the bastion tunnel opens first, the core boundary pair deploys before the edge boundary pair, publish the shared release pack, rerun release verification, keep rollback intact, and do not widen beyond this one remote release pack. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=assistant&compute_budget=long&advanced_loop=1&max_iterations=6&stream_session=$(uri "$stream_session")"
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=200 post_api_json_with_timeout "$run_body" 110)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

config_fixed=0
if grep -q '^CORE_APPROVED_RELEASE=2026.03.22-core$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^EDGE_APPROVED_RELEASE=2026.03.22-edge$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^RELEASE_APPROVED=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^TUNNEL_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^CORE_CANARY_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^CORE_FLEET_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^EDGE_CANARY_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^EDGE_FLEET_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^RELEASE_NOTES_READY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/remote/release-pack.env" \
  && grep -q '^PACK_STATE=ready$' "$tmp_ws/remote/release-pack.env"; then
  config_fixed=1
fi

bastion_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh status")) | if . then 1 else 0 end')
bastion_tunnel_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh tunnel")) | if . then 1 else 0 end')
bastion_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh health")) | if . then 1 else 0 end')
core_canary_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-canary.sh status")) | if . then 1 else 0 end')
core_canary_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-canary.sh deploy")) | if . then 1 else 0 end')
core_canary_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-canary.sh health")) | if . then 1 else 0 end')
core_fleet_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-fleet.sh status")) | if . then 1 else 0 end')
core_fleet_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-fleet.sh deploy")) | if . then 1 else 0 end')
core_fleet_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-core-fleet.sh health")) | if . then 1 else 0 end')
edge_canary_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-canary.sh status")) | if . then 1 else 0 end')
edge_canary_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-canary.sh deploy")) | if . then 1 else 0 end')
edge_canary_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-canary.sh health")) | if . then 1 else 0 end')
edge_fleet_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-fleet.sh status")) | if . then 1 else 0 end')
edge_fleet_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-fleet.sh deploy")) | if . then 1 else 0 end')
edge_fleet_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-edge-fleet.sh health")) | if . then 1 else 0 end')
publish_release_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/publish-release.sh")) | if . then 1 else 0 end')
verify_release_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/verify-release.sh")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' '1' || printf '%s' '0')
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' '1' || printf '%s' '0')
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' '1' || printf '%s' '0')
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' '1' || printf '%s' '0')
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' '1' || printf '%s' '0')
bastion_health_ok=$(sh "$tmp_ws/bin/ssh-bastion.sh" health >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
core_canary_health_ok=$(sh "$tmp_ws/bin/ssh-core-canary.sh" health >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
core_fleet_health_ok=$(sh "$tmp_ws/bin/ssh-core-fleet.sh" health >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
edge_canary_health_ok=$(sh "$tmp_ws/bin/ssh-edge-canary.sh" health >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
edge_fleet_health_ok=$(sh "$tmp_ws/bin/ssh-edge-fleet.sh" health >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
verify_release_ok=$(sh "$tmp_ws/bin/verify-release.sh" >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] \
  && cmp -s "$baseline_dir/remote/release-pack.env.bak" "$tmp_ws/remote/release-pack.env.bak" \
  && cmp -s "$baseline_dir/state/core.canary.release.bak" "$tmp_ws/state/core.canary.release.bak" \
  && cmp -s "$baseline_dir/state/core.fleet.release.bak" "$tmp_ws/state/core.fleet.release.bak" \
  && cmp -s "$baseline_dir/state/edge.canary.release.bak" "$tmp_ws/state/edge.canary.release.bak" \
  && cmp -s "$baseline_dir/state/edge.fleet.release.bak" "$tmp_ws/state/edge.fleet.release.bak" \
  && cmp -s "$baseline_dir/release/live/current.json.bak" "$tmp_ws/release/live/current.json.bak" \
  && printf '%s' '1' || printf '%s' '0')
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status='fail'
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] \
  && [ "$bastion_status_ran" -eq 1 ] && [ "$bastion_tunnel_ran" -eq 1 ] && [ "$bastion_health_ran" -eq 1 ] \
  && [ "$core_canary_status_ran" -eq 1 ] && [ "$core_canary_deploy_ran" -eq 1 ] && [ "$core_canary_health_ran" -eq 1 ] \
  && [ "$core_fleet_status_ran" -eq 1 ] && [ "$core_fleet_deploy_ran" -eq 1 ] && [ "$core_fleet_health_ran" -eq 1 ] \
  && [ "$edge_canary_status_ran" -eq 1 ] && [ "$edge_canary_deploy_ran" -eq 1 ] && [ "$edge_canary_health_ran" -eq 1 ] \
  && [ "$edge_fleet_status_ran" -eq 1 ] && [ "$edge_fleet_deploy_ran" -eq 1 ] && [ "$edge_fleet_health_ran" -eq 1 ] \
  && [ "$publish_release_ran" -eq 1 ] && [ "$verify_release_ran" -eq 1 ] \
  && [ "$bastion_health_ok" -eq 1 ] && [ "$core_canary_health_ok" -eq 1 ] && [ "$core_fleet_health_ok" -eq 1 ] \
  && [ "$edge_canary_health_ok" -eq 1 ] && [ "$edge_fleet_health_ok" -eq 1 ] && [ "$verify_release_ok" -eq 1 ] \
  && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] \
  && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"bastion_status_ran":%s,"bastion_tunnel_ran":%s,"bastion_health_ran":%s,"core_canary_status_ran":%s,"core_canary_deploy_ran":%s,"core_canary_health_ran":%s,"core_fleet_status_ran":%s,"core_fleet_deploy_ran":%s,"core_fleet_health_ran":%s,"edge_canary_status_ran":%s,"edge_canary_deploy_ran":%s,"edge_canary_health_ran":%s,"edge_fleet_status_ran":%s,"edge_fleet_deploy_ran":%s,"edge_fleet_health_ran":%s,"publish_release_ran":%s,"verify_release_ran":%s,"bastion_health_ok":%s,"core_canary_health_ok":%s,"core_fleet_health_ok":%s,"edge_canary_health_ok":%s,"edge_fleet_health_ok":%s,"verify_release_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$bastion_status_ran" "$bastion_tunnel_ran" "$bastion_health_ran" "$core_canary_status_ran" "$core_canary_deploy_ran" "$core_canary_health_ran" "$core_fleet_status_ran" "$core_fleet_deploy_ran" "$core_fleet_health_ran" "$edge_canary_status_ran" "$edge_canary_deploy_ran" "$edge_canary_health_ran" "$edge_fleet_status_ran" "$edge_fleet_deploy_ran" "$edge_fleet_health_ran" "$publish_release_ran" "$verify_release_ran" "$bastion_health_ok" "$core_canary_health_ok" "$core_fleet_health_ok" "$edge_canary_health_ok" "$edge_fleet_health_ok" "$verify_release_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Remote Release Pack Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `ssh-bastion.sh status` ran: %s\n' "$bastion_status_ran"
  printf -- '- `ssh-bastion.sh tunnel` ran: %s\n' "$bastion_tunnel_ran"
  printf -- '- `ssh-bastion.sh health` ran: %s\n' "$bastion_health_ran"
  printf -- '- `ssh-core-canary.sh status` ran: %s\n' "$core_canary_status_ran"
  printf -- '- `ssh-core-canary.sh deploy` ran: %s\n' "$core_canary_deploy_ran"
  printf -- '- `ssh-core-canary.sh health` ran: %s\n' "$core_canary_health_ran"
  printf -- '- `ssh-core-fleet.sh status` ran: %s\n' "$core_fleet_status_ran"
  printf -- '- `ssh-core-fleet.sh deploy` ran: %s\n' "$core_fleet_deploy_ran"
  printf -- '- `ssh-core-fleet.sh health` ran: %s\n' "$core_fleet_health_ran"
  printf -- '- `ssh-edge-canary.sh status` ran: %s\n' "$edge_canary_status_ran"
  printf -- '- `ssh-edge-canary.sh deploy` ran: %s\n' "$edge_canary_deploy_ran"
  printf -- '- `ssh-edge-canary.sh health` ran: %s\n' "$edge_canary_health_ran"
  printf -- '- `ssh-edge-fleet.sh status` ran: %s\n' "$edge_fleet_status_ran"
  printf -- '- `ssh-edge-fleet.sh deploy` ran: %s\n' "$edge_fleet_deploy_ran"
  printf -- '- `ssh-edge-fleet.sh health` ran: %s\n' "$edge_fleet_health_ran"
  printf -- '- `publish-release.sh` ran: %s\n' "$publish_release_ran"
  printf -- '- `verify-release.sh` ran: %s\n' "$verify_release_ran"
  printf -- '- Bastion health now passes: %s\n' "$bastion_health_ok"
  printf -- '- Core canary health now passes: %s\n' "$core_canary_health_ok"
  printf -- '- Core fleet health now passes: %s\n' "$core_fleet_health_ok"
  printf -- '- Edge canary health now passes: %s\n' "$edge_canary_health_ok"
  printf -- '- Edge fleet health now passes: %s\n' "$edge_fleet_health_ok"
  printf -- '- Verify-release now passes: %s\n' "$verify_release_ok"
  printf -- '- Rollback referenced: %s\n' "$rollback_ref"
  printf -- '- Rollback intact: %s\n' "$rollback_intact"
  printf -- '- Has Outcome section: %s\n' "$has_outcome"
  printf -- '- Has Verification Evidence section: %s\n' "$has_verify"
  printf -- '- Has Risks section: %s\n' "$has_risks"
  printf -- '- Has Next Improvement section: %s\n' "$has_next"
  printf -- '- Stream line count: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
