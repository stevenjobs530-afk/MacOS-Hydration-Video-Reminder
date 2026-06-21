#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
exec "$PROJECT_DIR/script/build_and_run.sh" run
