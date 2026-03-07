import SwiftUI
import AppKit

struct RecentEntriesView: View {
    let entries: [JournalEntry]
    var onEdit: ((JournalEntry) -> Void)?
    var onTagTap: ((String) -> Void)?
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
                            onEdit: onEdit,
                            onTagTap: onTagTap
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
    var onTagTap: ((String) -> Void)?

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
                Text(highlightedBody(entry.body))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "jrnltag", let tag = url.host {
                            onTagTap?("@\(tag)")
                        }
                        return .handled
                    })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
    }

    private func highlightedBody(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "@(\\w+)") else {
            return attributed
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let attrRange = AttributedString.Index(swiftRange.lowerBound, within: attributed)!
                ..< AttributedString.Index(swiftRange.upperBound, within: attributed)!
            let tagName = nsText.substring(with: match.range(at: 1))
            attributed[attrRange].foregroundColor = .systemTeal
            attributed[attrRange].link = URL(string: "jrnltag://\(tagName)")
        }
        return attributed
    }
}
