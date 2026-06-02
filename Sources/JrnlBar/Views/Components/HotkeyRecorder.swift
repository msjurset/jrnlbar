import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted after the user records a new hotkey in Preferences. The
    /// app-level Carbon registration listens for this and re-registers.
    public static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

/// Namespace for UserDefaults keys used by the hotkey system.
public enum HotkeyManager {
    public static let togglePanelKey = "togglePanelHotkey"
}

/// Persisted binding for a single global hotkey. Stored as two ints in
/// UserDefaults: `keyCode` (Cocoa NSEvent keyCode, which is the same
/// value as Carbon's `kVK_*` constants) and `modifiers` (a Carbon
/// modifier mask — `cmdKey | shiftKey | optionKey | controlKey`).
public struct HotkeyBinding: Equatable, Hashable, Codable {
    public let keyCode: UInt16
    /// Carbon modifier mask (`cmdKey | shiftKey | …`), NOT Cocoa's
    /// `NSEvent.ModifierFlags` bitfield. Conversions happen at the
    /// recorder boundary.
    public let modifiers: UInt32

    public init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Default `Shift+Cmd+J` to match the previously hard-coded combo.
    public static let `default` = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_J),
        modifiers: UInt32(shiftKey | cmdKey)
    )

    /// Compact key-equivalent style display (e.g. `⇧⌘J`).
    public var display: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += HotkeyBinding.keyName(for: keyCode)
        return out
    }

    private static let alphanumerics: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9", 29: "0"
    ]
    private static let namedKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12"
    ]

    public static func keyName(for keyCode: UInt16) -> String {
        if let s = alphanumerics[keyCode] { return s }
        if let s = namedKeys[keyCode]     { return s }
        return "Key \(keyCode)"
    }
}

extension HotkeyBinding {
    /// Persist + restore via UserDefaults under a single key (Codable JSON blob).
    public static func load(forKey key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return nil }
        return value
    }

    public func save(forKey key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func clear(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// SwiftUI wrapper around an NSView that records the next keyDown the
/// user types into a `HotkeyBinding`. Posts the binding via `onChange`
/// and `onCommit`; the host is responsible for persisting it.
public struct HotkeyRecorder: NSViewRepresentable {
    @Binding public var binding: HotkeyBinding?
    public var placeholder: String

    public init(binding: Binding<HotkeyBinding?>, placeholder: String = "Click to record") {
        self._binding = binding
        self.placeholder = placeholder
    }

    public func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.placeholder = placeholder
        view.binding = binding
        view.onChange = { newBinding in
            // Avoid writing during view-update by deferring one tick.
            DispatchQueue.main.async { self.binding = newBinding }
        }
        return view
    }

    public func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.placeholder = placeholder
        nsView.binding = binding
        nsView.needsDisplay = true
    }
}

/// Custom NSView that draws the current binding (or a placeholder), can
/// become first responder on click, and captures the next keyDown as a
/// new binding.
public final class HotkeyRecorderView: NSView {
    public var binding: HotkeyBinding? { didSet { needsDisplay = true } }
    public var placeholder: String = "Click to record"
    public var onChange: ((HotkeyBinding?) -> Void)?

    private var isRecording: Bool = false { didSet { needsDisplay = true } }

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        isRecording = ok
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { isRecording = false }
        return ok
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    public override func keyDown(with event: NSEvent) {
        // Esc cancels recording without changing the binding.
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        // Require at least one modifier so the user doesn't bind a bare
        // letter as a global hotkey.
        let cocoa = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = HotkeyRecorderView.carbonModifiers(from: cocoa)
        guard carbon != 0 else {
            NSSound.beep()
            return
        }
        let newBinding = HotkeyBinding(keyCode: event.keyCode, modifiers: carbon)
        onChange?(newBinding)
        window?.makeFirstResponder(nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bg: NSColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : NSColor.textBackgroundColor
        bg.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        border.lineWidth = 1
        border.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Type a key combination…"
            color = .secondaryLabelColor
        } else if let b = binding {
            text = b.display
            color = .labelColor
        } else {
            text = placeholder
            color = .tertiaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = attributed.size()
        let origin = NSPoint(x: 8, y: (bounds.height - size.height) / 2)
        attributed.draw(at: origin)
    }

    /// Convert a Cocoa modifier mask to the Carbon modifier mask used
    /// by `RegisterEventHotKey`.
    private static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if cocoa.contains(.command)  { out |= UInt32(cmdKey) }
        if cocoa.contains(.shift)    { out |= UInt32(shiftKey) }
        if cocoa.contains(.option)   { out |= UInt32(optionKey) }
        if cocoa.contains(.control)  { out |= UInt32(controlKey) }
        return out
    }
}
