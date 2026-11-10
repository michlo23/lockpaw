import Cocoa
import Carbon
import os.log

private let logger = Logger(subsystem: "com.eriknielsen.lockpaw", category: "HotkeyManager")

/// Manages global hotkey detection using a CGEventTap on a dedicated background thread.
/// Running on its own thread with its own run loop bypasses the LSUIElement activation
/// issue where the main run loop doesn't process events until user interaction.
/// The tap is a `.defaultTap` so the hotkey can be consumed rather than delivered to
/// whatever is frontmost as well. Requires Accessibility permission.
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var isRegistered = false
    private var carbonHotKey: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?

    /// The tap goes blind while any process holds Secure Input — and macOS's loginwindow
    /// can keep it on long after the lock screen or a password AutoFill closed, killing the
    /// hotkey until the next logout. A Carbon hotkey is delivered by the window server even
    /// then, so it is registered too. When both fire, LockController's
    /// `InputBlockPolicy.hotkeyPressToggles` collapses them into one toggle.
    private func registerCarbonHotkey() {
        guard carbonHotKey == nil else { return }
        if carbonHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .toggleLockpaw, object: nil)
                }
                return noErr
            }, 1, &spec, nil, &carbonHandler)
        }
        let id = EventHotKeyID(signature: OSType(0x4C4B_5057), id: 1) // "LKPW"
        let status = RegisterEventHotKey(
            UInt32(HotkeyConfig.keyCode), UInt32(HotkeyConfig.modifiers), id,
            GetApplicationEventTarget(), 0, &carbonHotKey
        )
        if status != noErr {
            carbonHotKey = nil
            logger.error("RegisterEventHotKey failed: \(status, privacy: .public)")
        }
    }

    private func unregisterCarbonHotkey() {
        if let ref = carbonHotKey { UnregisterEventHotKey(ref) }
        carbonHotKey = nil
    }

    func registerHotkey() {
        registerCarbonHotkey()
        if isRegistered {
            guard !AXIsProcessTrusted() else { return }
            // Accessibility was revoked (dead tap) — tear down and re-register
            logger.info("registerHotkey: tap registered but Accessibility revoked — re-registering")
            unregisterHotkey()
        }

        guard AXIsProcessTrusted() else {
            logger.warning("registerHotkey: skipped — Accessibility not granted")
            return
        }

        logger.info("registerHotkey: accessibility=\(AXIsProcessTrusted())")

        // Create the event tap on the calling thread first
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                // Re-enable if the tap gets disabled by the system
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = manager.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                let savedKeyCode = HotkeyConfig.keyCode
                let savedMods = HotkeyConfig.modifiers

                guard keyCode == savedKeyCode else { return Unmanaged.passUnretained(event) }

                var matches = true
                if savedMods & cmdKey != 0 { matches = matches && flags.contains(.maskCommand) }
                if savedMods & shiftKey != 0 { matches = matches && flags.contains(.maskShift) }
                if savedMods & optionKey != 0 { matches = matches && flags.contains(.maskAlternate) }
                if savedMods & controlKey != 0 { matches = matches && flags.contains(.maskControl) }

                if matches {
                    // A held key auto-repeats; only the first press toggles (InputBlockPolicy).
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    if InputBlockPolicy.hotkeyShouldToggle(isAutorepeat: isRepeat) {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .toggleLockpaw, object: nil)
                        }
                    }
                    // Swallow it. A .listenOnly tap cannot, so the hotkey's own key used to
                    // reach the frontmost app as well — locking from a terminal with
                    // Cmd+Shift+L typed an "L" at the prompt. Only the matched keyDown is
                    // consumed; every other key passes through untouched. The orphaned
                    // keyUp is harmless (nothing acts on a keyUp alone).
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            logger.error("Failed to create event tap for hotkey")
            return
        }

        // Run the event tap on a dedicated background thread with its own run loop.
        // This avoids the LSUIElement main run loop activation issue entirely.
        // The thread takes its own tap rather than reading `self.eventTap` once it starts:
        // a rebuild that lands before it runs must not hand it the replacement's tap.
        let thread = Thread { [weak self, tap = eventTap] in
            guard let self, CFMachPortIsValid(tap) else { return }

            self.tapRunLoop = CFRunLoopGetCurrent()

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            logger.info("registerHotkey: event tap running on background thread")

            CFRunLoopRun()

            logger.info("registerHotkey: background run loop exited")
        }
        thread.name = "com.eriknielsen.lockpaw.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread

        isRegistered = true
        logger.info("registerHotkey: complete")
    }

    func unregisterHotkey() {
        unregisterCarbonHotkey()
        guard isRegistered else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Invalidating removes the port's run loop source, so the tap thread's run loop
            // exits even when `tapRunLoop` isn't set yet (a rebuild racing the thread's start).
            CFMachPortInvalidate(tap)
        }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tapRunLoop = nil
        tapThread = nil
        eventTap = nil
        isRegistered = false
        logger.info("unregisterHotkey: complete")
    }

    func reregister() {
        logger.info("reregister called")
        unregisterHotkey()
        registerHotkey()
    }

    /// Rebuild a registered tap after the system slept, the macOS session was locked, or
    /// the user switched away and back. Like InputBlocker's tap, the old one may be dead
    /// even though it still exists and reads as enabled, and nothing else would ever notice:
    /// the hotkey just stops working until relaunch (#29). Unregistered stays unregistered.
    func refreshAfterSessionChange() {
        guard isRegistered else { return }
        logger.info("refreshAfterSessionChange: rebuilding the hotkey tap")
        reregister()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { registerHotkey() } else { unregisterHotkey() }
    }

    deinit { unregisterHotkey() }
}
