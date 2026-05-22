#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
. "$SCRIPT_DIR/common.sh"

out_dir=${1-"$ROOT_DIR/dist"}
version=$(artificer_version "$ROOT_DIR")
app_name="Artificer.app"

mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd -P)
app_root="$out_dir/$app_name"
resources_dir="$app_root/Contents/Resources/artificer-app"
macos_dir="$app_root/Contents/MacOS"
zip_path="$out_dir/artificer-$version-macos.zip"
rm -rf "$app_root"
mkdir -p "$macos_dir" "$app_root/Contents/Resources"
artificer_stage_runtime "$ROOT_DIR" "$resources_dir"

cat > "$macos_dir/Artificer" <<'APP'
#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
exec "$HERE/../Resources/artificer-app/artificer" "$@"
APP
chmod +x "$macos_dir/Artificer"

cat > "$app_root/Contents/Info.plist" <<PLIST
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

rm -f "$zip_path"
(
  cd "$out_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_name" "$zip_path"
)
printf 'artifact=%s\n' "$zip_path"
printf 'app=%s\n' "$app_root"
