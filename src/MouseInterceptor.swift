import Cocoa
import ApplicationServices
import Foundation

// Global variable to store start point
var lastMouseDownPoint: CGPoint = .zero

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // Check if Terminal is active
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          frontApp.bundleIdentifier == "com.apple.Terminal" else {
        return Unmanaged.passUnretained(event)
    }

    // 1. Handle Right Click -> Paste (Cmd+V)
    if type == .rightMouseDown {
        // Check Setting
        if UserDefaults.standard.bool(forKey: "pasteOnRightClick") {
            print("DEBUG: Right Click detected. Pasting...")
            
            let source = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 9 // 'v'
            
            if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
               let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
                
                cmdDown.flags = .maskCommand
                cmdUp.flags = .maskCommand
                
                cmdDown.post(tap: .cghidEventTap)
                cmdUp.post(tap: .cghidEventTap)
            }
            return nil // Swallow the right click
        }
        // If disabled, let the event pass through normally
        return Unmanaged.passUnretained(event)
    }
    
    // 2. Track Mouse Down
    if type == .leftMouseDown {
        lastMouseDownPoint = event.location
        return Unmanaged.passUnretained(event)
    }
    
    // 3. Handle Left Mouse Up -> Copy (Cmd+C)
    if type == .leftMouseUp {
        // Check Setting
        if !UserDefaults.standard.bool(forKey: "copyOnSelect") {
             return Unmanaged.passUnretained(event)
        }

        let currentPoint = event.location
        // Calculate drag distance
        let dist = hypot(currentPoint.x - lastMouseDownPoint.x, currentPoint.y - lastMouseDownPoint.y)
        
        // Get Click Count (1 = single, 2 = double, 3 = triple)
        let clickCount = event.getIntegerValueField(.mouseEventClickState)
        
        // Trigger Copy if:
        // A) User dragged more than 5 pixels (Manual selection)
        // B) User Double-clicked (Word selection) or Triple-clicked (Line selection)
        if dist > 5.0 || clickCount >= 2 {
            
            print("DEBUG: Selection Detected (Drag: \(Int(dist))px, Clicks: \(clickCount)). Queuing Copy...")
            
            // Wait 0.25s for Terminal to finalize the visual selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // Ensure Terminal is still focused
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" {
                    
                    let source = CGEventSource(stateID: .hidSystemState)
                    let cKey: CGKeyCode = 8 // 'c'
                    
                    if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
                       let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false) {
                        
                        cmdDown.flags = .maskCommand
                        cmdUp.flags = .maskCommand
                        
                        cmdDown.post(tap: .cghidEventTap)
                        cmdUp.post(tap: .cghidEventTap)
                        print("DEBUG: Cmd+C sent.")
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
        // Listen for Down, Up, and Right Click
        let eventMask = (1 << CGEventType.leftMouseUp.rawValue) | 
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue)
        
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
    }
}
