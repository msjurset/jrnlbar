import Foundation

public enum DraftManager {
    private static var draftURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("JrnlBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("draft.md")
    }

    public static func save(text: String) {
        // Don't save if it's just whitespace (clears the draft)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: draftURL)
            return
        }
        try? text.write(to: draftURL, atomically: true, encoding: .utf8)
    }

    public static func load() -> String {
        return (try? String(contentsOf: draftURL, encoding: .utf8)) ?? ""
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: draftURL)
    }
}
