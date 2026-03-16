#!/bin/bash
#
# smart-sleep uninstaller
#

INSTALL_DIR="$HOME/.local/bin"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
SCRIPT_NAME="smart-sleep.sh"
PLIST_NAME="com.smart-sleep.plist"
SUDOERS_FILE="/etc/sudoers.d/smart-sleep"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "  smart-sleep uninstaller"
echo "  ───────────────────────"
echo ""

# Stop service
if launchctl list 2>/dev/null | grep -q "com.smart-sleep"; then
    launchctl unload "$LAUNCH_AGENT_DIR/$PLIST_NAME" 2>/dev/null
    info "Service stopped"
fi

pkill -f "smart-sleep.sh" 2>/dev/null || true

# Restore sleep settings
if [ -f "/tmp/smart-sleep.state" ]; then
    source /tmp/smart-sleep.state
    sudo pmset -a disablesleep "${ORIG_DISABLESLEEP:-0}" displaysleep "${ORIG_DISPLAYSLEEP:-10}" 2>/dev/null
    rm -f /tmp/smart-sleep.state
    info "Sleep settings restored (disablesleep=${ORIG_DISABLESLEEP:-0}, displaysleep=${ORIG_DISPLAYSLEEP:-10})"
else
    sudo pmset -a disablesleep 0 2>/dev/null
    info "Sleep settings restored (disablesleep=0)"
fi

# Remove files
[ -f "$LAUNCH_AGENT_DIR/$PLIST_NAME" ] && rm "$LAUNCH_AGENT_DIR/$PLIST_NAME" && info "LaunchAgent removed"
[ -f "$INSTALL_DIR/$SCRIPT_NAME" ] && rm "$INSTALL_DIR/$SCRIPT_NAME" && info "Script removed"
[ -f "/tmp/smart-sleep.pid" ] && rm "/tmp/smart-sleep.pid"
[ -f "/tmp/smart-sleep.log" ] && rm "/tmp/smart-sleep.log" && info "Log removed"
[ -f "/tmp/smart-sleep.log.old" ] && rm "/tmp/smart-sleep.log.old"

# Remove sudoers
if [ -f "$SUDOERS_FILE" ]; then
    warn "Removing sudoers config (requires your password)..."
    sudo rm "$SUDOERS_FILE"
    info "Sudoers cleaned up"
fi

echo ""
info "Uninstall complete!"
echo ""
