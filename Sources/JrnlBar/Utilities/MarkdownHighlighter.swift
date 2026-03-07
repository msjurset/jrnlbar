import AppKit

class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let headerFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
    private let baseForeground = NSColor.textColor

    private let tagColor = NSColor.systemTeal
    private let headerColor = NSColor.textColor
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    private let codeColor = NSColor.systemGray
    private let codeBackground = NSColor.quaternaryLabelColor
    private let listColor = NSColor.systemOrange

    // Pre-compiled patterns
    private let patterns: [(NSRegularExpression, (NSMutableAttributedString, NSRange, NSTextCheckingResult) -> Void)]

    override init() {
        var p: [(NSRegularExpression, (NSMutableAttributedString, NSRange, NSTextCheckingResult) -> Void)] = []

        // Headers: # ... at start of line
        if let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: .anchorsMatchLines) {
            p.append((re, { [headerFont, headerColor] str, _, match in
                let full = match.range
                str.addAttribute(.font, value: headerFont, range: full)
                str.addAttribute(.foregroundColor, value: headerColor, range: full)
            }))
        }

        // Bold: **text** or __text__
        if let re = try? NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\1)", options: []) {
            p.append((re, { [boldFont] str, _, match in
                str.addAttribute(.font, value: boldFont, range: match.range)
            }))
        }

        // Italic: *text* or _text_ (not preceded/followed by same char)
        if let re = try? NSRegularExpression(pattern: "(?<![*_])([*_])(?![*_])(.+?)(?<![*_])\\1(?![*_])", options: []) {
            p.append((re, { [baseFont] str, _, match in
                let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                str.addAttribute(.font, value: italicFont, range: match.range)
            }))
        }

        // Inline code: `text`
        if let re = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            p.append((re, { [codeColor, codeBackground] str, _, match in
                str.addAttribute(.foregroundColor, value: codeColor, range: match.range)
                str.addAttribute(.backgroundColor, value: codeBackground, range: match.range)
            }))
        }

        // List markers: - or * at start of line
        if let re = try? NSRegularExpression(pattern: "^\\s*[-*+]\\s", options: .anchorsMatchLines) {
            p.append((re, { [listColor] str, _, match in
                str.addAttribute(.foregroundColor, value: listColor, range: match.range)
            }))
        }

        // Tags: @word
        if let re = try? NSRegularExpression(pattern: "@\\w+", options: []) {
            p.append((re, { [tagColor] str, _, match in
                str.addAttribute(.foregroundColor, value: tagColor, range: match.range)
            }))
        }

        self.patterns = p
        super.init()
    }

    private let titleFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private let titleSeparatorColor = NSColor.separatorColor

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let string = textStorage.string

        // Reset to base style
        textStorage.addAttribute(.font, value: baseFont, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: baseForeground, range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.underlineColor, range: fullRange)

        // Title detection: jrnl uses the first sentence (ending with . ? !) as the title
        if let titleEnd = findTitleEnd(in: string) {
            let titleRange = NSRange(location: 0, length: titleEnd)
            textStorage.addAttribute(.font, value: titleFont, range: titleRange)

            // Add a subtle underline on the last character of the title line to hint at the boundary
            // Instead, use paragraph spacing — add extra space after the title's paragraph
            if let lineEnd = findEndOfLine(at: titleEnd - 1, in: string) {
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.paragraphSpacing = 6
                let lineRange = NSRange(location: 0, length: lineEnd)
                textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: lineRange)
            }
        }

        // Apply each pattern
        for (regex, apply) in patterns {
            regex.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                apply(textStorage, fullRange, match)
            }
        }
    }

    /// Find the end of the title — the position after the first sentence-ending punctuation (. ? !)
    private func findTitleEnd(in string: String) -> Int? {
        let nsString = string as NSString
        guard nsString.length > 0 else { return nil }

        for i in 0..<nsString.length {
            let ch = nsString.character(at: i)
            guard let scalar = Unicode.Scalar(ch) else { continue }
            if scalar == "." || scalar == "?" || scalar == "!" {
                return i + 1
            }
            // If we hit a newline before any sentence ender, the whole first line is the title
            if scalar == "\n" {
                return i
            }
        }
        // No sentence ender found — everything typed so far is the title
        return nsString.length
    }

    /// Find the end of the line containing the given character index
    private func findEndOfLine(at index: Int, in string: String) -> Int? {
        let nsString = string as NSString
        guard index < nsString.length else { return nsString.length }
        let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
        return lineRange.location + lineRange.length
    }
}
