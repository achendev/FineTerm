import SwiftUI
import Combine
import Cocoa

struct ClipboardStats {
    let totalItems: Int
    let imageCount: Int
    let textBlobCount: Int
    let historyDiskSizeBytes: Int64
    let blobsDiskSizeBytes: Int64
    let imageContentSizeBytes: Int64
    let textBlobContentSizeBytes: Int64
}

class ClipboardStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var blobs: [UUID: String] = [:]
    
    private let fileURL: URL
    private let blobsURL: URL
    
    private var timer: Timer?
    private var lastChangeCount: Int
    
    private let processingQueue = DispatchQueue(label: "com.fineterm.clipboard.processing", qos: .userInitiated)
    private let saveQueue = DispatchQueue(label: "com.fineterm.clipboard.save", qos: .utility)
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.FineTerm"
        let appDir = appSupport.appendingPathComponent(bundleID)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        fileURL = appDir.appendingPathComponent("clipboard_history.enc")
        blobsURL = appDir.appendingPathComponent("clipboard_blobs.enc")
        lastChangeCount = NSPasteboard.general.changeCount
        
        let loaded = ClipboardCrypto.load(fileURL: fileURL, blobsURL: blobsURL, as: ClipboardItem.self)
        self.history = loaded.history
        self.blobs = loaded.blobs
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkClipboard() }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                processAndAdd(image: image)
            } else if let newString = pb.string(forType: .string) {
                if !newString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    processAndAdd(content: newString)
                }
            }
        }
    }
    
    private func processAndAdd(image: NSImage) {
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
            
            let item = ClipboardItem(id: UUID(), content: "Image \(Int(image.size.width))x\(Int(image.size.height))", timestamp: Date(), type: .image, thumbnailData: thumbData)
            DispatchQueue.main.async { self.insertItem(item, blob: fullBlob) }
        }
    }
    
    private func processAndAdd(content: String) {
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
            
            let item = ClipboardItem(content: displayContent, timestamp: Date())
            DispatchQueue.main.async { self.insertItem(item, blob: fullContent) }
        }
    }
    
    private func insertItem(_ item: ClipboardItem, blob: String?) {
        if item.type == .text, let first = history.first, first.type == .text {
            if let newBlob = blob { if let existingBlob = blobs[first.id], existingBlob == newBlob { return } }
            else { if first.content == item.content { return } }
        }
        history.insert(item, at: 0)
        if let b = blob { blobs[item.id] = b }
        pruneHistory()
        save()
    }
    
    private func pruneHistory() {
        let globalLimit = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardHistorySize))
        let imageLimit = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardMaxImages))
        
        let currentImages = history.filter { $0.type == .image }
        if currentImages.count > imageLimit {
            let idsToRemove = Set(currentImages.suffix(currentImages.count - imageLimit).map { $0.id })
            history.removeAll { idsToRemove.contains($0.id) }
            for id in idsToRemove { blobs.removeValue(forKey: id) }
        }
        
        if history.count > globalLimit {
            let removedItems = history.suffix(from: globalLimit)
            for removed in removedItems { blobs.removeValue(forKey: removed.id) }
            history = Array(history.prefix(globalLimit))
        }
    }
    
    func delete(id: UUID) { history.removeAll { $0.id == id }; blobs.removeValue(forKey: id); save() }
    func clear() { history.removeAll(); blobs.removeAll(); save() }
    func getFullContent(for item: ClipboardItem) -> String { return blobs[item.id] ?? item.content }
    
    func removeDuplicates() {
        let historySnapshot = self.history
        let blobsSnapshot = self.blobs
        
        processingQueue.async {[weak self] in
            guard let self = self else { return }
            var seenContent = Set<String>()
            var idsToRemove: Set<UUID> = []
            
            for item in historySnapshot {
                let identifier: String
                if item.type == .text {
                    identifier = blobsSnapshot[item.id] ?? item.content
                } else {
                    identifier = blobsSnapshot[item.id] ?? item.thumbnailData?.base64EncodedString() ?? UUID().uuidString
                }
                if seenContent.contains(identifier) { idsToRemove.insert(item.id) } else { seenContent.insert(identifier) }
            }
            if !idsToRemove.isEmpty {
                DispatchQueue.main.async {
                    self.history.removeAll { idsToRemove.contains($0.id) }
                    for id in idsToRemove { self.blobs.removeValue(forKey: id) }
                    self.save()
                }
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
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
    
    func getStats() -> ClipboardStats {
        let historySize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let blobsSize = (try? FileManager.default.attributesOfItem(atPath: blobsURL.path)[.size] as? Int64) ?? 0
        var imgCount = 0, txtBlobCount = 0, imgBytes: Int64 = 0, txtBlobBytes: Int64 = 0
        
        for item in history {
            if item.type == .image {
                imgCount += 1
                if let thumb = item.thumbnailData { imgBytes += Int64(thumb.count) }
                if let blob = blobs[item.id] { imgBytes += Int64(blob.utf8.count) }
            } else {
                if let blob = blobs[item.id] { txtBlobCount += 1; txtBlobBytes += Int64(blob.utf8.count) }
            }
        }
        return ClipboardStats(totalItems: history.count, imageCount: imgCount, textBlobCount: txtBlobCount, historyDiskSizeBytes: historySize, blobsDiskSizeBytes: blobsSize, imageContentSizeBytes: imgBytes, textBlobContentSizeBytes: txtBlobBytes)
    }
    
    private func save() {
        let historySnapshot = self.history
        let blobsSnapshot = self.blobs
        let fURL = self.fileURL
        let bURL = self.blobsURL
        saveQueue.async { ClipboardCrypto.save(history: historySnapshot, blobs: blobsSnapshot, fileURL: fURL, blobsURL: bURL) }
    }
}