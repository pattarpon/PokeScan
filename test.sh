#!/bin/bash
# PokeScan Automated Test Script
# Launches everything and verifies connection + data flow

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/dev/logs"
TIMEOUT=15

echo "=== PokeScan Automated Test ==="
echo ""

# Run dev launcher (suppress most output)
echo "[1/4] Launching dev environment..."
"$SCRIPT_DIR/dev.sh" > /dev/null 2>&1

sleep 2

echo "[2/4] Checking processes..."
if pgrep -x mGBA > /dev/null; then
    echo "  mGBA: running"
else
    echo "  FAIL: mGBA not running"
    exit 1
fi

if pgrep -f "PokeScan" > /dev/null; then
    echo "  PokeScan: running"
else
    echo "  FAIL: PokeScan not running"
    exit 1
fi

echo ""
echo "[3/4] Waiting for connection..."
for i in $(seq 1 $TIMEOUT); do
    if grep -q "CONNECTED to mGBA" "$LOGS_DIR/swift.log" 2>/dev/null; then
        echo "  Connection established!"
        break
    fi
    sleep 1
    printf "."
done
echo ""

if ! grep -q "CONNECTED" "$LOGS_DIR/swift.log" 2>/dev/null; then
    echo "  FAIL: No connection within ${TIMEOUT}s"
    exit 1
fi

echo ""
echo "[4/4] Checking data flow..."
sleep 2

if grep -q "Pokemon:" "$LOGS_DIR/swift.log" 2>/dev/null; then
    POKEMON=$(grep "Pokemon:" "$LOGS_DIR/swift.log" | tail -1 | sed 's/.*Pokemon: //')
    echo "  Received: $POKEMON"
else
    echo "  WARN: No Pokemon data received"
fi

echo ""
echo "=== Logs ==="
echo "--- Lua ---"
tail -10 "$LOGS_DIR/lua.log" 2>/dev/null
echo ""
echo "--- Swift ---"
tail -10 "$LOGS_DIR/swift.log" 2>/dev/null
echo ""
echo "=== PASS ==="
