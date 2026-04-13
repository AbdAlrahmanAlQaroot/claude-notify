#!/usr/bin/env bash
# ============================================================================
# claude-jump.sh — Focus the IDE window that last triggered a claude-notify
#                  notification.
#
# Companion to claude-notify.sh. Bind this to a global keyboard shortcut
# so you can instantly jump back to the window where Claude is waiting.
#
# License: MIT
# Repository: https://github.com/AbdAlrahmanAlQaroot/claude-notify
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-last-window"

# ---------------------------------------------------------------------------
# Read saved state
# ---------------------------------------------------------------------------

if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

read -r WINDOW_ID TAB_NUM IDE_TYPE < "$STATE_FILE" 2>/dev/null || exit 0

if [[ -z "${WINDOW_ID:-}" || "$WINDOW_ID" == "none" ]]; then
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

case "$PLATFORM" in
    linux)
        if command -v wmctrl &>/dev/null; then
            wmctrl -ia "$WINDOW_ID"
        fi
        ;;
    macos)
        osascript -e "tell application \"$WINDOW_ID\" to activate" 2>/dev/null
        ;;
    wsl)
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
            [Win32]::ShowWindow(\$hwnd, 9)
            [Win32]::SetForegroundWindow(\$hwnd)
        " 2>/dev/null
        ;;
esac

exit 0
