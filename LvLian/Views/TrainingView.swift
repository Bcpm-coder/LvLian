import SwiftUI

struct TrainingView: View {
    @Bindable var session: TrainingSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmEnd = false

    private var title: String {
        switch session.phase {
        case .ready, .prepare: "准备开始"
        case .contract: "轻柔收缩"
        case .relax: "充分放松"
        case .paused: "已暂停"
        case .completed: "完成了，做得好"
        case .interrupted: "本次练习已结束"
        }
    }
    private var hint: String {
        switch session.phase {
        case .contract: "轻轻向内提起，不要憋气"
        case .relax: "完全松开，自然呼吸"
        case .paused: "继续时先完整放松，再进入收缩"
        default: "找到舒适姿势，让身体放松"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Text(session.course.isPersonal ? "自定节奏 · 每组 10 次" : "\(session.course.name) · 阶段 \(session.course.id + 1)")
                        .font(.headline)
                    Spacer()
                    if !session.isTerminal {
                        Button("结束") { session.pause(); confirmEnd = true }
                            .foregroundStyle(.secondary)
                    }
                }
                if session.isTerminal { summary } else { guidance }
                if let error = session.errorMessage {
                    Card {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("重试保存") {
                            Task {
                                if await session.persist(), session.phase == .ready { await session.start() }
                            }
                        }
                    }
                }
            }.padding(24)
        }
        .background(Theme.background)
        .interactiveDismissDisabled()
        .task {
            await session.start()
            if scenePhase != .active { session.pause() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.pause() }
        }
        .onDisappear { session.cleanup() }
        .confirmationDialog("提前结束这次练习？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束并保存记录") { session.end() }
            Button("返回暂停页面", role: .cancel) { }
        } message: { Text("已完成的次数和时长会保存，本次不计入达标天数。") }
    }

    private var guidance: some View {
        VStack(spacing: 26) {
            Text(hint).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 12)
            CountdownDial(clock: session.countdown, seconds: session.seconds, title: title, paused: session.phase == .paused)
            Text("已完成 \(session.completedRepetitions) / \(session.course.repetitions) 次")
                .font(.headline).monospacedDigit()
            Text(WatchBridge.shared.status).font(.caption).foregroundStyle(.secondary)
            Text("收缩和完整放松后，计为一次。")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                if session.phase == .paused { session.resume() } else { session.pause() }
            } label: {
                Label(session.phase == .paused ? "继续训练" : "暂停一下", systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(session.errorMessage != nil || session.phase == .ready)
            Button("感到不适，停止练习") { session.end(feedback: "不适") }
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(spacing: 24) {
            Image(systemName: session.record.isCompleted ? "checkmark.seal.fill" : "leaf.circle.fill")
                .font(.system(size: 72)).foregroundStyle(Theme.teal).padding(.top, 30)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(session.record.isCompleted ? (session.course.isPersonal ? "本组 10 次已完成。各组可分时进行，先充分休息。" : "今天又为自己留出了一点时间。") : "听从身体的感受，休息也很重要。")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Card {
                LabeledContent("有效训练", value: durationText(session.record.activeDuration))
                LabeledContent("完成次数", value: "\(session.record.completedRepetitions) / \(session.record.targetRepetitions)")
                LabeledContent("训练状态", value: session.record.statusTitle)
            }
            Card {
                Text("这次感觉如何？").font(.headline)
                Text("可选，仅用于自己的训练记录。")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(["轻松", "适中", "吃力", "不适"], id: \.self) { value in
                        Button { session.setFeedback(value) } label: {
                            Text(value).frame(maxWidth: .infinity).padding(14)
                                .foregroundStyle(session.record.feedback == value ? .white : Theme.teal)
                                .background(session.record.feedback == value ? Theme.teal : Theme.mint, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                if session.record.feedback == "不适" {
                    Text("请停止继续练习。若疼痛或不适持续，请咨询医生或盆底康复专业人员。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if session.saving { ProgressView("正在保存…") }
            Button("返回今天") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.errorMessage != nil || session.saving)
        }
    }
}
