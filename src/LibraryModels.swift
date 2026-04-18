import Foundation

struct LibraryItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var timestamp: Date
    var type: ClipboardType = .text
    var thumbnailData: Data? = nil
}