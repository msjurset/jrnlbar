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

// ─── Summary ───

print("\n\(passed + failed) tests, \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
