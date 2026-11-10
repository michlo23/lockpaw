import XCTest
@testable import Lockpaw

final class InputBlockPolicyTests: XCTestCase {

    func testFirstPressTogglesButAutoRepeatDoesNot() {
        XCTAssertTrue(InputBlockPolicy.hotkeyShouldToggle(isAutorepeat: false))
        XCTAssertFalse(InputBlockPolicy.hotkeyShouldToggle(isAutorepeat: true))
    }

    func testDeferredBlockerStartsOnlyWhileLocked() {
        XCTAssertTrue(InputBlockPolicy.shouldStartDeferredBlocking(state: .locked))
        for state in [LockState.unlocked, .locking, .unlocking] {
            XCTAssertFalse(InputBlockPolicy.shouldStartDeferredBlocking(state: state), "\(state)")
        }
    }

    func testOnePressArrivingTwiceTogglesOnce() {
        let t = Date()
        XCTAssertTrue(InputBlockPolicy.hotkeyPressToggles(now: t, lastPress: nil))
        XCTAssertFalse(InputBlockPolicy.hotkeyPressToggles(now: t.addingTimeInterval(0.05), lastPress: t))
        XCTAssertTrue(InputBlockPolicy.hotkeyPressToggles(now: t.addingTimeInterval(0.8), lastPress: t))
    }

    func testSleepsOnlyWhenAFinishedAgentPingsALockedScreenWithTheSettingOn() {
        XCTAssertTrue(InputBlockPolicy.sleepsAfterPing(kind: .finished, state: .locked, settingEnabled: true))
        XCTAssertFalse(InputBlockPolicy.sleepsAfterPing(kind: .finished, state: .locked, settingEnabled: false))
        XCTAssertFalse(InputBlockPolicy.sleepsAfterPing(kind: .finished, state: .unlocked, settingEnabled: true))
        for kind in [AgentPing.Kind.permission, .needsInput, .failed, .rateLimited, .attention] {
            XCTAssertFalse(InputBlockPolicy.sleepsAfterPing(kind: kind, state: .locked, settingEnabled: true), "\(kind)")
        }
    }
}
