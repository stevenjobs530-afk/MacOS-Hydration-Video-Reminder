#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BINARY="$PROJECT_DIR/.build/release/DrinkingProject"

if pgrep -x "DrinkingProject" >/dev/null 2>&1; then
  osascript -e 'display dialog "该项目已在运行中。" with title "Drinking Project" buttons {"好的"} default button "好的"' >/dev/null 2>&1 || true
  exit 0
fi

cd "$PROJECT_DIR"
mkdir -p .build/release

swiftc Sources/DrinkingProject/main.swift \
  -o "$BINARY" \
  -framework AppKit \
  -framework AVFoundation \
  -framework AVKit

nohup "$BINARY" --resume-on-launch >/tmp/drinkingproject.out.log 2>/tmp/drinkingproject.err.log &
disown

osascript -e 'display notification "已开启喝水提醒。" with title "Drinking Project"' >/dev/null 2>&1 || true
