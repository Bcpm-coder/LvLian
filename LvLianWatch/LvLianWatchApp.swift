import SwiftUI
import WatchKit
import WatchConnectivity
import Observation
import HealthKit

private struct WatchActiveBackup: Codable {
    enum Kind: String, Codable { case pelvic, squat }
    var kind: Kind
    var id: UUID
    var startedAt: Date
    var target = 50
    var down = 2.0
    var up = 2.0
    var rest = 30.0
    var confirmedSets: [Int] = []
    var guidedRepetitions = 0
    var completedRepetitions = 0
    var activeDuration = 0.0
}

@main
struct LvLianWatchApp: App {
    @State private var receiver = WatchReceiver()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 10) {
                    Text("律练").font(.headline).foregroundStyle(.mint)
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        let fresh = receiver.isFresh
                        Text(fresh ? receiver.title : "可独立训练").font(.title3.bold())
                        Text(fresh && (receiver.running || receiver.localPaused) ? "\(receiver.seconds)" : "—")
                            .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(fresh ? receiver.detail : receiver.homeNotice)
                            .font(.caption2).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                    }
                    if receiver.localNeedsConfirmation {
                        Stepper("完成 \(receiver.localActual) 个", value: $receiver.localActual,
                                in: 0...receiver.localSetTarget)
                            .font(.caption2).minimumScaleFactor(0.65)
                        Button("确认本组") { receiver.confirmLocalSet() }.tint(.mint)
                    } else if receiver.localActive {
                        HStack {
                            Button { receiver.toggleLocalPause() } label: {
                                Label(receiver.localPaused ? "继续" : "暂停",
                                      systemImage: receiver.localPaused ? "play.fill" : "pause.fill")
                            }.tint(.mint)
                            Button { receiver.prepareLocalEnd() } label: {
                                Label("结束", systemImage: "stop.fill")
                            }.tint(.orange)
                        }.font(.caption)
                    } else if !receiver.isFresh {
                        Button("开始盆底肌 1 组") { receiver.startLocalPelvic() }.tint(.mint)
                        Button("在手表开始深蹲") { receiver.startLocalSquat() }.tint(.mint)
                    } else if receiver.running {
                        Button("暂停手机训练") { receiver.pausePhone() }.tint(.mint)
                    } else if receiver.remotePaused {
                        Button("继续手机训练") { receiver.resumePhone() }.tint(.mint)
                    }
                    if receiver.kind == .squat {
                        if let bpm = receiver.heartRate.bpm {
                            Label("\(bpm) 次/分钟", systemImage: "heart.fill")
                                .font(.headline).foregroundStyle(.red).monospacedDigit()
                        } else {
                            Label(receiver.heartRate.status, systemImage: "heart")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(receiver.localActive ? "手表独立计时，完成后自动同步手机。" : "也可以从手机发起训练。")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal, 4)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in receiver.setActive(phase == .active) }
        }
    }
}

@MainActor
@Observable
final class WatchReceiver: NSObject, WCSessionDelegate, WKExtendedRuntimeSessionDelegate {
    enum LocalUIState { case idle, running, paused, confirming }
    private(set) var title = "等待手机"
    private(set) var detail = "在手机开始训练"
    private(set) var running = false
    private(set) var kind: WatchCuePacket.WorkoutKind = .pelvic
    private(set) var homeNotice = "可直接从手表开始训练"
    let heartRate = HeartRateWorkoutManager()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var gate = WatchCueGate()
    @ObservationIgnored private var receivedAt = 0.0
    @ObservationIgnored private var remaining = 0.0
    @ObservationIgnored private var workout: UUID?
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var localMachine: SquatMachine?
    @ObservationIgnored private var localPelvicMachine: TrainingMachine?
    @ObservationIgnored private var localPlan = SquatPlan()
    @ObservationIgnored private var localStartedAt: Date?
    @ObservationIgnored private var localLoop: Task<Void, Never>?
    @ObservationIgnored private var extendedRuntime: WKExtendedRuntimeSession?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var recoveredBackup: WatchActiveBackup?
    private(set) var localUIState: LocalUIState = .idle
    var localActual = 0
    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private static let backupKey = "activeStandaloneTraining"
    var isFresh: Bool { receivedAt > 0 && (active || localActive || heartRate.isActive) }
    var seconds: Int { Int(ceil(max(0, remaining - (running ? uptime - receivedAt : 0)))) }
    var localActive: Bool { localUIState != .idle }
    var localPaused: Bool { localUIState == .paused }
    var localNeedsConfirmation: Bool { localUIState == .confirming }
    var localSetTarget: Int { localMachine?.setTarget ?? 10 }
    var remotePaused: Bool { !localActive && isFresh && title == "已暂停" }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.backupKey) {
            recoveredBackup = try? JSONDecoder().decode(WatchActiveBackup.self, from: data)
        }
        heartRate.onHeartRate = { [weak self] bpm in self?.sendHeartRate(bpm) }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func setActive(_ value: Bool) {
        active = value
        if value { requestSync() }
        else if !heartRate.isActive && !localActive { cancelHaptics() }
    }
    func cancelHaptics() { hapticTask?.cancel(); hapticTask = nil }
    private func requestSync() {
        guard active, WCSession.default.activationState == .activated else { return }
        receiveApplicationContext(WCSession.default.receivedApplicationContext)
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["command": "sync"], replyHandler: nil, errorHandler: nil)
    }
    func pausePhone() {
        cancelHaptics(); WKInterfaceDevice.current().play(.click)
        guard let workout, WCSession.default.isReachable else {
            resetHome(notice: "手机暂时未连接"); return
        }
        WCSession.default.sendMessage(["command": "pause", "workout": workout.uuidString], replyHandler: nil) { [weak self] _ in
            Task { @MainActor in self?.resetHome(notice: "手机暂时未连接") }
        }
    }
    func resumePhone() {
        WKInterfaceDevice.current().play(.click)
        guard let workout, WCSession.default.isReachable else {
            resetHome(notice: "手机暂时未连接"); return
        }
        WCSession.default.sendMessage(["command": "resume", "workout": workout.uuidString],
                                      replyHandler: nil) { [weak self] _ in
            Task { @MainActor in self?.resetHome(notice: "手机暂时未连接") }
        }
    }
    func startLocalSquat() {
        guard !localActive else { return }
        homeNotice = "可直接从手表开始训练"
        localPlan = SquatPlan()
        var machine = SquatMachine(plan: localPlan)
        let id = UUID()
        localStartedAt = .now; workout = id; kind = .squat
        machine.start(at: uptime); localMachine = machine
        saveLocalBackup()
        heartRate.begin(workout: id, running: true)
        publishLocal(phaseChanged: true)
        localLoop?.cancel()
        localLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.tickLocal()
            }
        }
    }
    func startLocalPelvic() {
        guard !localActive else { return }
        homeNotice = "可直接从手表开始训练"
        var machine = TrainingMachine(course: .personal)
        let id = UUID()
        localStartedAt = .now; workout = id; kind = .pelvic
        machine.start(at: uptime); localPelvicMachine = machine
        saveLocalBackup()
        let runtime = WKExtendedRuntimeSession()
        runtime.delegate = self; extendedRuntime = runtime; runtime.start()
        publishLocalPelvic(phaseChanged: true)
        localLoop?.cancel()
        localLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.tickLocalPelvic()
            }
        }
    }
    private func tickLocalPelvic() {
        guard var machine = localPelvicMachine, machine.isRunning else { return }
        let oldPhase = machine.phase
        machine.tick(at: uptime); localPelvicMachine = machine
        publishLocalPelvic(phaseChanged: oldPhase != machine.phase)
        if machine.isTerminal { finishLocalPelvic(status: "completed") }
    }
    private func publishLocalPelvic(phaseChanged: Bool) {
        guard let machine = localPelvicMachine else { return }
        let nextTitle: String
        switch machine.phase {
        case .prepare: nextTitle = "准备开始"
        case .contract: nextTitle = "收缩"
        case .relax: nextTitle = "充分放松"
        case .paused: nextTitle = "已暂停"
        case .completed: nextTitle = "本组完成"
        case .interrupted: nextTitle = "本组已结束"
        case .ready: nextTitle = "准备开始"
        }
        if title != nextTitle { title = nextTitle }
        let nextUIState: LocalUIState = machine.phase == .paused ? .paused : .running
        if localUIState != nextUIState { localUIState = nextUIState }
        let nextDetail = "已完成 \(machine.completedRepetitions) / \(machine.course.repetitions) 次"
        if detail != nextDetail { detail = nextDetail }
        if running != machine.isRunning { running = machine.isRunning }
        remaining = machine.remaining; receivedAt = uptime
        if phaseChanged {
            saveLocalBackup()
            if machine.phase == .contract { playHaptic(.single) }
            if machine.phase == .relax { playHaptic(.double) }
        }
    }
    private func tickLocal() {
        guard var machine = localMachine, machine.isRunning else { return }
        let oldPhase = machine.phase
        machine.tick(at: uptime)
        localMachine = machine
        publishLocal(phaseChanged: oldPhase != machine.phase)
        if machine.isTerminal { finishLocal(status: "completed") }
    }
    private func publishLocal(phaseChanged: Bool) {
        guard let machine = localMachine else { return }
        let nextTitle: String
        switch machine.phase {
        case .prepare: nextTitle = "站稳准备"
        case .down: nextTitle = "下蹲"
        case .up: nextTitle = "起身"
        case .confirm: nextTitle = "确认本组次数"
        case .rest: nextTitle = "组间休息"
        case .resuming: nextTitle = "站稳准备"
        case .paused: nextTitle = "已暂停"
        case .completed: nextTitle = "深蹲完成"
        case .interrupted: nextTitle = "本次已结束"
        case .ready: nextTitle = "准备开始"
        }
        if title != nextTitle { title = nextTitle }
        let nextUIState: LocalUIState
        if machine.phase == .confirm { nextUIState = .confirming }
        else if machine.phase == .paused { nextUIState = .paused }
        else { nextUIState = .running }
        if localUIState != nextUIState { localUIState = nextUIState }
        let nextDetail = "第 \(machine.setIndex + 1) 组 · 已带练 \(machine.guidedInSet) / \(machine.setTarget)"
        if detail != nextDetail { detail = nextDetail }
        if running != machine.isRunning { running = machine.isRunning }
        remaining = machine.remaining
        receivedAt = uptime
        if phaseChanged {
            saveLocalBackup()
            if machine.phase == .confirm { localActual = machine.setTarget }
            heartRate.setRunning(machine.phase != .paused)
            if machine.phase == .down { playHaptic(.single) }
            if machine.phase == .up { playHaptic(.double) }
        }
    }
    func confirmLocalSet() {
        guard var machine = localMachine, machine.phase == .confirm else { return }
        machine.confirmSet(actual: localActual, at: uptime)
        localMachine = machine; publishLocal(phaseChanged: true)
        if machine.isTerminal { finishLocal(status: "completed") }
    }
    func pauseLocal() {
        if var machine = localPelvicMachine {
            machine.pause(at: uptime); localPelvicMachine = machine
            cancelHaptics(); WKInterfaceDevice.current().play(.click)
            publishLocalPelvic(phaseChanged: true); return
        }
        guard var machine = localMachine else { return }
        machine.pause(at: uptime); localMachine = machine
        cancelHaptics(); WKInterfaceDevice.current().play(.click)
        publishLocal(phaseChanged: true)
    }
    func resumeLocal() {
        if var machine = localPelvicMachine {
            machine.resume(at: uptime); localPelvicMachine = machine
            publishLocalPelvic(phaseChanged: true); return
        }
        guard var machine = localMachine else { return }
        machine.resume(at: uptime); localMachine = machine; publishLocal(phaseChanged: true)
    }
    func toggleLocalPause() {
        localPaused ? resumeLocal() : pauseLocal()
    }
    func prepareLocalEnd() {
        if var machine = localPelvicMachine {
            machine.end(at: uptime); localPelvicMachine = machine
            finishLocalPelvic(status: "interrupted"); return
        }
        guard var machine = localMachine else { return }
        machine.end(actualInCurrentSet: 0, at: uptime)
        localMachine = machine; finishLocal(status: "interrupted")
    }
    private func finishLocal(status: String) {
        guard let machine = localMachine, let id = workout, let startedAt = localStartedAt else { return }
        let result = WatchSquatResult(id: id, startedAt: startedAt, endedAt: .now,
            target: localPlan.target, down: localPlan.down, up: localPlan.up, rest: localPlan.rest,
            confirmedSets: machine.confirmedSets, guidedRepetitions: machine.guidedTotal,
            activeDuration: machine.activeDuration, status: status)
        transfer(result)
        clearLocalBackup()
        heartRate.finish()
        localLoop?.cancel(); localLoop = nil; localMachine = nil
        localStartedAt = nil
        WKInterfaceDevice.current().play(.success)
        resetHome(notice: "深蹲已记录 \(result.confirmedSets.reduce(0, +)) 个")
    }
    private func finishLocalPelvic(status: String) {
        guard let machine = localPelvicMachine, let id = workout,
              let startedAt = localStartedAt else { return }
        let result = WatchPelvicResult(id: id, startedAt: startedAt, endedAt: .now,
            completedRepetitions: machine.completedRepetitions,
            activeDuration: machine.activeDuration, status: status)
        transfer(result)
        clearLocalBackup()
        extendedRuntime?.invalidate(); extendedRuntime = nil
        localLoop?.cancel(); localLoop = nil; localPelvicMachine = nil
        localStartedAt = nil
        WKInterfaceDevice.current().play(.success)
        resetHome(notice: "盆底肌已记录 \(result.completedRepetitions) 次")
    }
    private func transfer(_ result: WatchSquatResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        let value: [String: Any] = ["squatResult": data]
        WCSession.default.transferUserInfo(value)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(value, replyHandler: nil, errorHandler: nil)
        }
    }
    private func transfer(_ result: WatchPelvicResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        let value: [String: Any] = ["pelvicResult": data]
        WCSession.default.transferUserInfo(value)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(value, replyHandler: nil, errorHandler: nil)
        }
    }
    private func saveLocalBackup() {
        let value: WatchActiveBackup?
        if let machine = localMachine, let id = workout, let startedAt = localStartedAt {
            value = WatchActiveBackup(kind: .squat, id: id, startedAt: startedAt,
                target: localPlan.target, down: localPlan.down, up: localPlan.up, rest: localPlan.rest,
                confirmedSets: machine.confirmedSets, guidedRepetitions: machine.guidedTotal,
                completedRepetitions: 0, activeDuration: machine.activeDuration)
        } else if let machine = localPelvicMachine, let id = workout, let startedAt = localStartedAt {
            value = WatchActiveBackup(kind: .pelvic, id: id, startedAt: startedAt,
                completedRepetitions: machine.completedRepetitions, activeDuration: machine.activeDuration)
        } else {
            value = nil
        }
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.backupKey)
    }
    private func clearLocalBackup() {
        recoveredBackup = nil
        UserDefaults.standard.removeObject(forKey: Self.backupKey)
    }
    private func flushRecoveredBackup() {
        guard WCSession.default.activationState == .activated, let value = recoveredBackup else { return }
        switch value.kind {
        case .squat:
            transfer(WatchSquatResult(id: value.id, startedAt: value.startedAt, endedAt: .now,
                target: value.target, down: value.down, up: value.up, rest: value.rest,
                confirmedSets: value.confirmedSets, guidedRepetitions: value.guidedRepetitions,
                activeDuration: value.activeDuration, status: "interrupted"))
        case .pelvic:
            transfer(WatchPelvicResult(id: value.id, startedAt: value.startedAt, endedAt: .now,
                completedRepetitions: value.completedRepetitions,
                activeDuration: value.activeDuration, status: "interrupted"))
        }
        clearLocalBackup()
        homeNotice = "上次中断的训练已同步"
    }
    private func receive(_ packet: WatchCuePacket) {
        guard !localActive else { return }
        guard gate.accept(packet, now: .now) else { return }
        title = packet.title; detail = packet.detail; workout = packet.workout; kind = packet.kind
        running = packet.running && packet.enabled
        remaining = max(0, packet.remaining - max(0, Date.now.timeIntervalSince(packet.sentAt)))
        receivedAt = uptime
        heartRate.handle(packet)
        if !packet.enabled || packet.title.contains("已结束") {
            cancelHaptics(); resetHome(notice: "手机训练已结束"); return
        }
        scheduleRemoteExpiry(seconds: packet.running ? 4 : 30)
        if !packet.running { cancelHaptics(); return }
        playHaptic(packet.cue)
    }
    private func scheduleRemoteExpiry(seconds: Double) {
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !self.localActive else { return }
            self.cancelHaptics(); self.resetHome(notice: "可直接从手表开始训练")
        }
    }
    private func resetHome(notice: String) {
        freshnessTask?.cancel(); freshnessTask = nil
        running = false; remaining = 0; receivedAt = 0
        workout = nil; kind = .pelvic; localActual = 0; localUIState = .idle
        title = "可独立训练"; detail = notice; homeNotice = notice
    }
    private func playHaptic(_ cue: WatchCuePacket.Cue) {
        guard cue != .none else { return }
        cancelHaptics()
        hapticTask = Task { [weak self] in
            guard let self, self.active || self.localActive || self.heartRate.isActive else { return }
            // watchOS does not expose intensity. A repeated notification pattern
            // is substantially easier to notice than the old single `.start` tap.
            let pulseCount = cue == .single ? 2 : 4
            for index in 0..<pulseCount {
                if index > 0 {
                    do { try await Task.sleep(for: .milliseconds(index == 2 ? 420 : 180)) } catch { return }
                }
                guard !Task.isCancelled,
                      self.active || self.localActive || self.heartRate.isActive else { return }
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
    private func sendHeartRate(_ bpm: Int) {
        guard let workout, WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["heartRate": bpm, "workout": workout.uuidString],
                                      replyHandler: nil, errorHandler: nil)
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flushRecoveredBackup(); self.requestSync() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            if reachable { self.requestSync() }
            else if !self.localActive { self.cancelHaptics(); self.running = false; self.receivedAt = 0 }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let packet = try? JSONDecoder().decode(WatchCuePacket.self, from: messageData) else { return }
        Task { @MainActor in self.receive(packet) }
    }
    private func receiveApplicationContext(_ context: [String: Any]) {
        guard let data = context["packet"] as? Data,
              let packet = try? JSONDecoder().decode(WatchCuePacket.self, from: data) else { return }
        receive(packet)
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receiveApplicationContext(applicationContext) }
    }
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard self.extendedRuntime === extendedRuntimeSession else { return }
            self.pauseLocal(); self.detail = "延长运行时间已到，请抬腕继续"
        }
    }
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in
            guard self.extendedRuntime === extendedRuntimeSession else { return }
            self.extendedRuntime = nil
            if self.localPelvicMachine != nil {
                self.pauseLocal(); self.detail = "后台运行已结束，请点继续"
            }
        }
    }
}

@MainActor
@Observable
final class HeartRateWorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private(set) var bpm: Int?
    private(set) var status = "等待心率"
    private(set) var isActive = false
    var onHeartRate: ((Int) -> Void)?
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var workoutID: UUID?
    @ObservationIgnored private var startingID: UUID?
    @ObservationIgnored private var failedWorkoutID: UUID?
    @ObservationIgnored private var desiredRunning = true
    @ObservationIgnored private var isEnding = false

    func handle(_ packet: WatchCuePacket) {
        guard packet.kind == .squat else {
            if isActive { finish() }
            return
        }
        if packet.title.contains("已结束") {
            finish()
        } else if workoutID == packet.workout {
            // Confirmation and rest are still part of the workout. Only an
            // explicit user/system pause should pause the HealthKit session.
            setRunning(packet.title != "已暂停")
        } else if session == nil, startingID == nil {
            begin(workout: packet.workout, running: packet.title != "已暂停")
        }
    }

    func begin(workout id: UUID, running: Bool) {
        guard failedWorkoutID != id, session == nil, startingID == nil else { return }
        if failedWorkoutID != id { failedWorkoutID = nil }
        desiredRunning = running
        startingID = id
        Task { await start(workout: id) }
    }

    private func start(workout id: UUID) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            status = "此手表无法读取心率"; startingID = nil; return
        }
        status = "请允许心率权限"
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartRateType])
            guard startingID == id else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .functionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self; builder.delegate = self
            self.session = session; self.builder = builder; workoutID = id; startingID = nil
            let startedAt = Date.now
            session.startActivity(with: startedAt)
            try await builder.beginCollection(at: startedAt)
            isActive = true; status = "正在测量心率"
            setRunning(desiredRunning)
        } catch {
            status = "无法读取心率，请检查健康权限"
            failedWorkoutID = id
            startingID = nil; session = nil; builder = nil; workoutID = nil; isActive = false
        }
    }

    func setRunning(_ value: Bool) {
        desiredRunning = value
        guard isActive, let session else { return }
        if value, session.state == .paused {
            session.resume(); status = "正在测量心率"
        } else if !value, session.state == .running {
            session.pause(); status = "心率测量已暂停"
        }
    }
    func finish() {
        guard let session, isActive, !isEnding else {
            startingID = nil; return
        }
        isEnding = true
        status = "正在保存力量训练"
        session.stopActivity(with: .now)
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        guard toState == .stopped else { return }
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            await self.finishWorkout(at: date)
        }
    }

    private func finishWorkout(at date: Date) async {
        guard let builder else { reset(status: "力量训练保存失败"); return }
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
            reset(status: "力量训练已保存")
        } catch {
            reset(status: "力量训练保存失败")
        }
    }

    private func reset(status: String) {
        session?.end()
        self.status = status
        isActive = false; session = nil; builder = nil
        workoutID = nil; startingID = nil; bpm = nil; isEnding = false
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard session === workoutSession else { return }
            failedWorkoutID = workoutID ?? startingID
            reset(status: "心率会话已中断")
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let value = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { return }
        let bpm = Int(value.rounded())
        guard (30...240).contains(bpm) else { return }
        Task { @MainActor in self.bpm = bpm; self.status = "实时心率"; self.onHeartRate?(bpm) }
    }
}
