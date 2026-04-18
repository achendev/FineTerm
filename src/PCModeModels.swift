import Foundation

enum AppFilterMode: String, Codable, CaseIterable {
    case none = "All Apps"
    case include = "Include Only"
    case exclude = "Exclude"
}

struct KeyMap: Identifiable, Codable, Equatable {
    var id = UUID()
    var from: String
    var to: String
    
    enum CodingKeys: String, CodingKey {
        case id, from, to
        case fromKey, fromModifiers, toKey, toModifiers
    }
    
    init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        
        if let f = try? container.decode(String.self, forKey: .from),
           let t = try? container.decode(String.self, forKey: .to) {
            from = f
            to = t
        } else if let fKey = try? container.decode(String.self, forKey: .fromKey),
                  let fMods = try? container.decode([String].self, forKey: .fromModifiers),
                  let tKey = try? container.decode(String.self, forKey: .toKey),
                  let tMods = try? container.decode([String].self, forKey: .toModifiers) {
            let fromString = (fMods + [fKey]).joined(separator: " + ")
            let toString = (tMods + [tKey]).joined(separator: " + ")
            from = fromString
            to = toString
        } else {
            from = ""
            to = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
    }
}

struct PCModeRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var isEnabled: Bool = false
    var mappings: [KeyMap] = []
    var appFilterMode: AppFilterMode = .none
    var appBundleIDs: [String] = []
    
    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, mappings, appFilterMode, appBundleIDs
    }
    
    init(id: UUID = UUID(), name: String, isEnabled: Bool = false, mappings: [KeyMap] = [], appFilterMode: AppFilterMode = .none, appBundleIDs: [String] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.mappings = mappings
        self.appFilterMode = appFilterMode
        self.appBundleIDs = appBundleIDs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Rule"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        mappings = try container.decodeIfPresent([KeyMap].self, forKey: .mappings) ?? []
        appFilterMode = try container.decodeIfPresent(AppFilterMode.self, forKey: .appFilterMode) ?? .none
        appBundleIDs = try container.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
    }
}