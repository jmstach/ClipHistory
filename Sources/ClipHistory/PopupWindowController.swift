import AppKit
import SwiftUI
import CoreGraphics
import ApplicationServices

final class PopupWindowController {
    private var panel:      NSPanel?
    private let store:      ClipboardStore
    private let settings:   AppSettings
    private let popupState = PopupState()

    private var clickMonitor: Any?
    private var eventTap:     CFMachPort?
    private var tapSource:    CFRunLoopSource?

    /// Invoked when the user taps the in-popup settings gear. Set by AppDelegate.
    var openSettings: (() -> Void)?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store    = store
        self.settings = settings
    }

    // MARK: - Show / Hide

    func show(near mouse: NSPoint) {
        popupState.reset()

        if panel == nil { buildPanel() }
        guard let panel else { return }

        // Anchor to whichever screen the cursor is on, so multi-display users get
        // the popup where they're working regardless of placement mode.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let sf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Bottom tray spans the screen width (inset on both sides + bottom) and is
        // shorter; every other placement keeps the standard vertical popup size.
        let trayInset: CGFloat = 12
        let size: CGSize = settings.popupPlacement == .bottomTray
            ? CGSize(width: sf.width - trayInset * 2, height: 266)
            : CGSize(width: 520, height: 420)

        var origin: NSPoint
        switch settings.popupPlacement {
        case .bottomTray:
            origin = NSPoint(x: sf.minX + trayInset, y: sf.minY + trayInset)
        case .cursor:
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 14)
            origin.x = max(sf.minX + 8, min(origin.x, sf.maxX - size.width - 8))
            if origin.y + size.height > sf.maxY - 8 {
                origin.y = mouse.y - size.height - 14
            }
            origin.y = max(sf.minY + 8, origin.y)
        case .centre:
            origin = NSPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)
        case .topCentre:
            origin = NSPoint(x: sf.midX - size.width / 2, y: sf.maxY - size.height - 60)
        case .bottomCentre:
            origin = NSPoint(x: sf.midX - size.width / 2, y: sf.minY + 60)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        // makeKeyAndOrderFront so SwiftUI buttons inside the panel receive clicks.
        // .nonactivatingPanel guarantees our *app* is never activated, meaning
        // App A remains the active application.  Its text cursor / first-responder
        // state is preserved inside its own window and resumes the moment our
        // panel closes, which is exactly what we need before firing Cmd+V.
        panel.makeKeyAndOrderFront(nil)
        startEventTap()
        addClickMonitor()
    }

    func hide() {
        stopEventTap()
        removeClickMonitor()
        panel?.orderOut(nil)
        // No focus restoration needed — App A never lost focus.
    }

    // MARK: - Paste

    func pasteItem(_ item: ClipItem, plain: Bool = false) {
        // Suppress the monitor so our own clipboard write doesn't re-insert the item.
        store.suppressNextPoll = true

        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.content {
        case .text(let text):
            // Styled paste (↵): write the captured RTF plus a plain-text fallback
            // for apps that don't accept RTF. Plain paste (⇧↵), or items with no
            // captured RTF, write only the plain string.
            if !plain, let rtf = item.rtf {
                pb.setData(rtf, forType: .rtf)
            }
            pb.setString(text, forType: .string)
        case .image(let data):
            if let img = NSImage(data: data) { pb.writeObjects([img]) }
        case .files(let urls, _):
            // Write the file URLs back verbatim; Cmd+V then drops the real files.
            pb.writeObjects(urls as [NSURL])
        }

        // Bubble the just-pasted clip up to the top of the unpinned list.
        store.promoteToTop(id: item.id)

        hide()

        // Short delay so the panel finishes dismissing before Cmd+V fires.
        // App A's text field kept focus the whole time (nonactivatingPanel),
        // so no activate() call is needed — the Cmd+V lands directly into App A.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.simulateCmdV()
        }
    }

    // MARK: - Filtered items

    private var filteredItems: [ClipItem] {
        store.filtered(query: popupState.searchText,
                       showImages: !settings.hideImages)
    }

    private func selectCurrentItem(plain: Bool = false) {
        let items = filteredItems
        guard items.indices.contains(popupState.selectedIndex) else { return }
        pasteItem(items[popupState.selectedIndex], plain: plain)
    }

    /// Move selection towards newer items (top of the list / left of the tray).
    private func selectNewer() {
        popupState.selectedIndex = max(0, popupState.selectedIndex - 1)
    }

    /// Move selection towards older items (bottom of the list / right of the tray).
    private func selectOlder() {
        let count = filteredItems.count
        popupState.selectedIndex = min(max(count - 1, 0), popupState.selectedIndex + 1)
    }

    private func togglePinCurrent() {
        let items = filteredItems
        guard items.indices.contains(popupState.selectedIndex) else { return }
        let id = items[popupState.selectedIndex].id
        store.togglePin(id: id)
        // Pinning reorders the list — keep the selection on the same item.
        if let newIdx = filteredItems.firstIndex(where: { $0.id == id }) {
            popupState.selectedIndex = newIdx
        }
    }

    private func deleteCurrent() {
        let items = filteredItems
        guard items.indices.contains(popupState.selectedIndex) else { return }
        store.remove(id: items[popupState.selectedIndex].id)
        // Clamp selection to the shortened list.
        let count = filteredItems.count
        popupState.selectedIndex = min(popupState.selectedIndex, max(0, count - 1))
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: .zero,
            // .nonactivatingPanel: clicking / ordering-front does NOT activate our app,
            // so the previously-focused app (and its text cursor) remain active.
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level              = .popUpMenu
        p.isFloatingPanel    = true
        p.hidesOnDeactivate  = false
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = true   // System draws a shadow around the rounded glass content, outside the window frame

        p.contentView = NSHostingView(rootView: PopupView(
            store:     store,
            settings:  settings,
            state:     popupState,
            onSelect:  { [weak self] item in self?.pasteItem(item) },
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.openSettings?()
            }
        ))
        panel = p
    }

    // MARK: - CGEvent tap (keyboard interception while popup is visible)
    //
    // Because the panel is non-activating, App A retains keyboard focus and
    // SwiftUI's onKeyPress would never fire.  We install a session-level
    // intercepting event tap instead so ALL key-down events are routed here.

    private func startEventTap() {
        stopEventTap()   // clean up any stale tap

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask    = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .defaultTap,          // intercepting (events can be consumed)
            eventsOfInterest: mask,
            callback: { (_, type, cgEvent, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let ctrl = Unmanaged<PopupWindowController>
                    .fromOpaque(userInfo).takeUnretainedValue()
                // macOS silently disables taps that are slow to respond (e.g.
                // after sleep/wake or heavy load). Re-enable instead of letting
                // keyboard handling die for the rest of the session.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ctrl.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                return ctrl.handleKeyDown(event: cgEvent)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            // Accessibility not effective. The popup still opens via the Carbon
            // hotkey, but no keys reach it — surface that instead of degrading
            // silently (the view swaps the hints for an "enable access" banner).
            popupState.keyboardActive = false
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap  = tap
        tapSource = src
        popupState.keyboardActive = true
    }

    /// Re-prompt for Accessibility and open its System Settings pane. Currently
    /// unwired — kept ready for the upcoming Settings-window rebuild, where the
    /// Accessibility row's "grant access" button will call it. The red dot on the
    /// popup's gear is the interim signal that the grant is missing.
    func requestAccessibility() {
        hide()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap  = nil
        tapSource = nil
    }

    /// Called from the CGEvent tap callback (may be on any thread).
    /// Returns nil to consume the event; returns the event to pass it through.
    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags

        // ⌘-based actions on the selected item, intercepted before the Cmd
        // passthrough below so they don't leak to the app behind the popup.
        if flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            switch keyCode {
            case 35:                    // ⌘P → pin / unpin
                DispatchQueue.main.async { [weak self] in self?.togglePinCurrent() }
                return nil
            case 51:                    // ⌘⌫ → delete
                DispatchQueue.main.async { [weak self] in self?.deleteCurrent() }
                return nil
            default:
                break
            }
        }

        // Always pass other Cmd and Ctrl combos through so the OS / App A can
        // handle things like Cmd+Q, Cmd+Tab, Ctrl+C, etc.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return Unmanaged.passRetained(event)
        }

        switch keyCode {
        case 53:                        // Escape
            DispatchQueue.main.async { [weak self] in self?.hide() }
            return nil

        case 126:                       // ↑ Up arrow → newer
            DispatchQueue.main.async { [weak self] in self?.selectNewer() }
            return nil

        case 125:                       // ↓ Down arrow → older
            DispatchQueue.main.async { [weak self] in self?.selectOlder() }
            return nil

        case 36, 76:                    // Return / numpad Enter
            // ⇧↵ pastes as plain text; ↵ keeps the original formatting.
            let plain = flags.contains(.maskShift)
            DispatchQueue.main.async { [weak self] in self?.selectCurrentItem(plain: plain) }
            return nil

        case 51:                        // Backspace / Delete
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.popupState.searchText.isEmpty {
                    self.popupState.searchText.removeLast()
                    self.popupState.selectedIndex = 0
                }
            }
            return nil

        case 123:                       // ← Left arrow → newer (tray only)
            if settings.popupPlacement == .bottomTray {
                DispatchQueue.main.async { [weak self] in self?.selectNewer() }
            }
            return nil                  // consumed in every mode

        case 124:                       // → Right arrow → older (tray only)
            if settings.popupPlacement == .bottomTray {
                DispatchQueue.main.async { [weak self] in self?.selectOlder() }
            }
            return nil

        default:
            // Decode the typed character (respects shift, option-accent, etc.)
            var unicodeChars = [UniChar](repeating: 0, count: 4)
            var length       = 0
            event.keyboardGetUnicodeString(maxStringLength: 4,
                                           actualStringLength: &length,
                                           unicodeString: &unicodeChars)
            guard length > 0 else { return Unmanaged.passRetained(event) }

            let typed = String(decoding: unicodeChars.prefix(length), as: Unicode.UTF16.self)

            // Drop control characters (value < 32) and DEL (127)
            let printable = typed.filter { ch in
                guard let v = ch.unicodeScalars.first?.value else { return false }
                return v >= 32 && v != 127
            }
            guard !printable.isEmpty else { return Unmanaged.passRetained(event) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.popupState.searchText += printable
                self.popupState.selectedIndex = 0
            }
            return nil
        }
    }

    // MARK: - Click monitor (dismiss when user clicks outside the popup)

    private func addClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    // MARK: - Paste simulation

    private static func simulateCmdV() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
