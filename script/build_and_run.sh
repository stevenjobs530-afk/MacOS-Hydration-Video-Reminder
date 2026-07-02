#!/usr/bin/env bash
set -euo pipefail

# Parse arguments. `--variant <name>` selects a build variant (default | claude) and can
# appear anywhere; the first remaining positional argument is the mode.
VARIANT="default"
MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      VARIANT="${2:-default}"
      shift 2
      ;;
    --variant=*)
      VARIANT="${1#*=}"
      shift
      ;;
    *)
      if [[ -z "$MODE" ]]; then
        MODE="$1"
      fi
      shift
      ;;
  esac
done
MODE="${MODE:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIN_SYSTEM_VERSION="13.0"
DIST_DIR="$ROOT_DIR/dist"

case "$VARIANT" in
  claude)
    APP_DISPLAY_NAME="Drinking Project"
    EXECUTABLE_NAME="DrinkingProjectClaude"
    BUNDLE_ID="com.local.drinkingproject.claude"
    RELEASE_DIR="$ROOT_DIR/Drinking Project 2 (Claude)/软甲本体"
    ;;
  default)
    APP_DISPLAY_NAME="Drinking Project"
    EXECUTABLE_NAME="DrinkingProject"
    BUNDLE_ID="com.local.drinkingproject"
    RELEASE_DIR="$ROOT_DIR/软甲本体"
    ;;
  *)
    echo "unknown variant: $VARIANT (expected: default | claude)" >&2
    exit 2
    ;;
esac

APP_BUNDLE="$RELEASE_DIR/$APP_DISPLAY_NAME.app"
LEGACY_CLAUDE_APP_BUNDLE="$RELEASE_DIR/Drinking Project 2 (Claude).app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Sources/DrinkingProject/Resources/AppIcon.icns"
APP_ICON_NAME="AppIcon.icns"
CLAUDE_LOGO_DIR="$ROOT_DIR/Drinking Project 2 (Claude)/Logo"

usage() {
  echo "usage: $0 [--variant default|claude] [run|--build-only|--debug|--logs|--telemetry|--verify|--test|--test-background-media|--self-test-persistence|--media-privacy-check|--qa]" >&2
}

sign_app() {
  if command -v codesign >/dev/null 2>&1; then
    find "$APP_BUNDLE" -name '._*' -type f -delete
    /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
    find "$APP_BUNDLE" -name '._*' -type f -delete
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    echo "Signed app bundle: $APP_BUNDLE"
  else
    echo "codesign is not available; skipped app bundle signing" >&2
  fi
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

  if [[ "$VARIANT" == "claude" && "$LEGACY_CLAUDE_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
    rm -rf "$LEGACY_CLAUDE_APP_BUNDLE"
    rm -f "$RELEASE_DIR/._Drinking Project 2 (Claude).app"
  fi
  rm -rf "$APP_BUNDLE"
  rm -f "$RELEASE_DIR/._$APP_DISPLAY_NAME.app"
  mkdir -p "$RELEASE_DIR"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [[ -d "$ROOT_DIR/Sources/DrinkingProject/WebResources" ]]; then
    cp -R "$ROOT_DIR/Sources/DrinkingProject/WebResources" "$APP_RESOURCES/WebResources"
  fi

  copy_app_icon

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
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
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

  sign_app
  rm -f "$RELEASE_DIR/._$APP_DISPLAY_NAME.app"
  echo "Built app bundle: $APP_BUNDLE"
}

copy_app_icon() {
  local icon_source="$APP_ICON_SOURCE"
  if [[ "$VARIANT" == "claude" ]]; then
    local logo_source
    logo_source="$(find "$CLAUDE_LOGO_DIR" -maxdepth 1 -type f ! -name '._*' \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tif' -o -iname '*.tiff' \) -print -quit 2>/dev/null || true)"
    if [[ -n "$logo_source" ]]; then
      icon_source="$(build_icns_from_image "$logo_source")"
    fi
  fi

  if [[ -f "$icon_source" ]]; then
    cp "$icon_source" "$APP_RESOURCES/$APP_ICON_NAME"
  fi
}

build_icns_from_image() {
  local source_image="$1"
  local icon_root="$ROOT_DIR/.build/generated-icons/$VARIANT"
  local iconset="$icon_root/AppIcon.iconset"
  local square_source="$icon_root/source-square.png"
  local output_icon="$icon_root/AppIcon.icns"

  mkdir -p "$icon_root"
  rm -rf "$iconset"
  mkdir -p "$iconset"

  local width height side
  width="$(/usr/bin/sips -g pixelWidth "$source_image" 2>/dev/null | awk '/pixelWidth/ { print $2; exit }')"
  height="$(/usr/bin/sips -g pixelHeight "$source_image" 2>/dev/null | awk '/pixelHeight/ { print $2; exit }')"
  if [[ -z "$width" || -z "$height" ]]; then
    echo "$APP_ICON_SOURCE"
    return
  fi
  if (( width < height )); then
    side="$width"
  else
    side="$height"
  fi

  /usr/bin/sips --cropToHeightWidth "$side" "$side" "$source_image" --out "$square_source" >/dev/null
  /usr/bin/sips -z 16 16 "$square_source" --out "$iconset/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$square_source" --out "$iconset/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$square_source" --out "$iconset/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$square_source" --out "$iconset/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$square_source" --out "$iconset/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$square_source" --out "$iconset/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$square_source" --out "$iconset/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$square_source" --out "$iconset/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$square_source" --out "$iconset/icon_512x512.png" >/dev/null
  /usr/bin/sips -z 1024 1024 "$square_source" --out "$iconset/icon_512x512@2x.png" >/dev/null
  /usr/bin/iconutil -c icns "$iconset" -o "$output_icon"
  echo "$output_icon"
}

app_needs_build() {
  if [[ ! -d "$APP_BUNDLE" || ! -x "$APP_BINARY" || ! -f "$INFO_PLIST" ]]; then
    return 0
  fi

  if find "$ROOT_DIR/Sources/DrinkingProject" "$ROOT_DIR/script/build_and_run.sh" \
    ! -name '._*' -type f -newer "$APP_BINARY" -print -quit | grep -q .; then
    return 0
  fi

  return 1
}

ensure_app_built() {
  if app_needs_build; then
    build_app
  else
    echo "Using existing app bundle: $APP_BUNDLE"
  fi
}

open_app() {
  if [[ "$VARIANT" != "default" ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --args --project-dir "$ROOT_DIR" --variant "$VARIANT" "$@"
  else
    /usr/bin/open -n "$APP_BUNDLE" --args --project-dir "$ROOT_DIR" "$@"
  fi
}

check_js_syntax() {
  if command -v node >/dev/null 2>&1; then
    if [[ -f "$ROOT_DIR/Sources/DrinkingProject/WebResources/ReminderWeb/app.js" ]]; then
      node --check "$ROOT_DIR/Sources/DrinkingProject/WebResources/ReminderWeb/app.js"
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

  MEDIA_PATTERN='\.((mp4|mov|m4v|avi|mkv|webm|mp3|wav|aac|flac|jpg|jpeg|png|gif|heic|webp|icns|svg))$'

  is_allowed_app_icon_resource() {
    case "$1" in
      Sources/DrinkingProject/Resources/AppIcon.icns|Sources/DrinkingProject/Resources/AppIcon.svg)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  filter_private_media() {
    local path
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if is_allowed_app_icon_resource "$path"; then
        continue
      fi
      printf '%s\n' "$path"
    done
  }

  TRACKED_MEDIA="$(git -C "$ROOT_DIR" ls-files | grep -Ei "$MEDIA_PATTERN" | filter_private_media || true)"
  STAGED_MEDIA="$(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMRT | grep -Ei "$MEDIA_PATTERN" | filter_private_media || true)"

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

run_background_media_test() {
  "$APP_BINARY" --project-dir "$ROOT_DIR" --variant "$VARIANT" --test-background-media
}

case "$MODE" in
  run|--run)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    ensure_app_built
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
    ensure_app_built
    open_app --resume-on-launch
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    ensure_app_built
    open_app --resume-on-launch
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    ensure_app_built
    open_app --resume-on-launch
    sleep 2
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    echo "Verified running process: $EXECUTABLE_NAME"
    ;;
  --test|test)
    pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
    ensure_app_built
    open_app --resume-on-launch --test-on-launch
    ;;
  --test-background-media|test-background-media)
    ensure_app_built
    run_background_media_test
    ;;
  --self-test-persistence|self-test-persistence)
    ensure_app_built
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
