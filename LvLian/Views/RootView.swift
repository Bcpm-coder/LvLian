import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ReminderService.self) private var reminders
    @Environment(TrainingLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var recoveryError: String?

    var body: some View {
        TabView {
            TodayView().tabItem { Label("今天", systemImage: "sun.max") }
            CourseView().tabItem { Label("课程", systemImage: "square.stack.3d.up") }
            HistoryView().tabItem { Label("记录", systemImage: "calendar") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .foregroundStyle(Theme.ink)
        .disabled(!library.ready)
        .fullScreenCover(isPresented: Binding(
            get: { !settings.onboardingComplete },
            set: { _ in }
        )) { OnboardingView() }
        .task {
            WatchBridge.shared.configure()
            WatchBridge.shared.setStandaloneHandler { result in
                var snapshot = SquatSnapshot(
                    plan: SquatPlan(target: result.target, down: result.down, up: result.up, rest: result.rest),
                    now: result.startedAt
                )
                snapshot.id = result.id
                snapshot.endedAt = result.endedAt
                snapshot.confirmedSets = result.confirmedSets
                snapshot.guidedRepetitions = result.guidedRepetitions
                snapshot.activeDuration = result.activeDuration
                snapshot.status = result.status
                snapshot.revision = result.revision
                do { try await library.save(snapshot); return true }
                catch { return false }
            }
            WatchBridge.shared.setPelvicHandler { result in
                var snapshot = PelvicSnapshot(course: .personal, now: result.startedAt)
                snapshot.id = result.id
                snapshot.endedAt = result.endedAt
                snapshot.completedRepetitions = result.completedRepetitions
                snapshot.activeDuration = result.activeDuration
                snapshot.status = result.status
                snapshot.revision = result.revision
                do { try await library.save(snapshot); return true }
                catch { return false }
            }
            await recoverInterruptedRecords()
            await reminders.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.refresh() } }
        }
        .alert("记录恢复失败", isPresented: Binding(get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } })) {
            Button("重试") { Task { await recoverInterruptedRecords() } }
        } message: { Text(recoveryError ?? "") }
    }

    private func recoverInterruptedRecords() async {
        guard !library.ready else { return }
        do { try await library.load() }
        catch { recoveryError = error.localizedDescription }
    }

}

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 48)).foregroundStyle(Theme.teal).padding(.top, 35)
                VStack(alignment: .leading, spacing: 10) {
                    Text("律练").font(.largeTitle.bold())
                    Text("感受节奏，也学会放松。")
                        .font(.title2).foregroundStyle(Theme.teal)
                    Text("男性盆底肌训练辅助工具").foregroundStyle(.secondary)
                }
                Card {
                    tip("1", "找到肌肉", "想象轻轻忍住排气，感受盆底向内提起。不要收紧腹部、大腿或臀部。")
                    tip("2", "轻柔收缩，充分放松", "舒适地坐下或躺下，自然呼吸，不憋气。放松阶段让肌肉完全松开，不要向下用力。")
                    tip("3", "以舒适为准", "不要在排尿时反复练习。出现疼痛或不适就停止；已有盆底疼痛、术后恢复或不确定是否适合时，先咨询专业人员。")
                }
                Text("课程是通用练习示例，不是个体化治疗处方，也不保证改善勃起硬度。手机震动只提示节奏，不用于刺激肌肉。")
                    .font(.footnote).foregroundStyle(.secondary)
                SourceLink()
                Button("了解，开始使用") { settings.onboardingComplete = true }
                    .buttonStyle(PrimaryButtonStyle())
                Text("无需账号 · 记录保存在设备上")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24)
        }
        .background(Theme.background)
        .interactiveDismissDisabled()
    }

    private func tip(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).foregroundStyle(Theme.teal)
                .frame(width: 30, height: 30).background(Theme.mint, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
