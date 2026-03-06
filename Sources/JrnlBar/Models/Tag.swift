import Foundation

struct Tag: Identifiable, Hashable {
    let name: String
    let count: Int

    var id: String { name }
}
