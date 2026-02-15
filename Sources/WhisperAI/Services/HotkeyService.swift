import AppKit
import Carbon
import os.log

/// Service responsible for managing global keyboard shortcuts
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private let logger = Logger(subsystem: "com.holaai.app", category: "Hotkey")

    /// Callback when dictation should start (Fn pressed)
    var onDictationStart: (() -> Void)?

    /// Callback when dictation should stop (Fn released)
    var onDictationStop: (() -> Void)?

    /// Callback when dictation hotkey is pressed (Cmd+Shift+D) - toggle mode
    var onHotkeyPressed: (() -> Void)?

    /// Callback when command mode hotkey is pressed (Cmd+Shift+C)
    var onCommandModePressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false

    private init() {}

    /// Start listening for the global hotkey
    func startListening() {
        guard eventTap == nil else {
            logger.info("Already listening for hotkey")
            return
        }

        // Create event tap for key down, key up, and flags changed events
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        // We need to capture self for the callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            logger.error("Failed to create event tap. Accessibility permission may be required.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Started listening for hotkeys (Fn hold, Cmd+Shift+D, Cmd+Shift+C)")
        }
    }

    /// Stop listening for the global hotkey
    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isFnPressed = false
        logger.info("Stopped listening for hotkey")
    }

    /// Handle keyboard events
    private nonisolated func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        let flags = event.flags

        // Handle modifier keys (flags changed event) for walkie-talkie mode
        // We use RIGHT Option key (⌥) - check if Option is pressed without other modifiers
        if type == .flagsChanged {
            // Check for Option key (either left or right)
            let isOptionPressed = flags.contains(.maskAlternate)
            // Make sure no other modifiers are pressed (pure Option only)
            let isOnlyOption = isOptionPressed &&
                              !flags.contains(.maskCommand) &&
                              !flags.contains(.maskShift) &&
                              !flags.contains(.maskControl)

            Task { @MainActor in
                // Option just pressed (alone)
                if isOnlyOption && !self.isFnPressed {
                    self.isFnPressed = true
                    self.onDictationStart?()
                }
                // Option just released
                else if !isOptionPressed && self.isFnPressed {
                    self.isFnPressed = false
                    self.onDictationStop?()
                }
            }

            // Pass through the event
            return Unmanaged.passUnretained(event)
        }

        // Handle key down events for legacy shortcuts
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            let isCommand = flags.contains(.maskCommand)
            let isShift = flags.contains(.maskShift)

            // Check for Cmd+Shift+D (key code 2 is 'D') - Dictation toggle
            if isCommand && isShift && keyCode == 2 {
                Task { @MainActor in
                    self.onHotkeyPressed?()
                }
                return nil  // Consume the event
            }

            // Check for Cmd+Shift+C (key code 8 is 'C') - Command mode toggle
            if isCommand && isShift && keyCode == 8 {
                Task { @MainActor in
                    self.onCommandModePressed?()
                }
                return nil  // Consume the event
            }
        }

        // Pass through other events
        return Unmanaged.passUnretained(event)
    }

    deinit {
        // Note: Can't call stopListening() directly from deinit due to @MainActor isolation
        // The service is a singleton so this shouldn't be called anyway
    }
}
