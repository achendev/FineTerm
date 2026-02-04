import Cocoa
import ApplicationServices
import Foundation

// Global variable to store start point
var lastMouseDownPoint: CGPoint = .zero

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // Check if Terminal is active (frontmost)
    // Exception: If global mode is enabled in future, this might need adjustment, 
    // but for now the requirement is "Terminal focused".
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          frontApp.bundleIdentifier == "com.apple.Terminal" else {
        return Unmanaged.passUnretained(event)
    }
    
    let isDebug = UserDefaults.standard.bool(forKey: "debugMode")
    
    // Robust Hit-Testing:
    // We determine if the click is actually ON the Terminal window, 
    // or if it's intercepted by something on top (like the Dock, Spotlight, or Notification Center).
    func isClickInTerminalWindow(_ point: CGPoint) -> Bool {
        // OptionOnScreenOnly: Lists all visible windows from front to back (Z-order).
        // We do NOT use .excludeDesktopElements because we WANT to see the Dock if it's there.
        let options: CGWindowListOption = [.optionOnScreenOnly]
        
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        for windowInfo in windowList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }
            
            let windowRect = CGRect(x: x, y: y, width: width, height: height)
            
            if windowRect.contains(point) {
                // We found the topmost visible window at this coordinate.
                
                // Check who owns it.
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String {
                    if ownerName == "Terminal" {
                        // The top window is Terminal -> It's a valid click.
                        return true
                    } else {
                        // The top window is something else (Dock, Finder, etc.) -> Ignore.
                        if isDebug { print("DEBUG: Click blocked by: \(ownerName)") }
                        return false
                    }
                }
                // If owner unknown, assume it's an obstruction.
                return false
            }
        }
        
        return false
    }

    // 1. Handle Right Click -> Paste (Cmd+V)
    if type == .rightMouseDown {
        // Check Setting
        if UserDefaults.standard.bool(forKey: "pasteOnRightClick") {
            // Only paste if click is strictly on a Terminal window (not obscured by Dock)
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
                
                cmdDown.post(tap: .cghidEventTap)
                cmdUp.post(tap: .cghidEventTap)
            }
            return nil // Swallow the right click
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 2. Track Mouse Down
    if type == .leftMouseDown {
        // Only track if click is actually in Terminal window
        if isClickInTerminalWindow(event.location) {
            lastMouseDownPoint = event.location
        } else {
            lastMouseDownPoint = .zero // Reset to prevent false triggers
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 3. Handle Left Mouse Up -> Copy (Cmd+C)
    if type == .leftMouseUp {
        // Check Setting
        if !UserDefaults.standard.bool(forKey: "copyOnSelect") {
             return Unmanaged.passUnretained(event)
        }
        
        // Only copy if release is in Terminal window
        if !isClickInTerminalWindow(event.location) {
            return Unmanaged.passUnretained(event)
        }
        
        // Skip if mouse down was outside Terminal (lastMouseDownPoint was reset)
        if lastMouseDownPoint == .zero {
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
            
            if isDebug {
                print("DEBUG: Selection Detected (Drag: \(Int(dist))px, Clicks: \(clickCount)). Queuing Copy...")
            }
            
            // Wait 0.01s (reduced from 0.25s) for Terminal to finalize the visual selection
            // This ensures it feels "instant" (10ms) but is reliably processed after selection logic.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
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
