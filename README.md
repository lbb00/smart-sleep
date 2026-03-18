# smart-sleep

Intelligent clamshell mode manager for macOS. Lightweight, zero-dependency shell script.

**[中文说明](./README.zh-CN.md)**

## The Problem

macOS requires a power adapter for clamshell mode (closed-lid with external display). Without power, closing the lid immediately puts your Mac to sleep — killing the external display signal.

Simply running `pmset disablesleep 1` fixes this, but creates a new problem: your Mac **never sleeps**, even when you unplug the display and throw it in your bag.

## The Solution

**smart-sleep** runs as a background daemon that:

1. **Detects external displays** — uses `ioreg` + lid state for fast, accurate detection
2. **Disables sleep** when an external display is connected (with or without power)
3. **Forces sleep** when the display is disconnected and the lid is closed
4. **Manages display timeout** — your display still sleeps after inactivity

All in a single shell script. No compilation. No dependencies. No App Store.

## Features

- Lid-aware display detection — correctly handles clamshell mode where macOS only reports external displays
- Auto sleep/wake management — smart state transitions based on display + lid state
- Force sleep on disconnect — Mac sleeps when display is unplugged and lid is closed
- Timer mode — temporarily disable sleep for a set duration
- Log rotation — automatic log management
- Configurable — polling interval and display sleep timeout via environment variables
- Clean install/uninstall — one-command setup and removal
- LaunchAgent integration — starts automatically on login
- Shell script, zero dependencies — no compilation, no App Store
- macOS Tahoe compatible
- CLI commands for status, timer, and settings
- Homebrew install support

## Installation

### Homebrew

```bash
brew tap lbb00/smart-sleep https://github.com/lbb00/smart-sleep
brew install smart-sleep
```

### Manual install

```bash
git clone https://github.com/lbb00/smart-sleep.git
cd smart-sleep
bash install.sh
```

The installer will:

- Copy `smart-sleep` to `~/.local/bin/`
- Configure passwordless `sudo` for `pmset` only
- Install and start a LaunchAgent (auto-start on login)

## Usage

```bash
# Check status
smart-sleep status

# Disable sleep for 1 hour (regardless of display state)
smart-sleep timer

# Cancel timer
smart-sleep timer-off

# Stop the daemon
smart-sleep stop

# View logs
cat /tmp/smart-sleep.log
```

> **Note:** Homebrew installs `smart-sleep` to your PATH. For manual install, add `~/.local/bin` to PATH or use the full path.

## Configuration

Modify settings on the fly without restarting the daemon:

```bash
# Set polling interval to 3 seconds
smart-sleep set interval 3

# Set display sleep timeout to 5 minutes
smart-sleep set displaysleep 5
```

Config is stored in `~/.config/smart-sleep/config` and picked up automatically.

### Environment Variables

Set initial defaults before installation:

| Variable                    | Default                | Description                      |
| --------------------------- | ---------------------- | -------------------------------- |
| `SMART_SLEEP_INTERVAL`      | `5`                    | Polling interval in seconds      |
| `SMART_SLEEP_DISPLAY_SLEEP` | `10`                   | Display sleep timeout in minutes |
| `SMART_SLEEP_LOG`           | `/tmp/smart-sleep.log` | Log file path                    |

## How It Works

```
┌──────────────────────────────────────┐
│           Every N seconds            │
│                                      │
│  ┌─ Has external display?            │
│  │   YES → disablesleep 1 (stay on)  │
│  │   NO  → Is lid closed?            │
│  │          YES → pmset sleepnow     │
│  │          NO  → stay awake         │
│  │                                   │
│  └─ Timer active? → override: stay   │
└──────────────────────────────────────┘
```

**Key insight:** When the lid is closed, macOS does not report the built-in display in `system_profiler`. So `display_count=1` with a closed lid means the external display is connected. The script combines lid state + display count for accurate detection.

## Behavior Matrix

| Scenario                                        | Behavior                                 |
| ----------------------------------------------- | ---------------------------------------- |
| Lid closed + external display (any power state) | ✅ Display works, Mac stays awake        |
| Lock screen + idle 10 min                       | ✅ Display turns off                     |
| Lid closed + display disconnected               | ✅ Mac sleeps within 5 seconds           |
| Lid open + no external display                  | ✅ Normal operation                      |
| Manual Apple → Sleep                            | ✅ Works normally                        |
| Sleep + reconnect display                       | ⚠️ Press external keyboard/mouse to wake |

## Uninstall

**Homebrew:**
```bash
brew uninstall smart-sleep
```

**Manual install:**
```bash
bash uninstall.sh
```

This will stop the daemon, remove all files, clean up sudoers, and restore default sleep settings.

## License

Unlicense (public domain) — <https://unlicense.org>
