#!/bin/sh
set -eu

home_dir=$HOME
install_root="$home_dir/.local/share/artificer/app"
shim="$home_dir/.local/bin/artificer"
config_dir="$home_dir/.config/artificer"

if [ -x "$install_root/scripts/artificer-automations.sh" ]; then
  sh "$install_root/scripts/artificer-automations.sh" disable >/dev/null 2>&1 || true
fi

rm -rf "$install_root" "$shim" "$config_dir" "$home_dir/.local/share/applications/artificer.desktop" "$home_dir/Applications/Artificer.app"
if [ -d /Applications/Artificer.app ] && [ -w /Applications ]; then
  rm -rf /Applications/Artificer.app
fi
printf '%s\n' 'uninstalled=artificer'
