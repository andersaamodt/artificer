#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
. "$SCRIPT_DIR/common.sh"

root=$ROOT_DIR
home_dir=$HOME
scope=auto
app_dir=''
install_root=''

usage() {
  cat <<'USAGE'
Usage: install-artificer [--root ROOT_DIR] [--home HOME_DIR] [--system|--user] [--app-dir APP_PATH] [--install-root DIR]

Installs a standalone Artificer runtime and launcher.

Defaults:
  - runtime payload: ~/.local/share/artificer/app
  - command shim: ~/.local/bin/artificer
  - macOS app bundle: /Applications/Artificer.app (falls back to ~/Applications)
  - Linux desktop entry: ~/.local/share/applications/artificer.desktop
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|--usage|-h)
      usage
      exit 0
      ;;
    --root)
      root=${2-}
      [ -n "$root" ] || exit 2
      shift 2
      ;;
    --home)
      home_dir=${2-}
      [ -n "$home_dir" ] || exit 2
      shift 2
      ;;
    --system)
      scope=system
      shift
      ;;
    --user)
      scope=user
      shift
      ;;
    --app-dir)
      app_dir=${2-}
      [ -n "$app_dir" ] || exit 2
      shift 2
      ;;
    --install-root)
      install_root=${2-}
      [ -n "$install_root" ] || exit 2
      shift 2
      ;;
    *)
      printf '%s\n' "install-artificer: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

version=$(artificer_version "$root")
[ -n "$install_root" ] || install_root="$home_dir/.local/share/artificer/app"
bin_dir="$home_dir/.local/bin"
config_dir="$home_dir/.config/artificer"
shim="$bin_dir/artificer"
root_file="$config_dir/install-root"
version_file="$config_dir/version"

mkdir -p "$bin_dir" "$config_dir"
artificer_stage_runtime "$root" "$install_root"
printf '%s\n' "$install_root" > "$root_file"
printf '%s\n' "$version" > "$version_file"

cat > "$shim" <<SHIM
#!/bin/sh
set -eu
exec "$install_root/artificer" "\$@"
SHIM
chmod +x "$shim"

install_macos_bundle() {
  target=$1
  parent=$(dirname "$target")
  bundle="$target"
  macos_dir="$bundle/Contents/MacOS"
  resources_dir="$bundle/Contents/Resources"
  mkdir -p "$macos_dir" "$resources_dir"
  cat > "$macos_dir/Artificer" <<APP
#!/bin/sh
set -eu
exec "$shim" "\$@"
APP
  chmod +x "$macos_dir/Artificer"
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Artificer</string>
<key>CFBundleDisplayName</key><string>Artificer</string>
<key>CFBundleIdentifier</key><string>com.artificer.app</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>Artificer</string>
</dict></plist>
PLIST
  mkdir -p "$parent"
}

os=$(uname -s 2>/dev/null || printf unknown)
case "$os" in
  Darwin)
    if [ -n "$app_dir" ]; then
      target_app=$app_dir
    elif [ "$scope" = "user" ]; then
      target_app="$home_dir/Applications/Artificer.app"
    else
      target_app="/Applications/Artificer.app"
    fi
    if mkdir -p "$(dirname "$target_app")" >/dev/null 2>&1 && rm -rf "$target_app" >/dev/null 2>&1; then
      install_macos_bundle "$target_app"
      printf '%s\n' "installed_app=$target_app"
    else
      target_app="$home_dir/Applications/Artificer.app"
      rm -rf "$target_app"
      install_macos_bundle "$target_app"
      printf '%s\n' "installed_app=$target_app"
    fi
    ;;
  Linux)
    apps_dir="$home_dir/.local/share/applications"
    desktop_file="$apps_dir/artificer.desktop"
    mkdir -p "$apps_dir"
    cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Artificer
Comment=Local-first AI assistant
Exec=/bin/sh "$shim"
Terminal=false
Categories=Development;Utility;
StartupNotify=true
DESKTOP
    printf '%s\n' "installed_desktop=$desktop_file"
    ;;
esac

printf '%s\n' "installed_command=$shim"
printf '%s\n' "install_root=$install_root"
printf '%s\n' "version=$version"
