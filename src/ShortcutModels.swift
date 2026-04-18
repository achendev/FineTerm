import SwiftUI

// MARK: - Constants
struct AppColors {
    static let activeHighlight = Color(red: 10/255.0, green: 48/255.0, blue: 105/255.0)
}

struct ShortcutTrigger: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var modifier: String
    var modifier2: String?
    
    init(id: UUID = UUID(), key: String, modifier: String, modifier2: String? = nil) {
        self.id = id
        self.key = key
        self.modifier = modifier
        self.modifier2 = modifier2
    }
}

struct CustomAppShortcut: Identifiable, Codable, Equatable {
    var id = UUID()
    var triggers: [ShortcutTrigger]
    var bundleIDs: [String]
    var isEnabled: Bool = true
    
    init(id: UUID = UUID(), triggers: [ShortcutTrigger], bundleIDs: [String], isEnabled: Bool = true) {
        self.id = id
        self.triggers = triggers
        self.bundleIDs = bundleIDs
        self.isEnabled = isEnabled
    }
    
    enum CodingKeys: String, CodingKey {
        case id, triggers, key, modifier, modifier2, bundleIDs, bundleID, isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        
        if let decodedTriggers = try? container.decode([ShortcutTrigger].self, forKey: .triggers) {
            triggers = decodedTriggers
        } else if let key = try? container.decode(String.self, forKey: .key),
                  let mod = try? container.decode(String.self, forKey: .modifier) {
            let mod2 = try? container.decodeIfPresent(String.self, forKey: .modifier2)
            triggers = [ShortcutTrigger(key: key, modifier: mod, modifier2: mod2)]
        } else {
            triggers = [ShortcutTrigger(key: "", modifier: "command")]
        }
        
        if let ids = try? container.decode([String].self, forKey: .bundleIDs) {
            bundleIDs = ids
        } else if let single = try? container.decode(String.self, forKey: .bundleID) {
            bundleIDs = [single]
        } else {
            bundleIDs = [""]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(triggers, forKey: .triggers)
        try container.encode(bundleIDs, forKey: .bundleIDs)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}