#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"

if pgrep -x "DrinkingProject" >/dev/null 2>&1; then
  osascript -e 'display dialog "该项目已在运行中。" with title "Drinking Project" buttons {"好的"} default button "好的"' >/dev/null 2>&1 || true
  exit 0
fi

cd "$PROJECT_DIR"
/bin/bash "$PROJECT_DIR/script/build_and_run.sh" run

osascript -e 'display notification "已开启喝水提醒。" with title "Drinking Project"' >/dev/null 2>&1 || true
