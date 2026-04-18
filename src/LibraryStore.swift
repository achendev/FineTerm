import SwiftUI
import Combine
import Cocoa

struct LibraryStats {
    let totalItems: Int
    let imageCount: Int
    let textBlobCount: Int
    let historyDiskSizeBytes: Int64
    let blobsDiskSizeBytes: Int64
    let imageContentSizeBytes: Int64
    let textBlobContentSizeBytes: Int64
}

class LibraryStore: ObservableObject {
    @Published var items: [LibraryItem] = []
    private var blobs: [UUID: String] = [:]
    
    private let fileURL: URL
    private let blobsURL: URL
    
    private let processingQueue = DispatchQueue(label: "com.fineterm.library.processing", qos: .userInitiated)
    private let saveQueue = DispatchQueue(label: "com.fineterm.library.save", qos: .utility)
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.FineTerm"
        let appDir = appSupport.appendingPathComponent(bundleID)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        fileURL = appDir.appendingPathComponent("library_items.enc")
        blobsURL = appDir.appendingPathComponent("library_blobs.enc")
        
        let loaded = ClipboardCrypto.load(fileURL: fileURL, blobsURL: blobsURL, as: LibraryItem.self)
        self.items = loaded.history
        self.blobs = loaded.blobs
    }
    
    func add(title: String, content: String) {
        let fastLimitKB = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardItemSizeLimitKB))
        let slowLimitMB = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardLargeItemSizeLimitMB))
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let fastLimitBytes = fastLimitKB * 1024
            let slowLimitBytes = slowLimitMB * 1024 * 1024
            var displayContent = content
            var fullContent: String? = nil
            
            if content.utf8.count > fastLimitBytes {
                displayContent = ClipboardProcessor.truncate(string: content, limitBytes: fastLimitBytes)
                fullContent = content.utf8.count <= slowLimitBytes ? content : ClipboardProcessor.truncate(string: content, limitBytes: slowLimitBytes)
            }
            
            let item = LibraryItem(title: title, content: displayContent, timestamp: Date(), type: .text)
            DispatchQueue.main.async { self.insertItem(item, blob: fullContent) }
        }
    }
    
    func add(title: String, image: NSImage) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let thumbnail = ClipboardProcessor.resize(image: image, to: NSSize(width: 300, height: 300))
            var thumbData = thumbnail.tiffRepresentation
            if let tiff = thumbData, let bitmap = NSBitmapImageRep(data: tiff) {
                if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) { thumbData = jpeg }
            }
            
            var fullBlob: String? = nil
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                fullBlob = pngData.base64EncodedString()
            }
            
            let item = LibraryItem(title: title, content: "Image \(Int(image.size.width))x\(Int(image.size.height))", timestamp: Date(), type: .image, thumbnailData: thumbData)
            DispatchQueue.main.async { self.insertItem(item, blob: fullBlob) }
        }
    }
    
    private func insertItem(_ item: LibraryItem, blob: String?) {
        items.insert(item, at: 0)
        if let b = blob { blobs[item.id] = b }
        save()
    }
    
    func delete(id: UUID) { items.removeAll { $0.id == id }; blobs.removeValue(forKey: id); save() }
    func clear() { items.removeAll(); blobs.removeAll(); save() }
    func getFullContent(for item: LibraryItem) -> String { return blobs[item.id] ?? item.content }
    
    func copyToClipboard(item: LibraryItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.type == .image {
            if let base64 = blobs[item.id], let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        } else {
            pb.setString(blobs[item.id] ?? item.content, forType: .string)
        }
    }
    
    func getStats() -> LibraryStats {
        let historySize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let blobsSize = (try? FileManager.default.attributesOfItem(atPath: blobsURL.path)[.size] as? Int64) ?? 0
        var imgCount = 0, txtBlobCount = 0, imgBytes: Int64 = 0, txtBlobBytes: Int64 = 0
        
        for item in items {
            if item.type == .image {
                imgCount += 1
                if let thumb = item.thumbnailData { imgBytes += Int64(thumb.count) }
                if let blob = blobs[item.id] { imgBytes += Int64(blob.utf8.count) }
            } else {
                if let blob = blobs[item.id] { txtBlobCount += 1; txtBlobBytes += Int64(blob.utf8.count) }
            }
        }
        return LibraryStats(totalItems: items.count, imageCount: imgCount, textBlobCount: txtBlobCount, historyDiskSizeBytes: historySize, blobsDiskSizeBytes: blobsSize, imageContentSizeBytes: imgBytes, textBlobContentSizeBytes: txtBlobBytes)
    }
    
    private func save() {
        let itemsSnapshot = self.items
        let blobsSnapshot = self.blobs
        let fURL = self.fileURL
        let bURL = self.blobsURL
        saveQueue.async { ClipboardCrypto.save(history: itemsSnapshot, blobs: blobsSnapshot, fileURL: fURL, blobsURL: bURL) }
    }
}