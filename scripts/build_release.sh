#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

mkdir -p .build/release
swiftc Sources/DrinkingProject/main.swift \
  -o .build/release/DrinkingProject \
  -framework AppKit \
  -framework AVFoundation \
  -framework AVKit

echo "Built: $PROJECT_DIR/.build/release/DrinkingProject"
