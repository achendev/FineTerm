import Cocoa
import ApplicationServices

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
    }
}

// Global C-function callback
func keyboardEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    let defaults = UserDefaults.standard
    let globalAnywhere = defaults.bool(forKey: "globalShortcutAnywhere")

    // 1. Check Scope: If NOT global anywhere, require Terminal focus
    if !globalAnywhere {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.Terminal" else {
            // If we are NOT in Terminal, we might be in our own app.
            // We pass it through so our app can handle it normally.
            return Unmanaged.passUnretained(event)
        }
    }
    // If globalAnywhere is true, we proceed regardless of frontApp

    let targetKeyChar = defaults.string(forKey: "globalShortcutKey") ?? "n"
    let targetModifierStr = defaults.string(forKey: "globalShortcutModifier") ?? "command"
    
    // 2. Get target KeyCode
    guard let targetKeyCode = KeyboardInterceptor.getKeyCode(for: targetKeyChar) else {
        return Unmanaged.passUnretained(event)
    }
    
    // 3. Check Modifiers & KeyCode
    let flags = event.flags
    var modifierMatch = false
    
    // Enforce exclusive modifier (e.g. if Command is set, Ctrl shouldn't be pressed)
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
        // MATCH DETECTED!
        
        // FIX: If the app is ALREADY active, do NOT swallow the event.
        // Pass it through so the Local Event Monitor in the View can handle it (reset focus, clear form).
        if NSApp.isActive {
            return Unmanaged.passUnretained(event)
        }
        
        // Otherwise, wake the app and swallow the event
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
        return nil // Swallow the event
    }
    
    return Unmanaged.passUnretained(event)
}
