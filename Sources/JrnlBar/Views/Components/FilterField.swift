import AppKit
import SwiftUI

/// A text field that suppresses macOS autofill/autocomplete popups.
/// Use this instead of SwiftUI TextField for every text input on macOS —
/// SwiftUI TextField shows a phantom autocomplete dropdown no modifier
/// can kill.
///
/// Internally this is a SwiftUI `ZStack` overlaying a SwiftUI `Text`
/// placeholder on top of an `NSViewRepresentable`-wrapped
/// `NoAutoFillTextField`. The NSTextField's own `placeholderString` is
/// kept empty so the cell never draws a placeholder — that draw path
/// has a known bug with the externally-supplied shared field editor
/// (layer 5 of the autofill suppression stack) where the cell's
/// `stringValue` stays empty during typing and the placeholder ghosts
/// under the typed text. Driving placeholder visibility from the
/// SwiftUI side via `text.isEmpty` sidesteps that entirely.
struct FilterField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)?
    var onFocus: (() -> Void)?
    var autoFocus: Bool = false
    var isDisabled: Bool = false
    /// Bumping this integer requests that the field become first responder.
    /// Use instead of SwiftUI @FocusState, which doesn't bind to NSViewRepresentable.
    var focusTrigger: Int = 0
    /// One-shot caret move request. When non-nil, the field positions its
    /// caret there and clears the binding so the request isn't applied
    /// twice. User-driven cursor moves never write to this binding —
    /// the source of truth for the live caret is the field editor itself.
    /// Used by suggestion-accept handlers to land the cursor at the end
    /// of the inserted text (e.g. after "is" → "is:" the cursor goes to
    /// 3, not 2, so the next keystroke types past the colon).
    @Binding var pendingCursor: Int?
    /// Visual style — .rounded for form/sheet inputs, .plain for inline search bars.
    var style: Style = .rounded

    enum Style { case rounded, plain }

    init(placeholder: String,
         text: Binding<String>,
         onCommit: (() -> Void)? = nil,
         onFocus: (() -> Void)? = nil,
         autoFocus: Bool = false,
         isDisabled: Bool = false,
         focusTrigger: Int = 0,
         pendingCursor: Binding<Int?> = .constant(nil),
         style: Style = .rounded) {
        self.placeholder = placeholder
        self._text = text
        self.onCommit = onCommit
        self.onFocus = onFocus
        self.autoFocus = autoFocus
        self.isDisabled = isDisabled
        self.focusTrigger = focusTrigger
        self._pendingCursor = pendingCursor
        self.style = style
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                // Placeholder rendered by SwiftUI rather than the
                // NSTextField cell. Keeps it cleanly under our control:
                // hides the moment text is non-empty, with no chance of
                // ghosting under the typed text.
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, style == .rounded ? 6 : 0)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            FilterFieldRepresentable(
                text: $text,
                onCommit: onCommit,
                onFocus: onFocus,
                autoFocus: autoFocus,
                isDisabled: isDisabled,
                focusTrigger: focusTrigger,
                pendingCursor: $pendingCursor,
                style: style
            )
        }
    }
}

/// AppKit wrapper around NoAutoFillTextField. Internal — callers should
/// use `FilterField` (which adds the SwiftUI placeholder overlay).
private struct FilterFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (() -> Void)?
    var onFocus: (() -> Void)?
    var autoFocus: Bool
    var isDisabled: Bool
    var focusTrigger: Int
    @Binding var pendingCursor: Int?
    var style: FilterField.Style

    func makeNSView(context: Context) -> NoAutoFillTextField {
        let field = NoAutoFillTextField()
        // Forward focus-arrival to the SwiftUI caller (e.g. JobSearchField
        // refreshes its suggestion list based on the current text on
        // every focus, not just on text-change). Covers BOTH mouse-clicks
        // and programmatic makeFirstResponder. updateNSView reassigns
        // this each render so the closure stays bound to the latest
        // SwiftUI state.
        field.onFocusReceived = onFocus
        // Empty placeholder — the SwiftUI overlay handles placeholder
        // display. If we left this as the user-supplied text, the cell
        // would draw it under typed content because the shared field
        // editor leaves the cell's stringValue empty during typing.
        field.placeholderString = ""
        // Single-line cell settings ensure the field renders on the
        // standard single-line input draw path (matches homebar-mac's
        // working pattern).
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        switch style {
        case .rounded:
            field.bezelStyle = .roundedBezel
            field.isBordered = true
            field.drawsBackground = true
        case .plain:
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
        }
        field.delegate = context.coordinator
        field.isAutomaticTextCompletionEnabled = false
        field.contentType = .none
        context.coordinator.lastFocusTrigger = focusTrigger
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                field.window?.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NoAutoFillTextField, context: Context) {
        nsView.isEnabled = !isDisabled
        // Re-bind onFocusReceived each render so the closure captures
        // the latest SwiftUI state (callers often close over @State
        // that changes between renders).
        nsView.onFocusReceived = onFocus
        let editor = nsView.currentEditor() as? NSTextView
        // When the field is focused (editor attached), bypass the
        // cell entirely. Writing nsView.stringValue triggers AppKit's
        // "select all on programmatic change" behavior AND the
        // singleton shared field editor doesn't reliably propagate
        // cell writes to its text storage in the same render pass —
        // either of which would override our selectedRange request
        // and land the caret at position 0 / end-of-old-text. Going
        // straight to textStorage keeps editor + caret in lockstep.
        if let editor, let storage = editor.textStorage {
            if storage.string != text {
                context.coordinator.isProgrammaticEdit = true
                storage.beginEditing()
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
                storage.endEditing()
                DispatchQueue.main.async {
                    context.coordinator.isProgrammaticEdit = false
                }
            }
            if let cursor = pendingCursor {
                // AppKit's textDidChange post-processing (from
                // storage.endEditing above) can reset the editor's
                // selection — applying selectedRange synchronously
                // alone gets clobbered. Re-apply on the next runloop
                // tick so our request outlasts that post-processing.
                let target = cursor
                editor.selectedRange = NSRange(location: max(0, min(target, storage.length)), length: 0)
                DispatchQueue.main.async {
                    if let e = nsView.currentEditor() as? NSTextView,
                       let s = e.textStorage {
                        let clamped = max(0, min(target, s.length))
                        e.selectedRange = NSRange(location: clamped, length: 0)
                    }
                    self.pendingCursor = nil
                }
            }
        } else {
            // No editor (field not focused). Cell stringValue is the
            // only source we can update, and pendingCursor has no
            // editor to act on — clear it so it doesn't apply later
            // against the wrong text.
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
            if pendingCursor != nil {
                DispatchQueue.main.async { self.pendingCursor = nil }
            }
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: (() -> Void)?
        var lastFocusTrigger: Int = 0
        /// Set while updateNSView is writing to stringValue / editor.string
        /// programmatically. Suppresses the resulting controlTextDidChange
        /// echo so it doesn't write the value we just wrote back into
        /// the binding (which would be a no-op for value but could
        /// override an in-flight user-driven binding update).
        var isProgrammaticEdit = false

        init(text: Binding<String>, onCommit: (() -> Void)?) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isProgrammaticEdit else { return }
            guard let field = obj.object as? NSTextField else { return }
            // With the singleton shared field editor (layer 5 of the
            // autofill suppression stack), the cell's `stringValue`
            // stays empty during typing and `field.currentEditor()`
            // can return nil mid-notification. The notification's
            // `NSFieldEditor` userInfo key is the canonical source —
            // it carries the live field editor for this change event.
            // Falling back to currentEditor and stringValue covers
            // edge paths (programmatic edits, services), but the
            // userInfo path is what actually fires on every keystroke.
            let editor = (obj.userInfo?["NSFieldEditor"] as? NSText)
                ?? (field.currentEditor())
            let newText = editor?.string ?? field.stringValue
            text.wrappedValue = newText
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            onCommit?()
        }
    }
}

/// NSTextField subclass that refuses all autofill and autocompletion.
/// The field editor (NSTextView) must be reconfigured in three places —
/// becomeFirstResponder, textDidBeginEditing, and textShouldBeginEditing —
/// because AppKit re-enables auto-* flags at each lifecycle point.
final class NoAutoFillTextField: NSTextField {
    override var allowsCharacterPickerTouchBarItem: Bool {
        get { false }
        set {}
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layer-5 install at the earliest moment a field's window is
        // known. AppKit calls this synchronously when the view is
        // attached to a window — before any focus event is possible —
        // so our shared field-editor singleton is wired before
        // becomeFirstResponder fires. Eliminates per-call-site
        // DispatchQueue.main.async install races.
        if let window {
            installFieldEditorInterceptor(on: window)
        }
    }

    /// Called the moment the field receives first-responder status —
    /// covers BOTH mouse-clicks into the field AND programmatic
    /// focus changes. NSText's controlTextDidBeginEditing only fires
    /// on first edit, not on click-in, so the SwiftUI side needs
    /// this hook to react to focus arrival itself (e.g. refreshing
    /// suggestion lists from the current text). Convention from
    /// stash-mac / workspace CLAUDE.md.
    var onFocusReceived: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            disableAllAutoComplete(editor)
        }
        if result { onFocusReceived?() }
        return result
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        if let editor = currentEditor() as? NSTextView {
            disableAllAutoComplete(editor)
        }
    }

    override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        if let editor = textObject as? NSTextView {
            disableAllAutoComplete(editor)
        }
        return super.textShouldBeginEditing(textObject)
    }

    /// Force the cell to be our subclass so the cell-level
    /// `setUpFieldEditor` override gets installed. Without this, AppKit
    /// hands the field its default NSTextFieldCell.
    override class var cellClass: AnyClass? {
        get { NoAutoFillTextFieldCell.self }
        set {}
    }

    fileprivate func disableAllAutoComplete(_ editor: NSTextView) {
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        // macOS 14 added an inline-prediction bar that renders as a
        // large ghost popup beneath the field on focus. The usual
        // auto-* flags don't disable it; this trait does.
        if #available(macOS 14.0, *) {
            editor.inlinePredictionType = .no
        }
        // macOS 15 wired Apple Intelligence Writing Tools into every
        // editable NSTextView — the same big rounded popup reappeared
        // because the prediction surface moved here. Setting the
        // behavior to .none and rejecting all actions covers both the
        // Writing Tools floating panel and the inline rewrite affordance.
        if #available(macOS 15.0, *) {
            editor.writingToolsBehavior = .none
            editor.allowedWritingToolsResultOptions = []
        }
    }
}

/// Cell that disables predictions on the field editor *before* it
/// begins taking input. NSTextField's `becomeFirstResponder` /
/// `textDidBeginEditing` overrides aren't enough on macOS 15 — the
/// empty rounded-rect inline-prediction popup is scheduled inside
/// `super.becomeFirstResponder()`, so by the time those hooks fire,
/// the popup has already been laid out and shown once.
/// `NSTextFieldCell.setUpFieldEditor` runs earlier in the focus chain,
/// before AppKit attaches the editor for input — that's the only point
/// where setting `inlinePredictionType = .no` actually suppresses the
/// initial popup.
final class NoAutoFillTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let configured = super.setUpFieldEditorAttributes(textObj)
        if let editor = configured as? NSTextView,
           let owner = controlView as? NoAutoFillTextField {
            owner.disableAllAutoComplete(editor)
        }
        return configured
    }
}
