#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
render_script="$root/scripts/render-native-desktop.sh"
package="$root/generated/macos/Package.swift"
generated_swift="$root/generated/macos/Sources/App/App.swift"
generated_asset="$root/generated/macos/Sources/App/Resources/menu-bar-icon.png"

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
  grep -q 'image.isTemplate = true' "$file" || {
    printf '%s\n' "native menu bar icon should be an AppKit template image: $file" >&2
    exit 1
  }
  grep -q 'item.button?.image?.isTemplate = true' "$file" || {
    printf '%s\n' "native status item should force template rendering: $file" >&2
    exit 1
  }
  perl -0ne 'exit((/let capTip = NSBezierPath\(\)\s*capTip\.move\(to: upperLeft\)\s*capTip\.line\(to: upperTop\)\s*capTip\.line\(to: upperRight\)/s) ? 0 : 1)' "$file" || {
    printf '%s\n' "native menu bar icon should use the non-native Artificer cap path: $file" >&2
    exit 1
  }
  perl -0ne 'exit((/let upperCross = NSBezierPath\(\)\s*upperCross\.move\(to: upperLeft\)\s*upperCross\.line\(to: sharedUpperBottom\)\s*upperCross\.line\(to: lowerRight\)/s) ? 0 : 1)' "$file" || {
    printf '%s\n' "native menu bar icon should use the non-native upper crossing stroke: $file" >&2
    exit 1
  }
  perl -0ne 'exit((/let upperCrossMirror = NSBezierPath\(\)\s*upperCrossMirror\.move\(to: upperRight\)\s*upperCrossMirror\.line\(to: sharedUpperBottom\)\s*upperCrossMirror\.line\(to: lowerLeft\)/s) ? 0 : 1)' "$file" || {
    printf '%s\n' "native menu bar icon should mirror the non-native upper crossing stroke: $file" >&2
    exit 1
  }
  perl -0ne 'exit((/let lowerCross = NSBezierPath\(\)\s*lowerCross\.move\(to: lowerLeft\)\s*lowerCross\.line\(to: lowerBottom\)\s*lowerCross\.line\(to: rightFoot\)/s) ? 0 : 1)' "$file" || {
    printf '%s\n' "native menu bar icon should use the non-native lower crossing stroke: $file" >&2
    exit 1
  }
  perl -0ne 'exit((/let lowerCrossMirror = NSBezierPath\(\)\s*lowerCrossMirror\.move\(to: lowerRight\)\s*lowerCrossMirror\.line\(to: lowerBottom\)\s*lowerCrossMirror\.line\(to: leftFoot\)/s) ? 0 : 1)' "$file" || {
    printf '%s\n' "native menu bar icon should mirror the non-native lower crossing stroke: $file" >&2
    exit 1
  }
  grep -q 'loadDesktopPrefsForLaunch()' "$file" || {
    printf '%s\n' "native app should load menu_bar_icon before a window task runs: $file" >&2
    exit 1
  }
  if grep -q 'isTemplate = false' "$file"; then
    printf '%s\n' "native menu bar icon must not opt out of monochrome template rendering: $file" >&2
    exit 1
  fi
done

grep -q 'cp "$project_dir/assets/menu-bar-icon.png" "$macos_dir/Sources/App/Resources/menu-bar-icon.png"' "$render_script" || {
  printf '%s\n' "renderer should stage the menu bar icon resource" >&2
  exit 1
}

grep -q '.process("Resources")' "$package" || {
  printf '%s\n' "Swift package should include generated Resources" >&2
  exit 1
}

cmp "$root/assets/menu-bar-icon.png" "$generated_asset" || {
  printf '%s\n' "generated menu bar icon should match source asset" >&2
  exit 1
}

printf '%s\n' "ok native menu bar icon contract"
