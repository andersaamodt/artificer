#!/bin/sh
set -eu

BASE_PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/opt/pkg/bin:/opt/pkg/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
PATH="$BASE_PATH${PATH:+:$PATH}"
export PATH

BACKEND_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
BACKEND_ROOT=$(CDPATH= cd -- "$BACKEND_SCRIPT_DIR/.." && pwd -P)
. "$BACKEND_SCRIPT_DIR/lib/wizardry_runtime.sh"

ACTION=${1-}
APP_DIR=${2-}
ARG3=${3-}

ROOT="${WEB_WIZARDRY_ROOT:-$HOME/sites}"
SITE="$ROOT/artificer"
CFG="$SITE/site.conf"
ARTIFICER_STATE_ROOT=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/artificer}

resolve_apps_root() {
  apps_root=${WIZARDRY_APPS_ROOT:-}
  if [ -z "$apps_root" ]; then
    apps_root=${WIZARDRY_DIR:-$HOME/.wizardry}
  fi
  printf '%s\n' "$apps_root"
}

ensure_wizardry_runtime() {
  wizardry_bootstrap_or_install "$BACKEND_ROOT" "$HOME" || exit 127
}

resolve_web_cmd() {
  apps_root=$(resolve_apps_root)
  web_cmd="$apps_root/spells/web/web-wizardry"
  if [ ! -x "$web_cmd" ]; then
    web_cmd="web-wizardry"
  fi
  printf '%s\n' "$web_cmd"
}

set_site_port_value() {
  new_port=${1-}
  case "$new_port" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ -f "$CFG" ] || return 1
  tmp="$CFG.tmp.$$"
  if ! awk -F= -v p="$new_port" 'BEGIN{done=0} /^port=/{print "port=" p; done=1; next} {print} END{if(!done) print "port=" p}' "$CFG" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$CFG"
}

probe_port() {
  p=${1-}
  [ -n "$p" ] || return 1
  case "$p" in
    *[!0-9]*) return 1 ;;
  esac
  if curl -fsS --max-time 2 "http://127.0.0.1:$p/pages/index.html" 2>/dev/null | head -c 4096 | tr '[:upper:]' '[:lower:]' | grep -q '<title>artificer'; then
    return 0
  fi
  return 1
}

cmd_ensure_data_root() {
  data="$ROOT/.sitedata"
  target="$data/artificer/artificer"
  mkdir -p "$target/workspaces"
}

cmd_ensure_site() {
  ensure_wizardry_runtime
  [ -n "$APP_DIR" ] || {
    printf 'unable to resolve app directory\n' >&2
    exit 1
  }
  hosted="$APP_DIR/hosted-web"
  [ -d "$hosted" ] || {
    printf 'hosted-web assets missing at %s\n' "$hosted" >&2
    exit 1
  }

  web_cmd=$(resolve_web_cmd)

  rebuild=0
  [ -f "$CFG" ] || rebuild=1
  [ -L "$SITE/cgi" ] && rebuild=1
  [ -L "$SITE/site/pages" ] && rebuild=1
  [ -L "$SITE/site/static" ] && rebuild=1
  [ -L "$SITE/site/includes" ] && rebuild=1
  [ -d "$SITE/cgi" ] || rebuild=1
  [ -d "$SITE/site/pages" ] || rebuild=1
  [ -d "$SITE/site/static" ] || rebuild=1

  if [ "$rebuild" -eq 1 ]; then
    uploads_tmp=$(mktemp -d "${TMPDIR:-/tmp}/artificer-uploads.XXXXXX")
    if [ -d "$SITE/site/uploads" ]; then
      cp -R "$SITE/site/uploads/." "$uploads_tmp/" 2>/dev/null || true
    fi
    rm -rf "$SITE"
    mkdir -p "$SITE"
    cp -R "$hosted/." "$SITE/"
    if [ -d "$SITE/pages" ]; then
      mkdir -p "$SITE/site"
      mv "$SITE/pages" "$SITE/site/"
    fi
    if [ -d "$SITE/static" ]; then
      mkdir -p "$SITE/site"
      mv "$SITE/static" "$SITE/site/"
    fi
    if [ -d "$SITE/includes" ]; then
      mkdir -p "$SITE/site"
      mv "$SITE/includes" "$SITE/site/"
    fi
    mkdir -p "$SITE/site/uploads" "$SITE/build"
    cp -R "$uploads_tmp/." "$SITE/site/uploads/" 2>/dev/null || true
    rm -rf "$uploads_tmp"
  fi

  cfg_fix=0
  [ -f "$CFG" ] || cfg_fix=1
  if [ "$cfg_fix" -eq 0 ]; then
    grep -q '^site-name=' "$CFG" 2>/dev/null || cfg_fix=1
    grep -q '^site-user=' "$CFG" 2>/dev/null || cfg_fix=1
    grep -q '^template=' "$CFG" 2>/dev/null || cfg_fix=1
    grep -q '^port=' "$CFG" 2>/dev/null || cfg_fix=1
    grep -q '^domain=' "$CFG" 2>/dev/null || cfg_fix=1
    grep -q '^https=' "$CFG" 2>/dev/null || cfg_fix=1
  fi

  if [ "$cfg_fix" -eq 1 ]; then
    {
      echo 'site-name=artificer'
      echo 'site-user='
      echo 'template=artificer'
      echo 'port=8080'
      echo 'domain=localhost'
      echo 'https=false'
    } > "$CFG"
  fi

  if [ ! -f "$SITE/site.allowlist" ]; then
    echo '# List additional absolute paths this site may access.' > "$SITE/site.allowlist"
  fi

  for asset_dir in pages static includes; do
    if [ -d "$hosted/$asset_dir" ]; then
      mkdir -p "$SITE/site"
      rm -rf "$SITE/site/$asset_dir"
      cp -R "$hosted/$asset_dir" "$SITE/site/"
    fi
  done

  # Keep CGI runtime scripts in sync even when a full site rebuild is skipped.
  if [ -d "$hosted/cgi" ]; then
    mkdir -p "$SITE/cgi"
    for cgi_name in artificer-api mode-runtime-lib.sh multi-agent-lib.sh; do
      if [ -f "$hosted/cgi/$cgi_name" ]; then
        cp "$hosted/cgi/$cgi_name" "$SITE/cgi/$cgi_name"
        chmod +x "$SITE/cgi/$cgi_name" 2>/dev/null || true
      fi
    done
  fi

  needs_build=0
  [ -f "$SITE/build/pages/index.html" ] || needs_build=1
  if [ "$needs_build" -eq 0 ] && find "$hosted/pages" "$hosted/static" "$hosted/includes" "$hosted/cgi" -type f -newer "$SITE/build/pages/index.html" 2>/dev/null | read x; then
    needs_build=1
  fi
  [ "$needs_build" -eq 0 ] || "$web_cmd" build artificer

  if [ -n "$APP_DIR" ]; then
    app_root_canonical=$(cd "$APP_DIR" 2>/dev/null && pwd -P || true)
    if [ -n "$app_root_canonical" ]; then
      printf '%s\n' "$app_root_canonical" > "$SITE/.artificer-app-root"
    fi
  fi
}

cmd_start_serve() {
  ensure_wizardry_runtime
  web_cmd=$(resolve_web_cmd)
  ready_port=$(cmd_detect_ready_port)
  if [ -n "$ready_port" ]; then
    printf '%s\n' "$ready_port"
    exit 0
  fi

  if [ "$(cmd_is_running)" = "yes" ]; then
    "$web_cmd" stop artificer >/dev/null 2>&1 || true
  fi

  serve_log="$ARTIFICER_STATE_ROOT/logs/backend-serve.log"
  mkdir -p "$SITE" "$(dirname "$serve_log")"
  nohup "$web_cmd" serve artificer >"$serve_log" 2>&1 &

  i=0
  while [ "$i" -lt 40 ]; do
    ready_port=$(cmd_detect_ready_port)
    if [ -n "$ready_port" ]; then
      printf '%s\n' "$ready_port"
      exit 0
    fi
    sleep 0.25
    i=$((i+1))
  done

  printf 'artificer start timed out; see %s\n' "$serve_log" >&2
  exit 1
}

cmd_ensure_usable_port() {
  [ -f "$CFG" ] || {
    printf '8080'
    exit 0
  }
  pidf="$SITE/nginx/nginx.pid"
  nginx_cfg="$SITE/nginx/nginx.conf"
  port=$(sed -n 's/^port=//p' "$CFG" 2>/dev/null | head -n 1)
  [ -n "$port" ] || port=8080

  if command -v lsof >/dev/null 2>&1; then
    if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      printf '%s' "$port"
      exit 0
    fi
    p=8081
    while [ "$p" -le 8120 ]; do
      if ! lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
        set_site_port_value "$p" && printf '%s' "$p" && exit 0
      fi
      p=$((p+1))
    done
    exit 1
  fi

  if [ -f "$pidf" ] && pid=$(cat "$pidf" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -F "$nginx_cfg" >/dev/null 2>&1; then
    printf '%s' "$port"
    exit 0
  fi
  printf '%s' "$port"
}

cmd_is_running() {
  pidf="$SITE/nginx/nginx.pid"
  nginx_cfg="$SITE/nginx/nginx.conf"
  port=$(sed -n 's/^port=//p' "$CFG" 2>/dev/null | head -n 1)
  [ -n "$port" ] || port=8080

  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      printf 'yes'
    else
      printf 'no'
    fi
    exit 0
  fi

  if [ -f "$pidf" ] && pid=$(cat "$pidf" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -F "$nginx_cfg" >/dev/null 2>&1; then
    printf 'yes'
  else
    printf 'no'
  fi
}

cmd_get_port() {
  if [ -f "$CFG" ]; then
    sed -n 's/^port=//p' "$CFG" | head -n 1
  fi
}

cmd_probe_ready() {
  port=$(sed -n 's/^port=//p' "$CFG" 2>/dev/null | head -n 1)
  [ -n "$port" ] || port=8080
  if probe_port "$port"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

cmd_detect_ready_port() {
  cfg_port=$(sed -n 's/^port=//p' "$CFG" 2>/dev/null | head -n 1)
  if probe_port "$cfg_port"; then
    printf '%s' "$cfg_port"
    exit 0
  fi
  conf_port=$(sed -n 's/^[[:space:]]*listen[[:space:]]\([0-9][0-9]*\).*;$/\1/p' "$SITE/nginx/nginx.conf" 2>/dev/null | head -n 1)
  if [ "$conf_port" != "$cfg_port" ] && probe_port "$conf_port"; then
    printf '%s' "$conf_port"
    exit 0
  fi
  printf ''
}

cmd_set_port() {
  new_port=${ARG3-}
  set_site_port_value "$new_port" || exit 1
}

case "$ACTION" in
  ensure-data-root) cmd_ensure_data_root ;;
  ensure-site) cmd_ensure_site ;;
  start-serve) cmd_start_serve ;;
  ensure-usable-port) cmd_ensure_usable_port ;;
  is-running) cmd_is_running ;;
  get-port) cmd_get_port ;;
  probe-ready) cmd_probe_ready ;;
  detect-ready-port) cmd_detect_ready_port ;;
  set-port) cmd_set_port ;;
  *)
    printf 'unknown action: %s\n' "$ACTION" >&2
    exit 2
    ;;
esac
