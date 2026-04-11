import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants
struct AppColors {
    // Custom Color #0A3069 (Red: 10, Green: 48, Blue: 105)
    static let activeHighlight = Color(red: 10/255.0, green: 48/255.0, blue: 105/255.0)
}

// MARK: - Internal Data Models

struct CustomAppShortcut: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var modifier: String
    var modifier2: String?
    var bundleIDs: [String]
    var isEnabled: Bool = true
    
    init(id: UUID = UUID(), key: String, modifier: String, modifier2: String? = nil, bundleIDs: [String], isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.modifier = modifier
        self.modifier2 = modifier2
        self.bundleIDs = bundleIDs
        self.isEnabled = isEnabled
    }
    
    enum CodingKeys: String, CodingKey {
        case id, key, modifier, modifier2, bundleIDs, bundleID, isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try container.decode(String.self, forKey: .key)
        modifier = try container.decode(String.self, forKey: .modifier)
        modifier2 = try container.decodeIfPresent(String.self, forKey: .modifier2)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        
        // Backward compatibility: Handle both new array format and old single string format
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
        try container.encode(key, forKey: .key)
        try container.encode(modifier, forKey: .modifier)
        try container.encodeIfPresent(modifier2, forKey: .modifier2)
        try container.encode(bundleIDs, forKey: .bundleIDs)
        try container.encode(isEnabled, forKey: .isEnabled)
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
    var lastUsed: Date? // Timestamp for sorting
    
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
    
    enum CodingKeys: String, CodingKey {
        case id, groupID, name, command, usePrefix, useSuffix, setTabName, lastUsed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        usePrefix = try container.decodeIfPresent(Bool.self, forKey: .usePrefix) ?? true
        useSuffix = try container.decodeIfPresent(Bool.self, forKey: .useSuffix) ?? true
        setTabName = try container.decodeIfPresent(Bool.self, forKey: .setTabName) ?? true
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(groupID, forKey: .groupID)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encode(usePrefix, forKey: .usePrefix)
        try container.encode(useSuffix, forKey: .useSuffix)
        try container.encode(setTabName, forKey: .setTabName)
        try container.encode(lastUsed, forKey: .lastUsed)
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
    
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, type, thumbnailData
    }
    
    init(id: UUID = UUID(), content: String, timestamp: Date, type: ClipboardType = .text, thumbnailData: Data? = nil) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.type = type
        self.thumbnailData = thumbnailData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
    }
}

struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

// MARK: - Export/Import Models

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
    static var readableContentTypes: [UTType] {[.json] }

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