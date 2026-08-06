#!/bin/zsh
set -u

candidates=(
  "/Applications/DJI Media Mover.app/Contents/MacOS/DJIMediaMover"
  "$HOME/Applications/DJI Media Mover.app/Contents/MacOS/DJIMediaMover"
)

for executable in "${candidates[@]}"; do
  if [[ -x "$executable" ]]; then
    if [[ "${1:-}" == "--print-path" ]]; then
      print -r -- "$executable"
      exit 0
    fi
    exec "$executable"
  fi
done

print -u2 "DJI Media Mover was not found in /Applications or ~/Applications."
exit 1
