import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private(set) var status = "正在连接 Apple Watch"
    private(set) var heartRate: Int?
    @ObservationIgnored private let stream = UUID()
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var latest: WatchCuePacket?
    @ObservationIgnored private var pauseHandler: (() -> Void)?
    @ObservationIgnored private var resumeHandler: (() -> Void)?
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var standaloneHandler: ((WatchSquatResult) async -> Bool)?
    @ObservationIgnored private var pendingStandalone: [WatchSquatResult] = []
    @ObservationIgnored private var importingStandalone = false
    @ObservationIgnored private var pelvicHandler: ((WatchPelvicResult) async -> Bool)?
    @ObservationIgnored private var pendingPelvic: [WatchPelvicResult] = []
    @ObservationIgnored private var importingPelvic = false
    private static let pendingKey = "pendingWatchSquatResults"
    private static let pendingPelvicKey = "pendingWatchPelvicResults"

    override private init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let values = try? JSONDecoder().decode([WatchSquatResult].self, from: data) {
            pendingStandalone = values
        }
        if let data = UserDefaults.standard.data(forKey: Self.pendingPelvicKey),
           let values = try? JSONDecoder().decode([WatchPelvicResult].self, from: data) {
            pendingPelvic = values
        }
        guard WCSession.isSupported() else { status = "此设备不支持手表连接"; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func setStandaloneHandler(_ handler: @escaping (WatchSquatResult) async -> Bool) {
        standaloneHandler = handler
        drainStandalone()
    }
    func setPelvicHandler(_ handler: @escaping (WatchPelvicResult) async -> Bool) {
        pelvicHandler = handler
        drainPelvic()
    }
    func configure() {
        refreshStatus()
    }
    func bind(workout: UUID, pause: @escaping () -> Void, resume: @escaping () -> Void) {
        owner = workout
        heartRate = nil
        pauseHandler = pause
        resumeHandler = resume
    }
    func update(workout: UUID, kind: WatchCuePacket.WorkoutKind, title: String, detail: String, remaining: Double, running: Bool,
                cue: WatchCuePacket.Cue = .none) {
        guard owner == workout else { return }
        let packet = WatchCuePacket(stream: stream, sequence: 0, sentAt: .now, workout: workout, kind: kind,
                                    title: title, detail: detail, remaining: max(0, remaining),
                                    running: running, enabled: true, cue: cue)
        send(packet)
    }
    func unbind(workout: UUID) {
        guard owner == workout else { return }
        update(workout: workout, kind: latest?.kind ?? .pelvic, title: "本次训练已结束", detail: "请查看手机记录", remaining: 0, running: false)
        heartRate = nil
        pauseHandler = nil; resumeHandler = nil; owner = nil
    }
    private func send(_ value: WatchCuePacket) {
        var packet = value
        sequence += 2
        packet.sequence = sequence + 1
        packet.sentAt = .now
        latest = packet
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(packet) else { refreshStatus(); return }
        // applicationContext keeps only the newest state. It repairs the common
        // post-install case where isReachable/isWatchAppInstalled is temporarily stale.
        var displayPacket = packet
        displayPacket.sequence = sequence
        displayPacket.cue = .none
        if let displayData = try? JSONEncoder().encode(displayPacket) {
            try? WCSession.default.updateApplicationContext(["packet": displayData])
        }
        guard WCSession.default.isReachable else { refreshStatus(); return }
        // sendMessageData is deliberately used instead of transferUserInfo: stale cues must never queue.
        WCSession.default.sendMessageData(data, replyHandler: nil) { [weak self] _ in
            Task { @MainActor in self?.status = "手表提示暂不可用，请查看手机" }
        }
    }
    private func refreshStatus() {
        let session = WCSession.default
        if session.activationState != .activated { status = "正在连接 Apple Watch" }
        else if !session.isPaired { status = "尚未配对 Apple Watch" }
        else if session.isReachable { status = "手表已连接 · 请保持手表 App 前台" }
        else if !session.isWatchAppInstalled { status = "手表版已直接安装，正在刷新连接状态" }
        else { status = "请在手表打开律练并保持前台" }
    }
    private func acceptStandalone(_ data: Data) {
        guard let value = try? JSONDecoder().decode(WatchSquatResult.self, from: data) else { return }
        if let index = pendingStandalone.firstIndex(where: { $0.id == value.id }) {
            if pendingStandalone[index].revision < value.revision { pendingStandalone[index] = value }
        } else {
            pendingStandalone.append(value)
        }
        persistPendingStandalone()
        drainStandalone()
    }
    private func persistPendingStandalone() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pendingStandalone), forKey: Self.pendingKey)
    }
    private func drainStandalone() {
        guard !importingStandalone, let handler = standaloneHandler,
              let value = pendingStandalone.first else { return }
        importingStandalone = true
        Task {
            let saved = await handler(value)
            if saved { pendingStandalone.removeAll { $0.id == value.id } }
            persistPendingStandalone()
            importingStandalone = false
            if saved { drainStandalone() }
        }
    }
    private func acceptPelvic(_ data: Data) {
        guard let value = try? JSONDecoder().decode(WatchPelvicResult.self, from: data) else { return }
        if let index = pendingPelvic.firstIndex(where: { $0.id == value.id }) {
            if pendingPelvic[index].revision < value.revision { pendingPelvic[index] = value }
        } else {
            pendingPelvic.append(value)
        }
        persistPendingPelvic()
        drainPelvic()
    }
    private func persistPendingPelvic() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pendingPelvic), forKey: Self.pendingPelvicKey)
    }
    private func drainPelvic() {
        guard !importingPelvic, let handler = pelvicHandler, let value = pendingPelvic.first else { return }
        importingPelvic = true
        Task {
            let saved = await handler(value)
            if saved { pendingPelvic.removeAll { $0.id == value.id } }
            persistPendingPelvic()
            importingPelvic = false
            if saved { drainPelvic() }
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refreshStatus() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let command = message["command"] as? String
        let workout = message["workout"] as? String
        let bpm = message["heartRate"] as? Int
        let squatResult = message["squatResult"] as? Data
        let pelvicResult = message["pelvicResult"] as? Data
        Task { @MainActor in
            if command == "pause", workout == self.owner?.uuidString { self.pauseHandler?() }
            if command == "resume", workout == self.owner?.uuidString { self.resumeHandler?() }
            if let bpm, workout == self.owner?.uuidString, (30...240).contains(bpm) {
                self.heartRate = bpm
            }
            if command == "sync" {
                // Never replay an old cue when the watch returns to the foreground.
                self.refreshStatus()
                if var packet = self.latest, Date.now.timeIntervalSince(packet.sentAt) < 2 {
                    packet.cue = .none; self.send(packet)
                }
            }
            if let squatResult { self.acceptStandalone(squatResult) }
            if let pelvicResult { self.acceptPelvic(pelvicResult) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let squat = userInfo["squatResult"] as? Data
        let pelvic = userInfo["pelvicResult"] as? Data
        Task { @MainActor in
            if let squat { self.acceptStandalone(squat) }
            if let pelvic { self.acceptPelvic(pelvic) }
        }
    }
}
