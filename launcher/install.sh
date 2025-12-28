#!/bin/bash
# PokeScan Launcher Installer
# Creates the macOS app bundle and config directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POKESCAN_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="/Applications/PokeScan Launcher.app"
CONFIG_DIR="$HOME/.config/pokescan"

echo "=== PokeScan Launcher Installer ==="
echo ""

# Create config directory and copy default config if it doesn't exist
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/pokescan.conf" ]]; then
    cp "$SCRIPT_DIR/pokescan.conf" "$CONFIG_DIR/pokescan.conf"
    echo "Created config file: $CONFIG_DIR/pokescan.conf"
    echo "  -> Edit this file to set your ROM path and preferences"
else
    echo "Config file already exists: $CONFIG_DIR/pokescan.conf"
fi

# Remove old app if it exists
if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
    echo "Removed old launcher"
fi

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Create Info.plist
cat > "$APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.pokescan.launcher</string>
    <key>CFBundleName</key>
    <string>PokeScan Launcher</string>
    <key>CFBundleVersion</key>
    <string>1.2</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

# Copy launcher script and embed the PokeScan directory path
sed "s|__POKESCAN_DIR__|$POKESCAN_DIR|g" "$SCRIPT_DIR/launcher.sh" > "$APP_PATH/Contents/MacOS/launcher"
chmod +x "$APP_PATH/Contents/MacOS/launcher"

echo ""
echo "Installed: $APP_PATH"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.config/pokescan/pokescan.conf to set your ROM path"
echo "  2. Double-click 'PokeScan Launcher' in Applications to start"
echo ""
