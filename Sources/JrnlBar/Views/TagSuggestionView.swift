import SwiftUI

struct TagSuggestionView: View {
    let tags: [Tag]
    let filter: String
    @Binding var selectedIndex: Int

    var filteredTags: [Tag] {
        let query = filter.lowercased().replacingOccurrences(of: "@", with: "")
        if query.isEmpty {
            return Array(tags.prefix(6))
        }
        return Array(tags.filter {
            $0.name.lowercased().replacingOccurrences(of: "@", with: "").hasPrefix(query)
        }.prefix(6))
    }

    var body: some View {
        let items = filteredTags
        if !items.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, tag in
                    Text(tag.name)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            index == selectedIndex
                                ? Color.accentColor.opacity(0.3)
                                : Color.primary.opacity(0.06)
                        )
                        .clipShape(Capsule())
                        .onTapGesture {
                            selectedIndex = index
                        }
                }

                Spacer()

                Text("↑↓ Enter")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.03))
        }
    }
}
