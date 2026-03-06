import Foundation

public struct JournalEntry: Codable, Identifiable, Equatable {
    public let title: String
    public let body: String
    public let date: String
    public let time: String
    public let tags: [String]
    public let starred: Bool

    public var id: String { "\(date)-\(time)-\(title)" }

    public var displayDate: String {
        "\(date) \(time)"
    }

    public var fullText: String {
        if body.isEmpty {
            return title
        }
        return title + "\n" + body
    }

    public init(title: String, body: String, date: String, time: String, tags: [String], starred: Bool) {
        self.title = title
        self.body = body
        self.date = date
        self.time = time
        self.tags = tags
        self.starred = starred
    }
}

struct JrnlOutput: Codable {
    let entries: [JournalEntry]
}
