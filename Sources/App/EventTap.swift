import AppKit
import CoreGraphics

// Global C-compatible callback — cannot be a method or capturing closure
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = refcon else { return Unmanaged.passUnretained(event) }
    let mgr = Unmanaged<EventTap>.fromOpaque(ptr).takeUnretainedValue()

    // macOS disables the tap automatically when the callback is too slow
    // (e.g. while AppleScript is executing). Re-enable it immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        mgr.reenable()
        return nil
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return mgr.handle(event) ? nil : Unmanaged.passUnretained(event)
}

// MARK: - Key codes (hardware-layout-independent virtual codes)
enum KCode {
    static let c: Int64 = 8
    static let v: Int64 = 9
    static let x: Int64 = 7
    static let z: Int64 = 6
    static let returnKey: Int64 = 36
    static let escape: Int64 = 53
}

// MARK: - EventTap

final class EventTap {
    static let shared = EventTap()

    private var tap: CFMachPort?
    private var src: CFRunLoopSource?

    private init() {}

    var isRunning: Bool { tap != nil }

    // MARK: Lifecycle

    func startIfPermitted() {
        guard AXIsProcessTrusted(), tap == nil else { return }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: selfPtr
        )
        guard let tap else { return }
        src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src { CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        self.tap = nil
        self.src  = nil
    }

    // MARK: Handler — returns true to consume (drop) the event

    func handle(_ event: CGEvent) -> Bool {
        let key   = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let cmd   = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand
        let bare  = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty

        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let inFinder = frontID == "com.apple.finder"

        // ── Finder keyboard features ──────────────────────────────────────────
        // While the user is renaming a file, Cmd+X/Cmd+V/Return must keep
        // their normal text-editing meaning — never intercept in rename mode.
        // (finderIsRenaming() is checked lazily, only when a combo matches,
        // to avoid an Accessibility round-trip on every keystroke.)
        if inFinder {
            // Cmd+X → cut selected files
            if cmd && key == KCode.x && pref("kb.cutPaste") && !finderIsRenaming() {
                FinderCutPaste.shared.cut()
                return true
            }

            // Cmd+V → paste (move) cut files if we have any pending
            if cmd && key == KCode.v && FinderCutPaste.shared.hasPending && !finderIsRenaming() {
                FinderCutPaste.shared.paste()
                return true
            }

            // Cmd+Z → undo the last Handy move. Single-shot: once consumed,
            // canUndo is false and Cmd+Z reaches Finder's own undo again.
            // (`cmd` requires Command alone, so Cmd+Shift+Z redo passes through.)
            if cmd && key == KCode.z && FinderCutPaste.shared.canUndo && !finderIsRenaming() {
                FinderCutPaste.shared.undo()
                return true
            }

            // Return → open file
            if bare && key == KCode.returnKey && pref("kb.returnToOpen") && !finderIsRenaming() {
                DispatchQueue.global(qos: .userInteractive).async {
                    AppleScriptRunner.shared.run("tell application \"Finder\" to open selection")
                }
                return true
            }

            // Cmd+C or Escape in Finder cancels a pending cut (event passes
            // through). Scoped to Finder so e.g. Escape in another app's
            // dialog doesn't silently discard the cut.
            if (cmd && key == KCode.c) || (bare && key == KCode.escape) {
                FinderCutPaste.shared.cancel()
            }
        }

        return false
    }

    // MARK: Helpers

    private func pref(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    // Detects whether Finder has an inline text field focused (rename mode)
    private func finderIsRenaming() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid_t(pid))
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let elem = raw else { return false }
        var roleRaw: CFTypeRef?
        AXUIElementCopyAttributeValue(elem as! AXUIElement, kAXRoleAttribute as CFString, &roleRaw)
        let role = roleRaw as? String ?? ""
        return role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox"
    }
}
