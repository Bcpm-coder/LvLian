import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ReminderService.self) private var reminders
    @Environment(TrainingLibrary.self) private var library
    @State private var previewHaptics = HapticService()
    @State private var clearing = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @State private var showGuide = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("盆底肌震动", isOn: $settings.hapticsEnabled)
                Toggle("增强手机震动", isOn: $settings.strongHaptics)
                Button("试一下收缩震动") { previewHaptics.play(relaxing: false, strong: settings.strongHaptics) }
                Button("试一下放松震动") { previewHaptics.play(relaxing: true, strong: settings.strongHaptics) }
            } header: { Text("节奏引导") } footer: {
                Text("收缩开始：一次震动。放松开始：两次震动。不支持震动的设备仍可使用屏幕引导。")
            }
            Section {
                Text(WatchBridge.shared.status).font(.subheadline)
                Text("可直接从手表开始盆底肌或深蹲；也可接收手机训练提示。手表独立训练结束后会自动同步记录。触感强度由 watchOS 控制，可在手表“声音与触感”中开启明显触感。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("深蹲会在手表启动功能性力量训练，实时显示并回传心率，同时保存到健康 App。盆底肌训练不读取心率。首次使用需在手表授权。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("手表引导") }
            Section("深蹲带练") {
                Toggle("中文语音", isOn: $settings.squatVoiceEnabled)
                Toggle("深蹲震动", isOn: $settings.squatHapticsEnabled)
                Text("每日 50 个，分组确认实际次数。节奏和休息可在开始深蹲前调整。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("每日提醒", isOn: Binding(
                    get: { reminders.enabled },
                    set: { enabled in Task { await reminders.update(enabled: enabled) } }
                ))
                DatePicker("提醒时间", selection: Binding(
                    get: { reminders.date },
                    set: { date in Task { await reminders.update(enabled: reminders.enabled, date: date) } }
                ), displayedComponents: .hourAndMinute)
                if reminders.busy { ProgressView("正在更新提醒…") }
                if reminders.denied {
                    Text("通知权限未开启，请到系统设置中允许通知，然后回来开启每日提醒。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if let error = reminders.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: { Text("每日提醒") } footer: {
                Text("通知显示“该进行今天的练习了”，不会透露训练内容。实际送达及声音、震动受系统通知和专注模式设置影响。")
            }
            .disabled(reminders.busy)
            Section("关于练习") {
                Button("重新查看训练说明") { showGuide = true }
                SourceLink()
                Text("通用练习示例，非个体化治疗处方。不采集或推断硬度评分。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("清空训练数据", role: .destructive) { confirmClear = true }.disabled(clearing)
                if clearing { ProgressView("正在清空…") }
            } header: { Text("数据与隐私") } footer: {
                Text("无需账号，无广告或分析 SDK。记录保存在本机，可能随系统设备备份保存。清空两种训练记录后回到盆底肌第一阶段，提醒及深蹲偏好保持不变。")
            }
            Section {
                HStack { Text("律练"); Spacer(); Text("1.10").foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("设置")
        .onDisappear { previewHaptics.stop() }
        .confirmationDialog("清空全部训练记录？此操作无法撤销。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空训练数据", role: .destructive) {
                clearing = true
                Task {
                    defer { clearing = false }
                    do { try await library.clear(); settings.currentStage = 0 }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .alert("清空失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好的", role: .cancel) { }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showGuide) {
            NavigationStack {
                GuideView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showGuide = false } } }
            }
        }
    }
}

private struct GuideView: View {
    var body: some View {
        List {
            Section("正确练习") {
                Text("想象轻轻忍住排气，盆底向内提起。腹部、大腿和臀部保持放松。")
                Text("自然呼吸，不憋气。放松时完全松开，不向下用力。不要在排尿时反复练习。")
                Text("手机只提供节奏提示，请正常握持或放在手边。")
            }
            Section("以舒适为准") {
                Text("出现疼痛或不适立即停止。已有盆底疼痛、术后恢复或不确定是否适合时，先咨询医生或盆底康复专业人员。")
                Text("课程为通用练习示例，不是治疗处方，不保证改善勃起硬度。")
                SourceLink()
            }
        }.navigationTitle("训练说明")
    }
}
