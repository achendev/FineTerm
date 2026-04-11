import Cocoa

class AppFocusTracker {
    static let shared = AppFocusTracker()
    
    private var history: [String] = [] // Index 0 is the most recently activated
    private let lock = NSLock()
    
    func start() {
        seedHistory()
        
        // Listen for all app activation events globally
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    private func seedHistory() {
        // Build initial history using window server Z-order so it works immediately upon launch
        let options: CGWindowListOption = [.excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            var seen = Set<String>()
            for info in list {
                if let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                   let pid = info[kCGWindowOwnerPID as String] as? Int32,
                   let app = NSRunningApplication(processIdentifier: pid),
                   let bundleID = app.bundleIdentifier {
                    if !seen.contains(bundleID) {
                        history.append(bundleID)
                        seen.insert(bundleID)
                    }
                }
            }
        }
        
        // Append any other background/running apps that don't have active windows
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, !history.contains(bundleID) {
                history.append(bundleID)
            }
        }
    }
    
    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        lock.lock()
        // Move the activated app to the top of the history
        history.removeAll { $0 == bundleID }
        history.insert(bundleID, at: 0)
        
        // Keep memory footprint small
        if history.count > 200 {
            history.removeLast()
        }
        lock.unlock()
        
        if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
            print("DEBUG: FocusTracker registered activation -> \(bundleID)")
        }
    }
    
    func getMostRecent(from bundleIDs: [String]) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        // Return the first bundleID that appears in our recent history
        for historicalApp in history {
            if bundleIDs.contains(historicalApp) {
                return historicalApp
            }
        }
        
        return bundleIDs.first
    }
}