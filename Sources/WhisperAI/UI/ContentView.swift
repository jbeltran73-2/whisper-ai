import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue)

            Text("Hola-AI")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-Powered Voice Dictation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 300, minHeight: 200)
    }
}

#Preview {
    ContentView()
}
