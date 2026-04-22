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
        userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {[weak self] _ in
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
        let isDebug = UserDefaults.standard.bool(forKey: "debugMode")
        if isDebug { print("DEBUG: [KeyboardCache] Refreshing internal rule cache...") }
        
        if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.customAppShortcuts),
           let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
            self.customShortcuts = shortcuts
        } else {
            self.customShortcuts = []
        }
        
        var newPCRules: [ParsedPCModeRule] = []
        if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.pcModeRules) {
            do {
                let rules = try JSONDecoder().decode([PCModeRule].self, from: data)
                
                for rule in rules where rule.isEnabled {
                    var parsedMappings: [ParsedKeyMap] = []
                    for map in rule.mappings {
                        let fromParsed = KeyboardParser.parseKeyString(map.from)
                        guard !fromParsed.key.isEmpty else { 
                            if isDebug { print("DEBUG: [KeyboardCache] ERROR: Skipping '\(map.from)' -> fromKey is empty") }
                            continue 
                        }
                        guard let fromCode = KeyboardParser.getKeyCode(for: fromParsed.key) else { 
                            if isDebug { print("DEBUG: [KeyboardCache] ERROR: Skipping '\(map.from)' -> Unknown KeyCode for '\(fromParsed.key)'") }
                            continue 
                        }
                        
                        var isShell = false
                        var shellCommand: String? = nil
                        var isFunc = false
                        var funcCommand: String? = nil
                        var isType = false
                        var typeText: String? = nil
                        var toActions: [ParsedToAction] = []
                        
                        if map.to.lowercased().hasPrefix("shell:") {
                            isShell = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 6)
                            shellCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                        } else if map.to.lowercased().hasPrefix("func:") {
                            isFunc = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 5)
                            funcCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                        } else if map.to.lowercased().hasPrefix("type:") {
                            isType = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 5)
                            let text = String(map.to[cmdStartIndex...])
                            typeText = text.hasPrefix(" ") ? String(text.dropFirst()) : text
                        } else {
                            // FIX: Using custom safe split function instead of simple .components(separatedBy: ",")
                            let parts = KeyboardParser.splitActions(map.to)
                            for part in parts {
                                let toParsed = KeyboardParser.parseKeyString(part)
                                guard !toParsed.key.isEmpty else { continue }
                                guard let code = KeyboardParser.getKeyCode(for: toParsed.key) else { continue }
                                toActions.append(ParsedToAction(keyCode: code, coreFlags: toParsed.coreFlags))
                            }
                            if toActions.isEmpty { 
                                if isDebug { print("DEBUG: [KeyboardCache] ERROR: Skipping '\(map.from)' -> Unable to parse 'to' field: '\(map.to)'") }
                                continue 
                            }
                        }
                        
                        if isDebug {
                            print("DEBUG: [KeyboardCache] Loaded successfully: '\(map.from)' (Code: \(fromCode), Flags: \(fromParsed.coreFlags.rawValue))")
                        }
                        
                        parsedMappings.append(ParsedKeyMap(
                            original: map, 
                            fromKeyCode: fromCode, 
                            fromCoreFlags: fromParsed.coreFlags, 
                            fromStrictFlags: fromParsed.strictFlags, 
                            isStrict: map.isStrict,
                            isShell: isShell,
                            shellCommand: shellCommand,
                            isFunc: isFunc,
                            funcCommand: funcCommand,
                            isType: isType,
                            typeText: typeText,
                            toActions: toActions
                        ))
                    }
                    
                    parsedMappings.sort { $0.fromCoreFlags.rawValue.nonzeroBitCount > $1.fromCoreFlags.rawValue.nonzeroBitCount }
                    newPCRules.append(ParsedPCModeRule(rule: rule, mappings: parsedMappings))
                }
            } catch {
                if isDebug { print("DEBUG: [KeyboardCache] CRITICAL ERROR decoding PCModeRules JSON: \(error)") }
            }
        }
        self.pcRules = newPCRules
        if isDebug { print("DEBUG: [KeyboardCache] Finished refreshing. Total Active PC Rule Groups loaded: \(self.pcRules.count)") }
        
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