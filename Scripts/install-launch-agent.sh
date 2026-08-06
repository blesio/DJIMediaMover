#!/bin/zsh
set -euo pipefail
app="${1:-$PWD/build/DJI Media Mover.app}"
target="/Applications/DJI Media Mover.app"
launcher_dir="$HOME/Library/Application Support/DJI Media Mover"
launcher="$launcher_dir/launch-dji-media-mover.sh"
mkdir -p "$HOME/Library/LaunchAgents" "$launcher_dir"
launchctl bootout "gui/$(id -u)/com.radek.DJIMediaMover" 2>/dev/null || true
pkill -x DJIMediaMover 2>/dev/null || true
sleep 1
ditto "$app" "$target"
xattr -cr "$target"
codesign --force --deep --sign - "$target"
cp "${0:A:h:h}/Resources/launch-dji-media-mover.sh" "$launcher"
chmod +x "$launcher"
sed "s|__LAUNCHER_PATH__|$launcher|g" "${0:A:h:h}/Resources/com.radek.DJIMediaMover.plist.template" > "$HOME/Library/LaunchAgents/com.radek.DJIMediaMover.plist"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.radek.DJIMediaMover.plist"
