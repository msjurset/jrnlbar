# JrnlBar

A macOS menu bar app for quickly adding journal entries via the [jrnl](https://jrnl.sh) CLI.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar app** — lives in your menu bar, no dock icon
- **Markdown editor** with syntax highlighting (headers, bold, italic, code, lists, @tags)
- **Title detection** — jrnl's title boundary (first sentence) is visually distinguished as you type
- **Tag autocomplete** — type `@` to see suggestions from your existing tags, navigate with arrow keys
- **Tag filtering** — click any @tag in an expanded entry to filter the list to that tag
- **Edit entries** — click the pencil icon on an expanded entry to edit it in place, with rollback safety
- **Multiple journals** — switch between configured jrnl journals (e.g., default/work)
- **Recent entries** — view and expand your last 10 entries, with sort direction toggle
- **Global hotkey** — `Shift+Cmd+J` to toggle from anywhere (no Accessibility permission needed)
- **Keyboard driven** — `Cmd+Enter` to submit, `Escape` to close, `Cmd+V/C/X/A/Z` all work
- **Services integration** — select text in any app → Services → "Add to jrnl"
- **Notifications** — brief macOS notification confirms when an entry is saved
- **Launch at Login** — toggle via right-click context menu, no System Settings needed
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
git clone https://github.com/msjurset/jrnlbar.git
cd jrnlbar
make install
```

This builds a release binary, assembles the `.app` bundle, installs to `/Applications`, and registers a launch agent for login startup.

## Usage

1. Click the book icon in the menu bar to open the editor
2. Write your entry (the title is auto-detected and shown in semibold)
3. Press `Cmd+Enter` or click "Save Entry" to submit
4. Switch journals by clicking the journal name in the submit bar
5. Click any @tag in an expanded entry to filter the list
6. Click the pencil icon on an expanded entry to edit it
7. Right-click the icon for Launch at Login / About / Quit

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Shift+Cmd+J` | Toggle panel (global) |
| `Cmd+Enter` | Submit entry |
| `Cmd+V/C/X/A/Z` | Paste / Copy / Cut / Select All / Undo |
| `Escape` | Close panel / dismiss tag suggestions |
| `↑` `↓` | Navigate tag suggestions |
| `Enter` / `Tab` | Accept tag suggestion |

### Services

Select text in any application, then use the Services menu (right-click → Services → **Add to jrnl**) to send it directly to your currently selected journal.

## Makefile targets

```
make build      # Build release binary
make app        # Build + assemble .app bundle
make install    # Build + install to /Applications + launch agent
make dmg        # Build + create distributable DMG
make uninstall  # Remove from /Applications + launch agent
make clean      # Remove build artifacts
make test       # Run unit tests
make run        # Build + run
```

## License

MIT — see [LICENSE](LICENSE).
