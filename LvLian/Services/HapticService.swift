import CoreHaptics

@MainActor
final class HapticService {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func play(relaxing: Bool, strong: Bool = true) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            try player?.stop(atTime: CHHapticTimeImmediate)
            let times: [Double] = relaxing ? [0, 0.32] : [0]
            let events = times.map {
                CHHapticEvent(eventType: strong ? .hapticContinuous : .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: strong ? 1.0 : (relaxing ? 0.45 : 0.7)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: strong ? 0.75 : 0.4)
                ], relativeTime: $0, duration: strong ? 0.16 : 0)
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Visual guidance always remains available if the engine is interrupted.
            stop()
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop(completionHandler: nil)
        player = nil
        engine = nil
    }
}
