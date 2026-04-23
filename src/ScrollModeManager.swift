import Cocoa
import CoreGraphics

private var globalScrollMovementTap: CFMachPort?

func scrollMovementCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return autoreleasepool {
        if type == .tapDisabledByTimeout {
            if ScrollModeManager.shared.isActive, let tap = globalScrollMovementTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        } else if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        
        if !ScrollModeManager.shared.isActive {
            return Unmanaged.passUnretained(event)
        }
        
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            let deltaY = Double(event.getIntegerValueField(.mouseEventDeltaY))
            let deltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
            ScrollModeManager.shared.processMovement(deltaX: deltaX, deltaY: deltaY)
            return nil 
        }
        return Unmanaged.passUnretained(event)
    }
}

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
    
    private var lastEventTime: TimeInterval = 0
    private var velocityY: Double = 0
    private var velocityX: Double = 0
    private var inertiaTimer: Timer?
    private var flingDetectTimer: Timer?
    
    private var accumulatedScrollDistance: Double = 0
    var hasScrolledSinceActive = false
    
    private var isScrollPhaseActive = false
    private var isMomentumPhaseActive = false
    
    private func setupTapIfNeeded() {
        if globalScrollMovementTap != nil { return }
        
        let mask: UInt64 = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: scrollMovementCallback,
            userInfo: nil
        ) else { return }
        
        globalScrollMovementTap = tap
        let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
    }
    
    var isActive: Bool {
        get { return _isActive }
        set {
            if _isActive != newValue {
                _isActive = newValue
                if newValue {
                    setupTapIfNeeded()
                    if let tap = globalScrollMovementTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    syncTargetModifierState(clear: true)
                    stopInertia()
                    
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
                    if let tap = globalScrollMovementTap { CGEvent.tapEnable(tap: tap, enable: false) }
                    syncTargetModifierState(clear: false)
                    flingDetectTimer?.invalidate()
                    startInertia()
                }
            }
        }
    }
    
    private func syncTargetModifierState(clear: Bool) {
        let source = CGEventSource(stateID: .privateState)
        let targetFlags = clear ? CGEventFlags() : CGEventSource.flagsState(.hidSystemState)
        let modifierKeys: [CGKeyCode] = [56, 59, 58, 55]
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
        stopInertia()
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastEventTime
        lastEventTime = now
        
        accumulatedScrollDistance += hypot(deltaX, deltaY)
        if accumulatedScrollDistance > 5.0 { hasScrolledSinceActive = true }
        
        CGWarpMouseCursorPosition(anchorPoint)
        
        if dt > 0 && dt < 0.1 {
            let instVelY = deltaY / dt
            let instVelX = deltaX / dt
            velocityY = (velocityY * 0.4) + (instVelY * 0.6)
            velocityX = (velocityX * 0.4) + (instVelX * 0.6)
        } else {
            velocityY = 0
            velocityX = 0
        }
        
        if !isScrollPhaseActive {
            emitScroll(dx: deltaX, dy: deltaY, phase: .began, momentumPhase: nil)
            isScrollPhaseActive = true
        } else {
            emitScroll(dx: deltaX, dy: deltaY, phase: .changed, momentumPhase: nil)
        }
        
        flingDetectTimer?.invalidate()
        flingDetectTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.startInertia()
        }
        RunLoop.main.add(flingDetectTimer!, forMode: .common)
    }
    
    private func startInertia() {
        let speed = hypot(velocityX, velocityY)
        if speed < 150 {
            if isScrollPhaseActive {
                emitScroll(dx: 0, dy: 0, phase: .ended, momentumPhase: nil)
                isScrollPhaseActive = false
            }
            return 
        }
        if isScrollPhaseActive {
            emitScroll(dx: 0, dy: 0, phase: .ended, momentumPhase: nil)
            isScrollPhaseActive = false
        }
        
        var lastTime = ProcessInfo.processInfo.systemUptime
        isMomentumPhaseActive = true
        emitScroll(dx: 0, dy: 0, phase: nil, momentumPhase: .began)
        
        inertiaTimer?.invalidate()
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if hypot(self.velocityX, self.velocityY) < 10 {
                self.stopInertia()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = now - lastTime
            lastTime = now
            let dy = self.velocityY * dt
            let dx = self.velocityX * dt
            self.emitScroll(dx: dx, dy: dy, phase: nil, momentumPhase: .changed)
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
        if abs(dx) <= 0.05 && abs(dy) <= 0.05 && phase == nil && momentumPhase == nil { return }
        
        let mult: Double = 1.8
        let finalY = dy * mult
        let finalX = dx * mult
        let source = CGEventSource(stateID: .privateState)
        
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
            wheel1: Int32(finalY), wheel2: Int32(finalX), wheel3: 0
        ) {
            scrollEvent.flags = CGEventFlags()
            scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: finalY)
            scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: finalX)
            
            if let p = phase { scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: p.rawValue) }
            else { scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0) }
            
            if let mp = momentumPhase { scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: mp.rawValue) }
            else { scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0) }
            
            if _isActive { scrollEvent.location = self.anchorPoint }
            scrollEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }
}