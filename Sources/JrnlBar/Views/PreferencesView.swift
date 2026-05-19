import SwiftUI
import AppKit

public struct PreferencesView: View {
    @AppStorage("externalEditorBundleID") private var externalEditorBundleID: String = ""

    private let templatesPath = "~/.local/share/jrnl/templates"

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preferences")
                .font(.title2.bold())

            // External editor
            VStack(alignment: .leading, spacing: 6) {
                Text("External editor")
                    .font(.headline)
                Text("App bundle ID used by Cmd+E to open the draft. Leave empty for the system default text editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FilterField(
                    placeholder: "pro.writer.mac, com.microsoft.VSCode, …",
                    text: $externalEditorBundleID
                )
                .frame(height: 24)
                HStack(spacing: 8) {
                    Button("iA Writer") { externalEditorBundleID = "pro.writer.mac" }
                    Button("VS Code") { externalEditorBundleID = "com.microsoft.VSCode" }
                    Button("Obsidian") { externalEditorBundleID = "md.obsidian" }
                    Button("Clear") { externalEditorBundleID = "" }
                        .disabled(externalEditorBundleID.isEmpty)
                }
                .controlSize(.small)
            }

            Divider()

            // Templates
            VStack(alignment: .leading, spacing: 6) {
                Text("Templates")
                    .font(.headline)
                Text("JrnlBar reads slash-command templates from the same folder jrnl's `--template` flag uses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(templatesPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal in Finder", action: revealTemplatesFolder)
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 460, height: 280)
    }

    private func revealTemplatesFolder() {
        let url = URL(fileURLWithPath: NSString(string: templatesPath).expandingTildeInPath)
        // Create if missing so the user always lands somewhere.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
