#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_DISPLAY_NAME="Drinking Project"
EXECUTABLE_NAME="DrinkingProject"
BUNDLE_ID="com.local.drinkingproject"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify|--test|--self-test-persistence|--media-privacy-check|--qa]" >&2
}

build_app() {
  BUILD_DIR="$ROOT_DIR/.build/release"
  BUILD_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
  mkdir -p "$BUILD_DIR"

  SOURCE_FILES=()
  while IFS= read -r -d '' source_file; do
    SOURCE_FILES+=("$source_file")
  done < <(find "$ROOT_DIR/Sources/DrinkingProject" -name '*.swift' ! -name '._*' -print0 | sort -z)

  swiftc -O "${SOURCE_FILES[@]}" \
    -o "$BUILD_BINARY" \
    -framework AppKit \
    -framework AVFoundation \
    -framework AVKit \
    -framework WebKit

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [[ -d "$ROOT_DIR/Sources/DrinkingProject/WebResources" ]]; then
    cp -R "$ROOT_DIR/Sources/DrinkingProject/WebResources" "$APP_RESOURCES/WebResources"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Drinking Project can pause browser or media playback when a hydration reminder appears.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>Drinking Project scans local reminder videos stored on your Mac or external drive.</string>
</dict>
</plist>
PLIST

  echo "Built app bundle: $APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args --project-dir "$ROOT_DIR" "$@"
}

check_js_syntax() {
  if command -v node >/dev/null 2>&1; then
    if [[ -f "$ROOT_DIR/Sources/DrinkingProject/WebResources/ReminderWeb/app.js" ]]; then
      node --check "$ROOT_DIR/Sources/DrinkingProject/WebResources/ReminderWeb/app.js"
    fi
    if [[ -f "$ROOT_DIR/Test /ReminderWeb/app.js" ]]; then
      node --check "$ROOT_DIR/Test /ReminderWeb/app.js"
    fi
    echo "WebResources JS syntax check passed"
  else
    echo "node is not available; skipped WebResources JS syntax check" >&2
  fi
}

check_media_privacy() {
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git checkout; skipped media privacy check" >&2
    return 0
  fi

  MEDIA_PATTERN='\.((mp4|mov|m4v|avi|mkv|webm|mp3|wav|aac|flac|jpg|jpeg|png|gif|heic|webp))$'
  TRACKED_MEDIA="$(git -C "$ROOT_DIR" ls-files | grep -Ei "$MEDIA_PATTERN" || true)"
  STAGED_MEDIA="$(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMRT | grep -Ei "$MEDIA_PATTERN" || true)"

  if [[ -n "$TRACKED_MEDIA$STAGED_MEDIA" ]]; then
    echo "Media privacy check failed. Do not commit private video, image, or audio files." >&2
    if [[ -n "$TRACKED_MEDIA" ]]; then
      echo "Tracked media:" >&2
      echo "$TRACKED_MEDIA" >&2
    fi
    if [[ -n "$STAGED_MEDIA" ]]; then
      echo "Staged media:" >&2
      echo "$STAGED_MEDIA" >&2
    fi
    return 1
  fi

  echo "Media privacy check passed"
}

run_persistence_self_test() {
  SELF_TEST_DIR="$(mktemp -d)"
  "$APP_BINARY" --project-dir "$ROOT_DIR" --app-support-dir "$SELF_TEST_DIR" --self-test-persistence
}

case "$MODE" in
  run|--run)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    open_app --resume-on-launch
    ;;
  --build-only|build-only)
    build_app
    ;;
  --debug|debug)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    lldb -- "$APP_BINARY" --project-dir "$ROOT_DIR"
    ;;
  --logs|logs)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    open_app --resume-on-launch
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    open_app --resume-on-launch
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    open_app --resume-on-launch
    sleep 2
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    echo "Verified running process: $EXECUTABLE_NAME"
    ;;
  --test|test)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    build_app
    open_app --resume-on-launch --test-on-launch
    ;;
  --self-test-persistence|self-test-persistence)
    build_app
    run_persistence_self_test
    ;;
  --media-privacy-check|media-privacy-check)
    check_media_privacy
    ;;
  --qa|qa)
    check_js_syntax
    check_media_privacy
    build_app
    plutil -lint "$INFO_PLIST"
    run_persistence_self_test
    ;;
  *)
    usage
    exit 2
    ;;
esac
