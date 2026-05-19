# JrnlBar Backlog

Feature ideas to consider. JrnlBar wraps the `jrnl` CLI — anything that
would replace jrnl's storage / DB layer is out of scope. Everything here
sits *around* jrnl.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped

---

## Integrations

- [ ] **macOS Shortcuts action** — Expose an "Add jrnl entry" action to the
      Shortcuts app so users can chain entry creation with other actions
      (Siri, automations, share sheets that target Shortcuts).
- [ ] **URL scheme** — Register `jrnlbar://new?body=...&tags=...&journal=...`
      so Alfred / Raycast / bookmarklets / scripts can push entries without
      shelling out to the CLI.
- [ ] **Raycast / Alfred extension** — Thin third-party-launcher wrapper
      around the URL scheme above. Mostly distribution, not code.
- [ ] **Calendar context seed** — On open, offer a "Seed from today's
      meetings" button. Reads EventKit, builds a draft listing today's
      meeting titles + times as a starting point.
- [ ] **Now-Playing / weather / location stamp** — Opt-in metadata header
      auto-prepended to a new entry (currently-playing track, current
      weather + location). Useful for memory-jogging context.
- [ ] **Drag-and-drop attachments** — Drop an image or file onto the editor;
      JrnlBar copies it to `~/Documents/jrnl-attachments/<date>/` and
      inserts a relative markdown link at the cursor.
- [ ] **Share Sheet target** — Register as a share-sheet recipient so
      Safari / Notes / Mail can send selected text directly into JrnlBar.

## UX

- [ ] **Live markdown preview toggle** — Split or swap view showing the
      rendered markdown. The existing `MarkdownHighlighter` already knows
      the syntax; this is a rendering layer on top.
- [ ] **Resizable panel + remembered size** — The current panel is fixed
      size. Allow drag-resize and persist last size per launch.
- [ ] **Word / char / reading-time counter** — Small live readout in the
      submit bar footer.
- [ ] **Crash-safe draft autosave** — Persist the in-flight buffer to disk
      every N seconds (and on focus loss). On launch, restore the draft
      if non-empty. Survives app quit, panel close, crash.
- [ ] **Templates** — User-defined snippets (morning standup, gratitude,
      retro template, weekly review). Insert via a slash menu or a
      template picker button. Stored in `~/Library/Application
      Support/JrnlBar/templates/`.
- [ ] **Quick-entry mode** — A second global hotkey that pops a single-line
      text field, commits on Enter, no panel UI. For one-liners.
- [ ] **Recent entries free-text filter** — Add a search field above the
      recents list that filters by body text in addition to the existing
      tag filter.
- [ ] **Pinned entries** — Pin 1–3 entries to the top of the recents list,
      saved per-journal. Useful for "current focus" notes.
- [ ] **Per-journal accent color** — Visual cue (border / header tint)
      that changes when swapping between journals, so the user knows at a
      glance whether they're writing to work or default.

## Search & Navigation

- [ ] **Full-text search panel** — Dedicated search view with snippet
      highlights. Wraps `jrnl --contains` or scans the journal file
      directly.
- [ ] **Date-range picker for recents** — Scope the recents list to a
      date range. Use the `StepperDateField` + `CalendarPopoverButton`
      pattern (see global CLAUDE.md notes on the macOS DatePicker
      anti-pattern).
- [ ] **"On this day"** — When entries exist from the same calendar date
      in prior years, surface them at the top of the recents list.
- [ ] **Tag cloud / tag stats popover** — Visual frequency + last-used
      date per tag. Click any tag to filter recents.

## Utility / Quality

- [ ] **Auto-detect jrnl path** — Currently hard-coded to
      `/opt/homebrew/bin/jrnl`. Probe `/usr/local/bin`, `$PATH`, and a
      user-override preference. Removes a silent failure mode for Intel
      Macs and pipx installs.
- [ ] **Rotating encrypted backups** — On each save, snapshot the
      journal file to `~/Library/Application Support/JrnlBar/backups/`,
      keeping the last N. Optional encryption with a user-supplied
      passphrase.
- [ ] **Streak + word-count goal** — Small badge in the panel header
      showing current streak and progress toward a configurable daily
      word-count target.
- [ ] **Weekly digest notification** — Sunday evening macOS notification
      summarising the past week: entry count, top tags, total words.
- [ ] **Conflict detection** — If the journal file mtime changed while
      the JrnlBar editor was open (external `jrnl` CLI run, another
      tool, manual edit), warn before overwriting.

## Intelligence (BYO API key, opt-in)

All AI features require explicit opt-in and a user-supplied API key.
Privacy stance must be clear: nothing leaves the device without consent.

- [ ] **Suggest tags before save** — Read the draft body, propose 1–3
      `@tag`s the user can accept/dismiss with a keystroke.
- [ ] **Tighter title suggestion** — jrnl's title = first sentence.
      Offer a one-line rewrite the user can accept.
- [ ] **Proofread / tone pass** — Manual button (not auto) that runs the
      current draft through a proofread or tone-adjustment pass and
      shows a diff.
- [ ] **Weekly themes** — "Your week in 5 bullets" generated from the
      last 7 entries on demand.
- [ ] **Ask-my-journal (RAG)** — Q&A over the full journal file. Small
      embedding index rebuilt on save. Biggest payoff, biggest cost
      (embeddings storage, key management, privacy story).

---

## Top 3 (current priorities)

1. **Templates + quick-entry mode** — biggest daily-usage lift, no
   external dependencies, fits the menu-bar ergonomic.
2. **Auto-detect jrnl path + crash-safe draft autosave** — invisible
   quality wins; users get fewer "lost the thing I typed" moments and
   the app works on more setups out of the box.
3. **Ask-my-journal (RAG)** — the one feature that transforms what the
   app *is* rather than polishes it. Only worth doing with commitment
   to the BYO-API-key path.
