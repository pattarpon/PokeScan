#!/bin/bash
# PokeScan Development Launcher
# One-click launch for mGBA + ROM + Lua script + save state + PokeScan app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$SCRIPT_DIR/dev"
LOGS_DIR="$DEV_DIR/logs"
LUA_SCRIPT="$SCRIPT_DIR/lua/pokescan_sender.lua"

ROM="$DEV_DIR/emerald.gba"
SAVESTATE="$DEV_DIR/emerald.ss0"
MGBA_APP="$DEV_DIR/mGBA.app"

echo "=== PokeScan Dev Launcher ==="

# Kill existing processes
echo "Stopping existing processes..."
pkill -x mGBA 2>/dev/null || true
pkill -f PokeScan 2>/dev/null || true
sleep 0.5

# Clear old logs and create log directory
mkdir -p "$LOGS_DIR"
> "$LOGS_DIR/lua.log"
> "$LOGS_DIR/swift.log"
rm -f "$LOGS_DIR/port"

export POKESCAN_LOG="$LOGS_DIR/swift.log"

# Build PokeScan
echo "Building PokeScan..."
cd "$SCRIPT_DIR"
swift build --product PokeScan 2>&1 | tail -5

# Copy the built app to dev folder for convenience
BUILD_PATH=$(swift build --product PokeScan --show-bin-path)
cp -f "$BUILD_PATH/PokeScan" "$DEV_DIR/PokeScan" 2>/dev/null || true

# Also copy resources bundle if it exists
if [ -d "$BUILD_PATH/PokeScan_PokeScan.bundle" ]; then
    cp -Rf "$BUILD_PATH/PokeScan_PokeScan.bundle" "$DEV_DIR/" 2>/dev/null || true
fi

# Launch mGBA first (it's the server)
echo "Starting mGBA with Emerald + battle save state..."
"$MGBA_APP/Contents/MacOS/mGBA" "$ROM" --script "$LUA_SCRIPT" -t "$SAVESTATE" &
MGBA_PID=$!

# Wait for Lua to write the port file
echo "Waiting for Lua server to start..."
for i in {1..10}; do
    if [ -f "$LOGS_DIR/port" ]; then
        break
    fi
    sleep 0.5
done

if [ ! -f "$LOGS_DIR/port" ]; then
    echo "Warning: Port file not created, using default port 9876"
fi

# Now launch PokeScan (it's the client)
echo "Starting PokeScan..."
export POKESCAN_PORT_FILE="$LOGS_DIR/port"
"$BUILD_PATH/PokeScan" >> "$LOGS_DIR/swift.log" 2>&1 &
POKESCAN_PID=$!

echo ""
echo "=== Ready! ==="
echo "PokeScan PID: $POKESCAN_PID"
echo "mGBA PID: $MGBA_PID"
echo ""
echo "Logs:"
echo "  Lua:   $LOGS_DIR/lua.log"
echo "  Swift: $LOGS_DIR/swift.log"
echo ""
echo "To stop: pkill mGBA; pkill PokeScan"
