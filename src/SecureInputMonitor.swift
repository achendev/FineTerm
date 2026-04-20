import Cocoa
import Carbon

class SecureInputMonitor {
    static let shared = SecureInputMonitor()
    private var timer: Timer?
    private var lastState: Bool = false
    
    func start() {
        if UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine) == 2 {
            forceSync()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ForceSecureInputSync"), object: nil, queue: .main) { [weak self] _ in
            self?.forceSync()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            guard UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine) == 2 else { return }
            
            let currentState = IsSecureEventInputEnabled()
            if currentState != self.lastState {
                self.lastState = currentState
                self.updateKarabiner(secure: currentState)
                
                if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
                    print("DEBUG: [SecureInputMonitor] State changed to: \(currentState)")
                }
            }
        }
    }
    
    @objc func forceSync() {
        let currentState = IsSecureEventInputEnabled()
        self.lastState = currentState
        self.updateKarabiner(secure: currentState)
    }
    
    private func updateKarabiner(secure: Bool) {
        let value = secure ? 1 : 0
        let path = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = path
            task.arguments = ["--set-variables", "{\"fineterm_secure_input\": \(value)}"]
            try? task.run()
        }
    }
}