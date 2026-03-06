import SwiftUI

struct RecentEntriesView: View {
    let entries: [JournalEntry]
    var onEdit: ((JournalEntry) -> Void)?
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
                            isExpanded: expandedID == entry.id,
                            onEdit: onEdit
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
    var onEdit: ((JournalEntry) -> Void)?

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

                Spacer()

                if isExpanded, let onEdit {
                    Button(action: { onEdit(entry) }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit entry")
                }
            }

            if isExpanded && !entry.body.isEmpty {
                highlightedBody(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
    }

    private func highlightedBody(_ text: String) -> Text {
        guard let regex = try? NSRegularExpression(pattern: "@\\w+") else {
            return Text(text)
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = Text("")
        var lastEnd = 0

        for match in matches {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if beforeRange.length > 0 {
                result = result + Text(nsText.substring(with: beforeRange))
            }
            result = result + Text(nsText.substring(with: match.range)).foregroundColor(.teal)
            lastEnd = match.range.location + match.range.length
        }

        let tailRange = NSRange(location: lastEnd, length: nsText.length - lastEnd)
        if tailRange.length > 0 {
            result = result + Text(nsText.substring(with: tailRange))
        }
        return result
    }
}
