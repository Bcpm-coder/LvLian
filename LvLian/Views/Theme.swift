import SwiftUI

// Shared visual language keeps training cues and history easy to read.
enum Theme {
    static let squat = Color(red: 0.68, green: 0.30, blue: 0.12)
    static let teal = Color(red: 0.06, green: 0.43, blue: 0.38)
    static let ink = Color(red: 0.12, green: 0.22, blue: 0.21)
    static let background = Color(red: 0.95, green: 0.97, blue: 0.95)
    static let mint = Color(red: 0.85, green: 0.93, blue: 0.88)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(Theme.teal.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

func durationText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return "\(total / 60) 分 \(total % 60) 秒"
}

struct SourceLink: View {
    var body: some View {
        Link(destination: URL(string: "https://www.niddk.nih.gov/health-information/urologic-diseases/kegel-exercises")!) {
            Label("了解盆底肌训练 · NIDDK", systemImage: "arrow.up.right.square")
                .font(.footnote)
        }
    }
}
