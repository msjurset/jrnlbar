import SwiftUI

struct RecentEntriesView: View {
    let entries: [JournalEntry]
    @State private var expandedID: String?

    var body: some View {
        if entries.isEmpty {
            Text("No recent entries")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        EntryRow(
                            entry: entry,
                            isExpanded: expandedID == entry.id
                        )
                        .onTapGesture {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        }
                    }
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: JournalEntry
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if entry.starred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Text(entry.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(isExpanded ? nil : 1)
                    .truncationMode(.tail)
            }

            if isExpanded && !entry.body.isEmpty {
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.teal.opacity(0.15))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
    }
}
