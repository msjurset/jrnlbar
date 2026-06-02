import Foundation

public enum JrnlPathManager {
    private static let userDefaultsKey = "jrnlPathOverride"
    private static let commonPaths = [
        "/opt/homebrew/bin/jrnl",    // Apple Silicon Homebrew
        "/usr/local/bin/jrnl",       // Intel Homebrew / manual install
        "/usr/bin/jrnl",             // System
        "/run/current-system/sw/bin/jrnl" // Nix
    ]

    public static var actualPath: String {
        if let override = UserDefaults.standard.string(forKey: userDefaultsKey),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback to searching PATH if possible
        if let pathFromShell = searchPath() {
            return pathFromShell
        }

        // Default to the most likely one if all else fails
        return "/opt/homebrew/bin/jrnl"
    }

    private static func searchPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["jrnl"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        // Ensure we have a reasonable PATH for the 'which' command
        var env = ProcessInfo.processInfo.environment
        let extraPaths = commonPaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               FileManager.default.isExecutableFile(atPath: output) {
                return output
            }
        } catch {
            return nil
        }
        return nil
    }
}
