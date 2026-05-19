# Paste this into any session for a Swift app that uses VimEngine

---

There's a bug in apps integrating `VimEngine` where the cursor walks
off-screen when vim moves it (j/k, G, gg, w/b/e past the visible area,
n after a search, etc.) — the text view's scroll position does not
follow. Confirmed in jrnlbar and recruit-mac; likely affects any host.

## Root cause

`VimEngine` mutates the cursor by assigning `editor.selectedRange = ...`
directly on its `VimTextEditor` (NSTextView in real hosts). On
`NSTextView`, that setter does **not** call `scrollRangeToVisible`.

AppKit's normal "the caret stays in view" behavior is a side effect of
`insertText(_:)` / typing, not of the `selectedRange` setter. Vim's
keystrokes bypass `insertText` entirely for navigation, so the scroll
view never adjusts.

## Fix

Override `setSelectedRanges(_:affinity:stillSelecting:)` on your
`NSTextView` subclass (the same one where you already implement vim's
block cursor — `JrnlTextView` in jrnlbar, `VimHostTextView` in
recruit-mac). After calling `super`, if vim is active and the change
isn't a mid-drag selection, call `scrollRangeToVisible` on a
zero-length range at the new primary location.

```swift
public override func setSelectedRanges(
    _ ranges: [NSValue],
    affinity: NSSelectionAffinity,
    stillSelecting: Bool
) {
    let oldRect = blockCursorRect()
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)

    guard let vim = vimEngineProvider?() else { return }

    // Bypassed by AppKit's normal scroll-to-reveal pipeline since the
    // engine sets selectedRange directly. Without this, j/k/G/gg/n
    // walk the caret off screen.
    if !stillSelecting,
       let primary = (ranges.first as? NSValue)?.rangeValue {
        scrollRangeToVisible(NSRange(location: primary.location, length: 0))
    }

    // Existing block-cursor invalidation continues below:
    guard vim.submode != .insert else { return }
    if let oldRect { setNeedsDisplay(oldRect.insetBy(dx: -1, dy: -1)) }
    if let newRect = blockCursorRect() { setNeedsDisplay(newRect.insetBy(dx: -1, dy: -1)) }
}
```

### Why this placement

- **Inside the existing override.** You already wrap `setSelectedRanges`
  to invalidate the block cursor rect on caret moves; this is the same
  funnel point for any cursor change, including the engine's. One hook
  covers `hjkl`, `w/b/e`, `gg/G`, search nav (`n/N`), and the post-edit
  cursor land after `d`/`y`/`p`.
- **Guarded on vim being active.** Outside vim, AppKit's existing
  selection-change behavior is what users expect — we don't want to
  start auto-scrolling on every programmatic `setSelectedRange` from
  some unrelated piece of code (find-in-page, AppleScript, accessibility
  tooling, etc.).
- **Guarded on `!stillSelecting`.** During a drag-select with the mouse,
  `setSelectedRanges` fires continuously; scrolling on every tick would
  fight the drag. AppKit's own drag-scroll handles that case.
- **Zero-length range.** `scrollRangeToVisible` honors the WHOLE range,
  which for a visual-mode selection could span screens. Reducing to a
  zero-length range at the caret's location scrolls only enough to
  reveal the caret, which is what vim users expect.

## What to verify after the fix

- `vim:N` then long-hold `j` past the bottom of the visible area — the
  view should scroll, the caret should stay on the last visible line.
- `vim:N` then `G` to jump to end-of-buffer — view jumps with the caret.
- `vim:N` then `gg` — back to top, both caret and viewport.
- `vim:I` (insert mode) → typing past the bottom — should keep working
  via AppKit's normal scroll-to-reveal-cursor (insertText path); the
  fix doesn't break it because `super.setSelectedRanges` already ran.
- Mouse drag-select within the visible area — no jumpy scroll.

## Should this be fixed in the engine instead?

Maybe — `extension NSTextView: VimTextEditor` could override the
`selectedRange` setter to also scroll. But that would change behavior
for any host that intentionally wants to set the selection silently
(e.g. for find-in-text without disrupting scroll position). Keeping
the scroll-to-reveal in the host subclass, gated on `vim active`, is
the conservative call. If you want to upstream the fix into the
engine instead, change it inside the `NSTextView: VimTextEditor`
conformance, not the protocol — protocol methods can't override
property setters.

## Deliver

When you're done, give me:

1. The diff of files modified.
2. A brief note on whether you upstreamed to the engine or kept it
   host-local (and why).
