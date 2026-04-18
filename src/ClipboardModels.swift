import Foundation

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