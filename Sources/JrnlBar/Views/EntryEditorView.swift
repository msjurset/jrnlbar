import SwiftUI
import AppKit

struct EntryEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var tagPrefix: String  // Current @partial text, empty when no tag context
    var onSubmit: () -> Void
    var onTagKeyEvent: (TagKeyEvent) -> Bool  // Returns true if handled

    enum TagKeyEvent {
        case arrowUp, arrowDown, enter, escape, tab
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = JrnlTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        let highlighter = MarkdownHighlighter()
        textStorage.delegate = highlighter
        context.coordinator.highlighter = highlighter

        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.submitHandler = { coordinator.parent.onSubmit() }
        textView.tagKeyHandler = { event in coordinator.parent.onTagKeyEvent(event) }
        textView.isShowingTags = { !coordinator.parent.tagPrefix.isEmpty }
        context.coordinator.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            context.coordinator.updatingFromBinding = true
            textView.string = text
            textView.textStorage?.edited(.editedCharacters, range: NSRange(location: 0, length: 0), changeInLength: 0)
            context.coordinator.updatingFromBinding = false
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EntryEditorView
        var textView: NSTextView?
        var highlighter: MarkdownHighlighter?
        var updatingFromBinding = false

        init(_ parent: EntryEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !updatingFromBinding else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.tagPrefix = findTagPrefix(in: textView)
        }

        private func findTagPrefix(in textView: NSTextView) -> String {
            let cursorLocation = textView.selectedRange().location
            let string = textView.string
            guard cursorLocation > 0, cursorLocation <= string.count else { return "" }

            let nsString = string as NSString
            var i = cursorLocation - 1
            while i >= 0 {
                let ch = nsString.character(at: i)
                guard let scalar = Unicode.Scalar(ch) else { return "" }
                if scalar == "@" {
                    return nsString.substring(with: NSRange(location: i, length: cursorLocation - i))
                } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                    i -= 1
                } else {
                    return ""
                }
            }
            return ""
        }

        /// Replace the current @prefix in the text view with the given tag name.
        func insertTag(_ tagName: String) {
            guard let textView = textView else { return }
            let prefix = parent.tagPrefix
            guard !prefix.isEmpty else { return }

            let cursor = textView.selectedRange().location
            let prefixStart = cursor - prefix.count
            let range = NSRange(location: prefixStart, length: prefix.count)

            let replacement = tagName + " "
            textView.shouldChangeText(in: range, replacementString: replacement)
            textView.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()

            parent.text = textView.string
            parent.tagPrefix = ""
        }
    }
}

class JrnlTextView: NSTextView {
    var submitHandler: (() -> Void)?
    var tagKeyHandler: ((EntryEditorView.TagKeyEvent) -> Bool)?
    var isShowingTags: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Cmd+Enter → submit
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            submitHandler?()
            return
        }

        // When tag suggestions are showing, intercept navigation keys
        if isShowingTags?() == true {
            switch event.keyCode {
            case 125: // down arrow
                if tagKeyHandler?(.arrowDown) == true { return }
            case 126: // up arrow
                if tagKeyHandler?(.arrowUp) == true { return }
            case 36:  // enter/return
                if tagKeyHandler?(.enter) == true { return }
            case 48:  // tab
                if tagKeyHandler?(.tab) == true { return }
            case 53:  // escape
                if tagKeyHandler?(.escape) == true { return }
            default:
                break
            }
        }

        super.keyDown(with: event)
    }
}
