#!/usr/bin/env bash
# ============================================================================
# claude-notify.sh — Claude Code notification hook
#
# Plays a sound and sends a desktop notification whenever Claude Code is
# waiting for user input (permission prompt, question, etc.).
#
# Install as a Claude Code hook — it receives CLAUDE_NOTIFICATION_MESSAGE
# from the environment and always exits 0 so it never blocks the hook chain.
#
# Supports Linux (X11/Wayland), macOS, and WSL.
#
# License: MIT
# Repository: https://github.com/AbdAlrahmanAlQaroot/claude-notify
# ============================================================================

set -uo pipefail
# Note: set -e is intentionally omitted. This script is a hook and MUST
# always exit 0. Commands like grep legitimately return non-zero on no match.

# ---------------------------------------------------------------------------
# Resolve install directory (follow symlinks)
# ---------------------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" \
    || SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
INSTALL_DIR="$(dirname "$SCRIPT_PATH")"

# ---------------------------------------------------------------------------
# Load user config (non-fatal)
# ---------------------------------------------------------------------------
CONFIG_FILE="${HOME}/.config/claude-notify/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Config defaults
# ---------------------------------------------------------------------------
CLAUDE_NOTIFY_SOUND="${CLAUDE_NOTIFY_SOUND:-ninja-swoosh.wav}"
CLAUDE_NOTIFY_IDE="${CLAUDE_NOTIFY_IDE:-auto}"
CLAUDE_NOTIFY_URGENCY="${CLAUDE_NOTIFY_URGENCY:-normal}"
CLAUDE_NOTIFY_ENABLED="${CLAUDE_NOTIFY_ENABLED:-true}"
CLAUDE_NOTIFY_SOUND_ENABLED="${CLAUDE_NOTIFY_SOUND_ENABLED:-true}"

# Early exit if disabled
if [[ "$CLAUDE_NOTIFY_ENABLED" != "true" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

OS="$(detect_os)"

# ---------------------------------------------------------------------------
# Resolve sound file path
# ---------------------------------------------------------------------------
resolve_sound() {
    local sound="$1"

    # Absolute path — use directly
    if [[ "$sound" == /* ]]; then
        if [[ -f "$sound" ]]; then
            echo "$sound"
        fi
        return
    fi

    # Relative name — look in install dir's sounds/ folder
    local candidate="${INSTALL_DIR}/sounds/${sound}"
    if [[ -f "$candidate" ]]; then
        echo "$candidate"
    fi
}

SOUND_FILE="$(resolve_sound "$CLAUDE_NOTIFY_SOUND")"

# ---------------------------------------------------------------------------
# Derive project name from the working directory
# ---------------------------------------------------------------------------
PROJECT_NAME="$(basename "${PWD:-unknown}")"

# ---------------------------------------------------------------------------
# Notification body
# ---------------------------------------------------------------------------
NOTIFICATION_BODY="${CLAUDE_NOTIFICATION_MESSAGE:-Waiting for input}"

# ---------------------------------------------------------------------------
# IntelliJ tab detection
#
# Match the current PTY against IntelliJ terminal PTYs by looking for
# processes running bash-integration.bash on each PTY.
# ---------------------------------------------------------------------------
TAB_NUM=""

detect_intellij_tab() {
    # The hook runs in a child process without a TTY.
    # Walk up the process tree from PPID to find the Claude Code process,
    # which runs on a real PTY inside IntelliJ's terminal.
    local my_tty=""
    local pid="$PPID"
    for _ in 1 2 3 4 5; do
        my_tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ -n "$my_tty" && "$my_tty" != "?" ]] && break
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [[ -z "$pid" || "$pid" == "0" || "$pid" == "1" ]] && return 0
    done

    [[ -z "$my_tty" || "$my_tty" == "?" ]] && return 0

    # Match this PTY against IntelliJ terminal tabs by finding processes
    # running bash-integration.bash (IntelliJ injects this into each tab).
    local tab_index=0
    local found=false

    while IFS= read -r pid_dir; do
        local pid_tty
        pid_tty="$(ls -la "/proc/$(basename "$pid_dir")/fd/0" 2>/dev/null \
                   | awk '{print $NF}' | sed 's|^/dev/||')" || continue

        local cmdline
        cmdline="$(tr '\0' ' ' < "/proc/$(basename "$pid_dir")/cmdline" 2>/dev/null)" || continue

        if [[ "$cmdline" == *"bash-integration.bash"* ]]; then
            tab_index=$((tab_index + 1))
            if [[ "$pid_tty" == "$my_tty" ]]; then
                TAB_NUM="$tab_index"
                found=true
                break
            fi
        fi
    done < <(ls -d /proc/[0-9]* 2>/dev/null | sort -t/ -k3 -n)

    if ! $found; then
        TAB_NUM=""
    fi
}

# Only attempt tab detection on Linux (IntelliJ integrated terminal)
if [[ "$OS" == "linux" ]]; then
    detect_intellij_tab
fi

# ---------------------------------------------------------------------------
# Build notification title
# ---------------------------------------------------------------------------
NOTIFICATION_TITLE="Claude Code ${PROJECT_NAME}"
if [[ -n "$TAB_NUM" ]]; then
    NOTIFICATION_TITLE="Claude Code ${PROJECT_NAME} (Tab ${TAB_NUM})"
fi

# ---------------------------------------------------------------------------
# IDE window detection (Linux only — uses wmctrl)
# ---------------------------------------------------------------------------
WINDOW_ID=""

detect_window_id() {
    local mode="$1"

    # wmctrl is required for window detection
    if ! command -v wmctrl &>/dev/null; then
        return
    fi

    local wmctrl_list
    wmctrl_list="$(wmctrl -l 2>/dev/null)" || return

    case "$mode" in
        intellij)
            # Try project name + IDE keyword first
            WINDOW_ID="$(echo "$wmctrl_list" | grep -i "$PROJECT_NAME" \
                         | grep -iE "idea|jetbrains|intellij" \
                         | head -1 | awk '{print $1}')"
            # Fallback: project name with em-dash (IntelliJ title format: "project – file")
            if [[ -z "$WINDOW_ID" ]]; then
                WINDOW_ID="$(echo "$wmctrl_list" | grep -i "$PROJECT_NAME" \
                             | grep -E " – " \
                             | head -1 | awk '{print $1}')"
            fi
            # Fallback: just project name
            if [[ -z "$WINDOW_ID" ]]; then
                WINDOW_ID="$(echo "$wmctrl_list" | grep -i "$PROJECT_NAME" \
                             | head -1 | awk '{print $1}')"
            fi
            ;;
        vscode)
            WINDOW_ID="$(echo "$wmctrl_list" \
                         | grep -iE "Visual Studio Code|$PROJECT_NAME" \
                         | head -1 | awk '{print $1}')"
            ;;
        auto)
            # Try IntelliJ first
            detect_window_id "intellij"
            if [[ -n "$WINDOW_ID" ]]; then
                return
            fi
            # Then VS Code
            detect_window_id "vscode"
            ;;
        terminal)
            # Explicitly skip window detection
            ;;
    esac
}

if [[ "$OS" == "linux" ]]; then
    detect_window_id "$CLAUDE_NOTIFY_IDE"
fi

# ---------------------------------------------------------------------------
# Save window state for the jump script
# ---------------------------------------------------------------------------
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="${STATE_DIR}/claude-notify-last-window"

save_state() {
    # Determine IDE type for the jump script
    local ide_type="terminal"
    if [[ -n "$WINDOW_ID" ]]; then
        case "$CLAUDE_NOTIFY_IDE" in
            intellij) ide_type="intellij" ;;
            vscode)   ide_type="vscode" ;;
            auto)
                # Detect from window title
                local win_title
                win_title="$(wmctrl -l 2>/dev/null | grep "$WINDOW_ID" | cut -d' ' -f5-)" || true
                if echo "$win_title" | grep -qiE "idea|jetbrains|intellij"; then
                    ide_type="intellij"
                elif echo "$win_title" | grep -qiE "Visual Studio Code"; then
                    ide_type="vscode"
                fi
                ;;
        esac
    fi

    # Single-line format: WINDOW_ID TAB_NUM IDE_TYPE
    echo "${WINDOW_ID:-none} ${TAB_NUM:-0} ${ide_type}" > "$STATE_FILE" 2>/dev/null || true
}

save_state

# ---------------------------------------------------------------------------
# Play sound
# ---------------------------------------------------------------------------
play_sound() {
    local file="$1"
    [[ -z "$file" ]] && return
    [[ "$CLAUDE_NOTIFY_SOUND_ENABLED" != "true" ]] && return

    case "$OS" in
        linux)
            if command -v paplay &>/dev/null; then
                paplay "$file" &>/dev/null &
            elif command -v aplay &>/dev/null; then
                aplay -q "$file" &>/dev/null &
            fi
            ;;
        macos)
            afplay "$file" &>/dev/null &
            ;;
        wsl)
            # Convert Unix path to Windows path for PowerShell
            local win_path
            win_path="$(wslpath -w "$file" 2>/dev/null)" || return
            powershell.exe -NoProfile -NonInteractive -Command \
                "(New-Object Media.SoundPlayer '$win_path').PlaySync()" &>/dev/null &
            ;;
    esac
}

play_sound "$SOUND_FILE"

# ---------------------------------------------------------------------------
# Send desktop notification
# ---------------------------------------------------------------------------
send_notification() {
    case "$OS" in
        linux)
            if command -v notify-send &>/dev/null; then
                # Run in background subshell so --wait doesn't block the hook
                (
                    args=(
                        "--urgency=$CLAUDE_NOTIFY_URGENCY"
                        "--app-name=Claude Code"
                    )

                    # Add action button if we have a window to focus
                    if [[ -n "$WINDOW_ID" ]] && command -v wmctrl &>/dev/null; then
                        args+=("--action=focus=Go to terminal" "--wait")
                    fi

                    output="$(notify-send "${args[@]}" "$NOTIFICATION_TITLE" "$NOTIFICATION_BODY" 2>/dev/null)" || true

                    # If the user clicked the action, just focus the window.
                    # The correct terminal tab is already active since that's
                    # where the notification originated. Tab navigation is only
                    # needed for the claude-jump.sh keyboard shortcut.
                    if [[ "$output" == "focus" ]] && [[ -n "$WINDOW_ID" ]]; then
                        wmctrl -i -a "$WINDOW_ID" &>/dev/null || true
                    fi
                ) &
            fi
            ;;
        macos)
            osascript -e "
                display notification \"${NOTIFICATION_BODY//\"/\\\"}\" \
                    with title \"${NOTIFICATION_TITLE//\"/\\\"}\"
            " &>/dev/null || true
            ;;
        wsl)
            powershell.exe -NoProfile -NonInteractive -Command "
                [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
                \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                    [Windows.UI.Notifications.ToastTemplateType]::ToastText02
                )
                \$textNodes = \$template.GetElementsByTagName('text')
                \$textNodes.Item(0).AppendChild(\$template.CreateTextNode('${NOTIFICATION_TITLE//\'/\'\'}')) > \$null
                \$textNodes.Item(1).AppendChild(\$template.CreateTextNode('${NOTIFICATION_BODY//\'/\'\'}')) > \$null
                \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
                [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\$toast)
            " &>/dev/null || true
            ;;
    esac
}

send_notification

# ---------------------------------------------------------------------------
# Always exit successfully — never fail the hook
# ---------------------------------------------------------------------------
exit 0
