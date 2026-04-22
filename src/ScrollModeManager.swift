import Cocoa
import CoreGraphics

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
    
    var isActive: Bool {
        get { return _isActive }
        set {
            if _isActive != newValue {
                _isActive = newValue
                if newValue {
                    // Activation: Lock anchor and reset physics
                    stopInertia()
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
                    // If we were moving fast right before releasing, trigger the momentum fling.
                    flingDetectTimer?.invalidate()
                    startInertia()
                }
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
        
        // 3. Emit the active scroll event
        emitScroll(dx: deltaX, dy: deltaY, isMomentum: false)
        
        // 4. Restart the fling detector
        // If we don't receive any more movements for 50ms, it means the finger was lifted.
        // We will then check if the velocity was high enough to start inertia.
        flingDetectTimer?.invalidate()
        flingDetectTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) {[weak self] _ in
            self?.startInertia()
        }
        // Attach to common modes so it fires reliably during UI events
        RunLoop.main.add(flingDetectTimer!, forMode: .common)
    }
    
    private func startInertia() {
        let speed = hypot(velocityX, velocityY)
        
        // Only fling if the user was moving fast enough when they released/lifted
        if speed < 150 { return }
        
        var lastTime = ProcessInfo.processInfo.systemUptime
        
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
            
            self.emitScroll(dx: dx, dy: dy, isMomentum: true)
            
            // Apply trackpad-like friction (deceleration)
            // 0.88 closely mimics standard macOS momentum physics
            self.velocityY *= 0.88
            self.velocityX *= 0.88
        }
        
        RunLoop.main.add(inertiaTimer!, forMode: .common)
    }
    
    private func stopInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
    }
    
    private func emitScroll(dx: Double, dy: Double, isMomentum: Bool) {
        guard abs(dx) > 0.05 || abs(dy) > 0.05 else { return }
        
        // Speed multiplier to match native trackpad sensitivity natively
        let mult: Double = 1.8
        let finalY = dy * mult
        let finalX = dx * mult
        
        // Use standard `.pixel` event for smooth scrolling across the system
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(finalY),
            wheel2: Int32(finalX),
            wheel3: 0
        ) {
            // These high-precision fields are REQUIRED for both:
            // 1. Smooth scrolling in Web Browsers (Chrome/Safari)
            // 2. Correct Tmux scroll accumulation in Terminals (Ghostty/iTerm2 translate this properly to ANSI ticks)
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: finalY)
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: finalX)
            
            // Flag as a momentum event if generated by the physics timer (allows apps to handle rubber-banding)
            if isMomentum {
                scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2) // 2 = Continuous
            }
            
            scrollEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            scrollEvent.post(tap: .cghidEventTap)
        }
    }
}