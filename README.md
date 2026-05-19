# JrnlBar

A macOS menu bar app for quickly adding journal entries via the [jrnl](https://jrnl.sh) CLI — with slash commands, file-backed templates, and a built-in vim editor mode for power users.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Core
- **Menu bar app** — lives in your menu bar, no dock icon
- **Markdown editor** with syntax highlighting (headers, bold, italic, code, lists, @tags)
- **Title detection** — jrnl's title boundary (first sentence) is visually distinguished as you type
- **Multiple journals** — switch between configured jrnl journals (e.g., default / work) via the submit bar
- **Recent entries** — view, expand, and edit your last 10 entries, with sort direction toggle
- **Global hotkey** — `Shift+Cmd+J` to toggle the panel from anywhere
- **Services integration** — select text in any app → Services → "Add to jrnl"
- **Notifications, Launch at Login, About** — all in the right-click context menu

### Slash commands
Type `/` in the editor to open a horizontal dropdown of available commands. Counts work; `Tab`/`Enter` or `Space` (on exact match) commits.

- **Templates** — markdown files in `~/.local/share/jrnl/templates/` (the same folder jrnl's `--template` flag reads). Four defaults are seeded on first launch if the folder is empty: `morning-standup.md`, `gratitude.md`, `weekly-review.md`, `meeting-notes.md`. Each supports `{{date}}`, `{{time}}`, `{{weekday}}`, and `{{cursor}}` tokens (JrnlBar-only — these stay literal if you also use the file via `jrnl --template`).
- **Mode commands** — `/uc` toggles uppercase typing, `/vim` enters full vim editor mode (see below). Names are case-insensitive (`/UC` and `/vim` both work).
- **Escape sequence** — type `//name` to write a literal `/name` in the entry; the leading double-slash is stripped at save time.

### Vim editor mode
Type `/vim` (or click the badge to exit) to drop into a full vim emulator on the entry field. The engine is the standalone [`swift-vim-engine`](https://github.com/msjurset/swift-vim-engine) package — same component is usable in other Swift apps. Click the **?** icon next to the VIM badge for an in-app cheatsheet.

Highlights:
- Normal / Insert / Visual / Command-line / Replace modes
- `hjkl` (visual-line), `gj`/`gk` (logical line), `w b e ge`, `W B E`, `0 ^ $`, `{ }`, `%`, `f F t T`, `; ,`, `gg G`, `NG`/`:N`
- `Ctrl-d`/`Ctrl-u` half-page, `Ctrl-f`/`Ctrl-b` full-page, `H M L` viewport positions, `zz zt zb` cursor alignment
- Operators: `d y c gU gu g~` over motions; `dd D yy Y cc C s x X J`
- Text objects: `iw aw iW aW i" a" i' a' i\` a\` i( a( i[ a[ i{ a{`
- Replace: `r<x>`, `R` overstrike
- Search: `/term`, `?term`, `n N`, `*` `#` (word under cursor)
- Marks: `m<a-z>`, `'<a-z>`, `` `<a-z>``
- Indent: `>>` `<<` `>{motion}` `<{motion}`, visual `>` `<`
- `.` repeat including insert-mode text, `u` undo, `Ctrl-r` redo, `gv` re-enter last visual
- Command line: `:q :vim :w :wq` (`w` saves, `q` exits vim mode)

### Editor amenities
- **Tag autocomplete** — type `@` to see suggestions from your existing tags
- **Tag filtering** — click any @tag in an expanded entry to filter the recents list
- **Edit entries** — pencil icon on an expanded entry, with rollback safety on submit failure
- **External editor** — pop out your draft to any editor (iA Writer, VS Code, etc.) via `Cmd+E`
- **Keyboard driven** — standard `Cmd+V/C/X/A/Z` work; `Esc` closes panel (yielded to vim while vim is active)

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

1. Click the book icon in the menu bar (or press `Shift+Cmd+J`) to open the editor.
2. Write your entry. The first sentence is auto-detected as jrnl's title and shown in semibold.
3. Type `/` to insert a template or activate a mode (`/vim`, `/uc`).
4. Press `Cmd+Enter` (or click "Save Entry") to submit.
5. Click any @tag in an expanded entry to filter the recents list.
6. Click the pencil icon on an expanded entry to edit it in place.
7. Press `Cmd+E` (or click the pop-out icon) to compose in an external text editor.

### External editor

`Cmd+E` (or `Option+Cmd+Enter`) saves the current draft to a temp file, hides the panel, and opens your default text editor. When the editor closes, JrnlBar re-reads the file and the panel comes back.

Override the default with the `externalEditorBundleID` preference:

```bash
defaults write com.local.JrnlBar externalEditorBundleID "pro.writer.mac"   # iA Writer
defaults write com.local.JrnlBar externalEditorBundleID "com.microsoft.VSCode"
defaults delete com.local.JrnlBar externalEditorBundleID                    # revert
```

### Templates

JrnlBar reuses jrnl's templates folder (`~/.local/share/jrnl/templates/`). Add or edit any `.md` / `.txt` file there; the names appear as `/foo` slash commands. Names must be alphanumeric (plus `-` / `_`) to be reachable via slash — files with spaces or punctuation still work via `jrnl --template` from the CLI but aren't reachable via the slash dropdown.

Token substitution happens on insert in JrnlBar:
- `{{date}}` → `2026-05-19`
- `{{time}}` → `14:32`
- `{{weekday}}` → `Tuesday`
- `{{cursor}}` → empty (places the caret here after insertion)

These are **JrnlBar-only** — `jrnl --template` doesn't expand them, so tokens appear literally if you use the same file from the CLI.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Shift+Cmd+J` | Toggle panel (global) |
| `Cmd+Enter` | Submit entry |
| `Option+Cmd+Enter` (or `Cmd+E`) | Open in external editor |
| `Cmd+V/C/X/A/Z` | Paste / Copy / Cut / Select All / Undo |
| `Escape` | Close panel (yields to vim while vim is active) |
| `↑` `↓` | Navigate tag / slash dropdown |
| `Enter` / `Tab` | Accept tag / slash suggestion |
| `Space` | Accept slash suggestion on exact match |

### Services

Select text in any application, then use the Services menu (right-click → Services → **Add to jrnl**) to send it directly to your currently selected journal.

## Makefile targets

```
make build       # Build release binary
make app         # Build + assemble .app bundle
make install     # Build + install to /Applications + launch agent
make dmg         # Build + create distributable DMG
make uninstall   # Remove from /Applications + launch agent
make clean       # Remove build artifacts
make test        # Run unit tests
make run         # Build + run from the local bundle
make update-vim  # Pull the latest swift-vim-engine release
```

## VimEngine as a reusable component

The vim mode is implemented as a standalone Swift Package, `swift-vim-engine`, at [`github.com/msjurset/swift-vim-engine`](https://github.com/msjurset/swift-vim-engine). Other Swift apps can depend on it directly — see the package's `INTEGRATION_PROMPT.md` (new apps) or `MIGRATION_PROMPT.md` (apps with a copied source).

JrnlBar tracks it as a SwiftPM dependency pinned via `Package.resolved`. `make update-vim` pulls the latest tagged release in the configured version range; review the diff and commit `Package.resolved` to lock in.

## License

MIT — see [LICENSE](LICENSE).
