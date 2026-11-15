#!/bin/bash
# Builds dist/BitMount.app and dist/BitMount-<version>.zip for a GitHub release.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release
bin="$(swift build -c release --show-bin-path)"
plist="Sources/BitMount/Resources/AppInfo.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"

app="dist/BitMount.app"
rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/BitMount" "$app/Contents/MacOS/BitMount"
# Debug info holds the absolute paths of the build folder, and with them the builder's user name.
strip -S "$app/Contents/MacOS/BitMount" 2>/dev/null
cp "$plist" "$app/Contents/Info.plist"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R "$bin/BitMount_BitMount.bundle" "$app/Contents/Resources/"
# SwiftPM names the resource bundle after the folder the package was built in.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.alexander-gerontas.BitMount.resources' \
  "$app/Contents/Resources/BitMount_BitMount.bundle/Contents/Info.plist"

# Ad-hoc signature. Apple Silicon does not run unsigned code, and this is not a
# Developer ID signature, so macOS still asks the user to allow the first launch.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

zip="dist/BitMount-$version.zip"
# Without these two options the zip carries "._" metadata files. Finder drops them,
# but `unzip` puts them inside the app, which breaks its signature.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"
echo "$zip"
