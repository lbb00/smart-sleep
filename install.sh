#!/bin/bash
#
# smart-sleep installer
#

set -e

INSTALL_DIR="$HOME/.local/bin"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
SCRIPT_NAME="smart-sleep"
PLIST_NAME="com.smart-sleep.plist"
SUDOERS_FILE="/etc/sudoers.d/smart-sleep"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${SMART_SLEEP_LOG:-/tmp/smart-sleep.log}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "  smart-sleep installer"
echo "  ─────────────────────"
echo ""

# Check macOS
[ "$(uname)" = "Darwin" ] || error "This tool only works on macOS"

# Stop existing instance
if pgrep -f "smart-sleep start" > /dev/null 2>&1; then
    warn "Stopping existing smart-sleep instance..."
    launchctl unload "$LAUNCH_AGENT_DIR/$PLIST_NAME" 2>/dev/null || true
    pkill -f "smart-sleep start" 2>/dev/null || true
    sleep 1
fi

# Install script
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/smart-sleep.sh" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
info "Installed $SCRIPT_NAME to $INSTALL_DIR/"

# Configure sudoers for passwordless pmset
if [ ! -f "$SUDOERS_FILE" ]; then
    warn "Configuring passwordless sudo for pmset (requires your password)..."
    echo "$(whoami) ALL = NOPASSWD : /usr/bin/pmset" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    info "Sudoers configured"
else
    info "Sudoers already configured"
fi

# Install LaunchAgent
mkdir -p "$LAUNCH_AGENT_DIR"
cat > "$LAUNCH_AGENT_DIR/$PLIST_NAME" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.smart-sleep</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${INSTALL_DIR}/${SCRIPT_NAME}</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>SMART_SLEEP_LOG</key>
        <string>${LOG_FILE}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
info "LaunchAgent installed"

# Start service
launchctl load "$LAUNCH_AGENT_DIR/$PLIST_NAME"
info "Service started"

# Add to PATH hint
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo ""
    warn "Add $INSTALL_DIR to your PATH for easy access:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
fi

echo ""
info "Installation complete!"
echo ""
echo "  Usage:"
echo "    smart-sleep status     # Check status"
echo "    smart-sleep timer      # Disable sleep for 1 hour"
echo "    smart-sleep timer-off  # Cancel timer"
echo "    smart-sleep stop       # Stop daemon"
echo ""
echo "  Logs: $LOG_FILE"
echo ""
