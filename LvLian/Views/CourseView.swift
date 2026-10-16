import SwiftUI
import SwiftData

struct CourseView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TrainingLibrary.self) private var library
    private var records: [PelvicSnapshot] { library.records }
    @State private var showSquats = false
    @State private var confirmAdvance = false
    @State private var confirmRetreat = false
    @State private var stayed = false
    private var canAdvance: Bool { ProgressCalculator.canAdvance(records.map(\.trainingDay), stage: settings.currentStage) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Card {
                        Label("每日深蹲 · 50 个", systemImage: "figure.strengthtraining.functional").font(.headline)
                        Text("独立每日目标，默认 5 组 × 10 个，不影响盆底肌课程升级。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("查看深蹲计划") { showSquats = true }
                    }
                    PelvicPlanControls()
                    Text("盆底肌 · 循序渐进")
                        .font(.title2.bold())
                    Text("每阶段完成 7 个训练日后，可选择升级。漏练不跳级，也无需补练。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(Course.stages) { course in
                        let count = ProgressCalculator.completedDays(records.map(\.trainingDay), stage: course.id).count
                        Card {
                            HStack {
                                Text("0\(course.id + 1)").font(.title3.monospacedDigit()).foregroundStyle(Theme.teal)
                                Text(course.name).font(.title2.bold())
                                Spacer()
                                if !settings.personalRhythm && settings.currentStage == course.id {
                                    Text("当前").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Theme.mint, in: Capsule())
                                }
                            }
                            Text("收缩 \(Int(course.contraction)) 秒 / 放松 \(Int(course.relaxation)) 秒 × \(course.repetitions) 次")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(min(count, 7)), total: 7)
                            Text("已完成 \(count) 个训练日").font(.caption).foregroundStyle(.secondary)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(!settings.personalRhythm && settings.currentStage == course.id ? Theme.teal : .clear, lineWidth: 1.5))
                    }
                    if canAdvance && !settings.personalRhythm {
                        Button("进入下一阶段") { confirmAdvance = true }.buttonStyle(PrimaryButtonStyle())
                    }
                    Button(settings.personalRhythm ? "使用原来的四阶段课程" : "保持当前阶段") { settings.personalRhythm = false; stayed = true }
                        .frame(maxWidth: .infinity).padding(10)
                    if settings.currentStage > 0 {
                        Button("退回前一阶段") { confirmRetreat = true }
                            .frame(maxWidth: .infinity).padding(10)
                    }
                    Text("以上为通用练习示例，不是个体化治疗处方。不要为了进度勉强增加强度。")
                        .font(.footnote).foregroundStyle(.secondary)
                    SourceLink()
                }.padding(24)
            }
            .background(Theme.background)
            .navigationTitle("课程")
            .fullScreenCover(isPresented: $showSquats) { SquatSetupView() }
            .alert("准备好进入下一阶段了吗？", isPresented: $confirmAdvance) {
                Button("无不适且能充分放松") {
                    if canAdvance && !settings.personalRhythm { settings.currentStage += 1 }
                }
                Button("继续当前阶段", role: .cancel) { }
            } message: { Text("请以身体感受为准，升级不会自动发生。") }
            .confirmationDialog("退回较轻的前一阶段？", isPresented: $confirmRetreat, titleVisibility: .visible) {
                Button("退回前一阶段") { settings.currentStage = max(0, settings.currentStage - 1) }
            } message: { Text("之前的训练记录会保留。") }
            .alert("继续按自己的节奏", isPresented: $stayed) {
                Button("好的", role: .cancel) { }
            } message: { Text("当前阶段保持不变，你可以随时回来调整。") }
        }
    }
}

struct PelvicPlanControls: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        Card {
            Label("盆底肌 · 自定节奏", systemImage: "timer").font(.headline).foregroundStyle(Theme.teal)
            Toggle("使用 5 秒收缩／5 秒放松", isOn: $settings.personalRhythm)
            Text("每个收缩—完整放松循环计 1 次，每组 10 次，约 1 分 45 秒（含准备）。")
                .font(.subheadline).foregroundStyle(.secondary)
            if settings.personalRhythm {
                Stepper("每日目标 \(settings.pelvicDailySets) 组", value: $settings.pelvicDailySets, in: 1...8)
                Text("按你的计划默认 5 组，可选至 8 组，也可调低。分时进行，各组之间充分休息，不自动连练。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("这是个人目标，不是推荐最低训练量。请按自身情况或专业指导安排；无法充分放松或出现不适时停止。自定节奏不推进四阶段课程。")
                .font(.footnote).foregroundStyle(.secondary)
            SourceLink()
        }
    }
}
