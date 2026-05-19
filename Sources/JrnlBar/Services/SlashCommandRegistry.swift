import Foundation

/// Aggregates file-backed templates with built-in mode commands into a
/// single list the editor consults for autocomplete, exact-match space
/// trigger, and `//cmd` escape handling at save time.
public final class SlashCommandRegistry {
    public static let shared = SlashCommandRegistry(
        templateStore: .shared,
        modes: builtInModeCommands
    )

    private let templateStore: TemplateStore
    private let modes: [ModeCommand]

    public init(templateStore: TemplateStore, modes: [ModeCommand] = builtInModeCommands) {
        self.templateStore = templateStore
        self.modes = modes
    }

    /// Reload file-backed templates from disk (mode commands are static).
    /// Returns the full combined command list for convenience.
    @discardableResult
    public func reload() -> [SlashCommand] {
        templateStore.reload()
        return all
    }

    /// All registered slash commands. Mode commands first (alphabetical),
    /// then templates (filesystem order).
    public var all: [SlashCommand] {
        let modeItems = modes
            .sorted { $0.name < $1.name }
            .map(SlashCommand.mode)
        let templateItems = templateStore.templates.map(SlashCommand.template)
        return modeItems + templateItems
    }

    /// Commands whose name (case-insensitive) starts with the given
    /// prefix. Pass the run after `/`; leading slashes are stripped.
    public func match(prefix: String) -> [SlashCommand] {
        var needle = prefix
        while needle.hasPrefix("/") { needle.removeFirst() }
        let lower = needle.lowercased()
        if lower.isEmpty { return all }
        return all.filter { $0.name.lowercased().hasPrefix(lower) }
    }

    /// The unique command (if any) whose name equals the given prefix
    /// exactly (case-insensitive). Used by the space-trigger commit path.
    public func exactMatch(prefix: String) -> SlashCommand? {
        var needle = prefix
        while needle.hasPrefix("/") { needle.removeFirst() }
        let lower = needle.lowercased()
        return all.first { $0.name.lowercased() == lower }
    }

    /// Collapse `//<command-name>` escape sequences back to
    /// `/<command-name>` so typed literals land in the saved entry
    /// without the escape. Case-insensitive against the registered
    /// command names; preserves the user's typed casing. Only collapses
    /// at start-of-text, after whitespace, or after a newline (URLs
    /// like `https://example.com` are untouched).
    public func unescape(_ text: String) -> String {
        let lowerNames = Set(all.map { $0.name.lowercased() })
        if lowerNames.isEmpty { return text }

        let chars = Array(text)
        var result = ""
        result.reserveCapacity(text.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let leftOK = i == 0 || chars[i - 1].isWhitespace || chars[i - 1].isNewline
                if leftOK {
                    var j = i + 2
                    while j < chars.count, Template.isNameCharacter(chars[j]) {
                        j += 1
                    }
                    let word = String(chars[(i + 2)..<j])
                    if !word.isEmpty, lowerNames.contains(word.lowercased()) {
                        result.append("/")
                        result.append(word)
                        i = j
                        continue
                    }
                }
            }
            result.append(c)
            i += 1
        }
        return result
    }
}
