# Drinking Project

A local macOS hydration reminder built with Swift and AppKit. It runs from the menu bar, checks the local system time, and shows a full-screen reminder every 30 minutes between 08:00 and 22:00, including 22:00.

The public repository intentionally does not include private video, image, or audio assets. Add your own local reminder media under `视频/` after cloning.

## Status

This is a working first release for personal macOS use. The core reminder app, launch scripts, random local video selection, multi-display reminder windows, and user-level LaunchAgent setup are implemented.

## Features

- Menu bar app with the title `水`
- Reminders every 30 minutes from 08:00 through 22:00
- Manual test reminder from the menu bar or command launcher
- Randomly scans `视频/` for playable `.mp4`, `.mov`, and `.m4v` files
- Keeps personal media out of Git by default
- Covers all connected displays during a reminder
- Shows the confirmation button only after 30 seconds
- Requires three `已饮水` confirmations with at least five seconds between clicks
- Attempts to pause common background media sources before showing a reminder
- Sets macOS output volume to 15% during the reminder
- Supports pause-for-today, resume-today, and start-at-login setup
- Keeps `Command + Q` as an emergency exit

## Requirements

- macOS
- Xcode Command Line Tools, including `swiftc`
- Optional: local reminder videos in `视频/`

Install the command line tools if needed:

```bash
xcode-select --install
```

## Quick Start

From Finder, double-click:

```text
开启 Drinking Project.command
```

Or run from Terminal:

```zsh
chmod +x scripts/*.sh *.command
./scripts/run.sh
```

The app will compile the Swift source into `.build/release/DrinkingProject` and start the menu bar item.

## Stop the App

From Finder, double-click:

```text
关闭 Drinking Project.command
```

Or run:

```zsh
pkill -x DrinkingProject
```

## Test a Reminder

From Finder, double-click:

```text
测试 Drinking Project.command
```

This launches the same reminder window used by the normal schedule, including the 30-second lock and three-click confirmation flow.

## Start at Login

Install a user-level LaunchAgent:

```zsh
chmod +x scripts/*.sh
./scripts/install_launch_agent.sh
```

This creates:

```text
~/Library/LaunchAgents/com.local.drinkingproject.plist
```

Remove it later with:

```zsh
./scripts/uninstall_launch_agent.sh
```

## Local Media

Place private reminder videos in:

```text
视频/
```

Supported formats:

```text
mp4, mov, m4v
```

The app rescans this folder before each reminder, so adding or removing videos does not require code changes. If the folder is empty, the reminder still appears with the text and confirmation flow.

## Privacy Boundary

The repository is safe to publish because personal media files are ignored by Git. Keep private videos, images, audio, generated builds, and runtime logs out of version control.

## Validation

Non-interactive checks that do not launch the app:

```zsh
swiftc Sources/DrinkingProject/main.swift \
  -o /tmp/DrinkingProject-check \
  -framework AppKit \
  -framework AVFoundation \
  -framework AVKit

zsh -n scripts/*.sh *.command
```

## Limitations

- This is a local macOS utility, not a distributed App Store app.
- Browser and media pause behavior depends on macOS permissions and each app's scripting support.
- Some AVFoundation APIs currently compile with deprecation warnings on recent macOS SDKs; they do not block the current build.

## License

No open-source license has been selected yet. Until a license is added, reuse is subject to the repository owner's permission.
