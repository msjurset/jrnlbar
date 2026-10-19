import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("JrnlBar Documentation")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    Group {
                        Text("User Guidance")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("JrnlBar is a menu bar companion for the `jrnl` CLI. It allows you to rapidly add journal entries using a global hotkey (default: ⇧⌘J).")
                        
                        Text("To create a new entry:")
                            .font(.headline)
                        Text("1. Press the global hotkey or click the menu bar icon.")
                        Text("2. Type your entry (the first sentence becomes the title).")
                        Text("3. Press Cmd+Enter to save.")
                        
                        Text("Keyboard Shortcuts")
                            .font(.headline)
                        Text("• **Cmd+Enter** - Save and close.")
                        Text("• **Cmd+E** - Open the current draft in an external editor.")
                        Text("• **Escape** - Dismiss the panel without saving (draft is autosaved).")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Permissions")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("For full functionality, JrnlBar may require the following permissions:")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text("Location Services")
                                        .font(.headline)
                                    Text("Required for `/weather` and `/loc`. Enable this for JrnlBar in **System Settings > Privacy & Security > Location Services**.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            HStack(alignment: .top) {
                                Image(systemName: "keyboard")
                                    .foregroundStyle(.orange)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text("Accessibility")
                                        .font(.headline)
                                    Text("May be required for the global hotkey and Vim mode to function reliably. Enable in **System Settings > Privacy & Security > Accessibility**.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                        .controlSize(.small)
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Slash Commands")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Type `/` anywhere in your entry to open the slash command menu. Use arrow keys to navigate and Tab/Enter to insert.")
                        
                        Text("Formatting & Context")
                            .font(.headline)
                        Text("• **/todo** - Inserts a markdown checkbox (`- [ ] `).")
                        Text("• **/quote** - Inserts a markdown blockquote (`> `).")
                        Text("• **/date** - Inserts today's date.")
                        Text("• **/now** - Inserts the current time.")
                        Text("• **/weather** - Fetches and inserts your local weather summary. You can configure temperature and wind units in Preferences.")
                        Text("• **/loc** - Fetches and inserts your current city and state.")
                        
                        Text("Modes")
                            .font(.headline)
                        Text("• **/uc** - Toggles UPPERCASE typing mode.")
                        Text("• **/vim** - Drops you into a fully-featured Vim emulator for editing.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Jrnl Integration")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("JrnlBar tightly integrates with the `jrnl` CLI to let you reference your past journal entries inline.")
                        
                        Text("Integration Commands")
                            .font(.headline)
                        Text("• **/last [n]** - Fetches and inserts your most recent journal entry (or last *n* entries) as blockquotes.")
                        Text("• **/tags [filter]** - Inserts your top 10 tags. If a filter is provided (e.g., `/tags work`), it returns matching tags. If a number is provided (e.g., `/tags 3`), it returns only that many top tags.")
                        Text("• **/suggest** - Uses Local AI to scan your current draft and suggest relevant tags based on your previous journal history.")
                        
                        Text("Official JRNL Guide")
                            .font(.headline)
                        Text("For more advanced usage of the `jrnl` CLI (multiple journals, encryption, filtering), visit the official guide:")
                        Link("https://jrnl.org/guide", destination: URL(string: "https://jrnl.org/guide")!)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("To configure JrnlBar, right click the menu bar icon and select 'Preferences...'. Here you can set the path to your `jrnl` executable if it's in a non-standard location.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
    }
}
