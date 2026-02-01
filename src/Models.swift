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
}

// Data Wrapper for Internal Persistence
struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

// MARK: - Export/Import Models (User Friendly)
// These structs define the JSON format for Import/Export (No UUIDs)

struct ExportGroup: Codable {
    var name: String
    var isExpanded: Bool
}

struct ExportConnection: Codable {
    var name: String
    var command: String
    var group: String? // Optional Group Name
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
