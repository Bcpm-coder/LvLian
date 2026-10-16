import SwiftUI

struct CountdownDial: View {
    let clock: CountdownState
    let seconds: Int
    let title: String
    var paused = false
    var tint = Theme.teal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Only this subtree draws at display cadence; it never writes observed state.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.running || reduceMotion)) { _ in
                let progress = reduceMotion
                    ? min(1, max(0, 1 - Double(seconds) / clock.duration))
                    : clock.progress(at: ProcessInfo.processInfo.systemUptime)
                ZStack {
                    Circle().stroke(Theme.mint, lineWidth: 13)
                    Circle().trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }.transaction { $0.animation = nil }
            }
            VStack(spacing: 8) {
                Text(title).font(.title2.weight(.semibold))
                Text(paused ? "—" : "\(seconds)")
                    .font(.system(size: 72, weight: .light, design: .rounded)).monospacedDigit()
                Text(paused ? "准备好再继续" : "秒").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 300).aspectRatio(1, contentMode: .fit).padding(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? "已暂停" : "\(title)，剩余 \(seconds) 秒")
    }
}
