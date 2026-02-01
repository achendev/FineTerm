import SwiftUI

// MARK: - Constants
struct AppColors {
    // Custom Color #0A3069 (Red: 10, Green: 48, Blue: 105)
    static let activeHighlight = Color(red: 10/255.0, green: 48/255.0, blue: 105/255.0)
}

// MARK: - Data Models

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

// Data Wrapper for JSON Persistence
struct StoreData: Codable {
    var groups: [ConnectionGroup]
    var connections: [Connection]
}

// Wrapper for Alert Identifiable state to avoid UUID extension warnings
struct GroupAlertItem: Identifiable {
    let id: UUID
}
