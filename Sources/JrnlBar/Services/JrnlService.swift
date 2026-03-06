import Foundation

actor JrnlService {
    private let jrnlPath = "/opt/homebrew/bin/jrnl"

    func fetchJournals() throws -> [String] {
        let output = try run(arguments: ["--list"])
        var journals: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lines like: " * default -> /path/to/file"
            guard trimmed.hasPrefix("*") else { continue }
            let parts = trimmed.dropFirst().split(separator: "->", maxSplits: 1)
            guard let name = parts.first else { continue }
            journals.append(name.trimmingCharacters(in: .whitespaces))
        }
        return journals
    }

    func fetchTags(journal: String) throws -> [Tag] {
        let output = try run(arguments: [journal, "--tags"])
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

    func fetchRecentEntries(journal: String, count: Int = 10) throws -> [JournalEntry] {
        let output = try run(arguments: [journal, "--format", "json", "-n", "\(count)"])
        guard let data = output.data(using: .utf8), !output.isEmpty else {
            return []
        }
        let decoded = try JSONDecoder().decode(JrnlOutput.self, from: data)
        return decoded.entries
    }

    func submitEntry(_ text: String, journal: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jrnlPath)
        process.arguments = [journal]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()

        if let inputData = text.data(using: .utf8) {
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
