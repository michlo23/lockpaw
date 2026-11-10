import Foundation

/// What a ping means on the lock screen: the colour of its row's dot.
enum AgentPingStatus: CaseIterable, Equatable {
    case waiting
    case error
    case done
    /// A bare ping with no payload: something wants the user, nothing says what.
    case attention
    /// Mid-turn. A row with a neutral dot, never a glow.
    case working

    /// Blocked on the user, or stopped and needing a look. These outrank a finished turn
    /// for the glow: an amber "needs permission" must not be repainted teal because a
    /// different session finished afterwards.
    var isUrgent: Bool { self == .waiting || self == .error }

    /// The glow's colour. Errors glow amber, not red: red is for auth failure and danger,
    /// and a red full-screen bloom on a lock screen reads as an intrusion. The red marker
    /// on the row carries the difference.
    var glowTone: AgentGlowTone { isUrgent ? .amber : .teal }
}

/// The two colours the agent glow can take.
enum AgentGlowTone: Equatable {
    case teal
    case amber
}

extension AgentPing.Kind {
    var status: AgentPingStatus {
        switch self {
        case .finished: return .done
        case .permission, .needsInput: return .waiting
        case .rateLimited, .failed: return .error
        case .attention: return .attention
        case .working: return .working
        case .ended: return .done
        }
    }
}

/// The agents waiting on the user while the screen is locked, one entry per session, in
/// arrival order. Pure, so the precedence rules are unit-tested.
struct AgentPingQueue: Equatable {
    private(set) var pings: [AgentPing] = []

    var isEmpty: Bool { pings.isEmpty }
    var latest: AgentPing? { pings.last }

    /// A session's newest ping replaces its entry. A repeat in the same state keeps the
    /// original entry, so the wait time counts from when the agent started waiting —
    /// Claude's `idle_prompt` restates a `Stop` a minute later and must not reset it to "now".
    mutating func record(_ ping: AgentPing) {
        if ping.kind == .ended {
            pings.removeAll { $0.id == ping.id }
            return
        }
        if let index = pings.firstIndex(where: { $0.id == ping.id }) {
            if pings[index].kind == ping.kind { return }
            pings.remove(at: index)
        }
        pings.append(ping)
    }

    mutating func clear() {
        pings.removeAll()
    }

    /// Drops the working rows of sessions whose agent process is gone.
    mutating func removeWorking(ids: Set<String>) {
        pings.removeAll { $0.kind == .working && ids.contains($0.id) }
    }

    /// Something pinged that the glow speaks for — working rows alone don't count.
    var hasNews: Bool { pings.contains { $0.kind.isNews } }

    /// The ping the glow speaks for: the most urgent outstanding one, the latest breaking
    /// ties. Nil when nothing has pinged.
    var glowPing: AgentPing? {
        pings.last(where: { $0.kind.status.isUrgent }) ?? pings.last(where: { $0.kind.isNews })
    }

    /// Teal until something pings; then the colour of `glowPing`.
    var glowTone: AgentGlowTone { glowPing?.kind.status.glowTone ?? .teal }

    /// Rows for the lock screen: urgent first, newest first within each, so the row that
    /// explains an amber glow is never the one pushed into "and N more".
    func rows(includingWorking: Bool = true) -> [AgentPing] {
        let newestFirst = pings.reversed()
        return newestFirst.filter { $0.kind.status.isUrgent }
            + newestFirst.filter { !$0.kind.status.isUrgent && $0.kind != .working }
            + (includingWorking ? newestFirst.filter { $0.kind == .working } : [])
    }
}

/// Sessions mid-turn, tracked whether or not the screen is locked — an agent usually
/// starts before the lock — and seeded into the lock screen's rows when it locks.
struct WorkingSessions: Equatable {
    /// Without a process to watch, a session that never reports its end drops out after this.
    static let maxAgeWithoutPID: TimeInterval = 2 * 60 * 60

    private(set) var byID: [String: AgentPing] = [:]

    var all: [AgentPing] { byID.values.sorted { $0.receivedAt < $1.receivedAt } }

    /// A new turn starts tracking (a repeat keeps the turn's start time); a finished,
    /// failed or closed session stops. Waiting keeps it: once answered, the turn goes on.
    mutating func note(_ ping: AgentPing) {
        switch ping.kind {
        case .working: if byID[ping.id] == nil { byID[ping.id] = ping }
        case .finished, .failed, .rateLimited, .ended: byID[ping.id] = nil
        case .permission, .needsInput, .attention: break
        }
    }

    /// Removes sessions whose agent process is gone, or that have no process to watch and
    /// are older than `maxAgeWithoutPID`. Returns the removed ids.
    mutating func prune(now: Date = Date(), isAlive: (Int32) -> Bool) -> Set<String> {
        let dead = byID.filter { _, ping in
            if let pid = ping.pid { return !isAlive(pid) }
            return now.timeIntervalSince(ping.receivedAt) > Self.maxAgeWithoutPID
        }.keys
        for id in dead { byID[id] = nil }
        return Set(dead)
    }
}
