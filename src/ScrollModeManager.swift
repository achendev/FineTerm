import Cocoa
import CoreGraphics

enum ScrollPhase: Int64 {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
}

class ScrollModeManager {
    static let shared = ScrollModeManager()
    
    private var _isActive = false
    var anchorPoint: CGPoint = .zero
    
    // Physics & Momentum State
    private var lastEventTime: TimeInterval = 0
    private var velocityY: Double = 0
    private var velocityX: Double = 0
    private var inertiaTimer: Timer?
    private var flingDetectTimer: Timer?
    
    private var accumulatedScrollDistance: Double = 0
    var hasScrolledSinceActive = false
    
    private var isScrollPhaseActive = false
    private var isMomentumPhaseActive = false
    
    var isActive: Bool {
        get { return _isActive }
        set {
            if _isActive != newValue {
                _isActive = newValue
                if newValue {
                    // Activation: Lock anchor and reset physics
                    
                    // CRITICAL FIX: Terminal apps track modifier state internally.
                    // We must explicitly tell the focused app that all modifiers were released,
                    // otherwise it will apply its memory of the physical 'Shift' state to our virtual scrolls.
                    syncTargetModifierState(clear: true)
                    
                    stopInertia()
                    
                    // Failsafe end previous phase if it was somehow stuck
                    if isScrollPhaseActive {
                        emitScroll(dx: 0, dy: 0, phase: .ended, momentumPhase: nil)
                        isScrollPhaseActive = false
                    }
                    
                    if let event = CGEvent(source: nil) {
                        anchorPoint = event.location
                    }
                    velocityY = 0
                    velocityX = 0
                    lastEventTime = ProcessInfo.processInfo.systemUptime
                    accumulatedScrollDistance = 0
                    hasScrolledSinceActive = false
                } else {
                    // Deactivation: Modifier released.
                    
                    // Restore the actual physical modifier state to the focused app
                    syncTargetModifierState(clear: false)
                    
                    // If we were moving fast right before releasing, trigger the momentum fling.
                    flingDetectTimer?.invalidate()
                    startInertia()
                }
            }
        }
    }
    
    private func syncTargetModifierState(clear: Bool) {
        let source = CGEventSource(stateID: .privateState)
        // Fetch real hardware state if restoring, otherwise empty array
        let targetFlags = clear ? CGEventFlags() : CGEventSource.flagsState(.hidSystemState)
        
        // Firing flagsChanged for the major modifiers ensures the focused app 
        // recalculates its internal state mask and zeroes out the activation shortcut.
        let modifierKeys: [CGKeyCode] = [56, 59, 58, 55] // L-Shift, L-Ctrl, L-Opt, L-Cmd
        
        for key in modifierKeys {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                event.type = .flagsChanged
                event.flags = targetFlags
                event.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
    
    func processMovement(deltaX: Double, deltaY: Double) {
        // Cancel existing inertia since the user is actively moving the mouse again
        stopInertia()
        
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastEventTime
        lastEventTime = now
        
        accumulatedScrollDistance += hypot(deltaX, deltaY)
        if accumulatedScrollDistance > 5.0 {
            hasScrolledSinceActive = true
        }
        
        // 1. Forcefully lock the cursor to prevent drifting while active
        CGWarpMouseCursorPosition(anchorPoint)
        
        // 2. Calculate instantaneous velocity (pixels per second)
        // Low-pass filter to smooth out trackpad micro-stutters
        if dt > 0 && dt < 0.1 {
            let instVelY = deltaY / dt
            let instVelX = deltaX / dt
            velocityY = (velocityY * 0.4) + (instVelY * 0.6)
            velocityX = (velocityX * 0.4) + (instVelX * 0.6)
        } else {
            // First movement or long pause
            velocityY = 0
            velocityX = 0
        }
        
        // 3. Emit the active scroll event with proper macOS phases
        if !isScrollPhaseActive {
            emitScroll(dx: deltaX, dy: deltaY, phase: .began, momentumPhase: nil)
            isScrollPhaseActive = true
        } else {
            emitScroll(dx: deltaX, dy: deltaY, phase: .changed, momentumPhase: nil)
        }
        
        // 4. Restart the fling detector
        // If we don't receive any more movements for 50ms, it means the finger was lifted.
        // We will then check if the velocity was high enough to start inertia.
        flingDetectTimer?.invalidate()
        flingDetectTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.startInertia()
        }
        // Attach to common modes so it fires reliably during UI events
        RunLoop.main.add(flingDetectTimer!, forMode: .common)
    }
    
    private func startInertia() {
        let speed = hypot(velocityX, velocityY)
        
        // Only fling if the user was moving fast enough when they released/lifted
        if speed < 150 {
            // If speed is too low, we just end the scroll phase and stop.
            if isScrollPhaseActive {
                emitScroll(dx: 0, dy: 0, phase: .ended, momentumPhase: nil)
                isScrollPhaseActive = false
            }
            return 
        }
        
        // Transition gracefully from Scroll Phase -> Momentum Phase
        if isScrollPhaseActive {
            emitScroll(dx: 0, dy: 0, phase: .ended, momentumPhase: nil)
            isScrollPhaseActive = false
        }
        
        var lastTime = ProcessInfo.processInfo.systemUptime
        
        isMomentumPhaseActive = true
        emitScroll(dx: 0, dy: 0, phase: nil, momentumPhase: .began)
        
        // 60 FPS Physics Loop
        inertiaTimer?.invalidate()
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            // Stop if velocity dies naturally
            if hypot(self.velocityX, self.velocityY) < 10 {
                self.stopInertia()
                return
            }
            
            let now = ProcessInfo.processInfo.systemUptime
            let dt = now - lastTime
            lastTime = now
            
            // Calculate distance to scroll this frame
            let dy = self.velocityY * dt
            let dx = self.velocityX * dt
            
            self.emitScroll(dx: dx, dy: dy, phase: nil, momentumPhase: .changed)
            
            // Apply trackpad-like friction (deceleration)
            // 0.88 closely mimics standard macOS momentum physics
            self.velocityY *= 0.88
            self.velocityX *= 0.88
        }
        
        RunLoop.main.add(inertiaTimer!, forMode: .common)
    }
    
    private func stopInertia() {
        if isMomentumPhaseActive {
            emitScroll(dx: 0, dy: 0, phase: nil, momentumPhase: .ended)
            isMomentumPhaseActive = false
        }
        inertiaTimer?.invalidate()
        inertiaTimer = nil
    }
    
    private func emitScroll(dx: Double, dy: Double, phase: ScrollPhase?, momentumPhase: ScrollPhase?) {
        // Only ignore completely idle events without state changes
        if abs(dx) <= 0.05 && abs(dy) <= 0.05 && phase == nil && momentumPhase == nil { return }
        
        // Speed multiplier to match native trackpad sensitivity natively
        let mult: Double = 1.8
        let finalY = dy * mult
        let finalX = dx * mult
        
        // Use isolated .privateState to prevent global hardware modifiers from bleeding in
        let source = CGEventSource(stateID: .privateState)
        
        // Use standard `.pixel` event for smooth scrolling across the system
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(finalY),
            wheel2: Int32(finalX),
            wheel3: 0
        ) {
            // Strip modifiers attached to the scroll wheel packet
            scrollEvent.flags = CGEventFlags()
            
            // Explicitly mark as continuous trackpad-style scrolling
            scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            
            // These high-precision fields are REQUIRED for both:
            // 1. Smooth scrolling in Web Browsers (Chrome/Safari)
            // 2. Correct Tmux scroll accumulation in Terminals
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: finalY)
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: finalX)
            
            // Inform the macOS Window Server of the gesture state
            if let p = phase {
                scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: p.rawValue)
            } else {
                scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
            }
            
            if let mp = momentumPhase {
                scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: mp.rawValue)
            } else {
                scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            }
            
            // Force the event to happen perfectly on the targeted area ONLY if actively holding the shortcut.
            // During momentum (when released), overriding the location causes the OS to warp the cursor
            // back to the anchor point 60 times a second, causing the mouse to feel stuck.
            if _isActive {
                scrollEvent.location = self.anchorPoint
            }
            
            scrollEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            
            // Inject directly into the session to prevent WindowServer hardware merges
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }
}