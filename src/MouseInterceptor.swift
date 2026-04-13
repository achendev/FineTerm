import Cocoa
import ApplicationServices
import Foundation

// Global variable to store start point
var lastMouseDownPoint: CGPoint = .zero
// Global variable for re-enabling tap
private var globalMouseEventTap: CFMachPort?

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // 0. Handle Tap Disabled (CRITICAL FIX)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = globalMouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: Mouse Tap re-enabled after timeout/user input.")
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    // Safety Net: Prevent infinite loops from our own synthesized CGEvents
    if event.getIntegerValueField(.eventSourceUserData) == magicEventSourceUserData {
        return Unmanaged.passUnretained(event)
    }
    
    let frontApp = NSWorkspace.shared.frontmostApplication
    let frontAppID = frontApp?.bundleIdentifier ?? ""
    
    // 1. Process PC Mode Rules for Mouse Buttons
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
        let wasSwallowed = PCModeProcessor.shared.process(type: effectiveType, keyCode: vk, flags: event.flags, event: event, frontAppID: frontAppID)
        if wasSwallowed {
            return nil
        }
    }
    
    let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
    
    // Check if Terminal is active (frontmost)
    guard frontAppID == target else {
        return Unmanaged.passUnretained(event)
    }
    
    let isDebug = UserDefaults.standard.bool(forKey: "debugMode")
    
    // [001] Tahoe Compatibility Fix: Use AX API for Hit-Testing
    // Replaced geometric CGWindowList check with Accessibility Hit-Test
    func isClickInTerminalWindow(_ point: CGPoint) -> Bool {
        // 1. Get Terminal PID
        guard let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == target }) else {
            return false
        }
        let terminalPID = terminalApp.processIdentifier
        
        // 2. Ask Accessibility API what is under the mouse
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        
        // AX coordinates match global screen coordinates (CGEvent)
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        
        guard error == .success, let targetElement = element else {
            if isDebug { print("DEBUG: AX Hit-Test failed or found nothing.") }
            return false
        }

        // 3. Check owner PID of the element found
        var elementPID: pid_t = 0
        let pidError = AXUIElementGetPid(targetElement, &elementPID)
        
        if pidError == .success && elementPID == terminalPID {
            return true
        } else {
            if isDebug { 
                print("DEBUG: Click blocked. Owner PID: \(elementPID) != Terminal PID: \(terminalPID)") 
            }
            return false
        }
    }

    // 2. Handle Right Click -> Paste (Cmd+V)
    if type == .rightMouseDown {
        if UserDefaults.standard.bool(forKey: "pasteOnRightClick") {
            // Only paste if click is strictly on a Terminal window
            if !isClickInTerminalWindow(event.location) {
                if isDebug { print("DEBUG: Right click outside/obscured, ignoring.") }
                return Unmanaged.passUnretained(event)
            }
            
            if isDebug { print("DEBUG: Right Click detected. Pasting...") }
            
            let source = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 9 // 'v'
            
            if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
               let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                
                cmdDown.flags = .maskCommand
                cmdUp.flags = .maskCommand
                
                cmdDown.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                cmdUp.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                
                cmdDown.post(tap: .cghidEventTap)
                cmdUp.post(tap: .cghidEventTap)
            }
            return nil // Swallow the right click
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 3. Track Mouse Down
    if type == .leftMouseDown {
        if isClickInTerminalWindow(event.location) {
            lastMouseDownPoint = event.location
        } else {
            lastMouseDownPoint = .zero
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 4. Handle Left Mouse Up -> Copy (Cmd+C)
    if type == .leftMouseUp {
        if !UserDefaults.standard.bool(forKey: "copyOnSelect") {
             return Unmanaged.passUnretained(event)
        }
        
        // Note: We use the decision made at MouseDown to determine if this is a valid selection
        if lastMouseDownPoint == .zero {
            return Unmanaged.passUnretained(event)
        }

        let currentPoint = event.location
        let dist = hypot(currentPoint.x - lastMouseDownPoint.x, currentPoint.y - lastMouseDownPoint.y)
        let clickCount = event.getIntegerValueField(.mouseEventClickState)
        // Detect Shift key for extended selection
        let isShiftDown = event.flags.contains(.maskShift)
        
        // Reset lastMouseDownPoint to avoid stale state
        lastMouseDownPoint = .zero
        
        // Trigger Copy if:
        // 1. Dragged > 5px
        // 2. Double/Triple Click (clickCount >= 2)
        // 3. Shift is held down (Shift+Click extends selection)
        if dist > 5.0 || clickCount >= 2 || isShiftDown {
            
            if isDebug {
                print("DEBUG: Selection Detected (Drag: \(Int(dist))px, Clicks: \(clickCount), Shift: \(isShiftDown)). Queuing Copy...")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target {
                    
                    let source = CGEventSource(stateID: .hidSystemState)
                    let cKey: CGKeyCode = 8 // 'c'
                    
                    if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
                       let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false) {
                        
                        cmdDown.flags = .maskCommand
                        cmdUp.flags = .maskCommand
                        
                        cmdDown.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        cmdUp.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        
                        cmdDown.post(tap: .cghidEventTap)
                        cmdUp.post(tap: .cghidEventTap)
                        
                        if UserDefaults.standard.bool(forKey: "debugMode") {
                            print("DEBUG: Cmd+C sent.")
                        }
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
        // Listen for Down, Up, and Right/Other Clicks
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | 
                        (1 << CGEventType.leftMouseUp.rawValue) | 
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.otherMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseUp.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("FATAL ERROR: Failed to create Event Tap. Check Accessibility Permissions.")
            return
        }

        self.eventTap = tap
        globalMouseEventTap = tap
        
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let rls = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("Mouse Hook Active.")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let rls = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, .commonModes)
            }
        }
        globalMouseEventTap = nil
    }
}