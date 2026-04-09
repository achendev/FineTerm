import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants
struct AppColors {
    // Custom Color #0A3069 (Red: 10, Green: 48, Blue: 105)
    static let activeHighlight = Color(red: 10/255.0, green: 48/255.0, blue: 105/255.0)
}

// MARK: - Internal Data Models

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
    
    // Init for new items
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
    
    // Custom decoding to handle legacy JSON
    enum CodingKeys: String, CodingKey {
        case id, groupID, name, command, usePrefix, useSuffix, setTabName, lastUsed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        // Default to true if keys are missing
        usePrefix = try container.decodeIfPresent(Bool.self, forKey: .usePrefix) ?? true
        useSuffix = try container.decodeIfPresent(Bool.self, forKey: .useSuffix) ?? true
        setTabName = try container.decodeIfPresent(Bool.self, forKey: .setTabName) ?? true
        // Optional date
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

// Clipboard Model
enum ClipboardType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable {
    var id = UUID()
    var content: String // For images, this is the description (e.g. "Image 500x500")
    var timestamp: Date
    var type: ClipboardType = .text
    var thumbnailData: Data? = nil // For images
    
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
    
    // Backward compatibility for old JSON that lacked 'type' and 'thumbnailData'
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
    }
}

// Data Wrapper for Internal Persistence
struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

// MARK: - Export/Import Models (User Friendly)

struct ExportGroup: Codable {
    var name: String
}

struct ExportConnection: Codable {
    var name: String
    var command: String
    var group: String? // Optional Group Name
    var usePrefix: Bool? // Optional, default true
    var useSuffix: Bool? // Optional, default true
    var setTabName: Bool? // Optional, default true
}

struct ExportData: Codable {
    var groups: [ExportGroup]
    var connections: [ExportConnection]
}

// Wrapper for Alert Identifiable state
struct GroupAlertItem: Identifiable {
    let id: UUID
}

// MARK: - File Export/Import Document
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