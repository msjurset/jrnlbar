import Foundation

public enum JrnlParser {
    public static func parseJournals(from output: String) -> [String] {
        var journals: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }
            let parts = trimmed.dropFirst().split(separator: "->", maxSplits: 1)
            guard let name = parts.first else { continue }
            journals.append(name.trimmingCharacters(in: .whitespaces))
        }
        return journals
    }

    public static func parseTags(from output: String) -> [Tag] {
        var tags: [Tag] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("@") else { continue }
            let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            tags.append(Tag(name: name, count: count))
        }
        return tags.sorted { $0.count > $1.count }
    }

    public static func parseEntries(from output: String) throws -> [JournalEntry] {
        guard let data = output.data(using: .utf8), !output.isEmpty else {
            return []
        }
        let decoded = try JSONDecoder().decode(JrnlOutput.self, from: data)
        return decoded.entries
    }

    public static func buildSubmitContent(_ text: String, date: String?, time: String?) -> String {
        if let date, let time {
            return "\(date) \(time): \(text)"
        }
        return text
    }
}

actor JrnlService {
    private let jrnlPath = "/opt/homebrew/bin/jrnl"

    func fetchJournals() throws -> [String] {
        let output = try run(arguments: ["--list"])
        return JrnlParser.parseJournals(from: output)
    }

    func fetchTags(journal: String) throws -> [Tag] {
        let output = try run(arguments: [journal, "--tags"])
        return JrnlParser.parseTags(from: output)
    }

    func fetchRecentEntries(journal: String, count: Int = 10) throws -> [JournalEntry] {
        let output = try run(arguments: [journal, "--format", "json", "-n", "\(count)"])
        return try JrnlParser.parseEntries(from: output)
    }

    func deleteEntry(containing title: String, on date: String, journal: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jrnlPath)
        process.arguments = [journal, "--delete", "-on", date, "-contains", title]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()

        // jrnl --delete prompts for confirmation; send "Y\n"
        if let yesData = "Y\n".data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(yesData)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw JrnlError.commandFailed(errorMessage)
        }
    }

    func submitEntry(_ text: String, journal: String, date: String? = nil, time: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jrnlPath)
        process.arguments = [journal]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()

        let content = JrnlParser.buildSubmitContent(text, date: date, time: time)
        if let inputData = content.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(inputData)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw JrnlError.commandFailed(errorMessage)
        }
    }

    private func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jrnlPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw JrnlError.commandFailed(errorMessage)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

enum JrnlError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "jrnl error: \(message)"
        }
    }
}
