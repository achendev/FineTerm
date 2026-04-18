import Cocoa

struct KeyboardEventInjector {
    
    private static let asciiToKeyCode: [Character: (code: CGKeyCode, shift: Bool)] = [
        "a": (0, false), "A": (0, true),
        "s": (1, false), "S": (1, true),
        "d": (2, false), "D": (2, true),
        "f": (3, false), "F": (3, true),
        "h": (4, false), "H": (4, true),
        "g": (5, false), "G": (5, true),
        "z": (6, false), "Z": (6, true),
        "x": (7, false), "X": (7, true),
        "c": (8, false), "C": (8, true),
        "v": (9, false), "V": (9, true),
        "b": (11, false), "B": (11, true),
        "q": (12, false), "Q": (12, true),
        "w": (13, false), "W": (13, true),
        "e": (14, false), "E": (14, true),
        "r": (15, false), "R": (15, true),
        "y": (16, false), "Y": (16, true),
        "t": (17, false), "T": (17, true),
        "1": (18, false), "!": (18, true),
        "2": (19, false), "@": (19, true),
        "3": (20, false), "#": (20, true),
        "4": (21, false), "$": (21, true),
        "6": (22, false), "^": (22, true),
        "5": (23, false), "%": (23, true),
        "=": (24, false), "+": (24, true),
        "9": (25, false), "(": (25, true),
        "7": (26, false), "&": (26, true),
        "-": (27, false), "_": (27, true),
        "8": (28, false), "*": (28, true),
        "0": (29, false), ")": (29, true),
        "]": (30, false), "}": (30, true),
        "o": (31, false), "O": (31, true),
        "u": (32, false), "U": (32, true),
        "[": (33, false), "{": (33, true),
        "i": (34, false), "I": (34, true),
        "p": (35, false), "P": (35, true),
        "l": (37, false), "L": (37, true),
        "j": (38, false), "J": (38, true),
        "'": (39, false), "\"": (39, true),
        "k": (40, false), "K": (40, true),
        ";": (41, false), ":": (41, true),
        "\\": (42, false), "|": (42, true),
        ",": (43, false), "<": (43, true),
        "/": (44, false), "?": (44, true),
        "n": (45, false), "N": (45, true),
        "m": (46, false), "M": (46, true),
        ".": (47, false), ">": (47, true),
        "`": (50, false), "~": (50, true),
        " ": (49, false),
        "\n": (36, false),
        "\t": (48, false)
    ]

    static func postMediaKeyEvent(mediaKey: Int32, isDown: Bool, flags: CGEventFlags) {
        let loc = NSPoint(x: 0, y: 0)
        let data1 = (Int(mediaKey) << 16) | (isDown ? 0xA00 : 0xB00)
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
        
        if let ev = NSEvent.otherEvent(
            with: .systemDefined,
            location: loc,
            modifierFlags: nsFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cg = ev.cgEvent {
            cg.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            cg.post(tap: .cghidEventTap)
        }
    }
    
    static func postMouseEvent(button: Int32, isDown: Bool) {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let loc = currentEvent.location
        
        let type: CGEventType
        let mouseButton: CGMouseButton
        
        switch button {
        case 1:
            type = isDown ? .leftMouseDown : .leftMouseUp
            mouseButton = .left
        case 2:
            type = isDown ? .rightMouseDown : .rightMouseUp
            mouseButton = .right
        case 3:
            type = isDown ? .otherMouseDown : .otherMouseUp
            mouseButton = .center
        default: return
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let mouseEvent = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: loc, mouseButton: mouseButton) {
            mouseEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            mouseEvent.post(tap: .cghidEventTap)
        }
    }
    
    static func injectInstantMacro(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            down.post(tap: .cghidEventTap)
        }
        usleep(1000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            up.post(tap: .cghidEventTap)
        }
    }
    
    static func typeText(_ text: String, delayMs: UInt32 = 50) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait 1 second before starting to type to ensure user has released physical modifier keys
            Thread.sleep(forTimeInterval: 1.0)
            
            let source = CGEventSource(stateID: .hidSystemState)
            let shiftKeyCode: CGKeyCode = 56 // Left Shift
            
            for char in text {
                let s = String(char)
                let utf16 = Array(s.utf16)
                
                let mapping = asciiToKeyCode[char]
                let keyCode = mapping?.code ?? 0
                let shift = mapping?.shift ?? false
                
                // 1. Send physical Shift Down if needed
                if shift {
                    if let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: true) {
                        shiftDown.flags = .maskShift
                        shiftDown.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        shiftDown.post(tap: .cghidEventTap)
                    }
                    usleep(5000) // VNC needs a moment to process modifier state
                }
                
                // 2. Send Character Down
                if let downEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                    downEvent.flags = shift ? .maskShift : CGEventFlags()
                    downEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    downEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                    downEvent.post(tap: .cghidEventTap)
                }
                
                usleep(5000) // Character Hold Time
                
                // 3. Send Character Up
                if let upEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                    upEvent.flags = shift ? .maskShift : CGEventFlags()
                    upEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    upEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                    upEvent.post(tap: .cghidEventTap)
                }
                
                // 4. Send physical Shift Up if needed
                if shift {
                    usleep(5000)
                    if let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: false) {
                        shiftUp.flags = CGEventFlags()
                        shiftUp.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        shiftUp.post(tap: .cghidEventTap)
                    }
                }
                
                // 5. Delay between separate symbols
                usleep(delayMs * 1000) 
            }
        }
    }
}