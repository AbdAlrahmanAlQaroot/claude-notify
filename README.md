# claude-notify

Never miss a Claude Code permission prompt again.

A tiny shell script that plays a sound and pops a desktop notification whenever [Claude Code](https://docs.anthropic.com/en/docs/claude-code) is waiting for your input. Click the notification to jump straight back to the right window.

No daemon. No background process. Just a [hook](https://docs.anthropic.com/en/docs/claude-code/hooks) that runs when Claude needs you.

## Install

```bash
git clone https://github.com/AbdAlrahmanAlQaroot/claude-notify.git
cd claude-notify
bash install.sh
```

The installer picks up your OS, finds your sound player, lets you preview and choose a sound, wires up the hook, and you're done. Takes about 10 seconds.

## What you get

- Sound alert when Claude is waiting (3 bundled, or bring your own `.wav`)
- Desktop notification with a **"Go to terminal"** button
- Auto-detects your IDE window (IntelliJ, VS Code, or any terminal)
- Works on **Linux**, **macOS**, and **WSL**
- Zero dependencies beyond what your OS already has

## Sounds

| Sound | Vibe |
|-------|------|
| `ninja-swoosh` | Quick swoosh (default) |
| `ninja-shuriken-throw` | Shuriken in flight |
| `electric-piano` | Gentle piano note |

Switch anytime:

```bash
bash install.sh --sound ninja-shuriken-throw
```

Or use your own: set `CLAUDE_NOTIFY_SOUND="/path/to/sound.wav"` in `~/.config/claude-notify/config.env`.

## Configuration

All settings live in `~/.config/claude-notify/config.env`:

| Variable | Default | What it does |
|----------|---------|--------------|
| `CLAUDE_NOTIFY_SOUND` | `ninja-swoosh.wav` | Sound file or absolute path |
| `CLAUDE_NOTIFY_IDE` | `auto` | Window detection: `auto`, `intellij`, `vscode`, `terminal` |
| `CLAUDE_NOTIFY_URGENCY` | `normal` | Linux notification urgency: `low`, `normal`, `critical` |
| `CLAUDE_NOTIFY_ENABLED` | `true` | Kill switch |
| `CLAUDE_NOTIFY_SOUND_ENABLED` | `true` | `false` for silent (visual-only) notifications |

## Platform support

| | Linux | macOS | WSL |
|-|-------|-------|-----|
| Sound | `paplay` / `aplay` | `afplay` | `powershell.exe` |
| Notification | `notify-send` | `osascript` | `powershell.exe` |
| Window focus | `wmctrl` | `osascript` | `powershell.exe` |

## How it works

Claude Code fires a `Notification` hook whenever it's waiting for input. claude-notify registers itself as that hook. When it fires:

1. Plays your chosen sound in the background
2. Sends a desktop notification
3. If you click "Go to terminal", focuses the right window

That's it. One script, no magic.

## Uninstall

```bash
bash install.sh --uninstall
```

## Contributing

PRs welcome. Open an issue first for anything big.

## License

[MIT](LICENSE)

## Sound credits

- **ninja-shuriken-throw.wav** -- Cody Mahan via [SoundBible.com](https://soundbible.com) (Public Domain)
- **ninja-swoosh.wav** -- [SoundBible.com](https://soundbible.com) (Sampling Plus 1.0)
- **electric-piano.wav** -- [sound-icons](https://packages.debian.org/sound-icons) package (GPL)
