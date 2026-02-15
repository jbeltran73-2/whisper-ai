import AppKit
import ApplicationServices
import os.log

/// Errors that can occur during text insertion
enum TextInsertionError: Error, LocalizedError {
    case accessibilityNotGranted
    case noFocusedElement
    case insertionFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility access is required. Please enable it in System Settings > Privacy & Security > Accessibility."
        case .noFocusedElement:
            return "No text field is currently focused. Click on a text field and try again."
        case .insertionFailed:
            return "Failed to insert text. The application may not support text insertion."
        }
    }
}

/// Service responsible for inserting text into the currently focused text field
@MainActor
final class TextInsertionService {
    private let logger = Logger(subsystem: "com.whisperai.app", category: "TextInsertion")

    /// Check if Accessibility permission is granted
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission (opens System Settings)
    func requestAccessibilityPermission() {
        // This will show a prompt to the user and open System Settings
        // The constant value is "AXTrustedCheckOptionPrompt" - using literal to avoid Swift 6 concurrency issues
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Insert text at the current cursor position
    /// - Parameter text: The text to insert
    func insertText(_ text: String) throws {
        // CRITICAL: Check for Accessibility permission first
        print("🔐 [TextInsertion] Checking Accessibility permission...")
        let hasPermission = AXIsProcessTrusted()
        print("🔐 [TextInsertion] Accessibility permission: \(hasPermission ? "✅ GRANTED" : "❌ NOT GRANTED")")

        if !hasPermission {
            print("❌ [TextInsertion] Cannot insert text without Accessibility permission!")
            print("💡 [TextInsertion] Go to: System Settings → Privacy & Security → Accessibility → Enable Whisper-AI")
            throw TextInsertionError.accessibilityNotGranted
        }

        // Method 1: Try using the pasteboard and simulating Cmd+V
        // This is the most reliable method across different apps
        try insertTextViaPasteboard(text)
    }

    /// Insert text by copying to pasteboard and simulating Cmd+V
    private func insertTextViaPasteboard(_ text: String) throws {
        // Save current pasteboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [TextInsertion] Text copied to clipboard")

        // Simulate Cmd+V keystroke
        print("⌨️ [TextInsertion] Simulating Cmd+V...")
        simulatePaste()

        // Restore previous pasteboard content after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                print("📋 [TextInsertion] Previous clipboard restored")
            }
        }

        logger.info("Text inserted via pasteboard: \(text.prefix(30))...")
    }

    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        // Create key down event for 'V' with Command modifier
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyVCode: CGKeyCode = 9

        // Create key down event
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyVCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Create key up event
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyVCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Insert text character by character using CGEvents
    /// This is an alternative method that doesn't use the pasteboard
    /// but may be slower for long text
    func insertTextViaKeyEvents(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            guard character.unicodeScalars.first != nil else { continue }

            // Create key event with unicode character
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDown.keyboardSetUnicodeString(string: String(character))
                keyDown.post(tap: .cghidEventTap)
            }

            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUp.keyboardSetUnicodeString(string: String(character))
                keyUp.post(tap: .cghidEventTap)
            }

            // Small delay between characters to prevent issues
            Thread.sleep(forTimeInterval: 0.001)
        }

        logger.info("Text inserted via key events: \(text.prefix(30))...")
    }
}

// MARK: - CGEvent Extension for Unicode String

extension CGEvent {
    func keyboardSetUnicodeString(string: String) {
        let utf16 = Array(string.utf16)
        let length = utf16.count
        utf16.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                self.keyboardSetUnicodeString(stringLength: length, unicodeString: baseAddress)
            }
        }
    }
}
