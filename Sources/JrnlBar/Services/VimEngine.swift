import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Minimal interface VimEngine needs from the editor. NSTextView conforms
/// via an extension; tests use a small stub so engine logic can be
/// exercised without instantiating AppKit windows.
public protocol VimTextEditor: AnyObject {
    var text: String { get set }
    var selectedRange: NSRange { get set }
    func replace(in range: NSRange, with string: String)
    func vimUndo()
    func vimRedo()
    /// Returns the character offset after moving `lines` *visual* lines
    /// from `from`, preserving column. Negative `lines` moves up.
    /// Returns nil if the editor can't compute visual-line geometry
    /// (e.g. unit-test stubs without a layout manager) — callers should
    /// fall back to logical-line motion.
    func visualLineLocation(from: Int, lines: Int) -> Int?
}

extension VimTextEditor {
    public func visualLineLocation(from: Int, lines: Int) -> Int? { nil }
}

/// Subset of vim sufficient for "fast keyboard edits to a short
/// markdown entry without leaving the panel." Modes: normal, insert,
/// command-line. State machine driven by `handleKey`. See
/// `VimEngineTests` for the exhaustive behavior contract.
public final class VimEngine {
    public enum Submode: String {
        case normal, insert, command, replace, visual, visualLine, search
    }

    public private(set) var submode: Submode = .normal
    public private(set) var commandBuffer: String = ""

    public var onExit: (() -> Void)?
    public var onSubmit: (() -> Void)?
    public var onSubmodeChanged: (() -> Void)?
    public var onCommandBufferChanged: (() -> Void)?

    // Internal state — not part of the published surface.
    private var countBuffer: String = ""
    private var pendingOperator: PendingOperator?
    private var pendingOperatorCount: Int = 1
    private var pendingG: Bool = false
    private var pendingReplace: Bool = false
    private var pendingReplaceCount: Int = 1
    // r<char> and f/F/t/T are "pending-next-char" states.
    private var pendingFind: PendingFind?
    private var lastFind: (mode: PendingFind, char: Character)?
    // Yank/delete register. Linewise contents end with `\n` and paste
    // as new lines; characterwise paste inline at/after the caret.
    private var register: String = ""
    private var registerIsLine: Bool = false
    // Visual mode endpoints. anchor is fixed; cursor is the moving end.
    // We track cursor ourselves because once the selection has length,
    // editor.selectedRange.location always reports the lower bound.
    private var visualAnchor: Int = 0
    private var visualCursor: Int = 0
    // `.` repeat: closure recording the last text-mutating command,
    // replayed in the current editor when `.` is pressed.
    private var lastChange: ((VimTextEditor) -> Void)?
    // Search state for `/`, `n`, `N`.
    private var searchTerm: String = ""

    private enum PendingOperator {
        case delete
        case yank
        case change
    }

    /// Pending "next char" find mode set by f/F/t/T.
    public enum PendingFind: Hashable {
        case findForward      // f<x> — land on the char
        case findBackward     // F<x> — backward, land on the char
        case tilForward       // t<x> — land one before the char
        case tilBackward      // T<x> — backward, land one after the char
    }

    private enum Motion {
        case left, right, up, down
        case wordForward, wordBackward, wordEnd, previousWordEnd
        // Uppercase WORD variants (whitespace-only separators).
        case bigWordForward, bigWordBackward, bigWordEnd
        case lineStart, lineEnd, lineFirstNonBlank
        case bufferStart, bufferEnd
        case paragraphForward, paragraphBackward
        case matchingBracket
    }

    public init() {}

    /// Apex entry point — feed a single keyDown's normalized characters
    /// plus modifier flags. Returns true if the engine consumed it.
    /// `chars` should be `event.charactersIgnoringModifiers` and
    /// `keyCode` the raw keyCode (used for Esc/Enter/Backspace).
    @discardableResult
    public func handleKey(
        chars: String?,
        keyCode: UInt16,
        modifiers: KeyModifiers,
        editor: VimTextEditor
    ) -> Bool {
        switch submode {
        case .normal: return handleNormal(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        case .insert: return handleInsert(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        case .command: return handleCommand(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        case .replace: return handleReplace(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        case .visual, .visualLine:
            return handleVisual(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        case .search: return handleSearch(chars: chars, keyCode: keyCode, modifiers: modifiers, editor: editor)
        }
    }

    /// What the mode badge in the submit bar should display.
    public var badge: String {
        switch submode {
        case .normal: return "VIM:N"
        case .insert: return "VIM:I"
        case .command: return ":\(commandBuffer)"
        case .replace: return "VIM:R"
        case .visual: return "VIM:V"
        case .visualLine: return "VIM:VL"
        case .search: return "/\(searchTerm)"
        }
    }

    // MARK: - Normal mode

    private func handleNormal(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        // Ctrl-r = redo (must check before pendingReplace, which would
        // otherwise consume the 'r').
        if modifiers.contains(.control), chars == "r" {
            editor.vimRedo()
            resetTransient()
            return true
        }

        // r<char> awaiting its replacement character. Esc cancels.
        if pendingReplace {
            pendingReplace = false
            let n = pendingReplaceCount
            pendingReplaceCount = 1
            if keyCode == 53 { return true }
            guard let chars, chars.count == 1 else { return true }
            let captured = chars
            replaceCharAtCaret(with: captured, count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.replaceCharAtCaret(with: captured, count: n, editor: ed)
            }
            return true
        }

        // f/F/t/T awaiting their target character.
        if let mode = pendingFind {
            pendingFind = nil
            if keyCode == 53 { return true }  // Esc cancels
            guard let chars, chars.count == 1, let target = chars.first else { return true }
            lastFind = (mode: mode, char: target)
            performFind(mode: mode, target: target, count: 1, editor: editor)
            return true
        }

        // Esc clears any pending operator/count without changing mode.
        if keyCode == 53 {
            resetTransient()
            return true
        }

        // Arrow keys: map to h/j/k/l so users who instinctively reach
        // for them aren't stuck. Respects any pending count.
        let arrowCount = max(1, Int(countBuffer) ?? 1)
        switch keyCode {
        case 123: applyMotion(.left,  count: arrowCount, editor: editor); countBuffer = ""; return true
        case 124: applyMotion(.right, count: arrowCount, editor: editor); countBuffer = ""; return true
        case 125: applyMotion(.down,  count: arrowCount, editor: editor); countBuffer = ""; return true
        case 126: applyMotion(.up,    count: arrowCount, editor: editor); countBuffer = ""; return true
        default: break
        }

        guard let chars, chars.count == 1 else {
            return false
        }
        let c = Character(chars)

        // Count digits (0 is also a motion if no count is in progress).
        if c.isASCII, c.isNumber {
            if c == "0" && countBuffer.isEmpty {
                applyMotion(.lineStart, count: 1, editor: editor)
                return true
            }
            countBuffer.append(c)
            return true
        }

        let n = max(1, Int(countBuffer) ?? 1)
        countBuffer = ""

        if let op = pendingOperator {
            handleOperator(op, motionChar: c, count: pendingOperatorCount * n, editor: editor)
            pendingOperator = nil
            pendingOperatorCount = 1
            return true
        }

        if pendingG {
            pendingG = false
            switch c {
            case "g": applyMotion(.bufferStart, count: 1, editor: editor)
            case "e": applyMotion(.previousWordEnd, count: 1, editor: editor)
            default: break
            }
            return true
        }

        switch c {
        case "h": applyMotion(.left, count: n, editor: editor)
        case "j": applyMotion(.down, count: n, editor: editor)
        case "k": applyMotion(.up, count: n, editor: editor)
        case "l": applyMotion(.right, count: n, editor: editor)
        case "w": applyMotion(.wordForward, count: n, editor: editor)
        case "b": applyMotion(.wordBackward, count: n, editor: editor)
        case "e": applyMotion(.wordEnd, count: n, editor: editor)
        case "W": applyMotion(.bigWordForward, count: n, editor: editor)
        case "B": applyMotion(.bigWordBackward, count: n, editor: editor)
        case "E": applyMotion(.bigWordEnd, count: n, editor: editor)
        case "$": applyMotion(.lineEnd, count: 1, editor: editor)
        case "^": applyMotion(.lineFirstNonBlank, count: 1, editor: editor)
        case "{": applyMotion(.paragraphBackward, count: n, editor: editor)
        case "}": applyMotion(.paragraphForward, count: n, editor: editor)
        case "%": applyMotion(.matchingBracket, count: 1, editor: editor)
        case "~":
            toggleCaseAtCaret(count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.toggleCaseAtCaret(count: n, editor: ed)
            }
        case "G": applyMotion(.bufferEnd, count: 1, editor: editor)
        case "g": pendingG = true
        case "i":
            setSubmode(.insert)
        case "a":
            applyMotion(.right, count: 1, editor: editor)
            setSubmode(.insert)
        case "I":
            applyMotion(.lineFirstNonBlank, count: 1, editor: editor)
            setSubmode(.insert)
        case "A":
            applyMotion(.lineEnd, count: 1, editor: editor)
            setSubmode(.insert)
        case "o":
            openLine(below: true, editor: editor)
            setSubmode(.insert)
        case "O":
            openLine(below: false, editor: editor)
            setSubmode(.insert)
        case "x":
            deleteCharAtCaret(count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.deleteCharAtCaret(count: n, editor: ed)
            }
        case "d":
            pendingOperator = .delete
            pendingOperatorCount = n
        case "y":
            pendingOperator = .yank
            pendingOperatorCount = n
        case "c":
            pendingOperator = .change
            pendingOperatorCount = n
        case "C":
            deleteOverMotion(.lineEnd, count: n, editor: editor)
            setSubmode(.insert)
            recordChange { [weak self] ed in
                self?.deleteOverMotion(.lineEnd, count: n, editor: ed)
            }
        case "D":
            deleteOverMotion(.lineEnd, count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.deleteOverMotion(.lineEnd, count: n, editor: ed)
            }
        case "s":
            deleteCharAtCaret(count: n, editor: editor)
            setSubmode(.insert)
            recordChange { [weak self] ed in
                self?.deleteCharAtCaret(count: n, editor: ed)
            }
        case "r":
            pendingReplace = true
            pendingReplaceCount = n
        case "R":
            setSubmode(.replace)
        case "p":
            paste(after: true, count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.paste(after: true, count: n, editor: ed)
            }
        case "P":
            paste(after: false, count: n, editor: editor)
            recordChange { [weak self] ed in
                self?.paste(after: false, count: n, editor: ed)
            }
        case "v":
            let pos = editor.selectedRange.location
            visualAnchor = pos
            visualCursor = pos
            setSubmode(.visual)
            applyVisualSelection(editor)
        case "V":
            let pos = editor.selectedRange.location
            visualAnchor = pos
            visualCursor = pos
            setSubmode(.visualLine)
            applyVisualSelection(editor)
        case "/":
            searchTerm = ""
            setSubmode(.search)
            onCommandBufferChanged?()
        case "n":
            if !searchTerm.isEmpty {
                jumpToSearch(forward: true, count: n, editor: editor)
            }
        case "N":
            if !searchTerm.isEmpty {
                jumpToSearch(forward: false, count: n, editor: editor)
            }
        case "f":
            pendingFind = .findForward
        case "F":
            pendingFind = .findBackward
        case "t":
            pendingFind = .tilForward
        case "T":
            pendingFind = .tilBackward
        case ";":
            if let last = lastFind {
                performFind(mode: last.mode, target: last.char, count: n, editor: editor)
            }
        case ",":
            if let last = lastFind {
                performFind(mode: reverseFind(last.mode), target: last.char, count: n, editor: editor)
            }
        case ".":
            lastChange?(editor)
        case "u":
            editor.vimUndo()
        case ":":
            commandBuffer = ""
            setSubmode(.command)
            onCommandBufferChanged?()
        default:
            // Consume silently — feels less broken than letting unknown
            // characters land in the buffer.
            break
        }
        return true
    }

    private func handleOperator(_ op: PendingOperator, motionChar: Character, count: Int, editor: VimTextEditor) {
        switch op {
        case .delete:
            if motionChar == "d" {
                deleteLines(count: count, editor: editor)
                recordChange { [weak self] ed in self?.deleteLines(count: count, editor: ed) }
            } else if let motion = motionFor(motionChar) {
                deleteOverMotion(motion, count: count, editor: editor)
                recordChange { [weak self] ed in self?.deleteOverMotion(motion, count: count, editor: ed) }
            }
        case .yank:
            // Yank is not a "change" — don't record for `.`.
            if motionChar == "y" {
                yankLines(count: count, editor: editor)
            } else if let motion = motionFor(motionChar) {
                yankOverMotion(motion, count: count, editor: editor)
            }
        case .change:
            if motionChar == "c" {
                changeLines(count: count, editor: editor)
                recordChange { [weak self] ed in self?.changeLines(count: count, editor: ed) }
            } else if let motion = motionFor(motionChar) {
                deleteOverMotion(motion, count: count, editor: editor)
                setSubmode(.insert)
                recordChange { [weak self] ed in
                    self?.deleteOverMotion(motion, count: count, editor: ed)
                }
            }
        }
    }

    private func motionFor(_ c: Character) -> Motion? {
        switch c {
        case "w": return .wordForward
        case "b": return .wordBackward
        case "e": return .wordEnd
        case "W": return .bigWordForward
        case "B": return .bigWordBackward
        case "E": return .bigWordEnd
        case "$": return .lineEnd
        case "0": return .lineStart
        case "^": return .lineFirstNonBlank
        case "h": return .left
        case "l": return .right
        case "{": return .paragraphBackward
        case "}": return .paragraphForward
        case "%": return .matchingBracket
        default: return nil
        }
    }

    /// Inclusive motions include the destination character in operator
    /// ranges (e.g. `de` deletes through and including the end of word).
    /// Exclusive motions stop one short.
    private func isInclusiveMotion(_ motion: Motion) -> Bool {
        switch motion {
        case .wordEnd, .previousWordEnd, .bigWordEnd, .matchingBracket: return true
        default: return false
        }
    }

    // MARK: - Insert mode

    private func handleInsert(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        if keyCode == 53 {  // Escape
            setSubmode(.normal)
            return true
        }
        return false
    }

    // MARK: - Replace (R) mode

    private func handleReplace(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        // Esc returns to normal; everything else falls through to the
        // text view, where insertText overwrites the character at the
        // caret rather than inserting.
        if keyCode == 53 {
            setSubmode(.normal)
            return true
        }
        return false
    }

    // MARK: - Visual mode

    private func handleVisual(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        // Esc cancels visual without operating.
        if keyCode == 53 {
            collapseVisual(editor)
            setSubmode(.normal)
            return true
        }

        // Arrow keys: same as h/j/k/l in visual mode.
        switch keyCode {
        case 123: applyVisualMotion(.left, count: 1, editor: editor); return true
        case 124: applyVisualMotion(.right, count: 1, editor: editor); return true
        case 125: applyVisualMotion(.down, count: 1, editor: editor); return true
        case 126: applyVisualMotion(.up, count: 1, editor: editor); return true
        default: break
        }

        guard let chars, chars.count == 1, let c = chars.first else { return true }

        // Count digits.
        if c.isASCII, c.isNumber {
            if c == "0" && countBuffer.isEmpty {
                applyVisualMotion(.lineStart, count: 1, editor: editor)
                return true
            }
            countBuffer.append(c)
            return true
        }

        let n = max(1, Int(countBuffer) ?? 1)
        countBuffer = ""

        // Pending `g` for `gg` / `ge`.
        if pendingG {
            pendingG = false
            switch c {
            case "g": applyVisualMotion(.bufferStart, count: 1, editor: editor)
            case "e": applyVisualMotion(.previousWordEnd, count: 1, editor: editor)
            default: break
            }
            return true
        }

        switch c {
        // Movement — extends the selection.
        case "h": applyVisualMotion(.left, count: n, editor: editor)
        case "j": applyVisualMotion(.down, count: n, editor: editor)
        case "k": applyVisualMotion(.up, count: n, editor: editor)
        case "l": applyVisualMotion(.right, count: n, editor: editor)
        case "w": applyVisualMotion(.wordForward, count: n, editor: editor)
        case "b": applyVisualMotion(.wordBackward, count: n, editor: editor)
        case "e": applyVisualMotion(.wordEnd, count: n, editor: editor)
        case "W": applyVisualMotion(.bigWordForward, count: n, editor: editor)
        case "B": applyVisualMotion(.bigWordBackward, count: n, editor: editor)
        case "E": applyVisualMotion(.bigWordEnd, count: n, editor: editor)
        case "g": pendingG = true
        case "G": applyVisualMotion(.bufferEnd, count: 1, editor: editor)
        case "0": applyVisualMotion(.lineStart, count: 1, editor: editor)
        case "^": applyVisualMotion(.lineFirstNonBlank, count: 1, editor: editor)
        case "$": applyVisualMotion(.lineEnd, count: 1, editor: editor)
        case "{": applyVisualMotion(.paragraphBackward, count: n, editor: editor)
        case "}": applyVisualMotion(.paragraphForward, count: n, editor: editor)
        case "%": applyVisualMotion(.matchingBracket, count: 1, editor: editor)

        // Operators — apply to the current selection.
        case "d", "x":
            deleteSelection(editor)
            setSubmode(.normal)
        case "y":
            yankSelection(editor)
            collapseVisual(editor)
            setSubmode(.normal)
        case "c":
            deleteSelection(editor)
            setSubmode(.insert)
        case "v":
            // Toggle out of charwise visual.
            if submode == .visual {
                collapseVisual(editor)
                setSubmode(.normal)
            } else {
                setSubmode(.visual)
                applyVisualSelection(editor)
            }
        case "V":
            // Toggle linewise visual.
            if submode == .visualLine {
                collapseVisual(editor)
                setSubmode(.normal)
            } else {
                setSubmode(.visualLine)
                applyVisualSelection(editor)
            }
        case ":":
            // Allow leaving visual into command mode; rare but useful.
            collapseVisual(editor)
            commandBuffer = ""
            setSubmode(.command)
            onCommandBufferChanged?()
        default:
            break
        }
        return true
    }

    private func applyVisualMotion(_ motion: Motion, count: Int, editor: VimTextEditor) {
        let newLoc: Int
        if motion == .down, let target = editor.visualLineLocation(from: visualCursor, lines: count) {
            newLoc = target
        } else if motion == .up, let target = editor.visualLineLocation(from: visualCursor, lines: -count) {
            newLoc = target
        } else {
            newLoc = computeMotion(motion, count: count, text: editor.text, from: visualCursor)
        }
        visualCursor = newLoc
        applyVisualSelection(editor)
    }

    private func applyVisualSelection(_ editor: VimTextEditor) {
        let ns = editor.text as NSString
        let length = ns.length
        guard length > 0 else { return }

        let lo = min(visualAnchor, visualCursor)
        let hiInclusive = min(max(visualAnchor, visualCursor), length - 1)

        if submode == .visualLine {
            let firstLineStart = lineStart(in: ns, of: lo)
            let lastLineEnd = lineEnd(in: ns, of: hiInclusive)
            let endIncludingNewline = min(length, lastLineEnd + 1)
            editor.selectedRange = NSRange(location: firstLineStart, length: endIncludingNewline - firstLineStart)
        } else {
            let inclusiveEnd = min(length, hiInclusive + 1)
            editor.selectedRange = NSRange(location: lo, length: max(0, inclusiveEnd - lo))
        }
    }

    private func collapseVisual(_ editor: VimTextEditor) {
        // Land at the moving end (where the user has been "looking").
        editor.selectedRange = NSRange(location: visualCursor, length: 0)
    }

    private func deleteSelection(_ editor: VimTextEditor) {
        let sel = editor.selectedRange
        guard sel.length > 0 else { return }
        let ns = editor.text as NSString
        register = ns.substring(with: sel)
        registerIsLine = (submode == .visualLine)
        editor.replace(in: sel, with: "")
        editor.selectedRange = NSRange(location: sel.location, length: 0)
        recordChange { [weak self] ed in
            // The replay applies starting at the current caret, deleting
            // a region of the same length. Not perfect (vim's visual
            // replay re-selects), but useful for the common case.
            guard let self else { return }
            let len = (self.register as NSString).length
            let start = ed.selectedRange.location
            let edEnd = min((ed.text as NSString).length, start + len)
            ed.replace(in: NSRange(location: start, length: edEnd - start), with: "")
        }
    }

    private func yankSelection(_ editor: VimTextEditor) {
        let sel = editor.selectedRange
        guard sel.length > 0 else { return }
        register = (editor.text as NSString).substring(with: sel)
        registerIsLine = (submode == .visualLine)
    }

    // MARK: - Search (/, n, N)

    private func handleSearch(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        if keyCode == 53 {  // Escape — cancel
            searchTerm = ""
            onCommandBufferChanged?()
            setSubmode(.normal)
            return true
        }
        if keyCode == 36 {  // Enter — execute
            setSubmode(.normal)
            if !searchTerm.isEmpty {
                jumpToSearch(forward: true, count: 1, editor: editor)
            }
            return true
        }
        if keyCode == 51 {  // Backspace
            if searchTerm.isEmpty {
                setSubmode(.normal)
            } else {
                searchTerm.removeLast()
                onCommandBufferChanged?()
            }
            return true
        }
        if let chars, chars.count == 1, let c = chars.first, c.isASCII {
            searchTerm.append(c)
            onCommandBufferChanged?()
        }
        return true
    }

    private func jumpToSearch(forward: Bool, count: Int, editor: VimTextEditor) {
        guard !searchTerm.isEmpty else { return }
        let ns = editor.text as NSString
        let length = ns.length
        guard length > 0 else { return }

        var pos = editor.selectedRange.location
        for _ in 0..<count {
            let next = forward
                ? nextOccurrence(of: searchTerm, in: ns, after: pos)
                : previousOccurrence(of: searchTerm, in: ns, before: pos)
            guard let landing = next else { return }
            pos = landing
        }
        editor.selectedRange = NSRange(location: pos, length: 0)
    }

    private func nextOccurrence(of term: String, in text: NSString, after pos: Int) -> Int? {
        let length = text.length
        if length == 0 { return nil }
        // Search from pos+1 to end, wrapping to start.
        let start = min(pos + 1, length)
        let firstHalf = text.range(of: term, options: [], range: NSRange(location: start, length: length - start))
        if firstHalf.location != NSNotFound { return firstHalf.location }
        let secondHalf = text.range(of: term, options: [], range: NSRange(location: 0, length: max(0, start)))
        if secondHalf.location != NSNotFound { return secondHalf.location }
        return nil
    }

    private func previousOccurrence(of term: String, in text: NSString, before pos: Int) -> Int? {
        let length = text.length
        if length == 0 { return nil }
        // Search up to pos backward; if none, wrap from end.
        let firstHalf = text.range(of: term, options: [.backwards], range: NSRange(location: 0, length: max(0, pos)))
        if firstHalf.location != NSNotFound { return firstHalf.location }
        let secondHalf = text.range(of: term, options: [.backwards], range: NSRange(location: pos, length: length - pos))
        if secondHalf.location != NSNotFound { return secondHalf.location }
        return nil
    }

    // MARK: - Find (f/F/t/T)

    private func performFind(mode: PendingFind, target: Character, count: Int, editor: VimTextEditor) {
        let ns = editor.text as NSString
        let length = ns.length
        guard length > 0 else { return }
        let cursor = editor.selectedRange.location
        let line = (
            start: lineStart(in: ns, of: cursor),
            end: lineEnd(in: ns, of: cursor)
        )
        var pos = cursor
        for _ in 0..<count {
            let nextPos: Int?
            switch mode {
            case .findForward:
                nextPos = findCharForward(target, in: ns, from: pos + 1, lineEnd: line.end)
            case .findBackward:
                nextPos = findCharBackward(target, in: ns, from: pos - 1, lineStart: line.start)
            case .tilForward:
                if let hit = findCharForward(target, in: ns, from: pos + 2, lineEnd: line.end) {
                    nextPos = hit - 1
                } else {
                    nextPos = nil
                }
            case .tilBackward:
                if let hit = findCharBackward(target, in: ns, from: pos - 2, lineStart: line.start) {
                    nextPos = hit + 1
                } else {
                    nextPos = nil
                }
            }
            guard let landing = nextPos else { return }
            pos = landing
        }
        editor.selectedRange = NSRange(location: pos, length: 0)
    }

    private func findCharForward(_ target: Character, in text: NSString, from start: Int, lineEnd: Int) -> Int? {
        var i = max(0, start)
        while i < min(text.length, lineEnd) {
            if let scalar = Unicode.Scalar(text.character(at: i)), Character(scalar) == target {
                return i
            }
            i += 1
        }
        return nil
    }

    private func findCharBackward(_ target: Character, in text: NSString, from start: Int, lineStart: Int) -> Int? {
        var i = min(text.length - 1, start)
        while i >= lineStart {
            if let scalar = Unicode.Scalar(text.character(at: i)), Character(scalar) == target {
                return i
            }
            i -= 1
        }
        return nil
    }

    private func reverseFind(_ mode: PendingFind) -> PendingFind {
        switch mode {
        case .findForward: return .findBackward
        case .findBackward: return .findForward
        case .tilForward: return .tilBackward
        case .tilBackward: return .tilForward
        }
    }

    // MARK: - Change recording (.)

    private func recordChange(_ action: @escaping (VimTextEditor) -> Void) {
        lastChange = action
    }

    // MARK: - Command mode

    private func handleCommand(chars: String?, keyCode: UInt16, modifiers: KeyModifiers, editor: VimTextEditor) -> Bool {
        if keyCode == 53 {  // Escape
            commandBuffer = ""
            onCommandBufferChanged?()
            setSubmode(.normal)
            return true
        }
        if keyCode == 36 {  // Enter
            executeCommand(commandBuffer.lowercased(), editor: editor)
            commandBuffer = ""
            onCommandBufferChanged?()
            return true
        }
        if keyCode == 51 {  // Backspace
            if commandBuffer.isEmpty {
                setSubmode(.normal)
            } else {
                commandBuffer.removeLast()
                onCommandBufferChanged?()
            }
            return true
        }
        if let chars, chars.count == 1, let c = chars.first, c.isASCII {
            commandBuffer.append(c)
            onCommandBufferChanged?()
        }
        return true
    }

    private func executeCommand(_ cmd: String, editor: VimTextEditor) {
        switch cmd {
        case "q", "vim":
            setSubmode(.normal)
            onExit?()
        case "w":
            onSubmit?()
            setSubmode(.normal)
        case "wq":
            onSubmit?()
            setSubmode(.normal)
            onExit?()
        default:
            setSubmode(.normal)
        }
    }

    // MARK: - State helpers

    private func setSubmode(_ new: Submode) {
        guard submode != new else { return }
        submode = new
        onSubmodeChanged?()
    }

    private func resetTransient() {
        countBuffer = ""
        pendingOperator = nil
        pendingOperatorCount = 1
        pendingG = false
        pendingReplace = false
        pendingReplaceCount = 1
        pendingFind = nil
    }

    // MARK: - Motion application

    private func applyMotion(_ motion: Motion, count: Int, editor: VimTextEditor) {
        let cursor = editor.selectedRange.location
        // j/k prefer visual-line motion (matches what the user sees in
        // the wrapped editor). Falls back to logical-line motion when
        // the editor can't compute visual lines.
        if motion == .down, let target = editor.visualLineLocation(from: cursor, lines: count) {
            editor.selectedRange = NSRange(location: target, length: 0)
            return
        }
        if motion == .up, let target = editor.visualLineLocation(from: cursor, lines: -count) {
            editor.selectedRange = NSRange(location: target, length: 0)
            return
        }
        let newLoc = computeMotion(motion, count: count, text: editor.text, from: cursor)
        editor.selectedRange = NSRange(location: newLoc, length: 0)
    }

    private func computeMotion(_ motion: Motion, count: Int, text: String, from cursor: Int) -> Int {
        let nsText = text as NSString
        let len = nsText.length

        switch motion {
        case .left:
            return max(0, cursor - count)
        case .right:
            return min(len, cursor + count)
        case .up:
            return moveByLines(text: nsText, from: cursor, delta: -count)
        case .down:
            return moveByLines(text: nsText, from: cursor, delta: count)
        case .wordForward:
            var loc = cursor
            for _ in 0..<count { loc = nextWordStart(in: nsText, from: loc) }
            return loc
        case .wordBackward:
            var loc = cursor
            for _ in 0..<count { loc = previousWordStart(in: nsText, from: loc) }
            return loc
        case .wordEnd:
            var loc = cursor
            for _ in 0..<count { loc = nextWordEnd(in: nsText, from: loc) }
            return loc
        case .previousWordEnd:
            var loc = cursor
            for _ in 0..<count { loc = previousWordEnd(in: nsText, from: loc) }
            return loc
        case .bigWordForward:
            var loc = cursor
            for _ in 0..<count { loc = nextBigWordStart(in: nsText, from: loc) }
            return loc
        case .bigWordBackward:
            var loc = cursor
            for _ in 0..<count { loc = previousBigWordStart(in: nsText, from: loc) }
            return loc
        case .bigWordEnd:
            var loc = cursor
            for _ in 0..<count { loc = nextBigWordEnd(in: nsText, from: loc) }
            return loc
        case .paragraphForward:
            var loc = cursor
            for _ in 0..<count { loc = nextParagraph(in: nsText, from: loc) }
            return loc
        case .paragraphBackward:
            var loc = cursor
            for _ in 0..<count { loc = previousParagraph(in: nsText, from: loc) }
            return loc
        case .matchingBracket:
            return matchingBracketLocation(in: nsText, from: cursor) ?? cursor
        case .lineStart:
            return lineStart(in: nsText, of: cursor)
        case .lineEnd:
            return lineEnd(in: nsText, of: cursor)
        case .lineFirstNonBlank:
            return lineFirstNonBlank(in: nsText, of: cursor)
        case .bufferStart:
            return 0
        case .bufferEnd:
            return len
        }
    }

    // MARK: - Mutations

    private func openLine(below: Bool, editor: VimTextEditor) {
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        if below {
            let end = lineEnd(in: nsText, of: cursor)
            editor.replace(in: NSRange(location: end, length: 0), with: "\n")
            editor.selectedRange = NSRange(location: end + 1, length: 0)
        } else {
            let start = lineStart(in: nsText, of: cursor)
            editor.replace(in: NSRange(location: start, length: 0), with: "\n")
            editor.selectedRange = NSRange(location: start, length: 0)
        }
    }

    private func deleteCharAtCaret(count: Int, editor: VimTextEditor) {
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        let end = min(nsText.length, cursor + count)
        guard end > cursor else { return }
        editor.replace(in: NSRange(location: cursor, length: end - cursor), with: "")
        editor.selectedRange = NSRange(location: min(cursor, max(0, (editor.text as NSString).length - 1)), length: 0)
    }

    private func replaceCharAtCaret(with newChar: String, count: Int, editor: VimTextEditor) {
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        let end = min(nsText.length, cursor + count)
        guard end > cursor else { return }
        let replacement = String(repeating: newChar, count: end - cursor)
        editor.replace(in: NSRange(location: cursor, length: end - cursor), with: replacement)
        // Vim leaves the caret on the last replaced character.
        editor.selectedRange = NSRange(location: max(cursor, end - 1), length: 0)
    }

    private func deleteLines(count: Int, editor: VimTextEditor) {
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        let start = lineStart(in: nsText, of: cursor)
        var end = start
        for _ in 0..<count {
            let lineEnd = self.lineEnd(in: editor.text as NSString, of: end)
            // include trailing newline if present (so the line is fully removed)
            end = min((editor.text as NSString).length, lineEnd + 1)
        }
        register = nsText.substring(with: NSRange(location: start, length: end - start))
        registerIsLine = true
        editor.replace(in: NSRange(location: start, length: end - start), with: "")
        let newLen = (editor.text as NSString).length
        editor.selectedRange = NSRange(location: min(start, newLen), length: 0)
    }

    private func deleteOverMotion(_ motion: Motion, count: Int, editor: VimTextEditor) {
        let from = editor.selectedRange.location
        let to = computeMotion(motion, count: count, text: editor.text, from: from)
        let lo = min(from, to)
        var hi = max(from, to)
        if isInclusiveMotion(motion) {
            hi = min(hi + 1, (editor.text as NSString).length)
        }
        guard hi > lo else { return }
        register = (editor.text as NSString).substring(with: NSRange(location: lo, length: hi - lo))
        registerIsLine = false
        editor.replace(in: NSRange(location: lo, length: hi - lo), with: "")
        editor.selectedRange = NSRange(location: lo, length: 0)
    }

    private func changeLines(count: Int, editor: VimTextEditor) {
        // `cc` empties the current line(s) but leaves the line itself
        // behind so insert mode lands on a (now-blank) line. The yank
        // register receives the deleted content, linewise.
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        let start = lineStart(in: nsText, of: cursor)
        var end = start
        for i in 0..<count {
            end = lineEnd(in: editor.text as NSString, of: end)
            if i < count - 1 {
                end = min((editor.text as NSString).length, end + 1)
            }
        }
        register = nsText.substring(with: NSRange(location: start, length: end - start))
        registerIsLine = true
        editor.replace(in: NSRange(location: start, length: end - start), with: "")
        editor.selectedRange = NSRange(location: start, length: 0)
        setSubmode(.insert)
    }

    private func yankLines(count: Int, editor: VimTextEditor) {
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location
        let start = lineStart(in: nsText, of: cursor)
        var end = start
        for _ in 0..<count {
            let lineEnd = self.lineEnd(in: nsText, of: end)
            end = min(nsText.length, lineEnd + 1)
        }
        register = nsText.substring(with: NSRange(location: start, length: end - start))
        registerIsLine = true
    }

    private func yankOverMotion(_ motion: Motion, count: Int, editor: VimTextEditor) {
        let from = editor.selectedRange.location
        let to = computeMotion(motion, count: count, text: editor.text, from: from)
        let lo = min(from, to)
        var hi = max(from, to)
        if isInclusiveMotion(motion) {
            hi = min(hi + 1, (editor.text as NSString).length)
        }
        guard hi > lo else { return }
        register = (editor.text as NSString).substring(with: NSRange(location: lo, length: hi - lo))
        registerIsLine = false
    }

    private func paste(after: Bool, count: Int, editor: VimTextEditor) {
        guard !register.isEmpty else { return }
        let content = String(repeating: register, count: count)
        let nsText = editor.text as NSString
        let cursor = editor.selectedRange.location

        if registerIsLine {
            let curLineEnd = lineEnd(in: nsText, of: cursor)
            let hasTrailingNewline = curLineEnd < nsText.length

            if after {
                if hasTrailingNewline {
                    // Insert just past the existing newline; ensure pasted
                    // content ends with \n so what's after stays on its line.
                    let insertAt = curLineEnd + 1
                    let body = content.hasSuffix("\n") ? content : content + "\n"
                    editor.replace(in: NSRange(location: insertAt, length: 0), with: body)
                    let newText = editor.text as NSString
                    editor.selectedRange = NSRange(location: lineFirstNonBlank(in: newText, of: insertAt), length: 0)
                } else {
                    // End-of-buffer with no trailing newline. Prepend \n
                    // as a separator; don't append one (we're at EOF).
                    let insertAt = curLineEnd
                    let stripped = content.hasSuffix("\n") ? String(content.dropLast()) : content
                    let body = "\n" + stripped
                    editor.replace(in: NSRange(location: insertAt, length: 0), with: body)
                    let newText = editor.text as NSString
                    editor.selectedRange = NSRange(location: lineFirstNonBlank(in: newText, of: insertAt + 1), length: 0)
                }
            } else {
                // P: insert as a new line above. Ensure trailing \n so the
                // existing line stays distinct.
                let insertAt = lineStart(in: nsText, of: cursor)
                let body = content.hasSuffix("\n") ? content : content + "\n"
                editor.replace(in: NSRange(location: insertAt, length: 0), with: body)
                let newText = editor.text as NSString
                editor.selectedRange = NSRange(location: lineFirstNonBlank(in: newText, of: insertAt), length: 0)
            }
        } else {
            let insertAt = after ? min(nsText.length, cursor + 1) : cursor
            editor.replace(in: NSRange(location: insertAt, length: 0), with: content)
            let contentLen = (content as NSString).length
            // Vim leaves the caret on the last character of the pasted text.
            editor.selectedRange = NSRange(location: max(insertAt, insertAt + contentLen - 1), length: 0)
        }
    }

    // MARK: - Line helpers

    private func lineStart(in text: NSString, of location: Int) -> Int {
        var i = min(location, text.length)
        while i > 0, text.character(at: i - 1) != 0x0A {
            i -= 1
        }
        return i
    }

    private func lineEnd(in text: NSString, of location: Int) -> Int {
        var i = min(location, text.length)
        while i < text.length, text.character(at: i) != 0x0A {
            i += 1
        }
        return i
    }

    private func lineFirstNonBlank(in text: NSString, of location: Int) -> Int {
        let start = lineStart(in: text, of: location)
        var i = start
        while i < text.length {
            let c = text.character(at: i)
            if c == 0x20 || c == 0x09 { i += 1 } else { break }  // space, tab
        }
        // If line is all whitespace, return its start.
        let curLineEnd = lineEnd(in: text, of: start)
        return i >= curLineEnd ? start : i
    }

    private func moveByLines(text: NSString, from cursor: Int, delta: Int) -> Int {
        // Preserve column. Vim default; good enough for v1.
        let curLineStart = lineStart(in: text, of: cursor)
        let column = cursor - curLineStart
        var lineStartLoc = curLineStart
        var step = delta
        while step != 0 {
            if step > 0 {
                let nextLineStart = lineEnd(in: text, of: lineStartLoc) + 1
                if nextLineStart > text.length { break }
                lineStartLoc = nextLineStart
                step -= 1
            } else {
                if lineStartLoc == 0 { break }
                lineStartLoc = lineStart(in: text, of: lineStartLoc - 1)
                step += 1
            }
        }
        let targetLineEnd = lineEnd(in: text, of: lineStartLoc)
        return min(lineStartLoc + column, targetLineEnd)
    }

    // MARK: - Word helpers (simplified vim semantics)

    /// `w` — move to start of next word.
    private func nextWordStart(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        let len = text.length
        // Skip current word (letters/digits/_) if any.
        while i < len, isWordCharacter(text.character(at: i)) { i += 1 }
        // Skip whitespace + punctuation to next word start.
        while i < len, !isWordCharacter(text.character(at: i)) { i += 1 }
        return i
    }

    /// `b` — move to start of previous word.
    private func previousWordStart(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        if i > 0 { i -= 1 }
        // Skip whitespace + punctuation backwards.
        while i > 0, !isWordCharacter(text.character(at: i)) { i -= 1 }
        // Walk to start of this word.
        while i > 0, isWordCharacter(text.character(at: i - 1)) { i -= 1 }
        return i
    }

    /// `e` — move to end of current (or next) word.
    private func nextWordEnd(in text: NSString, from cursor: Int) -> Int {
        let len = text.length
        var i = cursor
        if i >= len { return len }
        i += 1
        // Step past non-word chars to land inside the next word.
        while i < len, !isWordCharacter(text.character(at: i)) { i += 1 }
        // Walk to the last char of that word.
        while i + 1 < len, isWordCharacter(text.character(at: i + 1)) { i += 1 }
        return min(i, max(0, len - 1))
    }

    /// `ge` — move to end of previous word.
    private func previousWordEnd(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        if i == 0 { return 0 }
        i -= 1
        // Step backward out of the current word.
        while i > 0, isWordCharacter(text.character(at: i)) { i -= 1 }
        // Skip backward through non-word chars to land on previous word's last char.
        while i > 0, !isWordCharacter(text.character(at: i)) { i -= 1 }
        return i
    }

    private func isWordCharacter(_ ch: unichar) -> Bool {
        if ch >= 0x30 && ch <= 0x39 { return true }  // 0-9
        if ch >= 0x41 && ch <= 0x5A { return true }  // A-Z
        if ch >= 0x61 && ch <= 0x7A { return true }  // a-z
        if ch == 0x5F { return true }                // _
        return false
    }

    private func isWhitespace(_ ch: unichar) -> Bool {
        return ch == 0x20 || ch == 0x09 || ch == 0x0A
    }

    // MARK: - WORD motions (whitespace-only separators)

    /// `W` — start of next WORD.
    private func nextBigWordStart(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        let len = text.length
        // Skip current WORD chars.
        while i < len, !isWhitespace(text.character(at: i)) { i += 1 }
        // Skip whitespace to next WORD start.
        while i < len, isWhitespace(text.character(at: i)) { i += 1 }
        return i
    }

    /// `B` — start of previous WORD.
    private func previousBigWordStart(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        if i > 0 { i -= 1 }
        while i > 0, isWhitespace(text.character(at: i)) { i -= 1 }
        while i > 0, !isWhitespace(text.character(at: i - 1)) { i -= 1 }
        return i
    }

    /// `E` — end of current/next WORD.
    private func nextBigWordEnd(in text: NSString, from cursor: Int) -> Int {
        let len = text.length
        var i = cursor
        if i >= len { return len }
        i += 1
        while i < len, isWhitespace(text.character(at: i)) { i += 1 }
        while i + 1 < len, !isWhitespace(text.character(at: i + 1)) { i += 1 }
        return min(i, max(0, len - 1))
    }

    // MARK: - Paragraph motion

    /// Position of next blank line (or buffer end). Vim's `}`.
    private func nextParagraph(in text: NSString, from cursor: Int) -> Int {
        let len = text.length
        var i = cursor
        // Skip current line.
        i = lineEnd(in: text, of: i)
        if i < len { i += 1 }
        // Skip blank lines we might already be on.
        while i < len, isLineBlank(in: text, at: i) {
            i = lineEnd(in: text, of: i)
            if i < len { i += 1 }
        }
        // Now on non-blank line. Walk forward until we hit a blank line
        // or EOF.
        while i < len, !isLineBlank(in: text, at: i) {
            i = lineEnd(in: text, of: i)
            if i < len { i += 1 } else { break }
        }
        return min(i, len)
    }

    /// Position of previous blank line (or buffer start). Vim's `{`.
    private func previousParagraph(in text: NSString, from cursor: Int) -> Int {
        var i = cursor
        if i == 0 { return 0 }
        // Step to start of previous line.
        i = lineStart(in: text, of: i)
        if i > 0 { i -= 1 }
        i = lineStart(in: text, of: i)
        // Skip blank lines.
        while i > 0, isLineBlank(in: text, at: i) {
            if i == 0 { break }
            i = lineStart(in: text, of: max(0, i - 1))
        }
        // Walk backward through non-blank until blank or BOF.
        while i > 0, !isLineBlank(in: text, at: i) {
            if i == 0 { break }
            let prevLineStart = lineStart(in: text, of: max(0, i - 1))
            if isLineBlank(in: text, at: prevLineStart) { i = prevLineStart; break }
            i = prevLineStart
        }
        return max(0, i)
    }

    private func isLineBlank(in text: NSString, at location: Int) -> Bool {
        let start = lineStart(in: text, of: location)
        let end = lineEnd(in: text, of: start)
        var i = start
        while i < end {
            let c = text.character(at: i)
            if c != 0x20 && c != 0x09 { return false }
            i += 1
        }
        return true
    }

    // MARK: - Matching bracket (%)

    private func matchingBracketLocation(in text: NSString, from cursor: Int) -> Int? {
        let pairs: [unichar: (match: unichar, forward: Bool)] = [
            0x28: (0x29, true),   // ( -> )
            0x29: (0x28, false),  // ) -> (
            0x5B: (0x5D, true),   // [ -> ]
            0x5D: (0x5B, false),  // ] -> [
            0x7B: (0x7D, true),   // { -> }
            0x7D: (0x7B, false)   // } -> {
        ]
        let len = text.length
        guard cursor < len else { return nil }
        // Vim's `%` scans the current line for the FIRST bracket if the
        // cursor isn't on one. Match what's at the cursor first.
        var startLoc = cursor
        var c = text.character(at: cursor)
        if pairs[c] == nil {
            // Scan forward on the current line.
            let endOfLine = lineEnd(in: text, of: cursor)
            var i = cursor
            while i < endOfLine {
                if pairs[text.character(at: i)] != nil { startLoc = i; break }
                i += 1
            }
            c = text.character(at: startLoc)
            guard pairs[c] != nil else { return nil }
        }
        let (target, forward) = pairs[c]!
        var depth = 1
        if forward {
            var i = startLoc + 1
            while i < len {
                let ch = text.character(at: i)
                if ch == c { depth += 1 }
                else if ch == target {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
        } else {
            var i = startLoc - 1
            while i >= 0 {
                let ch = text.character(at: i)
                if ch == c { depth += 1 }
                else if ch == target {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
        }
        return nil
    }

    // MARK: - Toggle case (~)

    private func toggleCaseAtCaret(count: Int, editor: VimTextEditor) {
        let ns = editor.text as NSString
        let length = ns.length
        let cursor = editor.selectedRange.location
        let end = min(length, cursor + count)
        guard end > cursor else { return }
        var swapped = ""
        for i in cursor..<end {
            if let scalar = Unicode.Scalar(ns.character(at: i)) {
                let ch = Character(scalar)
                if ch.isUppercase { swapped.append(String(ch).lowercased()) }
                else if ch.isLowercase { swapped.append(String(ch).uppercased()) }
                else { swapped.append(ch) }
            }
        }
        editor.replace(in: NSRange(location: cursor, length: end - cursor), with: swapped)
        editor.selectedRange = NSRange(location: min(end, max(0, (editor.text as NSString).length - 1)), length: 0)
    }
}

/// Modifier flags VimEngine cares about. Tiny enum so tests don't need
/// to construct AppKit event flags.
public struct KeyModifiers: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
    public static let shift   = KeyModifiers(rawValue: 1 << 3)
}

#if canImport(AppKit)
extension NSTextView: VimTextEditor {
    public var text: String {
        get { string }
        set { string = newValue }
    }

    public func replace(in range: NSRange, with string: String) {
        if shouldChangeText(in: range, replacementString: string) {
            replaceCharacters(in: range, with: string)
            didChangeText()
        }
    }

    public func vimUndo() { undoManager?.undo() }
    public func vimRedo() { undoManager?.redo() }

    public func visualLineLocation(from: Int, lines: Int) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let ns = string as NSString
        let length = ns.length
        guard length > 0 else { return 0 }
        let safeFrom = min(max(0, from), length)

        layoutManager.ensureLayout(for: textContainer)
        let totalGlyphs = layoutManager.numberOfGlyphs
        guard totalGlyphs > 0 else { return nil }

        let glyphIdx = safeFrom >= length
            ? totalGlyphs - 1
            : min(layoutManager.glyphIndexForCharacter(at: safeFrom), totalGlyphs - 1)

        var effectiveRange = NSRange()
        let currentLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIdx,
            effectiveRange: &effectiveRange
        )
        let cursorRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIdx, length: 1),
            in: textContainer
        )
        let targetX = cursorRect.minX
        let lineHeight = max(currentLineRect.height, 1)
        let targetY = currentLineRect.midY + (CGFloat(lines) * lineHeight)

        if targetY < 0 { return 0 }
        if targetY > textContainer.size.height { return length }

        let targetPoint = NSPoint(x: targetX, y: targetY)
        let targetGlyph = layoutManager.glyphIndex(for: targetPoint, in: textContainer)
        let targetChar = layoutManager.characterIndexForGlyph(at: targetGlyph)
        return min(max(0, targetChar), length)
    }
}

extension KeyModifiers {
    /// Convert AppKit modifier flags into the vim-relevant subset.
    public init(_ flags: NSEvent.ModifierFlags) {
        var s: KeyModifiers = []
        if flags.contains(.control) { s.insert(.control) }
        if flags.contains(.option)  { s.insert(.option) }
        if flags.contains(.command) { s.insert(.command) }
        if flags.contains(.shift)   { s.insert(.shift) }
        self = s
    }
}
#endif
