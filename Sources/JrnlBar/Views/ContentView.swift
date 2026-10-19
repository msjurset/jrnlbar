import SwiftUI
import UserNotifications
import VimEngine

extension Notification.Name {
    public static let closePanel = Notification.Name("closePanel")
    public static let openPanel = Notification.Name("openPanel")
    /// Posted when /vim is activated or exited. `userInfo["active"]` is
    /// the new state. The app-level Escape monitor reads this so vim
    /// owns Esc while it's on, then yields it back to "dismiss panel"
    /// when vim exits.
    public static let vimStateChanged = Notification.Name("vimStateChanged")
}

public struct ContentView: View {
    public init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    @State private var entryText = ""
    @State private var tags: [Tag] = []
    @State private var recentEntries: [JournalEntry] = []
    @State private var statusMessage = ""
    @State private var isSubmitting = false
    @State private var tagPrefix = ""
    @State private var tagSelectedIndex = 0
    @State private var slashPrefix = ""
    @State private var slashSelectedIndex = 0
    @State private var pendingCursor: Int?
    @State private var slashCommands: [SlashCommand] = []
    @State private var currentMode: TextMode?
    @State private var vimEngine: VimEngine?
    @State private var vimBadgeText: String = "VIM:N"
    @State private var showVimCheatsheet: Bool = false
    @State private var journals: [String] = []
    @State private var editingEntry: JournalEntry?
    @State private var editingJournal: String?
    @State private var pendingEditEntry: JournalEntry?
    @State private var showUnsavedAlert = false
    @State private var filterTag: String?
    @AppStorage("sortNewestFirst") private var sortNewestFirst = true
    @AppStorage("selectedJournal") private var selectedJournal = "default"
    @AppStorage("externalEditorBundleID") private var externalEditorBundleID = ""

    private let service = JrnlService()
    private let slashRegistry = SlashCommandRegistry.shared

    private var editorView: some View {
        EntryEditorView(
            text: $entryText,
            tagPrefix: $tagPrefix,
            slashPrefix: $slashPrefix,
            pendingCursor: $pendingCursor,
            currentMode: currentMode,
            vimEngine: vimEngine,
            onSubmit: { submit() },
            onOpenExternal: { openInExternalEditor() },
            onTagKeyEvent: { event in
                handleTagKey(event)
            },
            onSlashKeyEvent: { event in
                handleSlashKey(event)
            }
        )
        .frame(height: 150)
        .overlay(alignment: .topTrailing) {
            Button(action: openInExternalEditor) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary.opacity(0.6))
            .padding(10)
            .help("Open in External Editor (Option+Cmd+Enter or Cmd+E)")
        }
    }

    private var modeBadge: some View {
        Group {
            if let mode = currentMode {
                Button(action: { exitCurrentMode() }) {
                    HStack(spacing: 3) {
                        Text(mode == .vim ? vimBadgeText : mode.badge)
                            .font(.caption2.bold())
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.3))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(modeHelp(mode))
            }
        }
    }

    private func modeHelp(_ mode: TextMode) -> String {
        switch mode {
        case .uppercase: return "Typing in uppercase. Click or type /uc again to clear."
        case .vim:       return "Vim mode. Click to exit, or :q / :vim / :wq in normal mode."
        }
    }

    private func exitCurrentMode() {
        currentMode = nil
        vimEngine = nil
        // Defensive: the cheatsheet popover is anchored to the help
        // icon which only shows while vim is active. If the binding
        // got stuck true (rare but observed), the popover could keep
        // absorbing events. Force it closed on every exit.
        showVimCheatsheet = false
    }

    private var filteredTags: [Tag] {
        let query = tagPrefix.lowercased().replacingOccurrences(of: "@", with: "")
        if query.isEmpty {
            return Array(tags.prefix(6))
        }
        return Array(tags.filter {
            $0.name.lowercased().replacingOccurrences(of: "@", with: "").hasPrefix(query)
        }.prefix(6))
    }

    private var filteredCommands: [SlashCommand] {
        var needle = slashPrefix
        while needle.hasPrefix("/") { needle.removeFirst() }
        
        let parts = needle.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return slashCommands }
        
        let lower = first.lowercased()
        if lower.isEmpty {
            return slashCommands
        }
        return slashCommands.filter { $0.name.lowercased().hasPrefix(lower) }
    }

    private var tagSuggestion: some View {
        TagSuggestionView(
            tags: tags,
            filter: tagPrefix,
            selectedIndex: $tagSelectedIndex,
            onSelect: { tag in
                insertTagViaBinding(tag)
            }
        )
    }

    private var slashSuggestion: some View {
        SlashSuggestionView(
            commands: slashCommands,
            filter: slashPrefix,
            selectedIndex: $slashSelectedIndex,
            onSelect: { cmd in
                commitSlashCommand(cmd)
            }
        )
    }


    private var isEditing: Bool { editingEntry != nil }

    private var displayedEntries: [JournalEntry] {
        let sorted = sortNewestFirst ? recentEntries : recentEntries.reversed()
        guard let tag = filterTag else { return sorted }
        return sorted.filter { $0.tags.contains(tag) }
    }

    @State private var showHelpSheet = false

    private func showHelp() {
        showHelpSheet = true
    }

    private var footer: some View {
        HStack {
            Button(action: submit) {
                Text(isEditing ? "Update Entry" : "Save Entry")
            }
            .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            if isEditing {
                Button(action: cancelEdit) {
                    Text("Cancel")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if journals.count > 1 {
                Spacer().frame(width: 16)
                HStack(spacing: 6) {
                    ForEach(Array(journals.enumerated()), id: \.element) { index, journal in
                        if index > 0 {
                            Text("|")
                                .font(.caption)
                                .foregroundStyle(.quaternary)
                        }
                        Text(journal)
                            .font(.caption)
                            .fontWeight(journal == selectedJournal ? .bold : .regular)
                            .foregroundStyle(journal == selectedJournal ? .primary : .secondary)
                            .onTapGesture {
                                guard !isEditing else { return }
                                selectedJournal = journal
                            }
                    }
                }
                .opacity(isEditing ? 0.5 : 1)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            if currentMode == .vim {
                Button(action: { showVimCheatsheet.toggle() }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Vim command reference")
                .popover(isPresented: $showVimCheatsheet, arrowEdge: .top) {
                    VimCheatsheetView()
                }
                
                Spacer().frame(width: 8)
            }

            modeBadge
            
            if currentMode == nil { Spacer().frame(width: 8) }

            if isEditing {
                Text("Editing (\(editingJournal ?? selectedJournal))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Cmd+Enter")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorView

            if !tagPrefix.isEmpty {
                tagSuggestion
            } else if !slashPrefix.isEmpty {
                slashSuggestion
            }

            footer

            ZStack {
                Divider()
                Button(action: { sortNewestFirst.toggle() }) {
                    Image(systemName: sortNewestFirst ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .frame(width: 22, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(sortNewestFirst ? "Newest first" : "Oldest first")
            }

            if let tag = filterTag {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Button(action: { filterTag = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            RecentEntriesView(
                entries: displayedEntries,
                onEdit: { entry in startEdit(entry) },
                onTagTap: { tag in filterTag = filterTag == tag ? nil : tag }
            )
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Text("Shift+Cmd+J to toggle")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                
                Button(action: showHelp) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help("JrnlBar Documentation")
                .padding(.trailing, 8)
                .sheet(isPresented: $showHelpSheet) {
                    HelpView()
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 400, height: 500)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showHelpSheet"))) { _ in
            showHelpSheet = true
        }
        .task {
            entryText = DraftManager.load()
            slashCommands = slashRegistry.reload()
            await loadJournals()
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("panelDidOpen"))) { _ in
            slashCommands = slashRegistry.reload()
            Task {
                await loadJournals()
                await loadData()
            }
        }
        .onChange(of: tagPrefix) { _, _ in
            tagSelectedIndex = 0
        }
        .onChange(of: slashPrefix) { _, _ in
            slashSelectedIndex = 0
        }
        .onChange(of: entryText) { _, newValue in
            if !isEditing {
                DraftManager.save(text: newValue)
            }
        }
        .onChange(of: currentMode) { _, newMode in
            NotificationCenter.default.post(
                name: .vimStateChanged,
                object: nil,
                userInfo: ["active": newMode == .vim]
            )
        }
        .onChange(of: selectedJournal) { _, newJournal in
            let journal = newJournal
            Task { await loadData(for: journal) }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard", role: .destructive) {
                if let pending = pendingEditEntry {
                    loadEntryForEdit(pending)
                    pendingEditEntry = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingEditEntry = nil
            }
        } message: {
            Text("You have unsaved text in the editor. Discard it and load the selected entry?")
        }
    }

    private func handleTagKey(_ event: EntryEditorView.SuggestionKeyEvent) -> Bool {
        let items = filteredTags
        guard !items.isEmpty else { return false }

        switch event {
        case .arrowDown, .arrowRight:
            tagSelectedIndex = (tagSelectedIndex + 1) % items.count
            return true
        case .arrowUp, .arrowLeft:
            tagSelectedIndex = (tagSelectedIndex - 1 + items.count) % items.count
            return true
        case .tab:
            tagSelectedIndex = (tagSelectedIndex + 1) % items.count
            return true
        case .enter:
            let tag = items[tagSelectedIndex]
            insertTagViaBinding(tag)
            return true
        case .escape:
            tagPrefix = ""
            return true
        case .space:
            return false
        }
    }

    private func insertTagViaBinding(_ tag: Tag) {
        guard !tagPrefix.isEmpty,
              let range = entryText.range(of: tagPrefix, options: .backwards) else { return }
        entryText.replaceSubrange(range, with: tag.name + " ")
        tagPrefix = ""
    }

    private func autocompleteSlashCommand(_ command: SlashCommand) {
        guard !slashPrefix.isEmpty,
              let range = entryText.range(of: slashPrefix, options: .backwards) else { return }
        
        let newText = "/" + command.name + " "
        entryText.replaceSubrange(range, with: newText)
        
        // Move cursor to end of the new text
        let prefixStartUTF16 = entryText.utf16.distance(
            from: entryText.utf16.startIndex,
            to: range.lowerBound.samePosition(in: entryText.utf16) ?? entryText.utf16.startIndex
        )
        pendingCursor = prefixStartUTF16 + newText.utf16.count
        // Update slashPrefix so the dropdown stays open and reflects the new state
        slashPrefix = newText
    }

    private func handleSlashKey(_ event: EntryEditorView.SuggestionKeyEvent) -> Bool {
        let items = filteredCommands
        guard !items.isEmpty else { return false }

        switch event {
        case .arrowDown, .arrowRight:
            slashSelectedIndex = (slashSelectedIndex + 1) % items.count
            return true
        case .arrowUp, .arrowLeft:
            slashSelectedIndex = (slashSelectedIndex - 1 + items.count) % items.count
            return true
        case .tab:
            let command = items[slashSelectedIndex]
            let prefix = slashPrefix.hasPrefix("/") ? String(slashPrefix.dropFirst()) : slashPrefix
            
            // If the typed word doesn't match the selected command name exactly,
            // autocomplete the name and add a space for arguments.
            if prefix.trimmingCharacters(in: .whitespaces).lowercased() != command.name.lowercased() {
                autocompleteSlashCommand(command)
                return true
            }
            
            // Otherwise cycle selection
            slashSelectedIndex = (slashSelectedIndex + 1) % items.count
            return true
        case .enter:
            commitSlashCommand(items[slashSelectedIndex])
            return true
        case .escape:
            slashPrefix = ""
            return true
        case .space:
            // Space commits only on an exact case-insensitive match against
            // the typed prefix AND if the command allows space-commitment; 
            // otherwise the space falls through and ends the slash context 
            // naturally (or allows typing arguments).
            if let cmd = slashRegistry.exactMatch(prefix: slashPrefix), cmd.commitsOnSpace {
                commitSlashCommand(cmd)
                return true
            }
            return false
        }
    }

    private func commitSlashCommand(_ command: SlashCommand) {
        guard !slashPrefix.isEmpty,
              let range = entryText.range(of: slashPrefix, options: .backwards) else { return }
        
        let prefixStartUTF16 = entryText.utf16.distance(
            from: entryText.utf16.startIndex,
            to: range.lowerBound.samePosition(in: entryText.utf16) ?? entryText.utf16.startIndex
        )

        // Extract arguments if any
        var arguments = ""
        let prefix = slashPrefix.hasPrefix("/") ? String(slashPrefix.dropFirst()) : slashPrefix
        let parts = prefix.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count > 1 {
            arguments = String(parts[1])
        }

        switch command {
        case .template(let template):
            let (expanded, cursorOffset) = template.expand()
            entryText.replaceSubrange(range, with: expanded)
            pendingCursor = prefixStartUTF16 + cursorOffset
            slashPrefix = ""
        case .mode(let modeCommand):
            entryText.replaceSubrange(range, with: "")
            pendingCursor = prefixStartUTF16
            slashPrefix = ""
            if currentMode == modeCommand.mode {
                exitCurrentMode()
            } else {
                activateMode(modeCommand.mode)
            }
        case .inline(let inlineCommand):
            // Clear the typed prefix immediately so the dropdown dismisses
            entryText.replaceSubrange(range, with: "")
            pendingCursor = prefixStartUTF16
            slashPrefix = ""
            
            // Execute the async command and inject the result at the cursor
            Task {
                do {
                    let result = try await inlineCommand.action(arguments, entryText)
                    if !result.isEmpty {
                        await MainActor.run {
                            // Re-calculate insertion point in case user typed while waiting
                            let currentUTF16 = entryText.utf16
                            let safeOffset = min(pendingCursor ?? prefixStartUTF16, currentUTF16.count)
                            let insertIndex = String.Index(utf16Offset: safeOffset, in: entryText)
                            entryText.insert(contentsOf: result, at: insertIndex)
                            pendingCursor = safeOffset + result.utf16.count
                        }
                    }
                } catch {
                    await MainActor.run {
                        // Insert the error text so the user knows it failed rather than silently doing nothing
                        let currentUTF16 = entryText.utf16
                        let safeOffset = min(pendingCursor ?? prefixStartUTF16, currentUTF16.count)
                        let insertIndex = String.Index(utf16Offset: safeOffset, in: entryText)
                        let errText = " [Error: \(error.localizedDescription)] "
                        entryText.insert(contentsOf: errText, at: insertIndex)
                        pendingCursor = safeOffset + errText.utf16.count
                    }
                }
            }
        }
    }

    private func activateMode(_ mode: TextMode) {
        currentMode = mode
        if mode == .vim {
            let engine = VimEngine()
            engine.onExit = {
                Task { @MainActor in self.exitCurrentMode() }
            }
            engine.onSubmit = {
                Task { @MainActor in self.submit() }
            }
            // Submode + command-line buffer drive the badge text. Push
            // updates into @State so SwiftUI re-renders the capsule.
            let refresh: () -> Void = {
                Task { @MainActor in
                    self.vimBadgeText = engine.badge
                }
            }
            engine.onSubmodeChanged = refresh
            engine.onCommandBufferChanged = refresh
            vimBadgeText = engine.badge
            vimEngine = engine
        } else {
            vimEngine = nil
        }
    }

    private func startEdit(_ entry: JournalEntry) {
        let hasUnsavedText = !entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasUnsavedText {
            pendingEditEntry = entry
            showUnsavedAlert = true
        } else {
            loadEntryForEdit(entry)
        }
    }

    private func loadEntryForEdit(_ entry: JournalEntry) {
        editingEntry = entry
        editingJournal = selectedJournal
        entryText = entry.fullText
        tagPrefix = ""
        slashPrefix = ""
    }

    private func cancelEdit() {
        editingEntry = nil
        editingJournal = nil
        entryText = DraftManager.load()
        currentMode = nil
        vimEngine = nil
        tagPrefix = ""
        slashPrefix = ""
    }

    private func submit() {
        let text = slashRegistry.unescape(entryText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        statusMessage = ""

        let currentEditEntry = editingEntry
        let currentEditJournal = editingJournal
        let submitJournal = currentEditJournal ?? selectedJournal

        Task {
            do {
                if let original = currentEditEntry, let editJournal = currentEditJournal {
                    // Delete old entry, then add updated one
                    // If the add fails, rollback by re-adding the original
                    try await service.deleteEntry(
                        containing: original.title,
                        on: original.date,
                        journal: editJournal
                    )
                    do {
                        try await service.submitEntry(
                            text,
                            journal: editJournal,
                            date: original.date,
                            time: original.time
                        )
                    } catch {
                        // Rollback: restore original entry
                        try? await service.submitEntry(
                            original.fullText,
                            journal: editJournal,
                            date: original.date,
                            time: original.time
                        )
                        throw error
                    }
                    editingEntry = nil
                    editingJournal = nil
                    statusMessage = "Updated"
                    sendNotification("Entry updated in \(editJournal)")
                } else {
                    try await service.submitEntry(text, journal: selectedJournal)
                    statusMessage = "Saved"
                    sendNotification("Entry saved to \(selectedJournal)")
                    DraftManager.clear()
                }
                entryText = ""
                currentMode = nil
                vimEngine = nil
                await loadData(for: submitJournal)
                try? await Task.sleep(for: .seconds(2))
                statusMessage = ""
            } catch {
                statusMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func loadJournals() async {
        if let j = try? await service.fetchJournals(), !j.isEmpty {
            journals = j
            if !j.contains(selectedJournal) {
                selectedJournal = j[0]
            }
        }
    }

    private func openInExternalEditor() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("jrnl_entry_\(UUID().uuidString).md")

        do {
            try entryText.write(to: tempFileURL, atomically: true, encoding: .utf8)
            if !isEditing {
                DraftManager.save(text: entryText)
            }
        } catch {
            statusMessage = "Failed to create temp file"
            return
        }

        NotificationCenter.default.post(name: .closePanel, object: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if externalEditorBundleID.isEmpty {
            process.arguments = ["-W", "-n", "-t", tempFileURL.path]
        } else {
            process.arguments = ["-W", "-n", "-b", externalEditorBundleID, tempFileURL.path]
        }

        process.terminationHandler = { _ in
            Task { @MainActor in
                if let updatedText = try? String(contentsOf: tempFileURL, encoding: .utf8) {
                    self.entryText = updatedText
                    if !self.isEditing {
                        DraftManager.save(text: updatedText)
                    }
                }
                try? FileManager.default.removeItem(at: tempFileURL)
                NotificationCenter.default.post(name: .openPanel, object: nil)
            }
        }

        do {
            try process.run()
        } catch {
            statusMessage = "Failed to open editor"
        }
    }

    private func sendNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "JrnlBar"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func loadData(for journal: String? = nil) async {
        let j = journal ?? selectedJournal
        async let tagResult: [Tag]? = try? service.fetchTags(journal: j)
        async let entryResult: [JournalEntry]? = try? service.fetchRecentEntries(journal: j)
        let (t, e) = await (tagResult, entryResult)
        tags = t ?? []
        recentEntries = e ?? []
    }
}
