import XCTest
@testable import Lockpaw

/// Working rows: a turn starting (UserPromptSubmit) and a session closing (SessionEnd),
/// tracked but never announced, and dropped when the agent process is gone.
final class WorkingSessionsTests: XCTestCase {

    private func ping(_ event: String, session: String, pid: String? = nil, at seconds: TimeInterval = 0) -> AgentPing {
        var info: [String: String] = ["agent": "claude", "session_id": session, "hook_event_name": event]
        info["pid"] = pid
        return AgentPing.from(userInfo: info, now: Date(timeIntervalSince1970: seconds))
    }

    func testHookEventsDecodeAsBookkeeping() {
        XCTAssertEqual(ping("UserPromptSubmit", session: "a").kind, .working)
        XCTAssertEqual(ping("SessionEnd", session: "a").kind, .ended)
        XCTAssertFalse(AgentPing.Kind.working.isNews)
        XCTAssertFalse(AgentPing.Kind.ended.isNews)
        XCTAssertTrue(AgentPing.Kind.finished.isNews)
    }

    func testCLIForwardsTheAgentPIDAndTheAppReadsIt() {
        let info = AgentPing.userInfo(arguments: ["--agent", "claude"], stdinPayload: ["hook_event_name": "UserPromptSubmit"], agentPID: 4242)
        XCTAssertEqual(info["pid"], "4242")
        XCTAssertEqual(AgentPing.from(userInfo: info).pid, 4242)
        XCTAssertNil(ping("Stop", session: "a", pid: "1").pid, "launchd is never an agent")
        XCTAssertNil(ping("Stop", session: "a", pid: "x").pid)
    }

    func testTrackingFollowsTheTurn() {
        var sessions = WorkingSessions()
        sessions.note(ping("UserPromptSubmit", session: "a", at: 10))
        sessions.note(ping("UserPromptSubmit", session: "a", at: 50))
        XCTAssertEqual(sessions.all.map(\.receivedAt.timeIntervalSince1970), [10], "a repeat keeps the turn's start")
        sessions.note(ping("Notification", session: "a"))
        XCTAssertEqual(sessions.all.count, 1, "waiting keeps the turn going")
        sessions.note(ping("Stop", session: "a"))
        XCTAssertTrue(sessions.all.isEmpty)
        sessions.note(ping("UserPromptSubmit", session: "b"))
        sessions.note(ping("SessionEnd", session: "b"))
        XCTAssertTrue(sessions.all.isEmpty)
    }

    func testPruneDropsDeadProcessesAndOldSessionsWithoutOne() {
        var sessions = WorkingSessions()
        sessions.note(ping("UserPromptSubmit", session: "alive", pid: "100"))
        sessions.note(ping("UserPromptSubmit", session: "killed", pid: "200"))
        sessions.note(ping("UserPromptSubmit", session: "nopid", at: 0))
        let removed = sessions.prune(now: Date(timeIntervalSince1970: 60)) { $0 == 100 }
        XCTAssertEqual(removed, ["Claude Code/killed"])
        XCTAssertEqual(Set(sessions.all.compactMap(\.sessionID)), ["alive", "nopid"])
        let late = sessions.prune(now: Date(timeIntervalSince1970: WorkingSessions.maxAgeWithoutPID + 1)) { _ in true }
        XCTAssertEqual(late.count, 1)
        XCTAssertEqual(sessions.all.compactMap(\.sessionID), ["alive"])
    }

    func testWorkingRowsNeverDriveTheGlowAndSortLast() {
        var queue = AgentPingQueue()
        queue.record(ping("UserPromptSubmit", session: "w", at: 1))
        XCTAssertFalse(queue.hasNews)
        XCTAssertNil(queue.glowPing)
        queue.record(ping("Stop", session: "d", at: 2))
        queue.record(ping("UserPromptSubmit", session: "w2", at: 3))
        XCTAssertTrue(queue.hasNews)
        XCTAssertEqual(queue.glowPing?.sessionID, "d")
        XCTAssertEqual(queue.rows().map(\.sessionID), ["d", "w2", "w"])
        XCTAssertEqual(queue.rows(includingWorking: false).map(\.sessionID), ["d"])
    }

    func testFinishReplacesTheWorkingRowAndEndRemovesIt() {
        var queue = AgentPingQueue()
        queue.record(ping("UserPromptSubmit", session: "a"))
        queue.record(ping("Stop", session: "a"))
        XCTAssertEqual(queue.pings.map(\.kind), [.finished])
        queue.removeWorking(ids: ["Claude Code/a"])
        XCTAssertEqual(queue.pings.count, 1, "only working rows are pruned")
        queue.record(ping("SessionEnd", session: "a"))
        XCTAssertTrue(queue.isEmpty)
    }
}
