import Foundation

struct JournalEntry: Codable, Identifiable {
    let title: String
    let body: String
    let date: String
    let time: String
    let tags: [String]
    let starred: Bool

    var id: String { "\(date)-\(time)-\(title)" }

    var displayDate: String {
        // date comes as "YYYY-MM-DD", time as "HH:MM"
        "\(date) \(time)"
    }
}

struct JrnlOutput: Codable {
    let tags: [String: [String]]
    let entries: [JournalEntry]
}
