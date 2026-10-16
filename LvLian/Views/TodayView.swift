import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TrainingLibrary.self) private var library
    private var records: [PelvicSnapshot] { library.records }
    @State private var showSquats = false
    @State private var diagnosticStarted = false
    @State private var session: TrainingSession?
    @State private var repeatConfirmation = false
    private var course: Course { settings.selectedCourse }
    private var days: Int { ProgressCalculator.completedDays(records.map(\.trainingDay), stage: course.id).count }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let key = ProgressCalculator.dayKey(for: timeline.date)
                let groups = ProgressCalculator.personalGroups(records.map(\.trainingDay), dayKey: key)
                let done = course.isPersonal ? groups >= settings.pelvicDailySets : ProgressCalculator.completedDays(records.map(\.trainingDay)).contains(key)
                let squatCount = SquatProgress.totals(library.squats.map(\.day))[ProgressCalculator.dayKey(for: timeline.date)] ?? 0
                let allDone = done && squatCount >= 50
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(timeline.date, format: .dateTime.month().day().weekday()).font(.subheadline).foregroundStyle(.secondary)
                                Text("给自己一刻专注").font(.title.bold())
                            }
                            Spacer()
                            Image(systemName: "leaf").font(.largeTitle).foregroundStyle(Theme.teal)
                        }
                        Card {
                            Label(allDone ? "今日计划已完成" : "今天的两个小目标", systemImage: allDone ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.headline).foregroundStyle(Theme.teal)
                            Text(allDone ? "两项都完成了，留些时间放松。" : "盆底肌 \(course.isPersonal ? "\(settings.pelvicDailySets) 组" : "1 节") · 深蹲 50 个，可分开完成。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Card {
                            Text(course.isPersonal ? "盆底肌 · 自定节奏" : "盆底肌 · 阶段 \(course.id + 1) / 4").font(.caption.weight(.semibold)).foregroundStyle(Theme.teal)
                            Text(course.name).font(.system(size: 38, weight: .semibold, design: .rounded))
                            Text("收缩 \(Int(course.contraction)) 秒 · 放松 \(Int(course.relaxation)) 秒 · \(course.repetitions) 次")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Label("约 \(durationText(course.duration + 5))", systemImage: "clock")
                            Divider()
                            if course.isPersonal {
                                HStack {
                                    Text("今日完成")
                                    Spacer()
                                    Text("\(groups) / \(settings.pelvicDailySets) 组").monospacedDigit()
                                }
                                ProgressView(value: Double(min(groups, settings.pelvicDailySets)), total: Double(settings.pelvicDailySets))
                                Text("收缩 5 秒＋放松 5 秒算一次，10 次为一组。分时练习，不必连续完成。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Text("本阶段训练日")
                                    Spacer()
                                    Text("\(min(days, 7)) / 7").monospacedDigit().foregroundStyle(Theme.teal)
                                }.font(.subheadline)
                                ProgressView(value: Double(min(days, 7)), total: 7)
                                Text(days >= 7 ? "已达阶段目标，可在课程页选择是否升级。" : "同一天练习多次，只计为一个训练日。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button { if done { repeatConfirmation = true } else { start() } } label: {
                                Label(course.isPersonal ? (done ? "额外练一组" : "开始第 \(groups + 1) 组") : (done ? "再练一节" : "开始训练"), systemImage: "play.fill")
                            }.buttonStyle(PrimaryButtonStyle())
                        }
                        Card {
                            Label("每日深蹲", systemImage: "figure.strengthtraining.functional")
                                .font(.headline).foregroundStyle(Theme.teal)
                            Text("\(squatCount) / 50 个").font(.largeTitle.bold()).monospacedDigit()
                            ProgressView(value: Double(min(50, squatCount)), total: 50)
                            Text("默认 5 组 × 10 个，语音跟练，每组确认实际次数。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button(squatCount >= 50 ? "今日深蹲已完成" : "开始深蹲") { showSquats = true }
                                .buttonStyle(PrimaryButtonStyle()).disabled(squatCount >= 50)
                        }
                        Label("保持自然呼吸，放松和收缩同样重要。", systemImage: "wind")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(24)
                }.background(Theme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: library.ready, initial: true) { _, ready in
                guard ready, !diagnosticStarted, let mode = TrainingDiagnostics.mode else { return }
                diagnosticStarted = true
                if mode == "pelvic" { start() } else { showSquats = true }
            }
            .fullScreenCover(isPresented: $showSquats) { SquatSetupView() }
            .fullScreenCover(item: $session) { TrainingView(session: $0) }
            .confirmationDialog("今天已完成目标，额外练习不会加快课程升级。", isPresented: $repeatConfirmation, titleVisibility: .visible) {
                Button("舒适，继续练习") { start() }
                Button("今天先休息", role: .cancel) { }
            }
        }
    }

    private func start() { session = TrainingSession(course: course, library: library, settings: settings) }
}
