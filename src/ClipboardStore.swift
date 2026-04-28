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
    
    private let fileURL: URL
    private let blobsURL: URL
    
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastWrittenChangeCount: Int = 0
    
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
        
        self.history = ClipboardCrypto.loadHistory(fileURL: fileURL, as: ClipboardItem.self)
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
            if currentCount == lastWrittenChangeCount { return }
            
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
        var isDuplicate = false
        if item.type == .text, let first = history.first, first.type == .text {
            if first.content == item.content { isDuplicate = true }
        }
        if isDuplicate { return }
        
        history.insert(item, at: 0)
        let idsToRemove = pruneHistory()
        
        let hSnapshot = self.history
        let fURL = self.fileURL
        let bURL = self.blobsURL
        let itemID = item.id
        
        saveQueue.async {
            var diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: bURL)
            if let b = blob { diskBlobs[itemID] = b }
            for id in idsToRemove { diskBlobs.removeValue(forKey: id) }
            
            ClipboardCrypto.saveHistory(history: hSnapshot, fileURL: fURL)
            ClipboardCrypto.saveBlobs(blobs: diskBlobs, blobsURL: bURL)
        }
    }
    
    private func pruneHistory() -> [UUID] {
        let globalLimit = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardHistorySize))
        let imageLimit = max(1, UserDefaults.standard.integer(forKey: AppConfig.Keys.clipboardMaxImages))
        
        var idsToRemove: [UUID] = []
        
        let currentImages = history.filter { $0.type == .image }
        if currentImages.count > imageLimit {
            let toRemove = currentImages.suffix(currentImages.count - imageLimit)
            idsToRemove.append(contentsOf: toRemove.map { $0.id })
            let removeSet = Set(idsToRemove)
            history.removeAll { removeSet.contains($0.id) }
        }
        
        if history.count > globalLimit {
            let toRemove = history.suffix(from: globalLimit)
            idsToRemove.append(contentsOf: toRemove.map { $0.id })
            history = Array(history.prefix(globalLimit))
        }
        
        return idsToRemove
    }
    
    func delete(id: UUID) { 
        history.removeAll { $0.id == id }
        let hSnapshot = self.history
        let fURL = self.fileURL
        let bURL = self.blobsURL
        
        saveQueue.async {
            var diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: bURL)
            diskBlobs.removeValue(forKey: id)
            ClipboardCrypto.saveHistory(history: hSnapshot, fileURL: fURL)
            ClipboardCrypto.saveBlobs(blobs: diskBlobs, blobsURL: bURL)
        }
    }
    
    func clear() { 
        history.removeAll()
        let fURL = self.fileURL
        let bURL = self.blobsURL
        
        saveQueue.async {
            ClipboardCrypto.saveHistory(history: [ClipboardItem](), fileURL: fURL)
            ClipboardCrypto.saveBlobs(blobs: [:], blobsURL: bURL)
        }
    }
    
    func getFullContent(for item: ClipboardItem) -> String { 
        let diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: blobsURL)
        return diskBlobs[item.id] ?? item.content 
    }
    
    func getAllBlobs() -> [UUID: String] {
        return ClipboardCrypto.loadBlobs(blobsURL: blobsURL)
    }
    
    func removeDuplicates() {
        let historySnapshot = self.history
        let fURL = self.fileURL
        let bURL = self.blobsURL
        
        processingQueue.async {[weak self] in
            guard let self = self else { return }
            var seenContent = Set<String>()
            var idsToRemove: Set<UUID> = []
            
            let diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: bURL)
            
            for item in historySnapshot {
                let identifier: String
                if item.type == .text {
                    identifier = diskBlobs[item.id] ?? item.content
                } else {
                    identifier = diskBlobs[item.id] ?? item.thumbnailData?.base64EncodedString() ?? UUID().uuidString
                }
                if seenContent.contains(identifier) { idsToRemove.insert(item.id) } else { seenContent.insert(identifier) }
            }
            if !idsToRemove.isEmpty {
                DispatchQueue.main.async {
                    self.history.removeAll { idsToRemove.contains($0.id) }
                    let newSnapshot = self.history
                    self.saveQueue.async {
                        var newDiskBlobs = diskBlobs
                        for id in idsToRemove { newDiskBlobs.removeValue(forKey: id) }
                        ClipboardCrypto.saveHistory(history: newSnapshot, fileURL: fURL)
                        ClipboardCrypto.saveBlobs(blobs: newDiskBlobs, blobsURL: bURL)
                    }
                }
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        // Move item to top
        if let idx = history.firstIndex(where: { $0.id == item.id }), idx > 0 {
            var movedItem = history.remove(at: idx)
            movedItem.timestamp = Date()
            history.insert(movedItem, at: 0)
            
            let hSnapshot = self.history
            let fURL = self.fileURL
            saveQueue.async {
                ClipboardCrypto.saveHistory(history: hSnapshot, fileURL: fURL)
            }
        }
        
        if item.type == .text {
            pb.setString(item.content, forType: .string)
            self.lastWrittenChangeCount = pb.changeCount
            
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                let diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: self.blobsURL)
                if let fullContent = diskBlobs[item.id] {
                    DispatchQueue.main.async {
                        if pb.string(forType: .string) == item.content {
                            pb.clearContents()
                            pb.setString(fullContent, forType: .string)
                            self.lastWrittenChangeCount = pb.changeCount
                        }
                    }
                }
            }
        } else {
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                let diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: self.blobsURL)
                if let base64 = diskBlobs[item.id], let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        pb.clearContents()
                        pb.writeObjects([image])
                        self.lastWrittenChangeCount = pb.changeCount
                    }
                }
            }
        }
    }
    
    func getStats() -> ClipboardStats {
        let historySize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let blobsSize = (try? FileManager.default.attributesOfItem(atPath: blobsURL.path)[.size] as? Int64) ?? 0
        var imgCount = 0, txtBlobCount = 0, imgBytes: Int64 = 0, txtBlobBytes: Int64 = 0
        
        let diskBlobs = ClipboardCrypto.loadBlobs(blobsURL: blobsURL)
        
        for item in history {
            if item.type == .image {
                imgCount += 1
                if let thumb = item.thumbnailData { imgBytes += Int64(thumb.count) }
                if let blob = diskBlobs[item.id] { imgBytes += Int64(blob.utf8.count) }
            } else {
                if let blob = diskBlobs[item.id] { txtBlobCount += 1; txtBlobBytes += Int64(blob.utf8.count) }
            }
        }
        return ClipboardStats(totalItems: history.count, imageCount: imgCount, textBlobCount: txtBlobCount, historyDiskSizeBytes: historySize, blobsDiskSizeBytes: blobsSize, imageContentSizeBytes: imgBytes, textBlobContentSizeBytes: txtBlobBytes)
    }
}