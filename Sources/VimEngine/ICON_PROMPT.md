# Paste this into a fresh Claude session in a Swift app that uses VimEngine

---

I want to replace this app's vim toggle icon (currently an SF Symbol like
`keyboard`, or a bundled PNG asset) with the universal vim command-line
prompt — the `:_` mark — rendered as styled text rather than an image.
The reference change is in runbook-mac.

## Why

- `:_` (colon + underscore-cursor) is the vim command-line prompt itself,
  not a generic "keyboard" or "terminal" icon. Instantly readable to vim
  users; just a small chunky glyph to everyone else.
- Rendering as `Text(":_")` instead of an image means: crisp at any size,
  no bundle/asset hassle, recolors with `.foregroundStyle` exactly like
  an SF Symbol, no Makefile / asset-catalog changes.
- A PNG glyph at toolbar size (14×14) tends to render as specks — the
  actual `:_` content is a tiny fraction of any reasonable canvas. Text
  doesn't have that problem.

## What to change

1. **Find your vim toggle button.** Likely in a `VimToolbarItem` /
   "mode badge" / pill-button view, somewhere near where you create a
   `VimEngine` from a slash command or button click. Look for
   `Image(systemName: "keyboard")` or `Image("...VimIcon...")`.

2. **Replace the image with a `Text(":_")` view.** Add the glyph as a
   small private view in the same file:

   ```swift
   private struct VimGlyph: View {
       var body: some View {
           Text(":_")
               .font(.system(size: 14, weight: .heavy, design: .monospaced))
               .baselineOffset(-2)
               .tracking(-1)
       }
   }
   ```

   Then in the button, swap your old `Image(...)` for `VimGlyph()`.
   Apply `.foregroundStyle(.secondary)` on the button content the same
   way you would for an SF Symbol — Text honors it.

3. **Drop any framing constraints that were sized for an image.** A
   leftover `.frame(width: 14, height: 14)` will clip or shrink the
   text. Replace with breathing room only:

   ```swift
   .padding(.horizontal, 4)
   .padding(.vertical, 1)
   .contentShape(Rectangle())  // keeps the hit target sane
   ```

4. **If you were bundling a PNG** (asset catalog entry, `Resources/`
   directory, `NSImage(named:)` lookup, Makefile `cp` line) — delete
   all of it. The Text approach needs no resources.

5. **Tooltip.** Add `.help("Vim mode (off). Click — or type /vim — to enable.")`
   on the button if there isn't one already.

## Tune the size

The `Text(":_")` should match the surrounding caption-sized buttons (Save,
Validate, etc.) — ~14pt heavy monospaced is the runbook-mac value. If it
reads too small, bump to 15. If your toolbar's typography is larger,
align the font size with it.

The `baselineOffset(-2)` pulls the underscore up so the glyph centers
vertically against neighboring controls (the underscore sits at the
font's bottom, which otherwise leaves the glyph visually low).
`tracking(-1)` tightens the colon-to-underscore gap a hair — the colon's
default tracking pushes the underscore right; -1 brings them together.

## Verify

- Hover the icon — tooltip appears.
- The icon is clearly readable at toolbar size (you can identify the
  colon dots and the underscore bar without squinting).
- The icon recolors correctly in light AND dark mode — it should follow
  `.foregroundStyle(.secondary)`. If it's stuck at one color, you
  probably nested a `.foregroundColor(...)` further inside; remove it.
- Click the icon: vim activates exactly as before (the button's action
  closure is unchanged).

## Deliver

When you're done:
1. The diff (added `VimGlyph` view, swapped the button content, deleted
   any image/asset/Makefile lines).
2. A note on the final font size + weight you settled on.
