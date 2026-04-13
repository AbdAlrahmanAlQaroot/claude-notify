#!/usr/bin/env bash
# ============================================================================
# claude-jump.sh — Focus the IDE window and jump to the terminal tab
#                  that last triggered a claude-notify notification.
#
# Companion to claude-notify.sh. Bind this to a global keyboard shortcut
# so you can instantly jump back to the terminal where Claude finished.
#
# License: MIT
# Repository: https://github.com/AbdAlrahmanAlQaroot/claude-notify
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CONFIG_FILE="${HOME}/.config/claude-notify/config.env"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-last-window"

# Delay (seconds) between focusing the window and sending keystrokes.
# Gives the window manager time to bring the window to the foreground.
KEYSTROKE_DELAY=0.2

# ---------------------------------------------------------------------------
# Load user config (if present)
# ---------------------------------------------------------------------------

CLAUDE_NOTIFY_IDE="${CLAUDE_NOTIFY_IDE:-auto}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Read saved state
# ---------------------------------------------------------------------------
# State file format: "WINDOW_ID TAB_NUM IDE_TYPE"
#   WINDOW_ID  — X11 window id (hex) on Linux, app name on macOS, HWND on WSL
#   TAB_NUM    — terminal tab number (1-based), or 0 if unknown
#   IDE_TYPE   — "intellij", "vscode", or "terminal"

if [[ ! -f "$STATE_FILE" ]]; then
    # Nothing to jump to — exit silently.
    exit 0
fi

read -r WINDOW_ID TAB_NUM IDE_TYPE < "$STATE_FILE" 2>/dev/null || exit 0

# Validate that we got all three fields and a real window ID.
if [[ -z "${WINDOW_ID:-}" || -z "${TAB_NUM:-}" || -z "${IDE_TYPE:-}" || "$WINDOW_ID" == "none" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------

detect_platform() {
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*)
            echo "macos"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

PLATFORM="$(detect_platform)"

# ---------------------------------------------------------------------------
# Focus window — platform-specific
# ---------------------------------------------------------------------------

focus_window() {
    case "$PLATFORM" in
        linux)
            if ! command -v wmctrl &>/dev/null; then
                echo "Error: wmctrl is required on Linux. Install with: sudo apt install wmctrl" >&2
                exit 0
            fi
            wmctrl -ia "$WINDOW_ID"
            ;;

        macos)
            # On macOS the WINDOW_ID doubles as the application name
            # (e.g. "IntelliJ IDEA", "Code", "Terminal").
            osascript -e "tell application \"$WINDOW_ID\" to activate"
            ;;

        wsl)
            # Use PowerShell to bring the window to the foreground via its HWND.
            powershell.exe -NoProfile -NonInteractive -Command "
                Add-Type @'
                    using System;
                    using System.Runtime.InteropServices;
                    public class Win32 {
                        [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);
                        [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                    }
'@
                \$hwnd = [IntPtr]::new($WINDOW_ID)
                [Win32]::ShowWindow(\$hwnd, 9)   # SW_RESTORE
                [Win32]::SetForegroundWindow(\$hwnd)
            " 2>/dev/null
            ;;

        *)
            echo "Warning: unsupported platform '$(uname -s)'" >&2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Send keystrokes — platform-specific helpers
# ---------------------------------------------------------------------------

send_keys_linux() {
    # Requires xdotool on Linux/X11.
    if ! command -v xdotool &>/dev/null; then
        echo "Error: xdotool is required on Linux. Install with: sudo apt install xdotool" >&2
        return 1
    fi
    # $@ = list of key names (xdotool syntax, e.g. "alt+F12", "alt+Right")
    for key in "$@"; do
        xdotool key --delay 50 "$key"
    done
}

send_keys_macos() {
    # Accepts pairs: modifier keycode (e.g. "option" "F12").
    # Uses osascript with System Events for keystroke simulation.
    for key in "$@"; do
        case "$key" in
            alt+F12)
                osascript -e 'tell application "System Events" to key code 111 using {option down}'
                ;;
            alt+Left)
                osascript -e 'tell application "System Events" to key code 123 using {option down}'
                ;;
            alt+Right)
                osascript -e 'tell application "System Events" to key code 124 using {option down}'
                ;;
            ctrl+grave)
                osascript -e 'tell application "System Events" to keystroke "`" using {control down}'
                ;;
            *)
                echo "Warning: unhandled key '$key' on macOS" >&2
                ;;
        esac
    done
}

send_keys_wsl() {
    # Use PowerShell SendKeys via COM automation.
    for key in "$@"; do
        local ps_key=""
        case "$key" in
            alt+F12)    ps_key='%{F12}' ;;
            alt+Left)   ps_key='%{LEFT}' ;;
            alt+Right)  ps_key='%{RIGHT}' ;;
            ctrl+grave) ps_key='^{~}' ;;   # Ctrl+` approximation
            *)
                echo "Warning: unhandled key '$key' on WSL" >&2
                continue
                ;;
        esac
        powershell.exe -NoProfile -NonInteractive -Command "
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait('$ps_key')
        " 2>/dev/null
    done
}

send_keys() {
    case "$PLATFORM" in
        linux) send_keys_linux "$@" ;;
        macos) send_keys_macos "$@" ;;
        wsl)   send_keys_wsl "$@" ;;
    esac
}

# ---------------------------------------------------------------------------
# IDE-specific terminal tab navigation
# ---------------------------------------------------------------------------

navigate_intellij() {
    local target_tab="${1:-1}"

    # Open the terminal tool window (Alt+F12).
    send_keys "alt+F12"
    sleep "$KEYSTROKE_DELAY"

    # Navigate to the first tab: press Alt+Left 5 times (enough to reach
    # tab 1 from any reasonable position).
    for _ in 1 2 3 4 5; do
        send_keys "alt+Left"
    done
    sleep "$KEYSTROKE_DELAY"

    # Now press Alt+Right (target_tab - 1) times to land on the correct tab.
    local moves=$(( target_tab - 1 ))
    for (( i = 0; i < moves; i++ )); do
        send_keys "alt+Right"
    done
}

navigate_vscode() {
    # Toggle the integrated terminal panel (Ctrl+`).
    send_keys "ctrl+grave"
    sleep "$KEYSTROKE_DELAY"

    # VS Code does not have a simple "go to terminal tab N" shortcut
    # out of the box. The user can bind workbench.action.terminal.focusAtIndexN.
    # We do our best: if TAB_NUM > 1, we could use the command palette,
    # but that is fragile. For now, just ensure the terminal panel is open.
    # Users who need multi-tab navigation can bind custom shortcuts.
    if [[ "$TAB_NUM" -gt 1 ]]; then
        : # Terminal panel is open; tab routing left to user keybindings.
    fi
}

navigate_terminal() {
    # Plain terminal — just focusing the window is sufficient.
    :
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# 1. Focus the target window.
focus_window

# 2. Small delay for the window manager to bring it to front.
sleep "$KEYSTROKE_DELAY"

# 3. Navigate to the correct terminal tab based on IDE type.
case "$IDE_TYPE" in
    intellij)  navigate_intellij "$TAB_NUM" ;;
    vscode)    navigate_vscode ;;
    terminal)  navigate_terminal ;;
    *)
        echo "Warning: unknown IDE type '$IDE_TYPE', skipping tab navigation." >&2
        ;;
esac

exit 0
