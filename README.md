# claude-notify

Desktop notifications with sound for Claude Code permission prompts.

When [Claude Code](https://docs.anthropic.com/en/docs/claude-code) needs your approval -- a permission prompt, a question, or any pause for input -- claude-notify plays an audio cue and sends a desktop notification so you never miss it, even when the terminal is buried behind other windows.

It integrates with Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) via the `Notification` event.

## Features

- Desktop notification with a "Go to terminal" action button (Linux)
- Configurable notification sounds (3 bundled: ninja-swoosh, ninja-shuriken-throw, electric-piano)
- Custom sound support -- use any `.wav` file
- Jump-to-terminal keyboard shortcut helper (`claude-jump.sh`)
- Cross-platform: Linux, macOS, WSL
- IDE-aware: IntelliJ IDEA, VS Code, plain terminal
- Zero dependencies beyond standard OS tools

## Quick Install

```bash
git clone https://github.com/AbdAlrahmanAlQaroot/claude-notify.git
cd claude-notify
bash install.sh
```

The installer registers `claude-notify.sh` as a `Notification` hook in your Claude Code settings, copies a default config file, and prints next steps.

## Bundled Sounds

| File | Style | License |
|------|-------|---------|
| `ninja-swoosh.wav` | Quick swoosh | Sampling Plus 1.0 |
| `ninja-shuriken-throw.wav` | Shuriken in flight | Public Domain |
| `electric-piano.wav` | Gentle piano note | GPL (sound-icons) |

## Configuration

All settings live in `~/.config/claude-notify/config.env`, created automatically by the installer.

```bash
# Notification sound -- filename from sounds/ or an absolute path to any .wav
CLAUDE_NOTIFY_SOUND="ninja-swoosh.wav"

# IDE for window detection and terminal navigation
# Options: auto, intellij, vscode, terminal
# "auto" tries IntelliJ first, then VS Code, then plain terminal
CLAUDE_NOTIFY_IDE="auto"

# Desktop notification urgency (Linux only)
# Options: low, normal, critical
CLAUDE_NOTIFY_URGENCY="normal"

# Enable/disable notifications entirely
# Set to "false" to temporarily silence everything
CLAUDE_NOTIFY_ENABLED="true"

# Enable/disable sound independently of the visual notification
# Set to "false" to show the notification without playing a sound
CLAUDE_NOTIFY_SOUND_ENABLED="true"
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_NOTIFY_SOUND` | `ninja-swoosh.wav` | Sound file name (from `sounds/`) or absolute path |
| `CLAUDE_NOTIFY_IDE` | `auto` | IDE to detect: `auto`, `intellij`, `vscode`, `terminal` |
| `CLAUDE_NOTIFY_URGENCY` | `normal` | Notification urgency on Linux: `low`, `normal`, `critical` |
| `CLAUDE_NOTIFY_ENABLED` | `true` | Master switch -- set `false` to disable |
| `CLAUDE_NOTIFY_SOUND_ENABLED` | `true` | Set `false` for silent (visual-only) notifications |

## Jump to Terminal

`claude-jump.sh` is a companion script that reads the last notification state and focuses the correct IDE window (and, for IntelliJ, the correct terminal tab). Bind it to a global keyboard shortcut so you can jump straight to the waiting prompt from anywhere.

### Linux

Using your desktop environment's keyboard shortcut settings (GNOME, KDE, etc.), add a custom shortcut that runs:

```bash
/path/to/claude-notify/claude-jump.sh
```

Alternatively, with `xbindkeys`, add to `~/.xbindkeysrc`:

```
"/path/to/claude-notify/claude-jump.sh"
    Mod4 + grave
```

Then reload: `xbindkeys --poll-rc`.

### macOS

With [skhd](https://github.com/koekeishiya/skhd), add to `~/.skhdrc`:

```
cmd - escape : /path/to/claude-notify/claude-jump.sh
```

Or create an Automator Quick Action that runs the script and assign it a shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services.

## Custom Sounds

You can use any `.wav` file as the notification sound.

**Option A** -- Drop the file into the `sounds/` directory and reference it by name:

```bash
CLAUDE_NOTIFY_SOUND="my-custom-alert.wav"
```

**Option B** -- Use an absolute path to a file stored anywhere:

```bash
CLAUDE_NOTIFY_SOUND="/home/user/sounds/alert.wav"
```

## Platform Support

| Capability | Linux | macOS | WSL |
|------------|-------|-------|-----|
| Sound playback | `paplay` / `aplay` | `afplay` | `powershell.exe` |
| Notifications | `notify-send` | `osascript` | `powershell.exe` |
| Window focus | `wmctrl` | `osascript` | N/A |
| Jump to terminal | `xdotool` | `osascript` | N/A |

## Uninstall

```bash
bash install.sh --uninstall
```

This removes the hook entry from Claude Code settings and deletes the config file.

## How It Works

Claude Code supports user-defined [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) -- shell commands that run automatically in response to specific events. One of those events is `Notification`, which fires whenever Claude Code is waiting for user input (permission prompts, questions, etc.).

claude-notify registers itself as a `Notification` hook. When the event fires, the script:

1. Loads your configuration from `~/.config/claude-notify/config.env`.
2. Detects the current OS (Linux, macOS, or WSL).
3. Identifies the IDE and terminal tab (IntelliJ tab detection on Linux).
4. Plays the configured sound file in the background.
5. Sends a desktop notification with the message from Claude Code.
6. Saves window state so `claude-jump.sh` can focus the right window later.

The script always exits with code 0 so it never blocks the hook chain.

## Contributing

Pull requests are welcome. For large changes, please open an issue first to discuss what you would like to change.

## License

[MIT](LICENSE)

## Sound Attribution

- **ninja-shuriken-throw.wav** -- Cody Mahan via [SoundBible.com](https://soundbible.com) (Public Domain)
- **ninja-swoosh.wav** -- [SoundBible.com](https://soundbible.com) (Sampling Plus 1.0)
- **electric-piano.wav** -- [sound-icons](https://packages.debian.org/sound-icons) package (GPL)
