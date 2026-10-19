import Foundation

/// A unified slash-command type for the in-editor dropdown. Templates
/// expand into text and place the caret; modes toggle a typing transform;
/// inline commands execute async logic and insert text.
public enum SlashCommand: Identifiable, Hashable {
    case template(Template)
    case mode(ModeCommand)
    case inline(InlineCommand)

    public var name: String {
        switch self {
        case .template(let t): return t.name
        case .mode(let m): return m.name
        case .inline(let i): return i.name
        }
    }

    /// Short label shown in the dropdown after the slash. Templates show
    /// nothing extra (their filename is the description); modes and inline
    /// commands show what they do.
    public var hint: String {
        switch self {
        case .template: return ""
        case .mode(let m): return m.description
        case .inline(let i): return i.description
        }
    }

    public var commitsOnSpace: Bool {
        switch self {
        case .template: return true
        case .mode: return true
        case .inline(let i): return i.commitsOnSpace
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

/// Built-in slash commands that execute async logic and insert text.
public struct InlineCommand: Identifiable, Hashable, Sendable {
    public let name: String
    public let description: String
    public let commitsOnSpace: Bool
    public let action: @Sendable (_ arguments: String, _ context: String) async throws -> String

    public var id: String { name }

    public init(name: String, description: String, commitsOnSpace: Bool = true, action: @escaping @Sendable (_ arguments: String, _ context: String) async throws -> String) {
        self.name = name
        self.description = description
        self.commitsOnSpace = commitsOnSpace
        self.action = action
    }
    
    public static func == (lhs: InlineCommand, rhs: InlineCommand) -> Bool {
        lhs.name == rhs.name
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
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

public let builtInInlineCommands: [InlineCommand] = [
    InlineCommand(name: "todo", description: "insert task checkbox") { _, _ in "- [ ] " },
    InlineCommand(name: "quote", description: "insert blockquote") { _, _ in "> " },
    InlineCommand(name: "date", description: "insert current date") { _, _ in
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    },
    InlineCommand(name: "now", description: "insert current time") { _, _ in
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    },
    InlineCommand(name: "loc", description: "insert current location") { _, _ in
        let p = try await LocationService.shared.fetchCurrentPlacemark()
        let city = p.locality ?? p.subAdministrativeArea ?? "Unknown City"
        let state = p.administrativeArea ?? ""
        return state.isEmpty ? city : "\(city), \(state)"
    },
    InlineCommand(name: "weather", description: "insert current weather") { _, _ in
        let loc = try await LocationService.shared.fetchCurrentLocation()
        let weather = try await WeatherService.shared.fetchCurrentWeather(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        return weather
    },
    InlineCommand(name: "last", description: "insert last journal entries [count]", commitsOnSpace: false) { args, _ in
        let svc = JrnlService()
        let count = abs(Int(args.trimmingCharacters(in: .whitespaces)) ?? 1)
        let entries = try await svc.fetchRecentEntries(journal: "", count: count)
        guard !entries.isEmpty else { return "" }
        
        return entries.map { entry in
            entry.body.components(separatedBy: .newlines)
                .map { "> \($0)" }
                .joined(separator: "\n")
        }.joined(separator: "\n\n")
    },
    InlineCommand(name: "tags", description: "insert top tags [filter/count]", commitsOnSpace: false) { args, _ in
        let svc = JrnlService()
        var tags = try await svc.fetchTags(journal: "")
        
        let rawArgs = args.trimmingCharacters(in: .whitespaces)
        if let count = Int(rawArgs) {
            // Numeric argument: limit the top tags
            return tags.prefix(max(1, abs(count))).map { $0.name }.joined(separator: ", ")
        } else if !rawArgs.isEmpty {
            // String argument: filter tags containing the string
            let filter = rawArgs.lowercased()
            tags = tags.filter { $0.name.lowercased().contains(filter) }
        }
        
        guard !tags.isEmpty else { return "" }
        return tags.prefix(10).map { $0.name }.joined(separator: ", ")
    },
    InlineCommand(name: "suggest", description: "local AI tag suggestions") { _, context in
        let svc = JrnlService()
        let tags = try await svc.fetchTags(journal: "")
        let suggested = await TagSuggestionService.shared.suggestTags(for: context, existingTags: tags)
        return suggested.joined(separator: ", ")
    }
]
