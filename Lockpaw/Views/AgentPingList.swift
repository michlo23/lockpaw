import SwiftUI

/// The agents waiting on the user — the standing companion to the glow pulses, shown
/// until unlock. One quiet line per session: a dot whose colour is the state, who, and
/// how long ago. The glow already says how urgent; these only say who. Rows are urgent
/// first and capped so a busy afternoon cannot push the unlock prompt off a small screen.
///
/// No project names unless the user opts in (`Constants.lockScreenShowsProjectsKey`):
/// anyone walking past can read a lock screen. Notifications keep the project.
struct AgentPingList: View {
    let queue: AgentPingQueue
    let breathe: CGFloat

    @AppStorage(Constants.lockScreenShowsProjectsKey) private var showsProjects = false
    @AppStorage(Constants.showWorkingAgentsKey) private var showsWorking = true

    static let maxRows = 3

    var body: some View {
        VStack(spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(rows.prefix(Self.maxRows)) { ping in
                    row(ping)
                }
            }
            if rows.count > Self.maxRows {
                Text("and \(rows.count - Self.maxRows) more")
                    .font(.lockCaption)
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private var rows: [AgentPing] { queue.rows(includingWorking: showsWorking) }

    /// The state lives in the dot, so VoiceOver gets the words the row leaves out.
    private func row(_ ping: AgentPing) -> some View {
        GridRow {
            marker(ping.kind.status)
            Text(ping.name(includingProject: showsProjects))
                .font(.lockCaption)
                .foregroundStyle(.white.opacity(0.4))
            TimelineView(WaitTimeSchedule(start: ping.receivedAt)) { context in
                Text(Constants.formatWaitTime(context.date.timeIntervalSince(ping.receivedAt)))
                    .font(.lockMono)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .gridColumnAlignment(.trailing)
        }
        .tracking(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ping.summary(includingProject: showsProjects))
    }

    private func marker(_ status: AgentPingStatus) -> some View {
        Circle()
            .fill(status.dotColor)
            .frame(width: 5, height: 5)
            .opacity(0.55 + breathe * 0.3)
    }
}

/// Redraws a row's wait time only when its text changes (`Constants.nextWaitTimeChange`).
private struct WaitTimeSchedule: TimelineSchedule {
    let start: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date?
        return AnyIterator {
            let date = next.map { Constants.nextWaitTimeChange(after: $0, since: start) } ?? startDate
            next = date
            return date
        }
    }
}

extension AgentPingStatus {
    /// The row's marker: teal done, amber waiting, red for an error — the one place red
    /// appears for an agent, since the glow itself stays amber.
    var dotColor: Color {
        switch self {
        case .done, .attention: return Color("LockpawTeal")
        case .waiting: return Color("LockpawAmber")
        case .error: return Color("LockpawError")
        case .working: return .white.opacity(0.5)
        }
    }
}
