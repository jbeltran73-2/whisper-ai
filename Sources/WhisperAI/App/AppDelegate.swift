import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let showDockIconDefaultsKey = "showDockIcon"
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var dictationMenuItem: NSMenuItem?
    private var overlayMenuItem: NSMenuItem?
    private let recordingOverlay = RecordingOverlayController()
    private var isOverlayVisible = true
    private var lastTranscribedText: String?

    private let dictationManager = DictationManager.shared
    private let hotkeyService = HotkeyService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: showDockIconDefaultsKey) == nil {
            defaults.set(true, forKey: showDockIconDefaultsKey)
        }
        applyActivationPolicy(showDockIcon: defaults.bool(forKey: showDockIconDefaultsKey))
        setupMenuBar()
        setupDictationCallbacks()
        setupHotkey()
        setupDockIconObserver()

        // Check and request Accessibility permission on launch
        checkAccessibilityPermission()

        // Show the floating overlay button on launch
        recordingOverlay.show()
    }

    private func checkAccessibilityPermission() {
        // This will prompt the user if permission is not granted
        // Using string literal to avoid Swift 6 concurrency issues with kAXTrustedCheckOptionPrompt
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if hasPermission {
            print("✅ [AppDelegate] Accessibility permission granted")
        } else {
            print("⚠️ [AppDelegate] Accessibility permission needed - prompting user...")
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Hola-AI")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        dictationMenuItem = NSMenuItem(
            title: "Start Dictation",
            action: #selector(toggleDictationFromMenu),
            keyEquivalent: ""
        )
        dictationMenuItem?.target = self
        menu.addItem(dictationMenuItem!)

        overlayMenuItem = NSMenuItem(
            title: "Hide Overlay",
            action: #selector(toggleOverlayVisibility),
            keyEquivalent: ""
        )
        overlayMenuItem?.target = self
        menu.addItem(overlayMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Hola-AI",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupDockIconObserver() {
        _ = NotificationCenter.default.addObserver(
            forName: .showDockIconChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let showDockIcon = notification.userInfo?["showDockIcon"] as? Bool ?? UserDefaults.standard.bool(forKey: self?.showDockIconDefaultsKey ?? "showDockIcon")
            Task { @MainActor in
                self?.applyActivationPolicy(showDockIcon: showDockIcon)
            }
        }
    }

    private func applyActivationPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        _ = NSApp.setActivationPolicy(policy)
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    private func setupDictationCallbacks() {
        dictationManager.onStateChange = { [weak self] isRecording in
            self?.updateMenuBarState(isRecording: isRecording)
            // Update the overlay button state
            self?.recordingOverlay.setRecording(isRecording)
        }

        dictationManager.onAudioLevelUpdate = { [weak self] level in
            self?.recordingOverlay.updateAudioLevel(level)
        }

        dictationManager.onCommandModeChange = { [weak self] mode in
            self?.updateCommandModeState(mode)
        }

        dictationManager.onError = { [weak self] error in
            self?.showError(error)
        }

        dictationManager.onTranscriptionReady = { [weak self] text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.lastTranscribedText = trimmed.isEmpty ? nil : trimmed
            self?.recordingOverlay.setCopyAvailable(!(trimmed.isEmpty))
        }

        // Handle toggle button click on overlay
        recordingOverlay.onToggle = { [weak self] options in
            self?.toggleDictation(intent: options.intent, translateToEnglish: options.translateToEnglish)
        }
        recordingOverlay.onCopyLastText = { [weak self] in
            self?.copyLastTranscribedTextToClipboard()
        }
        recordingOverlay.onClose = { [weak self] in
            self?.quitApp()
        }
        recordingOverlay.setCopyAvailable(false)
    }

    private func updateOverlay(isRecording: Bool) {
        // The overlay is always visible as a toggle button
        // State is updated via recordingOverlay.setRecording() in the callback
    }

    private var commandSound: NSSound?

    private func updateCommandModeState(_ mode: DictationMode) {
        switch mode {
        case .command:
            // Update menu bar to show command mode (blue tint)
            statusItem?.button?.contentTintColor = .systemBlue
            // Play different sound for command mode
            if commandSound == nil {
                commandSound = NSSound(named: NSSound.Name("Submarine"))
            }
            commandSound?.play()
        case .dictation:
            // Reset menu bar color based on recording state
            statusItem?.button?.contentTintColor = dictationManager.isRecording ? .systemRed : nil
            stopSound?.play()
        }
    }

    private func setupHotkey() {
        // Fn key: hold to record (walkie-talkie style)
        hotkeyService.onDictationStart = { [weak self] in
            guard let self = self else { return }
            // Only start if not already recording
            if !self.dictationManager.isRecording {
                Task {
                    await self.dictationManager.startDictation(intent: .transcription)
                }
            }
        }

        hotkeyService.onDictationStop = { [weak self] in
            guard let self = self else { return }
            // Only stop if currently recording
            if self.dictationManager.isRecording {
                Task {
                    await self.dictationManager.stopDictation()
                }
            }
        }

        // Cmd+Shift+D: toggle mode (legacy)
        hotkeyService.onHotkeyPressed = { [weak self] in
            self?.toggleDictation(intent: .transcription, translateToEnglish: false)
        }

        // Cmd+Shift+C: command mode toggle
        hotkeyService.onCommandModePressed = { [weak self] in
            self?.toggleCommandMode()
        }

        hotkeyService.startListening()
    }

    private func toggleCommandMode() {
        dictationManager.toggleCommandMode()
    }

    private func updateMenuBarState(isRecording: Bool) {
        if isRecording {
            dictationMenuItem?.title = "Stop Dictation"
            statusItem?.button?.image = NSImage(
                systemSymbolName: "waveform.circle.fill",
                accessibilityDescription: "Recording"
            )
            // Use a different visual to indicate recording (red tint via contentTintColor)
            statusItem?.button?.contentTintColor = .systemRed
            // Play audio feedback for recording start
            playAudioFeedback(start: true)
        } else {
            dictationMenuItem?.title = "Start Dictation"
            statusItem?.button?.image = NSImage(
                systemSymbolName: "waveform.circle.fill",
                accessibilityDescription: "Hola-AI"
            )
            statusItem?.button?.contentTintColor = nil
            statusItem?.button?.image?.isTemplate = true
            // Play audio feedback for recording stop
            playAudioFeedback(start: false)
        }
    }

    private var startSound: NSSound?
    private var stopSound: NSSound?

    private func playAudioFeedback(start: Bool) {
        // Use system sounds for audio feedback
        // Cache sounds to avoid repeated creation/destruction
        if start {
            if startSound == nil {
                startSound = NSSound(named: NSSound.Name("Tink"))
            }
            startSound?.play()
        } else {
            if stopSound == nil {
                stopSound = NSSound(named: NSSound.Name("Pop"))
            }
            stopSound?.play()
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Dictation Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        // Add context-specific second button
        if let audioError = error as? AudioCaptureError,
           case .permissionDenied = audioError {
            alert.addButton(withTitle: "Open System Settings")
        } else if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .noAPIKey, .missingModel:
                alert.addButton(withTitle: "Open Preferences")
            default:
                break
            }
        } else if let textError = error as? TextProcessingError {
            switch textError {
            case .noAPIKey, .missingModel:
                alert.addButton(withTitle: "Open Preferences")
            default:
                break
            }
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // Handle second button based on error type
            if let audioError = error as? AudioCaptureError,
               case .permissionDenied = audioError {
                // Open System Settings > Privacy & Security > Microphone
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            } else if let transcriptionError = error as? TranscriptionError {
                switch transcriptionError {
                case .noAPIKey, .missingModel:
                    openPreferences()
                default:
                    break
                }
            } else if let textError = error as? TextProcessingError {
                switch textError {
                case .noAPIKey, .missingModel:
                    openPreferences()
                default:
                    break
                }
            }
        }
    }

    @objc private func toggleDictationFromMenu() {
        toggleDictation(intent: .transcription, translateToEnglish: false)
    }

    @objc private func toggleOverlayVisibility() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    private func showOverlay() {
        guard !isOverlayVisible else { return }
        recordingOverlay.show()
        isOverlayVisible = true
        overlayMenuItem?.title = "Hide Overlay"
        recordingOverlay.setCopyAvailable(lastTranscribedText != nil)
    }

    private func hideOverlay() {
        guard isOverlayVisible else { return }
        recordingOverlay.hide()
        isOverlayVisible = false
        overlayMenuItem?.title = "Show Overlay"
    }

    private func copyLastTranscribedTextToClipboard() {
        guard let text = lastTranscribedText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func toggleDictation(intent: DictationIntent, translateToEnglish: Bool) {
        Task {
            await dictationManager.toggleDictation(intent: intent, translateToEnglish: translateToEnglish)
        }
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let preferencesView = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "Hola-AI Preferences"
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
            preferencesWindow?.center()
            preferencesWindow?.isReleasedWhenClosed = false
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
