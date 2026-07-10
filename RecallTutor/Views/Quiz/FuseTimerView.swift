import SwiftUI

/// Depleting fuse bar — port of components/FuseTimer.tsx, driven by
/// TimelineView instead of requestAnimationFrame.
struct FuseTimerView: View {
    let duration: TimeInterval
    let isPaused: Bool
    let startedAt: Date
    let onExpire: () -> Void

    @State private var hasExpired = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isPaused)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = max(0, 1 - elapsed / duration)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.borderSoft)
                    Capsule()
                        .fill(progress > 0.3 ? Theme.accent : Theme.danger)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)
            .onChange(of: progress <= 0) { _, expired in
                if expired && !hasExpired && !isPaused {
                    hasExpired = true
                    onExpire()
                }
            }
        }
    }
}
