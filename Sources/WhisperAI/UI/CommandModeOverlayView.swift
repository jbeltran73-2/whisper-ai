import SwiftUI

/// A floating overlay that shows when command mode is active
struct CommandModeOverlayView: View {
    @State private var isPulsing = false
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing command indicator (blue instead of red)
            Image(systemName: "command.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                    value: isPulsing
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Command Mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Say a command or \"exit\"")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Audio level bars
            AudioLevelView(level: audioLevel)
                .frame(width: 40, height: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

#Preview {
    CommandModeOverlayView(audioLevel: 0.4)
        .padding()
}
