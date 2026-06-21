#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
LABEL="com.local.drinkingproject"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BINARY="$PROJECT_DIR/dist/Drinking Project.app/Contents/MacOS/DrinkingProject"

cd "$PROJECT_DIR"
"$PROJECT_DIR/script/build_and_run.sh" --build-only

mkdir -p "$HOME/Library/LaunchAgents"
rm -f "$PLIST"

/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $BINARY" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string --project-dir" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string $PROJECT_DIR" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:3 string --resume-on-launch" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :WorkingDirectory string $PROJECT_DIR" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string /tmp/drinkingproject.out.log" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string /tmp/drinkingproject.err.log" "$PLIST"

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Installed and started LaunchAgent: $PLIST"
