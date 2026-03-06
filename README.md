# JrnlBar

A macOS menu bar app for quickly adding journal entries via the [jrnl](https://jrnl.sh) CLI.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar app** — lives in your menu bar, no dock icon
- **Markdown editor** with syntax highlighting (headers, bold, italic, code, lists, @tags)
- **Tag autocomplete** — type `@` to see suggestions from your existing tags, navigate with arrow keys
- **Multiple journals** — switch between configured jrnl journals (e.g., personal/work)
- **Recent entries** — view and expand your last 10 entries, with sort direction toggle
- **Global hotkey** — `Shift+Cmd+J` to toggle from anywhere (no Accessibility permission needed)
- **Keyboard driven** — `Cmd+Enter` to submit, `Escape` to close
- **Zero dependencies** — pure AppKit/SwiftUI, no external packages

## Requirements

- macOS 14 (Sonoma) or later
- [jrnl](https://jrnl.sh) v4+ installed at `/opt/homebrew/bin/jrnl`
- Xcode Command Line Tools (for building from source)

## Install

### Download

Download `JrnlBar.dmg` from the [latest release](../../releases/latest), open it, and drag `JrnlBar.app` to `/Applications`.

### Build from source

```bash
git clone https://github.com/YOUR_USERNAME/jrnlbar.git
cd jrnlbar
make install
```

This builds a release binary, assembles the `.app` bundle, installs to `/Applications`, and registers a launch agent for login startup.

## Usage

1. Click the book icon in the menu bar to open the editor
2. Write your entry (markdown is highlighted as you type)
3. Press `Cmd+Enter` or click "Save Entry" to submit
4. Switch journals by clicking the journal name in the submit bar
5. Right-click the icon for About/Quit

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Shift+Cmd+J` | Toggle panel (global) |
| `Cmd+Enter` | Submit entry |
| `Escape` | Close panel / dismiss tag suggestions |
| `↑` `↓` | Navigate tag suggestions |
| `Enter` / `Tab` | Accept tag suggestion |

## Makefile targets

```
make build      # Build release binary
make app        # Build + assemble .app bundle
make install    # Build + install to /Applications + launch agent
make dmg        # Build + create distributable DMG
make uninstall  # Remove from /Applications + launch agent
make clean      # Remove build artifacts
make run        # Build + run
```

## License

MIT — see [LICENSE](LICENSE).
