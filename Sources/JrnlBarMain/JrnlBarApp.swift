import SwiftUI
import AppKit
import Carbon.HIToolbox
import JrnlBarLib

// Carbon event handler — must be a free function for C interop
private func hotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
    )
    if hotkeyID.id == 1 {
        DispatchQueue.main.async {
            AppController.shared.togglePanel()
        }
    }
    return noErr
}

// Singleton controller — avoids dependency on NSApp.delegate
final class AppController {
    static let shared = AppController()

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var hotkeyRef: EventHotKeyRef?
    private var globalClickMonitor: Any?
    private var escapeMonitor: Any?

    func setup() {
        setupStatusItem()
        panel = FloatingPanel(contentView: ContentView())
        registerHotkey()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "jrnl")
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func registerHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 1, &eventType, nil, nil)

        let hotkeyID = EventHotKeyID(signature: OSType(0x4A524E4C), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_J), UInt32(shiftKey | cmdKey), hotkeyID,
            GetApplicationEventTarget(), 0, &hotkeyRef
        )
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = buttonFrame.midX - panel.frame.width / 2
        let y = buttonFrame.minY - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.showAnimated()
        installMonitors()
    }

    private func closePanel() {
        panel.closeAnimated {
            self.removeMonitors()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let aboutItem = NSMenuItem(title: "About JrnlBar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            self.closePanel()
            return nil
        }
    }

    private func removeMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
    }
}

// MARK: - Entry point

@main
enum JrnlBarApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Set up everything before the run loop starts
        AppController.shared.setup()

        app.run()
    }
}

// MARK: - Styled floating panel

class FloatingPanel: NSPanel {
    init<V: View>(contentView: V) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .popUpMenu
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        effectView.material = .popover
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = effectView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.layer?.backgroundColor = nil

        effectView.addSubview(hosting)
        self.contentView = effectView
    }

    override var canBecomeKey: Bool { true }

    func showAnimated() {
        guard let contentView = self.contentView else { return }
        alphaValue = 0
        contentView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            contentView.layer?.setAffineTransform(.identity)
        }
    }

    func closeAnimated(completion: @escaping () -> Void) {
        guard let contentView = self.contentView else {
            orderOut(nil)
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            contentView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            contentView.layer?.setAffineTransform(.identity)
            completion()
        })
    }
}
