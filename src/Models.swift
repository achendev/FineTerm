import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants
struct AppColors {
    static let activeHighlight = Color(red: 10/255.0, green: 48/255.0, blue: 105/255.0)
}

// MARK: - Internal Data Models

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
            // Backward compatibility
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
    
    // Custom decoder guarantees that missing fields from older app versions won't cause the entire ruleset to crash and silently drop.
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

struct ConnectionGroup: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isExpanded: Bool = true
}

struct Connection: Identifiable, Codable {
    var id = UUID()
    var groupID: UUID? = nil
    var name: String
    var command: String
    var usePrefix: Bool
    var useSuffix: Bool
    var setTabName: Bool
    var lastUsed: Date?
    
    init(groupID: UUID? = nil, name: String, command: String, usePrefix: Bool = true, useSuffix: Bool = true, setTabName: Bool = true, lastUsed: Date? = nil) {
        self.id = UUID()
        self.groupID = groupID
        self.name = name
        self.command = command
        self.usePrefix = usePrefix
        self.useSuffix = useSuffix
        self.setTabName = setTabName
        self.lastUsed = lastUsed
    }
}

enum ClipboardType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable {
    var id = UUID()
    var content: String
    var timestamp: Date
    var type: ClipboardType = .text
    var thumbnailData: Data? = nil
}

struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

struct ExportGroup: Codable {
    var name: String
}

struct ExportConnection: Codable {
    var name: String
    var command: String
    var group: String?
    var usePrefix: Bool?
    var useSuffix: Bool?
    var setTabName: Bool?
}

struct ExportData: Codable {
    var groups: [ExportGroup]
    var connections: [ExportConnection]
}

struct GroupAlertItem: Identifiable {
    let id: UUID
}

struct ConnectionsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var exportData: ExportData

    init(exportData: ExportData) {
        self.exportData = exportData
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.exportData = try JSONDecoder().decode(ExportData.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(exportData)
        return FileWrapper(regularFileWithContents: data)
    }
}