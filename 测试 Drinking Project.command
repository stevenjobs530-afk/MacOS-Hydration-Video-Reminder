#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"

cd "$PROJECT_DIR"
"$PROJECT_DIR/script/build_and_run.sh" --test
