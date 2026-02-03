import Cocoa
import ApplicationServices

// Global reference to the keyboard event tap for use in the callback
private var globalKeyboardEventTap: CFMachPort?

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    // Static mapping for common QWERTY key codes
    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased()
        switch lower {
            case "a": return 0
            case "s": return 1
            case "d": return 2
            case "f": return 3
            case "h": return 4
            case "g": return 5
            case "z": return 6
            case "x": return 7
            case "c": return 8
            case "v": return 9
            case "b": return 11
            case "q": return 12
            case "w": return 13
            case "e": return 14
            case "r": return 15
            case "y": return 16
            case "t": return 17
            case "1": return 18
            case "2": return 19
            case "3": return 20
            case "4": return 21
            case "6": return 22
            case "5": return 23
            case "=": return 24
            case "9": return 25
            case "7": return 26
            case "-": return 27
            case "8": return 28
            case "0": return 29
            case "]": return 30
            case "o": return 31
            case "u": return 32
            case "[": return 33
            case "i": return 34
            case "p": return 35
            case "l": return 37
            case "j": return 38
            case "'": return 39
            case "k": return 40
            case ";": return 41
            case "\\": return 42
            case ",": return 43
            case "/": return 44
            case "n": return 45
            case "m": return 46
            case ".": return 47
            default: return nil
        }
    }

    func start() {
        // Listen for KeyDown events
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Create the tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: keyboardEventCallback,
            userInfo: nil
        ) else {
            print("KeyboardInterceptor: Failed to create event tap.")
            return
        }

        self.eventTap = tap
        globalKeyboardEventTap = tap  // Store globally for callback access
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let rls = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("KeyboardInterceptor: Started.")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let rls = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, .commonModes)
            }
        }
        globalKeyboardEventTap = nil  // Clear global reference
        eventTap = nil
        runLoopSource = nil
    }
}

// Global C-function callback
func keyboardEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // Handle special event types - tap may be disabled by system
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap using the global reference
        if let tap = globalKeyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    
    // Only process keyDown events
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }
    
    // OPTIMIZATION: Check modifier keys FIRST
    // All global shortcuts require a modifier (Command, Control, or Option)
    // If no modifier is pressed, immediately pass through without any processing
    let flags = event.flags
    let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    
    if !hasModifier {
        // No modifier key pressed - pass through immediately
        // This ensures Enter, regular typing, etc. go through with zero interference
        return Unmanaged.passUnretained(event)
    }
    
    // From here, we know a modifier key IS pressed
    let defaults = UserDefaults.standard
    let globalAnywhere = defaults.bool(forKey: "globalShortcutAnywhere")

    // Check Scope: If NOT global anywhere, require Terminal focus
    if !globalAnywhere {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.Terminal" else {
            // Not in Terminal, pass through for our app to handle
            return Unmanaged.passUnretained(event)
        }
    }

    let targetKeyChar = defaults.string(forKey: "globalShortcutKey") ?? "n"
    let targetModifierStr = defaults.string(forKey: "globalShortcutModifier") ?? "command"
    
    // Get target KeyCode
    guard let targetKeyCode = KeyboardInterceptor.getKeyCode(for: targetKeyChar) else {
        return Unmanaged.passUnretained(event)
    }
    
    // Check if the specific modifier matches (exclusive - only that modifier, not others)
    var modifierMatch = false
    switch targetModifierStr {
        case "command": 
            modifierMatch = flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        case "control": 
            modifierMatch = flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
        case "option":  
            modifierMatch = flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
        default: 
            modifierMatch = false
    }
    
    if modifierMatch && event.getIntegerValueField(.keyboardEventKeycode) == Int64(targetKeyCode) {
        // MATCH DETECTED! This is the global shortcut.
        
        // If FineTerm is already active, pass through to let local monitor handle it
        if NSApp.isActive {
            return Unmanaged.passUnretained(event)
        }
        
        // Otherwise, activate FineTerm and show window
        DispatchQueue.main.async {
            // Get the app delegate to access the window
            if let appDelegate = NSApp.delegate as? AppDelegate,
               let window = appDelegate.window {
                // Show the window if it's not visible or is minimized
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return nil // Swallow the event
    }
    
    return Unmanaged.passUnretained(event)
}
