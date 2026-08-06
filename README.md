# DJI Media Mover

A native SwiftUI macOS menu-bar app that detects DJI USB storage, imports JPEG and MP4 media into `Photos/YYYY-MM-DD` and `Videos/YYYY-MM-DD`, verifies every copy with SHA-256, and only then deletes the verified source media.

## Build and run

```sh
chmod +x Scripts/*.sh
Scripts/build-app.sh
open "build/DJI Media Mover.app"
```

Choose a destination on first launch. To install the built app in `/Applications` and start it automatically at login:

```sh
Scripts/install-launch-agent.sh "build/DJI Media Mover.app"
```

The LaunchAgent invokes a stable launcher under `~/Library/Application Support/DJI Media Mover`. At login the launcher searches `/Applications` first and then `~/Applications`, so the app continues to start from either standard application folder if it is moved later.

The destination is retained as a security-scoped bookmark so subsequent launches can restore access without showing the folder picker again. Keep the installed app in `/Applications`; running changing development builds can cause macOS privacy controls to request access again.

The app always runs as a menu-bar accessory and never appears in the Dock. Login creates no progress window. A verified DJI connection explicitly creates and opens the progress window without changing that policy. Closing the window or disconnecting all DJI volumes hides it while monitoring and active transfers continue in the background.

The main window is dedicated to live progress. Destination and automatic-import preferences live in the menu-bar Settings window, while `Import Immediately` provides a manual menu-bar action whenever DJI storage is connected.

`Unmount DJI Storage` safely unmounts every detected DJI volume from the menu bar. It is disabled during transfers and never force-unmounts a busy volume.
After every detected volume unmounts successfully, a foreground confirmation states that the drone is safe to disconnect.

Settings can optionally unmount DJI storage automatically after a non-empty import completes successfully. Failed imports and empty scans remain mounted.

The selected import destination must still exist and be writable when an import starts; the app never recreates a missing destination path. Settings can optionally remove source files that were imported previously, but only after an existing same-name or numerically suffixed destination file matches both the source size and SHA-256 hash. This duplicate-removal option is disabled by default.

During active copies, the progress window displays the current file's average transfer speed, calculated from bytes successfully written to the resumable partial file over its elapsed copy time.

The detector resolves each mounted volume to its BSD disk and walks its I/O Registry parent chain. A volume is accepted only when it belongs to USB vendor ID `0x2CA3` (DJI), or exposes a DJI USB vendor property, **and** is removable storage with DJI's `DCIM/DJI_*` layout. Multiple mounted DJI volumes are imported together. Existing same-name files are SHA-256 checked; identical files count as verified, while different files receive a numeric suffix. Interrupted files retain a hidden deterministic `.dji-partial` file; after reconnection its byte prefix is checked against the source and copying resumes from that point. Each JPEG/MP4 source is deleted immediately after its destination copy passes verification, together with matching `.LRF` and `.AIS` companions. This makes restarts scan only unfinished media. A per-file failure is recorded while remaining files continue, and failed sources stay available for automatic retry with backoff from 10 seconds up to 5 minutes.
