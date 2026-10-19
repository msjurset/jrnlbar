import SwiftUI
import AppKit

public struct PreferencesView: View {
    @AppStorage("externalEditorBundleID") private var externalEditorBundleID: String = ""
    @AppStorage("jrnlPathOverride") private var jrnlPathOverride: String = ""
    @AppStorage("weatherTempUnit") private var weatherTempUnit: String = "fahrenheit"
    @AppStorage("weatherWindUnit") private var weatherWindUnit: String = "mph"
    @State private var hotkey: HotkeyBinding? = HotkeyBinding.load(forKey: HotkeyManager.togglePanelKey)

    private let templatesPath = "~/.local/share/jrnl/templates"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Preferences")
                    .font(.title2.bold())
                
                // Jrnl Path
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jrnl executable path")
                        .font(.headline)
                    Text("Path to the jrnl CLI. If empty, JrnlBar will try to auto-detect it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        FilterField(
                            placeholder: "/opt/homebrew/bin/jrnl, /usr/local/bin/jrnl, …",
                            text: $jrnlPathOverride
                        )
                        .frame(height: 24)
                        Button("Auto-detect") {
                            jrnlPathOverride = ""
                        }
                        .controlSize(.small)
                        .disabled(jrnlPathOverride.isEmpty)
                    }
                    if !jrnlPathOverride.isEmpty && !FileManager.default.isExecutableFile(atPath: jrnlPathOverride) {
                        Text("Warning: path is not an executable file.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text("Currently using: \(JrnlPathManager.actualPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Weather
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weather units")
                        .font(.headline)
                    Text("Units used by the /weather inline command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(spacing: 8) {
                        LabeledContent("Temperature") {
                            Picker("Temperature", selection: $weatherTempUnit) {
                                Text("Fahrenheit (°F)").tag("fahrenheit")
                                Text("Celsius (°C)").tag("celsius")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        LabeledContent("Wind Speed") {
                            Picker("Wind", selection: $weatherWindUnit) {
                                Text("mph").tag("mph")
                                Text("km/h").tag("kmh")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                }
                
                Divider()
                
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

            // Toggle-panel hotkey
            VStack(alignment: .leading, spacing: 6) {
                Text("Toggle-panel hotkey")
                    .font(.headline)
                Text("Global shortcut to open / close the JrnlBar panel. Default ⇧⌘J. Esc cancels recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    HotkeyRecorder(binding: $hotkey)
                        .frame(height: 24)
                    Button("Reset to default") {
                        hotkey = .default
                    }
                    .controlSize(.small)
                }
            }
            .onChange(of: hotkey) { _, newValue in
                if let newValue {
                    newValue.save(forKey: HotkeyManager.togglePanelKey)
                } else {
                    HotkeyBinding.clear(forKey: HotkeyManager.togglePanelKey)
                }
                NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
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
        }
        .frame(minWidth: 460, maxWidth: 460, minHeight: 400)
    }

    private func revealTemplatesFolder() {
        let url = URL(fileURLWithPath: NSString(string: templatesPath).expandingTildeInPath)
        // Create if missing so the user always lands somewhere.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
