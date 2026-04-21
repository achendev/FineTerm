import Cocoa
import Carbon

class SecureInputMonitor {
    static let shared = SecureInputMonitor()
    
    private var timer: Timer?
    var isSecureInputEnabled = false
    
    func start() {
        stop()
        let engine = UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine)
        if engine != 2 { return }
        
        isSecureInputEnabled = IsSecureEventInputEnabled()
        setKarabinerVariable(isSecureInputEnabled ? 1 : 0)
        
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        // Reset state so Karabiner doesn't get stuck if we disable hybrid mode
        setKarabinerVariable(0)
    }
    
    func check() {
        let isEnabled = IsSecureEventInputEnabled()
        if isEnabled != isSecureInputEnabled {
            isSecureInputEnabled = isEnabled
            setKarabinerVariable(isEnabled ? 1 : 0)
            
            if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
                print("DEBUG: [SecureInputMonitor] Secure Input changed to: \(isEnabled)")
            }
        }
    }
    
    func triggerActiveCheck() {
        guard timer != nil else { return }
        
        // Check immediately on the main thread
        DispatchQueue.main.async {
            self.check()
        }
        // Check again after a small delay to catch UI/focus transitions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.check()
        }
    }
    
    private func setKarabinerVariable(_ value: Int) {
        // Run asynchronously to not block the main thread
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
            task.arguments = ["--set-variables", "{\"fineterm_secure_input\":\(value)}"]
            try? task.run()
        }
    }
}