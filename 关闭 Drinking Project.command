#!/bin/zsh
set -euo pipefail

LABEL="com.local.drinkingproject"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -f "$PLIST" ]]; then
  launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
fi

pkill -x "DrinkingProject" >/dev/null 2>&1 || true

osascript -e 'display notification "已关闭喝水提醒。" with title "Drinking Project"' >/dev/null 2>&1 || true
