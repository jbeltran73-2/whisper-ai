import AppKit
import SwiftUI

/// Controller for the floating recording overlay window
@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingOverlayView>?

    private var isRecording = false
    private var isTranscribing = false
    private var audioLevel: Float = 0
    private var intent: DictationIntent = .transcription
    private var translateToEnglish: Bool = false
    private var canCopyLastText = false
    private let idleSize = NSSize(width: 260, height: 96)
    private let recordingSize = NSSize(width: 310, height: 96)

    /// Callback when the toggle button is pressed
    var onToggle: ((DictationOptions) -> Void)?
    var onCopyLastText: (() -> Void)?
    var onClose: (() -> Void)?

    /// Show the overlay (always visible, ready to record)
    func show() {
        guard panel == nil else { return }

        // Use NSPanel with nonactivatingPanel so clicking doesn't steal focus from the text field
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: idleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        // These settings ensure the panel doesn't take focus
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false

        let overlayView = RecordingOverlayView(
            isRecording: isRecording,
            isTranscribing: isTranscribing,
            audioLevel: audioLevel,
            intent: intent,
            translateToEnglish: translateToEnglish,
            canCopyLastText: canCopyLastText,
            onToggle: { [weak self] options in
                self?.onToggle?(options)
            },
            onIntentChange: { [weak self] newIntent in
                self?.intent = newIntent
                if newIntent == .prompt {
                    self?.translateToEnglish = true
                }
                self?.updateView()
            },
            onTranslateChange: { [weak self] shouldTranslate in
                self?.translateToEnglish = shouldTranslate
                self?.updateView()
            },
            onCopyLastText: { [weak self] in
                self?.onCopyLastText?()
            },
            onClose: { [weak self] in
                self?.onClose?()
            }
        )
        let hostingView = NSHostingView(rootView: overlayView)
        self.hostingView = hostingView
        panel.contentView = hostingView
        hostingView.autoresizingMask = [.width, .height]

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true

        // Position in bottom-right corner with padding
        positionWindow(panel)

        panel.orderFront(nil)
        self.panel = panel
    }

    /// Hide the overlay completely
    func hide() {
        panel?.contentView = nil
        hostingView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// Update the recording state
    func setRecording(_ recording: Bool) {
        isRecording = recording

        if !recording {
            // Reset intent after each recording (do not remember last option)
            intent = .transcription
            translateToEnglish = false
        }

        updateView()

        // Resize panel based on state
        if let panel = panel {
            let newSize = recording ? recordingSize : idleSize
            var frame = panel.frame
            let widthDiff = newSize.width - frame.width
            frame.size.width = newSize.width
            frame.size.height = newSize.height
            frame.origin.x -= widthDiff // Keep right edge in place
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    /// Update the transcribing state (show spinner)
    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
        updateView()
    }

    /// Update the audio level visualization
    func updateAudioLevel(_ level: Float) {
        audioLevel = level
        updateView()
    }

    /// Update whether copy-last-text button should be enabled
    func setCopyAvailable(_ available: Bool) {
        canCopyLastText = available
        updateView()
    }

    private func updateView() {
        hostingView?.rootView = RecordingOverlayView(
            isRecording: isRecording,
            isTranscribing: isTranscribing,
            audioLevel: audioLevel,
            intent: intent,
            translateToEnglish: translateToEnglish,
            canCopyLastText: canCopyLastText,
            onToggle: { [weak self] options in
                self?.onToggle?(options)
            },
            onIntentChange: { [weak self] newIntent in
                self?.intent = newIntent
                if newIntent == .prompt {
                    self?.translateToEnglish = true
                }
                self?.updateView()
            },
            onTranslateChange: { [weak self] shouldTranslate in
                self?.translateToEnglish = shouldTranslate
                self?.updateView()
            },
            onCopyLastText: { [weak self] in
                self?.onCopyLastText?()
            },
            onClose: { [weak self] in
                self?.onClose?()
            }
        )
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }

        let screenRect = screen.visibleFrame
        let padding: CGFloat = 20
        let windowSize = window.frame.size

        let x = screenRect.maxX - windowSize.width - padding
        let y = screenRect.minY + padding

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
