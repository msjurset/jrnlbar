import Foundation

/// List-prefix kinds the editor recognizes for smart continuation.
public enum ListPrefix {
    case unordered(marker: Character)               // "-", "*", "+"
    case task(marker: Character, checked: Bool)     // "- [ ]" or "- [x]"
    case ordered(number: Int)                       // "1.", "23."
    case blockquote                                 // ">"

    /// Length of the prefix on the source line, after any leading indent.
    /// Always includes the single trailing space that follows the marker.
    public var prefixLength: Int {
        switch self {
        case .unordered: return 2                   // "- "
        case .task: return 6                        // "- [ ] "
        case .ordered(let n): return String(n).count + 2 // "1. " / "23. "
        case .blockquote: return 2                  // "> "
        }
    }

    /// Prefix to write on the new line when continuing the list.
    public func continuation(indent: String) -> String {
        switch self {
        case .unordered(let marker): return indent + "\(marker) "
        case .task(let marker, _): return indent + "\(marker) [ ] "
        case .ordered(let n): return indent + "\(n + 1). "
        case .blockquote: return indent + "> "
        }
    }

    public static func detect(in body: String) -> ListPrefix? {
        let chars = Array(body)
        // Task list: "<marker> [<x or space>] " (6 chars min: "- [ ] ").
        if chars.count >= 6,
           let marker = chars.first,
           "-*+".contains(marker),
           chars[1] == " ",
           chars[2] == "[",
           ("xX ".contains(chars[3])),
           chars[4] == "]",
           chars[5] == " " {
            return .task(marker: marker, checked: chars[3].lowercased() == "x")
        }
        // Unordered: "<marker> "
        if chars.count >= 2, let marker = chars.first, "-*+".contains(marker), chars[1] == " " {
            return .unordered(marker: marker)
        }
        // Ordered: "<digits>. "
        var digits = ""
        var i = 0
        while i < chars.count, chars[i].isASCII, chars[i].isNumber {
            digits.append(chars[i])
            i += 1
        }
        if !digits.isEmpty, i + 1 < chars.count, chars[i] == ".", chars[i + 1] == " ",
           let n = Int(digits) {
            return .ordered(number: n)
        }
        // Blockquote: "> "
        if body.hasPrefix("> ") {
            return .blockquote
        }
        return nil
    }
}
