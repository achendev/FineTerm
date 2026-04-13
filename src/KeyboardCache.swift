import Foundation

class KeyboardCache {
    static let shared = KeyboardCache()
    
    var customShortcuts: [CustomAppShortcut] = []
    var pcRules: [ParsedPCModeRule] = []
    var nextGroupTriggers: [ShortcutTrigger] = []
    var prevGroupTriggers: [ShortcutTrigger] = []
    var toggleGroupTriggers: [ShortcutTrigger] = []
    
    private var userDefaultsObserver: NSObjectProtocol?
    
    func start() {
        refresh()
        userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func stop() {
        if let obs = userDefaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        userDefaultsObserver = nil
        customShortcuts.removeAll()
        pcRules.removeAll()
        nextGroupTriggers.removeAll()
        prevGroupTriggers.removeAll()
        toggleGroupTriggers.removeAll()
    }
    
    private func refresh() {
        if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.customAppShortcuts),
           let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
            self.customShortcuts = shortcuts
        } else {
            self.customShortcuts = []
        }
        
        var newPCRules: [ParsedPCModeRule] = []
        if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.pcModeRules),
           let rules = try? JSONDecoder().decode([PCModeRule].self, from: data) {
            
            for rule in rules where rule.isEnabled {
                var parsedMappings: [ParsedKeyMap] = []
                for map in rule.mappings {
                    let fromParsed = KeyboardParser.parseKeyString(map.from)
                    guard !fromParsed.key.isEmpty else { continue }
                    guard let fromCode = KeyboardParser.getKeyCode(for: fromParsed.key) else { continue }
                    
                    var isShell = false
                    var shellCommand: String? = nil
                    var toActions: [ParsedToAction] = []
                    
                    if map.to.lowercased().hasPrefix("shell:") {
                        isShell = true
                        let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 6)
                        shellCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                    } else {
                        let parts = map.to.components(separatedBy: ",")
                        for part in parts {
                            let toParsed = KeyboardParser.parseKeyString(part)
                            guard !toParsed.key.isEmpty else { continue }
                            guard let code = KeyboardParser.getKeyCode(for: toParsed.key) else { continue }
                            toActions.append(ParsedToAction(keyCode: code, coreFlags: toParsed.coreFlags))
                        }
                        if toActions.isEmpty { continue }
                    }
                    
                    parsedMappings.append(ParsedKeyMap(
                        original: map, 
                        fromKeyCode: fromCode, 
                        fromCoreFlags: fromParsed.coreFlags, 
                        fromStrictFlags: fromParsed.strictFlags, 
                        isShell: isShell,
                        shellCommand: shellCommand,
                        toActions: toActions
                    ))
                }
                
                // Sort by most specific modifiers first (e.g. Ctrl+Shift matches before Ctrl)
                parsedMappings.sort { $0.fromCoreFlags.rawValue.nonzeroBitCount > $1.fromCoreFlags.rawValue.nonzeroBitCount }
                newPCRules.append(ParsedPCModeRule(rule: rule, mappings: parsedMappings))
            }
        }
        self.pcRules = newPCRules
        
        self.nextGroupTriggers = loadTriggers(forKey: AppConfig.Keys.nextGroupTriggers, oldMod1: AppConfig.Keys.nextGroupModifier, oldMod2: AppConfig.Keys.nextGroupModifier2, oldKey: AppConfig.Keys.nextGroupKey, defaultKey: ".")
        self.prevGroupTriggers = loadTriggers(forKey: AppConfig.Keys.prevGroupTriggers, oldMod1: AppConfig.Keys.prevGroupModifier, oldMod2: AppConfig.Keys.prevGroupModifier2, oldKey: AppConfig.Keys.prevGroupKey, defaultKey: ",")
        self.toggleGroupTriggers = loadTriggers(forKey: AppConfig.Keys.toggleGroupTriggers, oldMod1: AppConfig.Keys.toggleGroupModifier, oldMod2: AppConfig.Keys.toggleGroupModifier2, oldKey: AppConfig.Keys.toggleGroupKey, defaultKey: "/")
    }
    
    private func loadTriggers(forKey key: String, oldMod1: String, oldMod2: String, oldKey: String, defaultKey: String) -> [ShortcutTrigger] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: data), !decoded.isEmpty {
            return decoded
        }
        let m1 = UserDefaults.standard.string(forKey: oldMod1) ?? "right control"
        let m2 = UserDefaults.standard.string(forKey: oldMod2) ?? "shift"
        let k = UserDefaults.standard.string(forKey: oldKey) ?? defaultKey
        return [ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
    }
}