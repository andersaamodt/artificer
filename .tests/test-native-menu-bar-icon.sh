#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
render_script="$root/scripts/render-native-desktop.sh"
package="$root/generated/macos/Package.swift"
generated_swift="$root/generated/macos/Sources/App/App.swift"
asset="$root/assets/menu-bar-icon.png"
generated_asset="$root/generated/macos/Sources/App/Resources/menu-bar-icon.png"

[ -s "$asset" ] || {
  printf '%s\n' "native menu bar icon asset is missing" >&2
  exit 1
}

for file in "$template" "$generated_swift"; do
  grep -q 'ArtificerStatusItemController(model: launchModel)' "$file" || {
    printf '%s\n' "native app should install the AppKit status item controller at launch: $file" >&2
    exit 1
  }
  grep -q 'NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)' "$file" || {
    printf '%s\n' "native app should create a real NSStatusItem: $file" >&2
    exit 1
  }
  grep -q 'item.button?.image = artificerMenuBarImage()' "$file" || {
    printf '%s\n' "native status item should use the Artificer menu bar icon image: $file" >&2
    exit 1
  }
  grep -q 'loadDesktopPrefsForLaunch()' "$file" || {
    printf '%s\n' "native app should load menu_bar_icon before a window task runs: $file" >&2
    exit 1
  }
  grep -q 'assets/menu-bar-icon.png' "$file" || {
    printf '%s\n' "native app should fall back to the source menu bar icon asset: $file" >&2
    exit 1
  }
done

grep -q 'cp "$project_dir/assets/menu-bar-icon.png" "$macos_dir/Sources/App/Resources/menu-bar-icon.png"' "$render_script" || {
  printf '%s\n' "renderer should stage the menu bar icon resource" >&2
  exit 1
}

grep -q '.process("Resources")' "$package" || {
  printf '%s\n' "Swift package should include generated Resources" >&2
  exit 1
}

cmp "$asset" "$generated_asset" || {
  printf '%s\n' "generated menu bar icon should match source asset" >&2
  exit 1
}

printf '%s\n' "ok native menu bar icon contract"
