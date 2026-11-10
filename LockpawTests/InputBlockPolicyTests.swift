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

    func testSleepsOnlyOnceEveryAgentIsDoneOnALockedScreenWithTheSettingOn() {
        let sleeps = { (statuses: [AgentPingStatus], state: LockState, on: Bool) in
            InputBlockPolicy.sleepsNow(state: state, settingEnabled: on, statuses: statuses)
        }
        XCTAssertTrue(sleeps([.done], .locked, true))
        XCTAssertTrue(sleeps([.done, .error], .locked, true))
        XCTAssertFalse(sleeps([.done], .locked, false))
        XCTAssertFalse(sleeps([.done], .unlocked, true))
        XCTAssertFalse(sleeps([.done, .working], .locked, true), "another agent still working")
        XCTAssertFalse(sleeps([.done, .waiting], .locked, true), "another agent waiting on the user")
        XCTAssertFalse(sleeps([.working], .locked, true))
        XCTAssertFalse(sleeps([.error], .locked, true))
        XCTAssertFalse(sleeps([], .locked, true))
    }
}
