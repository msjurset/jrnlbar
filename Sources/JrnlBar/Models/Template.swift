import Foundation

public struct Template: Identifiable, Hashable {
    public let name: String
    public let body: String
    public let path: URL

    public var id: String { name }

    public init(name: String, body: String, path: URL) {
        self.name = name
        self.body = body
        self.path = path
    }

    /// Expand placeholder tokens. Returns the expanded text and the UTF-16
    /// offset where the caret should land after insertion (the position of
    /// `{{cursor}}`, or end-of-text if none).
    public func expand(now: Date = Date(), locale: Locale = .current) -> (text: String, cursorOffset: Int) {
        let date = Template.formatter(format: "yyyy-MM-dd", locale: locale).string(from: now)
        let time = Template.formatter(format: "HH:mm", locale: locale).string(from: now)
        let weekday = Template.formatter(format: "EEEE", locale: locale).string(from: now)

        let expanded = body
            .replacingOccurrences(of: "{{date}}", with: date)
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{weekday}}", with: weekday)

        let nsText = expanded as NSString
        let cursorRange = nsText.range(of: "{{cursor}}")
        if cursorRange.location != NSNotFound {
            let mutable = NSMutableString(string: expanded)
            mutable.replaceCharacters(in: cursorRange, with: "")
            return (mutable as String, cursorRange.location)
        }
        return (expanded, nsText.length)
    }

    private static func formatter(format: String, locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }
}
