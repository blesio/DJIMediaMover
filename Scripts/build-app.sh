#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"
swift build -c release
app="$root/build/DJI Media Mover.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/DJIMediaMover" "$app/Contents/MacOS/DJIMediaMover"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/Resources/MenuBarIconTemplate.png" "$app/Contents/Resources/MenuBarIconTemplate.png"
cp "$root/Resources/MenuBarIconTemplate@2x.png" "$app/Contents/Resources/MenuBarIconTemplate@2x.png"
cp "$root/Resources/MenuBarDJI.svg" "$app/Contents/Resources/MenuBarDJI.svg"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
echo "$app"
