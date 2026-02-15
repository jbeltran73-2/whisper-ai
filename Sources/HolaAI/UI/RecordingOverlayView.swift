import SwiftUI

/// A floating overlay with a toggle button for recording
struct RecordingOverlayView: View {
    let isRecording: Bool
    let audioLevel: Float
    let intent: DictationIntent
    let translateToEnglish: Bool
    let canCopyLastText: Bool
    var onToggle: ((DictationOptions) -> Void)?
    var onIntentChange: ((DictationIntent) -> Void)?
    var onTranslateChange: ((Bool) -> Void)?
    var onCopyLastText: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                closeButton
            }
            HStack(spacing: 10) {
                // Main toggle button (microphone)
                Button(action: {
                    onToggle?(DictationOptions(intent: intent, translateToEnglish: translateToEnglish))
                }) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 36, height: 36)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                if isRecording {
                    AudioLevelView(level: audioLevel)
                        .frame(width: 50, height: 20)
                }

                IconToggle(
                    isOn: promptToggleBinding,
                    systemName: "sparkles",
                    onColor: Color.orange
                )
                .disabled(isRecording)

                FlagToggle(
                    isOn: translateToggleBinding,
                    onColor: Color.blue
                )
                .disabled(isRecording || intent == .prompt)
                .opacity(intent == .prompt ? 0.5 : 1.0)

                Button(action: {
                    onCopyLastText?()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canCopyLastText ? .white : .secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(canCopyLastText ? Color.green : Color.white.opacity(0.98))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCopyLastText)
                .help("Copy last spoken text")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(controlClusterBackground)
        }
        .padding(8)
    }

    private var controlClusterBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private var closeButton: some View {
        Button(action: {
            onClose?()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(0.75)))
        }
        .buttonStyle(.plain)
    }

    private var promptToggleBinding: Binding<Bool> {
        Binding(
            get: { intent == .prompt },
            set: { isPrompt in
                onIntentChange?(isPrompt ? .prompt : .transcription)
            }
        )
    }

    private var translateToggleBinding: Binding<Bool> {
        Binding(
            get: { translateToEnglish || intent == .prompt },
            set: { shouldTranslate in
                onTranslateChange?(shouldTranslate)
            }
        )
    }
}

private struct IconToggle: View {
    @Binding var isOn: Bool
    let systemName: String
    let onColor: Color

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn ? .white : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isOn ? onColor : Color.white.opacity(0.98))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

private struct FlagToggle: View {
    @Binding var isOn: Bool
    let onColor: Color

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack {
                Circle()
                    .fill(isOn ? Color.clear : Color.white.opacity(0.98))

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    HStack(spacing: 0) {
                        USFlagView()
                            .frame(width: width / 2, height: height)
                        UKFlagView()
                            .frame(width: width / 2, height: height)
                    }
                }
                .clipShape(Circle())

                Circle()
                    .stroke(isOn ? onColor : Color.white.opacity(1.0), lineWidth: 1.5)
            }
            .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

private struct USFlagView: View {
    var body: some View {
        Canvas { context, size in
            let stripeCount = 13
            let stripeHeight = size.height / CGFloat(stripeCount)
            for index in 0..<stripeCount {
                let isRed = index % 2 == 0
                let rect = CGRect(x: 0, y: CGFloat(index) * stripeHeight, width: size.width, height: stripeHeight)
                context.fill(Path(rect), with: .color(isRed ? .red : .white))
            }

            let cantonWidth = size.width * 0.45
            let cantonHeight = size.height * 0.55
            let cantonRect = CGRect(x: 0, y: 0, width: cantonWidth, height: cantonHeight)
            context.fill(Path(cantonRect), with: .color(.blue))

            let rows = 5
            let cols = 6
            let starRadius = min(cantonWidth / CGFloat(cols * 3), cantonHeight / CGFloat(rows * 3))
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = (CGFloat(col) + 0.5) * (cantonWidth / CGFloat(cols))
                    let y = (CGFloat(row) + 0.5) * (cantonHeight / CGFloat(rows))
                    let rect = CGRect(x: x - starRadius / 2, y: y - starRadius / 2, width: starRadius, height: starRadius)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

private struct UKFlagView: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.03, green: 0.2, blue: 0.55)))

            let diagWidth = size.height * 0.25
            let wideDiag = diagWidth * 0.6
            let redDiag = diagWidth * 0.35

            let diagonal1 = Path { path in
                path.move(to: CGPoint(x: 0, y: wideDiag))
                path.addLine(to: CGPoint(x: wideDiag, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height - wideDiag))
                path.addLine(to: CGPoint(x: size.width - wideDiag, y: size.height))
                path.closeSubpath()
            }
            context.fill(diagonal1, with: .color(.white))

            let diagonal2 = Path { path in
                path.move(to: CGPoint(x: size.width - wideDiag, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: wideDiag))
                path.addLine(to: CGPoint(x: wideDiag, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height - wideDiag))
                path.closeSubpath()
            }
            context.fill(diagonal2, with: .color(.white))

            let redDiagonal1 = Path { path in
                path.move(to: CGPoint(x: 0, y: redDiag))
                path.addLine(to: CGPoint(x: redDiag, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height - redDiag))
                path.addLine(to: CGPoint(x: size.width - redDiag, y: size.height))
                path.closeSubpath()
            }
            context.fill(redDiagonal1, with: .color(.red))

            let redDiagonal2 = Path { path in
                path.move(to: CGPoint(x: size.width - redDiag, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: redDiag))
                path.addLine(to: CGPoint(x: redDiag, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height - redDiag))
                path.closeSubpath()
            }
            context.fill(redDiagonal2, with: .color(.red))

            let whiteCrossWidth = size.height * 0.3
            let redCrossWidth = size.height * 0.18

            let horizontalWhite = CGRect(x: 0, y: (size.height - whiteCrossWidth) / 2, width: size.width, height: whiteCrossWidth)
            let verticalWhite = CGRect(x: (size.width - whiteCrossWidth) / 2, y: 0, width: whiteCrossWidth, height: size.height)
            context.fill(Path(horizontalWhite), with: .color(.white))
            context.fill(Path(verticalWhite), with: .color(.white))

            let horizontalRed = CGRect(x: 0, y: (size.height - redCrossWidth) / 2, width: size.width, height: redCrossWidth)
            let verticalRed = CGRect(x: (size.width - redCrossWidth) / 2, y: 0, width: redCrossWidth, height: size.height)
            context.fill(Path(horizontalRed), with: .color(.red))
            context.fill(Path(verticalRed), with: .color(.red))
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

/// Animated audio level visualization
struct AudioLevelView: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                let isActive = level > threshold
                let barHeight = CGFloat(index + 1) * 4

                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? barColor(for: index) : Color.gray.opacity(0.3))
                    .frame(width: 5, height: barHeight)
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 20, alignment: .bottom)
    }

    private func barColor(for index: Int) -> Color {
        let progress = Float(index) / Float(barCount - 1)
        if progress < 0.5 {
            return .green
        } else if progress < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview("Idle") {
    RecordingOverlayView(
        isRecording: false,
        audioLevel: 0,
        intent: .transcription,
        translateToEnglish: false,
        canCopyLastText: true
    )
    .padding()
}

#Preview("Recording") {
    RecordingOverlayView(
        isRecording: true,
        audioLevel: 0.6,
        intent: .prompt,
        translateToEnglish: true,
        canCopyLastText: true
    )
    .padding()
}
