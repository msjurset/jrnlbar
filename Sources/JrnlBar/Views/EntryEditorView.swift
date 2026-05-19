import SwiftUI
import AppKit
import VimEngine

struct EntryEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var tagPrefix: String  // Current @partial text, empty when no tag context
    @Binding var slashPrefix: String  // Current /partial text, empty when no slash context
    @Binding var pendingCursor: Int?  // One-shot caret position request (UTF-16 offset)
    var currentMode: TextMode?  // Active typing transformation, if any
    var vimEngine: VimEngine?  // Non-nil when /vim is active; owns key routing
    var onSubmit: () -> Void
    var onOpenExternal: (() -> Void)?
    var onTagKeyEvent: (SuggestionKeyEvent) -> Bool  // Returns true if handled
    var onSlashKeyEvent: (SuggestionKeyEvent) -> Bool  // Returns true if handled

    enum SuggestionKeyEvent {
        case arrowUp, arrowDown, enter, escape, tab, space
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = JrnlTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.enabledTextCheckingTypes = NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.grammar.rawValue
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        let highlighter = MarkdownHighlighter()
        textStorage.delegate = highlighter
        context.coordinator.highlighter = highlighter

        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.submitHandler = { coordinator.parent.onSubmit() }
        textView.openExternalHandler = { coordinator.parent.onOpenExternal?() }
        textView.tagKeyHandler = { event in coordinator.parent.onTagKeyEvent(event) }
        textView.slashKeyHandler = { event in coordinator.parent.onSlashKeyEvent(event) }
        textView.isShowingTags = { !coordinator.parent.tagPrefix.isEmpty }
        textView.isShowingSlash = { !coordinator.parent.slashPrefix.isEmpty }
        textView.currentModeProvider = { coordinator.parent.currentMode }
        textView.vimEngineProvider = { coordinator.parent.vimEngine }
        context.coordinator.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Refresh the coordinator's parent so non-@Binding values (e.g.
        // currentMode) read live values rather than the struct captured
        // at makeCoordinator() time. @Binding values bypass this since
        // their wrapper has its own storage.
        context.coordinator.parent = self

        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            context.coordinator.updatingFromBinding = true
            textView.string = text
            textView.textStorage?.edited(.editedCharacters, range: NSRange(location: 0, length: 0), changeInLength: 0)
            context.coordinator.updatingFromBinding = false
        }

        if let cursor = pendingCursor {
            let length = (textView.string as NSString).length
            let clamped = max(0, min(cursor, length))
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
            DispatchQueue.main.async {
                self.pendingCursor = nil
            }
        }

        // On vim→off transition, return first responder to the text view
        // and repaint the cursor cell so the lingering block clears.
        let vimActiveNow = (currentMode == .vim)
        if context.coordinator.lastVimActive && !vimActiveNow {
            DispatchQueue.main.async {
                if let window = textView.window {
                    // Ensure the window can actually receive input —
                    // there have been reports where the panel lost
                    // key status during a focus shuffle and clicks
                    // back into the editor weren't routing properly.
                    if !window.isKeyWindow {
                        window.makeKeyAndOrderFront(nil)
                    }
                    window.makeFirstResponder(textView)
                }
                if let tv = textView as? JrnlTextView {
                    tv.refreshCursorArea()
                }
            }
        }
        context.coordinator.lastVimActive = vimActiveNow
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EntryEditorView
        var textView: NSTextView?
        var highlighter: MarkdownHighlighter?
        var updatingFromBinding = false
        // Tracks the previous vim-active state so updateNSView can
        // restore first-responder to the text view on the vim→off
        // transition (clicking the badge's X moves focus to the button).
        var lastVimActive: Bool = false

        init(_ parent: EntryEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !updatingFromBinding else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Slash + tag autocomplete are suspended while vim is on:
            // vim's normal mode wants `/` to be inert, and insert mode is
            // for plain typing without app-level popovers competing.
            if parent.currentMode == .vim {
                parent.tagPrefix = ""
                parent.slashPrefix = ""
                return
            }
            let tag = findTagPrefix(in: textView)
            parent.tagPrefix = tag
            parent.slashPrefix = tag.isEmpty ? findSlashPrefix(in: textView) : ""
        }

        private func findTagPrefix(in textView: NSTextView) -> String {
            let cursorLocation = textView.selectedRange().location
            let string = textView.string
            guard cursorLocation > 0, cursorLocation <= string.count else { return "" }

            let nsString = string as NSString
            var i = cursorLocation - 1
            while i >= 0 {
                let ch = nsString.character(at: i)
                guard let scalar = Unicode.Scalar(ch) else { return "" }
                if scalar == "@" {
                    return nsString.substring(with: NSRange(location: i, length: cursorLocation - i))
                } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                    i -= 1
                } else {
                    return ""
                }
            }
            return ""
        }

        private func findSlashPrefix(in textView: NSTextView) -> String {
            let cursorLocation = textView.selectedRange().location
            let string = textView.string
            guard cursorLocation > 0, cursorLocation <= string.count else { return "" }

            let nsString = string as NSString
            var i = cursorLocation - 1
            while i >= 0 {
                let ch = nsString.character(at: i)
                guard let scalar = Unicode.Scalar(ch) else { return "" }
                if scalar == "/" {
                    // `//` escape — caller typed a literal slash sequence; suppress.
                    if i > 0, nsString.character(at: i - 1) == 0x2F { return "" }
                    return nsString.substring(with: NSRange(location: i, length: cursorLocation - i))
                } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                    i -= 1
                } else {
                    return ""
                }
            }
            return ""
        }

        /// Replace the current @prefix in the text view with the given tag name.
        func insertTag(_ tagName: String) {
            guard let textView = textView else { return }
            let prefix = parent.tagPrefix
            guard !prefix.isEmpty else { return }

            let cursor = textView.selectedRange().location
            let prefixStart = cursor - prefix.count
            let range = NSRange(location: prefixStart, length: prefix.count)

            let replacement = tagName + " "
            textView.shouldChangeText(in: range, replacementString: replacement)
            textView.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()

            parent.text = textView.string
            parent.tagPrefix = ""
        }
    }
}

class JrnlTextView: NSTextView {
    var submitHandler: (() -> Void)?
    var openExternalHandler: (() -> Void)?
    var tagKeyHandler: ((EntryEditorView.SuggestionKeyEvent) -> Bool)?
    var slashKeyHandler: ((EntryEditorView.SuggestionKeyEvent) -> Bool)?
    var isShowingTags: (() -> Bool)?
    var isShowingSlash: (() -> Bool)?
    var currentModeProvider: (() -> TextMode?)?
    var vimEngineProvider: (() -> VimEngine?)?

    /// Block cursor: solid translucent fill over the character cell,
    /// no outline. Uses the system selection color so it adapts to
    /// light/dark mode. Reverts to the default beam in insert mode or
    /// when vim isn't active.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard let vim = vimEngineProvider?(), vim.submode != .insert else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        guard flag, let block = blockCursorRect() else { return }
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.75).setFill()
        block.fill()
    }

    /// Refresh the area where the cursor was painted. Called when the
    /// caret moves, the vim mode changes, or vim itself exits — so
    /// AppKit redraws the cell background + glyph, erasing the
    /// previous block.
    func refreshCursorArea() {
        invalidateBlockCursorArea()
    }

    private func invalidateBlockCursorArea() {
        // Force a full redraw rather than guessing rects. NSTextView's
        // selectedRange writes can come at any time (mouse, vim engine,
        // accessibility) and the OLD block position is hard to track
        // reliably — partial invalidation was causing stale blocks
        // ("double cursor") to linger after rapid moves. The text view
        // is small in this app, so the cost is fine.
        needsDisplay = true
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)

        guard let vim = vimEngineProvider?() else { return }

        // VimEngine sets `selectedRange` directly, which bypasses
        // AppKit's normal scroll-to-reveal-cursor pipeline (that runs
        // only on insertText). Without this, j/k/G/gg/n walk the caret
        // off screen. Skipped during mouse drag-select to avoid
        // fighting AppKit's own drag-scroll.
        if !stillSelecting,
           let primary = (ranges.first as? NSValue)?.rangeValue {
            scrollRangeToVisible(NSRange(location: primary.location, length: 0))
        }

        // Force a full redraw when vim is in a block-cursor submode so
        // the previous block position is reliably erased.
        if vim.submode != .insert {
            needsDisplay = true
        }
    }

    private func blockCursorRect() -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let ns = string as NSString
        let cursor = selectedRange.location

        // End of buffer (no character under caret): synthesise a cell
        // one char wide just past the last glyph.
        if cursor >= ns.length {
            let lineHeight = font?.boundingRectForFont.height ?? 16
            if ns.length == 0 {
                let origin = textContainerOrigin
                return NSRect(x: origin.x, y: origin.y, width: 8, height: lineHeight)
            }
            let lastRange = NSRange(location: ns.length - 1, length: 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lastRange, actualCharacterRange: nil)
            let lastRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            return NSRect(
                x: lastRect.maxX + textContainerOrigin.x,
                y: lastRect.minY + textContainerOrigin.y,
                width: max(lastRect.width, 8),
                height: lastRect.height
            )
        }

        let range = NSRange(location: cursor, length: 1)
        let chAtCursor = ns.character(at: cursor)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var r = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        r.origin.x += textContainerOrigin.x
        r.origin.y += textContainerOrigin.y

        // On a newline (empty line, or end-of-line position), the layout
        // manager reports a rect spanning the rest of the line. Vim shows
        // a normal char-width block there, so narrow it back down.
        if chAtCursor == 0x0A {
            r.size.width = approximateCharWidth()
        } else if r.width <= 1 {
            r.size.width = approximateCharWidth()
        }
        return r
    }

    private func approximateCharWidth() -> CGFloat {
        guard let font else { return 8 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = ("M" as NSString).size(withAttributes: attributes)
        return size.width > 0 ? size.width : 8
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // /vim R (replace) mode — overwrite the character at the caret
        // rather than inserting, advancing the caret one position.
        if let vim = vimEngineProvider?(), vim.submode == .replace,
           let s = string as? String {
            overwriteText(s)
            return
        }

        guard let mode = currentModeProvider?() else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        if let s = string as? String {
            super.insertText(mode.apply(s), replacementRange: replacementRange)
        } else if let attr = string as? NSAttributedString {
            let transformed = NSAttributedString(string: mode.apply(attr.string))
            super.insertText(transformed, replacementRange: replacementRange)
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
    }

    private func overwriteText(_ s: String) {
        let ns = self.string as NSString
        let cursor = selectedRange.location
        // Don't overwrite newlines or extend past end of buffer.
        let canOverwrite = cursor < ns.length && ns.character(at: cursor) != 0x0A
        let range = canOverwrite
            ? NSRange(location: cursor, length: 1)
            : NSRange(location: cursor, length: 0)
        if shouldChangeText(in: range, replacementString: s) {
            replaceCharacters(in: range, with: s)
            didChangeText()
            let newLoc = cursor + (s as NSString).length
            setSelectedRange(NSRange(location: newLoc, length: 0))
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                pasteAsPlainText(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "e":
                openExternalHandler?()
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Enter and Option-Cmd-Enter
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            if event.modifierFlags.contains(.option) {
                openExternalHandler?()
            } else {
                submitHandler?()
            }
            return
        }

        // /vim mode owns the keyboard when active. Cmd-shortcuts (Cmd+V,
        // Cmd+Z, …) bypass this entirely because they're handled in
        // performKeyEquivalent earlier in the responder chain.
        if let vim = vimEngineProvider?() {
            let prevSubmode = vim.submode
            let handled = vim.handleKey(
                chars: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: KeyModifiers(event.modifierFlags),
                editor: self
            )
            if handled {
                // Mode flips (insert→normal, normal→insert, etc.) need an
                // explicit repaint because the cursor shape changes
                // without the caret necessarily moving.
                if prevSubmode != vim.submode {
                    invalidateBlockCursorArea()
                }
                return
            }
        }

        // When tag suggestions are showing, intercept navigation keys
        if isShowingTags?() == true {
            switch event.keyCode {
            case 125: // down arrow
                if tagKeyHandler?(.arrowDown) == true { return }
            case 126: // up arrow
                if tagKeyHandler?(.arrowUp) == true { return }
            case 36:  // enter/return
                if tagKeyHandler?(.enter) == true { return }
            case 48:  // tab
                if tagKeyHandler?(.tab) == true { return }
            case 53:  // escape
                if tagKeyHandler?(.escape) == true { return }
            default:
                break
            }
        }

        // When slash suggestions are showing, intercept the same keys
        // plus spacebar (49) for the exact-match commit path.
        if isShowingSlash?() == true {
            switch event.keyCode {
            case 125:
                if slashKeyHandler?(.arrowDown) == true { return }
            case 126:
                if slashKeyHandler?(.arrowUp) == true { return }
            case 36:
                if slashKeyHandler?(.enter) == true { return }
            case 48:
                if slashKeyHandler?(.tab) == true { return }
            case 53:
                if slashKeyHandler?(.escape) == true { return }
            case 49:
                if slashKeyHandler?(.space) == true { return }
            default:
                break
            }
        }

        super.keyDown(with: event)
    }
}
