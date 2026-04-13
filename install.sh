#!/usr/bin/env bash
# ============================================================================
# install.sh — Interactive installer for claude-notify
#
# License: MIT
# Repository: https://github.com/abdalrahmanshaban0/claude-notify
# ============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$HOME/.claude/hooks/claude-notify"
CONFIG_DIR="$HOME/.config/claude-notify"
CONFIG_FILE="$CONFIG_DIR/config.env"
SETTINGS_FILE="$HOME/.claude/settings.json"
VERSION="1.0.0"

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# ── Output helpers ───────────────────────────────────────────────────────────
info()    { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()      { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()     { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
step()    { printf "\n${BOLD}${CYAN}>> %s${NC}\n" "$*"; }

# ── Sound catalog ────────────────────────────────────────────────────────────
# Parallel arrays — index-aligned.
SOUND_FILES=("ninja-swoosh.wav" "ninja-shuriken-throw.wav" "electric-piano.wav")
SOUND_NAMES=("ninja-swoosh" "ninja-shuriken-throw" "electric-piano")
SOUND_DESCS=("Quick ninja swoosh" "Shuriken flying through the air" "Gentle electric piano note")

# ── OS detection ─────────────────────────────────────────────────────────────
detect_os() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS="macos"
    elif grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        OS="wsl"
    else
        OS="linux"
    fi
}

# ── Sound player detection ───────────────────────────────────────────────────
detect_sound_player() {
    case "$OS" in
        macos)
            if command -v afplay &>/dev/null; then
                SOUND_PLAYER="afplay"
            else
                err "afplay not found — this is unexpected on macOS."
                exit 1
            fi
            ;;
        wsl)
            if command -v powershell.exe &>/dev/null; then
                SOUND_PLAYER="powershell.exe"
            else
                warn "powershell.exe not found. Sound playback may not work in WSL."
                SOUND_PLAYER=""
            fi
            ;;
        linux)
            if command -v paplay &>/dev/null; then
                SOUND_PLAYER="paplay"
            elif command -v aplay &>/dev/null; then
                SOUND_PLAYER="aplay"
            else
                warn "Neither aplay nor paplay found. Sound playback will not work."
                warn "Install pulseaudio-utils (paplay) or alsa-utils (aplay)."
                SOUND_PLAYER=""
            fi
            ;;
    esac
}

# ── Play a sound file ───────────────────────────────────────────────────────
play_sound() {
    local file="$1"
    [[ -z "${SOUND_PLAYER:-}" ]] && { warn "No sound player available."; return 0; }
    case "$SOUND_PLAYER" in
        afplay)          afplay "$file" &>/dev/null & ;;
        paplay)          paplay "$file" &>/dev/null & ;;
        aplay)           aplay  "$file" &>/dev/null & ;;
        powershell.exe)
            local winpath
            winpath="$(wslpath -w "$file" 2>/dev/null || echo "$file")"
            powershell.exe -c "(New-Object System.Media.SoundPlayer '$winpath').PlaySync()" &>/dev/null &
            ;;
    esac
    # Wait briefly so the user hears it before the menu reprints
    wait $! 2>/dev/null || true
}

# ── Notification tool detection ──────────────────────────────────────────────
check_notify_tool() {
    case "$OS" in
        macos)
            if command -v osascript &>/dev/null; then
                ok "osascript available (desktop notifications)"
            else
                warn "osascript not found — desktop notifications will not work."
            fi
            ;;
        wsl)
            if command -v powershell.exe &>/dev/null; then
                ok "powershell.exe available (toast notifications)"
            else
                warn "powershell.exe not found — desktop notifications may not work."
            fi
            ;;
        linux)
            if command -v notify-send &>/dev/null; then
                ok "notify-send available (desktop notifications)"
            else
                warn "notify-send not found. Desktop notifications will not appear."
                warn "Install libnotify-bin to enable them."
            fi
            ;;
    esac
}

# ── IDE detection ────────────────────────────────────────────────────────────
detect_ide() {
    if pgrep -f "idea" &>/dev/null || pgrep -f "jetbrains" &>/dev/null; then
        DETECTED_IDE="intellij"
    elif pgrep -xf "code" &>/dev/null || pgrep -f "/Code " &>/dev/null || pgrep -f "\.vscode" &>/dev/null; then
        DETECTED_IDE="vscode"
    else
        DETECTED_IDE="auto"
    fi
}

# ── JSON patching helpers ────────────────────────────────────────────────────
# We try jq first, then python3, then sed. Each returns 0 on success.

HOOK_COMMAND="bash $HOME/.claude/hooks/claude-notify/claude-notify.sh"

has_notification_hook() {
    # Returns 0 if a Notification hook already exists in settings.json
    [[ -f "$SETTINGS_FILE" ]] || return 1
    grep -q '"Notification"' "$SETTINGS_FILE" 2>/dev/null
}

notification_hook_is_ours() {
    # Returns 0 if the existing Notification hook points to our script (exact path)
    [[ -f "$SETTINGS_FILE" ]] || return 1
    grep -q "claude-notify/claude-notify.sh" "$SETTINGS_FILE" 2>/dev/null
}

patch_settings_jq() {
    command -v jq &>/dev/null || return 1
    local tmp
    tmp="$(mktemp)"

    local hook_entry='[{"matcher":"","hooks":[{"type":"command","command":"'"$HOOK_COMMAND"'"}]}]'

    jq --argjson entry "$hook_entry" '
        .hooks = (.hooks // {}) |
        .hooks.Notification = $entry
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
}

patch_settings_python() {
    command -v python3 &>/dev/null || return 1
    python3 -c "
import json, sys, os

path = os.path.expanduser('$SETTINGS_FILE')
with open(path, 'r') as f:
    data = json.load(f)

if 'hooks' not in data:
    data['hooks'] = {}

data['hooks']['Notification'] = [
    {
        'matcher': '',
        'hooks': [
            {
                'type': 'command',
                'command': '$HOOK_COMMAND'
            }
        ]
    }
]

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
}

patch_settings_sed() {
    # Last resort — fragile, but handles the common case.
    local tmp
    tmp="$(mktemp)"
    local hook_block
    hook_block=$(printf '    "Notification": [\n      {\n        "matcher": "",\n        "hooks": [\n          {\n            "type": "command",\n            "command": "%s"\n          }\n        ]\n      }\n    ]' "$HOOK_COMMAND")

    if grep -q '"hooks"' "$SETTINGS_FILE"; then
        # Inject inside existing "hooks": { ... }
        # Find the line with "hooks": { and insert after it
        sed '/"hooks"[[:space:]]*:[[:space:]]*{/a\'"$(printf '\n%s,' "$hook_block")" "$SETTINGS_FILE" > "$tmp" \
            && mv "$tmp" "$SETTINGS_FILE"
    else
        # No hooks key at all — add before the final closing brace
        sed '$i\  ,"hooks": {\n'"$hook_block"'\n  }' "$SETTINGS_FILE" > "$tmp" \
            && mv "$tmp" "$SETTINGS_FILE"
    fi
}

remove_hook_jq() {
    command -v jq &>/dev/null || return 1
    local tmp
    tmp="$(mktemp)"
    jq 'if .hooks and .hooks.Notification then .hooks |= del(.Notification) else . end' \
        "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
}

remove_hook_python() {
    command -v python3 &>/dev/null || return 1
    python3 -c "
import json, os

path = os.path.expanduser('$SETTINGS_FILE')
with open(path, 'r') as f:
    data = json.load(f)

if 'hooks' in data and 'Notification' in data['hooks']:
    del data['hooks']['Notification']

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
}

remove_hook_sed() {
    warn "Removing hook via sed — please verify $SETTINGS_FILE manually."
    local tmp
    tmp="$(mktemp)"
    # Remove lines between "Notification" and the next "]" closing bracket
    sed '/"Notification"/,/^[[:space:]]*\]/d' "$SETTINGS_FILE" > "$tmp" \
        && mv "$tmp" "$SETTINGS_FILE"
}

# ── Uninstall ────────────────────────────────────────────────────────────────
do_uninstall() {
    step "Uninstalling claude-notify"

    if [[ -d "$HOOK_DIR" ]]; then
        rm -rf "$HOOK_DIR"
        ok "Removed $HOOK_DIR"
    else
        info "Hook directory not found (already removed?)."
    fi

    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        ok "Removed $CONFIG_DIR"
    else
        info "Config directory not found (already removed?)."
    fi

    # Remove /tmp state file
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/claude-notify-last-window" 2>/dev/null || true

    if [[ -f "$SETTINGS_FILE" ]] && notification_hook_is_ours; then
        if remove_hook_jq || remove_hook_python || remove_hook_sed; then
            ok "Removed Notification hook from $SETTINGS_FILE"
        else
            warn "Could not auto-remove hook. Please edit $SETTINGS_FILE manually."
        fi
    else
        info "No claude-notify hook found in settings.json."
    fi

    printf "\n${GREEN}${BOLD}claude-notify has been uninstalled.${NC}\n"
    exit 0
}

# ── Change sound ─────────────────────────────────────────────────────────────
do_change_sound() {
    local requested_sound="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "claude-notify is not installed (no config found at $CONFIG_FILE)."
        err "Run install.sh first."
        exit 1
    fi

    # Check if it matches a known sound name
    local found=""
    for i in "${!SOUND_NAMES[@]}"; do
        if [[ "${SOUND_NAMES[$i]}" == "$requested_sound" ]]; then
            found="${SOUND_FILES[$i]}"
            break
        fi
    done

    if [[ -n "$found" ]]; then
        local sound_path="$HOOK_DIR/sounds/$found"
        if [[ -f "$sound_path" ]]; then
            update_config_sound "$sound_path"
            ok "Sound changed to: $requested_sound ($sound_path)"
        else
            err "Sound file not found at $sound_path. Is claude-notify installed?"
            exit 1
        fi
    elif [[ -f "$requested_sound" ]]; then
        # User provided a file path
        update_config_sound "$requested_sound"
        ok "Sound changed to custom file: $requested_sound"
    else
        err "Unknown sound: $requested_sound"
        printf "Available sounds: %s\n" "${SOUND_NAMES[*]}"
        err "Or provide a path to a .wav file."
        exit 1
    fi
    exit 0
}

update_config_sound() {
    local new_sound="$1"
    if grep -q '^CLAUDE_NOTIFY_SOUND=' "$CONFIG_FILE" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        sed "s|^CLAUDE_NOTIFY_SOUND=.*|CLAUDE_NOTIFY_SOUND=\"$new_sound\"|" "$CONFIG_FILE" > "$tmp" \
            && mv "$tmp" "$CONFIG_FILE"
    else
        echo "CLAUDE_NOTIFY_SOUND=\"$new_sound\"" >> "$CONFIG_FILE"
    fi
}

# ── Interactive sound selection ──────────────────────────────────────────────
select_sound() {
    step "Sound selection"
    printf "\nAvailable notification sounds:\n"
    for i in "${!SOUND_NAMES[@]}"; do
        local num=$((i + 1))
        printf "  ${BOLD}%d)${NC} %-22s ${DIM}-- %s${NC}\n" "$num" "${SOUND_NAMES[$i]}" "${SOUND_DESCS[$i]}"
    done
    printf "  ${BOLD}c)${NC} %-22s ${DIM}-- Provide your own .wav file${NC}\n" "custom"
    printf "\n${DIM}  Type 'p1', 'p2', 'p3' to preview a sound before choosing.${NC}\n"

    while true; do
        printf "\n${BOLD}Select a sound [1-%d/c]:${NC} " "${#SOUND_NAMES[@]}"
        read -r choice

        # Replay: p1, p2, p3
        if [[ "$choice" =~ ^p([0-9]+)$ ]]; then
            local pidx=$(( ${BASH_REMATCH[1]} - 1 ))
            if (( pidx >= 0 && pidx < ${#SOUND_FILES[@]} )); then
                local preview_file="$SCRIPT_DIR/sounds/${SOUND_FILES[$pidx]}"
                if [[ -f "$preview_file" ]]; then
                    info "Playing ${SOUND_NAMES[$pidx]}..."
                    play_sound "$preview_file"
                else
                    warn "Sound file not found: $preview_file"
                fi
            else
                warn "Invalid preview number."
            fi
            continue
        fi

        # Custom path
        if [[ "$choice" == "c" || "$choice" == "C" ]]; then
            printf "${BOLD}Enter path to .wav file:${NC} "
            read -r custom_path
            custom_path="${custom_path/#\~/$HOME}"
            if [[ -f "$custom_path" ]]; then
                SELECTED_SOUND="$custom_path"
                SELECTED_SOUND_NAME="custom ($custom_path)"
                ok "Custom sound selected: $custom_path"
                break
            else
                err "File not found: $custom_path"
                continue
            fi
        fi

        # Number selection
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local sidx=$((choice - 1))
            if (( sidx >= 0 && sidx < ${#SOUND_FILES[@]} )); then
                SELECTED_SOUND="$HOOK_DIR/sounds/${SOUND_FILES[$sidx]}"
                SELECTED_SOUND_NAME="${SOUND_NAMES[$sidx]}"
                ok "Selected: ${SOUND_NAMES[$sidx]}"
                break
            fi
        fi

        warn "Invalid choice. Enter a number (1-${#SOUND_NAMES[@]}), 'c' for custom, or 'p1'-'p${#SOUND_NAMES[@]}' to replay."
    done

    # Test notification with the chosen sound
    step "Testing notification"
    printf "  Sending a test notification with ${BOLD}%s${NC}...\n" "$SELECTED_SOUND_NAME"
    local test_sound="$SELECTED_SOUND"
    # If the sound points to the hook dir (not yet fully installed), use source dir
    if [[ ! -f "$test_sound" ]]; then
        test_sound="$SCRIPT_DIR/sounds/$(basename "$test_sound")"
    fi
    CLAUDE_NOTIFY_SOUND="$test_sound" \
    CLAUDE_NOTIFICATION_MESSAGE="This is a test notification" \
    bash "$HOOK_DIR/claude-notify.sh" 2>/dev/null || true

    printf "\n${BOLD}Did the notification look and sound right? [Y/n]:${NC} "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        info "Let's pick a different sound."
        select_sound
    else
        ok "Notification test passed"
    fi
}

# ── Write config ─────────────────────────────────────────────────────────────
write_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<ENVEOF
# claude-notify configuration
# Generated by install.sh v${VERSION} on $(date -Iseconds 2>/dev/null || date)

# Notification sound — filename from sounds/ directory or absolute path
# Available: ninja-swoosh.wav, ninja-shuriken-throw.wav, electric-piano.wav
CLAUDE_NOTIFY_SOUND="${SELECTED_SOUND}"

# IDE for window detection and terminal navigation
# Options: auto, intellij, vscode, terminal
CLAUDE_NOTIFY_IDE="${DETECTED_IDE}"

# Desktop notification urgency (Linux only)
# Options: low, normal, critical
CLAUDE_NOTIFY_URGENCY="normal"

# Enable/disable notifications
CLAUDE_NOTIFY_ENABLED="true"

# Enable/disable sound
CLAUDE_NOTIFY_SOUND_ENABLED="true"
ENVEOF
    ok "Config written to $CONFIG_FILE"
}

# ── Patch settings.json ─────────────────────────────────────────────────────
patch_settings() {
    step "Configuring Claude Code hook"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        warn "$SETTINGS_FILE does not exist. Creating it."
        printf '{\n  "hooks": {}\n}\n' > "$SETTINGS_FILE"
    fi

    if has_notification_hook; then
        if notification_hook_is_ours; then
            ok "Notification hook already points to claude-notify. No changes needed."
            return
        else
            warn "A Notification hook already exists in $SETTINGS_FILE but is not claude-notify."
            printf "  Existing entry will be ${BOLD}replaced${NC}.\n"
            printf "${BOLD}Continue? [Y/n]:${NC} "
            read -r confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                warn "Skipped hook installation. You can add it manually later."
                return
            fi
        fi
    fi

    if patch_settings_jq; then
        ok "Patched $SETTINGS_FILE (via jq)"
    elif patch_settings_python; then
        ok "Patched $SETTINGS_FILE (via python3)"
    elif patch_settings_sed; then
        ok "Patched $SETTINGS_FILE (via sed — please verify the file)"
    else
        err "Could not patch $SETTINGS_FILE automatically."
        err "Please add the following to .hooks.Notification in $SETTINGS_FILE:"
        printf '  "Notification": [{"matcher":"","hooks":[{"type":"command","command":"%s"}]}]\n' "$HOOK_COMMAND"
    fi
}

# ── Copy files ───────────────────────────────────────────────────────────────
copy_files() {
    step "Installing files"

    mkdir -p "$HOOK_DIR/sounds"

    # Copy scripts
    for script in claude-notify.sh claude-jump.sh; do
        local src="$SCRIPT_DIR/$script"
        if [[ -f "$src" ]]; then
            cp "$src" "$HOOK_DIR/$script"
            chmod +x "$HOOK_DIR/$script"
            ok "Installed $HOOK_DIR/$script"
        else
            warn "$src not found in source directory — skipping."
        fi
    done

    # Copy sounds
    local count=0
    for sfile in "$SCRIPT_DIR/sounds/"*.wav; do
        [[ -f "$sfile" ]] || continue
        cp "$sfile" "$HOOK_DIR/sounds/"
        count=$((count + 1))
    done
    if (( count > 0 )); then
        ok "Installed $count sound file(s) into $HOOK_DIR/sounds/"
    else
        warn "No .wav files found in $SCRIPT_DIR/sounds/"
    fi
}

# ── Print summary ────────────────────────────────────────────────────────────
print_summary() {
    step "Installation complete"

    printf "\n"
    printf "  ${BOLD}Hook scripts:${NC}  %s/\n" "$HOOK_DIR"
    printf "  ${BOLD}Sounds:${NC}        %s/sounds/\n" "$HOOK_DIR"
    printf "  ${BOLD}Config:${NC}        %s\n" "$CONFIG_FILE"
    printf "  ${BOLD}Sound:${NC}         %s\n" "$SELECTED_SOUND_NAME"
    printf "  ${BOLD}OS:${NC}            %s\n" "$OS"
    printf "  ${BOLD}IDE:${NC}           %s\n" "$DETECTED_IDE"

    printf "\n${BOLD}To change settings:${NC}\n"
    printf "  Edit %s\n" "$CONFIG_FILE"
    printf "  Or run: ${CYAN}bash %s/install.sh --sound <name>${NC}\n" "$SCRIPT_DIR"

    printf "\n${BOLD}To set up the jump shortcut:${NC}\n"
    case "$OS" in
        linux)
            printf "  Bind a keyboard shortcut (e.g. Super+J) to:\n"
            printf "    ${CYAN}bash %s/claude-jump.sh${NC}\n" "$HOOK_DIR"
            printf "  In GNOME: Settings > Keyboard > Custom Shortcuts\n"
            printf "  In KDE:   System Settings > Shortcuts > Custom Shortcuts\n"
            ;;
        macos)
            printf "  Use Automator or a tool like Hammerspoon/skhd to bind a hotkey to:\n"
            printf "    ${CYAN}bash %s/claude-jump.sh${NC}\n" "$HOOK_DIR"
            ;;
        wsl)
            printf "  Bind a keyboard shortcut in Windows to run:\n"
            printf "    ${CYAN}wsl bash %s/claude-jump.sh${NC}\n" "$HOOK_DIR"
            ;;
    esac

    printf "\n${BOLD}To uninstall:${NC}\n"
    printf "  ${CYAN}bash %s/install.sh --uninstall${NC}\n" "$SCRIPT_DIR"
    printf "\n"
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash install.sh [OPTIONS]

Install claude-notify — sound & desktop notifications for Claude Code.

Options:
  --uninstall       Remove claude-notify (files, config, and hook)
  --sound NAME      Change the notification sound without reinstalling
                    NAME can be: ${SOUND_NAMES[*]}
                    Or a path to a .wav file
  --help, -h        Show this help message

Examples:
  bash install.sh                         # Interactive install
  bash install.sh --sound electric-piano  # Change sound
  bash install.sh --uninstall             # Remove everything
EOF
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall)
                detect_os
                do_uninstall
                ;;
            --sound)
                [[ -z "${2:-}" ]] && { err "--sound requires a value."; exit 1; }
                detect_os
                detect_sound_player
                do_change_sound "$2"
                ;;
            --help|-h)
                usage
                ;;
            *)
                err "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done

    # ── Banner ───────────────────────────────────────────────────────────────
    printf "\n${BOLD}${CYAN}"
    printf "  ╔══════════════════════════════════════════╗\n"
    printf "  ║       claude-notify installer v%s     ║\n" "$VERSION"
    printf "  ╚══════════════════════════════════════════╝${NC}\n"

    # ── Step 1: Prerequisites ────────────────────────────────────────────────
    step "Checking prerequisites"

    if [[ ! -d "$HOME/.claude" ]]; then
        err "Claude Code is not installed (~/.claude/ does not exist)."
        err "Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi
    ok "Claude Code directory found (~/.claude/)"

    detect_os
    ok "Detected OS: $OS"

    detect_sound_player
    if [[ -n "${SOUND_PLAYER:-}" ]]; then
        ok "Sound player: $SOUND_PLAYER"
    fi

    check_notify_tool
    detect_ide
    ok "Detected IDE: $DETECTED_IDE"

    # ── Step 2: Copy files ───────────────────────────────────────────────────
    copy_files

    # ── Step 3: Sound selection ──────────────────────────────────────────────
    select_sound

    # ── Step 4: Write config ─────────────────────────────────────────────────
    step "Writing configuration"
    write_config

    # ── Step 5: Patch settings.json ──────────────────────────────────────────
    patch_settings

    # ── Step 6: Summary ──────────────────────────────────────────────────────
    print_summary
}

main "$@"
