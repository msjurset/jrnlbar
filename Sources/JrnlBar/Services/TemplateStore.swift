import Foundation

/// Loads slash-command templates from jrnl's shared templates folder
/// (`$XDG_DATA_HOME/jrnl/templates/`, defaulting to
/// `~/.local/share/jrnl/templates/`). Seeds a small set of starter
/// templates only when the folder is empty, so existing jrnl users keep
/// their content untouched.
public final class TemplateStore {
    public static let shared = TemplateStore()

    private let fileManager = FileManager.default
    private let directoryOverride: URL?
    private(set) public var templates: [Template] = []

    public init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
    }

    /// Absolute path to the templates directory. Honors `$XDG_DATA_HOME`,
    /// falling back to `~/.local/share/jrnl/templates`. Tests may inject a
    /// custom directory via `init(directoryOverride:)`.
    public var directory: URL {
        if let override = directoryOverride { return override }
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = env["XDG_DATA_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
        }
        return base
            .appendingPathComponent("jrnl", isDirectory: true)
            .appendingPathComponent("templates", isDirectory: true)
    }

    /// Ensures the directory exists, seeds defaults if empty, then loads
    /// every `*.md` / `*.txt` file in alphabetical order.
    @discardableResult
    public func reload() -> [Template] {
        ensureDirectoryExists()
        seedDefaultsIfEmpty()
        templates = loadFromDisk()
        return templates
    }

    /// Templates whose name (case-insensitive) starts with the given
    /// prefix. Pass the run after `/` — leading slashes are stripped.
    /// (For combined template+mode-command matching used by the editor,
    /// see `SlashCommandRegistry.match`.)
    public func match(prefix: String) -> [Template] {
        var needle = prefix
        while needle.hasPrefix("/") { needle.removeFirst() }
        let lower = needle.lowercased()
        if lower.isEmpty { return templates }
        return templates.filter { $0.name.lowercased().hasPrefix(lower) }
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func seedDefaultsIfEmpty() {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let existing = contents.filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }
        guard existing.isEmpty else { return }

        for (name, body) in TemplateStore.defaults {
            let url = directory.appendingPathComponent("\(name).md")
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func loadFromDisk() -> [Template] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let files = contents
            .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard Template.isValidName(name) else { return nil }
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Template(name: name, body: body, path: url)
        }
    }

    // MARK: - Default templates

    static let defaults: [(name: String, body: String)] = [
        (
            "morning-standup",
            """
            ## Morning standup {{date}}

            **Yesterday:** {{cursor}}

            **Today:**

            **Blockers:**
            """
        ),
        (
            "gratitude",
            """
            ## Gratitude {{date}}

            Three things I'm grateful for today:

            1. {{cursor}}
            2.
            3.
            """
        ),
        (
            "weekly-review",
            """
            ## Weekly review — week of {{date}}

            ### What went well

            {{cursor}}

            ### What didn't

            ### Next week
            """
        ),
        (
            "meeting-notes",
            """
            ## Meeting notes {{date}} {{time}}

            **Attendees:** {{cursor}}

            **Agenda:**

            **Decisions:**

            **Action items:**
            """
        )
    ]
}

extension Template {
    /// Characters allowed inside a slash-command name. Alphanumerics
    /// (any script) plus `_` and `-`. Whitespace and other punctuation
    /// are rejected, which is what makes `/foo-bar ` a clean terminator.
    public static func isNameCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-"
    }

    /// A template is reachable via slash-command only if its name (the
    /// filename without extension) is a non-empty run of name-characters.
    /// Matching is case-insensitive: `/Standup`, `/standup`, and
    /// `/STANDUP` all resolve to the same template. Files with spaces or
    /// other punctuation still live on disk for `jrnl --template` use but
    /// are not reachable via slash.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy(isNameCharacter)
    }
}
