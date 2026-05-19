#!/bin/zsh
set -euo pipefail

LABEL="com.local.drinkingproject"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Removed LaunchAgent: $PLIST"
