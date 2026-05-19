import AppKit
import Quartz
import SwiftUI

/// Once-and-for-all suppression of the empty rounded-rectangle popup
/// that appears the first time any field-editor or menu surface
/// initializes in a window on macOS 15. The popup is whatever
/// predictive-text / Apple Intelligence subsystem AppKit warms up when
/// it first creates the window's shared field editor — by providing
/// our own pre-configured editor *before* AppKit gets a chance to
/// instantiate the default one, the warm-up has nothing to render.
///
/// The interception happens via NSWindowDelegate's
/// `windowWillReturnFieldEditor(_:to:)` — when that returns non-nil,
/// AppKit uses it in place of its own default editor. SwiftUI assigns
/// its own internal delegate to the windows it creates, so we wrap
/// that delegate via a forwarding NSObject (`responds(to:)` +
/// `forwardingTarget(for:)`) and only add this single method on top.
/// Everything SwiftUI's delegate did before still happens; we just
/// inject one extra hook.

/// The pre-configured field editor returned by every wrapped window.
/// One per app — NSText/NSTextView field editors are designed to be
/// shared; AppKit checks that the returned editor isn't already in
/// use elsewhere and falls back to its own pool when it is, so a
/// shared instance plus the same disabled flags is the canonical
/// shape.
@MainActor
private let sharedNoAutoFillFieldEditor: NSTextView = {
    let editor = NSTextView()
    editor.isFieldEditor = true
    configureNoAutoFill(editor)
    return editor
}()

@MainActor
private func configureNoAutoFill(_ editor: NSTextView) {
    editor.isAutomaticTextCompletionEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticDataDetectionEnabled = false
    editor.isAutomaticLinkDetectionEnabled = false
    if #available(macOS 14.0, *) {
        editor.inlinePredictionType = .no
    }
    if #available(macOS 15.0, *) {
        editor.writingToolsBehavior = .none
        editor.allowedWritingToolsResultOptions = []
    }
    // Note: do NOT set editor.textColor / insertionPointColor /
    // backgroundColor / drawsBackground here on macOS 26. Touching
    // any of those on the singleton field editor caused AppKit to
    // throw an NSException out of `_postWindowNeedsUpdateConstraints`
    // during a SwiftUI hosting-view layout pass — observed as a
    // SIGTRAP the first time the user typed. The dark-mode text
    // legibility fix has to come via a different path (per-field
    // override or an NSTextField subclass attribute).
}

/// Forwarding NSObject that wraps an existing NSWindowDelegate and
/// adds `windowWillReturnFieldEditor`. All other delegate calls are
/// forwarded transparently so SwiftUI's window machinery (drag, key
/// equivalents, restoration, etc.) keeps working.
final class FieldEditorInterceptor: NSObject, NSWindowDelegate {
    weak var wrapped: NSObject?

    init(wrapping wrapped: NSObject?) {
        self.wrapped = wrapped
        super.init()
    }

    /// Tell AppKit we respond to a selector if EITHER we implement it
    /// directly, or the wrapped delegate does. Without this AppKit
    /// won't even attempt forwarding for selectors we don't define.
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return wrapped?.responds(to: aSelector) ?? false
    }

    /// Route any selector this interceptor doesn't define to the
    /// wrapped delegate. Selectors we DO define (notably
    /// windowWillReturnFieldEditor) get handled here.
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let wrapped, wrapped.responds(to: aSelector) else { return nil }
        return wrapped
    }

    @MainActor
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        // Re-apply flags every time AppKit asks for the editor — some
        // of these are reset between editor uses, and Sequoia in
        // particular re-enables `inlinePredictionType` on reuse.
        configureNoAutoFill(sharedNoAutoFillFieldEditor)
        return sharedNoAutoFillFieldEditor
    }
}

/// Strong references to installed interceptors, keyed by window
/// identity. Without this the wrapped objects would dealloc as soon
/// as `installFieldEditorInterceptor` returns since NSWindow.delegate
/// is a weak reference.
@MainActor
private var installedInterceptors: [ObjectIdentifier: FieldEditorInterceptor] = [:]

/// Heuristic class-name fragments that identify AppKit predictive /
/// Writing-Tools / inline-suggestion panels. Match is substring
/// `contains`-based since Apple namespaces these with private
/// underscore-prefixed classes and the exact names vary by macOS
/// version. False positives would orderOut some other AppKit panel
/// but the fragments are specific enough — "InlinePrediction",
/// "WritingTools", "InlineSuggestion", "PredictionPanel" — that no
/// legitimate panel in our app would match.
@MainActor
private let predictivePanelFragments: [String] = [
    "InlinePrediction",
    "InlineSuggestion",
    "PredictionPanel",
    "WritingTools",
    "TextCompletion",
    // macOS 26's empty-rounded autofill popup — confirmed via
    // reaper diagnostics (~/.recruit/reaper.log). Animates from
    // ~312×237 to ~332×265 right after a layout change (cold
    // launch or console expand). The "SP" prefix isn't Sparkle —
    // Sparkle uses SU/SPU. This is the system predictive surface
    // that none of the documented per-editor flags suppress.
    "SPRoundedWindow",
]

/// Order-out any visible panel whose class name matches a known
/// predictive-text fragment. Cheap to call (NSApp.windows is small)
/// and idempotent so multiple triggers per second are fine.
///
/// Diagnostic mode: when `verbose` is true, also logs the class
/// name of every visible window — used to identify new predictive
/// panel variants on macOS upgrades. Tap into this by setting the
/// flag below; output goes to stderr so it shows up under
/// `make deploy` console / Console.app.
@MainActor
private let reaperLogPath: String = {
    // Always-on diagnostic file at a known path so the user
    // doesn't need to mess with stderr redirection. Truncated on
    // app launch via O_TRUNC equivalent so the log reflects only
    // the current session.
    let path = NSHomeDirectory() + "/.recruit/reaper.log"
    try? "".write(toFile: path, atomically: true, encoding: .utf8)
    return path
}()

@MainActor
private func reapLog(_ s: String) {
    let line = s + "\n"
    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: reaperLogPath)) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
    } else {
        // First call: file may have been deleted; recreate.
        try? line.write(toFile: reaperLogPath, atomically: true, encoding: .utf8)
    }
}

@MainActor
func reapPredictivePanels() {
    for window in NSApp.windows where window.isVisible {
        let name = NSStringFromClass(type(of: window))
        if predictivePanelFragments.contains(where: { name.contains($0) }) {
            // Log on actual kills only — keeps reaper.log small
            // but still useful as a regression canary. If a future
            // macOS spawns a new variant, the log here is where
            // we'd see it; if a new variant slips through the
            // fragment list entirely, you'll see the popup
            // visually and can flip on a debug verbose mode.
            reapLog("[reaper] KILLED \(name) frame=\(window.frame)")
            window.orderOut(nil)
        }
    }
}

/// Install (or replace) the interceptor on a window. Idempotent —
/// safe to call repeatedly when SwiftUI re-assigns the delegate.
@MainActor
func installFieldEditorInterceptor(on window: NSWindow) {
    let key = ObjectIdentifier(window)
    let currentDelegate = window.delegate as? NSObject
    // If we've already wrapped this window's current delegate, leave it
    // alone. Detect by checking whether the current delegate IS our
    // interceptor for this window.
    if let existing = installedInterceptors[key],
       window.delegate === existing {
        return
    }
    let interceptor = FieldEditorInterceptor(wrapping: currentDelegate)
    installedInterceptors[key] = interceptor
    window.delegate = interceptor
}

/// AppDelegate that installs the field-editor interceptor on every
/// NSWindow the app creates — the SwiftUI-spawned main window and any
/// subsequent windows (settings, sheets that promote to windows, etc).
/// Optional belt-and-suspenders AppDelegate that suppresses macOS
/// autofill / predictive / Writing-Tools popups across every window.
/// Not wired up by default — jrnlbar's main editor uses NSTextView
/// directly (no SwiftUI TextField) and the FilterField in Preferences
/// installs the interceptor on its own window via viewDidMoveToWindow.
/// If a phantom popup is ever reported, set
/// `NSApplication.shared.delegate = JrnlBarAppDelegate()` in
/// JrnlBarApp.main() before `app.run()`.
final class JrnlBarAppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    /// Closure wired by RecruitMacApp at construction time so the
    /// AppDelegate can hand off incoming URLs (e.g. from the
    /// Chrome extension's `recruit://import?...`) to the
    /// RecruitStore. We don't keep a direct reference to the
    /// store here because the delegate is instantiated before
    /// the store (via @NSApplicationDelegateAdaptor); the App
    /// struct injects this closure once both exist.
    @MainActor var urlHandler: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        // AppDelegate path is the reliable one on macOS — SwiftUI's
        // `.onOpenURL` on a Scene doesn't always fire when an
        // NSApplicationDelegateAdaptor is present. We use BOTH:
        // this method handles URLs delivered while the app is
        // already running (most common path for the Chrome
        // extension), and .onOpenURL covers any cases this
        // method might miss.
        for url in urls {
            urlHandler?(url)
        }
    }

    override init() {
        // Layer 0 — fires the instant
        // `@NSApplicationDelegateAdaptor(RecruitAppDelegate.self)`
        // instantiates this delegate, which SwiftUI does very early
        // in the App lifecycle — before applicationWillFinishLaunching,
        // before any window has been laid out.
        //
        // Force-set the prediction-subsystem defaults in our app's
        // persistent domain. Earlier attempts at register() (only
        // fills gaps) and setVolatileDomain on NSArgumentDomain
        // (didn't actually take — AppKit ignored those values when
        // reading the predictive panel config) both let the empty
        // ghost popup back through on launches when the user has
        // system-wide predictive text enabled. set() writes to our
        // app's persistent domain which AppKit reads with higher
        // priority than NSGlobalDomain, so our values win. Trade-
        // off: persists to ~/Library/Preferences/<bundle>.plist,
        // but they're all "false" booleans for features we never
        // want — harmless on disk.
        let prefs = UserDefaults.standard
        for key in [
            "NSAutomaticTextCompletionEnabled",
            "NSAutomaticInlinePredictionEnabled",
            "WebAutomaticTextReplacementEnabled",
            "NSAllowsCharacterPickerTouchBarItem",
            "NSAutomaticSpellingCorrectionEnabled",
            "NSAutomaticTextReplacementEnabled",
            "NSAutomaticQuoteSubstitutionEnabled",
            "NSAutomaticDashSubstitutionEnabled",
            "NSAutomaticDataDetectionEnabled",
            "NSAutomaticLinkDetectionEnabled",
        ] {
            prefs.set(false, forKey: key)
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Earliest reliable hook — NSApp exists and any windows
        // SwiftUI has prepared are visible in NSApp.windows, but the
        // app hasn't entered its run loop yet, so the user can't have
        // focused a field. Sweep here AND register the willBecomeKey
        // observer so the very first focus on the main window goes
        // through our interceptor (otherwise AppKit hands out a
        // default pool field editor without our autofill suppression
        // flags, and that editor sticks until something forces a
        // detach — typically opening another window).
        for window in NSApp.windows {
            installFieldEditorInterceptor(on: window)
        }

        // didBecomeKey covers any future window that comes up. The
        // pre-launch sweep above plus the re-sweep in
        // applicationDidFinishLaunching covers the cold-launch race
        // where the user could focus the search field before this
        // delegate's launch hooks finish wiring up.
        let didToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                installFieldEditorInterceptor(on: window)
            }
        }
        observers.append(didToken)

        // Any window that's added later (sheets, popovers that get
        // promoted) gets wrapped at order-in time. NSWindow doesn't
        // post a "willBecomeKey" notification, but didUpdate fires
        // on every window after its layout/appearance changes —
        // cheap enough that we use it as a catch-all.
        let updateToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                installFieldEditorInterceptor(on: window)
            }
        }
        observers.append(updateToken)

        // Belt-and-suspenders: before any user interaction reaches a
        // text field, re-sweep every window. SwiftUI sometimes creates
        // panels (sheets, popovers, QLPreviewPanel) whose lifecycle
        // notifications don't reliably fire didBecomeKey / didUpdate
        // before the field-editor warm-up that raises the phantom
        // popup. Sweeping on .leftMouseDown and .keyDown is cheap
        // (idempotent installs) and guarantees coverage on macOS 26
        // where the earlier hooks lose the race against SwiftUI's own
        // focus-on-attach.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { event in
            MainActor.assumeIsolated {
                for window in NSApp.windows {
                    installFieldEditorInterceptor(on: window)
                }
                // Layer 6 piggyback — reap any predictive panel
                // immediately after this event. The popup is often
                // scheduled mid-relayout (e.g. when the user clicks
                // the collapsed-console bar, SwiftUI re-renders,
                // and AppKit decides somewhere in that render pass
                // to show a predictive overlay). Fan out reaper
                // sweeps at multiple deferred ticks so we catch the
                // popup whether it appears in the same runloop turn
                // or a few hops later, without polling forever.
                reapPredictivePanels()
                for delay in [0.05, 0.15, 0.35, 0.7] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        reapPredictivePanels()
                    }
                }
            }
            return event
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-sweep in case any windows came up between
        // applicationWillFinishLaunching and now.
        for window in NSApp.windows {
            installFieldEditorInterceptor(on: window)
        }
        // Touch the QLPreviewPanel singleton early so its one-time
        // creation happens during launch — when our interceptors are
        // fully wired — rather than the first time the user hits
        // spacebar. Mirrors stash-mac's canonical setup.
        if let panel = QLPreviewPanel.shared() {
            installFieldEditorInterceptor(on: panel)
        }
        // Cold-launch flash fix. The reaper otherwise only triggers
        // off events / occlusion changes / key changes — at cold
        // launch none of those fire reliably BEFORE the popup paints
        // its first frame. Result: user sees a "phantom box flash"
        // on app open that the reactive sweeps then kill a beat
        // later. Fan a series of timer-based reaper sweeps across
        // the first few seconds of life so any predictive panel
        // spawned during initial layout gets ordered-out within one
        // runloop turn of instantiation — usually before it draws.
        reapPredictivePanels()
        for delay in [0.05, 0.15, 0.3, 0.6, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                reapPredictivePanels()
            }
        }
        // Layer 6 — predictive-panel reaper. Even with the layer 0-5
        // stack in place, AppKit on macOS 26 sometimes instantiates a
        // predictive-text / Writing-Tools panel during window
        // relayout (e.g. when the console expands and the search
        // field gets re-laid-out, the popup appears anchored under
        // the field). Hooking the moment any window changes
        // occlusion state and sweeping NSApp.windows for known
        // predictive panel class names lets us order them out
        // immediately. Class-name match is heuristic — Apple doesn't
        // publish these classes — but catches the documented forms
        // (NSPredictionPanel, _NSInlinePredictionPanel, Writing-
        // Tools surfaces).
        let occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                reapPredictivePanels()
            }
        }
        observers.append(occlusionToken)
        // Also reap whenever any window becomes key (focus shifts).
        // Same closure, different trigger.
        let keyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                reapPredictivePanels()
            }
        }
        observers.append(keyToken)
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
