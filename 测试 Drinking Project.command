#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BINARY="$PROJECT_DIR/.build/release/DrinkingProject"

cd "$PROJECT_DIR"
mkdir -p .build/release

swiftc Sources/DrinkingProject/main.swift \
  -o "$BINARY" \
  -framework AppKit \
  -framework AVFoundation \
  -framework AVKit

pkill -x "DrinkingProject" >/dev/null 2>&1 || true
sleep 0.3

nohup "$BINARY" --resume-on-launch --test-on-launch >/tmp/drinkingproject.out.log 2>/tmp/drinkingproject.err.log &
disown
