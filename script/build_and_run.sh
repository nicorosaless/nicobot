#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Umi"
BUNDLE_ID="com.umi.dev"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
BACKEND_BINARY="$ROOT_DIR/backend/target/debug/umi-backend"
BACKEND_PORT="${PORT:-10201}"

log() {
  printf '\n==> %s\n' "$1"
}

wait_for_health() {
  local name="$1"
  local url="$2"
  local attempts="$3"

  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      printf '%s ready at %s\n' "$name" "$url"
      return 0
    fi
    sleep 1
  done

  printf 'ERROR: %s did not become ready at %s\n' "$name" "$url" >&2
  return 1
}

stop_existing() {
  log "Stopping old Umi processes"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "umi-backend" >/dev/null 2>&1 || true
}

build_backend() {
  log "Building Rust backend"
  cargo build --manifest-path "$ROOT_DIR/backend/Cargo.toml"
}

start_backend() {
  log "Starting Rust backend"
  "$BACKEND_BINARY" &
  wait_for_health "Umi backend" "http://127.0.0.1:$BACKEND_PORT/health" 10
}

build_frontend() {
  log "Building Swift frontend"
  xcrun swift build -c debug --package-path "$ROOT_DIR/frontend"
}

stage_app_bundle() {
  local build_binary

  build_binary="$(xcrun swift build -c debug --package-path "$ROOT_DIR/frontend" --show-bin-path)/$APP_NAME"

  log "Creating app bundle"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  sed \
    -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MIN_SYSTEM_VERSION/g" \
    "$ROOT_DIR/frontend/Info.plist" > "$INFO_PLIST"

  if [ -f "$ROOT_DIR/frontend/Sources/Resources/OmiIcon.icns" ]; then
    cp "$ROOT_DIR/frontend/Sources/Resources/OmiIcon.icns" "$APP_RESOURCES/OmiIcon.icns"
  fi

  codesign --force --sign - "$APP_BUNDLE" >/dev/null
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

prepare() {
  stop_existing
  build_backend
  start_backend
  build_frontend
  stage_app_bundle
}

case "$MODE" in
  run)
    prepare
    log "Opening Umi"
    open_app
    ;;
  --debug|debug)
    prepare
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    prepare
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    prepare
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    prepare
    log "Opening Umi"
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    curl -fsS "http://127.0.0.1:$BACKEND_PORT/health" >/dev/null
    printf 'Umi app and backend are running.\n'
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
