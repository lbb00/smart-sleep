#!/bin/bash
#
# smart-sleep - Intelligent clamshell mode manager for macOS
#
# Automatically manages sleep behavior based on external display
# and lid state. Keeps your Mac awake in clamshell mode without
# requiring a power adapter.
#
# https://github.com/lbb00/smart-sleep
# License: Unlicense (public domain)

set -o pipefail

# ─── Configuration ───────────────────────────────────────────────
CONFIG_FILE="${HOME}/.config/smart-sleep/config"
LOG_FILE="${SMART_SLEEP_LOG:-/tmp/smart-sleep.log}"
LOG_MAX_SIZE=1048576  # 1MB max log size before rotation
STATE_FILE="/tmp/smart-sleep.state"
VERSION="1.0.0"

# Defaults (overridden by config file)
INTERVAL="${SMART_SLEEP_INTERVAL:-5}"
DISPLAY_SLEEP="${SMART_SLEEP_DISPLAY_SLEEP:-10}"

# Load config file if exists (called every loop for hot-reload)
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        local new_interval new_displaysleep
        new_interval=$(grep '^INTERVAL=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        new_displaysleep=$(grep '^DISPLAY_SLEEP=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)

        if [ -n "$new_interval" ] && [ "$new_interval" != "$INTERVAL" ]; then
            INTERVAL="$new_interval"
            log "Config reloaded: interval=${INTERVAL}s"
        fi
        if [ -n "$new_displaysleep" ] && [ "$new_displaysleep" != "$DISPLAY_SLEEP" ]; then
            DISPLAY_SLEEP="$new_displaysleep"
            apply_display_sleep
            log "Config reloaded: displaysleep=${DISPLAY_SLEEP}m"
        fi
    fi
}

# ─── State tracking ─────────────────────────────────────────────
LAST_STATE="unknown"
TIMER_END=0

# ─── Logging ─────────────────────────────────────────────────────
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$LOG_FILE"
    [ -t 1 ] && echo "$msg"

    # Rotate log if too large
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$LOG_MAX_SIZE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Log rotated" >> "$LOG_FILE"
        fi
    fi
}

# ─── Display detection ───────────────────────────────────────────
# Combines lid state + display count to correctly detect external displays.
# Bug fix: when lid is closed, macOS only reports external displays (not built-in),
# so display_count=1 means external is connected.
# Uses ioreg instead of system_profiler for faster detection (ms vs 1-2s).
has_external_display() {
    local display_count
    display_count=$(ioreg -r -c AppleDisplay 2>/dev/null | grep -c '"IODisplayConnectFlags"')

    if is_lid_closed; then
        # Lid closed: any display = external (built-in not reported)
        [ "$display_count" -ge 1 ]
    else
        # Lid open: more than 1 display = has external
        [ "$display_count" -gt 1 ]
    fi
}

is_lid_closed() {
    ioreg -r -k AppleClamshellState 2>/dev/null | grep -q '"AppleClamshellState" = Yes'
}

# ─── Sleep management ────────────────────────────────────────────
get_sleep_disabled() {
    pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2}'
}

ensure_awake() {
    if [ "$(get_sleep_disabled)" = "0" ]; then
        sudo pmset -a disablesleep 1
    fi
}

force_sleep() {
    log "Forcing sleep now"
    pmset sleepnow
}

apply_display_sleep() {
    sudo pmset -a displaysleep "$DISPLAY_SLEEP"
}

# ─── Timer feature ───────────────────────────────────────────────
# Disable sleep for a specified duration regardless of display state.
is_timer_active() {
    [ "$TIMER_END" -gt 0 ] && [ "$(date +%s)" -lt "$TIMER_END" ]
}

# Handle USR1 signal: extend timer by 1 hour
handle_timer_signal() {
    TIMER_END=$(( $(date +%s) + 3600 ))
    log "Timer set: sleep disabled for 1 hour (until $(date -r "$TIMER_END" '+%H:%M:%S'))"
}

# Handle USR2 signal: cancel timer
handle_cancel_signal() {
    TIMER_END=0
    log "Timer cancelled"
}

trap handle_timer_signal USR1
trap handle_cancel_signal USR2

# ─── Cleanup ─────────────────────────────────────────────────────
cleanup() {
    log "Shutting down, restoring sleep settings..."
    if [ -f "$STATE_FILE" ]; then
        local orig_disablesleep orig_displaysleep
        orig_disablesleep=$(grep '^ORIG_DISABLESLEEP=' "$STATE_FILE" | cut -d= -f2 | tr -cd '0-9')
        orig_displaysleep=$(grep '^ORIG_DISPLAYSLEEP=' "$STATE_FILE" | cut -d= -f2 | tr -cd '0-9')
        orig_disablesleep="${orig_disablesleep:-0}"
        orig_displaysleep="${orig_displaysleep:-10}"
        sudo pmset -a disablesleep "$orig_disablesleep" displaysleep "$orig_displaysleep"
        rm -f "$STATE_FILE"
        log "Restored: disablesleep=${orig_disablesleep}, displaysleep=${orig_displaysleep}"
    else
        sudo pmset -a disablesleep 0
    fi
    rm -f /tmp/smart-sleep.pid
    exit 0
}

trap cleanup INT TERM

# ─── Usage ───────────────────────────────────────────────────────
usage() {
    cat <<EOF
smart-sleep v${VERSION} - Intelligent clamshell mode manager for macOS

Usage: smart-sleep.sh [command]

Commands:
  start                  Start the daemon (default)
  stop                   Stop the running daemon
  install                Set up LaunchAgent and sudoers (run after Homebrew install)
  uninstall              Remove LaunchAgent and sudoers (run before brew uninstall)
  status                 Show current status
  set interval <secs>    Set polling interval (takes effect immediately)
  set displaysleep <min> Set display sleep timeout (takes effect immediately)
  timer                  Disable sleep for 1 hour (send USR1 to daemon)
  timer-off              Cancel active timer (send USR2 to daemon)
  version                Show version

Config file: ~/.config/smart-sleep/config
  Edit directly or use 'smart-sleep.sh set' commands.
  Changes are picked up automatically without restart.

EOF
    exit 0
}

get_pid() {
    local pid_file="/tmp/smart-sleep.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
        fi
    fi
}

cmd_install() {
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    local launch_agent_dir="$HOME/Library/LaunchAgents"
    local plist_name="com.smart-sleep.plist"
    local sudoers_file="/etc/sudoers.d/smart-sleep"

    [ "$(uname)" = "Darwin" ] || { echo "This tool only works on macOS"; exit 1; }

    # Stop existing instance
    if pgrep -f "smart-sleep.sh start" > /dev/null 2>&1; then
        launchctl unload "$launch_agent_dir/$plist_name" 2>/dev/null || true
        pkill -f "smart-sleep.sh start" 2>/dev/null || true
        sleep 1
    fi

    # Configure sudoers for passwordless pmset
    if [ ! -f "$sudoers_file" ]; then
        echo "Configuring passwordless sudo for pmset (requires your password)..."
        echo "$(whoami) ALL = NOPASSWD : /usr/bin/pmset" | sudo tee "$sudoers_file" > /dev/null
        sudo chmod 440 "$sudoers_file"
        echo "[✓] Sudoers configured"
    else
        echo "[✓] Sudoers already configured"
    fi

    # Install LaunchAgent
    mkdir -p "$launch_agent_dir"
    cat > "$launch_agent_dir/$plist_name" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.smart-sleep</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
</dict>
</plist>
PLIST
    echo "[✓] LaunchAgent installed"

    launchctl load "$launch_agent_dir/$plist_name"
    echo "[✓] Service started"
    echo ""
    echo "Usage: smart-sleep.sh status | timer | timer-off | stop"
    echo "Logs:  /tmp/smart-sleep.log"
}

cmd_uninstall() {
    local launch_agent_dir="$HOME/Library/LaunchAgents"
    local plist_name="com.smart-sleep.plist"
    local sudoers_file="/etc/sudoers.d/smart-sleep"

    # Stop service
    if launchctl list 2>/dev/null | grep -q "com.smart-sleep"; then
        launchctl unload "$launch_agent_dir/$plist_name" 2>/dev/null
        echo "[✓] Service stopped"
    fi
    pkill -f "smart-sleep.sh" 2>/dev/null || true

    # Restore sleep settings
    if [ -f "/tmp/smart-sleep.state" ]; then
        local orig_disablesleep orig_displaysleep
        orig_disablesleep=$(grep '^ORIG_DISABLESLEEP=' /tmp/smart-sleep.state | cut -d= -f2 | tr -cd '0-9')
        orig_displaysleep=$(grep '^ORIG_DISPLAYSLEEP=' /tmp/smart-sleep.state | cut -d= -f2 | tr -cd '0-9')
        orig_disablesleep="${orig_disablesleep:-0}"
        orig_displaysleep="${orig_displaysleep:-10}"
        sudo pmset -a disablesleep "$orig_disablesleep" displaysleep "$orig_displaysleep" 2>/dev/null
        rm -f /tmp/smart-sleep.state
        echo "[✓] Sleep settings restored"
    else
        sudo pmset -a disablesleep 0 2>/dev/null
        echo "[✓] Sleep settings restored"
    fi

    # Remove LaunchAgent and temp files
    [ -f "$launch_agent_dir/$plist_name" ] && rm "$launch_agent_dir/$plist_name" && echo "[✓] LaunchAgent removed"
    [ -f "/tmp/smart-sleep.pid" ] && rm "/tmp/smart-sleep.pid"
    [ -f "/tmp/smart-sleep.log" ] && rm "/tmp/smart-sleep.log"
    [ -f "/tmp/smart-sleep.log.old" ] && rm "/tmp/smart-sleep.log.old"

    # Remove sudoers
    if [ -f "$sudoers_file" ]; then
        echo "Removing sudoers config (requires your password)..."
        sudo rm "$sudoers_file"
        echo "[✓] Sudoers cleaned up"
    fi
    echo "[✓] Uninstall complete"
}

cmd_status() {
    local pid
    pid=$(get_pid)
    local sleep_disabled
    sleep_disabled=$(get_sleep_disabled)

    echo "smart-sleep v${VERSION}"
    echo "─────────────────────────"

    if [ -n "$pid" ]; then
        echo "Daemon:    running (PID $pid)"
    else
        echo "Daemon:    not running"
    fi

    echo "Sleep:     $([ "$sleep_disabled" = "1" ] && echo "disabled" || echo "enabled")"

    if has_external_display; then
        echo "Display:   external detected"
    else
        echo "Display:   built-in only"
    fi

    echo "Lid:       $(is_lid_closed && echo "closed" || echo "open")"

    # Read live config values
    local live_interval="$INTERVAL" live_displaysleep="$DISPLAY_SLEEP"
    if [ -f "$CONFIG_FILE" ]; then
        live_interval=$(grep '^INTERVAL=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
        live_displaysleep=$(grep '^DISPLAY_SLEEP=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    fi
    echo "Interval:  ${live_interval:-5}s"
    echo "DispSleep: ${live_displaysleep:-10}m"
    echo "Config:    $CONFIG_FILE"

    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "Recent log:"
        tail -5 "$LOG_FILE"
    fi
}

cmd_stop() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        echo "Stopped smart-sleep (PID $pid)"
    else
        echo "smart-sleep is not running"
    fi
}

cmd_timer() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        kill -USR1 "$pid" 2>/dev/null
        echo "Timer set: sleep disabled for 1 hour"
    else
        echo "smart-sleep is not running. Start it first."
        exit 1
    fi
}

cmd_timer_off() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        kill -USR2 "$pid" 2>/dev/null
        echo "Timer cancelled"
    else
        echo "smart-sleep is not running"
    fi
}

cmd_set() {
    local key="$1" value="$2"
    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "Usage: smart-sleep.sh set <interval|displaysleep> <value>"
        exit 1
    fi

    mkdir -p "$(dirname "$CONFIG_FILE")"

    case "$key" in
        interval)
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
                echo "Error: interval must be a positive integer (seconds)"
                exit 1
            fi
            if [ -f "$CONFIG_FILE" ] && grep -q '^INTERVAL=' "$CONFIG_FILE"; then
                sed -i '' "s/^INTERVAL=.*/INTERVAL=$value/" "$CONFIG_FILE"
            else
                echo "INTERVAL=$value" >> "$CONFIG_FILE"
            fi
            echo "Interval set to ${value}s (takes effect within current cycle)"
            ;;
        displaysleep)
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                echo "Error: displaysleep must be a non-negative integer (minutes)"
                exit 1
            fi
            if [ -f "$CONFIG_FILE" ] && grep -q '^DISPLAY_SLEEP=' "$CONFIG_FILE"; then
                sed -i '' "s/^DISPLAY_SLEEP=.*/DISPLAY_SLEEP=$value/" "$CONFIG_FILE"
            else
                echo "DISPLAY_SLEEP=$value" >> "$CONFIG_FILE"
            fi
            echo "Display sleep set to ${value}m (takes effect within current cycle)"
            ;;
        *)
            echo "Unknown setting: $key"
            echo "Available: interval, displaysleep"
            exit 1
            ;;
    esac
}

# ─── Main loop
# Save original pmset values for restoration
save_original_settings() {
    if [ ! -f "$STATE_FILE" ]; then
        local orig_displaysleep
        local orig_disablesleep
        orig_displaysleep=$(pmset -g 2>/dev/null | awk '/displaysleep/{print $2}')
        orig_disablesleep=$(pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2}')
        echo "ORIG_DISPLAYSLEEP=${orig_displaysleep:-10}" > "$STATE_FILE"
        echo "ORIG_DISABLESLEEP=${orig_disablesleep:-0}" >> "$STATE_FILE"
        log "Saved original settings: displaysleep=${orig_displaysleep}, disablesleep=${orig_disablesleep}"
    fi
}

cmd_start() {
    log "smart-sleep v${VERSION} started (interval=${INTERVAL}s, displaysleep=${DISPLAY_SLEEP}m)"

    # Save original settings before modifying
    save_original_settings

    # Initialize display sleep setting
    apply_display_sleep

    # Write PID for signal-based commands
    echo $$ > /tmp/smart-sleep.pid

    while true; do
        load_config
        ensure_awake

        # Timer override: if timer is active, keep awake regardless
        if is_timer_active; then
            if [ "$LAST_STATE" != "timer" ]; then
                log "Timer active, keeping awake"
                LAST_STATE="timer"
            fi
            sleep "$INTERVAL"
            continue
        elif [ "$LAST_STATE" = "timer" ]; then
            log "Timer expired, resuming normal detection"
            LAST_STATE="unknown"
        fi

        if has_external_display; then
            if [ "$LAST_STATE" != "display_connected" ]; then
                log "External display detected, sleep disabled"
                LAST_STATE="display_connected"
            fi
        else
            if is_lid_closed; then
                if [ "$LAST_STATE" != "sleeping" ]; then
                    log "No external display + lid closed, forcing sleep"
                    LAST_STATE="sleeping"
                    force_sleep
                fi
            else
                if [ "$LAST_STATE" != "no_external" ]; then
                    log "No external display, lid open, staying awake"
                    LAST_STATE="no_external"
                fi
            fi
        fi

        sleep "$INTERVAL"
    done
}

# ─── Entry point ─────────────────────────────────────────────────
case "${1:-start}" in
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    install)    cmd_install ;;
    uninstall)  cmd_uninstall ;;
    status)     cmd_status ;;
    set)        cmd_set "$2" "$3" ;;
    timer)      cmd_timer ;;
    timer-off)  cmd_timer_off ;;
    version)    echo "smart-sleep v${VERSION}" ;;
    help|-h|--help) usage ;;
    *)          echo "Unknown command: $1"; usage ;;
esac
