# Drinking Project

Drinking Project is a local macOS hydration reminder app built with Swift, AppKit, SwiftUI, WebKit, and AVFoundation. It is designed as a portfolio-quality desktop project: a real menu bar utility with local persistence, reminder scheduling, media playback, privacy-aware file handling, permissions, LaunchAgent support, and a reproducible build/run workflow.

The public repository intentionally contains no private videos, images, audio, generated app bundles, local app data, logs, or personal media details. Add your own local reminder videos after cloning.

## What It Demonstrates

- Native macOS menu bar app architecture with AppKit lifecycle control and SwiftUI management views
- Full-screen reminder windows across one or more displays, with WebKit HUD resources layered over AVFoundation video playback
- Local reminder rules with presets, scheduling edges, daily pause, manual tests, and UK-day reset behavior
- Local JSON persistence with corrupt-file backup and self-test coverage
- A media library that copies local video files into a private local folder, avoids filename collisions, previews playable files, and keeps GitHub clean
- Best-effort browser and background media pause behavior for common macOS apps
- User-level LaunchAgent install/uninstall flow for start-at-login behavior
- Shell-based build, run, QA, signing, and privacy checks without requiring Xcode project files

## Features

- Menu bar status item for quick actions and reminder state
- SwiftUI management window with Overview, Reminder Rules, Video Library, and Settings
- Hydration reminder schedule defaults to 08:00 through 22:00, every 30 minutes, using Europe/London day boundaries
- Reminder rules support enabled/disabled state, custom time ranges, interval minutes, strictness presets, lock duration, confirmation count, and click cooldown
- Reminder windows stay full-screen and on top; the regular close shortcuts are blocked while `Command + Q` remains as an emergency exit
- The confirmation button appears after the configured lock duration and can require multiple spaced clicks
- Local videos play with the configured reminder volume on the primary display; secondary displays mirror the visual reminder silently
- Video library supports adding multiple videos, copying them to `视频/视频素材/`, renaming display titles, previewing, sorting, copying paths, showing in Finder, and deleting with confirmation
- Settings include reminder volume, playback mode, daily pause, easy test mode, display coverage, permissions status, background media test, and LaunchAgent controls

## Privacy Model

Drinking Project is local-only. Reminder rules, media-library metadata, settings, and daily history are saved under:

```text
~/Library/Application Support/Drinking Project/
```

Those files are user data and should not be committed. Real media is also excluded from Git. The repository keeps only placeholder documentation under:

```text
视频/
视频/视频素材/
```

Do not publish private videos, photos, audio, screenshots, generated `.app` bundles, `.build/`, `dist/`, `软甲本体/`, logs, Application Support data, or macOS `._` metadata files.

## Media Folder

Add your own reminder videos locally:

```text
视频/视频素材/
```

Supported video formats:

```text
mp4, mov, m4v, avi, mkv, webm
```

The app scans `视频/视频素材/` first and also supports compatible videos placed directly under `视频/`. The Video Library can copy selected files into the media folder and generate collision-safe names such as `example 2.mp4`.

## Build And Run

Double-click the root launch script:

```text
开启 Drinking Project.command
```

Or run from Terminal:

```zsh
cd "/path/to/Drinking Project"
bash ./script/build_and_run.sh
```

The script compiles the Swift sources, signs an ad-hoc macOS app bundle, and writes it to:

```text
软甲本体/Drinking Project.app
```

Then it launches the app with the project folder passed as the local media root.

To open a test reminder immediately:

```text
测试 Drinking Project.command
```

To stop the app:

```text
关闭 Drinking Project.command
```

## Command Line Workflow

Build only:

```zsh
bash ./script/build_and_run.sh --build-only
```

Run and verify that the app process starts:

```zsh
bash ./script/build_and_run.sh --verify
```

Open a reminder window immediately:

```zsh
bash ./script/build_and_run.sh --test
```

Run the background media pause test:

```zsh
bash ./script/build_and_run.sh --test-background-media
```

Run the full local QA gate:

```zsh
bash ./script/build_and_run.sh --qa
```

The QA command checks WebResources JavaScript syntax, verifies that tracked/staged files do not include private media, builds and signs the app bundle, validates `Info.plist`, and runs the persistence self-test.

## macOS Permissions

The app may request or benefit from these macOS permissions depending on which features you use:

- Automation permission for Safari or Chromium-based browsers when testing best-effort page media pause
- Accessibility permission for supported apps that expose media controls through the accessibility tree
- Removable volume access if local media is stored on an external drive

The app does not use global media-key toggles, kill media apps, upload media, or change the system volume.

## LaunchAgent

Start-at-login is implemented with a user-level LaunchAgent:

```text
~/Library/LaunchAgents/com.local.drinkingproject.plist
```

You can manage it from the Settings view, or with scripts:

```zsh
zsh ./scripts/install_launch_agent.sh
zsh ./scripts/uninstall_launch_agent.sh
```

The LaunchAgent points at the locally built app bundle in `软甲本体/Drinking Project.app` and passes the project directory so the app can find local media and resources.

## Project Structure

```text
Sources/DrinkingProject/App/          App lifecycle, paths, variants, clock helpers
Sources/DrinkingProject/Models/       Reminder, settings, media, and scan models
Sources/DrinkingProject/Services/     Scheduling, media scanning, persistence tests, LaunchAgent, background media control
Sources/DrinkingProject/Stores/       JSON-backed local stores
Sources/DrinkingProject/Views/        SwiftUI management window
Sources/DrinkingProject/Windows/      Full-screen reminder window and WebKit bridge
Sources/DrinkingProject/WebResources/ Reminder HUD HTML/CSS/JavaScript
script/build_and_run.sh               Build, run, test, QA, and privacy gate
scripts/                              Helper scripts for release build and LaunchAgent management
视频/                                 Local-only media placeholder folders
```

## Background Media Pause

Before showing a reminder, the app performs a best-effort pause pass for common media sources. It can inspect supported browser tabs through AppleScript and JavaScript, send explicit pause commands to common players, and use accessibility-based controls for selected apps that do not expose AppleScript playback commands.

This behavior is intentionally defensive: failure to control another app does not block a hydration reminder, does not mute the local reminder video, and does not kill any background process. A structured log line records attempted, paused, skipped, and failed targets for debugging.

## Local Data Files

The app stores these JSON files locally:

```text
reminder-rules.json
video-library.json
settings.json
history.json
```

If a JSON file is corrupt, the app saves a `.corrupt-<timestamp>` backup and falls back to defaults. Daily history is reset at the Europe/London day boundary and is not a long-term activity log.

## Public Repository Checklist

Before publishing, verify:

- no real media files are tracked or staged
- no generated `.app` bundle or build folder is tracked or staged
- no local Application Support JSON is tracked or staged
- media placeholder docs contain only generic instructions
- `bash ./script/build_and_run.sh --qa` passes
