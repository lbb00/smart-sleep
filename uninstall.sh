#!/bin/bash
#
# smart-sleep uninstaller
#

INSTALL_DIR="$HOME/.local/bin"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
SCRIPT_NAME="smart-sleep"
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

pkill -f "smart-sleep start" 2>/dev/null || true

# Restore sleep settings
if [ -f "/tmp/smart-sleep.state" ]; then
    orig_disablesleep=$(grep '^ORIG_DISABLESLEEP=' /tmp/smart-sleep.state | cut -d= -f2 | tr -cd '0-9')
    orig_displaysleep=$(grep '^ORIG_DISPLAYSLEEP=' /tmp/smart-sleep.state | cut -d= -f2 | tr -cd '0-9')
    orig_disablesleep="${orig_disablesleep:-0}"
    orig_displaysleep="${orig_displaysleep:-10}"
    sudo pmset -a disablesleep "$orig_disablesleep" displaysleep "$orig_displaysleep" 2>/dev/null
    rm -f /tmp/smart-sleep.state
    info "Sleep settings restored (disablesleep=${orig_disablesleep}, displaysleep=${orig_displaysleep})"
else
    sudo pmset -a disablesleep 0 2>/dev/null
    info "Sleep settings restored (disablesleep=0)"
fi

# Remove files
plist_path="$LAUNCH_AGENT_DIR/$PLIST_NAME"
log_path="/tmp/smart-sleep.log"
if [ -f "$plist_path" ]; then
    log_path=$(/usr/libexec/PlistBuddy -c "Print :StandardOutPath" "$plist_path" 2>/dev/null || echo "/tmp/smart-sleep.log")
    rm "$plist_path" && info "LaunchAgent removed"
fi
[ -f "$INSTALL_DIR/$SCRIPT_NAME" ] && rm "$INSTALL_DIR/$SCRIPT_NAME" && info "Script removed"
[ -f "/tmp/smart-sleep.pid" ] && rm "/tmp/smart-sleep.pid"
[ -f "$log_path" ] && rm "$log_path" && info "Log removed"
[ -f "${log_path}.old" ] && rm "${log_path}.old"

# Remove sudoers
if [ -f "$SUDOERS_FILE" ]; then
    warn "Removing sudoers config (requires your password)..."
    sudo rm "$SUDOERS_FILE"
    info "Sudoers cleaned up"
fi

echo ""
info "Uninstall complete!"
echo ""
