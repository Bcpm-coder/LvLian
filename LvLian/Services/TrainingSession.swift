import SwiftUI
import AVFAudio

@MainActor
@Observable
final class TrainingSession: Identifiable {
    nonisolated let id: UUID
    let course: Course
    private(set) var record: PelvicSnapshot
    private(set) var phase: TrainingMachine.Phase = .ready
    private(set) var completedRepetitions = 0
    private(set) var seconds = 5
    private(set) var countdown = CountdownState()
    private(set) var saving = false
    var errorMessage: String?
    @ObservationIgnored private var machine: TrainingMachine
    @ObservationIgnored private let library: TrainingLibrary
    @ObservationIgnored private let haptics = HapticService()
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Bool, Never>?
    @ObservationIgnored private var lastSavedSecond = -1
    @ObservationIgnored private var lastSuccessfulRevision = -1
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    var isTerminal: Bool { phase == .completed || phase == .interrupted }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(course: Course, library: TrainingLibrary, settings: AppSettings) {
        self.course = course; machine = TrainingMachine(course: course)
        let newRecord = PelvicSnapshot(course: course)
        record = newRecord; id = newRecord.id
        self.library = library; self.settings = settings
    }
    func start() async {
        guard phase == .ready else { return }
        guard await persist(), phase == .ready else { return }
        WatchBridge.shared.configure()
        WatchBridge.shared.bind(workout: id,
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() })
        machine.start(at: now); publish(resetClock: true)
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
        }
        if Int(machine.activeDuration) != lastSavedSecond {
            lastSavedSecond = Int(machine.activeDuration)
            checkpoint()
        }
    }
    private func publish(resetClock: Bool) {
        if resetClock {
            let duration = machine.phase == .paused ? countdown.duration : machine.phaseDuration
            countdown = CountdownState(duration: duration, remaining: machine.remaining, anchoredAt: now, running: machine.isRunning)
        }
        if phase != machine.phase { phase = machine.phase }
        if completedRepetitions != machine.completedRepetitions { completedRepetitions = machine.completedRepetitions }
        let value = Int(ceil(machine.remaining))
        let changedSecond = seconds != value
        if changedSecond { seconds = value }
        if resetClock || changedSecond { syncWatch() }
    }
    private func cue() {
        syncWatch(cue: phase == .contract ? .single : phase == .relax ? .double : .none)
        guard settings.hapticsEnabled else { return }
        if phase == .contract || phase == .relax { haptics.play(relaxing: phase == .relax, strong: settings.strongHaptics) }
    }
    private func syncWatch(cue: WatchCuePacket.Cue = .none) {
        let title: String
        switch phase {
        case .contract: title = "轻柔收缩"
        case .relax: title = "充分放松"
        case .prepare, .ready: title = "准备开始"
        case .paused: title = "已暂停"
        case .completed: title = "本组完成"
        case .interrupted: title = "本次已结束"
        }
        WatchBridge.shared.update(workout: id, kind: .pelvic, title: title,
            detail: "已完成 \(completedRepetitions) / \(course.repetitions) 次",
            remaining: machine.remaining, running: machine.isRunning, cue: cue)
    }
    func pause() {
        guard machine.isRunning else { return }
        machine.pause(at: now); publish(resetClock: true)
        haptics.stop(); UIApplication.shared.isIdleTimerDisabled = false
        checkpoint()
    }
    func resume() {
        guard phase == .paused, errorMessage == nil else { return }
        machine.resume(at: now); publish(resetClock: true)
        UIApplication.shared.isIdleTimerDisabled = true; cue()
    }
    func end(feedback: String? = nil) {
        guard !isTerminal else { return }
        record.feedback = feedback
        machine.end(at: now); publish(resetClock: true); finish()
    }
    func setFeedback(_ value: String) { record.feedback = value; checkpoint() }
    private func checkpoint() {
        record.activeDuration = machine.activeDuration
        record.completedRepetitions = machine.completedRepetitions
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
                        haptics.stop(); UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
                return false
            }
        }
    }
    @discardableResult func persist() async -> Bool {
        checkpoint()
        return await saveTask?.value ?? false
    }
    private func finish() {
        record.status = phase == .completed ? "completed" : "interrupted"
        record.endedAt = .now
        checkpoint(); cleanup()
    }
    func cleanup() {
        WatchBridge.shared.unbind(workout: id)
        loop?.cancel(); loop = nil
        haptics.stop(); UIApplication.shared.isIdleTimerDisabled = false
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }
}
