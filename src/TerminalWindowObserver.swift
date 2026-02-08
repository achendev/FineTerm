import Cocoa
import ApplicationServices

class TerminalWindowObserver {
    private var observer: AXObserver?
    private var terminalAppElement: AXUIElement?
    private var onUpdate: () -> Void
    private var isObserving = false
    
    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
    }
    
    func start() {
        if isObserving { return }
        
        guard let termApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) else { return }
        
        let pid = termApp.processIdentifier
        terminalAppElement = AXUIElementCreateApplication(pid)
        
        var obs: AXObserver?
        
        // Define callback
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let this = Unmanaged<TerminalWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            this.handleNotification()
        }
        
        let error = AXObserverCreate(pid, callback, &obs)
        guard error == .success, let observer = obs else {
            // print("TerminalWindowObserver: Failed to create AXObserver (Error: \(error.rawValue))")
            return
        }
        
        self.observer = observer
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Notifications to watch
        let notifications = [
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification
        ]
        
        for notif in notifications {
            AXObserverAddNotification(observer, terminalAppElement!, notif as CFString, selfPtr)
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        isObserving = true
    }
    
    func stop() {
        guard isObserving, let observer = observer else { return }
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
        self.terminalAppElement = nil
        isObserving = false
    }
    
    private func handleNotification() {
        // Direct dispatch to main thread ensures smoothest response to drag events
        DispatchQueue.main.async {
            self.onUpdate()
        }
    }
}