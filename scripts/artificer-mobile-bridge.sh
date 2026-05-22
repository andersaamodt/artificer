#!/bin/sh

case "${1-}" in
--help|--usage|-h)
  cat <<'USAGE'
Usage: artificer-mobile-bridge.sh ACTION [ARGS...]

Actions:
  status
  enable
  disable
  restart
  set KEY VALUE
  install-tor

Settings:
  bind_host 127.0.0.1|0.0.0.0
  port 8765
  tor_enabled 0|1
  allow_execute 0|1
  allow_self_actuation 0|1
USAGE
  exit 0
  ;;
esac

set -eu

action=${1-}
shift || true

home=${HOME:?}
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
backend_script=${ARTIFICER_NATIVE_BACKEND:-"$script_dir/artificer-native-backend.sh"}
config_dir="${XDG_CONFIG_HOME:-"$home/.config"}/artificer"
state_dir="${XDG_STATE_HOME:-"$home/.local/state"}/artificer-native/mobile-bridge"
prefs_file="$config_dir/mobile-bridge.env"
pid_file="$state_dir/mobile-bridge.pid"
server_script="$state_dir/mobile-bridge-server.py"
tor_pid_file="$state_dir/tor.pid"
torrc_file="$state_dir/torrc"
token_file="$state_dir/pairing-token"
nl='
'

reject_line_breaks() {
  rlb_value=${1-}
  rlb_label=${2-value}
  case "$rlb_value" in
    *"$nl"*) printf '%s\n' "artificer-mobile-bridge: $rlb_label must not contain line breaks" >&2; exit 2 ;;
  esac
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1] if len(sys.argv) > 1 else ""))
PY
}

read_pref() {
  key=$1
  [ -f "$prefs_file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$prefs_file"
}

write_pref() {
  key=$1
  value=$2
  reject_line_breaks "$key" "setting key"
  reject_line_breaks "$value" "setting value"
  case "$key" in
    bind_host)
      case "$value" in 127.0.0.1|0.0.0.0) ;; *) printf '%s\n' "artificer-mobile-bridge: bind_host must be 127.0.0.1 or 0.0.0.0" >&2; exit 2 ;; esac
      ;;
    port)
      case "$value" in *[!0-9]*|"") printf '%s\n' "artificer-mobile-bridge: port must be numeric" >&2; exit 2 ;; esac
      ;;
    tor_enabled|allow_execute|allow_self_actuation)
      case "$value" in 0|1|true|false|yes|no|on|off) value=$(bool_value "$value") ;; *) printf '%s\n' "artificer-mobile-bridge: $key must be boolean" >&2; exit 2 ;; esac
      ;;
    *) printf '%s\n' "artificer-mobile-bridge: unsupported setting key" >&2; exit 2 ;;
  esac
  mkdir -p "$config_dir"
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-mobile-bridge-prefs.XXXXXX")
  if [ -f "$prefs_file" ]; then
    awk -F= -v wanted="$key" '$1 != wanted' "$prefs_file" >"$tmp_file"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp_file"
  mv "$tmp_file" "$prefs_file"
}

bool_value() {
  case "$1" in
    1|true|yes|on) printf '%s\n' 1 ;;
    0|false|no|off) printf '%s\n' 0 ;;
    *) return 1 ;;
  esac
}

pref_or_default() {
  key=$1
  default=$2
  read_pref "$key" 2>/dev/null || printf '%s\n' "$default"
}

ensure_token() {
  mkdir -p "$state_dir"
  if [ ! -s "$token_file" ]; then
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -hex 18 >"$token_file"
    else
      python3 - <<'PY' >"$token_file"
import secrets
print(secrets.token_hex(18))
PY
    fi
    chmod 600 "$token_file"
  fi
}

process_alive() {
  pid=${1-}
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

current_pid() {
  [ -f "$pid_file" ] || return 1
  sed -n '1p' "$pid_file"
}

tor_pid() {
  [ -f "$tor_pid_file" ] || return 1
  sed -n '1p' "$tor_pid_file"
}

local_ip() {
  if command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null && return 0
    ipconfig getifaddr en1 2>/dev/null && return 0
  fi
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}' && return 0
  fi
  printf '%s\n' ""
}

write_server() {
  mkdir -p "$state_dir"
  cat >"$server_script" <<'PY'
import json
import os
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

backend = os.environ["ARTIFICER_MOBILE_BACKEND"]
token = os.environ["ARTIFICER_MOBILE_TOKEN"]
allow_execute = os.environ.get("ARTIFICER_MOBILE_ALLOW_EXECUTE") == "1"
allow_self = os.environ.get("ARTIFICER_MOBILE_ALLOW_SELF_ACTUATION") == "1"

def run_backend(args):
    proc = subprocess.run([backend] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    text = proc.stdout.strip()
    if proc.returncode != 0:
        raise RuntimeError(text or "backend action failed")
    return text or "{}"

def existing_projects(payload):
    projects = payload.get("projects", [])
    return [
        project for project in projects
        if str(project.get("path_exists", "1")).lower() not in ("0", "false", "no")
    ]

class Handler(BaseHTTPRequestHandler):
    server_version = "ArtificerMobileBridge/0.1"

    def log_message(self, fmt, *args):
        return

    def authed(self):
        return self.headers.get("X-Artificer-Mobile-Token", "") == token

    def write_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8") if not isinstance(payload, bytes) else payload
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def backend_json(self, args):
        return json.loads(run_backend(args))

    def require_auth(self):
        if self.authed():
            return True
        self.write_json(401, {"success": False, "error": "pairing token required"})
        return False

    def do_GET(self):
        if self.path == "/status":
            self.write_json(200, {"success": True, "bridge": "ready"})
            return
        if not self.require_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        try:
            if parsed.path == "/health":
                self.write_json(200, self.backend_json(["health"]))
            elif parsed.path == "/projects":
                payload = self.backend_json(["projects"])
                payload["projects"] = existing_projects(payload)
                self.write_json(200, payload)
            elif parsed.path == "/tree":
                health = self.backend_json(["health"])
                projects_payload = self.backend_json(["projects"])
                projects = existing_projects(projects_payload)
                for project in projects:
                    workspace_id = str(project.get("id", ""))
                    if not workspace_id:
                        project["sessions"] = []
                        continue
                    sessions_payload = self.backend_json(["sessions", workspace_id])
                    project["sessions"] = sessions_payload.get("sessions", [])
                self.write_json(200, {"success": True, "runtime": health.get("runtime", {}), "projects": projects})
            elif parsed.path == "/sessions":
                workspace_id = params.get("workspace_id", [""])[0]
                self.write_json(200, self.backend_json(["sessions", workspace_id]))
            elif parsed.path == "/session":
                workspace_id = params.get("workspace_id", [""])[0]
                conversation_id = params.get("conversation_id", [""])[0]
                self.write_json(200, self.backend_json(["session", workspace_id, conversation_id]))
            else:
                self.write_json(404, {"success": False, "error": "unknown endpoint"})
        except Exception as exc:
            self.write_json(500, {"success": False, "error": str(exc)})

    def do_POST(self):
        if not self.require_auth():
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            if self.path != "/message":
                self.write_json(404, {"success": False, "error": "unknown endpoint"})
                return
            prompt = str(payload.get("prompt", "")).strip()
            if not prompt:
                self.write_json(400, {"success": False, "error": "prompt is required"})
                return
            workspace_id = str(payload.get("workspace_id", ""))
            conversation_id = str(payload.get("conversation_id", ""))
            command_mode = "ask-some"
            self_actuation = "0"
            if allow_execute:
                command_mode = "all"
            if allow_self:
                self_actuation = "1"
            message = self.backend_json([
                "session-message",
                workspace_id,
                conversation_id,
                prompt,
                "auto",
                "auto",
                command_mode,
                "default",
                "1",
                "2",
                "0",
                self_actuation,
                "",
            ])
            if payload.get("run_after", False):
                self.backend_json(["session-run-next", workspace_id, conversation_id])
            self.write_json(200, {"success": True, "message": message})
        except Exception as exc:
            self.write_json(500, {"success": False, "error": str(exc)})

host = os.environ.get("ARTIFICER_MOBILE_HOST", "127.0.0.1")
port = int(os.environ.get("ARTIFICER_MOBILE_PORT", "8765"))
ThreadingHTTPServer((host, port), Handler).serve_forever()
PY
  chmod 700 "$server_script"
}

start_tor_if_needed() {
  tor_enabled=$(pref_or_default tor_enabled 0)
  [ "$tor_enabled" = 1 ] || return 0
  command -v tor >/dev/null 2>&1 || return 0
  if pid=$(tor_pid 2>/dev/null) && process_alive "$pid"; then
    return 0
  fi
  port=$(pref_or_default port 8765)
  hidden_service_dir="$state_dir/tor-hidden-service"
  mkdir -p "$hidden_service_dir"
  chmod 700 "$hidden_service_dir"
  cat >"$torrc_file" <<TORRC
DataDirectory $state_dir/tor-data
HiddenServiceDir $hidden_service_dir
HiddenServicePort 80 127.0.0.1:$port
SocksPort 0
Log notice file $state_dir/tor.log
TORRC
  tor -f "$torrc_file" >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$tor_pid_file"
}

stop_tor() {
  if pid=$(tor_pid 2>/dev/null) && process_alive "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$tor_pid_file"
}

start_bridge() {
  ensure_token
  if pid=$(current_pid 2>/dev/null) && process_alive "$pid"; then
    start_tor_if_needed
    return 0
  fi
  write_server
  bind_host=$(pref_or_default bind_host 127.0.0.1)
  port=$(pref_or_default port 8765)
  allow_execute=$(pref_or_default allow_execute 0)
  allow_self_actuation=$(pref_or_default allow_self_actuation 0)
  ARTIFICER_MOBILE_BACKEND="$backend_script" \
  ARTIFICER_MOBILE_TOKEN="$(cat "$token_file")" \
  ARTIFICER_MOBILE_HOST="$bind_host" \
  ARTIFICER_MOBILE_PORT="$port" \
  ARTIFICER_MOBILE_ALLOW_EXECUTE="$allow_execute" \
  ARTIFICER_MOBILE_ALLOW_SELF_ACTUATION="$allow_self_actuation" \
    python3 "$server_script" >/dev/null 2>"$state_dir/mobile-bridge.log" &
  printf '%s\n' "$!" >"$pid_file"
  start_tor_if_needed
}

stop_bridge() {
  if pid=$(current_pid 2>/dev/null) && process_alive "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pid_file"
  stop_tor
}

install_tor() {
  if command -v tor >/dev/null 2>&1; then
    printf '{"success":true,"installed":true,"method":"existing"}\n'
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    brew install tor >/dev/null
    printf '{"success":true,"installed":true,"method":"brew"}\n'
    return 0
  fi
  printf '{"success":false,"installed":false,"error":"Tor is not installed and no supported package manager was found."}\n'
}

status_json() {
  ensure_token
  bind_host=$(pref_or_default bind_host 127.0.0.1)
  port=$(pref_or_default port 8765)
  tor_enabled=$(pref_or_default tor_enabled 0)
  allow_execute=$(pref_or_default allow_execute 0)
  allow_self_actuation=$(pref_or_default allow_self_actuation 0)
  running=false
  pid=""
  if pid=$(current_pid 2>/dev/null) && process_alive "$pid"; then
    running=true
  fi
  tor_running=false
  tor_address=""
  if tor_pid_value=$(tor_pid 2>/dev/null) && process_alive "$tor_pid_value"; then
    tor_running=true
  fi
  if [ -f "$state_dir/tor-hidden-service/hostname" ]; then
    tor_address=$(sed -n '1p' "$state_dir/tor-hidden-service/hostname")
  fi
  ip=$(local_ip 2>/dev/null || printf '')
  lan_url=""
  if [ "$bind_host" = "0.0.0.0" ] && [ -n "$ip" ]; then
    lan_url="http://$ip:$port"
  fi
  printf '{"success":true,"enabled":%s,"running":%s,"pid":%s,"bind_host":%s,"port":%s,"local_url":%s,"lan_url":%s,"tor_enabled":%s,"tor_running":%s,"tor_address":%s,"pairing_token":%s,"allow_execute":%s,"allow_self_actuation":%s,"config_file":%s,"state_dir":%s}\n' \
    "$running" \
    "$running" \
    "$(json_escape "$pid")" \
    "$(json_escape "$bind_host")" \
    "$(json_escape "$port")" \
    "$(json_escape "http://127.0.0.1:$port")" \
    "$(json_escape "$lan_url")" \
    "$([ "$tor_enabled" = 1 ] && printf true || printf false)" \
    "$tor_running" \
    "$(json_escape "$tor_address")" \
    "$(json_escape "$(cat "$token_file")")" \
    "$([ "$allow_execute" = 1 ] && printf true || printf false)" \
    "$([ "$allow_self_actuation" = 1 ] && printf true || printf false)" \
    "$(json_escape "$prefs_file")" \
    "$(json_escape "$state_dir")"
}

case "$action" in
  status|"")
    status_json
    ;;
  enable)
    start_bridge
    status_json
    ;;
  disable)
    stop_bridge
    status_json
    ;;
  restart)
    stop_bridge
    start_bridge
    status_json
    ;;
  set)
    key=${1-}
    value=${2-}
    [ -n "$key" ] || { printf '%s\n' "artificer-mobile-bridge: set requires KEY" >&2; exit 2; }
    write_pref "$key" "$value"
    status_json
    ;;
  install-tor)
    install_tor
    ;;
  *)
    printf '%s\n' "artificer-mobile-bridge: unknown action: $action" >&2
    exit 2
    ;;
esac
