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
        case arrowUp, arrowDown, arrowLeft, arrowRight, enter, escape, tab, space
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
        } else if vimActiveNow {
            // Ensure color is correct on every update while vim is active
            if let tv = textView as? JrnlTextView {
                tv.refreshCursorArea()
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

            // Handle downward renumbering if an ordered list item was deleted/merged.
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
            let line = nsString.substring(with: lineRange)
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let body = String(line.dropFirst(indent.count))

            if let kind = ListPrefix.detect(in: body), case .ordered(let n) = kind {
                renumberFollowing(in: textView, from: selection.location, expectedIndent: indent, startNumber: n + 1)
            }

            let tag = findTagPrefix(in: textView)
            parent.tagPrefix = tag
            parent.slashPrefix = tag.isEmpty ? findSlashPrefix(in: textView) : ""
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleNewline(in: textView)
            }
            return false
        }

        private func handleNewline(in textView: NSTextView) -> Bool {
            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            // Only smart-continue for a single insertion point (no selection).
            guard selection.length == 0 else { return false }

            let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
            let line = nsString.substring(with: lineRange)
            let lineNoNewline = line.hasSuffix("\n") ? String(line.dropLast()) : line

            let indent = String(lineNoNewline.prefix(while: { $0 == " " || $0 == "\t" }))
            let bodyAfterIndent = String(lineNoNewline.dropFirst(indent.count))

            guard let kind = ListPrefix.detect(in: bodyAfterIndent) else { return false }

            // Smart-continue fires when the caret is at or past the end of the
            // prefix on this line — including mid-line splits. Caret inside
            // the indent/prefix region falls through to the default newline.
            let prefixEnd = lineRange.location + (indent as NSString).length + kind.prefixLength
            guard selection.location >= prefixEnd else { return false }

            let trailing = String(bodyAfterIndent.dropFirst(kind.prefixLength))

            if trailing.isEmpty {
                // Empty list item — strip the indent + prefix to exit the list.
                let suffix = line.hasSuffix("\n") ? "\n" : ""
                let replacement = suffix
                let replaceRange = lineRange
                guard textView.shouldChangeText(in: replaceRange, replacementString: replacement) else {
                    return false
                }
                textView.replaceCharacters(in: replaceRange, with: replacement)
                textView.didChangeText()
                let newCaret = lineRange.location + (replacement as NSString).length
                textView.setSelectedRange(NSRange(location: newCaret, length: 0))

                if case .ordered(let n) = kind {
                    renumberFollowing(in: textView, from: newCaret, expectedIndent: indent, startNumber: n)
                }
                return true
            }

            let insertion = "\n" + kind.continuation(indent: indent)
            let insertRange = NSRange(location: selection.location, length: 0)
            guard textView.shouldChangeText(in: insertRange, replacementString: insertion) else {
                return false
            }
            textView.replaceCharacters(in: insertRange, with: insertion)
            textView.didChangeText()
            let newCaret = selection.location + (insertion as NSString).length
            textView.setSelectedRange(NSRange(location: newCaret, length: 0))

            if case .ordered(let n) = kind {
                renumberFollowing(in: textView, from: newCaret, expectedIndent: indent, startNumber: n + 2)
            }
            return true
        }

        private func renumberFollowing(in textView: NSTextView, from location: Int, expectedIndent: String, startNumber: Int) {
            var nextNumber = startNumber
            
            // 1. Skip the current line (the one containing 'location')
            let text = textView.string as NSString
            let currentLineRange = text.lineRange(for: NSRange(location: location, length: 0))
            var searchFrom = currentLineRange.location + currentLineRange.length

            // 2. Scan subsequent lines
            while true {
                let currentText = textView.string as NSString
                guard searchFrom < currentText.length else { break }

                let lineRange = currentText.lineRange(for: NSRange(location: searchFrom, length: 0))
                let line = currentText.substring(with: lineRange)
                
                // If the line is empty (just a newline), stop.
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }

                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                // If indentation doesn't match exactly, stop.
                guard indent == expectedIndent else { break }

                let body = String(line.dropFirst(indent.count))
                guard let kind = ListPrefix.detect(in: body),
                      case .ordered = kind else { 
                    // Not a list item at this indentation level, stop.
                    break 
                }

                let oldPrefixLength = kind.prefixLength
                let newPrefix = "\(nextNumber). "

                if body.prefix(oldPrefixLength) != newPrefix {
                    let replaceRange = NSRange(location: lineRange.location + indent.count, length: oldPrefixLength)
                    if textView.shouldChangeText(in: replaceRange, replacementString: newPrefix) {
                        textView.replaceCharacters(in: replaceRange, with: newPrefix)
                        textView.didChangeText()
                    }
                }

                // Advance to next line. Refresh length in case prefix changed length.
                nextNumber += 1
                let updatedText = textView.string as NSString
                let updatedLineRange = updatedText.lineRange(for: NSRange(location: lineRange.location, length: 0))
                searchFrom = updatedLineRange.location + updatedLineRange.length
            }
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
                } else if CharacterSet.newlines.contains(scalar) {
                    return ""
                } else {
                    // Allow alphanumerics, symbols, AND spaces in arguments
                    i -= 1
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

        // When vim is in a block-mode, we draw our own block and SKIP 
        // calling super. This is the only definitive way to prevent 
        // AppKit from drawing the standard vertical beam (which 
        // otherwise causes a "double cursor" artifact).
        if flag {
            var block = rect
            
            // Use character-specific bounding rect for height so the 
            // cursor doesn't include line spacing or paragraph leading 
            // (fixes the "too long" cursor on the jrnl title line).
            if let lm = layoutManager, let tc = textContainer {
                let ns = string as NSString
                let charIndex = min(max(0, selectedRange.location), ns.length)
                // If at the very end, we look at the glyph just before
                // the caret to find the correct height metrics.
                let lookupIndex = (charIndex >= ns.length && ns.length > 0) ? charIndex - 1 : charIndex
                let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: lookupIndex, length: 1), actualCharacterRange: nil)
                let charRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
                
                block.size.height = charRect.height
                block.origin.y = charRect.origin.y + textContainerOrigin.y
            }
            
            block.size.width = approximateCharWidth()
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.75).setFill()
            block.fill()
        }
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
           let primary = ranges.first?.rangeValue {
            scrollRangeToVisible(NSRange(location: primary.location, length: 0))
        }

        // Force a full redraw when vim is in a block-cursor submode so
        // the previous block position is reliably erased.
        if vim.submode != .insert {
            needsDisplay = true
        }
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

    /// Cmd shortcut handler. **Must gate on first responder.**
    /// `performKeyEquivalent` walks the entire view hierarchy and
    /// the first view that returns `true` claims the event. Without
    /// the gate, any JrnlTextView in the window snatches Cmd+V/C/X/A
    /// away from other focused text fields — harmless in jrnlbar
    /// today (single text input in the floating panel) but a real
    /// trap if this class is ever copied into a host with multiple
    /// text inputs. Defensive: pay one extra check now so the
    /// reference pattern stays safe to lift.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCurrentFirstResponder, event.modifierFlags.contains(.command)
        else { return super.performKeyEquivalent(with: event) }
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
        case ";":
            checkSpelling(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// True when this text view (via its field editor) actually owns
    /// keyboard focus in its window. NSTextView's `firstResponder`
    /// for an editable text view is typically the view itself, but
    /// the field-editor variant routes through the NSText delegate,
    /// so we check both.
    private var isCurrentFirstResponder: Bool {
        guard let fr = window?.firstResponder else { return false }
        if fr === self { return true }
        if let text = fr as? NSText, text.delegate === self { return true }
        return false
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
            case 123: // left arrow
                if tagKeyHandler?(.arrowLeft) == true { return }
            case 124: // right arrow
                if tagKeyHandler?(.arrowRight) == true { return }
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
            case 123:
                if slashKeyHandler?(.arrowLeft) == true { return }
            case 124:
                if slashKeyHandler?(.arrowRight) == true { return }
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
