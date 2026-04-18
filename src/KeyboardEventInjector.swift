import Cocoa

struct KeyboardEventInjector {
    
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
}