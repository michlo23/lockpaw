import CoreGraphics
import Foundation

/// The real state of the macOS lock screen, read from the window server rather than taken
/// from the `com.apple.screenIsLocked` / `screenIsUnlocked` notifications, which any local
/// process can post. "Unlock with your Mac" must not be triggerable by a script.
enum SystemSession {
    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Locks the macOS session now, the way Ctrl+Cmd+Q does. Private login.framework call,
    /// looked up at runtime; false if it is missing. Callers confirm with `isScreenLocked`.
    @discardableResult
    static func lockScreen() -> Bool {
        typealias LockFn = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        _ = unsafeBitCast(sym, to: LockFn.self)()
        return true
    }

    /// Asks macOS to sleep now. Needs no privileges.
    static func sleepNow() {
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["sleepnow"]
        try? pmset.run()
    }
}
