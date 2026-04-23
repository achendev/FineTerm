import Cocoa
import ApplicationServices
import Foundation

var lastMouseDownPoint: CGPoint = .zero
private var globalMouseEventTap: CFMachPort?

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout {
        if let tap = globalMouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    } else if type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    
    if event.getIntegerValueField(CGEventField.eventSourceUserData) == magicEventSourceUserData {
        return Unmanaged.passUnretained(event)
    }
    
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        SecureInputMonitor.shared.triggerActiveCheck()
    }
    
    let getFrontAppID: () -> String = {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
    
    var virtualKeyCode: Int64? = nil
    var isMousePress: Bool? = nil

    switch type {
    case .leftMouseDown: virtualKeyCode = 2001; isMousePress = true
    case .leftMouseUp: virtualKeyCode = 2001; isMousePress = false
    case .rightMouseDown: virtualKeyCode = 2002; isMousePress = true
    case .rightMouseUp: virtualKeyCode = 2002; isMousePress = false
    case .otherMouseDown: virtualKeyCode = 2003; isMousePress = true
    case .otherMouseUp: virtualKeyCode = 2003; isMousePress = false
    default: break
    }

    if let vk = virtualKeyCode, let press = isMousePress {
        let effectiveType: CGEventType = press ? .keyDown : .keyUp
        let wasSwallowed = PCModeProcessor.shared.process(type: effectiveType, keyCode: vk, flags: event.flags, event: event, getFrontAppID: getFrontAppID)
        if wasSwallowed {
            return nil
        }
    }
    
    let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
    let frontAppID = getFrontAppID()
    
    guard frontAppID == target else {
        return Unmanaged.passUnretained(event)
    }
    
    func isClickInTerminalWindow(_ point: CGPoint) -> Bool {
        guard let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == target }) else {
            return false
        }
        let terminalPID = terminalApp.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard error == .success, let targetElement = element else {
            return false
        }

        var elementPID: pid_t = 0
        let pidError = AXUIElementGetPid(targetElement, &elementPID)
        return pidError == .success && elementPID == terminalPID
    }

    if type == .rightMouseDown {
        if UserDefaults.standard.bool(forKey: "pasteOnRightClick") {
            if !isClickInTerminalWindow(event.location) { return Unmanaged.passUnretained(event) }
            
            let source = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 9 
            
            if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
               let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                cmdDown.flags = .maskCommand
                cmdUp.flags = .maskCommand
                cmdDown.setIntegerValueField(CGEventField.eventSourceUserData, value: magicEventSourceUserData)
                cmdUp.setIntegerValueField(CGEventField.eventSourceUserData, value: magicEventSourceUserData)
                cmdDown.post(tap: CGEventTapLocation.cghidEventTap)
                cmdUp.post(tap: CGEventTapLocation.cghidEventTap)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    
    if type == .leftMouseDown {
        if isClickInTerminalWindow(event.location) { lastMouseDownPoint = event.location } else { lastMouseDownPoint = .zero }
        return Unmanaged.passUnretained(event)
    }
    
    if type == .leftMouseUp {
        if !UserDefaults.standard.bool(forKey: "copyOnSelect") { return Unmanaged.passUnretained(event) }
        if lastMouseDownPoint == .zero { return Unmanaged.passUnretained(event) }

        let currentPoint = event.location
        let dist = hypot(currentPoint.x - lastMouseDownPoint.x, currentPoint.y - lastMouseDownPoint.y)
        let clickCount = event.getIntegerValueField(.mouseEventClickState)
        let isShiftDown = event.flags.contains(.maskShift)
        
        lastMouseDownPoint = .zero
        
        if dist > 5.0 || clickCount >= 2 || isShiftDown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target {
                    let source = CGEventSource(stateID: .hidSystemState)
                    let cKey: CGKeyCode = 8 
                    if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
                       let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false) {
                        cmdDown.flags = .maskCommand
                        cmdUp.flags = .maskCommand
                        cmdDown.setIntegerValueField(CGEventField.eventSourceUserData, value: magicEventSourceUserData)
                        cmdUp.setIntegerValueField(CGEventField.eventSourceUserData, value: magicEventSourceUserData)
                        cmdDown.post(tap: CGEventTapLocation.cghidEventTap)
                        cmdUp.post(tap: CGEventTapLocation.cghidEventTap)
                    }
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
    return Unmanaged.passUnretained(event)
}

class MouseInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    func start() {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        var mask: UInt64 = 0
        for t in types { mask |= (UInt64(1) << t.rawValue) }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: eventTapCallback, userInfo: nil
        ) else { return }

        self.eventTap = tap
        globalMouseEventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let rls = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let rls = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, .commonModes) }
        }
        globalMouseEventTap = nil
    }
}