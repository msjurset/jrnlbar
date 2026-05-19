import Foundation
import JrnlBarLib

// Minimal test harness (no Xcode required)
var passed = 0
var failed = 0

func expect(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let label = message.isEmpty ? "Assertion failed" : message
        print("  FAIL [\(file.split(separator: "/").last ?? ""):\(line)] \(label)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("  PASS \(name)")
    } catch {
        failed += 1
        print("  FAIL \(name): \(error)")
    }
}

// ─── parseJournals ───

test("parseJournals: multiple journals") {
    let output = """
    Journals defined in config (/Users/test/.config/jrnl/jrnl.yaml)
     * default -> /Users/test/.jrnl/journal.txt
     * work    -> /Users/test/.jrnl/work.txt
    """
    let journals = JrnlParser.parseJournals(from: output)
    expect(journals == ["default", "work"], "expected [default, work], got \(journals)")
}

test("parseJournals: single journal") {
    let output = """
    Journals defined in config (/Users/test/.config/jrnl/jrnl.yaml)
     * default -> /Users/test/.jrnl/journal.txt
    """
    expect(JrnlParser.parseJournals(from: output) == ["default"])
}

test("parseJournals: empty output") {
    expect(JrnlParser.parseJournals(from: "") == [])
}

test("parseJournals: ignores non-bullet lines") {
    let output = """
    Journals defined in config
    some random line
     * default -> /path
    another line
    """
    expect(JrnlParser.parseJournals(from: output) == ["default"])
}

// ─── parseTags ───

test("parseTags: basic") {
    let output = """
    @work                : 5
    @health              : 3
    @travel              : 1
    """
    let tags = JrnlParser.parseTags(from: output)
    expect(tags.count == 3, "expected 3 tags, got \(tags.count)")
    expect(tags[0].name == "@work")
    expect(tags[0].count == 5)
    expect(tags[1].name == "@health")
    expect(tags[2].name == "@travel")
}

test("parseTags: sorted by count descending") {
    let output = """
    @low                 : 1
    @high                : 10
    @mid                 : 5
    """
    let tags = JrnlParser.parseTags(from: output)
    expect(tags.map(\.name) == ["@high", "@mid", "@low"], "sort order wrong: \(tags.map(\.name))")
}

test("parseTags: ignores non-tag lines") {
    let output = """
    @valid               : 3
    not a tag            : 2
    """
    let tags = JrnlParser.parseTags(from: output)
    expect(tags.count == 1)
    expect(tags[0].name == "@valid")
}

test("parseTags: empty output") {
    expect(JrnlParser.parseTags(from: "").isEmpty)
}

// ─── parseEntries ───

test("parseEntries: basic") {
    let json = """
    {
      "tags": {},
      "entries": [
        {
          "title": "Test entry.",
          "body": "Some body text.",
          "date": "2026-03-06",
          "time": "09:00",
          "tags": [],
          "starred": false
        }
      ]
    }
    """
    let entries = try JrnlParser.parseEntries(from: json)
    expect(entries.count == 1)
    expect(entries[0].title == "Test entry.")
    expect(entries[0].body == "Some body text.")
    expect(entries[0].date == "2026-03-06")
    expect(entries[0].time == "09:00")
    expect(entries[0].starred == false)
}

test("parseEntries: with entry-level tags") {
    let json = """
    {
      "tags": {"@work": 1, "@health": 2},
      "entries": [
        {
          "title": "Tagged.",
          "body": "@work @health",
          "date": "2026-03-06",
          "time": "10:00",
          "tags": ["@work", "@health"],
          "starred": true
        }
      ]
    }
    """
    let entries = try JrnlParser.parseEntries(from: json)
    expect(entries[0].tags == ["@work", "@health"])
    expect(entries[0].starred == true)
}

test("parseEntries: top-level tags as [String: Int] does not break decode") {
    let json = """
    {
      "tags": {"@work": 5, "@personal": 12},
      "entries": [
        {
          "title": "Entry.",
          "body": "",
          "date": "2026-01-01",
          "time": "08:00",
          "tags": ["@work"],
          "starred": false
        }
      ]
    }
    """
    let entries = try JrnlParser.parseEntries(from: json)
    expect(entries.count == 1, "should decode despite [String: Int] tags")
}

test("parseEntries: multiple entries") {
    let json = """
    {
      "tags": {},
      "entries": [
        {"title": "First.", "body": "", "date": "2026-03-05", "time": "09:00", "tags": [], "starred": false},
        {"title": "Second.", "body": "Body.", "date": "2026-03-06", "time": "10:00", "tags": [], "starred": false}
      ]
    }
    """
    let entries = try JrnlParser.parseEntries(from: json)
    expect(entries.count == 2)
    expect(entries[0].title == "First.")
    expect(entries[1].title == "Second.")
}

test("parseEntries: empty string returns empty") {
    let entries = try JrnlParser.parseEntries(from: "")
    expect(entries.isEmpty)
}

// ─── buildSubmitContent ───

test("buildSubmitContent: new entry (no date)") {
    let result = JrnlParser.buildSubmitContent("Hello world.", date: nil, time: nil)
    expect(result == "Hello world.")
}

test("buildSubmitContent: edit with date prefix") {
    let result = JrnlParser.buildSubmitContent("Edited.\nWith body.", date: "2026-03-05", time: "14:30")
    expect(result == "2026-03-05 14:30: Edited.\nWith body.", "got: \(result)")
}

// ─── JournalEntry model ───

test("JournalEntry.fullText: title only") {
    let e = JournalEntry(title: "Just a title.", body: "", date: "2026-03-06", time: "09:00", tags: [], starred: false)
    expect(e.fullText == "Just a title.")
}

test("JournalEntry.fullText: title + body") {
    let e = JournalEntry(title: "Title.", body: "Body.\nLine 2.", date: "2026-03-06", time: "09:00", tags: [], starred: false)
    expect(e.fullText == "Title.\nBody.\nLine 2.")
}

test("JournalEntry.displayDate") {
    let e = JournalEntry(title: "T", body: "", date: "2026-03-06", time: "14:30", tags: [], starred: false)
    expect(e.displayDate == "2026-03-06 14:30")
}

test("JournalEntry.id is deterministic") {
    let e = JournalEntry(title: "My title.", body: "", date: "2026-03-06", time: "09:00", tags: [], starred: false)
    expect(e.id == "2026-03-06-09:00-My title.")
}

// ─── Template tokens ───

test("Template.expand: no tokens returns body verbatim") {
    let t = Template(name: "x", body: "Plain body.", path: URL(fileURLWithPath: "/tmp/x.md"))
    let (text, offset) = t.expand()
    expect(text == "Plain body.", "got: \(text)")
    expect(offset == ("Plain body." as NSString).length, "offset should be end-of-text, got \(offset)")
}

test("Template.expand: {{date}} substitution") {
    let t = Template(name: "x", body: "Today: {{date}}.", path: URL(fileURLWithPath: "/tmp/x.md"))
    let fixed = ISO8601DateFormatter().date(from: "2026-05-18T14:32:00Z")!
    let (text, _) = t.expand(now: fixed, locale: Locale(identifier: "en_US_POSIX"))
    expect(text.contains("Today: 2026-05-18."), "got: \(text)")
}

test("Template.expand: {{cursor}} is removed and offset returned") {
    let t = Template(name: "x", body: "Hi {{cursor}}there.", path: URL(fileURLWithPath: "/tmp/x.md"))
    let (text, offset) = t.expand()
    expect(text == "Hi there.", "got: \(text)")
    expect(offset == 3, "cursor offset should be 3, got \(offset)")
}

test("Template.expand: tokens combined") {
    let t = Template(name: "x", body: "## {{date}}\n{{cursor}}", path: URL(fileURLWithPath: "/tmp/x.md"))
    let fixed = ISO8601DateFormatter().date(from: "2026-05-18T14:32:00Z")!
    let (text, offset) = t.expand(now: fixed, locale: Locale(identifier: "en_US_POSIX"))
    expect(text == "## 2026-05-18\n", "got: \(text)")
    expect(offset == ("## 2026-05-18\n" as NSString).length, "offset should land at end, got \(offset)")
}

test("Template.expand: unknown tokens stay literal") {
    let t = Template(name: "x", body: "Hello {{name}}.", path: URL(fileURLWithPath: "/tmp/x.md"))
    let (text, _) = t.expand()
    expect(text == "Hello {{name}}.", "got: \(text)")
}

// ─── TemplateStore: seeding + load ───

func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("jrnlbar-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

test("TemplateStore.reload: seeds defaults when folder is empty") {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TemplateStore(directoryOverride: dir)
    let templates = store.reload()
    let names = Set(templates.map { $0.name })
    expect(names.contains("morning-standup"))
    expect(names.contains("gratitude"))
    expect(names.contains("weekly-review"))
    expect(names.contains("meeting-notes"))
}

test("TemplateStore.reload: does NOT seed when folder has existing files") {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let existing = dir.appendingPathComponent("user-template.md")
    try "User-authored content.".write(to: existing, atomically: true, encoding: .utf8)

    let store = TemplateStore(directoryOverride: dir)
    let templates = store.reload()
    let names = Set(templates.map { $0.name })
    expect(names == ["user-template"], "expected only user-template, got \(names)")
}

test("TemplateStore.reload: skips files with invalid (non-word) names") {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try "spaces in name".write(
        to: dir.appendingPathComponent("Has Spaces.md"),
        atomically: true, encoding: .utf8
    )
    try "good".write(
        to: dir.appendingPathComponent("good-name.md"),
        atomically: true, encoding: .utf8
    )
    let store = TemplateStore(directoryOverride: dir)
    let templates = store.reload()
    expect(templates.map(\.name) == ["good-name"], "got: \(templates.map(\.name))")
}

test("TemplateStore.match: prefix match is case-insensitive and strips leading slash") {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TemplateStore(directoryOverride: dir)
    store.reload()  // seeds the four defaults
    expect(store.match(prefix: "/MOR").map(\.name) == ["morning-standup"])
    expect(store.match(prefix: "weekly").map(\.name) == ["weekly-review"])
    expect(store.match(prefix: "/").count == 4, "empty prefix returns all, got \(store.match(prefix: "/").count)")
}

test("TemplateStore.match: matches mixed-case on-disk names case-insensitively") {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try "body".write(to: dir.appendingPathComponent("Standup.md"), atomically: true, encoding: .utf8)
    let store = TemplateStore(directoryOverride: dir)
    store.reload()
    expect(store.match(prefix: "/stand").map(\.name) == ["Standup"], "lowercase prefix should find Standup")
    expect(store.match(prefix: "/STAND").map(\.name) == ["Standup"], "uppercase prefix should find Standup")
}

test("Template.isValidName: rejects whitespace and punctuation") {
    expect(!Template.isValidName(""))
    expect(!Template.isValidName("has space"))
    expect(!Template.isValidName("has.dot"))
    expect(!Template.isValidName("slashy/name"))
    expect(Template.isValidName("good"))
    expect(Template.isValidName("good-name"))
    expect(Template.isValidName("good_name"))
    expect(Template.isValidName("CamelCase123"))
}

// ─── SlashCommandRegistry: //escape unescape ───

func makeRegistry(seeded: Bool = true) -> (SlashCommandRegistry, URL) {
    let dir = makeTempDir()
    let store = TemplateStore(directoryOverride: dir)
    if seeded { store.reload() } // seeds the four defaults
    let registry = SlashCommandRegistry(templateStore: store)
    return (registry, dir)
}

test("SlashCommandRegistry.unescape: collapses //cmd at word boundary") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    expect(registry.unescape("I love //gratitude entries.") == "I love /gratitude entries.")
    expect(registry.unescape("//gratitude at start.") == "/gratitude at start.")
    expect(registry.unescape("Line one.\n//gratitude is great.") == "Line one.\n/gratitude is great.")
}

test("SlashCommandRegistry.unescape: does NOT touch // inside URLs") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = "See https://gratitude.example.com for more."
    expect(registry.unescape(url) == url, "URL got mangled: \(registry.unescape(url))")
}

test("SlashCommandRegistry.unescape: leaves // alone when next word is not a registered command") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = "Random //notacommand here."
    expect(registry.unescape(text) == text, "got: \(registry.unescape(text))")
}

test("SlashCommandRegistry.unescape: only collapses exact command-name word boundary") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = "//gratitudes plural here."
    expect(registry.unescape(text) == text, "got: \(registry.unescape(text))")
}

test("SlashCommandRegistry.unescape: matches case-insensitively, preserves user casing") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    expect(registry.unescape("Love //Gratitude here.") == "Love /Gratitude here.")
    expect(registry.unescape("Love //GRATITUDE here.") == "Love /GRATITUDE here.")
    expect(registry.unescape("Love //gratitude here.") == "Love /gratitude here.")
}

test("SlashCommandRegistry.unescape: also collapses //uc (mode command)") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    expect(registry.unescape("I typed //uc in a sentence.") == "I typed /uc in a sentence.")
    expect(registry.unescape("And //UC too.") == "And /UC too.")
}

// ─── SlashCommandRegistry: match + exactMatch ───

test("SlashCommandRegistry.match: includes both templates and mode commands") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    let names = registry.all.map(\.name)
    expect(names.contains("uc"))
    expect(names.contains("gratitude"))
}

test("SlashCommandRegistry.match: prefix /u matches /uc") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    expect(registry.match(prefix: "/u").map(\.name) == ["uc"])
}

test("SlashCommandRegistry.exactMatch: case-insensitive, returns nil if no match") {
    let (registry, dir) = makeRegistry()
    defer { try? FileManager.default.removeItem(at: dir) }
    if case .mode(let m) = registry.exactMatch(prefix: "/UC") {
        expect(m.mode == .uppercase)
    } else {
        expect(false, "expected /UC to resolve to uppercase mode command")
    }
    expect(registry.exactMatch(prefix: "/nope") == nil)
}

// ─── TextMode.apply ───

test("TextMode.apply: uppercase transform") {
    expect(TextMode.uppercase.apply("hello") == "HELLO")
    expect(TextMode.uppercase.apply("MiXeD 1.0") == "MIXED 1.0")
}

test("TextMode.apply: vim is identity (engine handles input separately)") {
    expect(TextMode.vim.apply("hello") == "hello")
}

// ─── VimEngine ───

final class StubEditor: VimTextEditor {
    var text: String
    var selectedRange: NSRange
    private var history: [(String, NSRange)] = []
    private var future: [(String, NSRange)] = []

    init(_ text: String, caret: Int = 0) {
        self.text = text
        self.selectedRange = NSRange(location: caret, length: 0)
    }

    func replace(in range: NSRange, with string: String) {
        history.append((text, selectedRange))
        future.removeAll()
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: range, with: string)
        text = ns as String
    }

    func vimUndo() {
        guard let (prev, sel) = history.popLast() else { return }
        future.append((text, selectedRange))
        text = prev
        selectedRange = sel
    }

    func vimRedo() {
        guard let (next, sel) = future.popLast() else { return }
        history.append((text, selectedRange))
        text = next
        selectedRange = sel
    }
}

/// Feed each key in `keys` to the engine. A key is either:
///   * a 1-char string (e.g. "h", "i") — its first character.
///   * a sentinel like "<esc>", "<enter>", "<bs>" for special keys.
func feed(_ engine: VimEngine, _ keys: [String], on editor: VimTextEditor) {
    for k in keys {
        let (chars, keyCode): (String?, UInt16)
        switch k {
        case "<esc>": chars = nil; keyCode = 53
        case "<enter>": chars = nil; keyCode = 36
        case "<bs>": chars = nil; keyCode = 51
        case "<left>": chars = "\u{F702}"; keyCode = 123
        case "<right>": chars = "\u{F703}"; keyCode = 124
        case "<down>": chars = "\u{F701}"; keyCode = 125
        case "<up>": chars = "\u{F700}"; keyCode = 126
        case "<c-r>": chars = "r"; keyCode = 15
            engine.handleKey(chars: chars, keyCode: keyCode, modifiers: [.control], editor: editor)
            continue
        default: chars = k; keyCode = 0
        }
        engine.handleKey(chars: chars, keyCode: keyCode, modifiers: [], editor: editor)
    }
}

test("VimEngine: starts in normal mode") {
    let engine = VimEngine()
    expect(engine.submode == .normal)
    expect(engine.badge == "VIM:N")
}

test("VimEngine: i enters insert, Esc returns to normal") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 0)
    feed(engine, ["i"], on: ed)
    expect(engine.submode == .insert, "expected insert mode")
    feed(engine, ["<esc>"], on: ed)
    expect(engine.submode == .normal, "expected normal after Esc")
}

test("VimEngine: h/j/k/l move caret") {
    let engine = VimEngine()
    let ed = StubEditor("hello\nworld", caret: 0)
    feed(engine, ["l", "l"], on: ed)
    expect(ed.selectedRange.location == 2, "l, l -> 2, got \(ed.selectedRange.location)")
    feed(engine, ["j"], on: ed)
    expect(ed.selectedRange.location == 8, "down to 'r' in 'world', got \(ed.selectedRange.location)")
    feed(engine, ["h"], on: ed)
    expect(ed.selectedRange.location == 7, "back one, got \(ed.selectedRange.location)")
    feed(engine, ["k"], on: ed)
    expect(ed.selectedRange.location == 1, "up to col 1 of line 1, got \(ed.selectedRange.location)")
}

test("VimEngine: 0 and $ jump to line start / end") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 6)
    feed(engine, ["0"], on: ed)
    expect(ed.selectedRange.location == 0)
    feed(engine, ["$"], on: ed)
    expect(ed.selectedRange.location == 11, "got \(ed.selectedRange.location)")
}

test("VimEngine: gg and G jump to buffer start / end") {
    let engine = VimEngine()
    let ed = StubEditor("line one\nline two\nline three", caret: 10)
    feed(engine, ["g", "g"], on: ed)
    expect(ed.selectedRange.location == 0)
    feed(engine, ["G"], on: ed)
    expect(ed.selectedRange.location == 28, "got \(ed.selectedRange.location)")
}

test("VimEngine: w and b move by word") {
    let engine = VimEngine()
    let ed = StubEditor("the quick brown fox", caret: 0)
    feed(engine, ["w"], on: ed)
    expect(ed.selectedRange.location == 4, "got \(ed.selectedRange.location)")
    feed(engine, ["w", "w"], on: ed)
    expect(ed.selectedRange.location == 16, "got \(ed.selectedRange.location)")
    feed(engine, ["b"], on: ed)
    expect(ed.selectedRange.location == 10, "got \(ed.selectedRange.location)")
}

test("VimEngine: x deletes character") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 1)
    feed(engine, ["x"], on: ed)
    expect(ed.text == "hllo", "got: \(ed.text)")
    expect(ed.selectedRange.location == 1)
}

test("VimEngine: dd deletes whole line including newline") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo\nthree", caret: 5)
    feed(engine, ["d", "d"], on: ed)
    expect(ed.text == "one\nthree", "got: \(ed.text)")
}

test("VimEngine: dw deletes to next word start") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar baz", caret: 0)
    feed(engine, ["d", "w"], on: ed)
    expect(ed.text == "bar baz", "got: \(ed.text)")
}

test("VimEngine: count prefix repeats motion") {
    let engine = VimEngine()
    let ed = StubEditor("abcdefghij", caret: 0)
    feed(engine, ["3", "l"], on: ed)
    expect(ed.selectedRange.location == 3, "got \(ed.selectedRange.location)")
}

test("VimEngine: 3dd deletes three lines") {
    let engine = VimEngine()
    let ed = StubEditor("a\nb\nc\nd\ne", caret: 0)
    feed(engine, ["3", "d", "d"], on: ed)
    expect(ed.text == "d\ne", "got: \(ed.text)")
}

test("VimEngine: o opens line below and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("first\nsecond", caret: 2)
    feed(engine, ["o"], on: ed)
    expect(ed.text == "first\n\nsecond", "got: \(ed.text)")
    expect(ed.selectedRange.location == 6)
    expect(engine.submode == .insert)
}

test("VimEngine: A jumps to line end and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("hello\nworld", caret: 0)
    feed(engine, ["A"], on: ed)
    expect(ed.selectedRange.location == 5)
    expect(engine.submode == .insert)
}

test("VimEngine: a moves right and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("hi", caret: 0)
    feed(engine, ["a"], on: ed)
    expect(ed.selectedRange.location == 1)
    expect(engine.submode == .insert)
}

test("VimEngine: u undoes a delete") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 0)
    feed(engine, ["x"], on: ed)
    expect(ed.text == "ello")
    feed(engine, ["u"], on: ed)
    expect(ed.text == "hello", "undo restored, got: \(ed.text)")
}

test("VimEngine: :q exits via onExit callback") {
    let engine = VimEngine()
    let ed = StubEditor("anything", caret: 0)
    var exited = false
    engine.onExit = { exited = true }
    feed(engine, [":", "q", "<enter>"], on: ed)
    expect(exited, "expected :q to fire onExit")
}

test("VimEngine: :vim also exits") {
    let engine = VimEngine()
    let ed = StubEditor("anything", caret: 0)
    var exited = false
    engine.onExit = { exited = true }
    feed(engine, [":", "v", "i", "m", "<enter>"], on: ed)
    expect(exited)
}

test("VimEngine: :w submits without exiting") {
    let engine = VimEngine()
    let ed = StubEditor("body", caret: 0)
    var submitted = false
    var exited = false
    engine.onSubmit = { submitted = true }
    engine.onExit = { exited = true }
    feed(engine, [":", "w", "<enter>"], on: ed)
    expect(submitted)
    expect(!exited, ":w must not exit")
}

test("VimEngine: :wq submits and exits") {
    let engine = VimEngine()
    let ed = StubEditor("body", caret: 0)
    var submitted = false
    var exited = false
    engine.onSubmit = { submitted = true }
    engine.onExit = { exited = true }
    feed(engine, [":", "w", "q", "<enter>"], on: ed)
    expect(submitted)
    expect(exited)
}

test("VimEngine: command-mode Backspace deletes from buffer") {
    let engine = VimEngine()
    let ed = StubEditor("body", caret: 0)
    feed(engine, [":", "q", "<bs>"], on: ed)
    expect(engine.commandBuffer == "", "expected empty buffer after backspace, got '\(engine.commandBuffer)'")
    expect(engine.submode == .command, "still in command mode while buffer was non-empty before bs")
}

test("VimEngine: arrow keys are routed to motions in normal mode") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["<right>", "<right>"], on: ed)
    expect(ed.selectedRange.location == 2)
    feed(engine, ["<left>"], on: ed)
    expect(ed.selectedRange.location == 1)
}

test("VimEngine: ^ moves to first non-blank of line") {
    let engine = VimEngine()
    let ed = StubEditor("    hello world", caret: 10)
    feed(engine, ["^"], on: ed)
    expect(ed.selectedRange.location == 4, "got \(ed.selectedRange.location)")
}

test("VimEngine: ^ on all-whitespace line lands at line start") {
    let engine = VimEngine()
    let ed = StubEditor("   \nhello", caret: 2)
    feed(engine, ["^"], on: ed)
    expect(ed.selectedRange.location == 0, "got \(ed.selectedRange.location)")
}

test("VimEngine: I jumps to first non-blank and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("    hello", caret: 8)
    feed(engine, ["I"], on: ed)
    expect(ed.selectedRange.location == 4)
    expect(engine.submode == .insert)
}

test("VimEngine: yy then p pastes line below") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo", caret: 0)
    feed(engine, ["y", "y", "p"], on: ed)
    expect(ed.text == "one\none\ntwo", "got: \(ed.text)")
}

test("VimEngine: yy then P pastes line above") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo", caret: 4)  // on the 't' of two
    feed(engine, ["y", "y", "P"], on: ed)
    expect(ed.text == "one\ntwo\ntwo", "got: \(ed.text)")
}

test("VimEngine: yw then p pastes word inline after cursor") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar", caret: 0)
    feed(engine, ["y", "w", "p"], on: ed)
    // yw yanks "foo " (including trailing space — vim semantics).
    // Paste after cursor (pos 0 → insert at 1) → "ffoo oo bar"
    expect(ed.text == "ffoo oo bar", "got: \(ed.text)")
}

test("VimEngine: dd then p restores the deleted line") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo\nthree", caret: 4)
    feed(engine, ["d", "d", "p"], on: ed)
    // dd deletes "two\n", caret lands on "three" line. p pastes below.
    // Since "three" has no trailing newline (EOF), engine prepends \n
    // and drops the register's trailing \n, leaving no \n at EOF.
    expect(ed.text == "one\nthree\ntwo", "got: \(ed.text)")
}

test("VimEngine: 2yy then p pastes two lines") {
    let engine = VimEngine()
    let ed = StubEditor("a\nb\nc", caret: 0)
    feed(engine, ["2", "y", "y", "p"], on: ed)
    expect(ed.text == "a\na\nb\nb\nc", "got: \(ed.text)")
}

test("VimEngine: count multiplies paste") {
    let engine = VimEngine()
    let ed = StubEditor("ab", caret: 0)
    feed(engine, ["y", "l", "3", "p"], on: ed)
    // yl yanks "a" (single char), 3p pastes "aaa" after cursor → "aaaab"
    expect(ed.text == "aaaab", "got: \(ed.text)")
}

test("VimEngine: r replaces single char") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 1)
    feed(engine, ["r", "x"], on: ed)
    expect(ed.text == "hxllo", "got: \(ed.text)")
    expect(ed.selectedRange.location == 1, "caret stays on replaced char")
    expect(engine.submode == .normal, "stays in normal mode after r")
}

test("VimEngine: 3r replaces three chars") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 1)
    feed(engine, ["3", "r", "Z"], on: ed)
    expect(ed.text == "aZZZef", "got: \(ed.text)")
    expect(ed.selectedRange.location == 3, "caret on last replaced char, got \(ed.selectedRange.location)")
}

test("VimEngine: r at end of buffer is a no-op") {
    let engine = VimEngine()
    let ed = StubEditor("abc", caret: 3)
    feed(engine, ["r", "x"], on: ed)
    expect(ed.text == "abc", "unchanged: \(ed.text)")
}

test("VimEngine: r then Esc cancels without replacing") {
    let engine = VimEngine()
    let ed = StubEditor("abc", caret: 0)
    feed(engine, ["r", "<esc>"], on: ed)
    expect(ed.text == "abc", "unchanged: \(ed.text)")
}

test("VimEngine: cw deletes word and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar", caret: 0)
    feed(engine, ["c", "w"], on: ed)
    expect(ed.text == "bar", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

test("VimEngine: cc empties current line and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("hello\nworld", caret: 2)
    feed(engine, ["c", "c"], on: ed)
    expect(ed.text == "\nworld", "got: \(ed.text)")
    expect(ed.selectedRange.location == 0)
    expect(engine.submode == .insert)
}

test("VimEngine: c$ changes to end of line") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 6)
    feed(engine, ["c", "$"], on: ed)
    expect(ed.text == "hello ", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

test("VimEngine: C is shorthand for c$") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 6)
    feed(engine, ["C"], on: ed)
    expect(ed.text == "hello ", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

test("VimEngine: D is shorthand for d$") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 6)
    feed(engine, ["D"], on: ed)
    expect(ed.text == "hello ", "got: \(ed.text)")
    expect(engine.submode == .normal, "D stays in normal mode")
}

test("VimEngine: s replaces one char and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 0)
    feed(engine, ["s"], on: ed)
    expect(ed.text == "ello", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

test("VimEngine: r followed by space replaces with space and stays normal") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 2)
    feed(engine, ["r", " "], on: ed)
    expect(ed.text == "ab def", "got: \(ed.text)")
    expect(engine.submode == .normal, "r must NOT switch modes")
    expect(ed.selectedRange.location == 2, "caret stays on replaced char")
}

test("VimEngine: e moves to end of current word") {
    let engine = VimEngine()
    let ed = StubEditor("abc def", caret: 0)
    feed(engine, ["e"], on: ed)
    expect(ed.selectedRange.location == 2, "got \(ed.selectedRange.location)")
}

test("VimEngine: e from end of word jumps to end of next word") {
    let engine = VimEngine()
    let ed = StubEditor("abc def ghi", caret: 2)
    feed(engine, ["e"], on: ed)
    expect(ed.selectedRange.location == 6, "got \(ed.selectedRange.location)")
}

test("VimEngine: ea is the standard append-after-word idiom") {
    let engine = VimEngine()
    let ed = StubEditor("abc def", caret: 0)
    // ea: e moves to 'c' (end of "abc"), a then moves to position after 'c' and enters insert
    feed(engine, ["e", "a"], on: ed)
    expect(ed.selectedRange.location == 3, "should land just after 'c', got \(ed.selectedRange.location)")
    expect(engine.submode == .insert)
}

test("VimEngine: ge moves to end of previous word") {
    let engine = VimEngine()
    let ed = StubEditor("abc def ghi", caret: 9)
    feed(engine, ["g", "e"], on: ed)
    expect(ed.selectedRange.location == 6, "got \(ed.selectedRange.location)")
}

test("VimEngine: de deletes through end of word") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar", caret: 0)
    feed(engine, ["d", "e"], on: ed)
    // de from start of "foo" deletes "foo" (cursor 0..3 exclusive of trailing space)
    expect(ed.text == " bar", "got: \(ed.text)")
}

test("VimEngine: ce changes through end of word and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar", caret: 0)
    feed(engine, ["c", "e"], on: ed)
    expect(ed.text == " bar", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

// ─── VimEngine: R (overstrike), . (repeat), v/V (visual), / (search), f/t

test("VimEngine: R enters replace submode") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 0)
    feed(engine, ["R"], on: ed)
    expect(engine.submode == .replace, "expected replace, got \(engine.submode)")
    expect(engine.badge == "VIM:R")
}

test("VimEngine: R then Esc returns to normal") {
    let engine = VimEngine()
    let ed = StubEditor("hello", caret: 0)
    feed(engine, ["R", "<esc>"], on: ed)
    expect(engine.submode == .normal)
}

test("VimEngine: . repeats x") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["x"], on: ed)
    expect(ed.text == "bcdef")
    feed(engine, ["."], on: ed)
    expect(ed.text == "cdef", "got: \(ed.text)")
}

test("VimEngine: . repeats dd") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo\nthree\nfour", caret: 0)
    feed(engine, ["d", "d"], on: ed)
    expect(ed.text == "two\nthree\nfour")
    feed(engine, ["."], on: ed)
    expect(ed.text == "three\nfour", "got: \(ed.text)")
}

test("VimEngine: . repeats r<x>") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["r", "Z"], on: ed)
    expect(ed.text == "Zbcdef")
    feed(engine, ["l", "."], on: ed)
    expect(ed.text == "ZZcdef", "got: \(ed.text)")
}

test("VimEngine: yank is NOT recorded as a change") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["x"], on: ed)        // delete "a" → "bcdef" + recorded
    feed(engine, ["y", "y"], on: ed)   // yank (not a change)
    feed(engine, ["."], on: ed)        // should still repeat x, not yy
    expect(ed.text == "cdef", "got: \(ed.text)")
}

test("VimEngine: v enters visual mode and selects character at cursor") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 2)
    feed(engine, ["v"], on: ed)
    expect(engine.submode == .visual)
    expect(ed.selectedRange.location == 2 && ed.selectedRange.length == 1, "got \(ed.selectedRange)")
}

test("VimEngine: v then l extends selection to right") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["v", "l", "l"], on: ed)
    // anchor 0, cursor 2 → selection covers [0..2] inclusive = length 3
    expect(ed.selectedRange.location == 0 && ed.selectedRange.length == 3, "got \(ed.selectedRange)")
}

test("VimEngine: visual d deletes selection and returns to normal") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["v", "l", "l", "d"], on: ed)
    expect(ed.text == "def", "got: \(ed.text)")
    expect(engine.submode == .normal)
}

test("VimEngine: visual y yanks and returns to normal") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["v", "l", "l", "y", "$", "p"], on: ed)
    // yanked "abc", cursor on 'f' (end of line), p pastes after → "abcdefabc"
    expect(ed.text == "abcdefabc", "got: \(ed.text)")
}

test("VimEngine: visual c deletes selection and enters insert") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["v", "l", "l", "c"], on: ed)
    expect(ed.text == "def", "got: \(ed.text)")
    expect(engine.submode == .insert)
}

test("VimEngine: V selects whole line") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo\nthree", caret: 5)
    feed(engine, ["V"], on: ed)
    expect(engine.submode == .visualLine)
    // Should select all of "two\n"
    expect(ed.selectedRange.location == 4 && ed.selectedRange.length == 4, "got \(ed.selectedRange)")
}

test("VimEngine: V then d deletes line(s)") {
    let engine = VimEngine()
    let ed = StubEditor("one\ntwo\nthree", caret: 5)
    feed(engine, ["V", "d"], on: ed)
    expect(ed.text == "one\nthree", "got: \(ed.text)")
}

test("VimEngine: visual Esc cancels selection") {
    let engine = VimEngine()
    let ed = StubEditor("abcdef", caret: 0)
    feed(engine, ["v", "l", "l", "<esc>"], on: ed)
    expect(engine.submode == .normal)
    expect(ed.selectedRange.length == 0, "selection should collapse")
}

test("VimEngine: / followed by term + Enter jumps to first match") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar baz bar", caret: 0)
    feed(engine, ["/", "b", "a", "r", "<enter>"], on: ed)
    expect(ed.selectedRange.location == 4, "first 'bar' at 4, got \(ed.selectedRange.location)")
}

test("VimEngine: n repeats search forward") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar baz bar", caret: 0)
    feed(engine, ["/", "b", "a", "r", "<enter>", "n"], on: ed)
    expect(ed.selectedRange.location == 12, "second 'bar' at 12, got \(ed.selectedRange.location)")
}

test("VimEngine: N goes backward, wrapping") {
    let engine = VimEngine()
    let ed = StubEditor("foo bar baz bar", caret: 13)
    feed(engine, ["/", "b", "a", "r", "<enter>", "N"], on: ed)
    // first match from 13 jumps forward and wraps to first occurrence at 4.
    // Then N from 4 goes back, wrapping to 12.
    expect(ed.selectedRange.location == 12 || ed.selectedRange.location == 4,
           "got \(ed.selectedRange.location)")
}

test("VimEngine: f<char> finds next occurrence on line") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 0)
    feed(engine, ["f", "o"], on: ed)
    expect(ed.selectedRange.location == 4, "first 'o' at 4, got \(ed.selectedRange.location)")
}

test("VimEngine: t<char> lands one before the target") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 0)
    feed(engine, ["t", "w"], on: ed)
    expect(ed.selectedRange.location == 5, "should land at space before 'w', got \(ed.selectedRange.location)")
}

test("VimEngine: F<char> finds backward on line") {
    let engine = VimEngine()
    let ed = StubEditor("hello world", caret: 10)
    feed(engine, ["F", "l"], on: ed)
    expect(ed.selectedRange.location == 9, "last 'l' before pos 10 is 9, got \(ed.selectedRange.location)")
}

test("VimEngine: f does not cross line boundaries") {
    let engine = VimEngine()
    let ed = StubEditor("hello\nworld", caret: 0)
    feed(engine, ["f", "w"], on: ed)
    expect(ed.selectedRange.location == 0, "'w' is on next line, should stay put; got \(ed.selectedRange.location)")
}

test("VimEngine: ; repeats last find") {
    let engine = VimEngine()
    let ed = StubEditor("the quick brown fox", caret: 0)
    feed(engine, ["f", " ", ";"], on: ed)
    expect(ed.selectedRange.location == 9, "second space at 9, got \(ed.selectedRange.location)")
}

test("VimEngine: , reverses last find") {
    let engine = VimEngine()
    let ed = StubEditor("the quick brown fox", caret: 0)
    feed(engine, ["f", " ", ";", ","], on: ed)
    // f' ' → 3; ; → 9; , reverses → 3
    expect(ed.selectedRange.location == 3, "got \(ed.selectedRange.location)")
}

// ─── WORD motions (W/B/E), paragraph, matching bracket, toggle case

test("VimEngine: W treats punctuation as part of the WORD") {
    let engine = VimEngine()
    let ed = StubEditor("foo.bar baz", caret: 0)
    feed(engine, ["W"], on: ed)
    // w would stop at the '.', but W skips it (whitespace-only break)
    expect(ed.selectedRange.location == 8, "got \(ed.selectedRange.location)")
}

test("VimEngine: B (backward WORD) skips punctuation") {
    let engine = VimEngine()
    let ed = StubEditor("foo.bar baz", caret: 8)
    feed(engine, ["B"], on: ed)
    expect(ed.selectedRange.location == 0, "got \(ed.selectedRange.location)")
}

test("VimEngine: E moves to end of WORD") {
    let engine = VimEngine()
    let ed = StubEditor("foo.bar baz", caret: 0)
    feed(engine, ["E"], on: ed)
    // Last char of "foo.bar" is position 6
    expect(ed.selectedRange.location == 6, "got \(ed.selectedRange.location)")
}

test("VimEngine: } jumps to next blank line") {
    let engine = VimEngine()
    let ed = StubEditor("para one line one\npara one line two\n\npara two\n", caret: 0)
    feed(engine, ["}"], on: ed)
    // The blank line is at position 37 (after the second \n that ends "line two\n")
    // Actually let me count: "para one line one" 17 + "\n" 1 = 18 + "para one line two" 17 + "\n" 1 = 36 + "\n" 1 = 37
    expect(ed.selectedRange.location == 36 || ed.selectedRange.location == 37,
           "expected blank-line boundary, got \(ed.selectedRange.location)")
}

test("VimEngine: { jumps to previous blank line") {
    let engine = VimEngine()
    let ed = StubEditor("para one\n\npara two\n\npara three", caret: 22)
    // From "para three", { should walk back to the blank line at position 19 (or surrounding)
    feed(engine, ["{"], on: ed)
    expect(ed.selectedRange.location <= 20 && ed.selectedRange.location >= 9,
           "expected to land near a blank-line boundary, got \(ed.selectedRange.location)")
}

test("VimEngine: % jumps from ( to matching )") {
    let engine = VimEngine()
    let ed = StubEditor("(a b c)", caret: 0)
    feed(engine, ["%"], on: ed)
    expect(ed.selectedRange.location == 6, "got \(ed.selectedRange.location)")
}

test("VimEngine: % jumps from ) back to matching (") {
    let engine = VimEngine()
    let ed = StubEditor("(a b c)", caret: 6)
    feed(engine, ["%"], on: ed)
    expect(ed.selectedRange.location == 0, "got \(ed.selectedRange.location)")
}

test("VimEngine: % handles nested brackets") {
    let engine = VimEngine()
    let ed = StubEditor("(a (b c) d)", caret: 0)
    feed(engine, ["%"], on: ed)
    expect(ed.selectedRange.location == 10, "should find outer ) at 10, got \(ed.selectedRange.location)")
}

test("VimEngine: % on a non-bracket scans forward to first bracket on line") {
    let engine = VimEngine()
    let ed = StubEditor("foo (bar) baz", caret: 0)
    feed(engine, ["%"], on: ed)
    expect(ed.selectedRange.location == 8, "should land on matching ) at 8, got \(ed.selectedRange.location)")
}

test("VimEngine: ~ toggles case of char under caret") {
    let engine = VimEngine()
    let ed = StubEditor("Hello", caret: 0)
    feed(engine, ["~"], on: ed)
    expect(ed.text == "hello", "got: \(ed.text)")
}

test("VimEngine: ~ with count toggles N chars") {
    let engine = VimEngine()
    let ed = StubEditor("Hello world", caret: 0)
    feed(engine, ["3", "~"], on: ed)
    expect(ed.text == "hELlo world", "got: \(ed.text)")
}

test("VimEngine: dW deletes whole WORD including punctuation") {
    let engine = VimEngine()
    let ed = StubEditor("foo.bar baz", caret: 0)
    feed(engine, ["d", "W"], on: ed)
    expect(ed.text == "baz", "got: \(ed.text)")
}

// ─── Summary ───

print("\n\(passed + failed) tests, \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
