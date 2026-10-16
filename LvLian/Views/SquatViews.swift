import SwiftUI

struct SquatSetupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TrainingLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var session: SquatSession?
    @State private var diagnosticStarted = false
    private var remaining: Int { SquatProgress.remaining(library.squats.map(\.day), dayKey: ProgressCalculator.dayKey(for: .now)) }

    var body: some View {
        if let session { SquatTrainingView(session: session) }
        else {
            @Bindable var settings = settings
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Card {
                            Label("每日深蹲", systemImage: "figure.strengthtraining.functional")
                                .font(.headline).foregroundStyle(Theme.teal)
                            Text(remaining > 0 ? "还差 \(remaining) 个" : "今天的 50 个已完成")
                                .font(.largeTitle.bold())
                            if remaining > 0 {
                                let plan = SquatPlan(target: remaining)
                                Text("本次分组：" + plan.sets.map { "\($0)" }.joined(separator: " + "))
                                    .foregroundStyle(.secondary)
                            }
                            Text("跟随节奏练习，每组结束确认实际次数。手机不会自动识别你的动作。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Card {
                            Text("调整节奏").font(.headline)
                            Stepper("下蹲 \(Int(settings.squatDown)) 秒", value: $settings.squatDown, in: 1...5, step: 1)
                            Stepper("起身 \(Int(settings.squatUp)) 秒", value: $settings.squatUp, in: 1...5, step: 1)
                            Stepper("组间休息 \(Int(settings.squatRest)) 秒", value: $settings.squatRest, in: 15...120, step: 5)
                            Toggle("中文语音", isOn: $settings.squatVoiceEnabled)
                            Toggle("深蹲震动", isOn: $settings.squatHapticsEnabled)
                            Text("震动开启时，下蹲一次、起身两次。语音仅在前台带练时播放。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("手机放稳、留出活动空间，按舒适的幅度和节奏练习。感到不适就停止，不必勉强完成目标。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(remaining > 0 ? "开始深蹲" : "今日目标已达成") {
                            guard remaining > 0 else { return }
                            session = SquatSession(plan: SquatPlan(target: remaining, down: settings.squatDown, up: settings.squatUp, rest: settings.squatRest), library: library, settings: settings)
                        }.buttonStyle(PrimaryButtonStyle()).disabled(remaining == 0)
                    }.padding(24)
                }
                .background(Theme.background).navigationTitle("深蹲计划")
                .task {
                    guard TrainingDiagnostics.mode == "squat", !diagnosticStarted else { return }
                    diagnosticStarted = true
                    session = SquatSession(plan: SquatPlan(), library: library, settings: settings)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            }
        }
    }
}

struct SquatTrainingView: View {
    @Bindable var session: SquatSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var actual = 0

    private var title: String {
        switch session.phase {
        case .ready, .prepare: "准备开始"
        case .down: "下蹲"
        case .up: "起身"
        case .rest: "组间休息"
        case .resuming: "站稳准备"
        case .paused: "已暂停"
        case .confirm: "本组结束"
        case .completed: "带练完成"
        case .interrupted: "本次已结束"
        }
    }
    private var hint: String {
        switch session.phase {
        case .down: "按舒适的幅度下蹲"
        case .up: "平稳起身，不必抢节奏"
        case .rest: "放松一下，下一组不着急"
        case .paused: session.countdown.duration == session.plan.rest
            ? "继续时从剩余休息时间开始"
            : "继续时先站稳，再开始未完成的一次"
        case .resuming: "站稳，准备重新开始"
        default: "自然呼吸，以身体感受为准"
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("深蹲 · 第 \(session.setIndex + 1) / \(session.plan.sets.count) 组").font(.headline)
                    Spacer()
                    if !session.isTerminal {
                        Button("结束") { session.end() }
                            .disabled(session.phase == .ready)
                    }
                }
                if session.isTerminal { summary }
                else if session.phase == .confirm { confirmation }
                else {
                    Text(hint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    CountdownDial(clock: session.countdown, seconds: session.seconds, title: title, paused: session.phase == .paused)
                    Text("本组已带练 \(session.guidedInSet) / \(session.setTarget) 个").font(.headline).monospacedDigit()
                    Text("本次已确认 \(session.confirmed) 个").foregroundStyle(.secondary)
                    if let bpm = WatchBridge.shared.heartRate {
                        Label("心率 \(bpm) 次/分钟", systemImage: "heart.fill")
                            .font(.headline).foregroundStyle(.red).monospacedDigit()
                    } else {
                        Label("心率等待手表测量", systemImage: "heart")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button {
                        if session.phase == .paused { session.resume() } else { session.pause() }
                    } label: {
                        Label(session.phase == .paused ? "继续带练" : "暂停一下", systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
                    }.buttonStyle(PrimaryButtonStyle()).disabled(session.phase == .ready || session.errorMessage != nil)
                    Text("带练次数只是节奏参考，确认后才计入每日目标。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if let error = session.errorMessage {
                    Card {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("重试保存") {
                            Task { if await session.persist(), session.phase == .ready { await session.start() } }
                        }
                    }
                }
            }.padding(24)
        }
        .background(Theme.background).interactiveDismissDisabled()
        .task {
            await session.start()
            if scenePhase != .active { session.pause() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.pause() } }
        .onChange(of: session.phase) { _, phase in if phase == .confirm { actual = session.setTarget } }
        .onDisappear { session.cleanup() }
    }
    private var confirmation: some View {
        Card {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Theme.teal)
            Text("这一组实际做了几个？").font(.title2.bold())
            Text("按自己的实际完成情况确认，未完成的不用补记。")
                .font(.subheadline).foregroundStyle(.secondary)
            Stepper("\(actual) / \(session.setTarget) 个", value: $actual, in: 0...session.setTarget).font(.title3)
            Button(session.setIndex + 1 == session.plan.sets.count ? "确认并结束" : "确认，进入休息") {
                session.confirmSet(actual: actual)
            }.buttonStyle(PrimaryButtonStyle()).disabled(session.errorMessage != nil)
        }.padding(.top, 30)
    }
    private var summary: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.strengthtraining.functional").font(.system(size: 70)).foregroundStyle(Theme.teal).padding(.top, 30)
            Text(title).font(.largeTitle.bold())
            Card {
                LabeledContent("实际确认", value: "\(session.record.confirmed) 个")
                LabeledContent("节奏带练", value: "\(session.record.guidedRepetitions) 个")
                LabeledContent("有效训练", value: durationText(session.record.activeDuration))
                Text("实际确认次数已计入每日 50 个目标。未达到目标也可以稍后继续。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if session.saving { ProgressView("正在保存…") }
            Button("返回今天") { dismiss() }
                .buttonStyle(PrimaryButtonStyle()).disabled(session.saving || session.errorMessage != nil)
        }
    }
}
