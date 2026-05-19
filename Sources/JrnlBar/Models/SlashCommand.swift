import Foundation

/// A unified slash-command type for the in-editor dropdown. Templates
/// expand into text and place the caret; modes toggle a typing transform.
public enum SlashCommand: Identifiable, Hashable {
    case template(Template)
    case mode(ModeCommand)

    public var name: String {
        switch self {
        case .template(let t): return t.name
        case .mode(let m): return m.name
        }
    }

    /// Short label shown in the dropdown after the slash. Templates show
    /// nothing extra (their filename is the description); modes show
    /// what they do.
    public var hint: String {
        switch self {
        case .template: return ""
        case .mode(let m): return m.description
        }
    }

    public var id: String { name }
}

/// Built-in slash commands that toggle a typing transformation.
public struct ModeCommand: Identifiable, Hashable {
    public let name: String
    public let description: String
    public let mode: TextMode

    public var id: String { name }

    public init(name: String, description: String, mode: TextMode) {
        self.name = name
        self.description = description
        self.mode = mode
    }
}

/// Per-entry editor modes. `.uppercase` is a per-character transform;
/// `.vim` hands the keyboard off to `VimEngine`. `nil` means no mode is
/// active (normal typing).
public enum TextMode: String, Hashable, Codable {
    case uppercase
    case vim

    /// Short label for the mode badge in the submit bar. `.vim`'s badge
    /// is overridden at render time by `VimEngine.badge` so it can
    /// reflect the current submode (`VIM:N`, `VIM:I`, `:q` etc.).
    public var badge: String {
        switch self {
        case .uppercase: return "UC"
        case .vim:       return "VIM"
        }
    }

    /// Character-level transformation applied to typed input. For modes
    /// that don't transform input (like `.vim`, which intercepts keys at
    /// a higher level), this returns the string unchanged.
    public func apply(_ string: String) -> String {
        switch self {
        case .uppercase: return string.uppercased()
        case .vim:       return string
        }
    }
}

/// The starter set of mode commands. Add new entries here as the
/// concept proves itself in practice.
public let builtInModeCommands: [ModeCommand] = [
    ModeCommand(name: "uc", description: "uppercase typing", mode: .uppercase),
    ModeCommand(name: "vim", description: "vim keybindings", mode: .vim)
]
