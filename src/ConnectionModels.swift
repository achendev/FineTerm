import SwiftUI
import UniformTypeIdentifiers

struct ConnectionGroup: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isExpanded: Bool = true
    var parsingScript: String? = nil
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
    var isParsed: Bool? = false
    
    init(groupID: UUID? = nil, name: String, command: String, usePrefix: Bool = true, useSuffix: Bool = true, setTabName: Bool = true, lastUsed: Date? = nil, isParsed: Bool? = false) {
        self.id = UUID()
        self.groupID = groupID
        self.name = name
        self.command = command
        self.usePrefix = usePrefix
        self.useSuffix = useSuffix
        self.setTabName = setTabName
        self.lastUsed = lastUsed
        self.isParsed = isParsed
    }
}

struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

struct ExportGroup: Codable {
    var name: String
    var parsingScript: String?
}

struct ExportConnection: Codable {
    var name: String
    var command: String
    var group: String?
    var usePrefix: Bool?
    var useSuffix: Bool?
    var setTabName: Bool?
    var isParsed: Bool?
}

struct ExportData: Codable {
    var groups: [ExportGroup]
    var connections: [ExportConnection]
}

struct GroupAlertItem: Identifiable {
    let id: UUID
}

struct ParsingErrorAlert: Identifiable {
    let id = UUID()
    let message: String
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