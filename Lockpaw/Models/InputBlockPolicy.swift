import Foundation

/// Pure rules that keep the lock hotkey from stranding the keyboard, free of event taps and
/// timers so both can be unit-tested directly.
enum InputBlockPolicy {
    /// Holding the hotkey auto-repeats its keyDown. Each repeat used to toggle, so a held key
    /// flipped lock → unlock → lock, fast enough to land an unlock inside the window below.
    /// Only the first press toggles; repeats are swallowed.
    static func hotkeyShouldToggle(isAutorepeat: Bool) -> Bool {
        !isAutorepeat
    }

    /// `lock()` starts the keyboard blocker a beat after the overlay appears. If an unlock
    /// lands inside that beat, starting it anyway leaves the keyboard blocked with no cover
    /// up; the hotkey is then the only way out. So the deferred start only goes ahead while
    /// the screen is still locked.
    static func shouldStartDeferredBlocking(state: LockState) -> Bool {
        state == .locked
    }

    /// The hotkey can arrive twice for one press — the event tap and the Carbon hotkey
    /// (registered for when Secure Input blinds the tap) — and Carbon repeats while the key
    /// is held. A press only toggles if the previous one was more than `window` ago; every
    /// press, counted or not, restarts that window, so a held key toggles once.
    static let hotkeyPressWindow: TimeInterval = 0.5

    static func hotkeyPressToggles(now: Date, lastPress: Date?, window: TimeInterval = hotkeyPressWindow) -> Bool {
        guard let lastPress else { return true }
        return now.timeIntervalSince(lastPress) > window
    }

    /// Lock & sleep: while Lockpaw holds a lock started that way (`settingEnabled`),
    /// once an agent has finished and none is still working or waiting on the user.
    static func sleepsNow(state: LockState, settingEnabled: Bool, statuses: [AgentPingStatus]) -> Bool {
        settingEnabled && state == .locked && statuses.contains(.done)
            && !statuses.contains(.working) && !statuses.contains(.waiting)
    }
}
