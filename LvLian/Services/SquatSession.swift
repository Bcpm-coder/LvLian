import SwiftUI
import AVFAudio

@MainActor
@Observable
final class SquatSession: Identifiable {
    nonisolated let id: UUID
    let plan: SquatPlan
    private(set) var record: SquatSnapshot
    private(set) var phase: SquatMachine.Phase = .ready
    private(set) var setIndex = 0
    private(set) var guidedInSet = 0
    private(set) var confirmed = 0
    private(set) var seconds = 5
    private(set) var countdown = CountdownState()
    private(set) var saving = false
    private(set) var hasBegunCurrentSet = false
    var errorMessage: String?
    @ObservationIgnored private var machine: SquatMachine
    @ObservationIgnored private let library: TrainingLibrary
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let haptics = HapticService()
    @ObservationIgnored private let speech = SpeechService()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Bool, Never>?
    @ObservationIgnored private var lastSavedSecond = -1
    @ObservationIgnored private var lastSuccessfulRevision = -1
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    var isTerminal: Bool { phase == .completed || phase == .interrupted }
    var setTarget: Int { plan.sets[min(setIndex, plan.sets.count - 1)] }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(plan: SquatPlan, library: TrainingLibrary, settings: AppSettings) {
        self.plan = plan; machine = SquatMachine(plan: plan)
        let record = SquatSnapshot(plan: plan)
        self.record = record; id = record.id
        self.library = library; self.settings = settings
    }
    func start() async {
        guard phase == .ready else { return }
        guard await persist(), phase == .ready else { return }
        WatchBridge.shared.configure()
        WatchBridge.shared.bind(workout: id,
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() })
        machine.start(at: now); publish(resetClock: true); cue()
        UIApplication.shared.isIdleTimerDisabled = true
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.pause() } }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }
    private func tick() {
        guard machine.isRunning else { return }
        let previous = machine.phase
        machine.tick(at: now)
        let changed = previous != machine.phase
        publish(resetClock: changed)
        if changed {
            if machine.isTerminal { finish(); return }
            cue()
            if phase == .confirm { UIApplication.shared.isIdleTimerDisabled = false }
        }
        if Int(machine.activeDuration) != lastSavedSecond {
            lastSavedSecond = Int(machine.activeDuration); checkpoint()
        }
    }
    private func publish(resetClock: Bool) {
        if resetClock {
            let duration = machine.phase == .paused ? countdown.duration : machine.phaseDuration
            countdown = CountdownState(duration: duration, remaining: machine.remaining, anchoredAt: now, running: machine.isRunning)
        }
        if phase != machine.phase { phase = machine.phase }
        if setIndex != machine.setIndex { setIndex = machine.setIndex }
        if guidedInSet != machine.guidedInSet { guidedInSet = machine.guidedInSet }
        if confirmed != machine.confirmedTotal { confirmed = machine.confirmedTotal }
        if hasBegunCurrentSet != machine.hasBegunCurrentSet { hasBegunCurrentSet = machine.hasBegunCurrentSet }
        let value = Int(ceil(machine.remaining))
        let changedSecond = seconds != value
        if changedSecond { seconds = value }
        if resetClock || changedSecond { syncWatch() }
    }
    private func cue() {
        syncWatch(cue: phase == .down ? .single : phase == .up ? .double : .none)
        let text: String
        switch phase {
        case .prepare: text = "准备开始"
        case .resuming: text = "站稳，准备"
        case .down: text = "下蹲"
        case .up: text = "起身"
        case .rest: text = "组间休息"
        case .confirm: text = "本组结束，请确认次数"
        default: return
        }
        if settings.squatVoiceEnabled { speech.speak(text) }
        if settings.squatHapticsEnabled, phase == .down || phase == .up { haptics.play(relaxing: phase == .up, strong: settings.strongHaptics) }
    }
    private func syncWatch(cue: WatchCuePacket.Cue = .none) {
        let title: String
        switch phase {
        case .down: title = "下蹲"
        case .up: title = "起身"
        case .rest: title = "组间休息"
        case .confirm: title = "请在手机确认次数"
        case .paused: title = "已暂停"
        case .completed, .interrupted: title = "本次已结束"
        default: title = "站稳准备"
        }
        WatchBridge.shared.update(workout: id, kind: .squat, title: title,
            detail: "第 \(setIndex + 1) 组 · 已带练 \(guidedInSet) / \(setTarget)",
            remaining: machine.remaining, running: machine.isRunning, cue: cue)
    }
    func pause() {
        stopCues()
        guard machine.isRunning else { return }
        machine.pause(at: now); publish(resetClock: true)
        UIApplication.shared.isIdleTimerDisabled = false; checkpoint()
    }
    func resume() {
        guard phase == .paused, errorMessage == nil else { return }
        machine.resume(at: now); publish(resetClock: true)
        UIApplication.shared.isIdleTimerDisabled = true; cue()
    }
    func confirmSet(actual: Int) {
        guard phase == .confirm, errorMessage == nil else { return }
        machine.confirmSet(actual: actual, at: now); publish(resetClock: true)
        if machine.isTerminal { finish() }
        else {
            checkpoint(); UIApplication.shared.isIdleTimerDisabled = true; cue()
        }
    }
    func end() {
        guard !isTerminal else { return }
        machine.end(actualInCurrentSet: 0, at: now)
        publish(resetClock: true); finish()
    }
    func stopCues() { speech.stop(); haptics.stop() }
    private func checkpoint() {
        record.activeDuration = machine.activeDuration
        record.confirmedSets = machine.confirmedSets
        record.guidedRepetitions = machine.guidedTotal
        enqueueSave()
    }
    private func enqueueSave() {
        record.revision += 1
        let snapshot = record
        let previous = saveTask
        if isTerminal || phase == .ready { saving = true }
        saveTask = Task { [self] in
            _ = await previous?.value
            do {
                try await library.save(snapshot)
                lastSuccessfulRevision = snapshot.revision
                if record.revision == snapshot.revision { errorMessage = nil; saving = false }
                return true
            } catch {
                if snapshot.revision >= lastSuccessfulRevision {
                    errorMessage = "训练记录暂时无法保存，请重试。\n\(error.localizedDescription)"
                    saving = false
                    if machine.isRunning {
                        machine.pause(at: now); publish(resetClock: true)
                        stopCues(); UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
                return false
            }
        }
    }
    @discardableResult func persist() async -> Bool {
        checkpoint(); return await saveTask?.value ?? false
    }
    private func finish() {
        record.status = phase == .completed ? "completed" : "interrupted"
        record.endedAt = .now; checkpoint(); cleanup()
    }
    func cleanup() {
        WatchBridge.shared.unbind(workout: id)
        loop?.cancel(); loop = nil; stopCues()
        UIApplication.shared.isIdleTimerDisabled = false
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }
}
