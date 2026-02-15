import Foundation
import CoreGraphics
import os.log

/// Represents a voice command that can be executed
struct VoiceCommand {
    let name: String
    let patterns: [String]  // Regex patterns to match the command
    let action: VoiceCommandAction
}

/// Actions that can be performed by voice commands
enum VoiceCommandAction {
    case deleteThat
    case deleteLastSentence
    case undo
    case selectAll
    case clear
    case custom(handler: () -> Void)
}

/// Current mode of the dictation system
enum DictationMode {
    case dictation  // Normal dictation - text is transcribed and inserted
    case command    // Command mode - speech is interpreted as commands
}

/// Service responsible for handling voice commands
@MainActor
final class VoiceCommandService {
    static let shared = VoiceCommandService()

    private let logger = Logger(subsystem: "com.whisperai.app", category: "VoiceCommand")

    /// Current mode
    private(set) var mode: DictationMode = .dictation

    /// Callback when mode changes
    var onModeChange: ((DictationMode) -> Void)?

    /// Callback when a command is executed
    var onCommandExecuted: ((String) -> Void)?

    /// Timeout for command mode (auto-exit after inactivity)
    private var commandModeTimer: Timer?
    private let commandModeTimeout: TimeInterval = 30.0  // 30 seconds

    /// Available commands
    private let commands: [VoiceCommand] = [
        VoiceCommand(
            name: "Delete That",
            patterns: ["(?i)^delete\\s+that$", "(?i)^remove\\s+that$", "(?i)^erase\\s+that$"],
            action: .deleteThat
        ),
        VoiceCommand(
            name: "Delete Last Sentence",
            patterns: ["(?i)^delete\\s+last\\s+sentence$", "(?i)^remove\\s+last\\s+sentence$"],
            action: .deleteLastSentence
        ),
        VoiceCommand(
            name: "Undo",
            patterns: ["(?i)^undo$", "(?i)^undo\\s+that$"],
            action: .undo
        ),
        VoiceCommand(
            name: "Select All",
            patterns: ["(?i)^select\\s+all$"],
            action: .selectAll
        ),
        VoiceCommand(
            name: "Clear",
            patterns: ["(?i)^clear$", "(?i)^clear\\s+all$", "(?i)^clear\\s+text$"],
            action: .clear
        )
    ]

    private let textInsertionService = TextInsertionService()

    /// Last inserted text (for "delete that" command)
    private var lastInsertedText: String?

    private init() {}

    /// Toggle between dictation and command mode
    func toggleMode() {
        if mode == .dictation {
            enterCommandMode()
        } else {
            exitCommandMode()
        }
    }

    /// Enter command mode
    func enterCommandMode() {
        guard mode != .command else { return }

        mode = .command
        onModeChange?(.command)
        logger.info("Entered command mode")

        // Start timeout timer
        startCommandModeTimer()
    }

    /// Exit command mode (return to dictation)
    func exitCommandMode() {
        guard mode != .dictation else { return }

        mode = .dictation
        onModeChange?(.dictation)
        cancelCommandModeTimer()
        logger.info("Exited command mode")
    }

    /// Process speech input based on current mode
    /// - Parameter text: The transcribed text
    /// - Returns: True if text was processed as a command, false if it should be inserted as dictation
    func processInput(_ text: String) -> Bool {
        guard mode == .command else {
            // In dictation mode, track last inserted text for "delete that"
            lastInsertedText = text
            return false
        }

        // Reset timeout timer on activity
        startCommandModeTimer()

        // Try to match a command
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for command in commands {
            for pattern in command.patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: trimmedText, options: [], range: NSRange(trimmedText.startIndex..., in: trimmedText)) != nil {
                    executeCommand(command)
                    return true
                }
            }
        }

        // No command matched - could speak "exit" to leave command mode
        if trimmedText.lowercased() == "exit" || trimmedText.lowercased() == "exit command mode" {
            exitCommandMode()
            return true
        }

        logger.warning("Unrecognized command: \(trimmedText)")
        return true  // Still consumed the input (didn't insert as text)
    }

    /// Execute a voice command
    private func executeCommand(_ command: VoiceCommand) {
        logger.info("Executing command: \(command.name)")

        switch command.action {
        case .deleteThat:
            executeDeleteThat()
        case .deleteLastSentence:
            executeDeleteLastSentence()
        case .undo:
            executeUndo()
        case .selectAll:
            executeSelectAll()
        case .clear:
            executeClear()
        case .custom(let handler):
            handler()
        }

        onCommandExecuted?(command.name)
    }

    // MARK: - Command Implementations

    private func executeDeleteThat() {
        guard let lastText = lastInsertedText, !lastText.isEmpty else {
            logger.warning("No text to delete")
            return
        }

        // Select and delete the last inserted text length
        // This works by pressing backspace for each character
        let charCount = lastText.count
        for _ in 0..<charCount {
            simulateKeyPress(keyCode: 51)  // Backspace
        }

        lastInsertedText = nil
        logger.info("Deleted \(charCount) characters")
    }

    private func executeDeleteLastSentence() {
        // Select all and analyze to find last sentence
        // For now, just use backspace until we hit a period or start of text
        // This is a simplified implementation
        logger.info("Delete last sentence - pressing Cmd+Shift+Left then Backspace")

        // Shift+Cmd+Left to select to beginning of line, then Backspace
        simulateKeyPress(keyCode: 123, modifiers: [.maskShift, .maskCommand])  // Cmd+Shift+Left
        simulateKeyPress(keyCode: 51)  // Backspace
    }

    private func executeUndo() {
        // Cmd+Z
        simulateKeyPress(keyCode: 6, modifiers: [.maskCommand])
        logger.info("Executed Undo (Cmd+Z)")
    }

    private func executeSelectAll() {
        // Cmd+A
        simulateKeyPress(keyCode: 0, modifiers: [.maskCommand])
        logger.info("Executed Select All (Cmd+A)")
    }

    private func executeClear() {
        // Cmd+A then Backspace
        simulateKeyPress(keyCode: 0, modifiers: [.maskCommand])  // Cmd+A
        usleep(50000)  // 50ms delay
        simulateKeyPress(keyCode: 51)  // Backspace
        logger.info("Executed Clear (Cmd+A + Backspace)")
    }

    // MARK: - Keyboard Simulation

    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            if !modifiers.isEmpty {
                keyDown.flags = modifiers
            }
            keyDown.post(tap: .cghidEventTap)
        }

        usleep(10000)  // 10ms delay

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            if !modifiers.isEmpty {
                keyUp.flags = modifiers
            }
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Timer Management

    private func startCommandModeTimer() {
        cancelCommandModeTimer()
        commandModeTimer = Timer.scheduledTimer(withTimeInterval: commandModeTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.exitCommandMode()
            }
        }
    }

    private func cancelCommandModeTimer() {
        commandModeTimer?.invalidate()
        commandModeTimer = nil
    }
}
