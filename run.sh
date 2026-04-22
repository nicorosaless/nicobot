#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_PID=""
HERMES_PID=""

cleanup() {
  if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi
  "$ROOT_DIR/.venv/bin/hermes" gateway stop 2>/dev/null || true
}
trap cleanup EXIT

log() {
  printf '\n==> %s\n' "$1"
}

wait_for_health() {
  local name="$1"
  local url="$2"
  local attempts="$3"
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      printf '%s is ready: %s\n' "$name" "$url"
      return 0
    fi
    sleep 1
  done
  printf 'ERROR: %s did not become healthy at %s\n' "$name" "$url" >&2
  return 1
}

if [ -f "$ROOT_DIR/backend/.env" ]; then
  log "Loading backend/.env"
  set -a
  source "$ROOT_DIR/backend/.env"
  set +a
fi

BACKEND_PORT="${PORT:-10201}"
HERMES_PORT="${HERMES_PORT:-8642}"
APP_NAME="${UMI_APP_NAME:-Umi Dev}"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
HERMES_API_URL="${HERMES_API_URL:-https://api.fireworks.ai/inference/v1}"
HERMES_MODEL="${HERMES_MODEL:-accounts/fireworks/routers/kimi-k2p5-turbo}"
HERMES_API_KEY="${HERMES_API_KEY:-}"
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT="$HERMES_PORT"
API_SERVER_MODEL_NAME=hermes-agent
export API_SERVER_ENABLED API_SERVER_HOST API_SERVER_PORT API_SERVER_MODEL_NAME

log "Stopping old local services"
pkill -x "Umi" 2>/dev/null || true
pkill -x "umi-backend" 2>/dev/null || true
"$ROOT_DIR/.venv/bin/hermes" gateway stop 2>/dev/null || true
pkill -f "$ROOT_DIR/.venv/bin/hermes gateway run" 2>/dev/null || true
rm -f "$HOME/.hermes/gateway.pid" 2>/dev/null || true
sleep 1

log "Preparing Python environment"
PYTHON_BIN="${HERMES_PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="python3.11"
  else
    PYTHON_BIN="python3"
  fi
fi

if [ ! -d "$ROOT_DIR/.venv" ]; then
  "$PYTHON_BIN" -m venv "$ROOT_DIR/.venv"
fi

if ! [ -x "$ROOT_DIR/.venv/bin/hermes" ]; then
  log "Installing Hermes Agent from GitHub"
  "$ROOT_DIR/.venv/bin/python" -m pip install --upgrade pip >/dev/null
  "$ROOT_DIR/.venv/bin/python" -m pip install "git+https://github.com/NousResearch/hermes-agent.git"
fi

mkdir -p "$HOME/.hermes"
if [ ! -f "$HOME/.hermes/config.yaml" ]; then
  log "Writing Hermes config"
  cat > "$HOME/.hermes/config.yaml" <<EOF
model:
  provider: "custom"
  api_key: "$HERMES_API_KEY"
  base_url: "$HERMES_API_URL"
  default: "$HERMES_MODEL"
EOF
else
  log "Keeping existing Hermes config"
fi

log "Starting Hermes Agent"
"$ROOT_DIR/.venv/bin/hermes" gateway run --replace &
HERMES_PID=$!
wait_for_health "Hermes Agent" "http://127.0.0.1:$HERMES_PORT/health" 15

log "Building Rust backend"
cargo build --release --manifest-path "$ROOT_DIR/backend/Cargo.toml"

log "Starting Rust backend"
"$ROOT_DIR/backend/target/release/umi-backend" &
BACKEND_PID=$!
wait_for_health "Umi backend" "http://127.0.0.1:$BACKEND_PORT/health" 10

log "Building Swift frontend"
xcrun swift build -c debug --package-path "$ROOT_DIR/frontend"

log "Creating app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/frontend/.build/debug/Umi" "$APP_BUNDLE/Contents/MacOS/Umi"
sed \
  -e "s/\$(EXECUTABLE_NAME)/Umi/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.umi.dev/g" \
  -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
  -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" \
  "$ROOT_DIR/frontend/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$ROOT_DIR/frontend/Sources/Resources/OmiIcon.icns" ]; then
  cp "$ROOT_DIR/frontend/Sources/Resources/OmiIcon.icns" "$APP_BUNDLE/Contents/Resources/OmiIcon.icns"
fi

log "Code signing"
codesign --force --sign - "$APP_BUNDLE"

log "Opening Umi"
open "$APP_BUNDLE"

log "Services running"
printf 'Hermes Agent: http://127.0.0.1:%s (PID %s)\n' "$HERMES_PORT" "$HERMES_PID"
printf 'Umi backend:  http://127.0.0.1:%s (PID %s)\n' "$BACKEND_PORT" "$BACKEND_PID"
wait "$BACKEND_PID"
