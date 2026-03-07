import SwiftUI
import UserNotifications

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
    @State private var journals: [String] = []
    @State private var editingEntry: JournalEntry?
    @State private var editingJournal: String?
    @State private var pendingEditEntry: JournalEntry?
    @State private var showUnsavedAlert = false
    @State private var filterTag: String?
    @AppStorage("sortNewestFirst") private var sortNewestFirst = true
    @AppStorage("selectedJournal") private var selectedJournal = "default"

    private let service = JrnlService()

    private var editorView: some View {
        EntryEditorView(
            text: $entryText,
            tagPrefix: $tagPrefix,
            onSubmit: { submit() },
            onTagKeyEvent: { event in
                handleTagKey(event)
            }
        )
        .frame(height: 150)
    }

    private var tagSuggestion: TagSuggestionView {
        TagSuggestionView(
            tags: tags,
            filter: tagPrefix,
            selectedIndex: $tagSelectedIndex
        )
    }

    private var isEditing: Bool { editingEntry != nil }

    private var displayedEntries: [JournalEntry] {
        let sorted = sortNewestFirst ? recentEntries : recentEntries.reversed()
        guard let tag = filterTag else { return sorted }
        return sorted.filter { $0.tags.contains(tag) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorView

            if !tagPrefix.isEmpty {
                tagSuggestion
            }

            // Submit bar
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
            }
            .padding(.vertical, 4)
        }
        .frame(width: 400, height: 500)
        .task {
            await loadJournals()
            await loadData()
        }
        .onChange(of: tagPrefix) { _, _ in
            tagSelectedIndex = 0
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

    private func handleTagKey(_ event: EntryEditorView.TagKeyEvent) -> Bool {
        let items = tagSuggestion.filteredTags
        guard !items.isEmpty else { return false }

        switch event {
        case .arrowDown:
            tagSelectedIndex = min(tagSelectedIndex + 1, items.count - 1)
            return true
        case .arrowUp:
            tagSelectedIndex = max(tagSelectedIndex - 1, 0)
            return true
        case .enter, .tab:
            let tag = items[tagSelectedIndex]
            insertTagViaBinding(tag)
            return true
        case .escape:
            tagPrefix = ""
            return true
        }
    }

    private func insertTagViaBinding(_ tag: Tag) {
        guard !tagPrefix.isEmpty,
              let range = entryText.range(of: tagPrefix, options: .backwards) else { return }
        entryText.replaceSubrange(range, with: tag.name + " ")
        tagPrefix = ""
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
    }

    private func cancelEdit() {
        editingEntry = nil
        editingJournal = nil
        entryText = ""
    }

    private func submit() {
        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                }
                entryText = ""
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

    private func sendNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "JrnlBar"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func loadData(for journal: String? = nil) async {
        let j = journal ?? selectedJournal
        async let tagResult = try? service.fetchTags(journal: j)
        async let entryResult = try? service.fetchRecentEntries(journal: j)
        let (t, e) = await (tagResult, entryResult)
        if let t { tags = t }
        if let e { recentEntries = e }
    }
}
