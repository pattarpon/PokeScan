#!/bin/bash
# PokeScan Launcher - Double-click to start mGBA + PokeScan overlay

# Default paths (installer replaces __POKESCAN_DIR__)
DEFAULT_POKESCAN_DIR="__POKESCAN_DIR__"
CONFIG_FILE="$HOME/.config/pokescan/pokescan.conf"

# Default values
ROM_PATH=""
SAVE_SLOT="latest"
MGBA_APP=""
POKESCAN_DIR=""

# Load user config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Use default if not set in config
if [[ -z "$POKESCAN_DIR" ]]; then
    POKESCAN_DIR="$DEFAULT_POKESCAN_DIR"
fi

# Auto-detect mGBA if not specified
if [[ -z "$MGBA_APP" || ! -d "$MGBA_APP" ]]; then
    if [[ -d "/Applications/mGBA.app" ]]; then
        MGBA_APP="/Applications/mGBA.app"
    elif [[ -d "$POKESCAN_DIR/dev/mGBA.app" ]]; then
        MGBA_APP="$POKESCAN_DIR/dev/mGBA.app"
    fi
fi

# Verify ROM exists
if [[ -z "$ROM_PATH" || ! -f "$ROM_PATH" ]]; then
    osascript -e 'display alert "ROM Not Found" message "Please edit ~/.config/pokescan/pokescan.conf and set ROM_PATH to your Pokemon Emerald ROM location."'
    exit 1
fi

# Verify mGBA exists
if [[ ! -d "$MGBA_APP" ]]; then
    osascript -e 'display alert "mGBA Not Found" message "Please install mGBA from mgba.io or via: brew install --cask mgba"'
    exit 1
fi

# Find save state based on SAVE_SLOT setting
find_savestate() {
    local rom_dir=$(dirname "$ROM_PATH")
    local rom_base=$(basename "$ROM_PATH" .gba)

    if [[ "$SAVE_SLOT" == "none" || -z "$SAVE_SLOT" ]]; then
        echo ""
        return
    fi

    if [[ "$SAVE_SLOT" == "latest" ]]; then
        # Find most recent save state
        local latest=""
        local latest_time=0
        for ss in "$rom_dir/$rom_base".ss*; do
            if [[ -f "$ss" ]]; then
                local mtime=$(stat -f %m "$ss" 2>/dev/null || echo 0)
                if [[ $mtime -gt $latest_time ]]; then
                    latest_time=$mtime
                    latest="$ss"
                fi
            fi
        done
        echo "$latest"
    else
        # Use specific slot number
        local ss_file="$rom_dir/$rom_base.ss$SAVE_SLOT"
        if [[ -f "$ss_file" ]]; then
            echo "$ss_file"
        else
            echo ""
        fi
    fi
}

SAVESTATE=$(find_savestate)
LUA_SCRIPT="$POKESCAN_DIR/lua/pokescan_sender.lua"

# Find PokeScan - prefer installed app, fall back to building
POKESCAN_APP="/Applications/PokeScan.app"
if [[ -d "$POKESCAN_APP" ]]; then
    POKESCAN_BIN="$POKESCAN_APP/Contents/MacOS/PokeScan"
else
    POKESCAN_BIN="$POKESCAN_DIR/.build/release/PokeScan"
    if [[ ! -f "$POKESCAN_BIN" ]]; then
        cd "$POKESCAN_DIR"
        swift build -c release 2>/dev/null
    fi
fi

# Kill any existing instances
pkill -x mGBA 2>/dev/null
pkill -f "PokeScan$" 2>/dev/null
sleep 0.5

# Launch mGBA with ROM, script, and optionally save state
MGBA_ARGS=("$ROM_PATH" --script "$LUA_SCRIPT")
if [[ -n "$SAVESTATE" ]]; then
    MGBA_ARGS+=(-t "$SAVESTATE")
fi

"$MGBA_APP/Contents/MacOS/mGBA" "${MGBA_ARGS[@]}" &

# Wait for Lua server to start
sleep 2

# Launch PokeScan overlay
"$POKESCAN_BIN" &

exit 0
